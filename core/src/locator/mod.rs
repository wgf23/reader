//! Locator 锚定：文本锚生成 / 重定位 / 降级链。
//!
//! 设计：docs/04-module-design.md §3；ADR REQ-009 D2。
//! 定位优先级：文本片段锚（重排不失效）→ progression → CFI；PDF：page + rect。
//!
//! `from_selection` 为纯函数（只 `use crate::types`/`crate::error`）：由 interface 层
//! `api.rs` 取章全文后调用；在章全文内按「空白折叠归一化」匹配选中片段，用当前章内
//! `progression` 消歧，输出 UTF-16 半开区间 `TextAnchor{start,end}`；无匹配则
//! `text=None` + `progression` 兜底（不静默丢失）。

use crate::error::{Error, Result};
use crate::types::{BookId, Locator, TextAnchor, TextSelection};

pub struct LocatorResolver;

impl LocatorResolver {
    /// 由选中片段 + 当前章内进度生成文本锚；无匹配 → `text=None`（progression 兜底）。
    pub fn from_selection(
        text: &str,
        book_id: &BookId,
        href: &str,
        sel: &TextSelection,
    ) -> Result<Locator> {
        let total = utf16_len(text);
        let fallback = |p: f32| Locator {
            book_id: book_id.clone(),
            href: href.to_string(),
            progression: p,
            total_progression: p,
            text: None,
            cfi: None,
            page: None,
            rect: None,
        };
        let snippet = sel.snippet.trim();
        if snippet.is_empty() {
            let p = clamp_progression(sel.progression);
            return Ok(fallback(p));
        }

        // 1) 归一化匹配（折叠空白，ASCII 小写），带 UTF-16 偏移映射
        let (norm_text, map) = normalize_with_map(text);
        let (norm_needle, _) = normalize_with_map(snippet);
        let hay: Vec<char> = norm_text.chars().collect();
        let needle: Vec<char> = norm_needle.chars().collect();
        let mut candidates: Vec<(u32, u32)> = Vec::new();
        for start in find_all(&hay, &needle) {
            let end = start + needle.len();
            if let (Some(s), Some(e)) = (map.get(start), map.get(end - 1)) {
                candidates.push((s.0, e.1));
            }
        }
        // 2) 归一化无命中 → 原始精确匹配兜底
        if candidates.is_empty() {
            let raw: Vec<char> = text.chars().collect();
            let raw_needle: Vec<char> = snippet.chars().collect();
            let mut u = 0u32;
            let mut offsets: Vec<u32> = Vec::with_capacity(raw.len() + 1);
            for c in &raw {
                offsets.push(u);
                u += c.len_utf16() as u32;
            }
            offsets.push(u);
            for start in find_all(&raw, &raw_needle) {
                candidates.push((offsets[start], offsets[start + raw_needle.len()]));
            }
        }

        if candidates.is_empty() {
            let p = clamp_progression(sel.progression);
            return Ok(fallback(p));
        }

        // 3) progression 消歧：score = |occ_start / len - progression|，取最小，并列取最早
        let target = clamp_progression(sel.progression);
        let mut best = candidates[0];
        let mut best_score = score_of(best.0, total, target);
        for &(s, e) in candidates.iter().skip(1) {
            let sc = score_of(s, total, target);
            if sc < best_score {
                best_score = sc;
                best = (s, e);
            }
        }
        let (start, end) = best;
        let progression = if total == 0 {
            0.0
        } else {
            (start as f32 / total as f32).clamp(0.0, 1.0)
        };
        Ok(Locator {
            book_id: book_id.clone(),
            href: href.to_string(),
            progression,
            total_progression: progression,
            text: Some(TextAnchor {
                snippet: snippet.to_string(),
                start,
                end,
            }),
            cfi: None,
            page: None,
            rect: None,
        })
    }

    /// 取锚点对应原文片段（面板/导出用；无文本锚或越界 → `Err`）。
    pub fn text_at(text: &str, loc: &Locator) -> Result<String> {
        let anchor = loc
            .text
            .as_ref()
            .ok_or_else(|| Error::Other("无文本锚，无法取原文".to_string()))?;
        if anchor.start > anchor.end {
            return Err(Error::Other("非法文本锚区间".to_string()));
        }
        utf16_slice(text, anchor.start, anchor.end)
            .ok_or_else(|| Error::Other("文本锚越界".to_string()))
    }
}

fn clamp_progression(p: f32) -> f32 {
    if p.is_finite() {
        p.clamp(0.0, 1.0)
    } else {
        0.0
    }
}

fn score_of(start: u32, total: u32, target: f32) -> f32 {
    if total == 0 {
        0.0
    } else {
        (start as f32 / total as f32 - target).abs()
    }
}

pub(crate) fn utf16_len(s: &str) -> u32 {
    s.chars().map(|c| c.len_utf16() as u32).sum()
}

/// 按 UTF-16 半开区间切片；越界返回 `None`。
pub(crate) fn utf16_slice(s: &str, start: u32, end: u32) -> Option<String> {
    let mut u = 0u32;
    let mut out = String::new();
    for c in s.chars() {
        let cs = u;
        let ce = u + c.len_utf16() as u32;
        if cs >= start && ce <= end {
            out.push(c);
        } else if cs >= end {
            break;
        }
        u = ce;
    }
    if u < end {
        return None;
    }
    Some(out)
}

/// 归一化：连续空白折叠为单个空格、ASCII 大写转小写；返回
/// `(归一化串, 每个输出字符的原文 UTF-16 [start,end) 映射)`。
fn normalize_with_map(text: &str) -> (String, Vec<(u32, u32)>) {
    let mut out = String::new();
    let mut map: Vec<(u32, u32)> = Vec::new();
    let mut u = 0u32;
    let mut pending_space = false;
    let mut started = false;
    for c in text.chars() {
        let start = u;
        let end = u + c.len_utf16() as u32;
        u = end;
        if c.is_whitespace() {
            if started {
                pending_space = true;
            }
            continue;
        }
        if pending_space {
            out.push(' ');
            map.push((start, start)); // 折叠空格零宽，指向当前字符起点
            pending_space = false;
        }
        if c.is_ascii_uppercase() {
            out.push(c.to_ascii_lowercase());
        } else {
            out.push(c);
        }
        map.push((start, end));
        started = true;
    }
    (out, map)
}

/// 在字符序列中查找全部出现位置（重叠也计入）。
fn find_all(hay: &[char], needle: &[char]) -> Vec<usize> {
    if needle.is_empty() || needle.len() > hay.len() {
        return Vec::new();
    }
    let mut out = Vec::new();
    for i in 0..=(hay.len() - needle.len()) {
        if hay[i..i + needle.len()] == *needle {
            out.push(i);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sel(snippet: &str, p: f32) -> TextSelection {
        TextSelection {
            snippet: snippet.to_string(),
            progression: p,
        }
    }

    #[test]
    fn unique_snippet_maps_correct_offsets() {
        let text = "很久以前，有一座山。他每天清晨散步。";
        let loc = LocatorResolver::from_selection(
            text,
            &"b1".to_string(),
            "c1.xhtml",
            &sel("有一座山", 0.0),
        )
        .unwrap();
        let a = loc.text.clone().expect("应有文本锚");
        assert_eq!(a.snippet, "有一座山");
        // 很(0)久(1)以(2)前(3)，(4)有(5)一(6)座(7)山(8)
        assert_eq!(a.start, 5);
        assert_eq!(a.end, 9);
        assert_eq!(LocatorResolver::text_at(text, &loc).unwrap(), "有一座山");
    }

    #[test]
    fn duplicate_snippet_disambiguated_by_progression() {
        let text = "开头。城市是记忆的。中间很多文字。城市是记忆的。结尾。";
        let total = utf16_len(text) as f32;
        // 第二个"城市"起点约在 0.7 处
        let second = text.rfind("城市").unwrap();
        let second_u16 = utf16_len(&text[..second]) as f32 / total;
        let loc = LocatorResolver::from_selection(
            text,
            &"b1".to_string(),
            "c1.xhtml",
            &sel("城市是记忆的", second_u16),
        )
        .unwrap();
        let a = loc.text.clone().unwrap();
        let expected = utf16_len(&text[..second]);
        assert_eq!(a.start, expected, "应按 progression 选第二处");
        assert!(a.start > 10);
    }

    #[test]
    fn no_match_falls_back_to_progression_without_text() {
        let loc = LocatorResolver::from_selection(
            "完全不同的内容。",
            &"b1".to_string(),
            "c1.xhtml",
            &sel("不存在片段", 0.42),
        )
        .unwrap();
        assert!(loc.text.is_none());
        assert!((loc.progression - 0.42).abs() < 1e-6);
        assert!(LocatorResolver::text_at("完全不同的内容。", &loc).is_err());
    }

    #[test]
    fn whitespace_normalized_match_maps_back() {
        let text = "他说：\n\n  你好   世界。";
        let loc = LocatorResolver::from_selection(
            text,
            &"b1".to_string(),
            "c1.xhtml",
            &sel("你好 世界", 0.0),
        )
        .unwrap();
        let a = loc.text.clone().unwrap();
        assert_eq!(LocatorResolver::text_at(text, &loc).unwrap(), "你好   世界");
        assert_eq!(a.snippet, "你好 世界");
    }

    #[test]
    fn utf16_offsets_match_dart_substring_semantics() {
        // 😀 占 2 个 UTF-16 code unit
        let text = "😀你好。世界。";
        let loc = LocatorResolver::from_selection(
            text,
            &"b1".to_string(),
            "c1.xhtml",
            &sel("世界", 0.0),
        )
        .unwrap();
        let a = loc.text.clone().unwrap();
        assert_eq!(a.start, 5);
        assert_eq!(a.end, 7);
        // Rust 侧按 UTF-16 切片结果与 Dart substring(5,7) 一致
        assert_eq!(LocatorResolver::text_at(text, &loc).unwrap(), "世界");
    }

    #[test]
    fn empty_snippet_is_safe() {
        let loc =
            LocatorResolver::from_selection("abc", &"b1".to_string(), "c1.xhtml", &sel("   ", 0.3))
                .unwrap();
        assert!(loc.text.is_none());
        assert!((loc.progression - 0.3).abs() < 1e-6);
    }

    #[test]
    fn nan_progression_is_clamped() {
        let loc = LocatorResolver::from_selection(
            "abc",
            &"b1".to_string(),
            "c1.xhtml",
            &sel("zzz", f32::NAN),
        )
        .unwrap();
        assert_eq!(loc.progression, 0.0);
    }

    #[test]
    fn text_at_rejects_bad_anchor() {
        let loc = Locator {
            book_id: "b1".to_string(),
            href: "c1.xhtml".to_string(),
            progression: 0.0,
            total_progression: 0.0,
            text: Some(TextAnchor {
                snippet: "x".to_string(),
                start: 2,
                end: 99,
            }),
            cfi: None,
            page: None,
            rect: None,
        };
        assert!(LocatorResolver::text_at("abc", &loc).is_err());
    }
}
