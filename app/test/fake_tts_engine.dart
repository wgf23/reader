import 'dart:async';

import 'package:reader_app/engines/tts_engine.dart';

/// 测试用 TTS 引擎：记录调用序列 + 可控派发 [TtsSentenceDone]/[TtsFailed]。
class FakeTtsEngine implements TtsEngine {
  final List<String> calls = [];
  final List<String> spokenTexts = [];
  final List<int> spokenIndexes = [];
  String? lastVoiceId;
  double? lastSpeed;

  final StreamController<TtsEvent> _events =
      StreamController<TtsEvent>.broadcast();

  @override
  Stream<TtsEvent> get events => _events.stream;

  @override
  Future<void> configure({
    required String voiceId,
    required double speed,
  }) async {
    calls.add('configure');
    lastVoiceId = voiceId;
    lastSpeed = speed;
  }

  @override
  Future<void> speak(SentenceChunk chunk) async {
    calls.add('speak:${chunk.index}');
    spokenIndexes.add(chunk.index);
    spokenTexts.add(chunk.text);
  }

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> stop() async => calls.add('stop');

  /// 模拟一句开始朗读（REQ-006 US-5）
  void emitStarted(int sentenceIndex) =>
      _events.add(TtsSentenceStarted(sentenceIndex));

  /// 模拟一句朗读完成
  void emitDone(int sentenceIndex) =>
      _events.add(TtsSentenceDone(sentenceIndex));

  /// 模拟音色回退为系统默认（REQ-006 US-21）
  void emitVoiceFallback(String requestedVoiceId) =>
      _events.add(TtsVoiceFallback(requestedVoiceId));

  /// 模拟朗读失败（US-12）
  void emitFailed(String message) => _events.add(TtsFailed(message));

  Future<void> dispose() => _events.close();
}
