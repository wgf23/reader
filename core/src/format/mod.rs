//! 格式解析层：把各格式解析为统一中间表示（`ParsedBook`）。
//!
//! 设计：docs/02-technical.md §3（格式方案）、docs/04-module-design.md §7（接口）。
//! 两条管线：reflow（epub/mobi/azw3/txt/fb2 → 规范 EPUB）与 page（pdf/cbz 直读）。
//!
//! 实现：EPUB（epub.rs）、TXT（txt.rs）、MOBI7（mobi.rs + mobi_common.rs）、
//! AZW3/KF8（azw3.rs + mobi_common.rs）；pdf/fb2/cbz 为 P1。

pub mod epub;
pub mod mobi;
pub(crate) mod mobi_common;
pub mod azw3;
pub mod txt;
pub mod fb2;
pub mod pdf;
pub mod cbz;

use std::path::Path;

use crate::error::{Error, Result};

/// 支持的文件格式
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Format {
    #[default]
    Epub,
    Pdf,
    Mobi,
    Azw3,
    Txt,
    Fb2,
    Cbz,
}

impl Format {
    pub fn name(&self) -> &'static str {
        match self {
            Format::Epub => "epub",
            Format::Pdf => "pdf",
            Format::Mobi => "mobi",
            Format::Azw3 => "azw3",
            Format::Txt => "txt",
            Format::Fb2 => "fb2",
            Format::Cbz => "cbz",
        }
    }
}

/// 章节（spine 中的一个内容单元）
#[derive(Debug, Clone)]
pub struct Chapter {
    pub title: String,
    /// 资源路径（规范 EPUB 内相对路径）
    pub href: String,
    /// 原始 HTML（规范化用）
    pub html: String,
    /// 纯文本（阅读/搜索/锚定用）
    pub text: String,
}

/// 目录条目（扁平化，带层级深度；用于还原层级展示）
#[derive(Debug, Clone)]
pub struct TocEntry {
    pub title: String,
    pub href: String,
    pub depth: u8,
}

/// 资源（图片/字体/CSS，规范化时拷贝）
#[derive(Debug, Clone)]
pub struct Resource {
    /// 源 zip 内路径
    pub source_path: String,
    /// 媒体类型（如 image/jpeg）
    pub media_type: String,
    pub data: Vec<u8>,
}

/// 解析后的统一中间表示
#[derive(Debug, Default)]
pub struct ParsedBook {
    pub format: Format,
    pub title: String,
    pub authors: Vec<String>,
    pub language: Option<String>,
    pub chapters: Vec<Chapter>,
    pub toc: Vec<TocEntry>,
    pub resources: Vec<Resource>,
}

/// 按扩展名嗅探格式
pub fn format_for_path(path: &Path) -> Option<Format> {
    let ext = path.extension()?.to_str()?.to_ascii_lowercase();
    match ext.as_str() {
        "epub" => Some(Format::Epub),
        "pdf" => Some(Format::Pdf),
        "mobi" => Some(Format::Mobi),
        "azw" | "azw3" => Some(Format::Azw3),
        "txt" => Some(Format::Txt),
        "fb2" => Some(Format::Fb2),
        "cbz" => Some(Format::Cbz),
        _ => None,
    }
}

/// 按文件头嗅探格式（无扩展名/扩展名缺失时）
pub fn detect_format(bytes: &[u8]) -> Option<Format> {
    if bytes.starts_with(b"%PDF") {
        Some(Format::Pdf)
    } else if bytes.starts_with(b"PK") {
        // ZIP 容器：EPUB（有 mimetype）或 CBZ（无）
        Some(Format::Epub)
    } else if looks_like_pdb(bytes) {
        // PDB 容器：按 MOBI 头 type 区分（==248 为 KF8/AZW3，否则 MOBI7；
        // 头解析失败保守回退 Mobi，满足 US-2 无扩展名嗅探）。
        // 注：真实 PDB 的 BOOKMOBI 魔数在偏移 60（前 32 字节为书名），
        // 兼容旧约定偏移 0。
        if mobi_type_from_head(bytes) == Some(248) {
            Some(Format::Azw3)
        } else {
            Some(Format::Mobi)
        }
    } else if bytes.starts_with(b"<?xml") && looks_like_fb2(bytes) {
        Some(Format::Fb2)
    } else if bytes.starts_with(b"\xef\xbb\xbf") || !bytes.contains(&0) {
        // BOM 或纯文本
        Some(Format::Txt)
    } else {
        None
    }
}

/// PDB 容器魔数检测：BOOKMOBI 在偏移 60（真实 PDB，前 32 字节为书名）或偏移 0（旧约定）
fn looks_like_pdb(bytes: &[u8]) -> bool {
    (bytes.len() >= 68 && &bytes[60..68] == b"BOOKMOBI") || (bytes.len() >= 8 && &bytes[..8] == b"BOOKMOBI")
}

/// 从 PDB 文件头读 MOBI 头 type 字段：record 0 偏移在 78..82（BE u32），
/// MOBI 魔数在 record 0 +16，type 字段在魔数 +8；解析失败返回 None（保守回退 Mobi）。
fn mobi_type_from_head(bytes: &[u8]) -> Option<u32> {
    let rec0 = be_u32(bytes, 78)? as usize;
    let mobi = rec0.checked_add(16)?;
    let magic = bytes.get(mobi..mobi + 4)?;
    if magic != b"MOBI" {
        return None;
    }
    be_u32(bytes, mobi + 8)
}

/// 大端 u32 读取（越界返回 None）
fn be_u32(bytes: &[u8], off: usize) -> Option<u32> {
    let slice = bytes.get(off..off + 4)?;
    Some(u32::from_be_bytes([slice[0], slice[1], slice[2], slice[3]]))
}

fn looks_like_fb2(bytes: &[u8]) -> bool {
    let head = String::from_utf8_lossy(&bytes[..bytes.len().min(2048)]);
    head.contains("<FictionBook")
}

/// 解析文件为统一中间表示（P0：epub / txt；P1：mobi / azw3）
pub fn parse(path: &Path) -> Result<ParsedBook> {
    let format = format_for_path(path)
        .or_else(|| {
            std::fs::read(path)
                .ok()
                .and_then(|b| detect_format(&b))
        })
        .ok_or_else(|| Error::UnsupportedFormat(format!("无法识别文件类型: {}", path.display())))?;

    match format {
        Format::Epub => epub::parse(path),
        Format::Txt => txt::parse(path),
        Format::Mobi => mobi::parse(path),
        Format::Azw3 => azw3::parse(path),
        other => Err(Error::UnsupportedFormat(format!(
            "{} 格式解析尚未实现（P1 里程碑）",
            other.name()
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detect_unknown_returns_none() {
        // 二进制内容：无魔数、含 NUL → 无法识别
        assert_eq!(detect_format(b"\x00\x01\x02\x03\xff\xfe"), None);
    }

    #[test]
    fn detect_pdf_magic() {
        assert_eq!(detect_format(b"%PDF-1.7\n..."), Some(Format::Pdf));
    }

    #[test]
    fn detect_txt_fallback() {
        assert_eq!(detect_format(b"\xe4\xbd\xa0\xe5\xa5\xbd"), Some(Format::Txt));
    }
}
