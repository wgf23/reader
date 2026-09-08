/// 听书服务后端抽象（application 层）：切句/句↔Locator/听书设置。
///
/// 设计：REQ-005 02-design §2.4；UI（pages/engines/widgets）只面向此接口编程，
/// 测试注入 fake；生成物只在 `rust_tts_backend.dart` 里转换。
library;

import '../engines/tts_engine.dart';

/// 听书设置（与桥接 `ListenSettingsView` 一一对应）
class ListenSettingsData {
  const ListenSettingsData({
    required this.voiceId,
    required this.speed,
    required this.autoNext,
  });

  final String voiceId;

  /// 0.5..=3.0
  final double speed;
  final bool autoNext;

  ListenSettingsData copyWith({String? voiceId, double? speed, bool? autoNext}) {
    return ListenSettingsData(
      voiceId: voiceId ?? this.voiceId,
      speed: speed ?? this.speed,
      autoNext: autoNext ?? this.autoNext,
    );
  }
}

/// 听书后端（Rust 核心 / fake）
abstract class TtsBackend {
  /// 章文本 → 句列表（UTF-16 半开区间、章内句序号）
  Future<List<SentenceChunk>> segment(String bookId, String href);

  Future<SentenceLocator> locatorForSentence(
      String bookId, String href, int index);

  Future<int> sentenceIndexAt(
      String bookId, String href, SentenceLocator locator);

  Future<ListenSettingsData> loadListenSettings();

  Future<void> saveListenSettings(ListenSettingsData settings);
}
