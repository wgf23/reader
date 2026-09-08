//! 听书（TTS）：句级切分 + 句 ↔ Locator 映射 + 音色/语速参数。
//!
//! 设计：docs/02-technical.md §11（TTS 方案）、docs/04-module-design.md §9（领域设计）。
//! 约定：合成与播放**不**在本模块（走 Flutter 侧 `TtsEngine`，见 app/lib/engines/tts_engine.dart）；
//! 本模块只负责文本切分与"听读同一进度"的位置换算（"脑子"）。
//!
//! REQ-005（ADR 决策点1a/1b）：三个函数改为**文本入参**（domain 纯函数，只 `use crate::types`），
//! 由 interface 层 `api.rs` 经 `LibraryService::open_book` 取章文本后调用。
//! `char_range`/`TextAnchor.start/end` 统一使用 **UTF-16 code unit 半开区间 `[start, end)`**，
//! 与 Dart `String` 索引一致（US-17 高亮可直接 `substring`）。

use crate::types::{BookId, Locator, TextAnchor};

/// 朗读句子块（切句粒度 = 句子）
#[derive(Debug, Clone)]
pub struct SentenceChunk {
    pub text: String,
    /// 在章文本中的字符区间（UTF-16 code unit，半开 `[start, end)`）
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

/// 对章文本按句子切分（中文标点 。！？；… 与段落边界，保持引号/书名号完整）。
///
/// 规则见 docs/04 §9.4 规则2 / ADR 决策点1(b)：
/// 1. 句末定界 `。！？；…` 与 ASCII `.!?;`；段落边界 `\n`/`\r\n` 强制断句；
/// 2. 定界符后紧跟的收尾引号/括号并入本句；
/// 3. 连续 `……`/`...` 视为一个定界整体；
/// 4. ASCII `.` 仅在"前一个非空白为字母且后一个为空白/串尾且非缩写、非数字间"时断句；
/// 5. `char_range_i = [start_i, start_{i+1})` 连续不重叠，末句 `end = utf16_len`；
/// 6. 空/纯空白文本返回 `Ok(vec![])`；超长无标点整段作为一句。
pub fn segment(text: &str, book_id: &BookId, href: &str) -> Result<Vec<SentenceChunk>, TtsError> {
    if text.trim().is_empty() {
        return Ok(Vec::new());
    }
    let (chars, total) = char_table(text);
    if chars.is_empty() {
        return Ok(Vec::new());
    }
    let starts = sentence_starts(&chars);
    let mut out: Vec<SentenceChunk> = Vec::new();
    for (idx, &(bs, us)) in starts.iter().enumerate() {
        let be = starts.get(idx + 1).map(|s| s.0).unwrap_or(text.len());
        let ue = starts.get(idx + 1).map(|s| s.1).unwrap_or(total);
        let trimmed = text[bs..be].trim();
        if trimmed.is_empty() {
            // 理论不可达（starts 均为非空白起点）；兜底保持区间连续。
            if let Some(last) = out.last_mut() {
                last.char_range.1 = ue;
                if let Some(anchor) = last.locator.text.as_mut() {
                    anchor.end = ue;
                }
            }
            continue;
        }
        let snippet = utf16_prefix(trimmed, 40);
        let progression = if total == 0 {
            0.0
        } else {
            (us as f32 / total as f32).clamp(0.0, 1.0)
        };
        let locator = Locator {
            book_id: book_id.clone(),
            href: href.to_string(),
            progression,
            // 本期无全书权重：total_progression 取章内近似，仅展示（ADR 关联裁定6）
            total_progression: progression,
            text: Some(TextAnchor {
                snippet,
                start: us,
                end: ue,
            }),
            cfi: None,
            page: None,
            rect: None,
        };
        out.push(SentenceChunk {
            text: trimmed.to_string(),
            char_range: (us, ue),
            locator,
        });
    }
    Ok(out)
}

/// 第 `idx` 句的 Locator（`0 <= idx < N`，否则 `Err`）。
pub fn locator_for_sentence(
    text: &str,
    book_id: &BookId,
    href: &str,
    idx: usize,
) -> Result<Locator, TtsError> {
    let chunks = segment(text, book_id, href)?;
    chunks
        .into_iter()
        .nth(idx)
        .map(|c| c.locator)
        .ok_or_else(|| TtsError::Other(format!("句子索引越界: {idx}")))
}

/// Locator 落在哪一句（听读进度互转）。
///
/// 返回满足 `progression_i <= loc.progression` 的最大 `i`：
/// 章首 `0.0 → 0`，章末 `1.0 → N-1`；`href`/`book_id` 不匹配、`progression` 为
/// NaN/<0/>1、空文本 → `Err`（不 panic）。
pub fn sentence_index_at(
    text: &str,
    book_id: &BookId,
    href: &str,
    loc: &Locator,
) -> Result<usize, TtsError> {
    if loc.book_id.as_str() != book_id.as_str() {
        return Err(TtsError::Other(format!(
            "book_id 不匹配: {} != {}",
            loc.book_id, book_id
        )));
    }
    if loc.href != href {
        return Err(TtsError::Other(format!(
            "href 不匹配: {} != {href}",
            loc.href
        )));
    }
    let p = loc.progression;
    if !p.is_finite() || !(0.0..=1.0).contains(&p) {
        return Err(TtsError::Other(format!("非法 progression: {p}")));
    }
    let chunks = segment(text, book_id, href)?;
    if chunks.is_empty() {
        return Err(TtsError::Other("空文本无句子".to_string()));
    }
    let mut best: Option<usize> = None;
    for (i, c) in chunks.iter().enumerate() {
        if c.locator.progression <= p + 1e-6 {
            best = Some(i);
        } else {
            break;
        }
    }
    best.ok_or_else(|| TtsError::Other(format!("progression 落在首句之前: {p}")))
}

// ===================== 内部辅助 =====================

/// 章文本字符表：字符 + 字节起点 + UTF-16 起点
struct Ch {
    c: char,
    byte: usize,
    utf16: u32,
}

fn char_table(text: &str) -> (Vec<Ch>, u32) {
    let mut out = Vec::new();
    let mut u = 0u32;
    for (b, c) in text.char_indices() {
        out.push(Ch {
            c,
            byte: b,
            utf16: u,
        });
        u += c.len_utf16() as u32;
    }
    (out, u)
}

fn utf16_prefix(s: &str, max: usize) -> String {
    let mut out = String::new();
    let mut n = 0usize;
    for c in s.chars() {
        let l = c.len_utf16();
        if n + l > max {
            break;
        }
        out.push(c);
        n += l;
    }
    out
}

/// 硬定界符（不含 `…`/`.`，二者单独处理）
fn is_hard_end(c: char) -> bool {
    matches!(c, '。' | '！' | '？' | '；' | '!' | '?' | ';')
}

/// 可并入前句的收尾引号/括号
fn is_closing(c: char) -> bool {
    matches!(
        c,
        '」' | '』' | '”' | '’' | '）' | ')' | '】' | '》' | '〉' | ']' | '}' | '］' | '｝'
            | '〕' | '〗' | '〙' | '〛' | '›' | '»'
    )
}

/// 常见英文缩写（小写、含内部点），避免句点误切
const ABBREVIATIONS: &[&str] = &[
    "e.g", "i.e", "mr", "mrs", "ms", "dr", "no", "vs", "etc", "st", "jr", "sr", "prof", "inc",
    "ltd", "co", "u.s", "a.m", "p.m", "fig", "vol", "ch", "sec", "approx", "dept", "est", "cf",
    "al", "ed",
];

fn is_abbreviation(word: &str) -> bool {
    if ABBREVIATIONS.contains(&word.to_ascii_lowercase().as_str()) {
        return true;
    }
    // 单大写字母缩写（姓名首字母，如 `J.`）
    let mut it = word.chars();
    matches!((it.next(), it.next()), (Some(c), None) if c.is_ascii_uppercase())
}

/// 句点前的"词"（字母/数字/内部点）
fn word_before(chars: &[Ch], dot: usize) -> String {
    let mut start = dot;
    while start > 0 {
        let c = chars[start - 1].c;
        if c.is_ascii_alphanumeric() || c == '.' {
            start -= 1;
        } else {
            break;
        }
    }
    chars[start..dot].iter().map(|c| c.c).collect()
}

fn is_ascii_period_end(chars: &[Ch], i: usize) -> bool {
    let prev = (0..i).rev().find_map(|k| {
        let c = chars[k].c;
        if c.is_whitespace() {
            None
        } else {
            Some(c)
        }
    });
    let Some(prev) = prev else { return false };
    if !prev.is_alphabetic() {
        return false;
    }
    match chars.get(i + 1) {
        None => {}
        Some(n) if n.c.is_whitespace() => {}
        _ => return false,
    }
    !is_abbreviation(&word_before(chars, i))
}

/// 若 `chars[i]` 是句末定界符，返回该定界整体最后一个字符的下标。
/// `……`/`...` 整体处理；`.` 走缩写/数字判定；`\n`/`\r` 段落边界也断句。
fn delimiter_end(chars: &[Ch], i: usize) -> Option<usize> {
    let c = chars[i].c;
    if c == '…' {
        let mut j = i;
        while j + 1 < chars.len() && chars[j + 1].c == '…' {
            j += 1;
        }
        return Some(j);
    }
    if c == '.' {
        if i + 1 < chars.len() && chars[i + 1].c == '.' {
            let mut j = i;
            while j + 1 < chars.len() && chars[j + 1].c == '.' {
                j += 1;
            }
            return Some(j);
        }
        return is_ascii_period_end(chars, i).then_some(i);
    }
    (is_hard_end(c) || c == '\n' || c == '\r').then_some(i)
}

/// 求每句首个非空白字符的 (字节起点, UTF-16 起点)。
/// 首句固定从 0 起（含前导空白），保证 `progression_0 == 0.0`（章首语义）。
fn sentence_starts(chars: &[Ch]) -> Vec<(usize, u32)> {
    let mut starts = Vec::new();
    if chars.is_empty() {
        return starts;
    }
    starts.push((0, 0));
    let mut i = 0usize;
    while i < chars.len() {
        let Some(end) = delimiter_end(chars, i) else {
            i += 1;
            continue;
        };
        let mut j = end + 1;
        while j < chars.len() && is_closing(chars[j].c) {
            j += 1;
        }
        while j < chars.len() && chars[j].c.is_whitespace() {
            j += 1;
        }
        if j < chars.len() {
            starts.push((chars[j].byte, chars[j].utf16));
        }
        i = j;
    }
    starts
}

#[derive(Debug, thiserror::Error)]
pub enum TtsError {
    #[error("{0}")]
    Other(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bid() -> BookId {
        BookId::from("b1")
    }

    fn seg(text: &str) -> Vec<SentenceChunk> {
        segment(text, &bid(), "chapter_0001.xhtml").expect("切句应成功")
    }

    fn texts(chunks: &[SentenceChunk]) -> Vec<String> {
        chunks.iter().map(|c| c.text.clone()).collect()
    }

    // ---------- US-4：切句规则 ----------

    #[test]
    fn splits_chinese_punctuation_and_keeps_closing_quotes() {
        let chunks = seg("“你好。”他说。下一句！还有？");
        assert_eq!(
            texts(&chunks),
            vec!["“你好。”", "他说。", "下一句！", "还有？"]
        );
        // 引号成对保留
        assert!(chunks[0].text.starts_with('“') && chunks[0].text.ends_with('”'));
        // 区间连续不重叠
        for w in chunks.windows(2) {
            assert_eq!(w[0].char_range.1, w[1].char_range.0, "相邻区间必须连续");
        }
        assert_eq!(chunks.last().unwrap().char_range.1, 15);
    }

    #[test]
    fn does_not_merge_across_paragraphs() {
        let chunks = seg("第一段没有句号\n第二段有。\n\n第三段。");
        assert_eq!(
            texts(&chunks),
            vec!["第一段没有句号", "第二段有。", "第三段。"]
        );
        for w in chunks.windows(2) {
            assert_eq!(w[0].char_range.1, w[1].char_range.0);
        }
    }

    #[test]
    fn ellipsis_run_is_single_delimiter() {
        let chunks = seg("他说……然后走了。");
        assert_eq!(texts(&chunks), vec!["他说……", "然后走了。"]);
        let ascii = seg("Wait... then go.");
        assert_eq!(texts(&ascii), vec!["Wait...", "then go."]);
    }

    #[test]
    fn ascii_abbreviation_not_split() {
        let chunks = seg("Mr. Smith went home. He left.");
        assert_eq!(texts(&chunks), vec!["Mr. Smith went home.", "He left."]);
        let eg = seg("Use e.g. this one. Done.");
        assert_eq!(texts(&eg), vec!["Use e.g. this one.", "Done."]);
        let decimal = seg("圆周率是 3.14 左右。完。");
        assert_eq!(texts(&decimal), vec!["圆周率是 3.14 左右。", "完。"]);
    }

    #[test]
    fn empty_or_whitespace_returns_empty_vec() {
        assert!(seg("").is_empty());
        assert!(seg("   \n\t  ").is_empty());
    }

    #[test]
    fn long_run_without_punctuation_is_one_sentence() {
        let s = "啊".repeat(200);
        let chunks = seg(&s);
        assert_eq!(chunks.len(), 1);
        assert_eq!(chunks[0].text.chars().count(), 200);
    }

    #[test]
    fn char_range_uses_utf16_code_units() {
        // 😀 占 2 个 UTF-16 code unit
        let chunks = seg("😀你好。世界。");
        assert_eq!(chunks[0].char_range, (0, 5));
        assert_eq!(chunks[0].text, "😀你好。");
        assert_eq!(chunks[1].char_range, (5, 8));
        assert_eq!(chunks[1].text, "世界。");
    }

    // ---------- US-5：句 → Locator ----------

    #[test]
    fn locator_fields_and_monotonic_progression() {
        let text = "第一句。第二句。第三句。";
        let chunks = seg(text);
        let mut last = -1.0f32;
        for (i, c) in chunks.iter().enumerate() {
            let loc = locator_for_sentence(text, &bid(), "chapter_0001.xhtml", i).unwrap();
            assert_eq!(loc.book_id, "b1");
            assert_eq!(loc.href, "chapter_0001.xhtml");
            assert!((0.0..=1.0).contains(&loc.progression));
            assert!(loc.progression >= last, "progression 单调不减");
            last = loc.progression;
            let anchor = loc.text.expect("应有文本锚");
            assert!(c.text.starts_with(&anchor.snippet), "snippet 应为句前缀");
            assert_eq!(anchor.start, c.char_range.0);
            assert_eq!(anchor.end, c.char_range.1);
        }
        assert_eq!(chunks[0].locator.progression, 0.0);
        assert!(chunks.last().unwrap().locator.progression < 1.0);
    }

    #[test]
    fn locator_for_sentence_out_of_range_errors() {
        let text = "一句。";
        assert!(locator_for_sentence(text, &bid(), "chapter_0001.xhtml", 1).is_err());
        assert!(locator_for_sentence(text, &bid(), "chapter_0001.xhtml", 99).is_err());
        assert!(locator_for_sentence("", &bid(), "chapter_0001.xhtml", 0).is_err());
    }

    // ---------- US-6：Locator → 句索引 ----------

    #[test]
    fn roundtrip_index_at_locator_for_sentence() {
        let text = "第一句。第二句！第三句？第四句；";
        let chunks = seg(text);
        for i in 0..chunks.len() {
            let loc = locator_for_sentence(text, &bid(), "chapter_0001.xhtml", i).unwrap();
            let got = sentence_index_at(text, &bid(), "chapter_0001.xhtml", &loc).unwrap();
            assert_eq!(got, i, "往返映射应一致");
        }
    }

    #[test]
    fn sentence_index_at_boundaries() {
        let text = "第一句。第二句。第三句。";
        let chunks = seg(text);
        let n = chunks.len();
        let start = Locator {
            book_id: "b1".to_string(),
            href: "chapter_0001.xhtml".to_string(),
            progression: 0.0,
            total_progression: 0.0,
            text: None,
            cfi: None,
            page: None,
            rect: None,
        };
        assert_eq!(
            sentence_index_at(text, &bid(), "chapter_0001.xhtml", &start).unwrap(),
            0
        );
        let mut end = start.clone();
        end.progression = 1.0;
        assert_eq!(
            sentence_index_at(text, &bid(), "chapter_0001.xhtml", &end).unwrap(),
            n - 1
        );
        // 句间进度 → 包含该进度的句子
        let mid = chunks[1].locator.clone();
        assert_eq!(
            sentence_index_at(text, &bid(), "chapter_0001.xhtml", &mid).unwrap(),
            1
        );
    }

    #[test]
    fn sentence_index_at_rejects_bad_input() {
        let text = "一句。二句。";
        let mut loc = locator_for_sentence(text, &bid(), "chapter_0001.xhtml", 0).unwrap();
        // href 不匹配
        loc.href = "chapter_9999.xhtml".to_string();
        assert!(sentence_index_at(text, &bid(), "chapter_0001.xhtml", &loc).is_err());
        // book_id 不匹配
        loc.href = "chapter_0001.xhtml".to_string();
        loc.book_id = "b2".to_string();
        assert!(sentence_index_at(text, &bid(), "chapter_0001.xhtml", &loc).is_err());
        // NaN / 越界
        for p in [f32::NAN, -0.1, 1.1] {
            let bad = Locator {
                book_id: "b1".to_string(),
                href: "chapter_0001.xhtml".to_string(),
                progression: p,
                total_progression: p,
                text: None,
                cfi: None,
                page: None,
                rect: None,
            };
            assert!(
                sentence_index_at(text, &bid(), "chapter_0001.xhtml", &bad).is_err(),
                "非法 progression 应 Err: {p}"
            );
        }
        // 空文本
        assert!(sentence_index_at("", &bid(), "chapter_0001.xhtml", &loc).is_err());
    }

    // ---------- US-8：性能预算 ----------

    #[test]
    fn segment_100k_chars_under_budget() {
        // 约 11.25 万 UTF-16 code unit（>10 万字）
        let text = "这是一个测试句子。".repeat(12_500);
        assert!(text.chars().count() > 100_000);
        let start = std::time::Instant::now();
        let chunks = seg(&text);
        let elapsed = start.elapsed();
        eprintln!(
            "[US-8 基准] segment {} 字 / {} 句耗时 {:?}",
            text.chars().count(),
            chunks.len(),
            elapsed
        );
        assert!(chunks.len() > 1000);
        assert!(
            elapsed.as_millis() <= 200,
            "segment 应 ≤200ms（CI 上限），实测 {elapsed:?}"
        );
    }
}
