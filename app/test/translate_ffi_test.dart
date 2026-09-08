// REQ-006 翻译端到端桥接测试：Dart `RustTranslateBackend` 适配层
// （DTO 映射 / getConfig / setStrategy / fallbackReason）。
//
// 依赖 Rust cdylib 产物与自造词库语料，缺失时自动跳过（保证普通 `flutter test` 全绿）。
// 运行方式：
//   READER_CORE_SO=../core/target/release/libreader_core.so \
//   READER_CORPUS_DICTS=../core/tests/corpus/src/dicts \
//   flutter test test/translate_ffi_test.dart
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/services/rust_translate_backend.dart';
import 'package:reader_app/src/rust/api.dart' as rust;
import 'package:reader_app/src/rust/frb_generated.dart';

/// 定位自造词库目录：优先 `READER_CORPUS_DICTS`，否则按仓库相对路径推导。
String? _findDictsDir() {
  final env = Platform.environment['READER_CORPUS_DICTS'];
  if (env != null && Directory(env).existsSync()) return env;
  const candidates = [
    '/home/heiwa/workspace/reader/core/tests/corpus/src/dicts',
    '../core/tests/corpus/src/dicts',
    'core/tests/corpus/src/dicts',
    '/root/reader/core/tests/corpus/src/dicts',
  ];
  for (final c in candidates) {
    if (Directory(c).existsSync()) return c;
  }
  return null;
}

void main() {
  const env = String.fromEnvironment('READER_CORE_SO');
  final soPath = env.isNotEmpty
      ? env
      : Platform.environment['READER_CORE_SO'] ?? 'libreader_core.so';

  test('FFI：RustTranslateBackend DTO 映射 / 策略 / 回退原因（US-10/13/15/17/18）',
      () async {
    final so = File(soPath);
    if (!so.existsSync()) {
      markTestSkipped('未找到 Rust 动态库：$soPath（先 cargo build --release）');
      return;
    }
    final dictsDir = _findDictsDir();
    if (dictsDir == null) {
      markTestSkipped('未找到自造词库语料目录（可用 READER_CORPUS_DICTS=... 指定）');
      return;
    }
    final ifo = '$dictsDir/test-tgmx/test-tgmx.ifo';
    if (!File(ifo).existsSync()) {
      markTestSkipped('自造词库缺失：$ifo');
      return;
    }

    await RustLib.init(externalLibrary: frb.ExternalLibrary.open(soPath));
    final dataDir = Directory.systemTemp.createTempSync('reader_ffi_translate');
    await rust.libraryOpen(dataDir: dataDir.path);

    final backend = RustTranslateBackend();

    // 安装/列表/查词：RustTranslateBackend 适配层映射
    final info = await backend.installDict(ifo);
    expect(info.name, 'Test TGMX Dictionary');
    expect(info.wordCount, greaterThan(0));
    expect((await backend.listDicts()).first.id, info.id);
    final entry = await backend.lookup('book');
    expect(entry, isNotNull);
    expect(entry!.word, 'book');
    expect(entry.definition, isNotEmpty);
    expect(await backend.lookup('zzzqqq'), isNull);

    // US-15：默认策略 auto、无 key、无掩码
    final cfg0 = await backend.getConfig();
    expect(cfg0.provider, 'auto');
    expect(cfg0.hasDeeplKey, isFalse);
    expect(cfg0.deeplKeyMasked, isNull);

    // US-13/US-17：auto + 未配置 key → 回退 offline，带回 fallbackReason（DTO 映射）
    final off = await backend.translate('Hello', from: 'en', to: 'zh');
    expect(off.provider, 'offline');
    expect(off.fromCache, isFalse);
    expect(off.fallbackReason, '未配置在线翻译 API Key，已回退离线');

    // US-10/US-18：echo 策略无 key 演示 → 在线标签语义、无回退原因；命中缓存
    await backend.setConfig('echo', '');
    expect((await backend.getConfig()).provider, 'echo');
    final echo = await backend.translate('Hello world', from: 'en', to: 'zh');
    expect(echo.provider, 'echo');
    expect(echo.text, '译文:Hello world');
    expect(echo.fallbackReason, isNull);
    final echo2 = await backend.translate('Hello world', from: 'en', to: 'zh');
    expect(echo2.fromCache, isTrue);

    // US-15：策略往返 + 未知策略报错
    await backend.setStrategy('offline');
    expect((await backend.getConfig()).provider, 'offline');
    await backend.setStrategy('auto');
    expect((await backend.getConfig()).provider, 'auto');
    expect(() => backend.setStrategy('nope'), throwsA(anything));

    // US-15：配置 key → 掩码回填（绝不回明文）；此处不发起网络请求
    await backend.setConfig('deepl', 'dummy-key-for-test');
    final cfg1 = await backend.getConfig();
    expect(cfg1.hasDeeplKey, isTrue);
    expect(cfg1.deeplKeyMasked, '••••••••');

    // 清理
    await backend.clearCache();
    await backend.removeDict(info.id);
    expect(await backend.listDicts(), isEmpty);
    dataDir.deleteSync(recursive: true);
  });
}
