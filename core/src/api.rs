//! flutter_rust_bridge 对外 API（设计：docs/03-architecture.md §4）。
//!
//! 约定：函数签名即桥接契约，改动需同步更新 docs/03 §4 与 Dart 侧服务层。
//! 错误统一映射为 `String`（用户可读文案）。
//! REQ-003：新增 7 个 **async** 桥接函数（FRB 2.13 async，函数体为同步阻塞代码，
//! 在 FRB 内部线程池执行，UI 不阻塞 —— ADR 决策点1）；`library_open` 装配 DICT/TRANSLATION
//! 双单例（两 trait 各持一个 TranslationRepo 第二连接，WAL + busy_timeout，迁移幂等）。

use std::path::Path;
use std::sync::{Mutex, OnceLock};

use crate::dict::{DeepLProvider, DictService, EchoProvider, TranslationService};
use crate::error::Result;
use crate::library::LibraryService;
use crate::store::TranslationRepo;
use crate::store::{BookRecord, Store};
use crate::types::{Lang, ProviderConfig, TranslationCacheRepository};

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

// ---------- REQ-003 桥接数据结构（FRB 生成面） ----------

/// 已安装词库信息（US-7；docs/03 §4 原 Result<()>，ADR 关联裁定4 修正）
#[derive(Debug)]
pub struct DictInfoView {
    pub id: String,
    pub name: String,
    pub word_count: u64,
    pub path: String,
}

/// 词条视图（US-1/16）
#[derive(Debug)]
pub struct DictEntryView {
    pub word: String,
    pub phonetic: Option<String>,
    pub pos: Option<String>,
    pub definition: String,
    pub example: Option<String>,
}

/// 译文视图（from_cache 标注缓存命中，US-10/13）
#[derive(Debug)]
pub struct TranslationView {
    pub text: String,
    pub from: String,
    pub to: String,
    pub provider: String,
    pub from_cache: bool,
}

// ---------- 全局服务（进程内单例） ----------

static SERVICE: OnceLock<Mutex<LibraryService>> = OnceLock::new();
static DICT: OnceLock<Mutex<DictService>> = OnceLock::new();
static TRANSLATION: OnceLock<Mutex<TranslationService>> = OnceLock::new();

fn service() -> std::result::Result<&'static Mutex<LibraryService>, String> {
    SERVICE
        .get()
        .ok_or_else(|| "书库未初始化：请先调用 library_open".to_string())
}

fn dict_service() -> std::result::Result<&'static Mutex<DictService>, String> {
    DICT.get()
        .ok_or_else(|| "词库未初始化：请先调用 library_open".to_string())
}

fn translation_service() -> std::result::Result<&'static Mutex<TranslationService>, String> {
    TRANSLATION
        .get()
        .ok_or_else(|| "翻译未初始化：请先调用 library_open".to_string())
}

fn err_msg<E: std::fmt::Display>(e: E) -> String {
    e.to_string()
}

// ---------- 书库 API ----------

/// 打开（或创建）书库，指定数据目录。应用启动时调用一次。
/// 装配：SERVICE（既有）+ DICT/TRANSLATION 双单例（REQ-003 02-design §4.1）。
pub fn library_open(data_dir: String) -> std::result::Result<(), String> {
    let store = Store::open(Path::new(&data_dir)).map_err(err_msg)?;
    let _ = SERVICE.set(Mutex::new(LibraryService::new(store)));

    let cache_repo =
        Box::new(TranslationRepo::open(Path::new(&data_dir)).map_err(err_msg)?)
            as Box<dyn TranslationCacheRepository + Send>;
    let config_repo = Box::new(TranslationRepo::open(Path::new(&data_dir)).map_err(err_msg)?)
        as Box<dyn ProviderConfig + Send>;
    let _ = DICT.set(Mutex::new(DictService::new(Path::new(&data_dir)).map_err(err_msg)?));
    let _ = TRANSLATION.set(Mutex::new(TranslationService::new(
        cache_repo,
        config_repo,
        vec![Box::new(DeepLProvider::new()), Box::new(EchoProvider)],
    )));
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

/// 取规范 EPUB 中某章节的原始 HTML（WebView 分页渲染用，REQ-001）
pub fn book_chapter_html(id: String, href: String) -> std::result::Result<String, String> {
    let svc = service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    svc.chapter_html(&id, &href).map_err(err_msg)
}

/// 取规范 EPUB 中某资源（图片/CSS/字体）的字节
pub fn book_resource(id: String, path: String) -> std::result::Result<Vec<u8>, String> {
    let svc = service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    svc.resource(&id, &path).map_err(err_msg)
}

/// 阅读进度视图（桥接）
pub struct ProgressView {
    pub href: String,
    pub progression: f32,
}

/// 保存阅读进度（href + 章内进度 0..1）
pub fn progress_save(id: String, href: String, progression: f32) -> std::result::Result<(), String> {
    let mut svc = service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    svc.save_progress(&id, &href, progression).map_err(err_msg)
}

/// 读取阅读进度（无记录返回 None）
pub fn progress_get(id: String) -> std::result::Result<Option<ProgressView>, String> {
    let svc = service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    let rec = svc.load_progress(&id).map_err(err_msg)?;
    Ok(rec.map(|r| ProgressView {
        href: r.href,
        progression: r.progression,
    }))
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

// ---------- REQ-003 词典与翻译桥接（全部 async；FRB 池线程执行，UI 不阻塞） ----------

/// 安装词库（入参为 .ifo 路径或含 .ifo 的目录）；返回 DictInfoView（US-7）
pub async fn dict_install(path: String) -> std::result::Result<DictInfoView, String> {
    let mut svc = dict_service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    let info = svc.install(Path::new(&path)).map_err(err_msg)?;
    Ok(DictInfoView {
        id: info.id,
        name: info.name,
        word_count: info.word_count,
        path: info.path,
    })
}

/// 移除词库
pub async fn dict_remove(dict_id: String) -> std::result::Result<(), String> {
    let mut svc = dict_service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    svc.remove(&dict_id).map_err(err_msg)
}

/// 已装词库列表（安装顺序）
pub async fn dict_list() -> std::result::Result<Vec<DictInfoView>, String> {
    let svc = dict_service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    let list = svc.list().map_err(err_msg)?;
    Ok(list
        .into_iter()
        .map(|i| DictInfoView {
            id: i.id,
            name: i.name,
            word_count: i.word_count,
            path: i.path,
        })
        .collect())
}

/// 查词：Ok(Some(DictEntryView)) 命中 / Ok(None) 未收录（US-2）/ Err（无词库 US-3、损坏 US-6）
pub async fn dict_lookup(
    word: String,
    dict_id: Option<String>,
) -> std::result::Result<Option<DictEntryView>, String> {
    let svc = dict_service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    let entry = svc.lookup(&word, dict_id.as_deref()).map_err(err_msg)?;
    Ok(entry.map(|e| DictEntryView {
        word: e.word,
        phonetic: e.phonetic,
        pos: e.pos,
        definition: e.definition,
        example: e.example,
    }))
}

/// 翻译：缓存优先；命中 from_cache=true（US-10/13）；未配置/网络失败给明确错误（US-12）
pub async fn translate(
    text: String,
    from: String,
    to: String,
) -> std::result::Result<TranslationView, String> {
    let from_lang = Lang::parse(&from)
        .ok_or_else(|| format!("不支持的语言代码: {from}"))?;
    let to_lang = Lang::parse(&to).ok_or_else(|| format!("不支持的语言代码: {to}"))?;
    let mut svc = translation_service()?
        .lock()
        .map_err(|_| "服务锁错误".to_string())?;
    let (t, from_cache) = svc.translate_cached(&text, from_lang, to_lang).map_err(err_msg)?;
    Ok(TranslationView {
        text: t.text,
        from: t.from.as_str().to_string(),
        to: t.to.as_str().to_string(),
        provider: t.provider,
        from_cache,
    })
}

/// 一键清空翻译缓存（US-13 / docs/04 领域规则4）
pub async fn translate_cache_clear() -> std::result::Result<(), String> {
    let mut svc = translation_service()?
        .lock()
        .map_err(|_| "服务锁错误".to_string())?;
    svc.clear_cache().map_err(err_msg)
}

/// Provider 最小配置通道：写 settings + 对注册 Provider 调 configure
/// （`translate_set_config("echo", "")` 即无 key 演示，ADR 关联裁定2）
pub async fn translate_set_config(
    provider: String,
    key: String,
) -> std::result::Result<(), String> {
    let mut svc = translation_service()?
        .lock()
        .map_err(|_| "服务锁错误".to_string())?;
    svc.set_config(&provider, &key).map_err(err_msg)
}

// 供 Rust 侧测试引用（避免 dead_code 告警）
#[allow(dead_code)]
fn _unused_result_type() -> Result<()> {
    Ok(())
}
