//! flutter_rust_bridge 对外 API（设计：docs/03-architecture.md §4）。
//!
//! 约定：函数签名即桥接契约，改动需同步更新 docs/03 §4 与 Dart 侧服务层。
//! 错误统一映射为 `String`（用户可读文案）。
//! REQ-003：新增 7 个 **async** 桥接函数（FRB 2.13 async，函数体为同步阻塞代码，
//! 在 FRB 内部线程池执行，UI 不阻塞 —— ADR 决策点1）；`library_open` 装配 DICT/TRANSLATION
//! 双单例（两 trait 各持一个 TranslationRepo 第二连接，WAL + busy_timeout，迁移幂等）。

use std::collections::HashMap;
use std::path::Path;
use std::sync::{Mutex, OnceLock};

use crate::dict::{DeepLProvider, DictService, EchoProvider, OfflineProvider, TranslationService};
use crate::error::{Error, Result};
use crate::library::LibraryService;
use crate::locator::LocatorResolver;
use crate::notes::AnnotationService;
use crate::search::{bigram_index_text, SearchService};
use crate::store::{AnnotationRepo, BookRecord, SearchIndexRepo, Store, TranslationRepo};
use crate::tts;
use crate::types::{
    Annotation, AnnotationRepository, ExportFormat, IndexedChapter, Lang, Locator, NoteGroup,
    NoteKind, NotePatch, ProviderConfig, SearchHit, SearchIndexRepository, SearchScope, TextAnchor,
    TextSelection, TranslationCacheRepository,
};

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
    /// 章/资源路径（REQ-009：搜索定位/笔记锚点用；规范 EPUB 内相对路径）
    pub href: String,
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

/// 译文视图（from_cache 标注缓存命中，US-10/13；fallback_reason REQ-006 US-17/18）
#[derive(Debug)]
pub struct TranslationView {
    pub text: String,
    pub from: String,
    pub to: String,
    pub provider: String,
    pub from_cache: bool,
    /// 回退原因（如"在线失败，已回退离线"）；未回退为 None。
    pub fallback_reason: Option<String>,
}

/// 翻译配置视图（REQ-006 决策点2，US-15；**绝不返回明文 key**）
#[derive(Debug)]
pub struct TranslateConfigView {
    /// "auto" | "offline" | "deepl" | "echo"（= default_provider）
    pub provider: String,
    /// `DeepLProvider::key_is_missing` 语义（空串=false）
    pub has_deepl_key: bool,
    /// 固定掩码 `••••••••`；无 key 为 None；绝不返回明文。
    pub deepl_key_masked: Option<String>,
}

// ---------- REQ-005 听书桥接数据结构（FRB 生成面；ADR 决策点1b/6） ----------

/// 句级位置视图（不暴露领域 `Locator` 的 `Rect/cfi/page`）
#[derive(Debug, Clone)]
pub struct LocatorView {
    pub book_id: String,
    pub href: String,
    /// 章内进度 0..=1
    pub progression: f32,
    /// 全书进度 0..=1（本期=章内近似，仅展示）
    pub total_progression: f32,
    /// 文本锚片段（`TextAnchor.snippet`；无文本锚为 None）
    pub snippet: Option<String>,
}

/// 朗读句子块视图（字段与 Dart `SentenceChunk` 一一对应）
#[derive(Debug, Clone)]
pub struct SentenceChunkView {
    /// 章内句序号（0 起，供 `TtsSentenceDone(index)` 回传）
    pub index: u32,
    pub text: String,
    /// UTF-16 code unit，半开区间 `[start, end)`
    pub char_start: u32,
    pub char_end: u32,
    pub locator: LocatorView,
}

/// 听书设置视图（settings 表三键的类型化投影）
#[derive(Debug, Clone)]
pub struct ListenSettingsView {
    pub voice_id: String,
    /// 0.5..=3.0
    pub speed: f32,
    pub auto_next: bool,
}

// ---------- REQ-009 笔记与搜索桥接数据结构（FRB 生成面；ADR D10） ----------

/// 选中文本 + 当前章内进度（笔记锚点解析入参）
pub struct TextSelectionView {
    pub book_id: String,
    pub href: String,
    pub text: String,
    pub progression: f32,
}

/// 笔记视图（字段与 Dart `AnnotationData` 一一对应）
pub struct AnnotationView {
    pub id: String,
    pub book_id: String,
    pub kind: String,
    pub color: Option<String>,
    pub href: String,
    pub progression: f32,
    pub snippet: Option<String>,
    pub note_text: Option<String>,
    pub start: Option<u32>,
    pub end: Option<u32>,
    pub created_at: i64,
    pub updated_at: i64,
    pub sync_status: String,
}

/// 按章节分组的笔记视图
pub struct NoteGroupView {
    pub chapter_title: String,
    pub href: String,
    pub notes: Vec<AnnotationView>,
}

/// 笔记局部更新视图
pub struct NotePatchView {
    pub note_text: Option<String>,
    pub color: Option<String>,
    pub kind: Option<String>,
}

/// 书签切换结果视图
pub struct BookmarkToggleView {
    pub bookmarked: bool,
    pub note_id: Option<String>,
}

/// UTF-16 半开区间视图
pub struct RangeView {
    pub start: u32,
    pub end: u32,
}

/// 搜索命中视图
pub struct SearchHitView {
    pub book_id: String,
    pub book_title: String,
    pub href: String,
    pub chapter_title: String,
    pub snippet: String,
    pub ranges: Vec<RangeView>,
    pub score: Option<f64>,
}

/// 搜索范围视图（`all_books=true` 时忽略 `book_id`）
pub struct SearchScopeView {
    pub all_books: bool,
    pub book_id: Option<String>,
    pub formats: Vec<String>,
}

/// 导出结果视图
pub struct ExportSummaryView {
    pub path: String,
    pub note_count: u32,
    pub format: String,
}

// ---------- 全局服务（进程内单例） ----------

static SERVICE: OnceLock<Mutex<LibraryService>> = OnceLock::new();
static DICT: OnceLock<Mutex<DictService>> = OnceLock::new();
static TRANSLATION: OnceLock<Mutex<TranslationService>> = OnceLock::new();
static NOTES: OnceLock<Mutex<AnnotationService>> = OnceLock::new();
static SEARCH: OnceLock<Mutex<SearchService>> = OnceLock::new();

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

fn notes_service() -> std::result::Result<&'static Mutex<AnnotationService>, String> {
    NOTES
        .get()
        .ok_or_else(|| "笔记未初始化：请先调用 library_open".to_string())
}

fn search_service() -> std::result::Result<&'static Mutex<SearchService>, String> {
    SEARCH
        .get()
        .ok_or_else(|| "搜索未初始化：请先调用 library_open".to_string())
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
    // 离线翻译 Provider：查词闭包锁定 DICT 静态（避免 domain→interface 依赖）
    let offline = OfflineProvider::new(Box::new(|word, dict_id| {
        let svc = dict_service().map_err(Error::Other)?;
        let svc = svc
            .lock()
            .map_err(|_| Error::Other("词典锁错误".to_string()))?;
        svc.lookup(word, dict_id)
    }));
    let _ = TRANSLATION.set(Mutex::new(TranslationService::new(
        cache_repo,
        config_repo,
        vec![
            Box::new(offline),          // 默认（内置词库离线翻译，开箱即用）
            Box::new(DeepLProvider::new()),
            Box::new(EchoProvider),
        ],
    )));

    // REQ-009：笔记/搜索单例（各自第二连接；契约在 types，实现在 store）。
    let ann_repo = Box::new(AnnotationRepo::open(Path::new(&data_dir)).map_err(err_msg)?)
        as Box<dyn AnnotationRepository + Send>;
    let idx_repo = Box::new(SearchIndexRepo::open(Path::new(&data_dir)).map_err(err_msg)?)
        as Box<dyn SearchIndexRepository + Send>;
    let _ = NOTES.set(Mutex::new(AnnotationService::new(ann_repo)));
    let _ = SEARCH.set(Mutex::new(SearchService::new(idx_repo)));
    Ok(())
}

/// 导入一个书籍文件（解析 → 规范 EPUB 缓存 → 入库 + 建搜索索引），返回书库条目。
pub fn library_import(path: String) -> std::result::Result<BookSummary, String> {
    let rec = {
        let mut svc = service()?.lock().map_err(|_| "服务锁错误".to_string())?;
        svc.import_file(Path::new(&path)).map_err(err_msg)?
    };
    // REQ-009 D5：导入即索引（US-21）；失败不阻断导入，搜索时懒回填。
    let _ = ensure_indexed(&rec.id);
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
                href: c.href.clone(),
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
    // REQ-006：策略路由（auto 在线优先→回退离线），带回 fallback_reason。
    let routed = svc
        .translate_routed(&text, from_lang, to_lang)
        .map_err(err_msg)?;
    Ok(TranslationView {
        text: routed.translation.text,
        from: routed.translation.from.as_str().to_string(),
        to: routed.translation.to.as_str().to_string(),
        provider: routed.translation.provider,
        from_cache: routed.from_cache,
        fallback_reason: routed.fallback_reason,
    })
}

/// 读取当前翻译配置（策略 + 是否已配置 DeepL key + 固定掩码；US-15）
pub async fn translate_get_config() -> std::result::Result<TranslateConfigView, String> {
    let svc = translation_service()?
        .lock()
        .map_err(|_| "服务锁错误".to_string())?;
    let cfg = svc.config_view().map_err(err_msg)?;
    Ok(TranslateConfigView {
        provider: cfg.provider,
        has_deepl_key: cfg.has_deepl_key,
        // 只回填固定掩码，绝不回传明文 key（决策点2）。
        deepl_key_masked: if cfg.has_deepl_key {
            Some("••••••••".to_string())
        } else {
            None
        },
    })
}

/// 设置翻译策略（"auto"/"offline"/"deepl"/"echo"）；未知 → Err("未知翻译策略: {s}")（US-15）
pub async fn translate_set_strategy(strategy: String) -> std::result::Result<(), String> {
    let mut svc = translation_service()?
        .lock()
        .map_err(|_| "服务锁错误".to_string())?;
    svc.set_strategy(&strategy).map_err(err_msg)
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

// ---------- REQ-005 听书桥接（全部 async；FRB 池线程执行，UI 不阻塞） ----------

/// 经 `LibraryService::open_book` 按 href 取章节纯文本（interface 层可 `use crate::library`）。
fn chapter_text(id: &str, href: &str) -> std::result::Result<String, String> {
    let svc = service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    let opened = svc.open_book(id).map_err(err_msg)?;
    opened
        .chapters
        .into_iter()
        .find(|c| c.href == href)
        .map(|c| c.text)
        .ok_or_else(|| format!("章节不存在: {href}"))
}

fn to_locator_view(loc: &Locator) -> LocatorView {
    LocatorView {
        book_id: loc.book_id.clone(),
        href: loc.href.clone(),
        progression: loc.progression,
        total_progression: loc.total_progression,
        snippet: loc.text.as_ref().map(|t| t.snippet.clone()),
    }
}

/// 章文本 → 句列表（US-4/US-7；index 为章内句序号）
pub async fn tts_segment(
    book_id: String,
    href: String,
) -> std::result::Result<Vec<SentenceChunkView>, String> {
    let text = chapter_text(&book_id, &href)?;
    let chunks = tts::segment(&text, &book_id, &href).map_err(err_msg)?;
    Ok(chunks
        .iter()
        .enumerate()
        .map(|(i, c)| SentenceChunkView {
            index: i as u32,
            text: c.text.clone(),
            char_start: c.char_range.0,
            char_end: c.char_range.1,
            locator: to_locator_view(&c.locator),
        })
        .collect())
}

/// 句索引 → Locator（US-5；越界/章节不存在 → Err）
pub async fn tts_locator_for_sentence(
    book_id: String,
    href: String,
    idx: u32,
) -> std::result::Result<LocatorView, String> {
    let text = chapter_text(&book_id, &href)?;
    let loc =
        tts::locator_for_sentence(&text, &book_id, &href, idx as usize).map_err(err_msg)?;
    Ok(to_locator_view(&loc))
}

/// Locator → 句索引（US-6；api 层重建 domain `Locator` 后调用 domain 函数）
pub async fn tts_sentence_index_at(
    book_id: String,
    href: String,
    locator: LocatorView,
) -> std::result::Result<u32, String> {
    let text = chapter_text(&book_id, &href)?;
    let loc = Locator {
        book_id: locator.book_id,
        href: locator.href,
        progression: locator.progression,
        total_progression: locator.total_progression,
        text: locator.snippet.map(|snippet| TextAnchor {
            snippet,
            start: 0,
            end: 0,
        }),
        cfi: None,
        page: None,
        rect: None,
    };
    let idx = tts::sentence_index_at(&text, &book_id, &href, &loc).map_err(err_msg)?;
    Ok(idx as u32)
}

/// 听书设置键与默认值（ADR 决策点6）
const KEY_VOICE_ID: &str = "listen.voice_id";
const KEY_SPEED: &str = "listen.speed";
const KEY_AUTO_NEXT: &str = "listen.auto_next";
const DEFAULT_VOICE_ID: &str = "system_male";
const DEFAULT_SPEED: f32 = 1.0;

/// 读取听书设置（缺省 `system_male/1.0/true`；speed clamp `[0.5,3.0]`）
pub async fn tts_listen_settings_get() -> std::result::Result<ListenSettingsView, String> {
    let svc = service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    let voice_id = svc
        .get_setting(KEY_VOICE_ID)
        .map_err(err_msg)?
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_VOICE_ID.to_string());
    let speed = svc
        .get_setting(KEY_SPEED)
        .map_err(err_msg)?
        .and_then(|s| s.parse::<f32>().ok())
        .unwrap_or(DEFAULT_SPEED)
        .clamp(0.5, 3.0);
    let auto_next = svc
        .get_setting(KEY_AUTO_NEXT)
        .map_err(err_msg)?
        .map(|s| s == "1")
        .unwrap_or(true);
    Ok(ListenSettingsView {
        voice_id,
        speed,
        auto_next,
    })
}

/// 写入听书设置（speed 落库前 clamp `[0.5,3.0]`）
pub async fn tts_listen_settings_set(
    settings: ListenSettingsView,
) -> std::result::Result<(), String> {
    let mut svc = service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    let voice_id = if settings.voice_id.trim().is_empty() {
        DEFAULT_VOICE_ID.to_string()
    } else {
        settings.voice_id
    };
    svc.set_setting(KEY_VOICE_ID, &voice_id).map_err(err_msg)?;
    let speed = if settings.speed.is_finite() {
        settings.speed.clamp(0.5, 3.0)
    } else {
        DEFAULT_SPEED
    };
    svc.set_setting(KEY_SPEED, &speed.to_string()).map_err(err_msg)?;
    svc.set_setting(KEY_AUTO_NEXT, if settings.auto_next { "1" } else { "0" })
        .map_err(err_msg)?;
    Ok(())
}

// ---------- REQ-009 笔记与搜索桥接（全部 async；FRB 池线程执行，UI 不阻塞） ----------

fn to_annotation_view(a: &Annotation) -> AnnotationView {
    AnnotationView {
        id: a.id.clone(),
        book_id: a.book_id.clone(),
        kind: a.kind.as_str().to_string(),
        color: a.color.clone(),
        href: a.locator.href.clone(),
        progression: a.locator.progression,
        snippet: a.snippet.clone(),
        note_text: a.note_text.clone(),
        start: a.locator.text.as_ref().map(|t| t.start),
        end: a.locator.text.as_ref().map(|t| t.end),
        created_at: a.created_at,
        updated_at: a.updated_at,
        sync_status: a.sync_status.clone(),
    }
}

fn to_group_view(g: &NoteGroup) -> NoteGroupView {
    NoteGroupView {
        chapter_title: g.chapter_title.clone(),
        href: g.href.clone(),
        notes: g.notes.iter().map(to_annotation_view).collect(),
    }
}

fn to_hit_view(h: &SearchHit) -> SearchHitView {
    SearchHitView {
        book_id: h.book_id.clone(),
        book_title: h.book_title.clone(),
        href: h.href.clone(),
        chapter_title: h.chapter_title.clone(),
        snippet: h.snippet.clone(),
        ranges: h
            .ranges
            .iter()
            .map(|r| RangeView {
                start: r.start,
                end: r.end,
            })
            .collect(),
        score: h.score,
    }
}

/// href → 章节标题映射（笔记面板分组用）。
fn chapter_titles(book_id: &str) -> std::result::Result<HashMap<String, String>, String> {
    let svc = service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    let opened = svc.open_book(book_id).map_err(err_msg)?;
    Ok(opened
        .chapters
        .into_iter()
        .map(|c| (c.href, c.title))
        .collect())
}

/// 书名（导出头部用）。
fn book_title_of(book_id: &str) -> std::result::Result<String, String> {
    let svc = service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    Ok(svc.open_book(book_id).map_err(err_msg)?.record.title)
}

/// 组装待索引章节（open_book + domain `bigram_index_text`）。
fn indexed_chapters(book_id: &str) -> std::result::Result<Vec<IndexedChapter>, String> {
    let svc = service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    let opened = svc.open_book(book_id).map_err(err_msg)?;
    Ok(opened
        .chapters
        .into_iter()
        .map(|c| {
            let text_bi = bigram_index_text(&c.text);
            IndexedChapter {
                href: c.href,
                chapter_title: c.title,
                text: c.text,
                text_bi,
            }
        })
        .collect())
}

/// 懒回填：未索引则 `open_book` + `index_book`（每书一次，US-23）。
fn ensure_indexed(book_id: &str) -> std::result::Result<(), String> {
    {
        let idx = search_service()?.lock().map_err(|_| "搜索锁错误".to_string())?;
        if idx.is_indexed(book_id).map_err(err_msg)? {
            return Ok(());
        }
    }
    let chapters = indexed_chapters(book_id)?;
    let mut idx = search_service()?.lock().map_err(|_| "搜索锁错误".to_string())?;
    idx.index_book(book_id, &chapters).map_err(err_msg)
}

fn domain_scope(scope: &SearchScopeView) -> SearchScope {
    SearchScope {
        book_id: if scope.all_books {
            None
        } else {
            scope.book_id.clone()
        },
        formats: scope.formats.clone(),
    }
}

/// scope 内书籍 id 列表（懒回填用）。
fn books_in_scope(scope: &SearchScope) -> std::result::Result<Vec<String>, String> {
    let svc = service()?.lock().map_err(|_| "服务锁错误".to_string())?;
    let books = svc.list().map_err(err_msg)?;
    Ok(books
        .into_iter()
        .filter(|b| {
            scope
                .book_id
                .as_deref()
                .map(|id| id == b.id)
                .unwrap_or(true)
                && (scope.formats.is_empty()
                    || scope
                        .formats
                        .iter()
                        .any(|f| f.eq_ignore_ascii_case(&b.format)))
        })
        .map(|b| b.id)
        .collect())
}

/// 创建笔记（高亮/划线/批注）：章全文 → 文本锚 → 落库（US-1/2/3）。
pub async fn notes_create(
    book_id: String,
    href: String,
    text: String,
    progression: f32,
    kind: String,
    color: Option<String>,
    note_text: Option<String>,
) -> std::result::Result<AnnotationView, String> {
    let k = NoteKind::parse(&kind).ok_or_else(|| format!("未知笔记类型: {kind}"))?;
    let chapter = chapter_text(&book_id, &href)?;
    let loc = LocatorResolver::from_selection(
        &chapter,
        &book_id,
        &href,
        &TextSelection {
            snippet: text,
            progression,
        },
    )
    .map_err(err_msg)?;
    let mut svc = notes_service()?
        .lock()
        .map_err(|_| "服务锁错误".to_string())?;
    let a = svc
        .create(&book_id, loc, k, color, note_text)
        .map_err(err_msg)?;
    Ok(to_annotation_view(&a))
}

/// 更新笔记（批注文本/颜色/kind）。
pub async fn notes_update(
    note_id: String,
    patch: NotePatchView,
) -> std::result::Result<(), String> {
    let kind = match patch.kind {
        Some(s) => Some(NoteKind::parse(&s).ok_or_else(|| format!("未知笔记类型: {s}"))?),
        None => None,
    };
    let domain = NotePatch {
        note_text: patch.note_text,
        color: patch.color,
        kind,
    };
    let mut svc = notes_service()?
        .lock()
        .map_err(|_| "服务锁错误".to_string())?;
    svc.update(&note_id, &domain).map_err(err_msg)
}

pub async fn notes_delete(note_id: String) -> std::result::Result<(), String> {
    let mut svc = notes_service()?
        .lock()
        .map_err(|_| "服务锁错误".to_string())?;
    svc.delete(&note_id).map_err(err_msg)
}

pub async fn notes_delete_many(
    note_ids: Vec<String>,
) -> std::result::Result<u32, String> {
    let mut svc = notes_service()?
        .lock()
        .map_err(|_| "服务锁错误".to_string())?;
    svc.delete_many(&note_ids).map(|n| n as u32).map_err(err_msg)
}

pub async fn notes_delete_all(book_id: String) -> std::result::Result<u32, String> {
    let mut svc = notes_service()?
        .lock()
        .map_err(|_| "服务锁错误".to_string())?;
    svc.delete_all(&book_id)
        .map(|n| n as u32)
        .map_err(err_msg)
}

/// 列出该书笔记（按章节分组；含书签，US-6/14）。
pub async fn notes_list(
    book_id: String,
) -> std::result::Result<Vec<NoteGroupView>, String> {
    let titles = chapter_titles(&book_id)?;
    let svc = notes_service()?
        .lock()
        .map_err(|_| "服务锁错误".to_string())?;
    let groups = svc.list(&book_id, &titles).map_err(err_msg)?;
    Ok(groups.iter().map(to_group_view).collect())
}

/// 笔记 id → 位置（面板/书签跳转用）。
pub async fn notes_resolve(note_id: String) -> std::result::Result<LocatorView, String> {
    let svc = notes_service()?
        .lock()
        .map_err(|_| "服务锁错误".to_string())?;
    let loc = svc.resolve(&note_id).map_err(err_msg)?;
    Ok(to_locator_view(&loc))
}

/// 导出 Markdown / JSON；空笔记 → Err("暂无笔记")（US-16/17）。
pub async fn notes_export(
    book_id: String,
    fmt: String,
    out_path: String,
) -> std::result::Result<ExportSummaryView, String> {
    let format = ExportFormat::parse(&fmt).ok_or_else(|| format!("未知导出格式: {fmt}"))?;
    let titles = chapter_titles(&book_id)?;
    let book_title = book_title_of(&book_id)?;
    let svc = notes_service()?
        .lock()
        .map_err(|_| "服务锁错误".to_string())?;
    let groups = svc.list(&book_id, &titles).map_err(err_msg)?;
    let summary = svc
        .export(&book_title, &groups, format, Path::new(&out_path))
        .map_err(err_msg)?;
    Ok(ExportSummaryView {
        path: summary.path,
        note_count: summary.note_count,
        format: summary.format.as_str().to_string(),
    })
}

/// 幂等切换书签（US-14）。
pub async fn notes_toggle_bookmark(
    book_id: String,
    href: String,
    progression: f32,
    snippet: Option<String>,
) -> std::result::Result<BookmarkToggleView, String> {
    let p = if progression.is_finite() {
        progression.clamp(0.0, 1.0)
    } else {
        0.0
    };
    let loc = Locator {
        book_id: book_id.clone(),
        href,
        progression: p,
        total_progression: p,
        text: None,
        cfi: None,
        page: None,
        rect: None,
    };
    let mut svc = notes_service()?
        .lock()
        .map_err(|_| "服务锁错误".to_string())?;
    let (bookmarked, note_id) = svc
        .toggle_bookmark(&book_id, loc, snippet)
        .map_err(err_msg)?;
    Ok(BookmarkToggleView {
        bookmarked,
        note_id,
    })
}

/// 全文搜索（空查询短路；懒回填旧书；CJK bigram；US-18/19/20/21/23）。
pub async fn search(
    query: String,
    scope: SearchScopeView,
) -> std::result::Result<Vec<SearchHitView>, String> {
    if query.trim().is_empty() {
        return Ok(Vec::new());
    }
    let domain = domain_scope(&scope);
    // 懒回填（有界：每书至多一次；单书失败不阻断整体搜索）
    if let Ok(ids) = books_in_scope(&domain) {
        for id in ids {
            let _ = ensure_indexed(&id);
        }
    }
    let svc = search_service()?
        .lock()
        .map_err(|_| "服务锁错误".to_string())?;
    let hits = svc.query(&query, &domain).map_err(err_msg)?;
    Ok(hits.iter().map(to_hit_view).collect())
}

// 供 Rust 侧测试引用（避免 dead_code 告警）
#[allow(dead_code)]
fn _unused_result_type() -> Result<()> {
    Ok(())
}
