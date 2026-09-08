import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:reader_app/engines/system_tts_engine.dart';
import 'package:reader_app/engines/tts_engine.dart';

/// 平台通道 mock：子类化 FlutterTts，记录调用并可控触发完成/错误回调。
class FakeFlutterTts extends FlutterTts {
  final List<String> calls = [];
  final List<Object?> args = [];
  VoidCallback? onComplete;
  VoidCallback? onCancel;
  ErrorHandler? onError;

  /// 可控异常：模拟平台不支持枚举音色 / setVoice 失败。
  bool throwGetVoices = false;
  bool throwSetVoice = false;

  /// 覆盖 getVoices 返回值（可为非 List 以覆盖类型分支）。
  dynamic voicesOverride;

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

  test('枚举音色失败 → 回退默认音色不阻断（US-12）', () async {
    final tts = FakeFlutterTts()..throwGetVoices = true;
    final engine = SystemTtsEngine(tts: tts);
    await engine.configure(voiceId: 'system_female', speed: 1.0);
    final voice = tts.args[tts.calls.indexOf('setVoice')] as Map;
    expect(voice['name'], 'system_female');
    expect(voice['locale'], 'zh-CN');
    await engine.dispose();
  });

  test('getVoices 返回非 List → 回退默认音色', () async {
    final tts = FakeFlutterTts()..voicesOverride = 'not-a-list';
    final engine = SystemTtsEngine(tts: tts);
    await engine.configure(voiceId: 'system_male', speed: 1.0);
    final voice = tts.args[tts.calls.indexOf('setVoice')] as Map;
    expect(voice['name'], 'system_male');
    await engine.dispose();
  });

  test('setVoice 抛错 → 静默回退不阻断（US-12）', () async {
    final tts = FakeFlutterTts()..throwSetVoice = true;
    final engine = SystemTtsEngine(tts: tts);
    await engine.configure(voiceId: 'system_male', speed: 1.0);
    expect(tts.calls, contains('setVoice'));
    await engine.speak(_chunk(0, '一句。'));
    expect(tts.calls.last, 'speak');
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
