//! flutter_rust_bridge 对外 API（设计：docs/03-architecture.md §4）。
//!
//! 约定：函数签名即桥接契约，改动需同步更新 docs/03 §4 与 Dart 侧服务层。
//! 错误统一映射为 `String`（用户可读文案）。

use std::path::Path;
use std::sync::{Mutex, OnceLock};

use crate::error::Result;
use crate::library::LibraryService;
use crate::store::{BookRecord, Store};

// ---------- 桥接数据结构 ----------

/// 书架条目
pub struct BookSummary {
    pub id: String,
    pub title: String,
    pub authors: Vec<String>,
    pub language: Option<String>,
    pub format: String,
}

/// 章节视图（阅读器用）
pub struct ChapterView {
    pub title: String,
    pub text: String,
}

/// 打开的书（元数据 + 全部章节纯文本）
pub struct BookView {
    pub id: String,
    pub title: String,
    pub chapters: Vec<ChapterView>,
}

// ---------- 全局服务（进程内单例） ----------

static SERVICE: OnceLock<Mutex<LibraryService>> = OnceLock::new();

fn service() -> std::result::Result<&'static Mutex<LibraryService>, String> {
    SERVICE
        .get()
        .ok_or_else(|| "书库未初始化：请先调用 library_open".to_string())
}

fn err_msg<E: std::fmt::Display>(e: E) -> String {
    e.to_string()
}

// ---------- 书库 API ----------

/// 打开（或创建）书库，指定数据目录。应用启动时调用一次。
pub fn library_open(data_dir: String) -> std::result::Result<(), String> {
    let store = Store::open(Path::new(&data_dir)).map_err(err_msg)?;
    let _ = SERVICE.set(Mutex::new(LibraryService::new(store)));
    Ok(())
}

/// 导入一个书籍文件（解析 → 规范 EPUB 缓存 → 入库），返回书库条目。
pub fn library_import(path: String) -> std::result::Result<BookSummary, String> {
    let mut svc = service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    let rec = svc.import_file(Path::new(&path)).map_err(err_msg)?;
    Ok(to_summary(&rec))
}

/// 书架列表（按添加时间倒序）
pub fn library_list() -> std::result::Result<Vec<BookSummary>, String> {
    let svc = service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    let books = svc.list().map_err(err_msg)?;
    Ok(books.iter().map(to_summary).collect())
}

/// 删除书籍
pub fn library_remove(id: String) -> std::result::Result<(), String> {
    let mut svc = service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    svc.remove(&id).map_err(err_msg)
}

/// 打开书：返回元数据与全部章节文本（P0 滚动模式直接渲染）
pub fn book_open(id: String) -> std::result::Result<BookView, String> {
    let svc = service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    let opened = svc.open_book(&id).map_err(err_msg)?;
    Ok(BookView {
        id: opened.record.id.clone(),
        title: opened.record.title.clone(),
        chapters: opened
            .chapters
            .iter()
            .map(|c| ChapterView {
                title: c.title.clone(),
                text: c.text.clone(),
            })
            .collect(),
    })
}

// ---------- 内部 ----------

fn to_summary(rec: &BookRecord) -> BookSummary {
    BookSummary {
        id: rec.id.clone(),
        title: rec.title.clone(),
        authors: rec.authors.clone(),
        language: rec.language.clone(),
        format: rec.format.clone(),
    }
}

// 供 Rust 侧测试引用（避免 dead_code 告警）
#[allow(dead_code)]
fn _unused_result_type() -> Result<()> {
    Ok(())
}
