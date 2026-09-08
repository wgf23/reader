/// 系统 TTS 引擎（离线）：封装 `flutter_tts`（REQ-005 · ADR 决策点3，US-9/US-12）。
///
/// 分层：interface 层，只 import `flutter_tts` + `tts_engine.dart`，不碰桥接生成物。
library;

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'tts_engine.dart';

/// `flutter_tts` 实现的系统 TTS（离线，零体积）
class SystemTtsEngine implements TtsEngine {
  /// [tts] 供测试注入（fake 平台通道）；缺省用真实 `FlutterTts`。
  SystemTtsEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts() {
    _tts.setCompletionHandler(_onComplete);
    _tts.setCancelHandler(_onCancel);
    _tts.setErrorHandler(_onError);
  }

  final FlutterTts _tts;
  final StreamController<TtsEvent> _events =
      StreamController<TtsEvent>.broadcast();

  SentenceChunk? _current;
  bool _disposed = false;

  @override
  Stream<TtsEvent> get events => _events.stream;

  @override
  Future<void> configure({
    required String voiceId,
    required double speed,
  }) async {
    await _tts.setSpeechRate(speed);
    await _applyVoice(voiceId);
  }

  /// 按逻辑音色（system_male/system_female）在系统音色表里挑一个；不可用时回退默认。
  Future<void> _applyVoice(String voiceId) async {
    Map<String, String>? voice;
    try {
      final voices = await _tts.getVoices;
      voice = _pickVoice(voices, voiceId);
    } catch (_) {
      // 平台不支持枚举音色 → 回退默认系统音色（US-12 不阻断朗读）
    }
    voice ??= {'name': voiceId, 'locale': 'zh-CN'};
    try {
      await _tts.setVoice(voice);
    } catch (_) {
      // 系统缺目标语言/音色 → 回退默认系统音色（US-12）
    }
  }

  Map<String, String>? _pickVoice(dynamic voices, String voiceId) {
    if (voices is! List) return null;
    final want = voiceId.toLowerCase().contains('female') ? 'female' : 'male';
    for (final v in voices) {
      if (v is Map) {
        final name = '${v['name'] ?? ''}'.toLowerCase();
        if (name.contains(want)) {
          return {'name': '${v['name']}', 'locale': '${v['locale'] ?? ''}'};
        }
      }
    }
    return null;
  }

  @override
  Future<void> speak(SentenceChunk chunk) async {
    _current = chunk;
    await _tts.speak(chunk.text);
  }

  @override
  Future<void> pause() => _tts.pause();

  @override
  Future<void> resume() async {
    // flutter_tts 无独立 resume：从当前句重读（完成回调仍只发一次 Done）。
    final c = _current;
    if (c == null) return;
    await _tts.speak(c.text);
  }

  @override
  Future<void> stop() async {
    _current = null;
    await _tts.stop();
  }

  void _onComplete() {
    final c = _current;
    if (c != null) _emit(TtsSentenceDone(c.index));
  }

  void _onCancel() {}

  void _onError(dynamic message) => _emit(TtsFailed('$message'));

  void _emit(TtsEvent event) {
    if (!_disposed) _events.add(event);
  }

  /// 释放事件流（页面 dispose 时调用；不强制，便于测试复用）。
  Future<void> dispose() async {
    _disposed = true;
    await _events.close();
  }
}
