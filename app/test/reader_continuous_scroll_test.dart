import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/pages/continuous_scroll_policy.dart';
import 'package:reader_app/pages/reader_page.dart';
import 'package:reader_app/services/library_backend.dart';
import 'package:reader_app/services/notes_backend.dart';
import 'package:reader_app/widgets/reader_chrome.dart';

import 'fake_backend.dart';
import 'fake_notes_backend.dart';

/// REQ-008 T-006 [widget 测试]：连续滚动矩阵 US-5/6/7/9/10/11。
///
/// 全程真实 `ReaderPage`（滚动模式）+ fake backend；分页模式注入 fake 构建器。

String _title(int i) => '第${i + 1}章';

String _text(int i) => List<String>.generate(
      30,
      (j) =>
          '第${i + 1}章第${j + 1}段，这是一段用于连续滚动阅读测试的正文，'
          '需要足够长以产生滚动并跨越视口，从而验证可见章判定与章内进度。',
    ).join();

class _MultiChapterBackend extends FakeBackend {
  _MultiChapterBackend(this.count);

  final int count;

  @override
  Future<BookViewData> openBook(String id) async => BookViewData(
        id: 'b1',
        title: '测试书',
        chapters: List<ChapterData>.generate(
          count,
          (i) => ChapterData(title: _title(i), text: _text(i)),
        ),
      );
}

const String _pagedMarker = '分页模式（fake WebView）';

Widget _fakePagedBuilder(
  BuildContext context, {
  required String bookId,
  required String href,
  required String html,
  required dynamic backend,
  required int fontSize,
  required ValueChanged<double> onProgress,
  ValueChanged<String>? onSelectedText,
}) =>
    const Center(child: Text(_pagedMarker));

Widget _app(
  LibraryBackend backend, {
  ChapterContentProvider? provider,
  NotesBackend? notesBackend,
}) =>
    MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: backend,
        pagedViewBuilder: _fakePagedBuilder,
        chapterProvider: provider,
        notesBackend: notesBackend,
      ),
    );

/// 呼出 Chrome（点击屏幕中部 1/3）。
Future<void> _showChrome(WidgetTester tester) async {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  await tester.tapAt(Offset(size.width / 2, size.height / 2));
  await tester.pumpAndSettle();
}

/// 章节正文 item 内的标题（避免与顶栏同名章节名混淆）。
Finder _sectionTitle(int i) => find.descendant(
      of: find.byType(ChapterSection),
      matching: find.text(_title(i)),
    );

bool _topBarShows(WidgetTester tester, String title) {
  final topBar = find.byType(ReaderTopBar);
  if (topBar.evaluate().isEmpty) return false;
  return find
      .descendant(of: topBar, matching: find.text(title))
      .evaluate()
      .isNotEmpty;
}

/// 反复向上 drag 直到顶栏显示目标章（真实滚动，非程序化跳章）。
Future<void> _scrollUntilChapter(WidgetTester tester, int index) async {
  // 顶栏只在 Chrome 呼出时渲染；先确保可见以读取"可见章"信号。
  if (find.byType(ReaderTopBar).evaluate().isEmpty) {
    await _showChrome(tester);
  }
  final title = _title(index);
  for (var i = 0; i < 120; i++) {
    if (_topBarShows(tester, title)) return;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pump();
  }
  fail('未能通过滚动到达 $title');
}

void main() {
  testWidgets('US-6 滚到章末自动接续下一章：标题/正文各 1，无重复 Key 异常',
      (tester) async {
    final backend = _MultiChapterBackend(3);
    await tester.pumpWidget(_app(backend));
    await tester.pumpAndSettle();

    expect(find.text(_title(0)), findsOneWidget);
    expect(find.text(_title(1)), findsNothing, reason: '第二章初始未构建（懒构建）');

    await _scrollUntilChapter(tester, 1);

    expect(_sectionTitle(1), findsOneWidget, reason: '自动接续且不重复');
    expect(find.text(_text(1)), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.byType(ChapterSection).evaluate().length,
        lessThanOrEqualTo(3), reason: '已构建章数有界（视口 + cacheExtent）');
  });

  testWidgets('US-6 章末小幅抖动不重复加载/不抛异常', (tester) async {
    final backend = _MultiChapterBackend(3);
    await tester.pumpWidget(_app(backend));
    await tester.pumpAndSettle();
    await _scrollUntilChapter(tester, 1);

    for (var i = 0; i < 6; i++) {
      await tester.drag(
        find.byType(CustomScrollView),
        Offset(0, i.isEven ? 40 : -40),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(_sectionTitle(1), findsOneWidget);
    expect(find.text(_text(1)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('US-5 顶栏章节名/底栏进度随可见章切换', (tester) async {
    final backend = _MultiChapterBackend(3);
    await tester.pumpWidget(_app(backend));
    await tester.pumpAndSettle();
    await _showChrome(tester);

    expect(_topBarShows(tester, _title(0)), isTrue);

    // 先在第一章内滚动一小段 → 进度 > 0
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
    await tester.pump();
    var slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, greaterThan(0.0));
    expect(slider.value, lessThanOrEqualTo(1.0));

    await _scrollUntilChapter(tester, 1);

    expect(_topBarShows(tester, _title(1)), isTrue, reason: '顶栏章节名随可见章更新');
    slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, lessThan(0.5), reason: '跨章后进度回到新章起点附近');
    expect(slider.value, greaterThanOrEqualTo(0.0));
  });

  testWidgets('US-7 上一章 / 目录跳转在连续流中正确', (tester) async {
    final backend = _MultiChapterBackend(4);
    await tester.pumpWidget(_app(backend));
    await tester.pumpAndSettle();
    await _showChrome(tester);
    await _scrollUntilChapter(tester, 1);

    // 上一章 → 第一章 + 立即落盘
    await tester.tap(find.text('上一章'));
    await tester.pumpAndSettle();
    expect(_topBarShows(tester, _title(0)), isTrue);
    expect(backend.saved?.href, 'chapter_0001.xhtml');

    // 目录 → 第三章
    await tester.tap(find.byTooltip('目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3. ${_title(2)}'));
    await tester.pumpAndSettle();
    expect(_topBarShows(tester, _title(2)), isTrue);
    expect(backend.saved?.href, 'chapter_0003.xhtml');
  });

  testWidgets('US-9 Aa 改主题后仍锚定「当前可见章 + 章内比例」', (tester) async {
    // 放大测试窗口，使 Aa 弹层完整可见（默认 800x600 会令"主题"行落到屏外）。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final backend = _MultiChapterBackend(3);
    await tester.pumpWidget(_app(backend));
    await tester.pumpAndSettle();
    await _showChrome(tester);
    await _scrollUntilChapter(tester, 1);
    expect(_topBarShows(tester, _title(1)), isTrue);

    // 改主题 → post-frame 以"章序号 + 章内比例"重新锚定（不跳变）。
    await tester.tap(find.text('Aa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    expect(_topBarShows(tester, _title(1)), isTrue, reason: '重排后仍锚定第二章');
    expect(find.text(_text(1)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('US-9 书签切换 + 分页↔滚动互切后连续滚动仍工作', (tester) async {
    // 放大测试窗口，使 Aa 弹层完整可见（默认 800x600 会令"翻页"行落到屏外）。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final backend = _MultiChapterBackend(3);
    final notes = FakeNotesBackend(
      chapterTexts: {
        for (var i = 0; i < 3; i++) 'chapter_${(i + 1).toString().padLeft(4, '0')}.xhtml': _text(i),
      },
      chapterTitles: {
        for (var i = 0; i < 3; i++) 'chapter_${(i + 1).toString().padLeft(4, '0')}.xhtml': _title(i),
      },
    );
    await tester.pumpWidget(_app(backend, notesBackend: notes));
    await tester.pumpAndSettle();
    await _showChrome(tester);

    // 书签幂等切换
    expect(find.byTooltip('加书签'), findsOneWidget);
    await tester.tap(find.byTooltip('加书签'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('取消书签'), findsOneWidget);

    // 切分页模式
    await tester.tap(find.text('Aa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分页模式'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text(_pagedMarker), findsOneWidget);

    // 切回滚动模式（Chrome 仍可见，无需重新呼出）
    await tester.tap(find.text('Aa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('滚动模式'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomScrollView), findsOneWidget);

    // 连续滚动仍工作
    await _scrollUntilChapter(tester, 1);
    expect(find.text(_text(1)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('US-10 下一章不可用：保留当前章 + 非阻断提示 + provider 调用有界',
      (tester) async {
    final backend = _MultiChapterBackend(2);
    var providerCalls = 0;
    ChapterData provider(int i) {
      if (i == 1) {
        providerCalls++;
        throw StateError('下一章不可用');
      }
      return ChapterData(title: _title(0), text: _text(0));
    }

    await tester.pumpWidget(_app(backend, provider: provider));
    await tester.pumpAndSettle();

    // 滚到章末触发第二章构建（失败）
    for (var i = 0; i < 20; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pump();
      if (find.textContaining('加载失败').evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();

    expect(find.text(_text(0)), findsOneWidget, reason: '当前章内容必须保留');
    expect(find.textContaining('加载失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(providerCalls, 1, reason: '失败记忆化，不自动重试');

    // 重复 pump 不再调用 provider
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(providerCalls, 1);

    // 显式重试 → 有界地再调用一次
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(providerCalls, 2, reason: '显式 retry 才允许再次调用');
    expect(tester.takeException(), isNull);
  });

  testWidgets('US-11 50 章仅滚到第二章：已构建章数有界（≤3 且 ≠50）',
      (tester) async {
    final backend = _MultiChapterBackend(50);
    await tester.pumpWidget(_app(backend));
    await tester.pumpAndSettle();
    await _showChrome(tester);
    await _scrollUntilChapter(tester, 1);

    final built = find.byType(ChapterSection).evaluate().length;
    expect(built, lessThanOrEqualTo(3), reason: '不一次性构建全书');
    expect(built, isNot(50));
    expect(tester.takeException(), isNull);
  });
}
