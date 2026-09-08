// 听书端到端桥接测试：Dart → flutter_rust_bridge → reader_core（US-7/US-11）。
//
// 依赖 Rust cdylib 产物与中文语料；缺失时自动跳过（保证普通 `flutter test` 全绿）。
// 运行方式：
//   READER_CORE_SO=../core/target/release/libreader_core.so flutter test test/tts_ffi_test.dart
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/services/rust_tts_backend.dart';
import 'package:reader_app/services/tts_backend.dart';
import 'package:reader_app/src/rust/api.dart' as rust;
import 'package:reader_app/src/rust/frb_generated.dart';

String? _findCorpus() {
  final env = Platform.environment['READER_CORPUS'];
  if (env != null && File(env).existsSync()) return env;
  const candidates = [
    '/home/heiwa/workspace/reader/core/tests/corpus/src/hongloumeng.epub',
    '../core/tests/corpus/src/hongloumeng.epub',
    'core/tests/corpus/src/hongloumeng.epub',
    '/root/reader/core/tests/corpus/src/hongloumeng.epub',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return null;
}

void main() {
  const env = String.fromEnvironment('READER_CORE_SO');
  final soPath = env.isNotEmpty
      ? env
      : Platform.environment['READER_CORE_SO'] ?? 'libreader_core.so';

  test('FFI：tts_segment / locator 往返 / 听书设置（US-7/US-11）', () async {
    final so = File(soPath);
    if (!so.existsSync()) {
      markTestSkipped('未找到 Rust 动态库：$soPath（先 cargo build --release）');
      return;
    }
    final corpus = _findCorpus();
    if (corpus == null) {
      markTestSkipped('未找到中文语料（可用 READER_CORPUS=... 指定）');
      return;
    }

    await RustLib.init(externalLibrary: frb.ExternalLibrary.open(soPath));
    final dataDir = Directory.systemTemp.createTempSync('reader_tts_ffi');
    await rust.libraryOpen(dataDir: dataDir.path);
    final book = await rust.libraryImport(path: corpus);

    const href = 'chapter_0001.xhtml';
    final chunks = await rust.ttsSegment(bookId: book.id, href: href);
    expect(chunks, isNotEmpty, reason: '章节应切出非空句列表');
    // DTO 字段一一对应
    for (var i = 0; i < chunks.length; i++) {
      final c = chunks[i];
      expect(c.index, i);
      expect(c.text, isNotEmpty);
      expect(c.charEnd, greaterThan(c.charStart));
      expect(c.locator.bookId, book.id);
      expect(c.locator.href, href);
      expect(c.locator.progression, inInclusiveRange(0.0, 1.0));
      expect(c.locator.snippet, isNotNull);
      expect(c.text.startsWith(c.locator.snippet!), isTrue,
          reason: 'snippet 应为句前缀');
    }
    // 区间连续不重叠
    for (var i = 1; i < chunks.length; i++) {
      expect(chunks[i].charStart, chunks[i - 1].charEnd);
    }

    // 句 ↔ Locator 往返一致
    final sample = chunks.length > 5 ? 5 : chunks.length;
    for (var i = 0; i < sample; i++) {
      final loc = await rust.ttsLocatorForSentence(
          bookId: book.id, href: href, idx: i);
      final back = await rust.ttsSentenceIndexAt(
          bookId: book.id, href: href, locator: loc);
      expect(back, i, reason: '往返映射应一致');
    }

    // 听书设置：默认 → 写入读回 → speed clamp
    final defaults = await rust.ttsListenSettingsGet();
    expect(defaults.voiceId, 'system_male');
    expect(defaults.speed, 1.0);
    expect(defaults.autoNext, isTrue);

    await rust.ttsListenSettingsSet(
      settings: const rust.ListenSettingsView(
        voiceId: 'system_female',
        speed: 1.5,
        autoNext: false,
      ),
    );
    final read = await rust.ttsListenSettingsGet();
    expect(read.voiceId, 'system_female');
    expect(read.speed, closeTo(1.5, 1e-6));
    expect(read.autoNext, isFalse);

    await rust.ttsListenSettingsSet(
      settings: const rust.ListenSettingsView(
        voiceId: 'system_male',
        speed: 9.9,
        autoNext: true,
      ),
    );
    final clamped = await rust.ttsListenSettingsGet();
    expect(clamped.speed, 3.0, reason: 'speed 读回应 clamp 到 3.0');

    // ---------- RustTtsBackend 适配层（DTO ↔ domain 映射） ----------
    final backend = RustTtsBackend();
    final viaBackend = await backend.segment(book.id, href);
    expect(viaBackend.length, chunks.length, reason: '适配层与直接调用结果一致');
    expect(viaBackend.first.text, chunks.first.text);
    expect(viaBackend.first.charStart, chunks.first.charStart);
    expect(viaBackend.first.charEnd, chunks.first.charEnd);
    expect(viaBackend.first.locator.bookId, book.id);
    expect(viaBackend.first.locator.href, href);

    final loc0 = await backend.locatorForSentence(book.id, href, 0);
    expect(loc0.bookId, book.id);
    expect(loc0.href, href);
    expect(loc0.snippet, isNotNull);
    expect(await backend.sentenceIndexAt(book.id, href, loc0), 0);

    await backend.saveListenSettings(
      const ListenSettingsData(
        voiceId: 'system_female',
        speed: 1.25,
        autoNext: false,
      ),
    );
    final readBack = await backend.loadListenSettings();
    expect(readBack.voiceId, 'system_female');
    expect(readBack.speed, closeTo(1.25, 1e-6));
    expect(readBack.autoNext, isFalse);
  });
}
