/// Rust 核心翻译/词典后端：经 flutter_rust_bridge 调用 `reader_core`，生成类型转 DTO。
/// 设计：REQ-003 02-design §5.1；仿 rust_library_backend.dart。
library;

import 'frb_init.dart';
import 'package:reader_app/src/rust/api.dart' as rust;

import 'translate_backend.dart';

/// flutter_rust_bridge 实现的词典/翻译后端
class RustTranslateBackend implements TranslateBackend {
  @override
  Future<DictInfoData> installDict(String path) async {
    final info = await rust.dictInstall(path: path);
    return DictInfoData(
      id: info.id,
      name: info.name,
      wordCount: info.wordCount.toInt(),
      path: info.path,
    );
  }

  @override
  Future<void> removeDict(String id) => rust.dictRemove(dictId: id);

  @override
  Future<List<DictInfoData>> listDicts() async {
    final list = await rust.dictList();
    return [
      for (final i in list)
        DictInfoData(
          id: i.id,
          name: i.name,
          wordCount: i.wordCount.toInt(),
          path: i.path,
        ),
    ];
  }

  @override
  Future<DictEntryData?> lookup(String word, {String? dictId}) async {
    final e = await rust.dictLookup(word: word, dictId: dictId);
    if (e == null) return null;
    return DictEntryData(
      word: e.word,
      phonetic: e.phonetic,
      pos: e.pos,
      definition: e.definition,
      example: e.example,
    );
  }

  @override
  Future<TranslationData> translate(
    String text, {
    String from = 'auto',
    String to = 'zh',
  }) async {
    final t = await rust.translate(text: text, from: from, to: to);
    return TranslationData(
      text: t.text,
      from: t.from,
      to: t.to,
      provider: t.provider,
      fromCache: t.fromCache,
    );
  }

  @override
  Future<void> clearCache() => rust.translateCacheClear();

  @override
  Future<void> setConfig(String provider, String key) =>
      rust.translateSetConfig(provider: provider, key: key);
}

/// 确保 Rust 库已加载（RustLibraryBackend.open 之外，翻译后端首次使用前调用）
Future<void> ensureTranslateBackendInit() => ensureRustLib();
