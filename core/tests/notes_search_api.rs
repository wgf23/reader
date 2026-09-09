//! REQ-009 端到端（core api 桥接层）：真实 SQLite/FTS5 上驱动 notes_*/search 桥接函数。
//!
//! 覆盖 `core/src/api.rs` 新增的 9 个 notes 桥接 + `search` + 懒回填/scope 组装。
//! 放在 `core/tests/`（不在 ddd-rules 分层路径内）。全部逻辑集中在单个 `#[test]`，
//! 因为 api 的 NOTES/SEARCH/SERVICE 为进程内单例，`library_open` 只初始化一次。

use std::path::Path;

use reader_core::api;
use reader_core::store::SearchIndexRepo;
use reader_core::types::SearchIndexRepository;

/// 极简 block_on：桥接函数体内无 `.await`，首轮 poll 即 Ready。
fn block_on<F: std::future::Future>(mut fut: F) -> F::Output {
    use std::pin::Pin;
    use std::ptr;
    use std::task::{Context, Poll, RawWaker, RawWakerVTable, Waker};
    const VTABLE: RawWakerVTable = RawWakerVTable::new(|_| RAW, |_| {}, |_| {}, |_| {});
    const RAW: RawWaker = RawWaker::new(ptr::null(), &VTABLE);
    let waker = unsafe { Waker::from_raw(RAW) };
    let mut cx = Context::from_waker(&waker);
    let fut = unsafe { Pin::new_unchecked(&mut fut) };
    match fut.poll(&mut cx) {
        Poll::Ready(v) => v,
        Poll::Pending => panic!("阻塞在无 await 的桥接函数上（不应发生）"),
    }
}

const EPUB: &str = "tests/corpus/src/hongloumeng.epub";
const TXT: &str = "tests/corpus/src/pride-and-prejudice.txt";

#[test]
fn notes_and_search_bridge_end_to_end() {
    assert!(Path::new(EPUB).exists(), "语料缺失：{EPUB}");

    let dir = tempfile::tempdir().unwrap();
    let data_dir = dir.path().join("data");
    std::fs::create_dir_all(&data_dir).unwrap();

    api::library_open(data_dir.display().to_string()).unwrap();

    // 导入即索引（US-21）
    let summary = api::library_import(EPUB.to_string()).unwrap();
    let book_id = summary.id.clone();
    assert!(!book_id.is_empty());
    assert!(!summary.title.is_empty(), "书名非空（导出头部/搜索标题依赖）");

    // 第二本（英文 txt）：导入时即索引，随后显式删其索引 → 覆盖 search 懒回填。
    let summary2 = api::library_import(TXT.to_string()).unwrap();
    let book2_id = summary2.id.clone();
    {
        let mut idx = SearchIndexRepo::open(&data_dir).unwrap();
        idx.remove_book(&book2_id).unwrap();
    }

    let view = api::book_open(book_id.clone()).unwrap();
    assert!(view.chapters.iter().all(|c| !c.href.is_empty()), "book_open 应填 href");
    let chapter = view
        .chapters
        .iter()
        .find(|c| c.text.chars().count() > 50 && c.text.chars().any(|ch| ch as u32 >= 0x4E00))
        .expect("应有中文正文章节");
    let href = chapter.href.clone();
    let word: String = chapter
        .text
        .chars()
        .filter(|c| (*c as u32) >= 0x4E00 && (*c as u32) <= 0x9FFF)
        .take(2)
        .collect();
    assert_eq!(word.chars().count(), 2, "应取到 2 字 CJK 词");

    // ---- notes_create：高亮 ----
    let created = block_on(api::notes_create(
        book_id.clone(),
        href.clone(),
        word.clone(),
        0.1,
        "highlight".to_string(),
        Some("#FBC02D".to_string()),
        None,
    ))
    .unwrap();
    assert_eq!(created.book_id, book_id);
    assert_eq!(created.kind, "highlight");
    assert_eq!(created.color.as_deref(), Some("#FBC02D"));
    assert_eq!(created.snippet.as_deref(), Some(word.as_str()));
    assert!(created.start.is_some() && created.end.is_some());
    assert!(created.start.unwrap() < created.end.unwrap());
    assert_eq!(created.sync_status, "local");

    // 未知 kind / 空批注 → 错误
    assert!(block_on(api::notes_create(
        book_id.clone(),
        href.clone(),
        word.clone(),
        0.1,
        "nope".to_string(),
        None,
        None,
    ))
    .is_err());
    assert!(block_on(api::notes_create(
        book_id.clone(),
        href.clone(),
        word.clone(),
        0.1,
        "note".to_string(),
        None,
        Some("   ".to_string()),
    ))
    .is_err());

    // ---- notes_list：分组含章节名 ----
    let groups = block_on(api::notes_list(book_id.clone())).unwrap();
    assert!(!groups.is_empty());
    assert!(
        groups.iter().any(|g| g.href == href && g.chapter_title == chapter.title),
        "notes_list 分组应注入真实章节标题（非 href 回退）"
    );
    assert!(groups
        .iter()
        .flat_map(|g| g.notes.iter())
        .any(|n| n.id == created.id));

    // ---- notes_update：改色 + 批注 ----
    block_on(api::notes_update(
        created.id.clone(),
        api::NotePatchView {
            note_text: Some("桥接批注".to_string()),
            color: Some("#1A73E8".to_string()),
            kind: None,
        },
    ))
    .unwrap();
    // 未知 kind → 错误
    assert!(block_on(api::notes_update(
        created.id.clone(),
        api::NotePatchView {
            note_text: None,
            color: None,
            kind: Some("nope".to_string()),
        },
    ))
    .is_err());

    // ---- notes_resolve ----
    let loc = block_on(api::notes_resolve(created.id.clone())).unwrap();
    assert_eq!(loc.href, href);
    assert!(loc.progression >= 0.0);

    // ---- 书签幂等 ----
    let on = block_on(api::notes_toggle_bookmark(
        book_id.clone(),
        href.clone(),
        0.3,
        Some(word.clone()),
    ))
    .unwrap();
    assert!(on.bookmarked && on.note_id.is_some());
    let off = block_on(api::notes_toggle_bookmark(
        book_id.clone(),
        href.clone(),
        0.3,
        Some(word.clone()),
    ))
    .unwrap();
    assert!(!off.bookmarked && off.note_id.is_none());
    // NaN progression 被 clamp 为 0（覆盖 finite 判断）
    let nan = block_on(api::notes_toggle_bookmark(
        book_id.clone(),
        href.clone(),
        f32::NAN,
        None,
    ))
    .unwrap();
    assert!(nan.bookmarked);

    // ---- notes_export：Markdown + JSON + 未知格式 ----
    let md = dir.path().join("notes.md");
    let sum = block_on(api::notes_export(
        book_id.clone(),
        "markdown".to_string(),
        md.display().to_string(),
    ))
    .unwrap();
    assert!(sum.note_count >= 1);
    assert_eq!(sum.format, "markdown");
    assert!(md.exists());
    let md_text = std::fs::read_to_string(&md).unwrap();
    let header = md_text.lines().next().unwrap_or("");
    assert!(
        header.contains(&summary.title),
        "导出 Markdown 头部应含真实书名，实际首行：{header:?}"
    );
    let js = dir.path().join("notes.json");
    let jsum = block_on(api::notes_export(
        book_id.clone(),
        "json".to_string(),
        js.display().to_string(),
    ))
    .unwrap();
    assert_eq!(jsum.format, "json");
    assert!(js.exists());
    assert!(block_on(api::notes_export(
        book_id.clone(),
        "pdf".to_string(),
        md.display().to_string(),
    ))
    .is_err());

    // ---- search：懒回填旧书 + 当前书 scope + 全部书 + 格式过滤 + 空查询 ----
    let hits = block_on(api::search(
        word.clone(),
        api::SearchScopeView {
            all_books: true,
            book_id: None,
            formats: vec![],
        },
    ))
    .unwrap();
    assert!(!hits.is_empty(), "search(\"{word}\") 应命中");
    let h = &hits[0];
    assert!(!h.book_id.is_empty());
    assert!(!h.book_title.is_empty());
    assert!(!h.snippet.is_empty());
    assert!(!h.ranges.is_empty());
    assert!(h.ranges[0].start < h.ranges[0].end);

    let scoped = block_on(api::search(
        word.clone(),
        api::SearchScopeView {
            all_books: false,
            book_id: Some(book_id.clone()),
            formats: vec![],
        },
    ))
    .unwrap();
    assert!(scoped.iter().all(|x| x.book_id == book_id));

    // domain_scope：当前书 scope 下英文词 "the" 不应命中英文 txt（b2）
    let scoped_en = block_on(api::search(
        "elizabeth".to_string(),
        api::SearchScopeView {
            all_books: false,
            book_id: Some(book_id.clone()),
            formats: vec![],
        },
    ))
    .unwrap();
    assert!(scoped_en.is_empty(), "当前书 scope 不应越界命中其他书");

    // books_in_scope：先移除 b2 索引；当前书 scope 搜索不得回填 b2
    {
        let mut idx = SearchIndexRepo::open(&data_dir).unwrap();
        idx.remove_book(&book2_id).unwrap();
    }
    let _ = block_on(api::search(
        word.clone(),
        api::SearchScopeView {
            all_books: false,
            book_id: Some(book_id.clone()),
            formats: vec![],
        },
    ))
    .unwrap();
    assert!(
        !SearchIndexRepo::open(&data_dir)
            .unwrap()
            .is_indexed(&book2_id)
            .unwrap(),
        "当前书 scope 不应懒回填其他书"
    );

    // 懒回填：b2（txt）索引已删除，全部书搜索应触发 ensure_indexed 并命中 b2
    let backfill = block_on(api::search(
        "elizabeth".to_string(),
        api::SearchScopeView {
            all_books: true,
            book_id: None,
            formats: vec![],
        },
    ))
    .unwrap();
    assert!(
        backfill.iter().any(|x| x.book_id == book2_id),
        "懒回填后未索引的 txt 书应可被搜到"
    );

    // 格式过滤（epub）→ 只返回 epub 书 b1
    let epub_only = block_on(api::search(
        word.clone(),
        api::SearchScopeView {
            all_books: true,
            book_id: None,
            formats: vec!["epub".to_string()],
        },
    ))
    .unwrap();
    assert!(
        epub_only.iter().all(|x| x.book_id == book_id),
        "格式过滤应只返回 epub"
    );

    // 空查询短路（不触达仓储）
    assert!(block_on(api::search(
        "   ".to_string(),
        api::SearchScopeView {
            all_books: true,
            book_id: None,
            formats: vec![],
        },
    ))
    .unwrap()
    .is_empty());

    // ---- 单条删除：建一条 → 删除 → 列表不再含该 id ----
    let tmp = block_on(api::notes_create(
        book_id.clone(),
        href.clone(),
        word.clone(),
        0.7,
        "underline".to_string(),
        Some("#E91E63".to_string()),
        None,
    ))
    .unwrap();
    block_on(api::notes_delete(tmp.id.clone())).unwrap();
    assert!(
        !block_on(api::notes_list(book_id.clone()))
            .unwrap()
            .iter()
            .flat_map(|g| g.notes.iter())
            .any(|n| n.id == tmp.id),
        "notes_delete 应真正删除记录"
    );

    // ---- 批量删除 + 全部删除 ----
    let created2 = block_on(api::notes_create(
        book_id.clone(),
        href.clone(),
        word.clone(),
        0.2,
        "underline".to_string(),
        Some("#43A047".to_string()),
        None,
    ))
    .unwrap();
    let n = block_on(api::notes_delete_many(vec![
        created.id.clone(),
        created2.id.clone(),
    ]))
    .unwrap();
    assert_eq!(n, 2, "delete_many 应返回实际删除条数");
    // 再建一条，使 delete_all 返回 2（书签@0.0 + 新高亮）
    block_on(api::notes_create(
        book_id.clone(),
        href.clone(),
        word.clone(),
        0.5,
        "highlight".to_string(),
        Some("#FBC02D".to_string()),
        None,
    ))
    .unwrap();
    let all = block_on(api::notes_delete_all(book_id.clone())).unwrap();
    assert_eq!(all, 2, "delete_all 应返回该书全部条数");
    assert!(block_on(api::notes_list(book_id.clone())).unwrap().is_empty());

    // 未初始化时的错误分支（另一 data_dir 的单例已存在，此处仅验证接口可达性）
    assert!(block_on(api::notes_delete("missing".to_string())).is_ok());
}
