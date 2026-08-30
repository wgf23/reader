//! azw3 解析器（P1 实现）。
//!
//! 双路径（ADR 决策3、02-design.md §2.3/§4.2）：
//!   路径1 KF8：容器为 KF8（MOBI 头 type==248 或 EXTH 121 存在）时，整书内容若呈 rawml
//!       特征（`<?xml`/`<package`/`<html`）→ 尽力解析内嵌 OPF 的 spine → 章节（规模受限，
//!       失败回 None 走兜底；与 01-req §5 风险7 的"KF8 尽力而为"降级线一致）；
//!   路径2 兜底：扫描记录内二次 MOBI 头（type==2）定位 MOBI7 回退段 → 复用 MOBI7 管线；
//!       无二次 MOBI 头（纯 MOBI7 内容误标 .azw3，如 Gutenberg "kf8" 下载实测）→
//!       整文件按 MOBI7 解析；
//!   两路径皆失败 → Error::Corrupt（不 panic）。
//!
//! 真实 KF8/AZW3 语料（both 与 KF8-only）需 calibre 生成（本环境无 calibre），
//! 留待开发机补录；本模块以"扩展名分发 + 内容嗅探 + 合成 rawml"覆盖（见 corpus README）。

use std::path::Path;

use super::{Chapter, Format, ParsedBook};
use crate::error::{Error, Result};
use crate::format::mobi_common::{self, PdbBook};

/// `<html>...</html>` 片段匹配（KF8 rawml 章节抽取）
static HTML_RE: &str = r"(?is)<html\b[^>]*>(.*?)</html>";

/// `<itemref idref="...">` 匹配（KF8 OPF spine）
static SPINE_RE: &str = r#"(?i)<itemref\b[^>]*\bidref\s*=\s*"([^"]+)""#;

/// AZW3（KF8）→ ParsedBook
pub fn parse(path: &Path) -> Result<ParsedBook> {
    let book = PdbBook::from_path(path)?;
    if book.has_drm() {
        return Err(Error::Encrypted("检测到 DRM/加密标记".to_string()));
    }
    if is_kf8(&book) {
        if let Some(parsed) = parse_kf8_rawml(&book) {
            return Ok(parsed);
        }
    }
    parse_fallback(&book)
}

/// KF8 判定：MOBI 头原始 type==248（KF8），或 EXTH 121（KF8BoundaryOffset）存在
fn is_kf8(book: &PdbBook) -> bool {
    mobi_common::mobi_type_u32(book) == 248 || book.mobi().metadata.exth_record_at(121).is_some()
}

/// 路径1 KF8：rawml 特征检测 + 内嵌 OPF 尽力解析；失败返回 None
fn parse_kf8_rawml(book: &PdbBook) -> Option<ParsedBook> {
    let html = mobi_common::whole_html(book).ok()?;
    if !looks_like_rawml(&html) {
        return None;
    }
    let mut parsed = parse_rawml_book(&html)?;
    parsed.title = book.mobi().title();
    parsed.authors = mobi_common::authors_of(book);
    parsed.language = mobi_common::language_of(book);
    Some(parsed)
}

/// rawml 特征：内容头部呈 XML/OPF/HTML 特征
fn looks_like_rawml(html: &str) -> bool {
    let head = &html[..html.len().min(4096)];
    head.contains("<?xml") || head.contains("<package") || head.contains("<html")
}

/// 解析内嵌 OPF：spine 顺序 ↔ rawml 中 `<html>` 片段出现顺序（best effort）
fn parse_rawml_book(rawml: &str) -> Option<ParsedBook> {
    let opf = extract_opf(rawml)?;
    let spine = opf_spine(&opf)?;
    let mut chapters = Vec::new();
    for (i, _) in spine.iter().enumerate() {
        let frag = nth_html_fragment(rawml, i)?;
        let text = crate::format::epub::html_to_text(&frag);
        let title = mobi_common::first_heading(&frag).unwrap_or_else(|| "未命名章节".to_string());
        chapters.push(Chapter {
            title,
            href: format!("chapter_{:04}.xhtml", i + 1),
            html: frag,
            text,
        });
    }
    if chapters.is_empty() {
        return None;
    }
    Some(ParsedBook {
        format: Format::Azw3,
        title: "未命名".to_string(),
        authors: Vec::new(),
        language: None,
        chapters,
        toc: Vec::new(),
        resources: Vec::new(),
    })
}

/// 抽取 OPF `<package ...>...</package>`（manifest/spine 源）
fn extract_opf(rawml: &str) -> Option<String> {
    let start = rawml.find("<package")?;
    let end = rawml.find("</package>")?;
    Some(rawml[start..end + 10].to_string())
}

/// OPF spine 的 idref 列表（按出现顺序）
fn opf_spine(opf: &str) -> Option<Vec<String>> {
    let re = regex::Regex::new(SPINE_RE).ok()?;
    let ids: Vec<String> = re
        .captures_iter(opf)
        .filter_map(|c| c.get(1))
        .map(|m| m.as_str().to_string())
        .collect();
    if ids.is_empty() {
        None
    } else {
        Some(ids)
    }
}

/// rawml 中第 n 个 `<html>` 片段
fn nth_html_fragment(rawml: &str, n: usize) -> Option<String> {
    let re = regex::Regex::new(HTML_RE).ok()?;
    let frag = re.captures_iter(rawml).nth(n)?.get(1)?.as_str().to_string();
    Some(frag)
}

/// 路径2 兜底：定位记录内二次 MOBI7 头（type==2）→ 复用 MOBI7 管线；
/// 无二次头（MOBI7 内容误标 .azw3）→ 整文件按 MOBI7 解析。
fn parse_fallback(book: &PdbBook) -> Result<ParsedBook> {
    if let Some(idx) = find_embedded_mobi7(book) {
        return super::mobi::parse_section(book, idx);
    }
    super::mobi::parse_mobi7(book, Format::Azw3)
}

/// 扫描记录（跳过 record 0），找内容为 "PalmDoc 头 + MOBI 魔数 + type==2" 的
/// MOBI7 回退段起点记录
fn find_embedded_mobi7(book: &PdbBook) -> Option<usize> {
    for i in 1..book.num_records() {
        if is_embedded_mobi7(book.record_bytes(i)) {
            return Some(i);
        }
    }
    None
}

/// 记录内容是否内嵌 MOBI7 头（content[16..20]=="MOBI" 且 type 字段==2）
fn is_embedded_mobi7(content: &[u8]) -> bool {
    if content.len() < 28 {
        return false;
    }
    if &content[16..20] != b"MOBI" {
        return false;
    }
    let ty = u32::from_be_bytes([content[24], content[25], content[26], content[27]]);
    ty == 2
}
