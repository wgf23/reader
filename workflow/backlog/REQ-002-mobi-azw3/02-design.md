<!-- wf-meta: req=REQ-002 | phase=architecture | agent=architect | date=2025-08-30 | gate=passed -->
# REQ-002 · 模块/接口设计（MOBI/AZW3 解析）

## 1. 模块与职责变化

| 模块 | 变化 | 层 | 说明 |
|---|---|---|---|
| `core/src/format/mobi_common.rs` | **新增**：PDB 薄封装 / PalmDOC LZ77 自研 / 编码解码链 / HTML 清洗 / 拆章 / INDX 解析 / 图片抽取 / 媒体类型嗅探 | domain | mobi.rs 与 azw3.rs 共用的解析内核（ADR 决策1）；ddd-rules 的 domain 路径 `core/src/format` 已覆盖，规则表无需改；只允许依赖 `crate::error`、`crate::format` 内部类型与外部 crate（mobi / encoding_rs / regex / quick-xml），禁止 `crate::store\|api\|library` |
| `core/src/format/mobi.rs` | 空 stub → MOBI7 完整管线（薄适配） | domain | `pub fn parse`；把 mobi_common 能力组装为 `ParsedBook` |
| `core/src/format/azw3.rs` | 空 stub → KF8/回退段双路径管线 | domain | `pub fn parse`；KF8 rawml 尽力而为 + 回退段兜底（ADR 决策3） |
| `core/src/format/mod.rs` | `parse()` 新增 Mobi/Azw3 分发；`detect_format()` BOOKMOBI 分支增强 | domain | 无扩展名 AZW3 嗅探（MOBI 头 type==248 → Azw3） |
| `core/src/error.rs` | 新增 `Encrypted` 变体 | domain | 对齐 docs/03 §8 CoreError 分类（ADR 决策5） |
| `core/src/convert/mod.rs` | **不改** | domain | 章节 href/资源重写约定由解析器侧对齐（ADR 决策4） |
| `core/src/library/mod.rs`、`core/src/api.rs` | **不改**（回归验证） | application / interface | `library_import`/`open_book`/`book_chapter_html`/`book_resource` 全复用；错误文案经 `err_msg(Display)` 自动覆盖新变体 |

## 2. 接口签名（Rust 函数级）

### 2.1 新增 `format/mobi_common.rs`（pub(crate) 共享层）
```rust
//! MOBI/AZW3 共用解析内核（domain 层；ADR-REQ-002 决策1）。
use crate::error::Result;
use crate::format::{Chapter, Resource, TocEntry};
use mobi::{Mobi, MobiMetadata, TextEncoding};
use std::collections::HashMap;
use std::path::Path;

/// PDB 容器薄封装：统一把 mobi crate 的错误映射为 crate::error::Error
pub(crate) struct PdbBook { mobi: Mobi }
impl PdbBook {
    /// 打开并解析 PDB 容器（MOBI7 与 AZW3 共用；AZW3 的 KF8 头同样可解析，
    /// mobi_type() 为 Unknown(248)，由 azw3.rs 判定）
    pub(crate) fn from_path(path: &Path) -> Result<PdbBook>;
    pub(crate) fn mobi(&self) -> &Mobi;
    /// 可读记录区范围（first_content_record .. first_non_book_index）
    pub(crate) fn readable_range(&self) -> std::ops::Range<usize>;
}

/// PalmDOC LZ77 解压（自研 ~100 行；mobi crate 的 palmdoc::decompress 为 pub(crate)
/// 不可外部调用，GBK 路径与 AZW3 回退段必须自解码）
pub(crate) fn palmdoc_decompress(data: &[u8]) -> Result<Vec<u8>>;

/// 编码解码链：声明编码 → 内容探测 → lossy UTF-8
/// declared：mobi::TextEncoding（CP1252=1252 / UTF8=65001 / Unknown(n)）
/// 936→GBK、950→Big5、1252→windows-1252、65001→UTF-8、未知→内容探测
/// （UTF-8 有效性 → GBK 启发式）→ 最后 lossy
pub(crate) fn decode_text(bytes: &[u8], declared: TextEncoding) -> String;

/// 整书 HTML：可读记录区逐记录解压（PalmDoc/No 走自研+decode_text；
/// Huff 走 mobi::Mobi::content_as_string_lossy 受限路径，编码仅 UTF8/CP1252）
pub(crate) fn whole_html(book: &PdbBook) -> Result<String>;

/// HTML 预处理（ADR 决策4）：剥 <mbp:pagebreak> 外残留的 mbp: 命名空间标签、
/// 去 <font>/内联 style、补 DOCTYPE、把 <img src> 重写为 images/imageNNNN.ext
/// （与 Resource.source_path 完全一致 → canonicalize 重写必然命中）
pub(crate) fn sanitize_html(html: &str, img_map: &HashMap<String, String>) -> String;

/// 拆章：<mbp:pagebreak> 主切分（大小写/属性容错）；切出 < 2 段时回退
/// h1-h3 标题切分；返回各段原始 HTML
pub(crate) fn split_chapters(html: &str) -> Vec<String>;

/// 章节标题：段内第一个 h1-h3/title（与 epub.rs first_heading 语义一致；
/// epub.rs 的为私有函数，此处独立实现，不修改 epub.rs）
pub(crate) fn first_heading(html: &str) -> Option<String>;

/// 图片记录 → Resource：image_records() 记录按序编号 image0001.ext 起；
/// media_type 按魔数嗅探（FFD8→image/jpeg、89504E47→image/png、
/// GIF87a/89a→image/gif、424D→image/bmp）
pub(crate) fn extract_images(book: &PdbBook) -> Vec<Resource>;

/// INDX 目录解析：定位 first_index_record..first_non_book_index 区间内的
/// INDX 记录，解析条目 (label, 内容流偏移 pos)；失败或缺失返回 None
pub(crate) fn parse_indx(book: &PdbBook) -> Option<Vec<(String, u32)>>;

/// INDX pos（内容流字节偏移）→ 拆章后的章节索引（二分/线性映射）
fn chapter_index_at(splits: &[usize], pos: u32) -> usize;
```

### 2.2 `format/mobi.rs`
```rust
/// MOBI7（MOBI 头 type∈{2,3,518}，PalmDoc/No/Huff 压缩）→ ParsedBook
pub fn parse(path: &Path) -> Result<ParsedBook>;

/// 由整书 HTML + 拆章偏移 + INDX 偏移映射产出 (chapters, toc)（azw3.rs 回退段复用）
pub(crate) fn chapters_and_toc(
    html: &str,
    indx: Option<Vec<(String, u32)>>,
) -> (Vec<Chapter>, Vec<TocEntry>);
```

### 2.3 `format/azw3.rs`
```rust
/// AZW3（KF8）→ ParsedBook。双路径（ADR 决策3）：
///   路径1 KF8：whole_html 产物呈 rawml 特征（<?xml/<package/<html）→
///       parse_kf8_rawml 解析内嵌 OPF 的 manifest/spine/nav → 章节+资源
///   路径2 兜底：EXTH 121 KF8BoundaryOffset + 记录内二次 MOBI 头(type==2) 扫描
///       → 自解析回退段 → mobi::chapters_and_toc
///   两者皆失败 → Error::Corrupt
pub fn parse(path: &Path) -> Result<ParsedBook>;

fn is_kf8(meta: &MobiMetadata) -> bool;                       // type==248 或 EXTH 121 存在
fn parse_kf8_rawml(book: &PdbBook) -> Option<ParsedBook>;     // 尽力而为，失败回 None
fn parse_fallback(book: &PdbBook) -> Result<ParsedBook>;      // 兜底必达路径
```

### 2.4 `format/mod.rs` 变更
```rust
pub fn parse(path: &Path) -> Result<ParsedBook> {
    match format {
        Format::Epub => epub::parse(path),
        Format::Txt => txt::parse(path),
        Format::Mobi => mobi::parse(path),
        Format::Azw3 => azw3::parse(path),
        other => Err(Error::UnsupportedFormat(...)),   // 既有文案不变
    }
}

// detect_format BOOKMOBI 分支（新增内部函数，解析失败保守回退 Mobi）：
fn mobi_type_from_head(bytes: &[u8]) -> Option<u32> {
    // 记录 0 偏移 = bytes[78..82] BE u32；MOBI 魔数在其偏移处；
    // type 字段 = MOBI 头偏移 +8（4 字节 BE）
    // 返回 type；==248 → Azw3，否则 → Mobi
}
```

### 2.5 `error.rs` 变更
```rust
#[error("文件可能受 DRM/加密保护，无法解析：{0}")]
Encrypted(String),
```
（`api.rs` 的 `err_msg<E: Display>(e) -> String` 泛型映射自动透出，无需改动；新变体需补测试断言）

## 3. 数据模型变化
无数据库表变更；无 `BookRecord`/`Locator`/`ReadingProgress` 字段变更。
`ParsedBook`（format/mod.rs）结构不变，MOBI/AZW3 按其字段填充：

| ParsedBook 字段 | MOBI/AZW3 填充约定 |
|---|---|
| `format` | `Format::Mobi` / `Format::Azw3` |
| `title` | EXTH 503 → 回退 PDB name（`MobiMetadata::title()` 已封装） |
| `authors` | EXTH 100 → 空 Vec |
| `language` | EXTH 524 → 回退 MOBI header `language()` 映射（English→en、Chinese→zh，其余 None） |
| `chapters[].title` | 段内首个 h1-h3 / 文件名兜底"未命名章节" |
| `chapters[].href` | `chapter_XXXX.xhtml`（idx+1 起，与 canonicalize 输出命名一致；canonicalize 实际按索引写盘，两者恒等） |
| `chapters[].html` | sanitize 后的章节 HTML（无 mbp:/font、有 DOCTYPE、img src 已重写） |
| `chapters[].text` | 复用 `epub::html_to_text`（pub） |
| `toc[].title/href/depth` | INDX 标签 + `chapter_XXXX.xhtml` 映射；INDX 缺失/失败 → 章节标题回退；depth clamp 0..=8（与 epub.rs 一致） |
| `resources[].source_path` | `images/imageNNNN.ext`（与 HTML 中 src 完全一致） |
| `resources[].media_type` | 魔数嗅探（image/jpeg|png|gif|bmp） |

## 4. 关键时序

### 4.1 MOBI7（mobi.rs）
```
format::parse(path)  // Format::Mobi
 → mobi_common::PdbBook::from_path          // Mobi::from_path；MobiError→Error::Corrupt
 → DRM 检查：encryption()!=No || metadata.mobi.has_drm() → Err(Error::Encrypted("...DRM/加密..."))
 → 元数据：title/authors/language（EXTH → MOBI header 兜底）
 → decode_text(records[readable_range], text_encoding)   // GBK(936) 经 encoding_rs，无 U+FFFD
 → whole_html → sanitize_html（剥 mbp:、补 DOCTYPE、重写 img src）
 → split_chapters（pagebreak 主 / 标题回退）
 → chapters_and_toc（first_heading + html_to_text；INDX 解析 → toc 或标题回退）
 → extract_images → resources
 → ParsedBook{format: Mobi, ...}
 → （下游）BookCanonicalizer::canonicalize → chapter_XXXX.xhtml + images/res_XXXX_*
   → LibraryService::import_file / open_book（既有管线，零改动）
```

### 4.2 AZW3（azw3.rs）
```
format::parse(path)  // Format::Azw3（扩展名或 detect_format 嗅探 type==248）
 → PdbBook::from_path（容器解析成功；mobi_type()==Unknown(248)）
 → DRM 检查（同 MOBI7）
 → 路径1 KF8：whole_html → 呈 rawml 特征？
     → 是：parse_kf8_rawml（内嵌 OPF manifest/spine/nav + 图片记录）→ ParsedBook{format: Azw3}
     → 否/失败：继续路径2
 → 路径2 兜底：EXTH 121 KF8BoundaryOffset + 记录扫描二次 MOBI 头(type==2)
     → 自解析回退段 MOBI 头 + 自研 palmdoc_decompress + decode_text
     → mobi::chapters_and_toc → ParsedBook{format: Azw3}
 → 两路径皆失败 → Err(Error::Corrupt)
```

## 5. 错误分类（复用 error.rs 变体 + 新增 Encrypted）

| 场景 | 检测手段 | 错误变体 |
|---|---|---|
| DRM 加密 | `encryption() != No` 或 `metadata.mobi.has_drm()` | **新增** `Encrypted`（消息含"DRM/加密"） |
| PDB 头/记录表损坏（偏移越界/魔数错乱） | `MobiError::MetadataParseError` / `IoError` | `Corrupt` |
| 解压失败（PalmDOC/Huff） | `DecodeError` / `HuffmanError` / 自研解压失败 | `Corrupt` |
| 截断文件（内容流被切断） | 记录区读取越界/长度不符 | `Corrupt` |
| 伪装文件（BOOKMOBI 魔数 + 垃圾） | 无有效 MOBI 头/可读记录区为空/内容非 HTML | `Corrupt` |
| KF8 双路径皆失败 | — | `Corrupt` |
| 文件不存在/IO | — | `Io` |

原则：**任何输入不 panic**（mobi crate 内部对损坏文件有防 OOM/越界处理；自研解析全部用
checked 运算 + 边界校验）。

## 6. 与既有约定的兼容性
- [x] 不破坏 Locator 模型（locator/ 模块零改动；章节文本锚定走既有 `TextAnchor` 模糊匹配）
- [x] 不跨越限界上下文（全部改动落在 domain 层 `core/src/format|error`；ddd-rules.toml 无需修改；
     禁止依赖 store/api/library 的约束在设计中显式声明）
- [x] 听读同进度不变式保持（不触碰 reading_progress/tts 模块）
- [x] 不破坏 ParsedBook/library 管线（convert/library/api 零改动；Chapter.href/resource.source_path
     约定与 canonicalize 输出命名对齐，资源重写精确命中）
- [x] epub/txt 零行为变化（parse 仅新增两臂；detect_format BOOKMOBI 分支只影响 mobi/azw3 判定）
- [x] 与 docs/02 §3.3（MOBI/AZW3 算法）、§3.2（规范 EPUB）、docs/03 §8（错误分类含 Encrypted）、
     docs/04 §7（FormatParser 契约）一致
