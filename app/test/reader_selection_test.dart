import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/pages/reader_page.dart';
import 'package:reader_app/services/library_backend.dart';
import 'package:reader_app/widgets/selection_toolbar.dart';
import 'fake_backend.dart';
import 'fake_translate_backend.dart';

/// 长文本后端：让正文占满纵向空间，便于验证工具条跟随所选文字（而非固定顶部）。
class _LongFakeBackend extends FakeBackend {
  @override
  Future<BookViewData> openBook(String id) async => const BookViewData(
        id: 'b1',
        title: '测试书',
        chapters: [ChapterData(title: '第一章', text: '第一句。\n\n第二句。\n\n第三句。\n\n第四句。\n\n第五句。\n\n第六句。\n\n第七句。\n\n第八句。\n\n第九句。\n\n第十句。\n\n第十一句。')],
      );
}

/// 真实长按手势触发选中 → 浮动工具条（含 翻译/查词）。
/// 守卫 REQ-004 关键交互：长按正文能弹出工具条，且注入 translateBackend 时含翻译/查词。
void main() {
  testWidgets('滚动模式：真实长按正文 → 浮动工具条出现且含翻译/查词', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: FakeBackend(),
        translateBackend: FakeTranslateBackend(),
      ),
    ));
    await tester.pumpAndSettle();

    final target = find.text('很久以前，有一座山。');
    expect(target, findsOneWidget);

    await tester.longPress(target);
    await tester.pumpAndSettle();

    expect(find.byType(ReaderSelectionToolbar), findsOneWidget);
    expect(find.text('划重点'), findsOneWidget);
    expect(find.text('笔记'), findsOneWidget);
    expect(find.text('翻译'), findsOneWidget);
    expect(find.text('查词'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
  });

  testWidgets('工具条跟随选中文字：中部长按 → 工具条出现在选词上方（非固定顶部）', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _LongFakeBackend(),
        translateBackend: FakeTranslateBackend(),
      ),
    ));
    await tester.pumpAndSettle();

    // 在正文中部（约 y=450）长按
    const pt = Offset(200, 450);
    await tester.longPressAt(pt);
    await tester.pumpAndSettle();

    expect(find.byType(ReaderSelectionToolbar), findsOneWidget);
    final toolbarTop = tester.getTopLeft(find.byType(ReaderSelectionToolbar)).dy;
    // 工具条应在所选文字上方（远高于固定顶部的 8px）
    expect(toolbarTop, lessThan(pt.dy));
    expect(toolbarTop, greaterThan(8), reason: '工具条应贴在选词上方，而非固定在屏幕最顶部');
  });
}
