// REQ-009 · FFI 桥接端到端：RustNotesBackend / RustSearchBackend 映射与真实 FTS。
//
// 依赖 Rust cdylib；未提供时自动跳过（普通 `flutter test` 全绿）。
// 运行：
//   READER_CORE_SO=core/target/release/libreader_core.so flutter test \
//     --coverage test/notes_search_ffi_test.dart
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/services/notes_backend.dart';
import 'package:reader_app/services/rust_library_backend.dart';
import 'package:reader_app/services/rust_notes_backend.dart';
import 'package:reader_app/services/rust_search_backend.dart';
import 'package:reader_app/services/search_backend.dart';
import 'package:reader_app/src/rust/api.dart' as rust;
import 'package:reader_app/src/rust/frb_generated.dart';

String? _findCorpus() {
  final env = Platform.environment['READER_CORPUS'];
  if (env != null && File(env).existsSync()) return env;
  for (final c in <String>[
    '../core/tests/corpus/src/hongloumeng.epub',
    'core/tests/corpus/src/hongloumeng.epub',
    '${Directory.current.path}/../core/tests/corpus/src/hongloumeng.epub',
  ]) {
    if (File(c).existsSync()) return c;
  }
  return null;
}

void main() {
  const env = String.fromEnvironment('READER_CORE_SO');
  final soPath = env.isNotEmpty
      ? env
      : Platform.environment['READER_CORE_SO'] ?? 'libreader_core.so';

  test('FFI：笔记 CRUD/书签/导出 + 搜索映射（真实 Rust 后端）', () async {
    final so = File(soPath);
    if (!so.existsSync()) {
      markTestSkipped('未找到 Rust 动态库：$soPath');
      return;
    }
    final corpus = _findCorpus();
    if (corpus == null) {
      markTestSkipped('未找到中文语料（可用 READER_CORPUS=... 指定）');
      return;
    }
    await RustLib.init(externalLibrary: frb.ExternalLibrary.open(soPath));

    final dataDir = Directory.systemTemp.createTempSync('req009_ffi');
    addTearDown(() => dataDir.deleteSync(recursive: true));
    await rust.libraryOpen(dataDir: dataDir.path);

    final book = await rust.libraryImport(path: corpus);
    final view = await rust.bookOpen(id: book.id);
    // RustLibraryBackend 映射 href（REQ-009 新增字段）
    final libView = await RustLibraryBackend().openBook(book.id);
    expect(libView.chapters.length, view.chapters.length);
    expect(libView.chapters.first.href, isNotEmpty);
    // 选一个有中文正文的章节（跳过封面/目录/英文版权页）
    final chapter = view.chapters.firstWhere((c) =>
        c.text.length > 50 && RegExp(r'[\u4e00-\u9fff]{2,}').hasMatch(c.text));
    expect(chapter.href, isNotEmpty);

    final notes = RustNotesBackend();

    // 创建高亮（文本锚映射）：取首个 ≥2 字的中文连续段
    final word = RegExp(r'[\u4e00-\u9fff]{2,}')
        .firstMatch(chapter.text)!
        .group(0)!;
    final snippet = word.length >= 4 ? word.substring(0, 4) : word;
    final query = snippet.substring(0, 2);
    final created = await notes.create(
      bookId: book.id,
      href: chapter.href,
      text: snippet,
      progression: 0.1,
      kind: 'highlight',
      color: '#FBC02D',
    );
    expect(created.id, isNotEmpty);
    expect(created.bookId, book.id);
    expect(created.kind, 'highlight');
    expect(created.color, '#FBC02D');
    expect(created.snippet, snippet);
    expect(created.start, isNotNull);
    expect(created.end, isNotNull);
    expect(created.start, lessThan(created.end!));

    // 空批注 → Rust 侧拒绝
    await expectLater(
      notes.create(
        bookId: book.id,
        href: chapter.href,
        text: snippet,
        progression: 0.1,
        kind: 'note',
        noteText: '   ',
      ),
      throwsA(anything),
    );

    // 列表分组映射
    final groups = await notes.list(book.id);
    expect(groups, isNotEmpty);
    expect(groups.first.notes.map((n) => n.id), contains(created.id));

    // 更新颜色 + 批注
    await notes.update(
      created.id,
      const NotePatchData(color: '#1A73E8', noteText: 'FFI 批注'),
    );
    final after = (await notes.list(book.id))
        .expand((g) => g.notes)
        .firstWhere((n) => n.id == created.id);
    expect(after.color, '#1A73E8');
    expect(after.noteText, 'FFI 批注');

    // 书签幂等
    final on = await notes.toggleBookmark(
      bookId: book.id,
      href: chapter.href,
      progression: 0.3,
      snippet: snippet,
    );
    expect(on.bookmarked, isTrue);
    expect(on.noteId, isNotNull);
    final off = await notes.toggleBookmark(
      bookId: book.id,
      href: chapter.href,
      progression: 0.3,
      snippet: snippet,
    );
    expect(off.bookmarked, isFalse);

    // resolve 映射为 href + progression
    final loc = await notes.resolve(created.id);
    expect(loc.href, chapter.href);
    expect(loc.progression, greaterThanOrEqualTo(0.0));

    // 导出（真实写文件）
    final mdPath = '${dataDir.path}/notes.md';
    final summary = await notes.export(book.id, 'markdown', mdPath);
    expect(summary.noteCount, greaterThanOrEqualTo(1));
    expect(File(mdPath).existsSync(), isTrue);
    expect(File(mdPath).readAsStringSync(), contains(snippet));

    // 搜索映射：2 字 CJK 命中真实 FTS
    final search = RustSearchBackend();
    final hits = await search.search(
      query,
      const SearchScopeData(allBooks: true),
    );
    expect(hits, isNotEmpty);
    final h = hits.first;
    expect(h.bookId, isNotEmpty);
    expect(h.bookTitle, isNotEmpty);
    expect(h.snippet, isNotEmpty);
    expect(h.ranges, isNotEmpty);
    expect(h.ranges.first.end, greaterThan(h.ranges.first.start));

    // 当前书 scope + 空查询短路
    final scoped = await search.search(
      query,
      SearchScopeData(allBooks: false, bookId: book.id),
    );
    expect(scoped.every((e) => e.bookId == book.id), isTrue);
    expect(await search.search('   ', const SearchScopeData()), isEmpty);

    // 单条删除（幂等）
    final temp = await notes.create(
      bookId: book.id,
      href: chapter.href,
      text: snippet,
      progression: 0.6,
      kind: 'underline',
      color: '#43A047',
    );
    await notes.delete(temp.id);
    await notes.delete(temp.id); // 幂等
    expect(
      (await notes.list(book.id)).expand((g) => g.notes).any((n) => n.id == temp.id),
      isFalse,
    );

    // 批量删除 + 全部删除
    final many = await notes.deleteMany([created.id]);
    expect(many, greaterThanOrEqualTo(0));
    final all = await notes.deleteAll(book.id);
    expect(all, greaterThanOrEqualTo(0));
    expect(await notes.list(book.id), isEmpty);
  });
}
