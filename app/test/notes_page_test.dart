// REQ-009 · NotesPage 薄壳（线框 07 独立路由）测试（US-6/9）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/pages/notes_page.dart';
import 'package:reader_app/services/export_path_picker.dart';
import 'package:reader_app/widgets/notes_panel.dart';

import 'fake_notes_backend.dart';

void main() {
  testWidgets('注入后端/选择器 → 渲染 NotesPanel 与空态', (tester) async {
    final backend = FakeNotesBackend();
    await tester.pumpWidget(MaterialApp(
      home: NotesPage(
        bookId: 'b1',
        bookTitle: '测试书',
        notesBackend: backend,
        picker: _NoopPicker(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('笔记'), findsWidgets);
    expect(find.byType(NotesPanel), findsOneWidget);
    expect(find.text('暂无笔记'), findsOneWidget);
  });

  testWidgets('未注入 → 使用默认实现（无 FFI 时显示加载失败，不崩溃）', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: NotesPage(bookId: 'b1', bookTitle: '测试书'),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(NotesPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _NoopPicker implements ExportPathPicker {
  @override
  Future<String?> pick({
    required String suggestedName,
    required String extension,
  }) async =>
      null;
}
