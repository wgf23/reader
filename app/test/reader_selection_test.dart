import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/pages/reader_page.dart';
import 'package:reader_app/widgets/selection_toolbar.dart';
import 'fake_backend.dart';
import 'fake_translate_backend.dart';

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
}
