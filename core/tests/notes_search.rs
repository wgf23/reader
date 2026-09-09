//! REQ-009 端到端（core 层）：真实 SQLite/FTS5 上的 CJK 搜索 + 笔记仓储 + 导出。
//!
//! 覆盖 US-18（2 字/4 字中文词命中）、US-21（耗时门槛）、US-6/16（分组/导出）。
//! 放在 `core/tests/`（不在 ddd-rules 分层路径内），可自由组装 store + domain。

use std::collections::HashMap;

use reader_core::notes::AnnotationService;
use reader_core::search::{bigram_index_text, SearchService};
use reader_core::store::{AnnotationRepo, BookRecord, SearchIndexRepo, Store};
use reader_core::types::{
    AnnotationRepository, ExportFormat, IndexedChapter, Locator, NoteKind, SearchIndexRepository,
    SearchScope, TextAnchor,
};

const CORPUS: &str = "看不见的城市，卡尔维诺写道：城市是记忆的。他还说，每一座城市都藏着记忆。";

fn temp_store() -> (tempfile::TempDir, Store) {
    let dir = tempfile::tempdir().unwrap();
    let mut store = Store::open(dir.path()).unwrap();
    store
        .insert_book(&BookRecord {
            id: "b1".to_string(),
            title: "看不见的城市".to_string(),
            authors: vec!["卡尔维诺".to_string()],
            language: Some("zh".to_string()),
            source_path: "/x.epub".to_string(),
            source_hash: "h1".to_string(),
            format: "epub".to_string(),
            canonical_path: None,
            added_at: 1,
        })
        .unwrap();
    (dir, store)
}

fn index(repo: &mut SearchIndexRepo, href: &str, text: &str) {
    let chapters = vec![IndexedChapter {
        href: href.to_string(),
        chapter_title: "城市与记忆".to_string(),
        text: text.to_string(),
        text_bi: bigram_index_text(text),
    }];
    repo.replace_book("b1", &chapters).unwrap();
}

#[test]
fn cjk_two_and_four_char_queries_hit_real_fts() {
    let (dir, _store) = temp_store();
    let mut repo = SearchIndexRepo::open(dir.path()).unwrap();
    index(&mut repo, "chapter_0001.xhtml", CORPUS);
    let svc = SearchService::new(Box::new(repo));

    for q in ["城市", "卡尔维诺", "记忆"] {
        let start = std::time::Instant::now();
        let hits = svc.query(q, &SearchScope::default()).unwrap();
        let elapsed = start.elapsed();
        eprintln!("[US-18/21] search(\"{q}\") → {} 命中，耗时 {elapsed:?}", hits.len());
        assert!(!hits.is_empty(), "search(\"{q}\") 应 ≥1 命中");
        assert!(elapsed.as_millis() <= 100, "查询应 ≤100ms，实测 {elapsed:?}");
        let h = &hits[0];
        assert_eq!(h.book_title, "看不见的城市");
        assert_eq!(h.href, "chapter_0001.xhtml");
        assert!(!h.ranges.is_empty(), "应给出关键词区间");
        // 区间指向关键词
        let r = h.ranges[0];
        let kw: String = h
            .snippet
            .chars()
            .skip(r.start as usize)
            .take((r.end - r.start) as usize)
            .collect();
        assert_eq!(kw, q, "区间应精确指向关键词");
    }
}

#[test]
fn single_cjk_char_like_fallback_and_special_chars_safe() {
    let (dir, _store) = temp_store();
    let mut repo = SearchIndexRepo::open(dir.path()).unwrap();
    index(&mut repo, "chapter_0001.xhtml", CORPUS);
    let svc = SearchService::new(Box::new(repo));

    assert!(!svc.query("城", &SearchScope::default()).unwrap().is_empty());
    for bad in ["", "   ", "%", "_", "\"", "*", "NEAR", "城市*", "城_市"] {
        let hits = svc.query(bad, &SearchScope::default());
        assert!(hits.is_ok(), "特殊输入 {bad:?} 不应抛异常");
    }
    assert!(svc.query("   ", &SearchScope::default()).unwrap().is_empty());
}

#[test]
fn notes_repo_service_and_export_end_to_end() {
    let (dir, _store) = temp_store();
    let repo = AnnotationRepo::open(dir.path()).unwrap();
    let mut svc = AnnotationService::new(Box::new(repo));

    let locator = Locator {
        book_id: "b1".to_string(),
        href: "chapter_0001.xhtml".to_string(),
        progression: 0.2,
        total_progression: 0.2,
        text: Some(TextAnchor {
            snippet: "看不见的城市".to_string(),
            start: 0,
            end: 6,
        }),
        cfi: None,
        page: None,
        rect: None,
    };
    let a = svc
        .create(
            "b1",
            locator.clone(),
            NoteKind::Highlight,
            Some("#FBC02D".to_string()),
            None,
        )
        .unwrap();
    svc.create(
        "b1",
        locator,
        NoteKind::Note,
        None,
        Some("这是批注".to_string()),
    )
    .unwrap();

    let mut titles = HashMap::new();
    titles.insert("chapter_0001.xhtml".to_string(), "城市与记忆".to_string());
    let groups = svc.list("b1", &titles).unwrap();
    assert_eq!(groups.len(), 1);
    assert_eq!(groups[0].chapter_title, "城市与记忆");
    assert_eq!(groups[0].notes.len(), 2);

    // 改色 + 删除
    svc.update(
        &a.id,
        &reader_core::types::NotePatch {
            color: Some("#1A73E8".to_string()),
            ..Default::default()
        },
    )
    .unwrap();
    assert_eq!(svc.resolve(&a.id).unwrap().text.unwrap().snippet, "看不见的城市");

    // 导出 Markdown / JSON
    let md = dir.path().join("n.md");
    let sum = svc
        .export("看不见的城市", &groups, ExportFormat::Markdown, &md)
        .unwrap();
    assert_eq!(sum.note_count, 2);
    assert!(std::fs::read_to_string(&md).unwrap().contains("城市与记忆"));

    let js = dir.path().join("n.json");
    svc.export("看不见的城市", &groups, ExportFormat::Json, &js)
        .unwrap();
    let v: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(&js).unwrap()).unwrap();
    assert_eq!(v["book_title"], "看不见的城市");
    assert_eq!(v["groups"][0]["notes"].as_array().unwrap().len(), 2);

    // 全部删除
    assert_eq!(svc.delete_all("b1").unwrap(), 2);
    assert!(svc.list("b1", &titles).unwrap().is_empty());
    // AnnotationRepository 契约在 infra 上可用（编译期/运行期断言）
    fn assert_repo<T: AnnotationRepository>(_: &T) {}
    let r = AnnotationRepo::open(dir.path()).unwrap();
    assert_repo(&r);
}
