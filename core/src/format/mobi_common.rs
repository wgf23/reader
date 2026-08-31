//! MOBI/AZW3 共用解析内核（domain 层；ADR-REQ-002 决策1）。
//!
//! 职责（02-design.md §2.1）：
//! - `PdbBook`：PDB 容器薄封装——统一错误映射 + **记录偏移边界校验**（mobi crate 0.8.0 的
//!   `raw_records()` 对越界偏移做无界切片会 panic，截断文件必须先拦下，保证"任何输入不 panic"）；
//! - `MobiSection`：MOBI7 段结构（整文件或 AZW3 内嵌回退段），从记录内嵌 MOBI 头字段圈定
//!   内容/图片/索引记录区间（Gutenberg 文件 `first_content_record=0` 的怪癖用 `max(1)` 兼容）；
//! - `palmdoc_decompress`：自研 PalmDOC LZ77（mobi crate 的为 `pub(crate)` 不可外部调用，
//!   GBK 路径与 AZW3 回退段必须自解码）；回引用偏移非法 → `Err`，截断流宽松停止；
//! - `decode_text`：编码解码链（declared → 内容探测 → lossy），936→GB18030、950→Big5、
//!   1252→windows-1252（含"声明 CP1252 实为 GBK"的 CJK 探测兜底）、65001→UTF-8、
//!   未知→内容探测；GBK 解码先拼原始字节再整体解码，避免跨记录断字；
//! - `section_html` / `sanitize_html` / `split_chapters` / `first_heading` /
//!   `extract_images_from` / `parse_indx_section` / `authors_of` / `language_of` / `build_toc`。
//!
//! 约束（ddd-rules domain 层）：只依赖 `crate::error`、`crate::format` 内部类型与外部 crate
//! （mobi / encoding_rs / regex / quick-xml），禁止 `crate::store|api|library`。

use std::collections::HashMap;
use std::path::Path;

use encoding_rs::{GB18030, WINDOWS_1252};
use mobi::headers::{Compression, TextEncoding};
use mobi::Mobi;
use regex::Regex;

use super::{Chapter, Resource, TocEntry};
use crate::error::{Error, Result};

/// `<mbp:pagebreak>` 匹配（大小写/属性/自闭合容错；拆章主切分点）
static PAGEBREAK_RE: &str = r"(?i)<mbp:pagebreak[^>]*/?>";

/// h1-h3 开标签匹配（标题层级拆章回退）
static HEADING_RE: &str = r"(?i)<h[123][\s>]";

/// 标题开标签匹配（第一个 h1-h3/title；regex crate 不支持反向引用，闭合标签另行匹配）
static HEADING_OPEN_RE: &str = r"(?i)<(h[1-3]|title)\b[^>]*>";

/// 去除标签（标题清理用）
static TAG_RE: &str = r"<[^>]+>";

/// `<img src="...">` 匹配（与 convert 的资源重写正则同构）
static IMG_SRC_RE: &str = r#"(?i)(src\s*=\s*")([^"]+)(")"#;

/// 剥除除 pagebreak 外的 mbp: 命名空间标签
static MBP_TAG_RE: &str = r"(?i)</?mbp:[a-z0-9]+[^>]*>";

/// 剥除 font 标签（保留文本内容）
static FONT_TAG_RE: &str = r"(?i)</?font[^>]*>";

/// script/style 块（lenient 文本抽取时整体剥除）
static SCRIPT_RE: &str = r"(?is)<script\b[^>]*>.*?</script\s*>";
static STYLE_RE: &str = r"(?is)<style\b[^>]*>.*?</style\s*>";

/// 块级标签 → 换行（lenient 文本抽取）
static BLOCK_TAG_RE: &str = r"(?i)</?(?:p|div|br|h[1-6]|li|blockquote|tr|table|section|article|pre)\b[^>]*>";

/// 数字实体（lenient 文本抽取）
static NUM_ENTITY_RE: &str = r"&#(x?)([0-9a-fA-F]+);";

/// PDB 容器薄封装：错误映射 + 截断防 panic 边界校验 + 记录字节直读。
///
/// 重要实现事实（实测 mobi-0.8.0）：crate 的 `Mobi.content` 是"头部长度个 0 + 剩余文件字节"
/// 的拼接缓冲（reader.rs from_reader），而 PDB 记录偏移是绝对文件偏移 → 记录 0 头部（含
/// MOBI 头字段）落在 0 填充前缀内，`raw_records()` 返回的记录 0 内容前段是 0 污染；
/// 且 `raw_records()` 对越界偏移做无界切片会 panic。因此本封装**直接读文件字节**（`record_bytes`）
/// 提供记录内容，并在 `from_path` 校验全部记录偏移在文件范围内（截断 → Corrupt，不 panic）。
pub(crate) struct PdbBook {
    mobi: Mobi,
    file_bytes: Vec<u8>,
}

impl PdbBook {
    /// 打开并解析 PDB 容器（MOBI7 与 AZW3 共用；AZW3 的 KF8 头同样可解析，
    /// 原始 type 字段经 `mobi_type_u32` 读取，由 azw3.rs 判定）
    pub(crate) fn from_path(path: &Path) -> Result<PdbBook> {
        let file_bytes = std::fs::read(path).map_err(Error::Io)?;
        let mobi = Mobi::from_path(path)
            .map_err(|e| Error::Corrupt(format!("PDB/MOBI 容器解析失败: {e}")))?;
        // 截断防护：任何记录偏移越界 → 视为截断/损坏（不 panic）。
        for rec in &mobi.metadata.records.records {
            if (rec.offset as usize) > file_bytes.len() {
                return Err(Error::Corrupt(format!(
                    "记录偏移越界（文件可能被截断）：offset={} 文件内容长度={}",
                    rec.offset,
                    file_bytes.len()
                )));
            }
        }
        Ok(PdbBook { mobi, file_bytes })
    }

    pub(crate) fn mobi(&self) -> &Mobi {
        &self.mobi
    }

    /// 记录总数
    pub(crate) fn num_records(&self) -> usize {
        self.mobi.metadata.records.records.len()
    }

    /// 记录 i 的原始字节（按 PDB 记录表偏移切片；越界返回空，不 panic）。
    /// 记录内容 = [offset_i, offset_{i+1} - extra_bytes)，与 crate 的切片语义一致。
    pub(crate) fn record_bytes(&self, i: usize) -> &[u8] {
        let recs = &self.mobi.metadata.records.records;
        let Some(rec) = recs.get(i) else {
            return &[];
        };
        let start = rec.offset as usize;
        let end = match recs.get(i + 1) {
            Some(next) => (next.offset as usize).saturating_sub(self.extra_bytes()),
            None => self.file_bytes.len(),
        };
        if start > self.file_bytes.len() {
            return &[];
        }
        &self.file_bytes[start..end.min(self.file_bytes.len())]
    }

    /// PDB 记录表尾 extra 字段（MOBI 通常为 0；按位展开与 crate 一致）
    fn extra_bytes(&self) -> usize {
        let num = self.num_records();
        let off = 78usize + 8 * num;
        let field = u16_be_at(&self.file_bytes, off);
        (2 * (field & 0xFFFE).count_ones()) as usize
    }

    /// DRM 检测：PalmDOC encryption 字段 ≠ No，或 MOBI 头 DRM 偏移非 0xFFFFFFFF
    pub(crate) fn has_drm(&self) -> bool {
        self.mobi.encryption() != mobi::headers::Encryption::No
            || self.mobi.metadata.mobi.has_drm()
    }
}

/// 大端 u16 读取（越界返回 0）
fn u16_be_at(data: &[u8], off: usize) -> u16 {
    if off + 2 > data.len() {
        return 0;
    }
    u16::from_be_bytes([data[off], data[off + 1]])
}

/// MOBI7 段结构：整文件（k=0）或 AZW3 内嵌回退段（k>0，记录 k 含二次 MOBI 头）。
/// 记录下标相对 PDB 全局记录表；字段从记录 k 的内嵌 MOBI 头（record content 偏移 16 起）读取。
pub(crate) struct MobiSection {
    /// 内容记录区间 [content_start, content_end)
    pub(crate) content_start: usize,
    pub(crate) content_end: usize,
    /// 图片记录起始下标
    pub(crate) image_start: usize,
    /// 索引记录起始下标
    pub(crate) index_start: usize,
    /// 压缩方式（PalmDoc/No/Huff）
    pub(crate) compression: Compression,
    /// 文本编码声明
    pub(crate) encoding: TextEncoding,
    /// PalmDoc 单记录解压尺寸上限（record_size 字段；解压越界噪声需截断，
    /// 否则记录边界处会产生流内杂字节 → 中文解码 U+FFFD）
    pub(crate) record_size: usize,
}

impl MobiSection {
    /// 从记录 k 的内嵌 MOBI 头解析段结构（k=0 即 record 0 的常规 MOBI 头）。
    /// 记录内容经 `PdbBook::record_bytes` 直读文件字节（不受 crate 0 填充前缀影响）。
    pub(crate) fn from_embedded(book: &PdbBook, k: usize) -> Result<MobiSection> {
        let content = book.record_bytes(k);
        if content.len() < 232 + 16 {
            return Err(Error::Corrupt("MOBI 头不完整（文件损坏）".to_string()));
        }
        // 记录 content 布局：PalmDoc 头(16B) + MOBI 头（字段偏移同 mobih.rs 读取顺序；
        // first_index_record 位于 MOBI 头偏移 228，已对照真实语料核实）
        let fcr = u16::from_be_bytes([content[16 + 176], content[16 + 177]]) as usize;
        let fnbi = u32_be(content, 16 + 64) as usize;
        let fii = u32_be(content, 16 + 92) as usize;
        let fir = u32_be(content, 16 + 228) as usize;
        let comp = Compression::from(u16::from_be_bytes([content[0], content[1]]));
        let enc = TextEncoding::from(u32_be(content, 16 + 12));
        let record_size = u16::from_be_bytes([content[10], content[11]]) as usize;
        Ok(MobiSection {
            content_start: k + fcr.max(1),
            content_end: k + fnbi,
            image_start: k + fii,
            index_start: k + fir,
            compression: comp,
            encoding: enc,
            record_size,
        })
    }
}

/// 大端 u32 读取（越界返回 0，避免索引 panic；调用方再按需判 0）
fn u32_be(data: &[u8], off: usize) -> u32 {
    if off + 4 > data.len() {
        return 0;
    }
    u32::from_be_bytes([data[off], data[off + 1], data[off + 2], data[off + 3]])
}

/// MOBI 头原始 type 字段（248=KF8/AZW3；mobi crate 的 `MobiType` 把 248 折叠为
/// `Unknown`，需读原始 u32 区分，供 azw3.rs 的 KF8 判定）
pub(crate) fn mobi_type_u32(book: &PdbBook) -> u32 {
    u32_be(book.record_bytes(0), 24)
}

/// PalmDOC LZ77 解压（自研；规范见 docs/02 §3.3）。
///
/// 宽松语义与 mobi crate 一致（实现修正——crate 对 `offset > text_pos` 用取模兜底会破坏
/// 重叠拷贝，本实现直接停止）：真实文件（KindleGen 输出）在记录末尾常带
/// **offset==0 的结束标记**与越界回引用，一律停止解压返回已解压部分，
/// 不 Err 不 panic（截断/损坏文件由 `PdbBook::from_path` 的偏移校验先行拦截）。
pub(crate) fn palmdoc_decompress(data: &[u8]) -> Vec<u8> {
    palmdoc_loop(data)
}

/// 解压主循环：0x00/0x09..=0x7f 字面量、0x01..=0x08 复制后随 n 字节、
/// 0x80..=0xbf 回引用（与下一字节组成 (offset,length) 对）、0xc0..=0xff 空格+(c^0x80)。
fn palmdoc_loop(data: &[u8]) -> Vec<u8> {
    let mut out: Vec<u8> = Vec::with_capacity(data.len() * 3);
    let mut pos = 0usize;
    while pos < data.len() {
        let c = data[pos];
        pos += 1;
        if c < 0x80 {
            copy_literal(data, &mut pos, c, &mut out);
        } else if c < 0xc0 {
            if !copy_backref(data, &mut pos, c, &mut out) {
                break;
            }
        } else {
            out.push(b' ');
            out.push(c ^ 0x80);
        }
    }
    out
}

/// 字面量字节拷贝：0x00/0x09..=0x7f 直接输出，0x01..=0x08 复制后随 n 字节（截断则跳过）
fn copy_literal(data: &[u8], pos: &mut usize, c: u8, out: &mut Vec<u8>) {
    if c <= 0x08 {
        let n = c as usize;
        if *pos + n <= data.len() {
            out.extend_from_slice(&data[*pos..*pos + n]);
            *pos += n;
        }
    } else {
        out.push(c);
    }
}

/// 回引用拷贝：((hi<<8)|lo) & 0x3fff → offset=高 11 位、length=低 3 位 +3；
/// 逐字节拷贝（支持重叠，即 LZ77 的 RLE 语义）；返回 false 表示应停止解压
/// （offset==0 结束标记 / 越界回引用 / 截断）。
fn copy_backref(data: &[u8], pos: &mut usize, hi: u8, out: &mut Vec<u8>) -> bool {
    if *pos >= data.len() {
        return false;
    }
    let lo = data[*pos];
    *pos += 1;
    let pair = (((hi as u16) << 8) | lo as u16) & 0x3fff;
    let offset = (pair >> 3) as usize;
    let len = (pair & 0x07) as usize + 3;
    if offset == 0 || offset > out.len() {
        return false;
    }
    for _ in 0..len {
        let idx = out.len() - offset;
        let b = out[idx];
        out.push(b);
    }
    true
}

/// 声明编码编号（CP1252=1252 / UTF8=65001 / Unknown(n)）
fn declared_code(enc: TextEncoding) -> u32 {
    match enc {
        TextEncoding::CP1252 => 1252,
        TextEncoding::UTF8 => 65001,
        TextEncoding::Unknown(n) => n,
    }
}

/// 编码解码链：声明编码 → 内容探测 → lossy（02-design.md §2.1）。
/// 936→GB18030（兼容 GBK）、950→Big5、1252→windows-1252（实为 GBK 时 CJK 探测兜底）、
/// 65001→UTF-8（信任声明，lossy；整书字节流可能含个别非 UTF-8 字节，不可用内容探测
/// 反向误判为 GBK）、未知→内容探测（UTF-8 有效→UTF-8，否则按 GBK 处理中文）。
pub(crate) fn decode_text(bytes: &[u8], declared: TextEncoding) -> String {
    let code = declared_code(declared);
    if code == 936 {
        gb18030_decode(bytes)
    } else if code == 950 {
        big5_decode(bytes)
    } else if code == 1252 {
        decode_cp1252_or_gbk(bytes)
    } else {
        utf8_or_declared(bytes, code)
    }
}

/// 65001 信任声明 lossy UTF-8；未知声明 → 内容探测
fn utf8_or_declared(bytes: &[u8], code: u32) -> String {
    if code == 65001 {
        utf8_decode(bytes)
    } else {
        utf8_or_sniff(bytes)
    }
}

/// 声明 CP1252 但内容实为 GBK 的兼容（US-5）：cp1252 结果无 CJK 而 GBK 结果有 CJK → 用 GBK
fn decode_cp1252_or_gbk(bytes: &[u8]) -> String {
    let cp = cp1252_decode(bytes);
    if has_cjk(&cp) {
        return cp;
    }
    let gbk = gb18030_decode(bytes);
    if has_cjk(&gbk) && !has_fffd(&gbk) {
        gbk
    } else {
        cp
    }
}

/// 是否含替换符（GBK 探测的排除条件：真 GBK 解码不应产生替换符）
fn has_fffd(s: &str) -> bool {
    s.contains('\u{fffd}')
}

/// 未知声明或 UTF-8 声明：内容探测（UTF-8 有效 → UTF-8，否则按 GBK 处理）
fn utf8_or_sniff(bytes: &[u8]) -> String {
    if std::str::from_utf8(bytes).is_ok() {
        utf8_decode(bytes)
    } else {
        gb18030_decode(bytes)
    }
}

fn gb18030_decode(bytes: &[u8]) -> String {
    let (cow, _, _) = GB18030.decode(bytes);
    cow.into_owned()
}

fn big5_decode(bytes: &[u8]) -> String {
    let (cow, _, _) = encoding_rs::BIG5.decode(bytes);
    cow.into_owned()
}

fn cp1252_decode(bytes: &[u8]) -> String {
    let (cow, _, _) = WINDOWS_1252.decode(bytes);
    cow.into_owned()
}

fn utf8_decode(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

/// 是否含 CJK 汉字（用于"声明 CP1252 实为 GBK"的探测）
fn has_cjk(s: &str) -> bool {
    s.chars().any(|c| ('\u{4e00}'..='\u{9fff}').contains(&c))
}

/// 段 HTML：解压并解码段内容（PalmDoc/No 走自研解压 + decode_text；
/// Huff 走 crate 受限路径 `content_as_string_lossy`，编码仅 UTF8/CP1252，尽力而为）
pub(crate) fn section_html(book: &PdbBook, section: &MobiSection) -> Result<String> {
    if section.compression == Compression::Huff {
        return Ok(book.mobi().content_as_string_lossy());
    }
    let bytes = section_text_bytes(book, section)?;
    Ok(decode_text(&bytes, section.encoding))
}

/// 段内容原始字节：先解压逐记录并拼接，再整体解码（避免 GBK 字符跨记录断字）
fn section_text_bytes(book: &PdbBook, section: &MobiSection) -> Result<Vec<u8>> {
    let end = section.content_end.min(book.num_records());
    let mut out = Vec::new();
    let cap = section.record_size.max(1);
    for i in section.content_start..end {
        let content = book.record_bytes(i);
        if section.compression == Compression::PalmDoc {
            let mut bytes = palmdoc_decompress(content);
            bytes.truncate(cap);
            out.extend_from_slice(&bytes);
        } else {
            out.extend_from_slice(content);
        }
    }
    Ok(out)
}

/// 整书 HTML（02-design.md §2.1；mobi.rs 与 azw3.rs 共用）
pub(crate) fn whole_html(book: &PdbBook) -> Result<String> {
    let section = MobiSection::from_embedded(book, 0)?;
    section_html(book, &section)
}

/// HTML 预处理（ADR 决策4）：剥除除 pagebreak 外的 mbp: 命名空间标签、去 <font> 标签、
/// 补 DOCTYPE、把 `<img src="kindle:embed:NNNN?mime=...">` 重写为
/// `images/imageNNNN.ext`（与 Resource.source_path 完全一致 → canonicalize 重写必然命中）。
pub(crate) fn sanitize_html(html: &str, images: &[Resource]) -> String {
    let mut out = strip_mbp_keep_pagebreak(html);
    let re = Regex::new(FONT_TAG_RE).expect("FONT_TAG_RE 编译失败");
    out = re.replace_all(&out, "").into_owned();
    if !out.to_ascii_lowercase().contains("<!doctype") {
        out = format!("<!DOCTYPE html>\n{out}");
    }
    let map = build_img_map(images);
    rewrite_imgs(&out, &map)
}

/// 剥除 mbp: 命名空间标签，但保留 `<mbp:pagebreak...>`（供拆章使用）
fn strip_mbp_keep_pagebreak(html: &str) -> String {
    let re = Regex::new(MBP_TAG_RE).expect("MBP_TAG_RE 编译失败");
    re.replace_all(html, |caps: &regex::Captures| {
        let m = caps[0].to_ascii_lowercase();
        if m.contains("pagebreak") {
            caps[0].to_string()
        } else {
            String::new()
        }
    })
    .into_owned()
}

/// 图片映射：embed 十六进制序号（如 "0001"）→ 抽取图片的规范化路径
fn build_img_map(images: &[Resource]) -> HashMap<String, String> {
    images
        .iter()
        .enumerate()
        .map(|(i, r)| (format!("{:04X}", i), r.source_path.clone()))
        .collect()
}

/// 重写 img src：embed 引用 → 图片路径；非 embed 引用原样保留（canonicalize 后缀匹配兜底）
fn rewrite_imgs(html: &str, map: &HashMap<String, String>) -> String {
    let re = Regex::new(IMG_SRC_RE).expect("IMG_SRC_RE 编译失败");
    re.replace_all(html, |caps: &regex::Captures| {
        let url = &caps[2];
        let rew = embed_rewrite(url, map);
        match rew {
            Some(path) => format!("{}{}{}", &caps[1], path, &caps[3]),
            None => caps[0].to_string(),
        }
    })
    .into_owned()
}

/// kindle:embed:NNNN?mime=... → 图片路径（NNNN 按十六进制解析；越界返回 None 原样保留）
fn embed_rewrite(url: &str, map: &HashMap<String, String>) -> Option<String> {
    let rest = url.strip_prefix("kindle:embed:")?;
    let digits = rest.split('?').next()?;
    let value = u32::from_str_radix(digits, 16).ok()?;
    map.get(&format!("{:04X}", value)).cloned()
}

/// 拆章：`<mbp:pagebreak>` 主切分（大小写/属性容错）；切出 < 2 段时回退 h1-h3 标题切分；
/// 仍 < 2 段 → 整书单章。返回（各段 HTML，各段在整书字符串中的起始字节偏移）；
/// 偏移供 INDX 目录位置映射（chapter_index_at）。
pub(crate) fn split_chapters(html: &str) -> (Vec<String>, Vec<usize>) {
    let pagebreak = Regex::new(PAGEBREAK_RE).expect("PAGEBREAK_RE 编译失败");
    let heading = Regex::new(HEADING_RE).expect("HEADING_RE 编译失败");
    // pagebreak 标记本身被消费（不进任何段）；标题开标签属于新段（保留在段内，
    // 否则 `<h2` 前缀丢失会使 quick_xml 把标签属性当正文文本）
    let mut splits = split_on_pattern(html, &pagebreak, true);
    if splits.len() < 2 {
        splits = split_on_pattern(html, &heading, false);
    }
    if splits.len() < 2 {
        return (vec![html.to_string()], vec![0]);
    }
    let parts = splits.iter().map(|(s, _)| s.clone()).collect();
    let offsets = splits.iter().map(|(_, o)| *o).collect();
    (parts, offsets)
}

/// 按正则切分：每个匹配点作为新段的开始。
/// `consume=true`：匹配的标记本身被消费（如 `<mbp:pagebreak/>`，不进任何段）；
/// `consume=false`：匹配保留在新段开头（如 `<h2` 标题开标签）。
fn split_on_pattern(html: &str, re: &Regex, consume: bool) -> Vec<(String, usize)> {
    let mut out = Vec::new();
    let mut prev = 0usize;
    for m in re.find_iter(html) {
        if m.start() > prev {
            out.push((html[prev..m.start()].to_string(), prev));
        }
        prev = if consume { m.end() } else { m.start() };
    }
    if prev < html.len() {
        out.push((html[prev..].to_string(), prev));
    }
    out
}

/// 章节标题：段内第一个 h1-h3/title（与 epub.rs first_heading 语义一致，此处独立实现）
pub(crate) fn first_heading(html: &str) -> Option<String> {
    let open = Regex::new(HEADING_OPEN_RE).expect("HEADING_OPEN_RE 编译失败");
    let m = open.find(html)?;
    let tag = tag_name_of(m.as_str());
    let close = Regex::new(&format!(r"(?i)</{tag}\s*>")).ok()?;
    let rest = &html[m.end()..];
    let end = close.find(rest).map(|mm| mm.start()).unwrap_or(rest.len());
    let text = strip_tags(&rest[..end]).trim().to_string();
    if text.is_empty() {
        None
    } else {
        Some(text)
    }
}

/// 从开标签字符串提取标签名（如 "<h2>" → "h2"）
fn tag_name_of(open: &str) -> String {
    open[1..]
        .chars()
        .take_while(|c| c.is_ascii_alphanumeric())
        .collect::<String>()
        .to_ascii_lowercase()
}

/// 去除标题内的内联标签
fn strip_tags(s: &str) -> String {
    let re = Regex::new(TAG_RE).expect("TAG_RE 编译失败");
    re.replace_all(s, "").into_owned()
}

/// 图片记录 → Resource：段内图片记录按序编号 `images/imageNNNN.ext`；
/// media_type 按魔数嗅探（FFD8FF→image/jpeg、89504E47→image/png、GIF8→image/gif、BM→image/bmp）。
pub(crate) fn extract_images_from(book: &PdbBook, section: &MobiSection) -> Vec<Resource> {
    let mut out = Vec::new();
    for i in section.image_start..book.num_records() {
        let content = book.record_bytes(i);
        if let Some(ext) = sniff_ext(content) {
            out.push(Resource {
                source_path: format!("images/image{:04}.{}", out.len() + 1, ext),
                media_type: format!("image/{ext}"),
                data: content.to_vec(),
            });
        }
    }
    out
}

/// 图片魔数嗅探：JPEG/PNG/GIF/BMP → 扩展名；其余 → None
fn sniff_ext(data: &[u8]) -> Option<&'static str> {
    if data.starts_with(b"\xff\xd8\xff") {
        Some("jpg")
    } else if data.starts_with(b"\x89PNG") {
        Some("png")
    } else if data.starts_with(b"GIF8") {
        Some("gif")
    } else {
        bmp_ext(data)
    }
}

/// BMP 魔数（拆出以控制单函数复杂度）
fn bmp_ext(data: &[u8]) -> Option<&'static str> {
    if data.starts_with(b"BM") {
        Some("bmp")
    } else {
        None
    }
}

/// INDX 目录解析（段内）：在 [index_start, content_end) 区间定位 INDX 记录，
/// 按经典 TAGX 格式解析条目 (label, 内容流偏移 pos)；失败/缺失/标签全数字 → None
/// （调用方回退章节标题生成 TOC；Gutenberg 文件的 KindleGen "IDXT" 变体解析失败走回退）。
pub(crate) fn parse_indx_section(
    book: &PdbBook,
    section: &MobiSection,
) -> Option<Vec<(String, u32)>> {
    // 索引记录区 = [first_index_record, first_image_index)（真实语料实测：
    // 内容记录 → INDX 记录 → 图片记录，first_index_record 可 ≥ first_non_book_index）
    let start = section.index_start;
    let end = section.image_start;
    if start > end {
        return None;
    }
    for i in start..end {
        let entries = indx_entries_of(book.record_bytes(i));
        if entries.is_some() {
            return entries;
        }
    }
    None
}

/// 单条 INDX 记录 → 条目；非 INDX 记录 / 解析失败 / 空 / 标签全数字 → None
fn indx_entries_of(content: &[u8]) -> Option<Vec<(String, u32)>> {
    if !content.starts_with(b"INDX") {
        return None;
    }
    let entries = parse_indx_record(content)?;
    if entries.is_empty() {
        return None;
    }
    let all_numeric = entries.iter().all(|(t, _)| t.chars().all(|c| c.is_ascii_digit()));
    if all_numeric {
        return None; // KindleGen 位置索引（标签即数字位置串）→ 无意义，回退章节标题
    }
    Some(entries)
}

/// 经典 TAGX 格式 INDX 记录解析（KindleUnpack/libmobi 同款布局）：
/// 头(0x40 控制字节计数+控制数据) → TAGX（标签表）→ 条目区 [index_start..index_end)。
/// 条目：2B id + 控制字节 + 可选 text_offset/text_length/entry_properties + 标签数据；
/// 位置取 tag==1 且 size==4 的 u32（内容流字节偏移），标签取其余首个文本型 tag 数据。
fn parse_indx_record(content: &[u8]) -> Option<Vec<(String, u32)>> {
    let count = indx_count(content)?;
    let (index_start, index_end) = entry_bounds(content)?;
    let tags = tagx_table(content)?;
    let mut entries = Vec::with_capacity(count as usize);
    let mut pos = index_start;
    for _ in 0..count {
        if pos >= index_end {
            return None;
        }
        entries.push(parse_indx_entry(content, &mut pos, &tags)?);
    }
    Some(entries)
}

/// 条目数与记录最小长度校验
fn indx_count(content: &[u8]) -> Option<u32> {
    if content.len() < 0x44 {
        return None;
    }
    let count = u32_be(content, 12);
    if count == 0 {
        return None;
    }
    if count > 10_000 {
        return None;
    }
    Some(count)
}

/// 条目区边界校验
fn entry_bounds(content: &[u8]) -> Option<(usize, usize)> {
    let start = u32_be(content, 40) as usize;
    let end = u32_be(content, 44) as usize;
    if start >= content.len() {
        return None;
    }
    if end > content.len() {
        return None;
    }
    if start > end {
        return None;
    }
    Some((start, end))
}

/// TAGX 标签表：控制字节计数(0x40) → TAGX 头 → (tag, size) 对
fn tagx_table(content: &[u8]) -> Option<Vec<(u8, usize)>> {
    let ctl_count = u16::from_be_bytes([content[64], content[65]]) as usize;
    let tagx = 66usize + ctl_count;
    if tagx + 12 > content.len() {
        return None;
    }
    let tagx_len = u32_be(content, tagx + 4) as usize;
    let tagx_data_len = u16::from_be_bytes([content[tagx + 10], content[tagx + 11]]) as usize;
    let table_end = tagx + 12 + tagx_len.saturating_sub(12 + tagx_data_len);
    if table_end > content.len() {
        return None;
    }
    let mut tags = Vec::new();
    let mut p = tagx + 12;
    while p + 2 <= table_end {
        tags.push((content[p], content[p + 1] as usize));
        p += 2;
    }
    Some(tags)
}

/// 单条目解析：2B id + 控制字节 + 可选字段 + 标签数据 → (label, pos)
fn parse_indx_entry(
    content: &[u8],
    pos: &mut usize,
    tags: &[(u8, usize)],
) -> Option<(String, u32)> {
    let control = entry_control(content, pos)?;
    skip_optional(content, pos, control)?;
    let mut label = String::new();
    let mut position = None;
    for (i, (tag, size)) in tags.iter().enumerate() {
        let bit = 0x10 >> i;
        if control & bit != 0 {
            read_tag_data(content, pos, *tag, *size, &mut label, &mut position)?;
        }
    }
    finalize_entry(label, position)
}

/// 读取条目头：2B id + 1B 控制字节
fn entry_control(content: &[u8], pos: &mut usize) -> Option<u8> {
    if *pos + 3 > content.len() {
        return None;
    }
    *pos += 2;
    let c = content[*pos];
    *pos += 1;
    Some(c)
}

/// 跳过可选字段（text_offset/text_length/entry_properties，各 2B，由控制字节位决定）
fn skip_optional(content: &[u8], pos: &mut usize, control: u8) -> Option<()> {
    let delta = optional_delta(control);
    let next = pos.checked_add(delta)?;
    if next > content.len() {
        return None;
    }
    *pos = next;
    Some(())
}

fn optional_delta(control: u8) -> usize {
    let mut d = 0usize;
    if control & 0x80 != 0 {
        d += 2;
    }
    if control & 0x40 != 0 {
        d += 2;
    }
    if control & 0x20 != 0 {
        d += 2;
    }
    d
}

/// 读取一个 tag 数据：tag==1 && size==4 → 位置；其余首个文本型数据 → 标签
fn read_tag_data(
    content: &[u8],
    pos: &mut usize,
    tag: u8,
    size: usize,
    label: &mut String,
    position: &mut Option<u32>,
) -> Option<()> {
    if *pos + size > content.len() {
        return None;
    }
    let data = &content[*pos..*pos + size];
    *pos += size;
    if is_position_tag(tag, size) {
        *position = Some(u32_be(data, 0));
    } else {
        push_label(data, label);
    }
    Some(())
}

/// 位置标签判定：tag==1 且 size==4 → 内容流字节偏移
fn is_position_tag(tag: u8, size: usize) -> bool {
    tag == 1 && size == 4
}

/// 标签文本收集（首个非空文本型 tag 数据）
fn push_label(data: &[u8], label: &mut String) {
    if label.is_empty() && !data.is_empty() {
        label.push_str(&text_until_nul(data));
    }
}

/// 取标签字节文本（截断到首个 NUL；定长标签槽的尾随填充不计入）
fn text_until_nul(data: &[u8]) -> String {
    let end = data.iter().position(|&b| b == 0).unwrap_or(data.len());
    String::from_utf8_lossy(&data[..end]).into_owned()
}

/// 条目收尾：位置缺失或标签为空 → None
fn finalize_entry(label: String, position: Option<u32>) -> Option<(String, u32)> {
    let pos = position?;
    if label.trim().is_empty() {
        return None;
    }
    Some((label.trim().to_string(), pos))
}

/// 目录组装：INDX 条目按 pos 映射到章节 → TocEntry；
/// INDX 缺失/映射失败 → 章节标题回退（depth=0，与 epub.rs 目录扁平化一致）。
pub(crate) fn build_toc(
    chapters: &[Chapter],
    offsets: &[usize],
    indx: Option<&[(String, u32)]>,
) -> Vec<TocEntry> {
    let mapped = indx.map(|entries| map_toc_entries(chapters, offsets, entries));
    match mapped {
        Some(t) if !t.is_empty() => t,
        _ => fallback_toc(chapters),
    }
}

/// INDX 条目 → TocEntry（pos 落在 [offsets[i], offsets[i+1]) → 章节 i）
fn map_toc_entries(
    chapters: &[Chapter],
    offsets: &[usize],
    entries: &[(String, u32)],
) -> Vec<TocEntry> {
    let mut toc = Vec::with_capacity(entries.len());
    for (title, pos) in entries {
        if let Some(idx) = chapter_index_at(offsets, *pos) {
            toc.push(TocEntry {
                title: title.clone(),
                href: chapters[idx].href.clone(),
                depth: 0,
            });
        }
    }
    toc
}

/// 章节标题回退目录
fn fallback_toc(chapters: &[Chapter]) -> Vec<TocEntry> {
    chapters
        .iter()
        .map(|c| TocEntry {
            title: c.title.clone(),
            href: c.href.clone(),
            depth: 0,
        })
        .collect()
}

/// INDX pos（内容流字节偏移）→ 章节索引（线性映射）
fn chapter_index_at(offsets: &[usize], pos: u32) -> Option<usize> {
    let pos = pos as usize;
    if offsets.is_empty() {
        return None;
    }
    if pos < offsets[0] {
        return Some(0);
    }
    offsets.iter().rposition(|&o| o <= pos)
}

/// EXTH 524 语言（小写）→ 兜底 MOBI header language_code 映射
pub(crate) fn language_of(book: &PdbBook) -> Option<String> {
    let exth = exth_language(book);
    match exth {
        Some(l) if !l.is_empty() => Some(l),
        _ => header_language(book),
    }
}

fn exth_language(book: &PdbBook) -> Option<String> {
    let recs = book.mobi().metadata.exth_record_at(524)?;
    let first = recs.first()?;
    let lang = String::from_utf8_lossy(first).trim().to_ascii_lowercase();
    if lang.is_empty() {
        None
    } else {
        Some(lang)
    }
}

/// MOBI header language_code 映射（English→en、Chinese→zh，其余 None）
fn header_language(book: &PdbBook) -> Option<String> {
    match book.mobi().language() {
        mobi::headers::Language::English => Some("en".to_string()),
        mobi::headers::Language::Chinese => Some("zh".to_string()),
        _ => None,
    }
}

/// EXTH 100 作者（可分号分隔多作者）→ Vec
pub(crate) fn authors_of(book: &PdbBook) -> Vec<String> {
    let raw = book.mobi().author().unwrap_or_default();
    split_authors(&raw)
}

fn split_authors(raw: &str) -> Vec<String> {
    raw.split(';')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

/// 宽松 HTML→纯文本（MOBI 专用）。
///
/// 为什么不用 `epub::html_to_text`：其内部 quick_xml 对"错配闭合标签"（如拆章切断
/// `<header>...</header>` 嵌套）会报错并中断，导致章节文本被截断（真实语料实测）。
/// 本实现用正则：剥 script/style → 块级标签转换行 → 去标签 → 实体解码 → 压缩空行。
/// 行为与 epub 版近似（段落/标题/换行转 \n、去标签），供 MOBI/AZW3 章节文本使用。
pub(crate) fn html_to_text_lenient(html: &str) -> String {
    let script = Regex::new(SCRIPT_RE).expect("SCRIPT_RE 编译失败");
    let style = Regex::new(STYLE_RE).expect("STYLE_RE 编译失败");
    let block = Regex::new(BLOCK_TAG_RE).expect("BLOCK_TAG_RE 编译失败");
    let no_scripts = style.replace_all(&script.replace_all(html, ""), "").into_owned();
    let with_breaks = block.replace_all(&no_scripts, "\n").into_owned();
    let no_tags = Regex::new(TAG_RE).expect("TAG_RE 编译失败");
    let text = no_tags.replace_all(&with_breaks, "").into_owned();
    collapse_lines(&decode_entities(&text))
}

/// 常见命名实体 + 数字实体解码（数值实体外保留原样）
fn decode_entities(s: &str) -> String {
    let named = s
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&nbsp;", " ");
    let re = Regex::new(NUM_ENTITY_RE).expect("NUM_ENTITY_RE 编译失败");
    re.replace_all(&named, |caps: &regex::Captures| {
        let hex = caps[1].eq_ignore_ascii_case("x");
        let body = &caps[2];
        let code = u32::from_str_radix(body, if hex { 16 } else { 10 }).unwrap_or(0);
        char::from_u32(code).map(|c| c.to_string()).unwrap_or_default()
    })
    .into_owned()
}

/// 压缩多余空行（与 epub::html_to_text 尾部逻辑语义一致）
fn collapse_lines(s: &str) -> String {
    let mut result = String::new();
    let mut prev_blank = true;
    for line in s.split('\n') {
        push_line(&mut result, line.trim(), &mut prev_blank);
    }
    result.trim().to_string()
}

/// 单行折叠：空行压缩为单个换行，非空行拼接
fn push_line(result: &mut String, line: &str, prev_blank: &mut bool) {
    if line.is_empty() {
        if !*prev_blank {
            result.push('\n');
        }
        *prev_blank = true;
    } else {
        if !result.is_empty() {
            result.push('\n');
        }
        result.push_str(line);
        *prev_blank = false;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ---------- PalmDOC ----------

    #[test]
    fn palmdoc_literal_stream_roundtrip() {
        let data = b"hello world, plain ascii text";
        let out = palmdoc_decompress(data);
        assert_eq!(out, data);
    }

    #[test]
    fn palmdoc_backref_copies() {
        // "abc" + (offset=3, length=3) → "abcabc"
        let stream = [b'a', b'b', b'c', 0x80, 0x18];
        let out = palmdoc_decompress(&stream);
        assert_eq!(out, b"abcabc");
    }

    #[test]
    fn palmdoc_overlap_rle() {
        // "A" + (offset=1, length=8) → 9 个 A（重叠拷贝 = LZ77 RLE）
        let stream = [b'A', 0x80, 0x0d];
        let out = palmdoc_decompress(&stream);
        assert_eq!(out, b"AAAAAAAAA");
    }

    #[test]
    fn palmdoc_space_xor_encoding() {
        // 0xc0..=0xff：空格 + (c ^ 0x80)
        let stream = [0xc1, 0xd0];
        let out = palmdoc_decompress(&stream);
        assert_eq!(out, b" A P");
    }

    #[test]
    fn palmdoc_c0_boundary_is_space_encoding() {
        // 边界：0xc0 属于 0xc0..=0xff 区间（空格编码），不属于 0x80..=0xbf 回引用区间
        let stream = [0xc0];
        let out = palmdoc_decompress(&stream);
        assert_eq!(out, b" @");
    }

    #[test]
    fn palmdoc_invalid_backref_stops_leniently() {
        // offset=0（KindleGen 结束标记）→ 停止，返回已解压部分
        let s = [b'x', 0x80, 0x00];
        assert_eq!(palmdoc_decompress(&s), b"x");
        // offset 超出已解压长度 → 停止，不 Err 不 panic
        let s = [b'x', 0x80, 0x50];
        assert_eq!(palmdoc_decompress(&s), b"x");
    }

    #[test]
    fn palmdoc_truncated_stream_lenient() {
        // 0x03 声明 3 字面量但只剩 2 字节 → 跳过该次拷贝（宽松），后续仍继续 → b"ab"
        let s = [0x03, b'a', b'b'];
        let out = palmdoc_decompress(&s);
        assert_eq!(out, b"ab");
    }

    // ---------- 大端读取辅助（边界守卫） ----------

    #[test]
    fn u16_be_at_reads_and_bounds() {
        assert_eq!(u16_be_at(&[0x12, 0x34], 0), 0x1234);
        // 越界（off+2 > len）→ 0；若守卫被变异（`+`→`-`/`*`、`>`→`==`）会越界读 → panic
        assert_eq!(u16_be_at(&[0x12, 0x34], 1), 0);
        assert_eq!(u16_be_at(&[0x12], 0), 0);
        assert_eq!(u16_be_at(&[], 0), 0);
    }

    #[test]
    fn u32_be_reads_be_bytes_and_bounds() {
        // 高位字节非 0 → 校验大端顺序正确（变异 `off+1`→`off` 会改变读值）
        assert_eq!(u32_be(&[1, 2, 3, 4], 0), 0x0102_0304);
        assert_eq!(u32_be(&[0, 0, 0, 5], 0), 5);
        assert_eq!(u32_be(&[1, 2, 3], 0), 0); // 越界 → 0
        assert_eq!(u32_be(&[], 0), 0);
    }

    // ---------- 编码解码链 ----------

    #[test]
    fn decode_utf8_declared() {
        let s = decode_text("你好世界".as_bytes(), TextEncoding::UTF8);
        assert_eq!(s, "你好世界");
        assert!(!s.contains('\u{fffd}'));
    }

    #[test]
    fn decode_gbk_936() {
        let (gbk, _, _) = GB18030.encode("红楼梦第一回");
        let s = decode_text(&gbk, TextEncoding::Unknown(936));
        assert_eq!(s, "红楼梦第一回");
        assert!(!s.contains('\u{fffd}'));
    }

    #[test]
    fn decode_unknown_declaration_sniffs_gbk() {
        let (gbk, _, _) = GB18030.encode("中文内容测试");
        let s = decode_text(&gbk, TextEncoding::Unknown(0));
        assert_eq!(s, "中文内容测试");
    }

    #[test]
    fn decode_unknown_declaration_valid_utf8_uses_utf8() {
        // 未知声明 + 内容本身是合法 UTF-8 → 按 UTF-8 解码（不得误判为 GBK）
        let s = decode_text("hello 你好 world".as_bytes(), TextEncoding::Unknown(0));
        assert!(s.contains("hello 你好 world"), "实际: {s}");
        assert!(!s.contains('\u{fffd}'));
    }

    #[test]
    fn decode_declared_cp1252_but_actual_gbk() {
        // US-5：声明 CP1252 但实为 GBK → 应正确解码中文且无替换符
        let (gbk, _, _) = GB18030.encode("红楼梦第一章内容");
        let s = decode_text(&gbk, TextEncoding::CP1252);
        assert!(s.contains("红楼梦"), "实际输出: {s}");
        assert!(!s.contains('\u{fffd}'));
    }

    #[test]
    fn decode_cp1252_plain_latin() {
        let s = decode_text(b"caf\xe9 \x93quoted\x94", TextEncoding::CP1252);
        assert!(s.contains("caf"));
        assert!(!s.contains('\u{fffd}'));
    }

    #[test]
    fn decode_big5_950() {
        let (big5, _, _) = encoding_rs::BIG5.encode("紅樓夢");
        let s = decode_text(&big5, TextEncoding::Unknown(950));
        assert!(s.contains('紅') || s.contains('樓'));
        assert!(!s.contains('\u{fffd}'));
    }

    // ---------- sanitize ----------

    #[test]
    fn sanitize_strips_mbp_and_font_adds_doctype() {
        let html = r#"<html><body><font size="2">正文</font><mbp:section><p>段落</p></mbp:section></body></html>"#;
        let out = sanitize_html(html, &[]);
        assert!(!out.contains("font"));
        assert!(!out.contains("mbp:"));
        assert!(out.starts_with("<!DOCTYPE html>"));
        assert!(out.contains("段落"));
    }

    #[test]
    fn sanitize_keeps_pagebreak_marker() {
        // pagebreak 供拆章使用，sanitize 必须保留
        let html = r#"<p>甲</p><mbp:pagebreak/><p>乙</p><mbp:pagebreak /></p>"#;
        let out = sanitize_html(html, &[]);
        assert!(out.contains("<mbp:pagebreak"));
        assert!(!out.contains("mbp:section"));
    }

    #[test]
    fn sanitize_rewrites_embed_img_src() {
        let imgs = vec![Resource {
            source_path: "images/image0001.jpg".to_string(),
            media_type: "image/jpeg".to_string(),
            data: Vec::new(),
        }];
        let html = r#"<p><img src="kindle:embed:0000?mime=image/jpeg"/></p>"#;
        let out = sanitize_html(html, &imgs);
        assert!(out.contains(r#"src="images/image0001.jpg""#), "实际: {out}");
    }

    #[test]
    fn sanitize_keeps_unknown_img_src() {
        let html = r#"<img src="kindle:flow:0001?mime=text/css"/>"#;
        let out = sanitize_html(html, &[]);
        assert!(out.contains("kindle:flow"));
    }

    #[test]
    fn sanitize_keeps_existing_doctype() {
        // 输入已含 DOCTYPE → 不重复前置
        let html = "<!DOCTYPE html>\n<html><body><p>正文</p></body></html>";
        let out = sanitize_html(html, &[]);
        assert!(out.starts_with("<!DOCTYPE html>"));
        assert_eq!(out.matches("<!DOCTYPE").count(), 1, "不应重复 DOCTYPE: {out}");
    }

    // ---------- 拆章 ----------

    #[test]
    fn split_by_pagebreak_variants() {
        let html = "<p>A</p><mbp:pagebreak/><p>B</p><MBP:PAGEBREAK><p>C</p>";
        let (parts, offsets) = split_chapters(html);
        assert_eq!(parts.len(), 3);
        assert!(parts[0].contains("A"));
        assert!(parts[1].contains("B"));
        assert!(parts[2].contains("C"));
        assert!(!parts.iter().any(|p| p.contains("pagebreak")));
        assert_eq!(offsets[0], 0);
        assert!(offsets[1] > offsets[0]);
        assert!(offsets[2] > offsets[1]);
    }

    #[test]
    fn split_falls_back_to_headings() {
        let html = "<html><body><h1>第一章</h1><p>内容一</p><h2>第二章</h2><p>内容二</p></body></html>";
        let (parts, _) = split_chapters(html);
        // 标题开标签保留在段内；front matter（<html><body>）为独立首段
        assert_eq!(parts.len(), 3);
        assert!(parts[0].contains("<body>"));
        assert!(parts[1].contains("<h1>第一章</h1>"));
        assert!(parts[2].contains("<h2>第二章</h2>"));
    }

    #[test]
    fn split_single_chapter_when_no_markers() {
        let html = "<html><body><p>只有一段</p></body></html>";
        let (parts, _) = split_chapters(html);
        assert_eq!(parts.len(), 1);
    }

    #[test]
    fn split_consecutive_pagebreaks_and_trailing_marker() {
        // 连续 pagebreak（无间隔内容）不产生空段；内容以 pagebreak 结尾不产生尾段
        let html = "<p>A</p><mbp:pagebreak/><mbp:pagebreak/><p>B</p><mbp:pagebreak/>";
        let (parts, _) = split_chapters(html);
        assert_eq!(parts.len(), 2, "应只有 A/B 两段: {parts:?}");
        assert!(parts[0].contains("A"));
        assert!(parts[1].contains("B"));
    }

    // ---------- 标题 ----------

    #[test]
    fn first_heading_inline_tags() {
        let html = r#"<h1><b>第一回</b> 甄士隱</h1><p>…</p>"#;
        assert_eq!(first_heading(html).as_deref(), Some("第一回 甄士隱"));
    }

    #[test]
    fn first_heading_none_when_absent() {
        assert_eq!(first_heading("<p>没有标题</p>"), None);
    }

    // ---------- 图片嗅探 ----------

    #[test]
    fn sniff_image_magic_four_kinds() {
        assert_eq!(sniff_ext(b"\xff\xd8\xff\xe0"), Some("jpg"));
        assert_eq!(sniff_ext(b"\x89PNG\r\n\x1a\n"), Some("png"));
        assert_eq!(sniff_ext(b"GIF89a..."), Some("gif"));
        assert_eq!(sniff_ext(b"BM..."), Some("bmp"));
        assert_eq!(sniff_ext(b"not image"), None);
    }

    // ---------- INDX（经典 TAGX 格式）----------

    /// 构造经典格式 INDX 记录（2 条目；tags=[(1,4) 位置, (0,8) 标签]）
    fn classic_indx_record(entries: &[(&str, u32)]) -> Vec<u8> {
        let tagx_len = 12 + 4; // 头 + 2 对 (tag,size)
        let header_len = 0xC0usize;
        let index_start = 66usize + tagx_len;
        let entry_size = 2 + 1 + 4 + 8;
        let index_end = index_start + entries.len() * entry_size;
        let mut content = vec![0u8; index_end];
        content[0..4].copy_from_slice(b"INDX");
        content[4..8].copy_from_slice(&(header_len as u32).to_be_bytes());
        content[8..12].copy_from_slice(&1u32.to_be_bytes()); // type
        content[12..16].copy_from_slice(&(entries.len() as u32).to_be_bytes()); // count
        content[40..44].copy_from_slice(&(index_start as u32).to_be_bytes());
        content[44..48].copy_from_slice(&(index_end as u32).to_be_bytes());
        // TAGX at 66（ctl_count=0）
        content[66..70].copy_from_slice(b"TAGX");
        content[70..74].copy_from_slice(&(tagx_len as u32).to_be_bytes());
        content[74..76].copy_from_slice(&0u16.to_be_bytes()); // ctl
        content[76..78].copy_from_slice(&0u16.to_be_bytes()); // data_len
        content[78..80].copy_from_slice(&[1, 4]); // tag 1 size 4（位置）
        content[80..82].copy_from_slice(&[0, 8]); // tag 0 size 8（标签）
        // 条目
        let mut p = index_start;
        for (i, (label, pos)) in entries.iter().enumerate() {
            content[p..p + 2].copy_from_slice(&((i + 1) as u16).to_be_bytes());
            content[p + 2] = 0x18; // tag0(0x10) + tag1(0x08) 位
            content[p + 3..p + 7].copy_from_slice(&pos.to_be_bytes());
            let lb = label.as_bytes();
            content[p + 7..p + 7 + lb.len().min(8)].copy_from_slice(&lb[..lb.len().min(8)]);
            p += entry_size;
        }
        content
    }

    #[test]
    fn parse_classic_indx_record() {
        let content = classic_indx_record(&[("CH1", 100), ("CH2", 200)]);
        let entries = parse_indx_record(&content).expect("应解析成功");
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0], ("CH1".to_string(), 100));
        assert_eq!(entries[1], ("CH2".to_string(), 200));
    }

    #[test]
    fn parse_indx_rejects_numeric_labels() {
        // KindleGen 位置索引：标签即数字位置串 → 判定无意义
        let content = classic_indx_record(&[("0000000123", 100), ("0000000456", 200)]);
        assert!(indx_entries_of(&content).is_none());
    }

    #[test]
    fn parse_indx_rejects_garbage_record() {
        let content = b"NOTINDXxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
        assert!(indx_entries_of(content).is_none());
    }

    #[test]
    fn parse_indx_rejects_truncated_header() {
        let content = vec![0u8; 30];
        assert!(indx_entries_of(&content).is_none());
    }

    // ---------- TOC 组装 ----------

    #[test]
    fn build_toc_maps_indx_positions_to_chapters() {
        let chapters = vec![
            Chapter { title: "封面".into(), href: "chapter_0001.xhtml".into(), html: String::new(), text: String::new() },
            Chapter { title: "第一章".into(), href: "chapter_0002.xhtml".into(), html: String::new(), text: String::new() },
            Chapter { title: "第二章".into(), href: "chapter_0003.xhtml".into(), html: String::new(), text: String::new() },
        ];
        let offsets = vec![0usize, 100, 300];
        let indx = vec![("第一章".to_string(), 150), ("第二章".to_string(), 400)];
        let toc = build_toc(&chapters, &offsets, Some(&indx));
        assert_eq!(toc.len(), 2);
        assert_eq!(toc[0].title, "第一章");
        assert_eq!(toc[0].href, "chapter_0002.xhtml");
        assert_eq!(toc[1].href, "chapter_0003.xhtml");
    }

    #[test]
    fn build_toc_maps_indx_positions_linearly() {
        // INDX pos 线性映射：pos 落在最后一章区间之后 → 映射到最后一章（不跳过）
        let chapters = vec![
            Chapter { title: "第一章".into(), href: "chapter_0001.xhtml".into(), html: String::new(), text: String::new() },
            Chapter { title: "第二章".into(), href: "chapter_0002.xhtml".into(), html: String::new(), text: String::new() },
        ];
        let offsets = vec![0usize, 100];
        let indx = vec![("第一章".to_string(), 50), ("越界条目".to_string(), 9999)];
        let toc = build_toc(&chapters, &offsets, Some(&indx));
        assert_eq!(toc.len(), 2);
        assert_eq!(toc[0].href, "chapter_0001.xhtml");
        assert_eq!(toc[1].href, "chapter_0002.xhtml", "9999 应线性映射到最后一章");
    }

    #[test]
    fn chapter_index_at_front_matter() {
        // pos 落在第一个偏移之前（front matter）→ 章节 0
        assert_eq!(chapter_index_at(&[100, 300], 50), Some(0));
        // 空偏移表 → None
        assert_eq!(chapter_index_at(&[], 50), None);
    }

    // ---------- lenient 文本抽取 ----------

    #[test]
    fn lenient_text_paragraphs_and_entities() {
        let html = r#"<html><body><h1>第一章</h1><p>你好，&amp;世界 &lt;OK&gt; &#20320;&#22909;。</p><p>第二段。</p></body></html>"#;
        let t = html_to_text_lenient(html);
        assert!(t.contains("第一章"), "实际: {t}");
        assert!(t.contains("你好，&世界 <OK> 你好。"), "实际: {t}");
        assert!(t.contains("第二段。"), "实际: {t}");
        assert!(!t.contains("<p>") && !t.contains("</h1>"), "不应残留标签: {t}");
    }

    #[test]
    fn lenient_text_skips_script_and_strips_unbalanced_tags() {
        // 错配闭合标签（拆章切断 <header>）不应中断抽取
        let html = "<header><p>正文</p></header><script>var x=1;</script><style>p{}</style><p>继续</p>";
        let t = html_to_text_lenient(html);
        assert!(t.contains("正文"), "实际: {t}");
        assert!(t.contains("继续"), "实际: {t}");
        assert!(!t.contains("var x"), "应剥 script: {t}");
        assert!(!t.contains("p{}"), "应剥 style: {t}");
    }

    #[test]
    fn build_toc_falls_back_to_chapter_titles() {
        let chapters = vec![
            Chapter { title: "第一章".into(), href: "chapter_0001.xhtml".into(), html: String::new(), text: String::new() },
            Chapter { title: "第二章".into(), href: "chapter_0002.xhtml".into(), html: String::new(), text: String::new() },
        ];
        let toc = build_toc(&chapters, &[0, 10], None);
        assert_eq!(toc.len(), 2);
        assert_eq!(toc[0].title, "第一章");
        assert_eq!(toc[0].depth, 0);
    }
}
