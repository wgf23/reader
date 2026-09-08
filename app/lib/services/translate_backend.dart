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
    this.fallbackReason,
  });

  final String text;
  final String from;
  final String to;
  final String provider;
  final bool fromCache;

  /// 回退原因（REQ-006 US-17/18；如"在线失败，已回退离线"），未回退为 null。
  final String? fallbackReason;
}

/// 翻译配置 DTO（REQ-006 US-15；**key 仅掩码，绝不含明文**）
class TranslateConfigData {
  const TranslateConfigData({
    required this.provider,
    required this.hasDeeplKey,
    this.deeplKeyMasked,
  });

  /// "auto" | "offline" | "deepl" | "echo"
  final String provider;
  final bool hasDeeplKey;

  /// 固定掩码；无 key 为 null。
  final String? deeplKeyMasked;
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

  /// 读取当前翻译配置（策略 + 是否已配置 DeepL key + 掩码；REQ-006 US-15）
  Future<TranslateConfigData> getConfig();

  /// 设置翻译策略（"auto"/"offline"/"deepl"/"echo"；REQ-006 US-15）
  Future<void> setStrategy(String strategy);
}
