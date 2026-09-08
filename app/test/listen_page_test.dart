import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/engines/paged_web_view.dart';
import 'package:reader_app/engines/tts_engine.dart';
import 'package:reader_app/pages/listen_page.dart';
import 'package:reader_app/services/library_backend.dart';
import 'package:reader_app/services/tts_backend.dart';
import 'package:reader_app/widgets/listen_control_bar.dart';
import 'package:reader_app/widgets/listen_follow_highlight.dart';
import 'package:reader_app/widgets/listen_settings_sheet.dart';
import 'package:reader_app/widgets/selection_toolbar.dart';

import 'fake_tts_backend.dart';
import 'fake_tts_engine.dart';

Future<FakeTtsEngine> _pump(
  WidgetTester tester, {
  required FakeListenBackend backend,
  required FakeTtsBackend ttsBackend,
  String href = 'chapter_0001.xhtml',
  double progression = 0.0,
}) async {
  final engine = FakeTtsEngine();
  // 经 Navigator push 进入，便于 US-15 验证"返回后重开"。
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ListenPage(
                  bookId: 'b1',
                  bookTitle: '测试书',
                  href: href,
                  progression: progression,
                  backend: backend,
                  ttsBackend: ttsBackend,
                  ttsEngine: engine,
                ),
              ),
            ),
            child: const Text('open-listen'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open-listen'));
  await tester.pumpAndSettle();
  return engine;
}

SentenceChunk _chunkAt(FakeTtsBackend b, String href, int i) =>
    b.chunksFor(href)[i];

void main() {
  test('US-19 buildPagedWebViewSettings 禁用 WebView 原生选择菜单（可覆盖）', () {
    expect(buildPagedWebViewSettings().disableContextMenu, isTrue);
    expect(
      buildPagedWebViewSettings(disableContextMenu: false).disableContextMenu,
      isFalse,
    );
  });

  testWidgets('US-2 从当前阅读位置起播且进入不写盘', (tester) async {
    final backend = FakeListenBackend(
      progress: const ProgressData(
        href: 'chapter_0001.xhtml',
        progression: 0.4,
      ),
    );
    final ttsBackend = FakeTtsBackend();
    final engine = await _pump(
      tester,
      backend: backend,
      ttsBackend: ttsBackend,
      progression: 0.4,
    );

    // prog1 = 1/3 ≈ 0.333 <= 0.4 < 0.667 → 第 2 句（索引 1）
    expect(engine.spokenIndexes.first, 1);
    expect(ttsBackend.indexAtLocators.single.progression, 0.4);
    expect(backend.saved, isEmpty, reason: '进入听书不得写盘（听读同位置）');
  });

  testWidgets('US-3 控制条含线框 09 控件，定时/音色禁用', (tester) async {
    final engine = await _pump(
      tester,
      backend: FakeListenBackend(),
      ttsBackend: FakeTtsBackend(),
    );
    engine.calls.clear();

    expect(find.byType(ListenControlBar), findsOneWidget);
    expect(find.text('第一章'), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('1.0x'), findsOneWidget);
    expect(find.byTooltip('听书设置'), findsOneWidget);

    final buttons =
        tester.widgetList<OutlinedButton>(find.byType(OutlinedButton)).toList();
    expect(buttons.length, 2, reason: '定时/音色两个占位按钮');
    expect(buttons.every((b) => b.onPressed == null), isTrue);
    expect(find.byType(ReaderSelectionToolbar), findsNothing);
  });

  testWidgets('US-10 暂停/播放/停止调用引擎并切图标', (tester) async {
    final engine = await _pump(
      tester,
      backend: FakeListenBackend(),
      ttsBackend: FakeTtsBackend(),
    );
    engine.calls.clear();

    await tester.tap(find.byTooltip('暂停'));
    await tester.pump();
    expect(engine.calls, contains('pause'));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    await tester.tap(find.byTooltip('播放'));
    await tester.pump();
    expect(engine.calls, contains('resume'));
    expect(find.byIcon(Icons.pause), findsOneWidget);

    await tester.tap(find.byTooltip('停止'));
    await tester.pump();
    expect(engine.calls, contains('stop'));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('US-11 语速调节触发 configure + 文本更新 + 持久化', (tester) async {
    final ttsBackend = FakeTtsBackend();
    final engine = await _pump(
      tester,
      backend: FakeListenBackend(),
      ttsBackend: ttsBackend,
    );

    await tester.tap(find.byTooltip('听书设置'));
    await tester.pumpAndSettle();
    expect(find.byType(ListenSettingsSheet), findsOneWidget);

    final slider = find.descendant(
      of: find.byType(ListenSettingsSheet),
      matching: find.byType(Slider),
    );
    await tester.drag(slider, const Offset(220, 0));
    await tester.pumpAndSettle();

    final speed = engine.lastSpeed!;
    expect(speed, greaterThan(1.0));
    expect(speed, inInclusiveRange(0.5, 3.0));
    expect(ttsBackend.savedSettings, isNotEmpty);
    expect(ttsBackend.savedSettings.last.speed, speed);
    expect(find.text('${speed.toStringAsFixed(1)}x'), findsWidgets);
  });

  testWidgets('US-13 设置面板：系统音色可选，P2 控件禁用灰置', (tester) async {
    final ttsBackend = FakeTtsBackend();
    await _pump(
      tester,
      backend: FakeListenBackend(),
      ttsBackend: ttsBackend,
    );

    await tester.tap(find.byTooltip('听书设置'));
    await tester.pumpAndSettle();

    expect(find.text('系统男声'), findsOneWidget);
    expect(find.text('系统女声'), findsOneWidget);
    expect(find.text('需网络（P2）'), findsOneWidget);
    expect(find.text('下载 52MB（P2）'), findsOneWidget);
    expect(find.text('声音克隆 · 评估中'), findsOneWidget);
    expect(find.textContaining('离线音色不联网'), findsOneWidget);

    final ai = tester.widget<RadioListTile<String>>(
      find.widgetWithText(RadioListTile<String>, 'AI 音色 · 在线'),
    );
    expect(ai.enabled, isFalse);
    final piper = tester.widget<RadioListTile<String>>(
      find.widgetWithText(RadioListTile<String>, '本地神经音色 Piper'),
    );
    expect(piper.enabled, isFalse);
    final timer = tester.widget<RadioListTile<String>>(
      find.widgetWithText(RadioListTile<String>, '15 分钟'),
    );
    expect(timer.enabled, isFalse);
    final bg = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, '后台播放'),
    );
    expect(bg.onChanged, isNull);

    // 系统女声可选
    await tester.tap(find.text('系统女声'));
    await tester.pumpAndSettle();
    expect(ttsBackend.savedSettings.last.voiceId, 'system_female');
  });

  testWidgets('US-14 句完成写 saveProgress（300ms 防抖）', (tester) async {
    final backend = FakeListenBackend();
    final ttsBackend = FakeTtsBackend();
    final engine = await _pump(
      tester,
      backend: backend,
      ttsBackend: ttsBackend,
    );

    engine.emitDone(0);
    await tester.pump(const Duration(milliseconds: 350));
    expect(backend.saved, isNotEmpty);
    expect(backend.saved.last.href, 'chapter_0001.xhtml');
    expect(
      (backend.saved.last.progression -
              _chunkAt(ttsBackend, 'chapter_0001.xhtml', 0).locator.progression)
          .abs(),
      lessThan(1e-6),
    );

    engine.emitDone(1);
    await tester.pump(const Duration(milliseconds: 350));
    expect(backend.saved.length, 2);
    expect(
      (backend.saved.last.progression -
              _chunkAt(ttsBackend, 'chapter_0001.xhtml', 1).locator.progression)
          .abs(),
      lessThan(1e-6),
    );
  });

  testWidgets('US-15 退出强刷进度，重开位置一致', (tester) async {
    final backend = FakeListenBackend();
    final ttsBackend = FakeTtsBackend();
    final engine = await _pump(
      tester,
      backend: backend,
      ttsBackend: ttsBackend,
    );

    engine.emitDone(0);
    await tester.pump(const Duration(milliseconds: 1));
    engine.emitDone(1);
    await tester.pump(const Duration(milliseconds: 1));

    // 防抖窗口内退出 → 强制刷一次
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(backend.saved, isNotEmpty);
    final savedProgression = backend.saved.last.progression;

    // 重开（阅读页会 loadProgress 并传入该 progression）
    final engine2 = await _pump(
      tester,
      backend: backend,
      ttsBackend: ttsBackend,
      progression: savedProgression,
    );
    expect(engine2.spokenIndexes.first, 1);
  });

  testWidgets('US-16 拖动进度条松手 → speak 句 j + saveProgress', (tester) async {
    final backend = FakeListenBackend();
    final ttsBackend = FakeTtsBackend();
    final engine = await _pump(
      tester,
      backend: backend,
      ttsBackend: ttsBackend,
    );
    engine.spokenIndexes.clear();

    final slider = find.descendant(
      of: find.byType(ListenControlBar),
      matching: find.byType(Slider),
    );
    final rect = tester.getRect(slider);
    await tester.tapAt(Offset(rect.left + rect.width * 0.5, rect.center.dy));
    await tester.pumpAndSettle();

    expect(engine.spokenIndexes.last, 1); // round(0.5*2)=1
    expect(backend.saved.last.href, 'chapter_0001.xhtml');
    expect(
      (backend.saved.last.progression -
              _chunkAt(ttsBackend, 'chapter_0001.xhtml', 1).locator.progression)
          .abs(),
      lessThan(1e-6),
    );
  });

  testWidgets('US-17 跟读高亮子串 == 当前句，推进切换', (tester) async {
    final engine = await _pump(
      tester,
      backend: FakeListenBackend(),
      ttsBackend: FakeTtsBackend(),
    );

    var w = tester.widget<ListenFollowHighlight>(
      find.byType(ListenFollowHighlight),
    );
    expect(w.text.substring(w.highlightStart, w.highlightEnd), '第一句。');

    engine.emitDone(0);
    await tester.pump(const Duration(milliseconds: 1));
    w = tester.widget<ListenFollowHighlight>(
      find.byType(ListenFollowHighlight),
    );
    expect(w.text.substring(w.highlightStart, w.highlightEnd), '第二句。');

    // 清掉 300ms 防抖定时器
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('US-18 章末连播：开 → 下一章句 0', (tester) async {
    final backend = FakeListenBackend();
    final ttsBackend = FakeTtsBackend();
    final engine = await _pump(
      tester,
      backend: backend,
      ttsBackend: ttsBackend,
    );

    engine.emitDone(2); // 本章最后一句
    await tester.pumpAndSettle();

    expect(engine.spokenTexts.last, '第四章句一。');
    expect(backend.saved.last.href, 'chapter_0002.xhtml');
    expect(backend.saved.last.progression, 0.0);
    expect(find.text('第二章'), findsOneWidget);
  });

  testWidgets('US-18 章末连播：关 → 不加载下一章、Stopped', (tester) async {
    final ttsBackend = FakeTtsBackend(
      settings: const ListenSettingsData(
        voiceId: 'system_male',
        speed: 1.0,
        autoNext: false,
      ),
    );
    final engine = await _pump(
      tester,
      backend: FakeListenBackend(),
      ttsBackend: ttsBackend,
    );
    final before = engine.spokenTexts.length;

    engine.emitDone(2);
    await tester.pumpAndSettle();

    expect(engine.spokenTexts.length, before, reason: '关闭连播不得加载下一章');
    expect(find.text('第一章'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget); // Stopped
  });

  testWidgets('US-12 TtsFailed → 可读提示含 语音/安装', (tester) async {
    final engine = await _pump(
      tester,
      backend: FakeListenBackend(),
      ttsBackend: FakeTtsBackend(),
    );

    engine.emitFailed('engine missing');
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.textContaining('语音'), findsOneWidget);
    expect(find.textContaining('安装'), findsOneWidget);
  });
}
