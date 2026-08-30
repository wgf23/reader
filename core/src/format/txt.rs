//! TXT 解析器（P0）。
//!
//! 要点（docs/02 §3.4）：编码探测（UTF-8 严格校验 → GB18030，覆盖 GBK；Big5 不覆盖，
//! 文档已注明）；按章节标记（第X章/章回节卷部篇、Chapter N）自动切章；无标记则单章。

use std::path::Path;

use encoding_rs::GB18030;
use regex::Regex;

use super::{Chapter, Format, ParsedBook};
use crate::error::{Error, Result};

/// 解析 TXT 文件为统一中间表示
pub fn parse(path: &Path) -> Result<ParsedBook> {
    let bytes = std::fs::read(path).map_err(Error::Io)?;
    let (text, _) = decode(&bytes);
    let text = strip_bom(&text);

    let chapters = split_chapters(&text)?;

    let title = path
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| "未命名".to_string());

    Ok(ParsedBook {
        format: Format::Txt,
        title,
        authors: Vec::new(),
        language: detect_language(&text),
        chapters,
        toc: Vec::new(),
        resources: Vec::new(),
    })
}

/// 编码探测：UTF-8 严格解码成功 → UTF-8；否则 GB18030（GBK 超集）
pub fn decode(bytes: &[u8]) -> (String, &'static str) {
    match std::str::from_utf8(bytes) {
        Ok(s) => (s.to_string(), "UTF-8"),
        Err(_) => {
            let (cow, _, _) = GB18030.decode(bytes);
            (cow.into_owned(), "GB18030")
        }
    }
}

fn strip_bom(text: &str) -> String {
    text.strip_prefix('\u{feff}').unwrap_or(text).to_string()
}

fn detect_language(text: &str) -> Option<String> {
    let chinese = text
        .chars()
        .filter(|c| {
            matches!(c,
                '\u{4e00}'..='\u{9fff}' | '\u{3400}'..='\u{4dbf}' | '\u{3000}'..='\u{303f}')
        })
        .count();
    if chinese > 0 {
        Some("zh".to_string())
    } else {
        Some("en".to_string())
    }
}

/// 按章节标记切章；无标记时整本为单章
fn split_chapters(text: &str) -> Result<Vec<Chapter>> {
    let re = Regex::new(
        r"^(第[0-9零一二三四五六七八九十百千万两〇]+[章回节卷部篇]|Chapter\s+[0-9IVXLC]+|CHAPTER\s+[0-9IVXLC]+)\s*(.*)$",
    )
    .map_err(|e| Error::Other(format!("正则编译失败: {e}")))?;

    let mut chapters: Vec<Chapter> = Vec::new();
    let mut current_title = "正文".to_string();
    let mut current_lines: Vec<String> = Vec::new();

    let flush = |chapters: &mut Vec<Chapter>, title: &str, lines: &[String]| {
        let text = lines.join("\n");
        let trimmed = text.trim();
        if !trimmed.is_empty() || !lines.is_empty() {
            let html = format!(
                "<html><body><h1>{}</h1>{}</body></html>",
                escape_html(title),
                lines
                    .iter()
                    .map(|l| format!("<p>{}</p>", escape_html(l)))
                    .collect::<Vec<_>>()
                    .join("\n")
            );
            chapters.push(Chapter {
                title: title.to_string(),
                href: format!("chapter_{:04}.xhtml", chapters.len() + 1),
                html,
                text: trimmed.to_string(),
            });
        }
    };

    for line in text.lines() {
        if let Some(caps) = re.captures(line) {
            if !current_lines.is_empty() {
                flush(&mut chapters, &current_title, &current_lines);
                current_lines.clear();
            }
            let marker = caps.get(1).map(|m| m.as_str()).unwrap_or("");
            let rest = caps.get(2).map(|m| m.as_str().trim()).unwrap_or("");
            current_title = if rest.is_empty() {
                marker.to_string()
            } else {
                format!("{} {}", marker, rest)
            };
        } else {
            current_lines.push(line.to_string());
        }
    }
    flush(&mut chapters, &current_title, &current_lines);

    if chapters.is_empty() {
        return Err(Error::Corrupt("TXT 文件无有效内容".into()));
    }
    Ok(chapters)
}

fn escape_html(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_utf8() {
        let (s, enc) = decode("你好，世界".as_bytes());
        assert_eq!(s, "你好，世界");
        assert_eq!(enc, "UTF-8");
    }

    #[test]
    fn decode_gbk() {
        // "你好" 的 GBK 编码
        let gbk = [0xc4, 0xe3, 0xba, 0xc3];
        let (s, enc) = decode(&gbk);
        assert_eq!(s, "你好");
        assert_eq!(enc, "GB18030");
    }

    #[test]
    fn split_chinese_chapters() {
        let text = "第一章 起风了\n内容一\n第二章 下雨了\n内容二\n第三章\n内容三";
        let chapters = split_chapters(text).unwrap();
        assert_eq!(chapters.len(), 3);
        assert!(chapters[0].title.contains("第一章"));
        assert!(chapters[1].title.contains("第二章 下雨了"));
        assert!(chapters[2].title.contains("第三章"));
        assert!(chapters[0].text.contains("内容一"));
    }

    #[test]
    fn split_english_chapters() {
        let text = "Chapter 1 Start\nbody\nCHAPTER II\nmore";
        let chapters = split_chapters(text).unwrap();
        assert_eq!(chapters.len(), 2);
    }

    #[test]
    fn no_markers_single_chapter() {
        let text = "这是\n一本没有章节标记的书";
        let chapters = split_chapters(text).unwrap();
        assert_eq!(chapters.len(), 1);
        assert!(chapters[0].text.contains("没有章节标记"));
    }
}
