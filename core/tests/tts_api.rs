//! REQ-005-fixes 阶段4：听书桥接 API 集成测试（真实 EPUB 全链路）。
//!
//! 覆盖 `api.rs` 新增函数：`tts_segment` / `tts_locator_for_sentence` /
//! `tts_sentence_index_at` / `tts_listen_settings_get` / `tts_listen_settings_set`
//! 以及 `chapter_text` 的错误路径与设置默认/往返/clamp。
//!
//! 语料：`tests/corpus/src/hongloumeng.epub`（缺失时跳过，保持 CI 可移植）。
//! 服务单例（`api::SERVICE`）只能初始化一次，故用进程级 `OnceLock` 夹具共享。

use std::path::PathBuf;
use std::sync::OnceLock;

use reader_core::api;
use reader_core::library::LibraryService;
use reader_core::store::Store;

/// 极简 block_on（桥接函数体内无 `.await`，首轮 poll 即 Ready）。
fn block_on<F: std::future::Future>(fut: F) -> F::Output {
    use std::task::{Context, Poll, Waker};
    let mut fut = Box::pin(fut);
    let mut cx = Context::from_waker(Waker::noop());
    match fut.as_mut().poll(&mut cx) {
        Poll::Ready(v) => v,
        Poll::Pending => panic!("阻塞在无 await 的桥接函数上（不应发生）"),
    }
}

fn corpus_epub() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/corpus/src/hongloumeng.epub")
}

/// 导入后的书信息（数据目录、id、正文最长章节 href、该章文本）。
struct Fixture {
    dir: PathBuf,
    book_id: String,
    href: String,
    chapter_text: String,
}

static FIXTURE: OnceLock<Fixture> = OnceLock::new();

fn fixture() -> Option<&'static Fixture> {
    if !corpus_epub().exists() {
        return None;
    }
    Some(FIXTURE.get_or_init(|| {
        let dir = tempfile::tempdir().unwrap();
        // 进程级服务持有该目录，测试期间不能删除 → 泄漏到进程结束。
        let path = dir.path().to_path_buf();
        std::mem::forget(dir);
        api::library_open(path.display().to_string()).unwrap();
        let book = api::library_import(corpus_epub().display().to_string()).unwrap();

        // 取正文最长章节（ChapterView 无 href，经 LibraryService 读领域章节）
        let store = Store::open(&path).unwrap();
        let svc = LibraryService::new(store);
        let longest = svc
            .open_book(&book.id)
            .unwrap()
            .chapters
            .into_iter()
            .max_by_key(|c| c.text.len())
            .expect("语料应有章节");
        Fixture {
            dir: path,
            book_id: book.id,
            href: longest.href,
            chapter_text: longest.text,
        }
    }))
}

#[test]
fn tts_segment_fields_source_and_error_paths() {
    let Some(f) = fixture() else {
        eprintln!("[skip] 语料缺失");
        return;
    };

    let chunks = block_on(api::tts_segment(f.book_id.clone(), f.href.clone())).unwrap();
    assert!(chunks.len() > 1, "真实章节应切出多句，实际 {}", chunks.len());
    assert!(
        f.chapter_text.trim_start().starts_with(&chunks[0].text),
        "首句必须来自请求章节（chapter_text 不得命中错章/空串）"
    );
    for (i, c) in chunks.iter().enumerate() {
        assert_eq!(c.index, i as u32);
        assert!(!c.text.is_empty());
        assert!(c.char_end > c.char_start);
        assert_eq!(c.locator.book_id, f.book_id);
        assert_eq!(c.locator.href, f.href);
        assert!((0.0..=1.0).contains(&c.locator.progression));
        assert!(c.text.starts_with(c.locator.snippet.as_deref().unwrap()));
    }
    for w in chunks.windows(2) {
        assert_eq!(w[0].char_end, w[1].char_start, "区间连续不重叠");
    }

    // 不存在 href → Err（chapter_text 找不到章节）
    assert!(block_on(api::tts_segment(f.book_id.clone(), "chapter_9999.xhtml".to_string())).is_err());
}

#[test]
fn tts_locator_roundtrip_and_error_paths() {
    let Some(f) = fixture() else {
        eprintln!("[skip] 语料缺失");
        return;
    };
    let chunks = block_on(api::tts_segment(f.book_id.clone(), f.href.clone())).unwrap();

    for i in [0usize, 1, chunks.len() / 2, chunks.len() - 1] {
        let loc = block_on(api::tts_locator_for_sentence(
            f.book_id.clone(),
            f.href.clone(),
            i as u32,
        ))
        .unwrap();
        assert_eq!(loc.book_id, f.book_id);
        assert_eq!(loc.href, f.href);
        assert!(chunks[i].text.starts_with(loc.snippet.as_deref().unwrap()));
        let back = block_on(api::tts_sentence_index_at(
            f.book_id.clone(),
            f.href.clone(),
            loc,
        ))
        .unwrap();
        assert_eq!(back, i as u32, "往返映射应一致");
    }

    // 越界 idx / 不存在 href → Err
    assert!(block_on(api::tts_locator_for_sentence(
        f.book_id.clone(),
        f.href.clone(),
        chunks.len() as u32,
    ))
    .is_err());
    assert!(block_on(api::tts_locator_for_sentence(
        f.book_id.clone(),
        "chapter_9999.xhtml".to_string(),
        0,
    ))
    .is_err());
    // 不匹配 href 的 locator → Err
    let mut bad =
        block_on(api::tts_locator_for_sentence(f.book_id.clone(), f.href.clone(), 0)).unwrap();
    bad.href = "chapter_9999.xhtml".to_string();
    assert!(block_on(api::tts_sentence_index_at(f.book_id.clone(), f.href.clone(), bad)).is_err());
}

#[test]
fn tts_listen_settings_default_roundtrip_clamp() {
    let Some(f) = fixture() else {
        eprintln!("[skip] 语料缺失");
        return;
    };

    let defaults = block_on(api::tts_listen_settings_get()).unwrap();
    assert_eq!(defaults.voice_id, "system_male");
    assert_eq!(defaults.speed, 1.0);
    assert!(defaults.auto_next);

    block_on(api::tts_listen_settings_set(api::ListenSettingsView {
        voice_id: "system_female".to_string(),
        speed: 1.5,
        auto_next: false,
    }))
    .unwrap();
    let read = block_on(api::tts_listen_settings_get()).unwrap();
    assert_eq!(read.voice_id, "system_female");
    assert!((read.speed - 1.5).abs() < 1e-6);
    assert!(!read.auto_next, "auto_next=false 读回必须为 false");

    // speed 上/下 clamp（落库前 clamp）
    block_on(api::tts_listen_settings_set(api::ListenSettingsView {
        voice_id: "system_male".to_string(),
        speed: 9.9,
        auto_next: true,
    }))
    .unwrap();
    assert!((block_on(api::tts_listen_settings_get()).unwrap().speed - 3.0).abs() < 1e-6);
    block_on(api::tts_listen_settings_set(api::ListenSettingsView {
        voice_id: "system_male".to_string(),
        speed: 0.1,
        auto_next: true,
    }))
    .unwrap();
    assert!((block_on(api::tts_listen_settings_get()).unwrap().speed - 0.5).abs() < 1e-6);

    // 非有限 speed → 默认 1.0；空音色 → 默认 system_male
    block_on(api::tts_listen_settings_set(api::ListenSettingsView {
        voice_id: "   ".to_string(),
        speed: f32::NAN,
        auto_next: true,
    }))
    .unwrap();
    let fallback = block_on(api::tts_listen_settings_get()).unwrap();
    assert_eq!(fallback.voice_id, "system_male", "空音色应回退默认");
    assert!((fallback.speed - 1.0).abs() < 1e-6, "NaN 语速应回退默认 1.0");

    // 库内存在空白 voice_id / 非法语速记录时，读取应回退默认（US-11 防回归）
    {
        let mut raw = Store::open(&f.dir).unwrap();
        raw.set_setting("listen.voice_id", "   ").unwrap();
        raw.set_setting("listen.speed", "not-a-number").unwrap();
    }
    let filtered = block_on(api::tts_listen_settings_get()).unwrap();
    assert_eq!(filtered.voice_id, "system_male", "空白记录应被过滤");
    assert!((filtered.speed - 1.0).abs() < 1e-6, "非法语速应回退默认");
}
