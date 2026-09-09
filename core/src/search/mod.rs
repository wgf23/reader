//! 全文搜索：FTS5 索引与查询 + CJK bigram 预处理纯函数。
//!
//! 设计：docs/04-module-design.md §5（fts_books 虚拟表）、docs/02 §6（<100ms）；
//! ADR REQ-009 D1（应用层 bigram 解决 `unicode61` 对 2 字中文词零命中）。
//!
//! 分层：domain 层，只依赖 `crate::types`/`crate::error`（经 `SearchIndexRepository` trait
//! 注入，禁 `crate::store`）。索引侧与查询侧共用 `bigram_index_text`，保证词法一致。

use crate::error::Result;
use crate::types::{
    IndexedChapter, SearchHit, SearchIndexRepository, SearchScope, TextRange,
};

/// CJK / 假名 / 谚文判定（ADR D1 语素范围）。
pub fn is_cjk(c: char) -> bool {
    matches!(c as u32,
        0x3400..=0x4DBF   // CJK 扩展 A
        | 0x4E00..=0x9FFF // CJK 统一表意
        | 0xF900..=0xFAFF // CJK 兼容表意
        | 0x3040..=0x30FF // 平假名/片假名
        | 0xAC00..=0xD7AF // 谚文音节
    )
}

fn flush_cjk(run: &mut Vec<char>, out: &mut Vec<String>) {
    if run.is_empty() {
        return;
    }
    if run.len() == 1 {
        out.push(run[0].to_string());
    } else {
        for w in run.windows(2) {
            out.push(w.iter().collect());
        }
    }
    run.clear();
}

fn flush_word(word: &mut String, out: &mut Vec<String>) {
    if word.is_empty() {
        return;
    }
    out.push(std::mem::take(word).to_ascii_lowercase());
}

/// CJK 连续段 → 重叠 bigram；ASCII 字母数字 → 整词小写；标点/空白为边界。
///
/// 例：`看不见的城市，卡尔维诺写道` → `看不 不见 见的 的城 城市 卡尔 尔维 维诺 诺写 写道`。
pub fn bigram_index_text(text: &str) -> String {
    let mut out: Vec<String> = Vec::new();
    let mut cjk_run: Vec<char> = Vec::new();
    let mut word = String::new();
    for c in text.chars() {
        if is_cjk(c) {
            flush_word(&mut word, &mut out);
            cjk_run.push(c);
        } else if c.is_alphanumeric() {
            flush_cjk(&mut cjk_run, &mut out);
            word.push(c);
        } else {
            flush_cjk(&mut cjk_run, &mut out);
            flush_word(&mut word, &mut out);
        }
    }
    flush_cjk(&mut cjk_run, &mut out);
    flush_word(&mut word, &mut out);
    out.join(" ")
}

/// 查询 → FTS5 安全短语表达式；全空 → `None`（api 层短路）。
///
/// 每个空格分词项经 `bigram_index_text` 预处理，作为 FTS5 短语；多项之间 `AND`。
pub fn build_match_expr(query: &str) -> Option<String> {
    let mut phrases: Vec<String> = Vec::new();
    for term in query.split_whitespace() {
        let bi = bigram_index_text(term);
        if bi.trim().is_empty() {
            continue;
        }
        // FTS5 短语引用：内部双引号翻倍（本函数产物仅 CJK/字母数字，防御性处理）
        let escaped = bi.replace('"', "\"\"");
        phrases.push(format!("\"{escaped}\""));
    }
    if phrases.is_empty() {
        None
    } else {
        Some(phrases.join(" AND "))
    }
}

fn char_table(text: &str) -> (Vec<char>, Vec<u32>) {
    let chars: Vec<char> = text.chars().collect();
    let mut offsets = Vec::with_capacity(chars.len() + 1);
    let mut u = 0u32;
    for c in &chars {
        offsets.push(u);
        u += c.len_utf16() as u32;
    }
    offsets.push(u);
    (chars, offsets)
}

fn eq_ci(a: char, b: char) -> bool {
    a == b || (a.is_ascii() && b.is_ascii() && a.eq_ignore_ascii_case(&b))
}

fn find_ci(hay: &[char], needle: &[char]) -> Vec<usize> {
    if needle.is_empty() || needle.len() > hay.len() {
        return Vec::new();
    }
    let mut out = Vec::new();
    for i in 0..=(hay.len() - needle.len()) {
        if hay[i..i + needle.len()]
            .iter()
            .zip(needle)
            .all(|(a, b)| eq_ci(*a, *b))
        {
            out.push(i);
        }
    }
    out
}

/// 在原文中抽上下文片段并给出关键词 UTF-16 区间（`window` = 命中两侧字符数）。
pub fn extract_snippet(text: &str, query: &str, window: usize) -> (String, Vec<TextRange>) {
    let (chars, offsets) = char_table(text);
    if chars.is_empty() {
        return (String::new(), Vec::new());
    }
    let terms: Vec<String> = {
        let ws: Vec<&str> = query.split_whitespace().collect();
        if ws.len() > 1 {
            ws.into_iter().map(|s| s.to_string()).collect()
        } else {
            vec![query.to_string()]
        }
    };
    let mut occ: Vec<(usize, usize)> = Vec::new();
    for t in &terms {
        let n: Vec<char> = t.chars().collect();
        for i in find_ci(&chars, &n) {
            occ.push((i, i + n.len()));
        }
    }
    occ.sort_unstable();
    occ.dedup();
    if occ.is_empty() {
        let end = window.min(chars.len());
        return (chars[..end].iter().collect(), Vec::new());
    }
    let (first_s, first_e) = occ[0];
    let start_char = first_s.saturating_sub(window);
    let end_char = (first_e + window).min(chars.len());
    let snippet: String = chars[start_char..end_char].iter().collect();
    let base = offsets[start_char];
    let mut ranges = Vec::new();
    for &(s, e) in &occ {
        if s >= start_char && e <= end_char {
            ranges.push(TextRange {
                start: offsets[s] - base,
                end: offsets[e] - base,
            });
        }
    }
    (snippet, ranges)
}

fn is_single_cjk_char(q: &str) -> bool {
    let mut it = q.chars();
    match (it.next(), it.next()) {
        (Some(c), None) => is_cjk(c),
        _ => false,
    }
}

pub struct SearchService {
    repo: Box<dyn SearchIndexRepository + Send>,
}

impl SearchService {
    pub fn new(repo: Box<dyn SearchIndexRepository + Send>) -> Self {
        SearchService { repo }
    }

    pub fn index_book(&mut self, book_id: &str, chapters: &[IndexedChapter]) -> Result<()> {
        self.repo.replace_book(book_id, chapters)
    }

    pub fn is_indexed(&self, book_id: &str) -> Result<bool> {
        self.repo.is_indexed(book_id)
    }

    /// 查询：空/纯空白短路；单字 CJK 走 LIKE 回退；否则 FTS5 短语。
    pub fn query(&self, q: &str, scope: &SearchScope) -> Result<Vec<SearchHit>> {
        let query = q.trim();
        if query.is_empty() {
            return Ok(Vec::new());
        }
        const LIMIT: usize = 200;
        let rows = if is_single_cjk_char(query) {
            self.repo.query_substring(query, scope, LIMIT)?
        } else {
            match build_match_expr(query) {
                Some(expr) => self.repo.query_fts(&expr, scope, LIMIT)?,
                None => Vec::new(),
            }
        };
        Ok(rows
            .into_iter()
            .map(|r| {
                let (snippet, ranges) = extract_snippet(&r.text, query, 30);
                SearchHit {
                    book_id: r.book_id,
                    book_title: r.book_title,
                    href: r.href,
                    chapter_title: r.chapter_title,
                    snippet,
                    ranges,
                    score: r.score,
                }
            })
            .collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::Result;
    use crate::types::SearchRow;
    use std::sync::{Arc, Mutex};

    #[derive(Default)]
    struct MemSearch {
        rows: Vec<SearchRow>,
        last_expr: Option<String>,
        last_needle: Option<String>,
        indexed: bool,
        replace_calls: usize,
    }

    struct Shared(Arc<Mutex<MemSearch>>);
    impl SearchIndexRepository for Shared {
        fn replace_book(&mut self, _b: &str, _c: &[IndexedChapter]) -> Result<()> {
            self.0.lock().unwrap().replace_calls += 1;
            Ok(())
        }
        fn is_indexed(&self, _b: &str) -> Result<bool> {
            Ok(self.0.lock().unwrap().indexed)
        }
        fn remove_book(&mut self, _b: &str) -> Result<()> {
            Ok(())
        }
        fn query_fts(
            &self,
            match_expr: &str,
            _scope: &SearchScope,
            _limit: usize,
        ) -> Result<Vec<SearchRow>> {
            self.0.lock().unwrap().last_expr = Some(match_expr.to_string());
            Ok(self.0.lock().unwrap().rows.clone())
        }
        fn query_substring(
            &self,
            needle: &str,
            _scope: &SearchScope,
            _limit: usize,
        ) -> Result<Vec<SearchRow>> {
            self.0.lock().unwrap().last_needle = Some(needle.to_string());
            Ok(self.0.lock().unwrap().rows.clone())
        }
    }

    fn row(text: &str) -> SearchRow {
        SearchRow {
            book_id: "b1".to_string(),
            book_title: "看不见的城市".to_string(),
            href: "c1.xhtml".to_string(),
            chapter_title: "城市与记忆".to_string(),
            text: text.to_string(),
            score: Some(-1.0),
        }
    }

    #[test]
    fn bigram_index_text_examples() {
        assert_eq!(bigram_index_text("城市"), "城市");
        assert_eq!(bigram_index_text("城"), "城");
        assert_eq!(
            bigram_index_text("看不见的城市，卡尔维诺写道"),
            "看不 不见 见的 的城 城市 卡尔 尔维 维诺 诺写 写道"
        );
        assert_eq!(bigram_index_text("Hello World"), "hello world");
        assert_eq!(bigram_index_text("abc123"), "abc123");
        assert_eq!(bigram_index_text("，。！ "), "");
        assert_eq!(bigram_index_text(""), "");
    }

    #[test]
    fn build_match_expr_safe_and_empty() {
        assert_eq!(build_match_expr(""), None);
        assert_eq!(build_match_expr("   "), None);
        assert_eq!(build_match_expr("%%%"), None);
        assert_eq!(build_match_expr("城市"), Some("\"城市\"".to_string()));
        assert_eq!(
            build_match_expr("卡尔维诺"),
            Some("\"卡尔 尔维 维诺\"".to_string())
        );
        // 特殊字符被短语引用隔离（`*`/`"`/NEAR 等不进表达式）
        let expr = build_match_expr("% _ \" * NEAR").unwrap();
        assert!(expr.contains("near"));
        assert!(!expr.contains('*'));
        assert!(!expr.contains('%'));
    }

    #[test]
    fn extract_snippet_ranges_point_to_keyword() {
        let text = "在《看不见的城市》里，卡尔维诺写道：城市是记忆的。";
        let (snip, ranges) = extract_snippet(text, "卡尔维诺", 5);
        assert!(snip.contains("卡尔维诺"));
        assert_eq!(ranges.len(), 1);
        let r = ranges[0];
        let kw: String = snip.chars().skip(r.start as usize).take((r.end - r.start) as usize).collect();
        assert_eq!(kw, "卡尔维诺", "range 应精确指向关键词");
    }

    #[test]
    fn extract_snippet_multiple_occurrences_and_no_match() {
        let (snip, ranges) = extract_snippet("城市与记忆，城市与符号。", "城市", 10);
        assert_eq!(ranges.len(), 2, "窗口内两处命中都应给出区间");
        for r in &ranges {
            let kw: String = snip
                .chars()
                .skip(r.start as usize)
                .take((r.end - r.start) as usize)
                .collect();
            assert_eq!(kw, "城市");
        }
        let (snip2, ranges2) = extract_snippet("无关内容", "不存在", 3);
        assert_eq!(snip2, "无关内", "无命中时取前 window 字符");
        assert!(ranges2.is_empty());
        assert_eq!(extract_snippet("", "x", 3), (String::new(), vec![]));
    }

    #[test]
    fn extract_snippet_utf16_offsets_with_emoji() {
        let text = "😀城市";
        let (snip, ranges) = extract_snippet(text, "城市", 0);
        assert_eq!(snip, "城市");
        assert_eq!(ranges[0], TextRange { start: 0, end: 2 });
    }

    #[test]
    fn service_query_routes_single_cjk_to_substring_and_multi_to_fts() {
        let mem = Arc::new(Mutex::new(MemSearch {
            rows: vec![row("看不见的城市，卡尔维诺写道。")],
            ..Default::default()
        }));
        let svc = SearchService::new(Box::new(Shared(mem.clone())));
        let hits = svc.query("城", &SearchScope::default()).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(mem.lock().unwrap().last_needle.as_deref(), Some("城"));
        assert!(mem.lock().unwrap().last_expr.is_none());

        let hits = svc.query("城市", &SearchScope::default()).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(mem.lock().unwrap().last_expr.as_deref(), Some("\"城市\""));
        assert!(!hits[0].ranges.is_empty());

        // 空查询短路（不触达 repo）
        mem.lock().unwrap().last_expr = None;
        assert!(svc.query("   ", &SearchScope::default()).unwrap().is_empty());
        assert!(mem.lock().unwrap().last_expr.is_none());
    }

    #[test]
    fn service_index_book_and_is_indexed_delegate_to_repo() {
        let mem = Arc::new(Mutex::new(MemSearch::default()));
        let mut svc = SearchService::new(Box::new(Shared(mem.clone())));
        assert!(!svc.is_indexed("b1").unwrap(), "未索引应为 false");
        svc.index_book("b1", &[]).unwrap();
        assert_eq!(mem.lock().unwrap().replace_calls, 1, "应委托 replace_book");
        mem.lock().unwrap().indexed = true;
        assert!(svc.is_indexed("b1").unwrap(), "已索引应为 true");
    }

    #[test]
    fn extract_snippet_case_insensitive_ascii_but_not_other_letters() {
        // 大小写不同 → 命中
        let (_s, r) = extract_snippet("Hello", "hello", 0);
        assert_eq!(r.len(), 1);
        // 不同 ASCII 字母 → 不命中（eq_ci 第二个 && 不可退化为 ||）
        let (_s2, r2) = extract_snippet("aX", "aY", 0);
        assert!(r2.is_empty(), "不同字母不应判等");
        // ASCII 与非 ASCII 混排不误判
        let (_s3, r3) = extract_snippet("a城", "aX", 0);
        assert!(r3.is_empty());
    }

    #[test]
    fn extract_snippet_empty_needle_and_length_edges() {
        // 空 query → 无命中区间（find_ci 空 needle 短路）
        let (snip, r) = extract_snippet("abc", "", 2);
        assert_eq!(snip, "ab");
        assert!(r.is_empty(), "空 needle 不应匹配任意位置");
        // needle 比正文长 → 无命中且不 panic
        let (snip2, r2) = extract_snippet("ab", "abcdef", 1);
        assert_eq!(snip2, "a");
        assert!(r2.is_empty());
        // needle 与正文等长且命中 → 区间覆盖全文
        let (snip3, r3) = extract_snippet("ab", "ab", 0);
        assert_eq!(snip3, "ab");
        assert_eq!(r3.len(), 1);
        assert_eq!((r3[0].start, r3[0].end), (0, 2));
    }

    #[test]
    fn extract_snippet_multi_term_query_and_partial_occurrence() {
        // 多词查询：空格分词后每个词独立给区间
        let (_s, r) = extract_snippet("城市与记忆", "城市 记忆", 10);
        assert_eq!(r.len(), 2, "两个词应各给一个区间");
        // 窗口外/半开区间的命中不应被纳入（&& 不可退化为 ||）
        let (snip, r2) = extract_snippet("城市x城市", "城市", 1);
        assert_eq!(snip, "城市x");
        assert_eq!(r2.len(), 1, "部分落在窗口外的命中应被排除");
    }
}
