import 'package:reader_app/services/translate_backend.dart';

/// 测试用词典/翻译后端（注入 ReaderPage/SettingsPage，避免依赖 Rust 动态库）。
/// 可配置行为：译文文案、缓存标记、查词结果、失败次数（第 N 次失败后成功）。
class FakeTranslateBackend implements TranslateBackend {
  FakeTranslateBackend({
    this.installedDicts = const [],
    this.translationText = '译文:Hello world',
    this.fromCache = false,
    this.fallbackReason,
    this.translationProvider = 'echo',
    this.lookupResult,
    this.translateFailures = 0,
    this.lookupFailures = 0,
    this.lookupError,
    this.translateError,
    this.delay = Duration.zero,
    this.configProvider = 'auto',
    this.hasDeeplKey = false,
    this.deeplKeyMasked,
  });

  final List<DictInfoData> installedDicts;
  final String translationText;
  final bool fromCache;
  final String? fallbackReason;
  final String translationProvider;
  final DictEntryData? lookupResult;
  int translateFailures; // 前 N 次翻译调用失败
  int lookupFailures; // 前 N 次查词调用失败
  String? lookupError; // 查词固定错误（如"未安装词库…"）
  String? translateError;

  /// 模拟网络/处理耗时（loading 态断言用）
  final Duration delay;

  final List<String> installed = [];
  final List<String> removed = [];
  int translateCalls = 0;
  int lookupCalls = 0;
  int clearCalls = 0;
  String? lastConfigProvider;
  String? lastConfigKey;
  String? lastTranslatedText;

  /// REQ-006：getConfig/setStrategy 可断言状态。
  String configProvider;
  bool hasDeeplKey;
  String? deeplKeyMasked;
  String? lastStrategy;

  @override
  Future<DictInfoData> installDict(String path) async {
    installed.add(path);
    final info = DictInfoData(id: 'd1', name: '测试词库', wordCount: 26, path: path);
    return info;
  }

  @override
  Future<void> removeDict(String id) async {
    removed.add(id);
  }

  @override
  Future<List<DictInfoData>> listDicts() async => installedDicts;

  @override
  Future<DictEntryData?> lookup(String word, {String? dictId}) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    lookupCalls++;
    if (lookupFailures > 0) {
      lookupFailures--;
      throw Exception(lookupError ?? '查词失败');
    }
    if (lookupError != null) throw Exception(lookupError!);
    return lookupResult;
  }

  @override
  Future<TranslationData> translate(
    String text, {
    String from = 'auto',
    String to = 'zh',
  }) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    translateCalls++;
    lastTranslatedText = text;
    if (translateFailures > 0) {
      translateFailures--;
      throw Exception(translateError ?? '网络请求失败（原文：$text）');
    }
    return TranslationData(
      text: '$translationText[$translateCalls]',
      from: from,
      to: to,
      provider: translationProvider,
      fromCache: fromCache,
      fallbackReason: fallbackReason,
    );
  }

  @override
  Future<void> clearCache() async {
    clearCalls++;
  }

  @override
  Future<void> setConfig(String provider, String key) async {
    lastConfigProvider = provider;
    lastConfigKey = key;
    if (provider == 'deepl') {
      // 保存非空 key → 已配置；空串 → 清除（与空 key 保存语义一致）。
      hasDeeplKey = key.trim().isNotEmpty;
      deeplKeyMasked = hasDeeplKey ? (deeplKeyMasked ?? '••••••••') : null;
    }
  }

  @override
  Future<TranslateConfigData> getConfig() async => TranslateConfigData(
        provider: configProvider,
        hasDeeplKey: hasDeeplKey,
        deeplKeyMasked: hasDeeplKey ? (deeplKeyMasked ?? '••••••••') : null,
      );

  @override
  Future<void> setStrategy(String strategy) async {
    lastStrategy = strategy;
    configProvider = strategy;
  }
}
