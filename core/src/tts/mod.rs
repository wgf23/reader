//! 听书（TTS）：句级切分 + 句 ↔ Locator 映射 + 音色/语速参数。
//!
//! 设计：docs/02-technical.md §11（TTS 方案）、docs/04-module-design.md §9（领域设计）。
//! 约定：合成与播放**不**在本模块（走 Flutter 侧 `TtsEngine`，见 app/lib/engines/tts_engine.dart）；
//! 本模块只负责文本切分与"听读同一进度"的位置换算（"脑子"）。

use crate::types::{BookId, Locator};

/// 朗读句子块（切句粒度 = 句子）
#[derive(Debug, Clone)]
pub struct SentenceChunk {
    pub text: String,
    /// 在章文本中的字符区间
    pub char_range: (u32, u32),
    /// 句 ↔ 位置映射（听读进度统一）
    pub locator: Locator,
}

/// 音色来源
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VoiceKind {
    /// 系统 TTS（默认，离线，零体积）
    System,
    /// 本地神经音色（Piper，P2 按需下载）
    Local,
    /// 在线 AI 音色（火山/Azure，P2，显式授权）
    Online,
}

/// 音色信息
#[derive(Debug, Clone)]
pub struct VoiceInfo {
    pub id: String,
    pub name: String,
    pub kind: VoiceKind,
    pub lang: String,
}

/// 听书会话运行态（不入库，UI 侧持有）
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ListenState {
    Idle,
    Playing,
    Paused,
    Stopped,
    Interrupted,
}

/// 听书会话（运行态）
#[derive(Debug, Clone)]
pub struct ListenSession {
    pub book_id: BookId,
    pub chapter_href: String,
    pub sentence_idx: usize,
    pub speed: f32,
    pub voice_id: String,
    pub state: ListenState,
    pub timer: Option<u32>, // 定时分钟数
}

/// 对章文本按句子切分（中文标点 。！？；… 与段落边界，保持引号/书名号完整）
pub fn segment(_book_id: &BookId, _href: &str) -> Result<Vec<SentenceChunk>, TtsError> {
    // TODO(P1): docs/04 §9.5
    Err(TtsError::NotImplemented)
}

/// 第 idx 句的 Locator
pub fn locator_for_sentence(
    _book_id: &BookId,
    _href: &str,
    _idx: usize,
) -> Result<Locator, TtsError> {
    // TODO(P1)
    Err(TtsError::NotImplemented)
}

/// Locator 落在哪一句（听读进度互转）
pub fn sentence_index_at(
    _book_id: &BookId,
    _href: &str,
    _loc: &Locator,
) -> Result<usize, TtsError> {
    // TODO(P1)
    Err(TtsError::NotImplemented)
}

#[derive(Debug, thiserror::Error)]
pub enum TtsError {
    #[error("尚未实现（P1）")]
    NotImplemented,
    #[error("{0}")]
    Other(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn not_implemented_yet() {
        let id = BookId::from("b1");
        assert!(segment(&id, "chapter1.xhtml").is_err());
    }
}
