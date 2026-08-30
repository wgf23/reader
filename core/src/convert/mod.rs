//! 规范化：任意 reflow 格式 → 规范 EPUB（缓存落盘，键=源文件内容 SHA-256）。
//!
//! 设计：docs/02-technical.md §3.2、docs/04-module-design.md §7。
//! 规范 EPUB 子集：mimetype + container.xml + content.opf + nav.xhtml +
//! 章节 XHTML（资源路径重写为扁平 images/）+ 资源拷贝。

use std::io::Write;
use std::path::Path;

use regex::Regex;
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipWriter};

use crate::error::{Error, Result};
use crate::format::ParsedBook;

pub struct BookCanonicalizer;

impl BookCanonicalizer {
    /// 生成规范 EPUB 到 `out_path`（含 .epub 扩展名）。
    pub fn canonicalize(parsed: &ParsedBook, out_path: &Path) -> Result<()> {
        let file = std::fs::File::create(out_path).map_err(Error::Io)?;
        let mut zip = ZipWriter::new(file);

        let stored = SimpleFileOptions::default().compression_method(CompressionMethod::Stored);
        let deflated = SimpleFileOptions::default().compression_method(CompressionMethod::Deflated);

        // mimetype 必须为第一个文件且不压缩（EPUB 规范）
        zip.start_file("mimetype", stored)
            .map_err(|e| Error::Io(std::io::Error::other(e.to_string())))?;
        zip.write_all(b"application/epub+zip").map_err(Error::Io)?;

        // 资源扁平化映射：源路径 → images/res_XXXX_<basename>
        let mut images: Vec<(String, String, String)> = Vec::new(); // (id, href, media_type)
        let mut flat_of: Vec<(String, String)> = Vec::new(); // (源路径, 扁平路径)
        for (idx, res) in parsed.resources.iter().enumerate() {
            let flat = format!("images/res_{:04}_{}", idx, basename(&res.source_path));
            flat_of.push((res.source_path.clone(), flat.clone()));
            images.push((format!("img{idx}"), flat, res.media_type.clone()));
        }

        let url_re = Regex::new(r#"(?i)((?:src|href)\s*=\s*")([^"]+)(")"#)
            .map_err(|e| Error::Other(format!("正则编译失败: {e}")))?;
        let rewrite = |html: &str| -> String {
            url_re
                .replace_all(html, |caps: &regex::Captures| {
                    let url = &caps[2];
                    let key = url.split('#').next().unwrap_or(url);
                    let flat = flat_of
                        .iter()
                        .find(|(src, _)| src == key || src.ends_with(&format!("/{key}")))
                        .map(|(_, f)| f.clone());
                    match flat {
                        Some(f) => format!("{}{}{}", &caps[1], f, &caps[3]),
                        None => caps[0].to_string(),
                    }
                })
                .into_owned()
        };

        // 章节 XHTML（扁平化：chapter_XXXX.xhtml）
        let mut chapter_hrefs: Vec<String> = Vec::new();
        for (idx, ch) in parsed.chapters.iter().enumerate() {
            let name = format!("chapter_{:04}.xhtml", idx + 1);
            let html = rewrite(&ch.html);
            zip.start_file(&name, deflated)
                .map_err(|e| Error::Io(std::io::Error::other(e.to_string())))?;
            zip.write_all(html.as_bytes()).map_err(Error::Io)?;
            chapter_hrefs.push(name);
        }

        // nav.xhtml（EPUB3 导航）
        let nav = build_nav(parsed, &chapter_hrefs);
        zip.start_file("nav.xhtml", deflated)
            .map_err(|e| Error::Io(std::io::Error::other(e.to_string())))?;
        zip.write_all(nav.as_bytes()).map_err(Error::Io)?;

        // 资源
        for (_, flat, _) in &images {
            let data = parsed
                .resources
                .iter()
                .find(|r| flat_of.iter().any(|(s, f)| f == flat && s == &r.source_path))
                .map(|r| &r.data)
                .ok_or_else(|| Error::Corrupt(format!("资源缺失: {flat}")))?;
            zip.start_file(flat, deflated)
                .map_err(|e| Error::Io(std::io::Error::other(e.to_string())))?;
            zip.write_all(data).map_err(Error::Io)?;
        }

        // content.opf
        let opf = build_opf(parsed, &chapter_hrefs, &images);
        zip.start_file("content.opf", deflated)
            .map_err(|e| Error::Io(std::io::Error::other(e.to_string())))?;
        zip.write_all(opf.as_bytes()).map_err(Error::Io)?;

        // container.xml
        zip.start_file("META-INF/container.xml", deflated)
            .map_err(|e| Error::Io(std::io::Error::other(e.to_string())))?;
        zip.write_all(container_xml().as_bytes()).map_err(Error::Io)?;

        zip.finish()
            .map_err(|e| Error::Io(std::io::Error::other(e.to_string())))?;
        Ok(())
    }
}

fn basename(path: &str) -> String {
    path.rsplit('/').next().unwrap_or(path).to_string()
}

fn container_xml() -> String {
    r#"<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"#
    .to_string()
}

fn build_opf(
    parsed: &ParsedBook,
    chapters: &[String],
    images: &[(String, String, String)], // (id, href, media_type)
) -> String {
    let mut manifest = String::from(
        r#"    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>"#,
    );
    for (idx, href) in chapters.iter().enumerate() {
        manifest.push_str(&format!(
            "\n    <item id=\"c{idx}\" href=\"{href}\" media-type=\"application/xhtml+xml\"/>"
        ));
    }
    for (id, href, media_type) in images {
        manifest.push_str(&format!(
            "\n    <item id=\"{id}\" href=\"{href}\" media-type=\"{media_type}\"/>"
        ));
    }

    let mut spine = String::new();
    for (idx, _) in chapters.iter().enumerate() {
        spine.push_str(&format!("\n    <itemref idref=\"c{idx}\"/>"));
    }

    let authors = parsed
        .authors
        .iter()
        .map(|a| format!("<dc:creator>{}</dc:creator>", escape_xml(a)))
        .collect::<Vec<_>>()
        .join("\n    ");
    let language = parsed.language.as_deref().unwrap_or("und");
    let authors_block = if authors.is_empty() {
        String::new()
    } else {
        format!("    {authors}\n")
    };

    format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">reader:{hash}</dc:identifier>
    <dc:title>{title}</dc:title>
    <dc:language>{language}</dc:language>
{authors_block}  </metadata>
  <manifest>
{manifest}
  </manifest>
  <spine>
{spine}
  </spine>
</package>
"#,
        hash = parsed_title_hash(parsed),
        title = escape_xml(&parsed.title),
    )
}

fn build_nav(parsed: &ParsedBook, chapter_hrefs: &[String]) -> String {
    let mut items = String::new();
    for (idx, ch) in parsed.chapters.iter().enumerate() {
        let title = if ch.title.is_empty() {
            format!("第 {} 章", idx + 1)
        } else {
            ch.title.clone()
        };
        let href = chapter_hrefs
            .get(idx)
            .cloned()
            .unwrap_or_else(|| format!("chapter_{:04}.xhtml", idx + 1));
        items.push_str(&format!(
            "      <li><a href=\"{href}\">{}</a></li>\n",
            escape_xml(&title)
        ));
    }
    format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目录</title></head>
<body>
  <nav epub:type="toc" id="toc">
    <h1>目录</h1>
    <ol>
{items}    </ol>
  </nav>
</body>
</html>
"#
    )
}

fn parsed_title_hash(parsed: &ParsedBook) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(parsed.title.as_bytes());
    for ch in &parsed.chapters {
        hasher.update(ch.href.as_bytes());
        hasher.update(ch.html.as_bytes());
    }
    let digest = hasher.finalize();
    let mut s = String::new();
    for b in digest.iter().take(8) {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

fn escape_xml(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::format::{Chapter, Format, ParsedBook};

    fn sample_book() -> ParsedBook {
        ParsedBook {
            format: Format::Txt,
            title: "测试书".to_string(),
            authors: vec!["作者".to_string()],
            language: Some("zh".to_string()),
            chapters: vec![
                Chapter {
                    title: "第一章".to_string(),
                    href: "c1".to_string(),
                    html: "<html><body><h1>第一章</h1><p>内容。</p></body></html>".to_string(),
                    text: "内容。".to_string(),
                },
                Chapter {
                    title: "第二章".to_string(),
                    href: "c2".to_string(),
                    html: "<html><body><h1>第二章</h1><p>更多。</p></body></html>".to_string(),
                    text: "更多。".to_string(),
                },
            ],
            toc: Vec::new(),
            resources: Vec::new(),
        }
    }

    #[test]
    fn canonicalize_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let out = dir.path().join("canonical.epub");
        BookCanonicalizer::canonicalize(&sample_book(), &out).unwrap();
        assert!(out.exists());

        // 重新解析规范 EPUB，章节数一致；章节文本含原标题（h1 并入正文）
        let reparsed = crate::format::epub::parse(&out).unwrap();
        assert_eq!(reparsed.chapters.len(), 2);
        assert!(reparsed.chapters[0].text.contains("内容。"));
        assert!(reparsed.chapters[0].text.contains("第一章"));
        assert_eq!(reparsed.title, "测试书");
    }
}
