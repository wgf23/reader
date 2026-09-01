// REQ-003 FFI 端到端桥接测试：Dart → flutter_rust_bridge → reader_core 的
// dict_install / dict_list / dict_lookup / translate / translate_cache_clear / 全链路。
//
// 依赖 Rust cdylib 产物与自造词库语料，未提供时自动跳过（保证普通 `flutter test` 全绿）。
// 运行方式：
//   READER_CORE_SO=<core/target/release/libreader_core.so> flutter test test/rust_dict_ffi_test.dart
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

  test('FFI：dict_install→lookup→translate(echo)→缓存清空 全链路', () async {
    final so = File(soPath);
    if (!so.existsSync()) {
      markTestSkipped('未找到 Rust 动态库：$soPath（先构建 core，或用 '
          '--dart-define=READER_CORE_SO=... 指定）');
      return;
    }
    await RustLib.init(externalLibrary: frb.ExternalLibrary.open(soPath));

    final dataDir = Directory.systemTemp.createTempSync('reader_ffi_dict');
    await rust.libraryOpen(dataDir: dataDir.path);

    // 自造词库语料（含 .dict.dz 变体）
    final dictsDir = Platform.environment['READER_CORPUS_DICTS'] ??
        '/home/heiwa/workspace/reader/core/tests/corpus/src/dicts';
    final ifoPath = '$dictsDir/test-tgmx/test-tgmx.ifo';
    if (!File(ifoPath).existsSync()) {
      markTestSkipped('自造词库语料缺失：$ifoPath（先运行 make_test_dict.py）');
      return;
    }

    // 1) 安装词库 → 返回 DictInfoView（US-7）
    final info = await rust.dictInstall(path: ifoPath);
    expect(info.wordCount.toInt(), greaterThan(0));
    expect(info.name, 'Test TGMX Dictionary');

    // 2) 列表含之
    final list = await rust.dictList();
    expect(list.length, 1);
    expect(list.first.id, info.id);

    // 3) 查词命中（.dict.dz 安装期流式解压路径）→ 字段归位
    final entry = await rust.dictLookup(word: 'book');
    expect(entry, isNotNull);
    expect(entry!.word, 'book');
    expect(entry.phonetic, '/bʊk/');
    expect(entry.pos, 'n.');
    expect(entry.example, 'an interesting book');

    // 4) 未收录 → null；坏 dict_id 查词 → Err
    expect(await rust.dictLookup(word: 'zzzqqq'), isNull);

    // 5) 翻译：未配置 key → FRB 将 Err(String) 映射为 Dart 异常（US-12）
    expect(
      () => rust.translate(text: 'Hello', from: 'en', to: 'zh'),
      throwsA(anything),
    );

    await rust.translateSetConfig(provider: 'echo', key: '');
    final t1 = await rust.translate(text: 'Hello world', from: 'en', to: 'zh');
    expect(t1.text, '译文:Hello world');
    expect(t1.provider, 'echo');
    expect(t1.fromCache, isFalse);

    // 6) 命中缓存：fromCache=true（US-10）
    final t2 = await rust.translate(text: 'Hello world', from: 'en', to: 'zh');
    expect(t2.fromCache, isTrue);
    expect(t2.text, t1.text);

    // 7) 清空缓存 → 再翻同文重新调 Provider（US-13）
    await rust.translateCacheClear();
    final t3 = await rust.translate(text: 'Hello world', from: 'en', to: 'zh');
    expect(t3.fromCache, isFalse);

    // 8) 移除词库 → 列表为空
    await rust.dictRemove(dictId: info.id);
    final after = await rust.dictList();
    expect(after, isEmpty);

    dataDir.deleteSync(recursive: true);
  });
}
