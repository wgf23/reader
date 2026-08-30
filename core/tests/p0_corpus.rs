//! 真实公版书语料驱动的集成测试（P0 垂直切片验收）。
//!
//! 语料：tests/corpus/src/（无版权争议公版书，来源见 corpus/README.md）。
//! 覆盖：EPUB（中/英）解析、TXT 解析、规范化缓存、书库导入/打开全链路。

use std::path::PathBuf;

use reader_core::library::LibraryService;
use reader_core::store::Store;
use reader_core::format;

fn corpus(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/corpus/src")
        .join(name)
}

#[test]
fn parse_chinese_epub_hongloumeng() {
    let book = format::parse(&corpus("hongloumeng.epub")).expect("解析失败");
    assert_eq!(book.format, format::Format::Epub);
    assert!(
        book.title.contains("樓夢") || book.title.contains("楼梦"),
        "title={}",
        book.title
    );
    assert_eq!(book.language.as_deref(), Some("zh"));
    assert!(book.chapters.len() >= 5, "章节数 {}", book.chapters.len());
    // 中文内容（Gutenberg 机翻版 nav/NCX 均只有 1 条目录，章节以 spine 为准）
    let all_text: String = book.chapters.iter().map(|c| c.text.as_str()).collect();
    assert!(
        all_text.chars().any(|c| ('\u{4e00}'..='\u{9fff}').contains(&c)),
        "应含中文字符"
    );
    assert!(book.toc.len() >= 1, "目录条目 {}", book.toc.len());
}

#[test]
fn parse_english_epub_pride() {
    // Gutenberg images-3 变体：整本书压缩为 9 个 XHTML（每个含多章）
    let book = format::parse(&corpus("pride-and-prejudice.epub")).expect("解析失败");
    assert!(
        book.title.to_lowercase().contains("pride"),
        "title={}",
        book.title
    );
    assert!(book.chapters.len() >= 5, "章节数 {}", book.chapters.len());
    assert!(
        book.chapters.iter().any(|c| c.text.contains("truth")),
        "应含 It is a truth..."
    );
    // 该书的 nav 有 516 条目录
    assert!(book.toc.len() >= 50, "目录条目 {}", book.toc.len());
    // 含图 EPUB：应收集到图片资源
    assert!(
        book.resources.iter().any(|r| r.media_type.starts_with("image/")),
        "应有图片资源"
    );
}

#[test]
fn parse_utf8_txt_chapters() {
    let book = format::parse(&corpus("pride-and-prejudice.txt")).expect("解析失败");
    assert_eq!(book.format, format::Format::Txt);
    assert!(book.chapters.len() >= 50, "章节数 {}", book.chapters.len());
    assert!(
        book.chapters.iter().any(|c| c.text.contains("truth")),
        "应含 It is a truth..."
    );
}

#[test]
fn library_import_and_open_roundtrip() {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::open(&dir.path().join("data")).unwrap();
    let mut svc = LibraryService::new(store);

    // 导入中文 EPUB
    let rec = svc
        .import_file(&corpus("hongloumeng.epub"))
        .expect("导入失败");
    assert!(rec.canonical_path.as_deref().unwrap().ends_with(".epub"));
    assert!(std::path::Path::new(rec.canonical_path.as_deref().unwrap()).exists(), "规范缓存应存在");

    // 打开 → 章节可读
    let opened = svc.open_book(&rec.id).expect("打开失败");
    assert!(opened.chapters.len() >= 5);
    assert!(opened.chapters[0].text.len() > 0);

    // 列表
    let books = svc.list().unwrap();
    assert_eq!(books.len(), 1);

    // 重复导入去重
    let again = svc.import_file(&corpus("hongloumeng.epub")).unwrap();
    assert_eq!(again.id, rec.id);
    assert_eq!(svc.list().unwrap().len(), 1);
}

#[test]
fn library_txt_import() {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::open(&dir.path().join("data")).unwrap();
    let mut svc = LibraryService::new(store);
    let rec = svc
        .import_file(&corpus("pride-and-prejudice.txt"))
        .unwrap();
    let opened = svc.open_book(&rec.id).unwrap();
    assert!(opened.chapters.len() >= 50);
}
