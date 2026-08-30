// 端到端桥接测试：Dart → flutter_rust_bridge → reader_core（真实 EPUB 导入）。
//
// 依赖 Rust cdylib 产物，未提供时自动跳过（保证普通 `flutter test` 全绿）。
// 运行方式：
//   READER_CORE_SO=<core/target/release/libreader_core.so> flutter test test/rust_bridge_test.dart
//   （或 --dart-define=READER_CORE_SO=...）
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/src/rust/api.dart' as rust;
import 'package:reader_app/src/rust/frb_generated.dart';

void main() {
  const env = String.fromEnvironment('READER_CORE_SO');
  final soPath = env.isNotEmpty
      ? env
      : Platform.environment['READER_CORE_SO'] ?? 'libreader_core.so';

  test('FFI：导入真实中文 EPUB 并打开章节', () async {
    final so = File(soPath);
    if (!so.existsSync()) {
      markTestSkipped('未找到 Rust 动态库：$soPath（先构建 core，或用 '
          '--dart-define=READER_CORE_SO=... 指定）');
      return;
    }
    await RustLib.init(externalLibrary: frb.ExternalLibrary.open(soPath));

    final dataDir = Directory.systemTemp.createTempSync('reader_ffi_test');
    await rust.libraryOpen(dataDir: dataDir.path);

    final corpus = Platform.environment['READER_CORPUS'] ??
        '/home/heiwa/workspace/reader/core/tests/corpus/src/hongloumeng.epub';
    final book = await rust.libraryImport(path: corpus);
    expect(book.title, contains('樓夢'));
    expect(book.format, 'epub');

    final view = await rust.bookOpen(id: book.id);
    expect(view.chapters.length, greaterThanOrEqualTo(5));
    expect(view.chapters.first.text.length, greaterThan(0));

    final books = await rust.libraryList();
    expect(books.length, 1);
  });
}
