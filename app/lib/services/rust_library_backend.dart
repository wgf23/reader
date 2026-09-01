/// Rust 核心后端：经 flutter_rust_bridge 调用 `reader_core`，并把生成类型转换为 DTO。
/// 设计：docs/03-architecture.md §4、docs/04 §7、docs/07 §6。
library;

import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../src/rust/api.dart' as rust;
import 'builtin_dict.dart';
import 'frb_init.dart';
import 'library_backend.dart';

/// flutter_rust_bridge 实现的书库后端
class RustLibraryBackend implements LibraryBackend {
  @override
  Future<void> open() async {
    await ensureRustLib();
    final dir = await getApplicationSupportDirectory();
    final dataDir = '${dir.path}/data';
    // 内置词典先落盘，library_open 才能扫到（查词/离线翻译开箱即用）
    await ensureBuiltinDict(dataDir);
    await rust.libraryOpen(dataDir: dataDir);
  }

  @override
  Future<List<BookSummaryData>> list() async {
    final books = await rust.libraryList();
    return [
      for (final b in books)
        BookSummaryData(
          id: b.id,
          title: b.title,
          authors: b.authors,
          language: b.language,
          format: b.format,
        ),
    ];
  }

  @override
  Future<BookSummaryData> import(String path) async {
    final b = await rust.libraryImport(path: path);
    return BookSummaryData(
      id: b.id,
      title: b.title,
      authors: b.authors,
      language: b.language,
      format: b.format,
    );
  }

  @override
  Future<BookViewData> openBook(String id) async {
    final view = await rust.bookOpen(id: id);
    return BookViewData(
      id: view.id,
      title: view.title,
      chapters: [
        for (final c in view.chapters)
          ChapterData(title: c.title, text: c.text),
      ],
    );
  }

  @override
  Future<void> remove(String id) => rust.libraryRemove(id: id);

  @override
  Future<String> chapterHtml(String bookId, String href) =>
      rust.bookChapterHtml(id: bookId, href: href);

  @override
  Future<Uint8List> resource(String bookId, String path) =>
      rust.bookResource(id: bookId, path: path);

  @override
  Future<void> saveProgress(String bookId, String href, double progression) =>
      rust.progressSave(id: bookId, href: href, progression: progression);

  @override
  Future<ProgressData?> loadProgress(String bookId) async {
    final p = await rust.progressGet(id: bookId);
    return p == null ? null : ProgressData(href: p.href, progression: p.progression);
  }
}
