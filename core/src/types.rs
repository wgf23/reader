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

// TODO(P0): TextSelection / NoteKind / Settings / DictEntry / Translation …
//           见 docs/04-module-design.md §2 与 §7。
