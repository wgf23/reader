//! MOBI7 解析器（P1 实现）。
//!
//! 要点见 docs/02-technical.md §3；输出统一中间表示 `ParsedBook`（format/mod.rs）。
//! 管线（02-design.md §2.2/§4.1）：PDB 容器（mobi_common::PdbBook，含截断防 panic 校验）
//! → DRM 检测 → 段结构（MobiSection）→ 整书 HTML 解压/解码 → sanitize → 拆章 →
//! 章节/TOC 组装 → 图片抽取。`parse_section` 供 azw3.rs 回退段复用（ADR 决策3）。

use std::path::Path;

use super::{Chapter, Format, ParsedBook, TocEntry};
use crate::error::{Error, Result};
use crate::format::mobi_common::{self, PdbBook};

/// MOBI7（MOBI 头 type∈{2,3,518}，PalmDoc/No/Huff 压缩）→ ParsedBook
pub fn parse(path: &Path) -> Result<ParsedBook> {
    let book = PdbBook::from_path(path)?;
    parse_mobi7(&book, Format::Mobi)
}

/// MOBI7 完整管线（整文件段 k=0；azw3.rs 纯 MOBI7 内容误标 .azw3 时复用）
pub(crate) fn parse_mobi7(book: &PdbBook, format: Format) -> Result<ParsedBook> {
    let section = mobi_common::MobiSection::from_embedded(book, 0)?;
    let html = mobi_common::section_html(book, &section)?;
    finish_book(book, &section, &html, format)
}

/// 解析从指定记录开始的 MOBI7 段（AZW3 内嵌回退段；ADR 决策3 路径2）
pub(crate) fn parse_section(book: &PdbBook, start: usize) -> Result<ParsedBook> {
    let section = mobi_common::MobiSection::from_embedded(book, start)?;
    let html = mobi_common::section_html(book, &section)?;
    finish_book(book, &section, &html, Format::Azw3)
}

/// 段 → ParsedBook 组装（MOBI7 与 AZW3 回退段共用）
fn finish_book(
    book: &PdbBook,
    section: &mobi_common::MobiSection,
    html: &str,
    format: Format,
) -> Result<ParsedBook> {
    if book.has_drm() {
        return Err(Error::Encrypted("检测到 DRM/加密标记".to_string()));
    }
    let images = mobi_common::extract_images_from(book, section);
    let html = mobi_common::sanitize_html(html, &images);
    let indx = mobi_common::parse_indx_section(book, section);
    let (chapters, toc) = chapters_and_toc(&html, indx);
    let parsed = ParsedBook {
        format,
        title: book.mobi().title(),
        authors: mobi_common::authors_of(book),
        language: mobi_common::language_of(book),
        chapters,
        toc,
        resources: images,
    };
    Ok(parsed)
}

/// 由整书 HTML + INDX 条目产出 (chapters, toc)（azw3.rs 回退段复用）。
/// 章节 href 按 `chapter_XXXX.xhtml`（idx+1 起）命名，与 canonicalize 输出命名一致。
pub(crate) fn chapters_and_toc(
    html: &str,
    indx: Option<Vec<(String, u32)>>,
) -> (Vec<Chapter>, Vec<TocEntry>) {
    let (splits, offsets) = mobi_common::split_chapters(html);
    let chapters = build_chapters(&splits);
    let toc = mobi_common::build_toc(&chapters, &offsets, indx.as_deref());
    (chapters, toc)
}

/// 章节组装：标题取段内首个 h1-h3/title，文本用宽松抽取（quick_xml 对拆章切断的
/// 错配闭合标签会中断，故不直接复用 epub::html_to_text——见 mobi_common 说明）
fn build_chapters(splits: &[String]) -> Vec<Chapter> {
    splits
        .iter()
        .enumerate()
        .map(|(i, part)| {
            let title = mobi_common::first_heading(part).unwrap_or_else(|| "未命名章节".to_string());
            Chapter {
                title,
                href: format!("chapter_{:04}.xhtml", i + 1),
                html: part.clone(),
                text: mobi_common::html_to_text_lenient(part),
            }
        })
        .collect()
}
