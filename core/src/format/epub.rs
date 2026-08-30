//! EPUB 解析器（P0）。
//!
//! 要点（docs/02 §3.2）：ZIP 容器 + container.xml → OPF（metadata/manifest/spine）+
//! 导航（EPUB3 nav.xhtml 优先，NCX 兜底）；章节按 spine 顺序读取并抽取纯文本；
//! 资源（图片/CSS/字体）收集供规范化使用。

use std::collections::{HashMap, HashSet};
use std::io::Read;
use std::path::Path;

use quick_xml::events::Event;
use quick_xml::Reader;
use zip::ZipArchive;

use super::{Chapter, Format, ParsedBook, Resource, TocEntry};
use crate::error::{Error, Result};

/// 解析 EPUB 文件为统一中间表示
pub fn parse(path: &Path) -> Result<ParsedBook> {
    let file = std::fs::File::open(path).map_err(Error::Io)?;
    let mut zip = ZipArchive::new(file)
        .map_err(|e| Error::Corrupt(format!("不是有效的 ZIP/EPUB 容器: {e}")))?;

    // mimetype 校验（宽松：缺失也继续尝试）
    if let Ok(mut m) = zip.by_name("mimetype") {
        let mut buf = String::new();
        m.read_to_string(&mut buf).ok();
        if !buf.trim().contains("epub") {
            return Err(Error::Corrupt("mimetype 不是 application/epub+zip".into()));
        }
    }

    // container.xml → OPF 路径
    let container = read_entry(&mut zip, "META-INF/container.xml")
        .map_err(|_| Error::Corrupt("缺少 META-INF/container.xml".into()))?;
    let opf_path = extract_opf_path(&String::from_utf8_lossy(&container))
        .ok_or_else(|| Error::Corrupt("container.xml 中未找到 rootfile".into()))?;

    let opf_bytes = read_entry(&mut zip, &opf_path)
        .map_err(|_| Error::Corrupt(format!("OPF 不存在: {opf_path}")))?;
    let opf_dir = opf_dir(&opf_path);
    let opf = Opf::parse(&String::from_utf8_lossy(&opf_bytes))?;

    // 章节：按 spine 顺序取 manifest item（xhtml 内容 + 其他资源）
    let mut manifest_ids: HashMap<&str, &ManifestItem> = HashMap::new();
    for item in &opf.manifest {
        manifest_ids.insert(item.id.as_str(), item);
    }

    let mut chapters = Vec::with_capacity(opf.spine.len());
    let mut resources = Vec::new();

    for idref in &opf.spine {
        let item = *manifest_ids
            .get(idref.as_str())
            .ok_or_else(|| Error::Corrupt(format!("spine 引用不存在的 item: {idref}")))?;
        if item.media_type.contains("html") {
            let full = join_path(&opf_dir, &item.href);
            let html = read_entry(&mut zip, &full)
                .map_err(|_| Error::Corrupt(format!("章节文件不存在: {full}")))?;
            let html = String::from_utf8_lossy(&html).into_owned();
            let text = html_to_text(&html);
            let title = first_heading(&html).unwrap_or_else(|| chapter_title_from_href(&item.href));
            chapters.push(Chapter {
                title,
                href: item.href.clone(),
                html,
                text,
            });
        } else if !is_navigation_item(item) {
            if let Ok(data) = read_entry(&mut zip, &join_path(&opf_dir, &item.href)) {
                resources.push(Resource {
                    source_path: join_path(&opf_dir, &item.href),
                    media_type: item.media_type.clone(),
                    data,
                });
            }
        }
    }

    // 资源：manifest 中全部图片/字体/CSS（含不在 spine 中的），供规范化拷贝
    let mut seen: HashSet<String> = resources.iter().map(|r| r.source_path.clone()).collect();
    for item in &opf.manifest {
        if is_navigation_item(item) {
            continue;
        }
        let is_resource = item.media_type.starts_with("image/")
            || item.media_type.starts_with("font/")
            || item.media_type == "text/css";
        if !is_resource {
            continue;
        }
        let full = join_path(&opf_dir, &item.href);
        if seen.contains(&full) {
            continue;
        }
        if let Ok(data) = read_entry(&mut zip, &full) {
            seen.insert(full.clone());
            resources.push(Resource {
                source_path: full,
                media_type: item.media_type.clone(),
                data,
            });
        }
    }

    // 目录：nav 与 NCX 都解析，取条目多者（Gutenberg 等出版商会生成
    // 仅含许可证链接的 nav + 完整 NCX，此时用 NCX）。
    let toc_nav = if let Some(nav) = opf.manifest.iter().find(|i| i.properties.contains("nav")) {
        if let Ok(bytes) = read_entry(&mut zip, &join_path(&opf_dir, &nav.href)) {
            parse_nav_xhtml(&String::from_utf8_lossy(&bytes))
        } else {
            Vec::new()
        }
    } else {
        Vec::new()
    };
    let toc_ncx = parse_ncx(&mut zip, &opf_dir, &opf);
    let toc = if toc_ncx.len() > toc_nav.len() {
        toc_ncx
    } else {
        toc_nav
    };

    Ok(ParsedBook {
        format: Format::Epub,
        title: opf.title,
        authors: opf.authors,
        language: opf.language,
        chapters,
        toc,
        resources,
    })
}

// ---------- 内部结构 ----------

struct ManifestItem {
    id: String,
    href: String,
    media_type: String,
    properties: String,
}

struct Opf {
    title: String,
    authors: Vec<String>,
    language: Option<String>,
    manifest: Vec<ManifestItem>,
    spine: Vec<String>,
}

impl Opf {
    fn parse(xml: &str) -> Result<Opf> {
        let mut reader = Reader::from_str(xml);
        reader.config_mut().trim_text(true);

        let mut opf = Opf {
            title: String::new(),
            authors: Vec::new(),
            language: None,
            manifest: Vec::new(),
            spine: Vec::new(),
        };
        let mut in_title = false;
        let mut in_creator = false;
        let mut in_language = false;
        let mut cur_text = String::new();

        loop {
            match reader.read_event() {
                Ok(Event::Start(e)) => match e.name().into_inner() {
                    "dc:title" => {
                        in_title = true;
                        cur_text.clear();
                    }
                    "dc:creator" => {
                        in_creator = true;
                        cur_text.clear();
                    }
                    "dc:language" => {
                        in_language = true;
                        cur_text.clear();
                    }
                    _ => {}
                },
                Ok(Event::Text(e)) => {
                    if in_title || in_creator || in_language {
                        cur_text.push_str(e.into_inner().as_ref());
                    }
                }
                Ok(Event::End(e)) => match e.name().into_inner() {
                    "dc:title" => {
                        opf.title = cur_text.trim().to_string();
                        in_title = false;
                    }
                    "dc:creator" => {
                        let t = cur_text.trim();
                        if !t.is_empty() {
                            opf.authors.push(t.to_string());
                        }
                        in_creator = false;
                    }
                    "dc:language" => {
                        opf.language = Some(cur_text.trim().to_string());
                        in_language = false;
                    }
                    _ => {}
                },
                Ok(Event::Empty(e)) => {
                    let name = e.name().into_inner();
                    if name == "item" {
                        let mut id = None;
                        let mut href = None;
                        let mut mt = None;
                        let mut props = String::new();
                        for attr in e.attributes().flatten() {
                            let key = attr.key.as_ref();
                            let value = attr.value.as_ref().to_string();
                            match key {
                                "id" => id = Some(value),
                                "href" => href = Some(value),
                                "media-type" => mt = Some(value),
                                "properties" => props = value,
                                _ => {}
                            }
                        }
                        if let (Some(id), Some(href), Some(mt)) = (id, href, mt) {
                            opf.manifest.push(ManifestItem {
                                id,
                                href,
                                media_type: mt,
                                properties: props,
                            });
                        }
                    } else if name == "itemref" {
                        for attr in e.attributes().flatten() {
                            if attr.key.as_ref() == "idref" {
                                opf.spine.push(attr.value.as_ref().to_string());
                            }
                        }
                    }
                }
                Ok(Event::Eof) => break,
                Err(_) => break,
                _ => {}
            }
        }
        Ok(opf)
    }
}

// ---------- 工具函数 ----------

fn read_entry(zip: &mut ZipArchive<std::fs::File>, name: &str) -> std::io::Result<Vec<u8>> {
    let mut entry = zip.by_name(name)?;
    let mut buf = Vec::with_capacity(entry.size() as usize);
    entry.read_to_end(&mut buf)?;
    Ok(buf)
}

fn extract_opf_path(container: &str) -> Option<String> {
    let mut reader = Reader::from_str(container);
    loop {
        match reader.read_event() {
            Ok(Event::Empty(e)) if e.name().into_inner() == "rootfile" => {
                for attr in e.attributes().flatten() {
                    if attr.key.as_ref() == "full-path" {
                        return Some(attr.value.as_ref().to_string());
                    }
                }
            }
            Ok(Event::Eof) => return None,
            Err(_) => return None,
            _ => {}
        }
    }
}

fn opf_dir(opf_path: &str) -> String {
    match opf_path.rfind('/') {
        Some(idx) => opf_path[..idx].to_string(),
        None => String::new(),
    }
}

fn join_path(dir: &str, name: &str) -> String {
    if dir.is_empty() {
        name.to_string()
    } else {
        format!("{dir}/{name}")
    }
}

fn is_navigation_item(item: &ManifestItem) -> bool {
    let href = item.href.to_ascii_lowercase();
    href.ends_with(".ncx") || href.ends_with("nav.xhtml") || item.properties.contains("nav")
}

/// 从 href 文件名推导章节标题（无 h1-h3 时兜底）
fn chapter_title_from_href(href: &str) -> String {
    let base = href.rsplit('/').next().unwrap_or(href);
    let stem = base.split('.').next().unwrap_or(base);
    if stem.is_empty() {
        "未命名章节".to_string()
    } else {
        stem.to_string()
    }
}

/// HTML → 纯文本：段落/标题/换行转 \n，去标签；跳过 script/style。
pub fn html_to_text(html: &str) -> String {
    let mut reader = Reader::from_str(html);
    reader.config_mut().trim_text(true);
    let mut out = String::with_capacity(html.len() / 2);
    let mut skip_depth = 0usize;

    loop {
        match reader.read_event() {
            Ok(Event::Start(e)) => {
                let name = e.name().into_inner();
                if matches!(name, "script" | "style") {
                    skip_depth += 1;
                } else if is_block_tag(name) {
                    out.push('\n');
                }
            }
            Ok(Event::End(e)) => {
                let name = e.name().into_inner();
                if matches!(name, "script" | "style") {
                    skip_depth = skip_depth.saturating_sub(1);
                } else if is_block_tag(name) {
                    out.push('\n');
                }
            }
            Ok(Event::Text(e)) => {
                if skip_depth == 0 {
                    let t = e.into_inner();
                    out.push_str(t.trim());
                }
            }
            Ok(Event::CData(e)) => {
                if skip_depth == 0 {
                    out.push_str(e.into_inner().trim());
                }
            }
            Ok(Event::Eof) => break,
            Err(_) => break,
            _ => {}
        }
    }

    // 压缩多余空行
    let mut result = String::new();
    let mut prev_blank = true;
    for line in out.split('\n') {
        let line = line.trim();
        if line.is_empty() {
            if !prev_blank {
                result.push('\n');
            }
            prev_blank = true;
        } else {
            if !result.is_empty() && !result.ends_with('\n') {
                result.push('\n');
            }
            result.push_str(line);
            prev_blank = false;
        }
    }
    result.trim().to_string()
}

fn is_block_tag(name: &str) -> bool {
    matches!(
        name,
        "p" | "div"
            | "br"
            | "h1"
            | "h2"
            | "h3"
            | "h4"
            | "h5"
            | "h6"
            | "li"
            | "blockquote"
            | "tr"
            | "table"
            | "section"
            | "article"
            | "pre"
    )
}

/// 取第一个标题（h1-h3 / title）作为章节名
fn first_heading(html: &str) -> Option<String> {
    let mut reader = Reader::from_str(html);
    reader.config_mut().trim_text(true);
    loop {
        match reader.read_event() {
            Ok(Event::Start(e)) => {
                let name = e.name().into_inner();
                if matches!(name, "h1" | "h2" | "h3" | "title") {
                    let mut text = String::new();
                    loop {
                        match reader.read_event() {
                            Ok(Event::Text(t)) => {
                                text.push_str(t.into_inner().as_ref());
                            }
                            Ok(Event::End(ee)) if ee.name().into_inner() == name => break,
                            Ok(Event::Eof) => break,
                            Err(_) => break,
                            _ => {}
                        }
                    }
                    let t = text.trim();
                    if !t.is_empty() {
                        return Some(t.to_string());
                    }
                }
            }
            Ok(Event::Eof) => return None,
            Err(_) => return None,
            _ => {}
        }
    }
}

/// 解析 EPUB3 nav.xhtml（ol/li/a）→ 扁平目录（depth 记录层级）
fn parse_nav_xhtml(nav: &str) -> Vec<TocEntry> {
    let mut reader = Reader::from_str(nav);
    reader.config_mut().trim_text(true);
    let mut toc = Vec::new();
    let mut current_href: Option<String> = None;
    let mut current_text = String::new();
    let mut in_a = false;
    let mut ol_depth = 0usize;

    loop {
        match reader.read_event() {
            Ok(Event::Start(e)) => match e.name().into_inner() {
                "ol" => ol_depth += 1,
                "a" => {
                    in_a = true;
                    current_text.clear();
                    for attr in e.attributes().flatten() {
                        if attr.key.as_ref() == "href" {
                            current_href = Some(strip_fragment(attr.value.as_ref()));
                        }
                    }
                }
                _ => {}
            },
            Ok(Event::Text(e)) => {
                if in_a {
                    current_text.push_str(e.into_inner().as_ref());
                }
            }
            Ok(Event::End(e)) => match e.name().into_inner() {
                "ol" => ol_depth = ol_depth.saturating_sub(1),
                "a" => {
                    in_a = false;
                    let title = current_text.trim();
                    if !title.is_empty() {
                        if let Some(href) = current_href.clone() {
                            toc.push(TocEntry {
                                title: title.to_string(),
                                href,
                                depth: ol_depth.saturating_sub(1).min(8) as u8,
                            });
                        }
                    }
                }
                _ => {}
            },
            Ok(Event::Eof) => break,
            Err(_) => break,
            _ => {}
        }
    }
    toc
}

/// 解析 NCX（EPUB2 兜底）
fn parse_ncx(
    zip: &mut ZipArchive<std::fs::File>,
    opf_dir: &str,
    opf: &Opf,
) -> Vec<TocEntry> {
    let Some(ncx_item) = opf
        .manifest
        .iter()
        .find(|i| i.href.to_ascii_lowercase().ends_with(".ncx"))
    else {
        return Vec::new();
    };
    let Ok(bytes) = read_entry(zip, &join_path(opf_dir, &ncx_item.href)) else {
        return Vec::new();
    };
    let ncx = String::from_utf8_lossy(&bytes);
    let mut reader = Reader::from_str(&ncx);
    reader.config_mut().trim_text(true);
    let mut toc = Vec::new();
    let mut in_nav_label = false;
    let mut label_text = String::new();
    let mut cur_href: Option<String> = None;
    let mut depth = 0u8;

    loop {
        match reader.read_event() {
            Ok(Event::Start(e)) => match e.name().into_inner() {
                "navPoint" => depth += 1,
                "text" => in_nav_label = true,
                "content" => {
                    for attr in e.attributes().flatten() {
                        if attr.key.as_ref() == "src" {
                            cur_href = Some(strip_fragment(attr.value.as_ref()));
                        }
                    }
                }
                _ => {}
            },
            Ok(Event::Text(e)) => {
                if in_nav_label {
                    label_text.push_str(e.into_inner().as_ref());
                }
            }
            Ok(Event::End(e)) => match e.name().into_inner() {
                "navPoint" => {
                    let title = label_text.trim();
                    if !title.is_empty() {
                        if let Some(href) = cur_href.clone() {
                            toc.push(TocEntry {
                                title: title.to_string(),
                                href,
                                depth: (depth.saturating_sub(1)).min(8),
                            });
                        }
                    }
                    label_text.clear();
                    cur_href = None;
                    depth = depth.saturating_sub(1);
                }
                "text" => in_nav_label = false,
                _ => {}
            },
            Ok(Event::Eof) => break,
            Err(_) => break,
            _ => {}
        }
    }
    toc
}

fn strip_fragment(href: &str) -> String {
    href.split('#').next().unwrap_or(href).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn html_to_text_paragraphs() {
        let html = "<html><body><h1>第一章</h1><p>你好，<b>世界</b>。</p><p>第二段。</p></body></html>";
        let text = html_to_text(html);
        assert!(text.contains("第一章"));
        assert!(text.contains("你好，世界。"));
        assert!(text.contains("第二段。"));
    }

    #[test]
    fn html_to_text_skips_script() {
        let html = "<p>正文</p><script>var x = 1;</script><p>继续</p>";
        let text = html_to_text(html);
        assert!(!text.contains("var x"));
        assert!(text.contains("正文"));
        assert!(text.contains("继续"));
    }
}
