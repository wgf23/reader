/// 听书：合成（TTS）与播放编排（设计：docs/02-technical.md §11、docs/03-architecture.md §13）。
///
/// - `SystemTtsEngine`：flutter_tts 封装系统 TTS（Windows SAPI / macOS AVSpeech /
///   Linux speech-dispatcher / Android TextToSpeech / iOS AVSpeechSynthesizer），完全离线；
/// - P2：`PiperLocalEngine`（本地神经音色，按需下载）、`OnlineAiEngine`（火山/Azure，显式授权）。
///
/// 后台播放与系统媒体控制由 `audio_service` 统一接入（桌面媒体键、移动端通知栏/锁屏）。
/// 分层（ddd-rules.toml）：本文件属 interface 层，禁止 import `src/rust/**`（只经 services）。
abstract class TtsEngine {
  /// 配置音色与语速（0.5–3.0x）。
  Future<void> configure({required String voiceId, required double speed});

  /// 朗读一个句子块；完成回调经 [events] 派发。
  Future<void> speak(SentenceChunk chunk);

  Future<void> pause();
  Future<void> resume();
  Future<void> stop();

  /// 句完成 / 失败 / 中断 事件流。
  Stream<TtsEvent> get events;
}

/// 句级位置（与桥接 DTO `LocatorView` 一一对应；ADR 决策点1b）
class SentenceLocator {
  const SentenceLocator({
    required this.bookId,
    required this.href,
    required this.progression,
    required this.totalProgression,
    this.snippet,
  });

  final String bookId;
  final String href;

  /// 章内进度 0..1
  final double progression;

  /// 全书进度（本期=章内近似，仅展示）
  final double totalProgression;

  /// 文本锚片段（句前缀）
  final String? snippet;
}

/// 朗读句子块（与桥接 DTO `SentenceChunkView` / Rust `tts::SentenceChunk` 对应）
class SentenceChunk {
  const SentenceChunk({
    required this.index,
    required this.text,
    required this.charStart,
    required this.charEnd,
    required this.locator,
  });

  /// 章内句序号（`TtsSentenceDone` 的唯一依据，seek 后仍正确）
  final int index;
  final String text;

  /// UTF-16 code unit，半开区间 `[start, end)`
  final int charStart;
  final int charEnd;
  final SentenceLocator locator;
}

/// 播放事件（`sealed`：新增子类时 `ListenPage` 的 `switch` 编译期强制补分支）
sealed class TtsEvent {}

/// 当前句开始朗读（平台 `speak.onStart`；REQ-006 US-5）。
///
/// **仅用于确认高亮/滚动锚点，不得写盘**（听读同进度不变式）。
class TtsSentenceStarted extends TtsEvent {
  TtsSentenceStarted(this.sentenceIndex);

  final int sentenceIndex;
}

class TtsSentenceDone extends TtsEvent {
  TtsSentenceDone(this.sentenceIndex);

  final int sentenceIndex;
}

/// 无匹配系统音色，已回退默认音色（REQ-006 US-21；用于"系统默认音色"提示）。
class TtsVoiceFallback extends TtsEvent {
  TtsVoiceFallback(this.requestedVoiceId);

  final String requestedVoiceId;
}

class TtsFailed extends TtsEvent {
  TtsFailed(this.message);

  final String message;
}
