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
  bool settle = true,
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
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // 错误态会持续显示进度圈（无限动画），不能 pumpAndSettle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
  return engine;
}

SentenceChunk _chunkAt(FakeTtsBackend b, String href, int i) =>
    b.chunksFor(href)[i];

/// 长句表（每句约 5 行）→ `maxScrollExtent > 0`，用于滚动同步断言（US-7/8/9）。
Map<String, List<String>> _longSentences() => {
      'chapter_0001.xhtml': List<String>.generate(
        8,
        (i) => '第$i句。${'这是一段足够长的正文内容用来换行滚动。' * 8}',
      ),
      'chapter_0002.xhtml': ['下一章句一。'],
    };

/// 取跟读组件内部 ScrollController 的当前偏移。
double _scrollOffset(WidgetTester tester) {
  final scrollable = find.descendant(
    of: find.byType(ListenFollowHighlight),
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(scrollable).position.pixels;
}

/// 下一章 segment 抛错，用于覆盖 _loadNextChapter 的 catch 分支。
class _ThrowingTtsBackend extends FakeTtsBackend {
  @override
  Future<List<SentenceChunk>> segment(String bookId, String href) async {
    if (href == 'chapter_0002.xhtml') throw StateError('boom');
    return super.segment(bookId, href);
  }
}

void main() {
  test('US-19 buildPagedWebViewSettings 禁用 WebView 原生选择菜单（可覆盖）', () {
    final s = buildPagedWebViewSettings();
    expect(s.disableContextMenu, isTrue);
    expect(s.useShouldInterceptRequest, isTrue);
    expect(s.transparentBackground, isFalse);
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

  // ---------- REQ-005-fixes 阶段4：防抖/退出/拖动 clamp/连播/异常 ----------

  test('ListenSettingsData.copyWith 仅更新指定字段', () {
    const s = ListenSettingsData(
      voiceId: 'system_male',
      speed: 1.0,
      autoNext: true,
    );
    final s2 = s.copyWith(speed: 2.0);
    expect(s2.voiceId, 'system_male');
    expect(s2.speed, 2.0);
    expect(s2.autoNext, isTrue);
    final s3 = s.copyWith(voiceId: 'system_female', autoNext: false);
    expect(s3.voiceId, 'system_female');
    expect(s3.autoNext, isFalse);
    expect(s3.speed, 1.0);
  });

  testWidgets('US-14 防抖：300ms 内连续完成只落盘最后一次', (tester) async {
    final backend = FakeListenBackend();
    final ttsBackend = FakeTtsBackend();
    final engine = await _pump(
      tester,
      backend: backend,
      ttsBackend: ttsBackend,
    );

    engine.emitDone(0);
    await tester.pump(const Duration(milliseconds: 100));
    engine.emitDone(1);
    await tester.pump(const Duration(milliseconds: 350));

    expect(backend.saved.length, 1, reason: '防抖窗口内多次完成应合并为一次落盘');
    expect(
      (backend.saved.last.progression -
              _chunkAt(ttsBackend, 'chapter_0001.xhtml', 1).locator.progression)
          .abs(),
      lessThan(1e-6),
    );
  });

  testWidgets('US-16 拖动到两端 clamp 到首句/末句', (tester) async {
    final backend = FakeListenBackend();
    final ttsBackend = FakeTtsBackend();
    final engine = await _pump(
      tester,
      backend: backend,
      ttsBackend: ttsBackend,
    );

    final slider = find.descendant(
      of: find.byType(ListenControlBar),
      matching: find.byType(Slider),
    );
    final rect = tester.getRect(slider);

    engine.spokenIndexes.clear();
    await tester.tapAt(Offset(rect.left + rect.width * 0.02, rect.center.dy));
    await tester.pumpAndSettle();
    expect(engine.spokenIndexes.last, 0, reason: '最左 → 第 0 句');

    await tester.tapAt(Offset(rect.left + rect.width * 0.98, rect.center.dy));
    await tester.pumpAndSettle();
    expect(engine.spokenIndexes.last, 2, reason: '最右 → 末句');
  });

  testWidgets('US-18 末章末句 autoNext 开 → Stopped 不再加载', (tester) async {
    final backend = FakeListenBackend();
    final ttsBackend = FakeTtsBackend();
    final engine = await _pump(
      tester,
      backend: backend,
      ttsBackend: ttsBackend,
      href: 'chapter_0002.xhtml',
    );
    final before = engine.spokenTexts.length;

    engine.emitDone(1); // chapter_0002 末句
    await tester.pumpAndSettle();

    expect(engine.spokenTexts.length, before, reason: '末章不得再加载');
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('空章节 → Stopped + 占位文案，不朗读', (tester) async {
    const sentences = {
      'chapter_0001.xhtml': <String>[],
      'chapter_0002.xhtml': ['下一章。'],
    };
    final ttsBackend = FakeTtsBackend(sentences: sentences);
    final engine = await _pump(
      tester,
      backend: FakeListenBackend(sentences: sentences),
      ttsBackend: ttsBackend,
    );

    expect(engine.spokenTexts, isEmpty);
    expect(find.text('本章暂无可朗读内容'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('章节不存在 → 显示打开失败且不朗读', (tester) async {
    final engine = await _pump(
      tester,
      backend: FakeListenBackend(),
      ttsBackend: FakeTtsBackend(),
      href: 'chapter_9999.xhtml',
      settle: false,
    );

    expect(engine.spokenTexts, isEmpty);
    expect(find.textContaining('打开听书失败'), findsOneWidget);
  });

  testWidgets('US-12 连续失败 >5 次 → 停止播放', (tester) async {
    final sentences = {
      'chapter_0001.xhtml': List<String>.generate(9, (i) => '第 $i 句。'),
      'chapter_0002.xhtml': ['下一章。'],
    };
    final engine = await _pump(
      tester,
      backend: FakeListenBackend(sentences: sentences),
      ttsBackend: FakeTtsBackend(sentences: sentences),
    );
    engine.calls.clear();

    for (var i = 0; i < 6; i++) {
      engine.emitFailed('fail $i');
      await tester.pump(const Duration(milliseconds: 1));
    }

    expect(engine.calls, contains('stop'), reason: '超过阈值应停止');
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('上一句/下一句按钮切句并 clamp', (tester) async {
    final engine = await _pump(
      tester,
      backend: FakeListenBackend(),
      ttsBackend: FakeTtsBackend(),
    );
    engine.spokenIndexes.clear();

    await tester.tap(find.byTooltip('下一句'));
    await tester.pumpAndSettle();
    expect(engine.spokenIndexes.last, 1);

    await tester.tap(find.byTooltip('下一句'));
    await tester.pumpAndSettle();
    expect(engine.spokenIndexes.last, 2);

    await tester.tap(find.byTooltip('上一句'));
    await tester.pumpAndSettle();
    expect(engine.spokenIndexes.last, 1);

    await tester.tap(find.byTooltip('上一句'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上一句'));
    await tester.pumpAndSettle();
    expect(engine.spokenIndexes.last, 0, reason: '首句再上一句应 clamp 到 0');
  });

  testWidgets('设置面板关闭按钮 → 面板消失', (tester) async {
    await _pump(
      tester,
      backend: FakeListenBackend(),
      ttsBackend: FakeTtsBackend(),
    );
    await tester.tap(find.byTooltip('听书设置'));
    await tester.pumpAndSettle();
    expect(find.byType(ListenSettingsSheet), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(ListenSettingsSheet), findsNothing);
  });

  testWidgets('跟读高亮越界区间被 clamp，不抛异常', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ListenFollowHighlight(
          text: 'abc',
          highlightStart: -5,
          highlightEnd: 99,
        ),
      ),
    ));
    expect(find.byKey(const Key('listen-follow-text')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('控制条拖动中仅本地预览，松手才回调 onSeek', (tester) async {
    final seeks = <double>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenControlBar(
          chapterTitle: '第一章',
          playing: false,
          speedText: '1.0x',
          progress: 0.0,
          onPrevSentence: () {},
          onTogglePlay: () {},
          onNextSentence: () {},
          onSeek: seeks.add,
        ),
      ),
    ));
    final rect = tester.getRect(find.byType(Slider));
    final gesture =
        await tester.startGesture(Offset(rect.left + 10, rect.center.dy));
    await gesture.moveTo(Offset(rect.left + rect.width * 0.5, rect.center.dy));
    await tester.pump();
    expect(seeks, isEmpty, reason: '拖动中不得回调 onSeek');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(seeks, isNotEmpty);
  });

  testWidgets('US-12 末句失败 → 停止播放', (tester) async {
    final engine = await _pump(
      tester,
      backend: FakeListenBackend(),
      ttsBackend: FakeTtsBackend(),
      href: 'chapter_0002.xhtml',
    );
    engine.calls.clear();

    engine.emitFailed('first'); // 第 0 句失败 → 前进到第 1 句
    await tester.pump(const Duration(milliseconds: 1));
    engine.emitFailed('last'); // 末句失败 → 停止
    await tester.pump(const Duration(milliseconds: 1));

    expect(engine.calls, contains('stop'));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('US-18 下一章加载失败 → 可读错误且停止', (tester) async {
    final engine = await _pump(
      tester,
      backend: FakeListenBackend(),
      ttsBackend: _ThrowingTtsBackend(),
    );
    engine.spokenTexts.clear();

    engine.emitDone(2); // 本章末句 → 触发下一章加载（抛错）
    await tester.pumpAndSettle();

    expect(find.textContaining('加载下一章失败'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('US-10 Stopped 态点播放 → 从当前句重读', (tester) async {
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

    engine.emitDone(0);
    await tester.pump(const Duration(milliseconds: 1));
    engine.emitDone(1);
    await tester.pump(const Duration(milliseconds: 1));
    engine.emitDone(2); // 关闭连播 → Stopped，_index 停在 2
    await tester.pumpAndSettle();
    engine.spokenIndexes.clear();

    await tester.tap(find.byTooltip('播放'));
    await tester.pumpAndSettle();
    expect(engine.spokenIndexes.last, 2, reason: 'Stopped 态应从当前句重读');
  });

  testWidgets('href 不含 chapter_N 模式 → 打开失败（-1 分支）', (tester) async {
    final engine = await _pump(
      tester,
      backend: FakeListenBackend(),
      ttsBackend: FakeTtsBackend(),
      href: 'foo.xhtml',
      settle: false,
    );

    expect(engine.spokenTexts, isEmpty);
    expect(find.textContaining('打开听书失败'), findsOneWidget);
  });

  // ---------- REQ-006：onStart / 自动滚动 / seek 同步 / 音色提示 ----------

  testWidgets('US-5 emitStarted 切换高亮锚点且不写盘', (tester) async {
    final backend = FakeListenBackend();
    final ttsBackend = FakeTtsBackend();
    final engine = await _pump(
      tester,
      backend: backend,
      ttsBackend: ttsBackend,
    );
    expect(backend.saved, isEmpty, reason: '进入听书不写盘');

    engine.emitStarted(2);
    await tester.pump(const Duration(milliseconds: 1));

    final w = tester.widget<ListenFollowHighlight>(
      find.byType(ListenFollowHighlight),
    );
    expect(w.text.substring(w.highlightStart, w.highlightEnd), '第三句。');
    await tester.pump(const Duration(milliseconds: 350));
    expect(backend.saved, isEmpty, reason: 'TtsSentenceStarted 只确认高亮，不写盘');
  });

  testWidgets('US-8 句推进 → 高亮切句且滚动偏移前移（旧句不再高亮）', (tester) async {
    final sentences = _longSentences();
    final backend = FakeListenBackend(sentences: sentences);
    final ttsBackend = FakeTtsBackend(sentences: sentences);
    final engine = await _pump(
      tester,
      backend: backend,
      ttsBackend: ttsBackend,
    );
    await tester.pumpAndSettle();
    final before = _scrollOffset(tester);

    engine.emitDone(0);
    await tester.pumpAndSettle();

    final w = tester.widget<ListenFollowHighlight>(
      find.byType(ListenFollowHighlight),
    );
    final second = sentences['chapter_0001.xhtml']![1];
    expect(w.text.substring(w.highlightStart, w.highlightEnd), second);
    expect(_scrollOffset(tester), greaterThan(before), reason: '应自动滚动到句 1');
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('US-9 拖动进度条到末句 → 高亮/滚动锚点同步且不越界', (tester) async {
    final sentences = _longSentences();
    final backend = FakeListenBackend(sentences: sentences);
    final ttsBackend = FakeTtsBackend(sentences: sentences);
    final engine = await _pump(
      tester,
      backend: backend,
      ttsBackend: ttsBackend,
    );
    final chunks = ttsBackend.chunksFor('chapter_0001.xhtml');

    final slider = find.descendant(
      of: find.byType(ListenControlBar),
      matching: find.byType(Slider),
    );
    final rect = tester.getRect(slider);
    await tester.tapAt(Offset(rect.left + rect.width * 0.98, rect.center.dy));
    await tester.pumpAndSettle();

    expect(engine.spokenIndexes.last, chunks.length - 1, reason: '不越界');
    final w = tester.widget<ListenFollowHighlight>(
      find.byType(ListenFollowHighlight),
    );
    expect(w.highlightStart, chunks.last.charStart);
    expect(w.highlightEnd, chunks.last.charEnd);
    expect(_scrollOffset(tester), greaterThan(0));
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('US-21 emitVoiceFallback → 控制条/设置面板显示"系统默认音色"', (tester) async {
    final engine = await _pump(
      tester,
      backend: FakeListenBackend(),
      ttsBackend: FakeTtsBackend(),
    );
    expect(find.text('🎙 系统男声'), findsOneWidget);

    engine.emitVoiceFallback('system_male');
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('🎙 系统默认音色'), findsOneWidget);

    await tester.tap(find.byTooltip('听书设置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('系统默认音色'), findsWidgets);
    expect(find.text('系统男声'), findsOneWidget, reason: 'P0 音色选项仍在');
  });
}
