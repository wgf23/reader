//! 书库服务：导入（解析→规范化→入库）/ 列表 / 打开（章节）。
//!
//! 设计：docs/04-module-design.md §4、§6（导入状态机：Pending→Parsing→Converting→Ready|Failed）。
//! 去重：按源文件内容 SHA-256（领域规则 §8）。

use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

use crate::error::{Error, Result};
use crate::format::{self, Chapter, ParsedBook};
use crate::store::{BookRecord, Store};

/// 打开的书（供阅读器使用）
#[derive(Debug, Clone)]
pub struct OpenedBook {
    pub record: BookRecord,
    pub chapters: Vec<Chapter>,
}

pub struct LibraryService {
    pub store: Store,
}

impl LibraryService {
    pub fn new(store: Store) -> Self {
        LibraryService { store }
    }

    /// 导入一个文件：嗅探格式 → 解析 → 规范 EPUB 缓存 → 入库。
    /// 返回书籍记录；内容重复（同 hash）时返回既有记录（不重复入库）。
    pub fn import_file(&mut self, path: &Path) -> Result<BookRecord> {
        let hash = sha256_of_file(path)?;
        if let Some(existing) = self
            .store
            .list_books()?
            .into_iter()
            .find(|b| b.source_hash == hash)
        {
            return Ok(existing);
        }

        let parsed = format::parse(path)?;
        let id = format!("bk_{}", &hash[..16]);
        let canonical_path = self.canonicalize_cached(&hash, &parsed)?;

        let record = BookRecord {
            id,
            title: parsed.title.clone(),
            authors: parsed.authors.clone(),
            language: parsed.language.clone(),
            source_path: path.display().to_string(),
            source_hash: hash,
            format: parsed.format.name().to_string(),
            canonical_path: Some(canonical_path.display().to_string()),
            added_at: 0,
        };
        self.store.insert_book(&record)?;
        Ok(record)
    }

    /// 规范 EPUB 缓存：cache/<hash>.epub，命中直接复用
    fn canonicalize_cached(&self, hash: &str, parsed: &ParsedBook) -> Result<PathBuf> {
        let path = self.store.cache_dir().join(format!("{hash}.epub"));
        if !path.exists() {
            crate::convert::BookCanonicalizer::canonicalize(parsed, &path)?;
        }
        Ok(path)
    }

    pub fn list(&self) -> Result<Vec<BookRecord>> {
        self.store.list_books()
    }

    /// 打开书：读取规范 EPUB 缓存并解析出章节（含纯文本）。
    pub fn open_book(&self, id: &str) -> Result<OpenedBook> {
        let record = self.store.get_book(id)?;
        let canonical = record
            .canonical_path
            .as_ref()
            .ok_or_else(|| Error::Corrupt("书籍缺少规范缓存".into()))?;
        let parsed = format::parse(Path::new(canonical))?;
        Ok(OpenedBook {
            record,
            chapters: parsed.chapters,
        })
    }

    /// 读取规范 EPUB 中指定章节的原始 HTML（WebView 渲染用，REQ-001）
    pub fn chapter_html(&self, id: &str, href: &str) -> Result<String> {
        let canonical = self.canonical_path(id)?;
        crate::format::epub::chapter_html(&canonical, href)
    }

    /// 读取规范 EPUB 中指定资源字节（图片/CSS/字体）
    pub fn resource(&self, id: &str, name: &str) -> Result<Vec<u8>> {
        let canonical = self.canonical_path(id)?;
        crate::format::epub::resource(&canonical, name)
    }

    /// 保存阅读进度（复用 reading_progress，听读同进度不变式）
    pub fn save_progress(&mut self, id: &str, href: &str, progression: f32) -> Result<()> {
        self.store.save_progress(id, href, progression)
    }

    /// 读取阅读进度
    pub fn load_progress(&self, id: &str) -> Result<Option<crate::store::ProgressRecord>> {
        self.store.load_progress(id)
    }

    fn canonical_path(&self, id: &str) -> Result<std::path::PathBuf> {
        let record = self.store.get_book(id)?;
        record
            .canonical_path
            .map(std::path::PathBuf::from)
            .ok_or_else(|| Error::Corrupt("书籍缺少规范缓存".into()))
    }

    pub fn remove(&mut self, id: &str) -> Result<()> {
        self.store.remove_book(id)
    }
}

fn sha256_of_file(path: &Path) -> Result<String> {
    let bytes = std::fs::read(path).map_err(Error::Io)?;
    Ok(sha256_hex(&bytes))
}

fn sha256_hex(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    let mut s = String::with_capacity(64);
    for b in digest.iter() {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write_tmp_txt(dir: &Path, name: &str, content: &str) -> PathBuf {
        let p = dir.join(name);
        std::fs::write(&p, content).unwrap();
        p
    }

    #[test]
    fn import_txt_and_open() {
        let dir = tempfile::tempdir().unwrap();
        let store = Store::open(&dir.path().join("data")).unwrap();
        let mut svc = LibraryService::new(store);

        let txt = write_tmp_txt(
            dir.path(),
            "book.txt",
            "第一章 出发\n很久以前……\n第二章 归来\n故事结束。",
        );
        let record = svc.import_file(&txt).unwrap();
        assert_eq!(record.title, "book");
        assert_eq!(record.format, "txt");
        assert!(record.canonical_path.is_some());

        let opened = svc.open_book(&record.id).unwrap();
        assert_eq!(opened.chapters.len(), 2);
        assert!(opened.chapters[0].text.contains("很久以前"));
    }

    #[test]
    fn import_dedup() {
        let dir = tempfile::tempdir().unwrap();
        let store = Store::open(&dir.path().join("data")).unwrap();
        let mut svc = LibraryService::new(store);
        let p1 = write_tmp_txt(dir.path(), "a.txt", "内容一样");
        let p2 = write_tmp_txt(dir.path(), "b.txt", "内容一样");
        let r1 = svc.import_file(&p1).unwrap();
        let r2 = svc.import_file(&p2).unwrap();
        assert_eq!(r1.id, r2.id); // 同内容 → 同书
        assert_eq!(svc.list().unwrap().len(), 1);
    }

    #[test]
    fn import_corrupt_fails_cleanly() {
        let dir = tempfile::tempdir().unwrap();
        let store = Store::open(&dir.path().join("data")).unwrap();
        let mut svc = LibraryService::new(store);
        let bad = write_tmp_txt(dir.path(), "bad.epub", "这不是 zip");
        let err = svc.import_file(&bad).unwrap_err();
        assert!(matches!(err, Error::Corrupt(_)));
    }

    #[test]
    fn progress_and_chapter_html_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let store = Store::open(&dir.path().join("data")).unwrap();
        let mut svc = LibraryService::new(store);
        let txt = write_tmp_txt(dir.path(), "p.txt", "第一章 甲\n内容\n第二章 乙\n更多");
        let rec = svc.import_file(&txt).unwrap();

        // 章节 HTML 可读（规范缓存）
        let html = svc.chapter_html(&rec.id, "chapter_0001.xhtml").unwrap();
        assert!(html.contains("第一章"));
        assert!(svc.chapter_html(&rec.id, "no_such.xhtml").is_err());

        // 资源读取：TXT 书无资源 → NotFound
        assert!(svc.resource(&rec.id, "images/x.jpg").is_err());

        // 进度保存/读取往返
        svc.save_progress(&rec.id, "chapter_0002.xhtml", 0.42)
            .unwrap();
        let p = svc.load_progress(&rec.id).unwrap().expect("应有进度");
        assert_eq!(p.href, "chapter_0002.xhtml");
        assert!((p.progression - 0.42).abs() < 1e-4);

        // 覆盖保存（UPSERT 单行）
        svc.save_progress(&rec.id, "chapter_0001.xhtml", 0.9)
            .unwrap();
        let p2 = svc.load_progress(&rec.id).unwrap().unwrap();
        assert_eq!(p2.href, "chapter_0001.xhtml");
        assert!((p2.progression - 0.9).abs() < 1e-4);
    }
}
