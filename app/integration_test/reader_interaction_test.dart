import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_app/pages/reader_page.dart';
import 'package:reader_app/pages/settings_page.dart';
import 'package:reader_app/services/library_backend.dart';
import 'package:reader_app/widgets/reader_chrome.dart';
import 'package:reader_app/widgets/selection_toolbar.dart';

import '../test/fake_backend.dart';
import '../test/fake_translate_backend.dart';

/// REQ-007 真实交互集成测试（US-1/2/4/12，D6）。
///
/// 全程真实 `ReaderPage`（滚动模式）+ 真实 `tapAt`/`longPress`/`drag`，
/// **不构造**合成顶/底栏页面（由 no_synthetic_chrome_test 静态守卫）。
/// 分页模式因 `flutter_inappwebview` 无 Linux 实现，由 widget/单测 + 真机清单覆盖。

const String _ch1Text =
    '很久以前，有一座山，山里住着一位老人。'
    '他每天清晨都会沿着溪流散步，看雾气从山谷里升起。'
    '孩子们围坐在他身边，听他讲那些古老的故事。'
    '年复一年，山还是那座山，溪水还是那条溪水，'
    '只是听故事的人换了一批又一批，故事却从未讲完。'
    '老人说，山外的世界很大，但每个人心里都有一座山。'
    '有一天，一个年轻人背起行囊，决定翻过那座山去看一看。'
    '他走了很远很远，直到回望时，故乡已经变成一个小小的点。';

const String _ch2Text = '故事结束了，年轻人终于翻过了那座山。';

/// 两章长文本后端：正文铺满屏幕中部，且下方留有中部空白（便于验证两种落点）。
class _InteractionBackend extends FakeBackend {
  @override
  Future<BookViewData> openBook(String id) async => const BookViewData(
        id: 'b1',
        title: '测试书',
        chapters: [
          ChapterData(title: '第一章', text: _ch1Text),
          ChapterData(title: '第二章', text: _ch2Text),
        ],
      );
}

/// 超长文本后端：确保可滚动（US-2 拖拽不误触 toggle）。
class _VeryLongBackend extends FakeBackend {
  @override
  Future<BookViewData> openBook(String id) async => BookViewData(
        id: 'b1',
        title: '测试书',
        chapters: [
          ChapterData(
            title: '第一章',
            text: List<String>.generate(
              40,
              (i) => '这是第${i + 1}段，用于验证拖动正文滚动时不会误触顶底栏。',
            ).join(),
          ),
        ],
      );
}

Widget _reader({
  required LibraryBackend backend,
  FakeTranslateBackend? translate,
}) =>
    MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: backend,
        translateBackend: translate,
      ),
    );

void _setPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('US-1 点击正文文字 center toggle 顶底栏（再点隐藏 + 空白同样 toggle）',
      (tester) async {
    _setPhone(tester);
    final backend = _InteractionBackend();
    await tester.pumpWidget(_reader(backend: backend));
    await _settle(tester);

    final textFinder = find.text(_ch1Text);
    expect(textFinder, findsOneWidget);
    expect(find.byTooltip('返回书架'), findsNothing, reason: '沉浸态无 Chrome');

    // 点在文字上（center）→ 呼出
    await tester.tapAt(tester.getCenter(textFinder));
    await _settle(tester);
    expect(find.byTooltip('返回书架'), findsOneWidget);
    expect(find.byType(ReaderBottomBar), findsOneWidget);
    expect(find.text('下一章'), findsOneWidget);

    // 再点同一段文字 center → 隐藏
    await tester.tapAt(tester.getCenter(textFinder));
    await _settle(tester);
    expect(find.byTooltip('返回书架'), findsNothing);
    expect(find.byType(ReaderBottomBar), findsNothing);

    // 点文字下方空白（仍在中部 1/3）→ 同样 toggle
    final rect = tester.getRect(textFinder);
    await tester.tapAt(Offset(rect.center.dx, rect.bottom + 40));
    await _settle(tester);
    expect(find.byTooltip('返回书架'), findsOneWidget, reason: '两种落点都成立');
  });

  testWidgets('US-2 长按选中不误触 Chrome', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_reader(
      backend: _InteractionBackend(),
      translate: FakeTranslateBackend(),
    ));
    await _settle(tester);

    // 长按文字 → 工具条出现，Chrome 不得出现
    await tester.longPress(find.text(_ch1Text));
    await _settle(tester);
    expect(find.byType(ReaderSelectionToolbar), findsOneWidget);
    expect(find.byTooltip('返回书架'), findsNothing, reason: '长按选中不得误触 Chrome');
  });

  testWidgets('US-2 拖拽滚动不误触 Chrome', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_reader(backend: _VeryLongBackend()));
    await _settle(tester);

    final scrollable = find.byType(SingleChildScrollView);
    expect(scrollable, findsOneWidget);
    await tester.drag(scrollable, const Offset(0, -200));
    await _settle(tester);
    final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(state.position.pixels, greaterThan(0.0), reason: '拖拽应产生滚动');
    expect(find.byTooltip('返回书架'), findsNothing, reason: '拖拽不得误触 Chrome');
  });

  testWidgets('US-4 滚动模式底栏"下一章"真实切章并保存进度', (tester) async {
    _setPhone(tester);
    final backend = _InteractionBackend();
    await tester.pumpWidget(_reader(backend: backend));
    await _settle(tester);

    await tester.tapAt(tester.getCenter(find.text(_ch1Text)));
    await _settle(tester);
    await tester.tap(find.text('下一章'));
    await _settle(tester);

    expect(find.text(_ch2Text), findsOneWidget);
    expect(backend.saved?.href, 'chapter_0002.xhtml');
  });

  testWidgets('US-12 无 key 翻译错误浮层 → 去设置 → SettingsPage', (tester) async {
    _setPhone(tester);
    final translate = FakeTranslateBackend(
      translateFailures: 1,
      translateError: '翻译服务未配置：未配置在线翻译 API Key（deepl），'
          '且离线翻译未命中（请先安装内置词库）；请在「设置」中配置在线翻译或导入词库',
    );
    await tester.pumpWidget(_reader(
      backend: _InteractionBackend(),
      translate: translate,
    ));
    await _settle(tester);

    // 真实长按选中 → 工具条 → 翻译
    await tester.longPress(find.text(_ch1Text));
    await _settle(tester);
    await tester.tap(find.text('翻译'));
    await _settle(tester);

    expect(find.textContaining('设置'), findsWidgets);
    expect(find.text('去设置'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('去设置'));
    await _settle(tester);
    expect(find.byType(SettingsPage), findsOneWidget);
  });
}
