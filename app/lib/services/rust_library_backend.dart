/// Rust 核心后端：经 flutter_rust_bridge 调用 `reader_core`，并把生成类型转换为 DTO。
/// 设计：docs/03-architecture.md §4、docs/04 §7、docs/07 §6。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:path_provider/path_provider.dart';

import '../src/rust/api.dart' as rust;
import '../src/rust/frb_generated.dart' as rustlib;
import 'library_backend.dart';

/// flutter_rust_bridge 实现的书库后端
class RustLibraryBackend implements LibraryBackend {
  static bool _initialized = false;

  /// 加载 Rust 动态库（只做一次）。
  /// - `--dart-define=READER_CORE_SO=<path>`：显式指定（开发期/桌面）；
  /// - Android：走 frb 默认 loader（.so 打包进 jniLibs，按 libreader_core.so 加载）；
  /// - 其他平台：按平台默认名（reader_core.dll / libreader_core.dylib / libreader_core.so）。
  Future<void> _ensureInit() async {
    if (_initialized) return;
    const env = String.fromEnvironment('READER_CORE_SO');
    if (env.isNotEmpty) {
      await rustlib.RustLib.init(externalLibrary: frb.ExternalLibrary.open(env));
    } else if (Platform.isAndroid) {
      await rustlib.RustLib.init();
    } else {
      await rustlib.RustLib.init(
        externalLibrary: frb.ExternalLibrary.open(_defaultSoName()),
      );
    }
    _initialized = true;
  }

  String _defaultSoName() {
    if (Platform.isWindows) return 'reader_core.dll';
    if (Platform.isMacOS) return 'libreader_core.dylib';
    return 'libreader_core.so';
  }

  @override
  Future<void> open() async {
    await _ensureInit();
    final dir = await getApplicationSupportDirectory();
    await rust.libraryOpen(dataDir: '${dir.path}/data');
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
