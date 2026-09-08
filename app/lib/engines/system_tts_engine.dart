/// 系统 TTS 引擎（离线）：封装 `flutter_tts`（REQ-005 · ADR 决策点3，REQ-006 · 决策点3/6）。
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
    _tts.setStartHandler(_onStart);
  }

  /// 朗读语言（REQ-006 决策点6：本期固定 `zh-CN`，多语言朗读留后续 REQ）
  static const String language = 'zh-CN';

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
    // 顺序契约（US-3）：awaitSpeakCompletion(true) → setLanguage('zh-CN')
    //   → setSpeechRate(speed) → _applyVoice(voiceId)
    // 平台不支持时返回 0 或抛错，均不阻断后续 speak（US-3 第 2 句）。
    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {
      // 平台不支持完成等待 → 仅作设置，不参与推进（ADR 决策点3）
    }
    try {
      await _tts.setLanguage(language);
    } catch (_) {
      // 语言不可用不抛错、不阻断（Android 返回 0 静默）
    }
    await _tts.setSpeechRate(speed);
    await _applyVoice(voiceId);
  }

  /// 按逻辑音色（system_male/system_female）在系统音色表里挑一个；
  /// 无匹配/枚举失败/setVoice 返回 0 或抛错 → `clearVoice()` 恢复默认 + `TtsVoiceFallback`
  /// （US-21：不把逻辑名当真实系统音色名）。
  Future<void> _applyVoice(String voiceId) async {
    Map<String, String>? voice;
    try {
      final voices = await _tts.getVoices;
      voice = _pickVoice(voices, voiceId);
    } catch (_) {
      voice = null;
    }
    if (voice == null) {
      await _clearVoiceAndFallback(voiceId);
      return;
    }
    try {
      final r = await _tts.setVoice(voice);
      if (r == 0 || r == false) {
        await _clearVoiceAndFallback(voiceId);
      }
    } catch (_) {
      await _clearVoiceAndFallback(voiceId);
    }
  }

  Future<void> _clearVoiceAndFallback(String voiceId) async {
    try {
      await _tts.clearVoice();
    } catch (_) {
      // 平台不支持 clearVoice → 保持系统默认音色（降级线），仍上报回退提示
    }
    _emit(TtsVoiceFallback(voiceId));
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
    // 立即返回、不 await 完成：推进只由 TtsSentenceDone 事件驱动（ADR 决策点3）；
    // Future 仅用于失败检测（返回 0/false 或异常 → TtsFailed，US-4）。
    unawaited(
      _tts
          .speak(chunk.text, focus: true)
          .then((dynamic r) {
            if (r == 0 || r == false) {
              _emit(TtsFailed('朗读未开始（引擎忙或不可用）'));
            }
          })
          .catchError((Object e) {
            _emit(TtsFailed('$e'));
          }),
    );
  }

  @override
  Future<void> pause() => _tts.pause();

  @override
  Future<void> resume() async {
    // flutter_tts 无独立 resume：从当前句重读（完成回调仍只发一次 Done）。
    // 统一走 speak 路径（focus:true、失败可见，ADR 决策点3）。
    final c = _current;
    if (c == null) return;
    await speak(c);
  }

  @override
  Future<void> stop() async {
    _current = null;
    await _tts.stop();
  }

  void _onStart() {
    // `_current` 可能为 null（stop 后平台迟到回调）→ 必须判空。
    final c = _current;
    if (c != null) _emit(TtsSentenceStarted(c.index));
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
