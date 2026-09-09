//! 跨上下文共享类型（Shared Kernel）：`BookId` / `Locator` / `BookMeta` 等。
//!
//! 设计：docs/04-module-design.md §2.1（实体与值对象）、§3（Locator 锚定模型）。
//! 这些类型定义在一处，禁止各上下文自造同义类型。

use serde::{Deserialize, Serialize};

use crate::error::Result;

/// 书籍标识（uuid 字符串）
pub type BookId = String;

/// 统一位置锚定模型：跨格式、跨设备、重排不失效。
///
/// 定位优先级：`text`（文本片段锚，最稳）→ `progression`（章内/全书进度）
/// → `cfi`（EPUB CFI，冗余精确锚）；PDF 使用 `page` + `rect`。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Locator {
    pub book_id: BookId,
    /// 章/资源路径（规范 EPUB 内相对路径）
    pub href: String,
    /// 章内进度 0.0..=1.0
    pub progression: f32,
    /// 全书进度 0.0..=1.0（跨设备同步用）
    pub total_progression: f32,
    /// 文本片段锚（重排后重新模糊匹配）
    pub text: Option<TextAnchor>,
    /// EPUB CFI（冗余精确锚，reflow 专用）
    pub cfi: Option<String>,
    /// PDF：页码（1 起）
    pub page: Option<u32>,
    /// PDF：页面矩形（高亮锚定）
    pub rect: Option<Rect>,
}

/// 文本片段锚（最稳的定位依据）
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TextAnchor {
    /// 创建时的原文片段（8–40 字符）
    pub snippet: String,
    /// snippet 在章文本中的起始偏移
    pub start: u32,
    /// snippet 在章文本中的结束偏移
    pub end: u32,
}

/// PDF 页面矩形（归一化坐标 0..=1）
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub struct Rect {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
}

/// 书籍元数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BookMeta {
    pub title: String,
    pub authors: Vec<String>,
    pub language: Option<String>,
    // TODO(P0): cover / toc / spine
}

// ===================== REQ-003 · 翻译上下文（共享内核 + 跨层契约） =====================
// 契约与载荷类型落共享内核的原因见 ADR REQ-003 决策点3：
// ddd-lint 对 infrastructure 层（core/src/store）禁 `crate::dict` 等业务模块、不禁
// `crate::types`；规则表冻结零改动 → store 实现契约必须只依赖本文件。

/// 语言（翻译语言对；桥接层用字符串 "en"/"zh"/"auto"… 经 `as_str`/`parse` 互转）。
/// `Auto` 表示自动检测（UI 默认 from='auto'；DeepL 请求省略 source_lang）。
/// serde 手写（`Other(&'static str)` 无法派生 Deserialize），序列化为语言代码字符串。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Lang {
    Auto,
    En,
    Zh,
    Ja,
    Ko,
    Fr,
    De,
    Es,
    Ru,
    Other(&'static str),
}

impl Lang {
    pub fn as_str(&self) -> &str {
        match self {
            Lang::Auto => "auto",
            Lang::En => "en",
            Lang::Zh => "zh",
            Lang::Ja => "ja",
            Lang::Ko => "ko",
            Lang::Fr => "fr",
            Lang::De => "de",
            Lang::Es => "es",
            Lang::Ru => "ru",
            Lang::Other(s) => s,
        }
    }

    /// 未知代码 → None（api 层映射为 `Err(Other("不支持的语言代码: …"))`）
    pub fn parse(s: &str) -> Option<Lang> {
        match s.to_ascii_lowercase().as_str() {
            "auto" => Some(Lang::Auto),
            "en" => Some(Lang::En),
            "zh" => Some(Lang::Zh),
            "ja" => Some(Lang::Ja),
            "ko" => Some(Lang::Ko),
            "fr" => Some(Lang::Fr),
            "de" => Some(Lang::De),
            "es" => Some(Lang::Es),
            "ru" => Some(Lang::Ru),
            _ => None,
        }
    }
}

impl serde::Serialize for Lang {
    fn serialize<S: serde::Serializer>(&self, s: S) -> std::result::Result<S::Ok, S::Error> {
        s.serialize_str(self.as_str())
    }
}

impl<'de> serde::Deserialize<'de> for Lang {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> std::result::Result<Lang, D::Error> {
        let s = String::deserialize(d)?;
        Ok(Lang::parse(&s).unwrap_or(Lang::Other("other")))
    }
}

/// 译文值对象（translation_cache.result 列的 JSON 载荷；docs/04 §5）
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Translation {
    pub text: String,
    pub from: Lang,
    pub to: Lang,
    pub provider: String,
}

/// 缓存键：(原文归一化, 语言对, Provider) —— docs/04 §5 唯一索引语义
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct CacheKey {
    pub source_text: String,
    pub from_lang: Lang,
    pub to_lang: Lang,
    pub provider: String,
}

/// 缓存行（translation_cache 表）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheEntry {
    pub key: CacheKey,
    pub result: Translation,
    pub created_at: i64, // unix 秒
    pub hit_count: u64,
}

/// 翻译缓存仓储契约（domain 契约 → infrastructure 实现 → interface 装配注入）。
/// 实现见 `core/src/store/translation.rs`（TranslationRepo）。
pub trait TranslationCacheRepository {
    fn cache_get(&self, key: &CacheKey) -> Result<Option<CacheEntry>>;
    fn cache_put(&mut self, entry: &CacheEntry) -> Result<()>; // UPSERT，不重置 hit_count
    fn cache_incr_hit(&mut self, key: &CacheKey) -> Result<()>; // 命中 +1
    fn cache_clear(&mut self) -> Result<()>;
    fn cache_count(&self) -> Result<u64>; // US-13 行数断言
}

/// Provider 凭据/默认路由契约（settings 表等价通道；docs/04 §5 settings 表）。
/// 键约定：`translate.default_provider`（默认 "deepl"）、`translate.key.<provider>`。
pub trait ProviderConfig {
    fn default_provider(&self) -> Result<String>;
    fn provider_key(&self, provider: &str) -> Result<Option<String>>; // None → 未配置
    fn set_provider_key(&mut self, provider: &str, key: &str) -> Result<()>;
    fn set_default_provider(&mut self, provider: &str) -> Result<()>;
}

// ===================== REQ-009 · 笔记与全文搜索（共享内核 + 跨层契约） =====================
// 契约与载荷类型落共享内核的原因同 REQ-003：ddd-rules 对 infrastructure（core/src/store）
// 禁业务模块（locator/notes/search）但不禁 `crate::types`；故 store 实现契约只依赖本文件，
// domain（locator/notes/search）只依赖 trait（ADR REQ-009 D3）。

/// 笔记种类（`annotations.kind`；docs/04 §5）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum NoteKind {
    Highlight,
    Underline,
    Note,
    Bookmark,
}

impl NoteKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            NoteKind::Highlight => "highlight",
            NoteKind::Underline => "underline",
            NoteKind::Note => "note",
            NoteKind::Bookmark => "bookmark",
        }
    }

    pub fn parse(s: &str) -> Option<NoteKind> {
        match s {
            "highlight" => Some(NoteKind::Highlight),
            "underline" => Some(NoteKind::Underline),
            "note" => Some(NoteKind::Note),
            "bookmark" => Some(NoteKind::Bookmark),
            _ => None,
        }
    }
}

/// 选中文本 + 当前章内进度（`LocatorResolver::from_selection` 的入参，ADR D2）。
#[derive(Debug, Clone, PartialEq)]
pub struct TextSelection {
    pub snippet: String,
    pub progression: f32,
}

/// 笔记记录（`annotations` 表行；`locator` 含文本锚/进度）。
#[derive(Debug, Clone, PartialEq)]
pub struct Annotation {
    pub id: String,
    pub book_id: BookId,
    pub kind: NoteKind,
    pub color: Option<String>, // "#RRGGBB"
    pub locator: Locator,
    pub snippet: Option<String>,
    pub note_text: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
    pub sync_status: String, // "local"
}

/// 笔记局部更新（`None` = 不修改该字段）。
#[derive(Debug, Clone, Default, PartialEq)]
pub struct NotePatch {
    pub note_text: Option<String>,
    pub color: Option<String>,
    pub kind: Option<NoteKind>,
}

/// 导出格式（Markdown / JSON）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExportFormat {
    Markdown,
    Json,
}

impl ExportFormat {
    pub fn parse(s: &str) -> Option<Self> {
        match s.to_ascii_lowercase().as_str() {
            "markdown" | "md" => Some(ExportFormat::Markdown),
            "json" => Some(ExportFormat::Json),
            _ => None,
        }
    }

    pub fn ext(&self) -> &'static str {
        match self {
            ExportFormat::Markdown => "md",
            ExportFormat::Json => "json",
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            ExportFormat::Markdown => "markdown",
            ExportFormat::Json => "json",
        }
    }
}

/// 导出结果摘要。
#[derive(Debug, Clone, PartialEq)]
pub struct ExportSummary {
    pub path: String,
    pub note_count: u32,
    pub format: ExportFormat,
}

/// 按章节分组的笔记列表。
#[derive(Debug, Clone, PartialEq)]
pub struct NoteGroup {
    pub chapter_title: String,
    pub href: String,
    pub notes: Vec<Annotation>,
}

/// 分组方式（本期只实现 `Chapter`）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GroupBy {
    Chapter,
    None,
}

/// UTF-16 code unit 半开区间 `[start, end)`（与 Dart `String` 索引一致）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct TextRange {
    pub start: u32,
    pub end: u32,
}

/// 搜索命中（含上下文片段与关键词 UTF-16 区间）。
#[derive(Debug, Clone, PartialEq)]
pub struct SearchHit {
    pub book_id: BookId,
    pub book_title: String,
    pub href: String,
    pub chapter_title: String,
    pub snippet: String,
    pub ranges: Vec<TextRange>,
    pub score: Option<f64>,
}

/// 搜索范围（`book_id=None` = 全部书籍；`formats` 空 = 全部格式）。
#[derive(Debug, Clone, Default, PartialEq)]
pub struct SearchScope {
    pub book_id: Option<BookId>,
    pub formats: Vec<String>,
}

/// 待索引章节（`api.rs` 组装后交 `SearchService::index_book`）。
#[derive(Debug, Clone, PartialEq)]
pub struct IndexedChapter {
    pub href: String,
    pub chapter_title: String,
    pub text: String,
    pub text_bi: String,
}

/// 仓储查询行（JOIN books 后的原始结果）。
#[derive(Debug, Clone, PartialEq)]
pub struct SearchRow {
    pub book_id: BookId,
    pub book_title: String,
    pub href: String,
    pub chapter_title: String,
    pub text: String,
    pub score: Option<f64>,
}

/// 笔记仓储契约（domain → infrastructure 实现 → interface 装配注入）。
pub trait AnnotationRepository {
    fn insert(&mut self, a: &Annotation) -> Result<()>;
    fn update(&mut self, id: &str, patch: &NotePatch, now: i64) -> Result<()>;
    fn delete(&mut self, id: &str) -> Result<()>;
    fn delete_many(&mut self, ids: &[String]) -> Result<usize>;
    fn delete_all(&mut self, book_id: &str, kinds: Option<&[NoteKind]>) -> Result<usize>;
    fn list(&self, book_id: &str) -> Result<Vec<Annotation>>;
    fn get(&self, id: &str) -> Result<Option<Annotation>>;
    fn find_bookmark(
        &self,
        book_id: &str,
        href: &str,
        progression: f32,
    ) -> Result<Option<Annotation>>;
}

/// 搜索索引仓储契约（FTS5 短语查询 + 单字 CJK 子串回退，ADR D1）。
pub trait SearchIndexRepository {
    /// 事务：先删该书全部行，再逐章插入（幂等，重复索引不翻倍）。
    fn replace_book(&mut self, book_id: &str, chapters: &[IndexedChapter]) -> Result<()>;
    fn is_indexed(&self, book_id: &str) -> Result<bool>;
    fn remove_book(&mut self, book_id: &str) -> Result<()>;
    /// FTS5 短语查询（≥2 字 CJK / ASCII 词走此路）。
    fn query_fts(
        &self,
        match_expr: &str,
        scope: &SearchScope,
        limit: usize,
    ) -> Result<Vec<SearchRow>>;
    /// 子串回退（单字 CJK，FTS bigram 不覆盖）：`text LIKE '%needle%'`。
    fn query_substring(
        &self,
        needle: &str,
        scope: &SearchScope,
        limit: usize,
    ) -> Result<Vec<SearchRow>>;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn note_kind_parse_as_str_all_arms() {
        for k in [
            NoteKind::Highlight,
            NoteKind::Underline,
            NoteKind::Note,
            NoteKind::Bookmark,
        ] {
            assert_eq!(NoteKind::parse(k.as_str()), Some(k));
        }
        assert_eq!(NoteKind::parse("highlight"), Some(NoteKind::Highlight));
        assert_eq!(NoteKind::parse("underline"), Some(NoteKind::Underline));
        assert_eq!(NoteKind::parse("note"), Some(NoteKind::Note));
        assert_eq!(NoteKind::parse("bookmark"), Some(NoteKind::Bookmark));
        assert_eq!(NoteKind::parse("Highlight"), None, "kind 解析大小写敏感");
        assert_eq!(NoteKind::parse("nope"), None);
    }

    #[test]
    fn export_format_parse_ext_as_str_all_arms() {
        assert_eq!(ExportFormat::parse("markdown"), Some(ExportFormat::Markdown));
        assert_eq!(ExportFormat::parse("md"), Some(ExportFormat::Markdown));
        assert_eq!(ExportFormat::parse("MD"), Some(ExportFormat::Markdown));
        assert_eq!(ExportFormat::parse("json"), Some(ExportFormat::Json));
        assert_eq!(ExportFormat::parse("JSON"), Some(ExportFormat::Json));
        assert_eq!(ExportFormat::parse("pdf"), None);
        assert_eq!(ExportFormat::Markdown.ext(), "md");
        assert_eq!(ExportFormat::Json.ext(), "json");
        assert_eq!(ExportFormat::Markdown.as_str(), "markdown");
        assert_eq!(ExportFormat::Json.as_str(), "json");
    }

    #[test]
    fn lang_parse_as_str_all_arms() {
        for l in [
            Lang::Auto,
            Lang::En,
            Lang::Zh,
            Lang::Ja,
            Lang::Ko,
            Lang::Fr,
            Lang::De,
            Lang::Es,
            Lang::Ru,
        ] {
            assert_eq!(Lang::parse(l.as_str()), Some(l));
        }
        assert_eq!(Lang::parse("EN"), Some(Lang::En));
        assert_eq!(Lang::parse("ZH"), Some(Lang::Zh));
        assert_eq!(Lang::parse("xx"), None);
        assert_eq!(Lang::Other("xx").as_str(), "xx");
    }
}
