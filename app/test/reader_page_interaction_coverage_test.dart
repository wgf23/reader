import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/pages/reader_page.dart';
import 'package:reader_app/services/library_backend.dart';
import 'package:reader_app/widgets/selection_toolbar.dart';

import 'fake_backend.dart';
import 'fake_paged_view_controls.dart';

/// REQ-007 阶段4补测：覆盖 `reader_page.dart` 新增行中的边界分支
/// （dismiss 命中区 / Listener.onPointerMove / `_jumpToProgress` 分页重排接线）。
/// 仅测试文件，不改生产代码。

const String _ch1 =
    '很久以前，有一座山，山里住着一位老人。'
    '他每天清晨都会沿着溪流散步，看雾气从山谷里升起。'
    '孩子们围坐在他身边，听他讲那些古老的故事。'
    '年复一年，山还是那座山，溪水还是那条溪水，'
    '只是听故事的人换了一批又一批，故事却从未讲完。'
    '老人说，山外的世界很大，但每个人心里都有一座山。'
    '有一天，一个年轻人背起行囊，决定翻过那座山去看一看。'
    '他走了很远很远，直到回望时，故乡已经变成一个小小的点。'
    '山风吹过他的衣襟，他忽然明白，老人讲的故事从来都不是关于山，'
    '而是关于每一个愿意出发的人，关于那些被时间带走却从未消失的东西。'
    '后来，年轻人也成了讲故事的人，把那座山讲给更多的孩子听。';

const String _ch2 = '故事结束了，年轻人终于翻过了那座山。';

/// 两章长文本后端（滚动模式），使正文文字铺满屏幕中部。
class _LongTextBackend extends FakeBackend {
  @override
  Future<BookViewData> openBook(String id) async => const BookViewData(
        id: 'b1',
        title: '测试书',
        chapters: [
          ChapterData(title: '第一章', text: _ch1),
          ChapterData(title: '第二章', text: _ch2),
        ],
      );
}

/// 分页模式 fake 构建器（不实例化真实 WebView）。
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
    const Center(child: Text('分页模式（fake WebView）'));

void main() {
  testWidgets('REQ-007 D1 dismiss 分支：非中部点击隐藏 Chrome 并清空选中', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(bookId: 'b1', bookTitle: '测试书', backend: _LongTextBackend()),
    ));
    await tester.pumpAndSettle();

    // 呼出 Chrome
    await tester.tapAt(tester.getCenter(find.text(_ch1)));
    await tester.pump();
    expect(find.byTooltip('返回书架'), findsOneWidget);

    // 触发选中（工具条出现），使 dismiss 同时命中 hasSelection 与 chromeVisible 两分支
    final sa = tester.widget<SelectionArea>(find.byType(SelectionArea));
    sa.onSelectionChanged!(const SelectedContent(plainText: '很久以前'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSelectionToolbar), findsOneWidget);

    // 点击左侧非中部（relX≈0.125 < 0.33）→ dismiss
    await tester.tapAt(const Offset(100, 400));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderSelectionToolbar), findsNothing, reason: 'dismiss 应清空选中');
    expect(find.byTooltip('返回书架'), findsNothing, reason: 'dismiss 应隐藏 Chrome');
  });

  testWidgets('REQ-007 D1 onPointerMove 分支：拖动正文（超 slop）不 toggle Chrome', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(bookId: 'b1', bookTitle: '测试书', backend: _LongTextBackend()),
    ));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(find.text(_ch1)));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -120)); // > kTouchSlop(18)
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byTooltip('返回书架'), findsNothing,
        reason: '位移超 slop 不算 tap，不得 toggle Chrome');
  });

  testWidgets('REQ-007 D2/D4 分页目录切章 → relayoutAfterLoad 经 PagedLoadGate 接线', (tester) async {
    final controls = FakePagedViewControls();
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: FakeBackend(),
        pagedViewBuilder: _fakePagedBuilder,
        initialPagedMode: true,
        pagedControls: controls,
      ),
    ));
    await tester.pumpAndSettle();

    // 中部点击呼出 Chrome → 打开目录 → 选第二章（触发 _onChapterSelect → _jumpToProgress）
    await tester.tapAt(tester.getCenter(find.text('分页模式（fake WebView）')));
    await tester.pump();
    await tester.tap(find.byTooltip('目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2. 第二章'));
    await tester.pumpAndSettle();

    expect(controls.relayoutAfterLoadCalls, 1, reason: '分页切章后应走 relayoutAfterLoad');
  });
}
