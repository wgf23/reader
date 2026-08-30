//! 跨上下文共享类型（Shared Kernel）：`BookId` / `Locator` / `BookMeta` 等。
//!
//! 设计：docs/04-module-design.md §2.1（实体与值对象）、§3（Locator 锚定模型）。
//! 这些类型定义在一处，禁止各上下文自造同义类型。

use serde::{Deserialize, Serialize};

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

// TODO(P0): TextSelection / NoteKind / Settings / DictEntry / Translation …
//           见 docs/04-module-design.md §2 与 §7。
