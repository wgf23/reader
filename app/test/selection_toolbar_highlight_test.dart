// REQ-009 · ReaderSelectionToolbar 高亮选色分支（onHighlightColor 为 null 时直接回调）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/widgets/selection_toolbar.dart';

void main() {
  testWidgets('未提供 onHighlightColor → 点高亮直接回调 SelectionAction.highlight',
      (tester) async {
    SelectionAction? action;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderSelectionToolbar(onAction: (a) => action = a),
      ),
    ));
    await tester.tap(find.text('高亮'));
    await tester.pumpAndSettle();
    expect(action, SelectionAction.highlight);
  });

  testWidgets('提供 onHighlightColor → 点高亮展开色板，选色回调十六进制',
      (tester) async {
    SelectionAction? action;
    String? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderSelectionToolbar(
          onAction: (a) => action = a,
          onHighlightColor: (hex) => picked = hex,
        ),
      ),
    ));
    await tester.tap(find.text('高亮'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-color-#FBC02D')), findsOneWidget);
    expect(action, isNull);
    await tester.tap(find.byKey(const Key('note-color-#1A73E8')));
    await tester.pumpAndSettle();
    expect(picked, '#1A73E8');
    // 选色后色板收起
    expect(find.byKey(const Key('note-color-#FBC02D')), findsNothing);
  });
}
