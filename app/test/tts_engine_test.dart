import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:reader_app/engines/system_tts_engine.dart';
import 'package:reader_app/engines/tts_engine.dart';

/// 平台通道 mock：子类化 FlutterTts，记录调用并可控触发完成/错误/开始回调。
class FakeFlutterTts extends FlutterTts {
  final List<String> calls = [];
  final List<Object?> args = [];
  VoidCallback? onComplete;
  VoidCallback? onCancel;
  VoidCallback? onStart;
  ErrorHandler? onError;

  /// 可控异常：模拟平台不支持枚举音色 / setVoice 失败 / 不支持语言或完成等待。
  bool throwGetVoices = false;
  bool throwSetVoice = false;
  bool throwAwaitCompletion = false;
  bool throwSetLanguage = false;

  /// setVoice 返回值（0/false 模拟平台拒绝该音色；默认 null=成功）。
  dynamic setVoiceResult;

  /// 覆盖 getVoices 返回值（可为非 List 以覆盖类型分支）。
  dynamic voicesOverride;

  /// speak 返回值（默认 1=成功；0/false 模拟引擎忙/不可用）。
  dynamic speakResult = 1;
  bool throwSpeak = false;

  /// 记录 speak 的 focus 参数（US-4）。
  final List<bool> speakFocus = [];

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {
    calls.add('awaitSpeakCompletion');
    args.add(awaitCompletion);
    if (throwAwaitCompletion) throw StateError('no awaitSpeakCompletion');
  }

  @override
  Future<dynamic> setLanguage(String language) async {
    calls.add('setLanguage');
    args.add(language);
    if (throwSetLanguage) throw StateError('no setLanguage');
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    calls.add('setSpeechRate');
    args.add(rate);
  }

  @override
  Future<dynamic> setVoice(Map<String, String> voice) async {
    calls.add('setVoice');
    args.add(voice);
    if (throwSetVoice) throw StateError('setVoice failed');
    return setVoiceResult;
  }

  @override
  Future<dynamic> clearVoice() async {
    calls.add('clearVoice');
  }

  @override
  Future<dynamic> get getVoices async {
    if (throwGetVoices) throw StateError('no voice enumeration');
    if (voicesOverride != null) return voicesOverride;
    return [
      {'name': 'zh-cn-x-sfg#male_1-local', 'locale': 'zh-CN'},
      {'name': 'zh-cn-x-sfg#female_1-local', 'locale': 'zh-CN'},
    ];
  }

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    calls.add('speak');
    args.add(text);
    speakFocus.add(focus);
    if (throwSpeak) throw StateError('speak failed');
    return speakResult;
  }

  @override
  Future<dynamic> pause() async => calls.add('pause');

  @override
  Future<dynamic> stop() async => calls.add('stop');

  @override
  void setCompletionHandler(VoidCallback callback) => onComplete = callback;

  @override
  void setErrorHandler(ErrorHandler handler) => onError = handler;

  @override
  void setCancelHandler(VoidCallback callback) => onCancel = callback;

  @override
  void setStartHandler(VoidCallback callback) => onStart = callback;
}

SentenceChunk _chunk(int index, String text) => SentenceChunk(
      index: index,
      text: text,
      charStart: 0,
      charEnd: text.length,
      locator: SentenceLocator(
        bookId: 'b1',
        href: 'chapter_0001.xhtml',
        progression: 0.0,
        totalProgression: 0.0,
        snippet: text,
      ),
    );

void main() {
  // FlutterTts 构造会设置平台通道 handler，需先初始化 binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SystemTtsEngine implements TtsEngine（US-9）', () {
    final engine = SystemTtsEngine(tts: FakeFlutterTts());
    expect(engine, isA<TtsEngine>());
  });

  test('configure 触发 setSpeechRate/setVoice（US-9）', () async {
    final tts = FakeFlutterTts();
    final engine = SystemTtsEngine(tts: tts);
    await engine.configure(voiceId: 'system_male', speed: 1.5);

    expect(tts.calls, containsAllInOrder(['setSpeechRate', 'setVoice']));
    final rateIndex = tts.calls.indexOf('setSpeechRate');
    expect(tts.args[rateIndex], 1.5);
    final voice = tts.args[tts.calls.indexOf('setVoice')] as Map;
    expect('${voice['name']}', contains('male'));
    await engine.dispose();
  });

  test('speak 触发 flutterTts.speak(chunk.text)（US-9）', () async {
    final tts = FakeFlutterTts();
    final engine = SystemTtsEngine(tts: tts);
    await engine.speak(_chunk(0, '你好世界。'));

    expect(tts.calls.last, 'speak');
    expect(tts.args.last, '你好世界。');
    await engine.dispose();
  });

  test('完成回调派发 TtsSentenceDone(chunk.index)（US-9/US-10）', () async {
    final tts = FakeFlutterTts();
    final engine = SystemTtsEngine(tts: tts);
    final events = <TtsEvent>[];
    engine.events.listen(events.add);

    await engine.speak(_chunk(7, '第七句。'));
    tts.onComplete!();
    await Future<void>.delayed(Duration.zero);

    expect(events.length, 1);
    expect(events.single, isA<TtsSentenceDone>());
    expect((events.single as TtsSentenceDone).sentenceIndex, 7);
    await engine.dispose();
  });

  test('错误回调派发 TtsFailed（US-12）', () async {
    final tts = FakeFlutterTts();
    final engine = SystemTtsEngine(tts: tts);
    final events = <TtsEvent>[];
    engine.events.listen(events.add);

    await engine.speak(_chunk(0, '一句。'));
    tts.onError!('language missing');
    await Future<void>.delayed(Duration.zero);

    expect(events.single, isA<TtsFailed>());
    expect((events.single as TtsFailed).message, contains('language missing'));
    await engine.dispose();
  });

  test('pause/resume/stop 转发（US-10）', () async {
    final tts = FakeFlutterTts();
    final engine = SystemTtsEngine(tts: tts);
    await engine.speak(_chunk(0, '一句。'));
    await engine.pause();
    await engine.resume();
    await engine.stop();

    expect(tts.calls.where((c) => c == 'pause').length, 1);
    expect(tts.calls.where((c) => c == 'speak').length, 2); // 初次 + resume 重读
    expect(tts.calls.where((c) => c == 'stop').length, 1);
    await engine.dispose();
  });

  test('离线约束：引擎/服务层无网络依赖（US-12）', () {
    for (final path in [
      'lib/engines/system_tts_engine.dart',
      'lib/services/tts_backend.dart',
      'lib/services/rust_tts_backend.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src.contains("package:http"), isFalse, reason: '$path 不应有 http 依赖');
      expect(src.contains('HttpClient'), isFalse, reason: '$path 不应有网络调用');
      expect(src.contains('just_audio'), isFalse, reason: '$path 不应启用 just_audio');
      expect(src.contains('audio_service'), isFalse, reason: '$path 不应启用 audio_service');
    }
  });

  // ---------- REQ-005-fixes 阶段4：音色回退/生命周期边界 ----------

  test('configure 女声：从系统音色表挑选 female（US-13）', () async {
    final tts = FakeFlutterTts();
    final engine = SystemTtsEngine(tts: tts);
    await engine.configure(voiceId: 'system_female', speed: 1.2);
    final voice = tts.args[tts.calls.indexOf('setVoice')] as Map;
    expect('${voice['name']}', contains('female'));
    expect(voice['locale'], 'zh-CN');
    await engine.dispose();
  });

  test('US-21 枚举音色失败 → clearVoice + TtsVoiceFallback，不传逻辑名且仍可 speak', () async {
    final tts = FakeFlutterTts()..throwGetVoices = true;
    final engine = SystemTtsEngine(tts: tts);
    final events = <TtsEvent>[];
    engine.events.listen(events.add);
    await engine.configure(voiceId: 'system_female', speed: 1.0);

    expect(tts.calls, isNot(contains('setVoice')), reason: '不得把逻辑名当真实音色名');
    expect(tts.calls, contains('clearVoice'));
    await Future<void>.delayed(Duration.zero);
    final fb = events.whereType<TtsVoiceFallback>().single;
    expect(fb.requestedVoiceId, 'system_female');

    await engine.speak(_chunk(0, '一句。'));
    expect(tts.calls.last, 'speak', reason: '音色回退不得阻断朗读');
    await engine.dispose();
  });

  test('US-21 getVoices 返回非 List → clearVoice + TtsVoiceFallback', () async {
    final tts = FakeFlutterTts()..voicesOverride = 'not-a-list';
    final engine = SystemTtsEngine(tts: tts);
    final events = <TtsEvent>[];
    engine.events.listen(events.add);
    await engine.configure(voiceId: 'system_male', speed: 1.0);
    expect(tts.calls, isNot(contains('setVoice')));
    expect(tts.calls, contains('clearVoice'));
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<TtsVoiceFallback>().single.requestedVoiceId, 'system_male');
    await engine.dispose();
  });

  test('US-21 getVoices 无 male/female → clearVoice + TtsVoiceFallback', () async {
    final tts = FakeFlutterTts()
      ..voicesOverride = [
        {'name': 'zh-cn-x-ccc-local', 'locale': 'zh-CN'},
      ];
    final engine = SystemTtsEngine(tts: tts);
    final events = <TtsEvent>[];
    engine.events.listen(events.add);
    await engine.configure(voiceId: 'system_male', speed: 1.0);
    expect(tts.calls, isNot(contains('setVoice')));
    expect(tts.calls, contains('clearVoice'));
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<TtsVoiceFallback>(), hasLength(1));
    await engine.dispose();
  });

  test('US-21 setVoice 抛错 → clearVoice + TtsVoiceFallback 不阻断', () async {
    final tts = FakeFlutterTts()..throwSetVoice = true;
    final engine = SystemTtsEngine(tts: tts);
    final events = <TtsEvent>[];
    engine.events.listen(events.add);
    await engine.configure(voiceId: 'system_male', speed: 1.0);
    expect(tts.calls, contains('setVoice'));
    expect(tts.calls, contains('clearVoice'));
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<TtsVoiceFallback>(), hasLength(1));
    await engine.speak(_chunk(0, '一句。'));
    expect(tts.calls.last, 'speak');
    await engine.dispose();
  });

  test('US-21 setVoice 返回 0 → clearVoice + TtsVoiceFallback 不阻断', () async {
    // 覆盖 _applyVoice 中 setVoice 成功返回但平台拒绝该音色（返回 0）的分支
    final tts = FakeFlutterTts()..setVoiceResult = 0;
    final engine = SystemTtsEngine(tts: tts);
    final events = <TtsEvent>[];
    engine.events.listen(events.add);
    await engine.configure(voiceId: 'system_male', speed: 1.0);
    expect(tts.calls, contains('setVoice'), reason: '先尝试真实音色名');
    expect(tts.calls, contains('clearVoice'), reason: '平台拒绝 → 恢复默认音色');
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<TtsVoiceFallback>(), hasLength(1));
    await engine.speak(_chunk(0, '一句。'));
    expect(tts.calls.last, 'speak', reason: '音色回退不得阻断朗读');
    await engine.dispose();
  });

  // ---------- REQ-006：调用序列 / 失败可见 / 焦点 / onStart ----------

  test('US-3 configure 序列：awaitSpeakCompletion → setLanguage(zh-CN) → setSpeechRate → setVoice，均在 speak 前', () async {
    final tts = FakeFlutterTts();
    final engine = SystemTtsEngine(tts: tts);
    await engine.configure(voiceId: 'system_male', speed: 1.5);

    expect(
      tts.calls,
      containsAllInOrder(
          ['awaitSpeakCompletion', 'setLanguage', 'setSpeechRate', 'setVoice']),
    );
    expect(tts.args[tts.calls.indexOf('awaitSpeakCompletion')], true);
    expect(tts.args[tts.calls.indexOf('setLanguage')], 'zh-CN');
    expect(tts.args[tts.calls.indexOf('setSpeechRate')], 1.5);

    await engine.speak(_chunk(0, '你好。'));
    expect(tts.calls.last, 'speak');
    await engine.dispose();
  });

  test('US-3 平台不支持 setLanguage/awaitSpeakCompletion → 不抛错且仍能 speak', () async {
    final tts = FakeFlutterTts()
      ..throwAwaitCompletion = true
      ..throwSetLanguage = true;
    final engine = SystemTtsEngine(tts: tts);
    await engine.configure(voiceId: 'system_male', speed: 1.0);
    await engine.speak(_chunk(0, '一句。'));
    expect(tts.calls.last, 'speak');
    await engine.dispose();
  });

  test('US-4 speak 传 focus:true（音频焦点）', () async {
    final tts = FakeFlutterTts();
    final engine = SystemTtsEngine(tts: tts);
    await engine.speak(_chunk(0, '一句。'));
    expect(tts.speakFocus.single, isTrue);
    await engine.dispose();
  });

  test('US-4 speak 返回 false → TtsFailed（不静默）', () async {
    final tts = FakeFlutterTts()..speakResult = false;
    final engine = SystemTtsEngine(tts: tts);
    final events = <TtsEvent>[];
    engine.events.listen(events.add);
    await engine.speak(_chunk(0, '一句。'));
    await Future<void>.delayed(Duration.zero);
    expect(events.single, isA<TtsFailed>());
    expect((events.single as TtsFailed).message, contains('朗读未开始'));
    await engine.dispose();
  });

  test('US-4 speak 返回 0 → TtsFailed', () async {
    final tts = FakeFlutterTts()..speakResult = 0;
    final engine = SystemTtsEngine(tts: tts);
    final events = <TtsEvent>[];
    engine.events.listen(events.add);
    await engine.speak(_chunk(0, '一句。'));
    await Future<void>.delayed(Duration.zero);
    expect(events.single, isA<TtsFailed>());
    await engine.dispose();
  });

  test('US-4 speak 抛错 → TtsFailed 含原因', () async {
    final tts = FakeFlutterTts()..throwSpeak = true;
    final engine = SystemTtsEngine(tts: tts);
    final events = <TtsEvent>[];
    engine.events.listen(events.add);
    await engine.speak(_chunk(0, '一句。'));
    await Future<void>.delayed(Duration.zero);
    expect((events.single as TtsFailed).message, contains('speak failed'));
    await engine.dispose();
  });

  test('US-4 完成回调恰好一次 TtsSentenceDone（speak Future 不重复推进）', () async {
    final tts = FakeFlutterTts();
    final engine = SystemTtsEngine(tts: tts);
    final events = <TtsEvent>[];
    engine.events.listen(events.add);
    await engine.speak(_chunk(4, '第四句。'));
    tts.onComplete!();
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<TtsSentenceDone>(), hasLength(1));
    expect(events.whereType<TtsSentenceDone>().single.sentenceIndex, 4);
    await engine.dispose();
  });

  test('US-5 构造时注册 setStartHandler；onStart → TtsSentenceStarted(index)', () async {
    final tts = FakeFlutterTts();
    final engine = SystemTtsEngine(tts: tts);
    expect(tts.onStart, isNotNull, reason: '必须注册 start handler');
    final events = <TtsEvent>[];
    engine.events.listen(events.add);
    await engine.speak(_chunk(3, '第三句。'));
    tts.onStart!();
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<TtsSentenceStarted>().single.sentenceIndex, 3);
    await engine.dispose();
  });

  test('US-5 _current 为 null 时 onStart 不抛错、不派发', () async {
    final tts = FakeFlutterTts();
    final engine = SystemTtsEngine(tts: tts);
    final events = <TtsEvent>[];
    engine.events.listen(events.add);
    tts.onStart!(); // 未 speak → _current==null
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    await engine.dispose();
  });

  test('resume 无当前句 → 不重读', () async {
    final tts = FakeFlutterTts();
    final engine = SystemTtsEngine(tts: tts);
    await engine.resume();
    expect(tts.calls.where((c) => c == 'speak'), isEmpty);
    await engine.dispose();
  });

  test('stop 清空当前句 → 完成回调不再派发', () async {
    final tts = FakeFlutterTts();
    final engine = SystemTtsEngine(tts: tts);
    final events = <TtsEvent>[];
    engine.events.listen(events.add);
    await engine.speak(_chunk(3, '第三句。'));
    await engine.stop();
    tts.onComplete!();
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty, reason: 'stop 后不应再上报 Done');
    await engine.dispose();
  });

  test('dispose 后不再派发事件', () async {
    final tts = FakeFlutterTts();
    final engine = SystemTtsEngine(tts: tts);
    final events = <TtsEvent>[];
    engine.events.listen(events.add);
    await engine.speak(_chunk(0, '一句。'));
    await engine.dispose();
    tts.onComplete!();
    tts.onError!('late');
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
  });

  test('cancel handler 注册且不派发事件', () async {
    final tts = FakeFlutterTts();
    final engine = SystemTtsEngine(tts: tts);
    final events = <TtsEvent>[];
    engine.events.listen(events.add);
    expect(tts.onCancel, isNotNull);
    tts.onCancel!();
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    await engine.dispose();
  });

  test('错误消息非字符串也可读（US-12）', () async {
    final tts = FakeFlutterTts();
    final engine = SystemTtsEngine(tts: tts);
    final events = <TtsEvent>[];
    engine.events.listen(events.add);
    tts.onError!(42);
    await Future<void>.delayed(Duration.zero);
    expect((events.single as TtsFailed).message, '42');
    await engine.dispose();
  });
}
