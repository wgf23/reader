/// 听书：合成（TTS）与播放编排（设计：docs/02-technical.md §11、docs/03-architecture.md §13）。
///
/// 骨架期仅定义接口；P1 实现：
/// - `SystemTtsEngine`：flutter_tts 封装系统 TTS（Windows SAPI / macOS AVSpeech /
///   Linux speech-dispatcher / Android TextToSpeech / iOS AVSpeechSynthesizer），完全离线；
/// - P2：`PiperLocalEngine`（本地神经音色，按需下载）、`OnlineAiEngine`（火山/Azure，显式授权）。
///
/// 后台播放与系统媒体控制由 `audio_service` 统一接入（桌面媒体键、移动端通知栏/锁屏）。
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

/// 朗读句子块（与 Rust core `tts::SentenceChunk` 对应）
class SentenceChunk {
  const SentenceChunk({
    required this.text,
    required this.charStart,
    required this.charEnd,
    required this.totalProgression,
  });

  final String text;
  final int charStart;
  final int charEnd;
  final double totalProgression;
}

/// 播放事件
sealed class TtsEvent {}

class TtsSentenceDone extends TtsEvent {
  TtsSentenceDone(this.sentenceIndex);

  final int sentenceIndex;
}

class TtsFailed extends TtsEvent {
  TtsFailed(this.message);

  final String message;
}
