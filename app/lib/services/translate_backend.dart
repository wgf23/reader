/// 词典/翻译后端抽象：UI 只面向此接口编程，测试注入 Fake。
/// 设计：REQ-003 02-design §5.1；docs/07 §6（分层合规：页面禁止直接 import 桥接
/// 生成物，只能经 services 拿 DTO）。
library;

/// 词条 DTO（US-1/16 渲染字段；空值 UI 不渲染）
class DictEntryData {
  const DictEntryData({
    required this.word,
    this.phonetic,
    this.pos,
    required this.definition,
    this.example,
  });

  final String word;
  final String? phonetic;
  final String? pos;
  final String definition;
  final String? example;
}

/// 已安装词库信息（US-7）
class DictInfoData {
  const DictInfoData({
    required this.id,
    required this.name,
    required this.wordCount,
    required this.path,
  });

  final String id;
  final String name;
  final int wordCount;
  final String path;
}

/// 译文 DTO（fromCache 命中缓存标记，US-13/15 可断言）
class TranslationData {
  const TranslationData({
    required this.text,
    required this.from,
    required this.to,
    required this.provider,
    required this.fromCache,
  });

  final String text;
  final String from;
  final String to;
  final String provider;
  final bool fromCache;
}

abstract class TranslateBackend {
  Future<DictInfoData> installDict(String path);
  Future<void> removeDict(String id);
  Future<List<DictInfoData>> listDicts();
  Future<DictEntryData?> lookup(String word, {String? dictId});
  Future<TranslationData> translate(
    String text, {
    String from = 'auto',
    String to = 'zh',
  });
  Future<void> clearCache();
  Future<void> setConfig(String provider, String key);
}
