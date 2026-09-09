import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport, RenderBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_app/pages/continuous_scroll_policy.dart';
import 'package:reader_app/pages/listen_page.dart';
import 'package:reader_app/pages/reader_page.dart';
import 'package:reader_app/services/library_backend.dart';
import 'package:reader_app/services/tts_backend.dart';
import 'package:reader_app/engines/tts_engine.dart';
import 'package:reader_app/widgets/reader_chrome.dart';

import '../test/fake_backend.dart';
import '../test/fake_tts_backend.dart';
import '../test/fake_tts_engine.dart';

/// REQ-008 T-007 真实集成测试（US-1/2/3/4/8/12）。
///
/// 全程真实 `ReaderPage`（滚动模式）+ 真实 `drag`/`fling`，**不构造**合成顶/底栏
/// 页面（由 `no_synthetic_chrome_test.dart` 静态守卫）。
/// 分页模式因 `flutter_inappwebview` 无 Linux 实现，由 widget/单测 + 真机清单覆盖。

String _title(int i) => '第${i + 1}章';

const int _paragraphs = 60;

String _longText(int i) => List<String>.generate(
      _paragraphs,
      (j) =>
          '第${i + 1}章第${j + 1}段，这是一段用于真实连续滚动集成测试的正文，'
          '需要足够长以产生真实滚动并跨越视口，验证章末自动衔接下一章。',
    ).join();

const String _shortText = '故事到这里就结束了。';

/// 多章长文本后端：末章可短（US-2 短末章触底锁）。
class _ScrollBackend extends FakeBackend {
  _ScrollBackend(this.count, {this.shortLast = false});

  final int count;
  final bool shortLast;

  @override
  Future<BookViewData> openBook(String id) async => BookViewData(
        id: 'b1',
        title: '测试书',
        chapters: List<ChapterData>.generate(
          count,
          (i) => ChapterData(
            title: _title(i),
            text: (shortLast && i == count - 1) ? _shortText : _longText(i),
          ),
        ),
      );
}

Widget _reader({
  required LibraryBackend backend,
  TtsBackend? ttsBackend,
  TtsEngine? ttsEngine,
}) =>
    MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: backend,
        ttsBackend: ttsBackend,
        ttsEngine: ttsEngine,
      ),
    );

void _setPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle();

double _pixels(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;

double _maxExtent(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .maxScrollExtent;

/// 呼出 Chrome（点击屏幕中部 1/3）。
Future<void> _showChrome(WidgetTester tester) async {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  await tester.tapAt(Offset(size.width / 2, size.height / 2));
  await _settle(tester);
}

bool _topBarShows(WidgetTester tester, String title) {
  final topBar = find.byType(ReaderTopBar);
  if (topBar.evaluate().isEmpty) return false;
  return find
      .descendant(of: topBar, matching: find.text(title))
      .evaluate()
      .isNotEmpty;
}

/// 真实 drag/fling 直到顶栏显示目标章（含迭代上限，防惰性列表死循环）。
Future<void> _scrollUntilChapter(WidgetTester tester, int index) async {
  if (find.byType(ReaderTopBar).evaluate().isEmpty) {
    await _showChrome(tester);
  }
  final title = _title(index);
  for (var i = 0; i < 160; i++) {
    if (_topBarShows(tester, title)) return;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pump();
  }
  fail('真实滚动未能到达 $title');
}

/// 真实 drag 到末尾（惰性列表 `maxScrollExtent` 随构建增长 → 连续两次确认）。
Future<void> _scrollToEnd(WidgetTester tester) async {
  for (var i = 0; i < 200; i++) {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pump();
    if (_pixels(tester) >= _maxExtent(tester) - 1.0) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pump();
      if (_pixels(tester) >= _maxExtent(tester) - 1.0) return;
    }
  }
  fail('真实滚动未能到达末尾');
}

/// 某章起点对应的滚动偏移（`getOffsetToReveal`，与 ensureVisible 同源）。
double _sectionStartOffset(WidgetTester tester, int index) {
  final section = tester
      .widgetList<ChapterSection>(find.byType(ChapterSection))
      .firstWhere((s) => s.index == index);
  final box = tester.renderObject(find.byWidget(section)) as RenderBox;
  return RenderAbstractViewport.of(box).getOffsetToReveal(box, 0.0).offset;
}

/// 真实 drag 直到目标进入视口（不依赖 Chrome，US-1 用）。
Future<void> _scrollUntilTextVisible(WidgetTester tester, Finder finder) async {
  final viewportHeight =
      tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (var i = 0; i < 200; i++) {
    if (finder.evaluate().isNotEmpty) {
      final dy = tester.getTopLeft(finder).dy;
      if (dy >= 0 && dy < viewportHeight) return;
    }
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pump();
  }
  fail('真实滚动未能使目标进入视口');
}

/// 等待尾沿防抖窗口（真实墙钟 ≥ 350ms）后落盘。
Future<void> _waitDebounce(WidgetTester tester) async {
  await Future<void>.delayed(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('US-1 真实滚到章末自动出现下一章正文与标题（未点"下一章"）',
      (tester) async {
    _setPhone(tester);
    final backend = _ScrollBackend(3);
    await tester.pumpWidget(_reader(backend: backend));
    await _settle(tester);

    expect(find.text(_title(1)), findsNothing, reason: '第二章初始未构建');
    expect(find.text('返回书架'), findsNothing, reason: '沉浸态无 Chrome（未点下一章）');

    // 真实 drag 直到第二章正文进入视口（章末自动衔接，无需点击）。
    await _scrollUntilTextVisible(tester, find.text(_longText(1)));
    await _settle(tester);

    expect(find.text(_title(1)), findsOneWidget);
    expect(find.text(_longText(1)), findsOneWidget);
    expect(find.text('返回书架'), findsNothing,
        reason: '期间未点击"下一章"（Chrome 仍隐藏）');

    // 继续真实 fling → 第二章内容继续可滚（offset 增大）。
    final before = _pixels(tester);
    await tester.fling(
        find.byType(CustomScrollView), const Offset(0, -600), 3000);
    await _settle(tester);
    expect(_pixels(tester), greaterThan(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('US-2 最后一章自然停止：不越界、不崩溃、不重复', (tester) async {
    _setPhone(tester);
    final backend = _ScrollBackend(3, shortLast: true);
    await tester.pumpWidget(_reader(backend: backend));
    await _settle(tester);

    await _scrollToEnd(tester);
    final max = _maxExtent(tester);

    // 额外多次 drag/fling：pixels 保持 max，不越界。
    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(_pixels(tester), closeTo(max, 1.0));
    expect(tester.takeException(), isNull);
    expect(find.text(_shortText), findsOneWidget, reason: '末章未重复渲染');
    expect(find.text(_title(3)), findsNothing, reason: '不存在第 4 章');

    // 末章时底栏"下一章"禁用。
    await _showChrome(tester);
    final nextButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '下一章'),
    );
    expect(nextButton.onPressed, isNull);
  });

  testWidgets('US-3 滚动写入"当前可见章" href + 章内 progression', (tester) async {
    _setPhone(tester);
    final backend = _ScrollBackend(2);
    await tester.pumpWidget(_reader(backend: backend));
    await _settle(tester);

    // 第一章内真实滚动 + 防抖窗口。
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pump();
    await _waitDebounce(tester);
    expect(backend.saved?.href, 'chapter_0001.xhtml');
    expect(backend.saved!.progression, inInclusiveRange(0.0, 1.0));

    // 滚入第二章并停下 → href 切换、progression 为章内值。
    await _scrollUntilChapter(tester, 1);
    await _waitDebounce(tester);
    expect(backend.saved?.href, 'chapter_0002.xhtml');
    expect(backend.saved!.progression, inInclusiveRange(0.0, 1.0),
        reason: '不得把全书比例写入 progression');

    // 第二章内再滚动 → href 保持、progression 仍 [0,1]。
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
    await tester.pump();
    await _waitDebounce(tester);
    expect(backend.saved?.href, 'chapter_0002.xhtml');
    expect(backend.saved!.progression, inInclusiveRange(0.0, 1.0));
  });

  testWidgets('US-4 重开恢复到跨章位置（章起点 + 章内比例）', (tester) async {
    _setPhone(tester);
    final backend = _ScrollBackend(3);
    await tester.pumpWidget(_reader(backend: backend));
    await _settle(tester);

    // 滚入第二章并在章内前进一段 → 保存 chapter_0002 + p>0。
    await _scrollUntilChapter(tester, 1);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
    await tester.pump();
    await _waitDebounce(tester);
    expect(backend.saved?.href, 'chapter_0002.xhtml');
    final chapter2Start = _sectionStartOffset(tester, 1);

    // 重建真实 ReaderPage（同一 backend 实例）→ 恢复到第二章。
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_reader(backend: backend));
    await _settle(tester);

    expect(find.text(_longText(1)), findsOneWidget,
        reason: '重开应恢复到第二章（非全书 0% / 第一章）');
    expect(_pixels(tester), greaterThanOrEqualTo(chapter2Start - 1.0));

    // progression==0 的章首进度 → 定位到该章起点。
    // 先卸载当前页（dispose 会强刷最后位置），再注入章首进度，避免被覆盖。
    await tester.pumpWidget(const SizedBox());
    backend.saved = const ProgressData(
      href: 'chapter_0002.xhtml',
      progression: 0.0,
    );
    await tester.pumpWidget(_reader(backend: backend));
    await _settle(tester);
    expect(find.text(_longText(1)), findsOneWidget);
    final restoredStart = _sectionStartOffset(tester, 1);
    expect(_pixels(tester), closeTo(restoredStart, 1.0));
  });

  testWidgets('US-8 听书跨章写入后返回：定位一致 + 连续滚动仍可接续', (tester) async {
    _setPhone(tester);
    final backend = _ScrollBackend(3);
    final engine = FakeTtsEngine();
    addTearDown(engine.dispose);
    await tester.pumpWidget(_reader(
      backend: backend,
      ttsBackend: FakeTtsBackend(),
      ttsEngine: engine,
    ));
    await _settle(tester);

    await _showChrome(tester);
    await tester.tap(find.byTooltip('更多'));
    await _settle(tester);
    await tester.tap(find.text('听书'));
    await _settle(tester);
    expect(find.byType(ListenPage), findsOneWidget);

    // 模拟 ListenPage 章末连播写入第二章进度。
    backend.saved = const ProgressData(
      href: 'chapter_0002.xhtml',
      progression: 0.0,
    );
    await tester.tap(find.byTooltip('返回'));
    await _settle(tester);

    expect(find.text(_longText(1)), findsOneWidget,
        reason: '返回后定位到听书写入的第二章');
    expect(backend.saved?.href, 'chapter_0002.xhtml');

    // 返回后连续滚动仍可自动衔接第三章。
    await _scrollUntilChapter(tester, 2);
    expect(find.text(_longText(2)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
