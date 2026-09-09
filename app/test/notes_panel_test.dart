// REQ-009 · NotesPanel / NoteEditorCard / filterNoteGroups 边界与异常测试
//（US-6/7/9/11/12/13/16/17，线框 07）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/services/export_path_picker.dart';
import 'package:reader_app/services/notes_backend.dart';
import 'package:reader_app/widgets/note_editor_card.dart';
import 'package:reader_app/widgets/notes_panel.dart';

import 'fake_notes_backend.dart';

/// 可编程导出路径选择器：记录调用，返回预设结果。
class _FakePicker implements ExportPathPicker {
  _FakePicker({this.result});
  final String? result;
  final List<String> calls = <String>[];

  @override
  Future<String?> pick({
    required String suggestedName,
    required String extension,
  }) async {
    calls.add('$suggestedName.$extension');
    return result;
  }
}

/// list() 抛异常的 fake（错误态）。
class _ThrowingBackend extends FakeNotesBackend {
  @override
  Future<List<NoteGroupData>> list(String bookId) async =>
      throw Exception('db down');
}

/// export() 抛异常的 fake（导出失败态）。
class _ExportThrowingBackend extends FakeNotesBackend {
  @override
  Future<ExportSummaryData> export(
          String bookId, String fmt, String outPath) async =>
      throw Exception('io');
}

AnnotationData note(
  String id, {
  String kind = 'highlight',
  String? color = '#FBC02D',
  String? snippet = '原文片段',
  String? noteText,
  String href = 'c1.xhtml',
  int? start = 0,
  int? end = 4,
  int updatedAt = 1700000000,
}) =>
    AnnotationData(
      id: id,
      bookId: 'b1',
      kind: kind,
      color: color,
      href: href,
      progression: 0.1,
      snippet: snippet,
      noteText: noteText,
      start: start,
      end: end,
      createdAt: updatedAt,
      updatedAt: updatedAt,
      syncStatus: 'local',
    );

FakeNotesBackend backendWith(List<AnnotationData> notes,
    {Map<String, String>? titles}) {
  final b = FakeNotesBackend(
    chapterTitles: titles ?? {'c1.xhtml': '第一章', 'c2.xhtml': '第二章'},
  );
  b.store.addAll(notes);
  return b;
}

Future<void> pumpPanel(
  WidgetTester tester, {
  required NotesBackend backend,
  ExportPathPicker? picker,
  VoidCallback? onClose,
  ValueChanged<AnnotationData>? onTapNote,
  VoidCallback? onChanged,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 360,
        height: 700,
        child: NotesPanel(
          bookId: 'b1',
          bookTitle: '测试书',
          notesBackend: backend,
          picker: picker ?? _FakePicker(result: '/tmp/out.md'),
          onClose: onClose,
          onTapNote: onTapNote,
          onChanged: onChanged,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('filterNoteGroups', () {
    final groups = <NoteGroupData>[
      NoteGroupData(
        chapterTitle: '城市与记忆',
        href: 'c1',
        notes: [
          note('a', snippet: '看不见的城市', noteText: '批注A'),
          note('b', snippet: '卡尔维诺', noteText: null),
        ],
      ),
    ];

    test('空/纯空白关键词返回原列表', () {
      expect(filterNoteGroups(groups, ''), same(groups));
      expect(filterNoteGroups(groups, '   '), same(groups));
    });

    test('匹配 snippet（大小写不敏感）', () {
      final out = filterNoteGroups(groups, '看不见');
      expect(out.length, 1);
      expect(out.first.notes.single.id, 'a');
    });

    test('匹配批注文本', () {
      final out = filterNoteGroups(groups, '批注a');
      expect(out.single.notes.single.id, 'a');
    });

    test('匹配章节标题 → 组内全部笔记保留', () {
      final out = filterNoteGroups(groups, '记忆');
      expect(out.single.notes.length, 2);
    });

    test('无匹配 → 空列表', () {
      expect(filterNoteGroups(groups, 'zzz'), isEmpty);
    });
  });

  group('NotesPanel 加载与空态', () {
    testWidgets('空笔记 → 暂无笔记 + 全部删除禁用 + 导出提示', (tester) async {
      await pumpPanel(tester, backend: backendWith(const []));
      expect(find.text('暂无笔记'), findsOneWidget);
      final deleteAll =
          tester.widget<TextButton>(find.byKey(const Key('notes-delete-all')));
      expect(deleteAll.onPressed, isNull, reason: '空态全部删除应禁用');

      await tester.tap(find.byKey(const Key('notes-export')));
      await tester.pump();
      expect(find.text('暂无笔记'), findsWidgets);
    });

    testWidgets('加载失败 → 显示错误信息且不崩溃', (tester) async {
      await pumpPanel(tester, backend: _ThrowingBackend());
      expect(find.textContaining('加载失败'), findsOneWidget);
    });

    testWidgets('渲染章节分组 / 片段 / 批注 / 书签行', (tester) async {
      final b = backendWith([
        note('a', snippet: '看不见的城市', noteText: '我的批注'),
        note('bm', kind: 'bookmark', color: null, snippet: '书签处'),
      ]);
      await pumpPanel(tester, backend: b);
      expect(find.text('第一章'), findsOneWidget);
      expect(find.text('看不见的城市'), findsOneWidget);
      expect(find.text('我的批注'), findsOneWidget);
      expect(find.text('书签处'), findsOneWidget);
      // 书签行无颜色色标，普通笔记有色标
      expect(find.byKey(const Key('note-color-strip-bm')), findsNothing);
      expect(find.byKey(const Key('note-color-strip-a')), findsOneWidget);
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
    });

    testWidgets('面板内搜索过滤：无匹配显示「无匹配」', (tester) async {
      await pumpPanel(tester, backend: backendWith([note('a')]));
      await tester.enterText(find.byKey(const Key('notes-search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('无匹配'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('notes-search')), '原文');
      await tester.pumpAndSettle();
      expect(find.text('原文片段'), findsOneWidget);
    });

    testWidgets('关闭按钮回调', (tester) async {
      var closed = false;
      await pumpPanel(tester, backend: backendWith(const []), onClose: () => closed = true);
      await tester.tap(find.byKey(const Key('notes-close')));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
    });

    testWidgets('点击笔记行触发 onTapNote（多选模式外）', (tester) async {
      AnnotationData? tapped;
      await pumpPanel(
        tester,
        backend: backendWith([note('a')]),
        onTapNote: (n) => tapped = n,
      );
      await tester.tap(find.byKey(const Key('note-row-a')));
      await tester.pumpAndSettle();
      expect(tapped?.id, 'a');
    });
  });

  group('多选批量删除', () {
    testWidgets('长按进入多选；取消选择后删除选中禁用', (tester) async {
      final b = backendWith([note('a'), note('b')]);
      await pumpPanel(tester, backend: b);

      await tester.longPress(find.byKey(const Key('note-row-a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notes-cancel-multi')), findsOneWidget);
      // 长按后 a 已选中 → 按钮可用
      var btn = tester.widget<FilledButton>(
          find.byKey(const Key('notes-delete-selected')));
      expect(btn.onPressed, isNotNull);
      // 再点 a 取消选择 → 空选 → 禁用
      await tester.tap(find.byKey(const Key('note-row-a')));
      await tester.pumpAndSettle();
      btn = tester.widget<FilledButton>(
          find.byKey(const Key('notes-delete-selected')));
      expect(btn.onPressed, isNull, reason: '未选任何笔记时应禁用批量删除');
    });

    testWidgets('取消多选退出选择态', (tester) async {
      await pumpPanel(tester, backend: backendWith([note('a')]));
      await tester.longPress(find.byKey(const Key('note-row-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notes-cancel-multi')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notes-cancel-multi')), findsNothing);
    });

    testWidgets('直接操作复选框：勾选/取消', (tester) async {
      final b = backendWith([note('a'), note('b')]);
      await pumpPanel(tester, backend: b);
      await tester.longPress(find.byKey(const Key('note-row-a')));
      await tester.pumpAndSettle();
      final checkboxA = find.descendant(
        of: find.byKey(const Key('note-row-a')),
        matching: find.byType(Checkbox),
      );
      expect(tester.widget<Checkbox>(checkboxA).value, isTrue);
      await tester.tap(checkboxA);
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(checkboxA).value, isFalse);
      expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('notes-delete-selected')))
            .onPressed,
        isNull,
      );
      await tester.tap(checkboxA);
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(checkboxA).value, isTrue);
    });

    testWidgets('批量删除：确认后调用 deleteMany 并刷新', (tester) async {
      final b = backendWith([note('a'), note('b')]);
      await pumpPanel(tester, backend: b);
      await tester.longPress(find.byKey(const Key('note-row-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notes-delete-selected')));
      await tester.pumpAndSettle();
      expect(find.textContaining('确认删除选中的'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-delete')));
      await tester.pumpAndSettle();
      expect(b.store.map((e) => e.id), ['b']);
    });

    testWidgets('批量删除：取消不删除', (tester) async {
      final b = backendWith([note('a')]);
      await pumpPanel(tester, backend: b);
      await tester.longPress(find.byKey(const Key('note-row-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notes-delete-selected')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(b.store.length, 1);
    });
  });

  group('单条删除 / 全部删除', () {
    testWidgets('编辑卡片删除 → 确认后删除', (tester) async {
      final b = backendWith([note('a', kind: 'note', noteText: '批注')]);
      await pumpPanel(tester, backend: b);
      await tester.tap(find.byKey(const Key('note-edit-a')));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorCard), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-delete')));
      await tester.pumpAndSettle();
      expect(b.store, isEmpty);
      expect(b.deleteCalls, contains('a'));
    });

    testWidgets('全部删除 → 确认后 deleteAll', (tester) async {
      final b = backendWith([note('a'), note('b')]);
      await pumpPanel(tester, backend: b);
      await tester.tap(find.byKey(const Key('notes-delete-all')));
      await tester.pumpAndSettle();
      expect(find.textContaining('确认删除该书全部笔记'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-delete')));
      await tester.pumpAndSettle();
      expect(b.store, isEmpty);
    });

    testWidgets('全部删除取消 → 保留', (tester) async {
      final b = backendWith([note('a')]);
      await pumpPanel(tester, backend: b);
      await tester.tap(find.byKey(const Key('notes-delete-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(b.store.length, 1);
    });
  });

  group('编辑 / 改色', () {
    testWidgets('保存批注 → update 并回列表', (tester) async {
      final b = backendWith([note('a', kind: 'note', noteText: '旧')]);
      await pumpPanel(tester, backend: b);
      await tester.tap(find.byKey(const Key('note-edit-a')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('note-editor-field')), '新批注');
      await tester.tap(find.byKey(const Key('note-editor-save')));
      await tester.pumpAndSettle();
      expect(b.store.single.noteText, '新批注');
      expect(find.byType(NoteEditorCard), findsNothing);
    });

    testWidgets('批注清空 → 提示「批注内容不能为空」且不保存', (tester) async {
      final b = backendWith([note('a', kind: 'note', noteText: '旧')]);
      await pumpPanel(tester, backend: b);
      await tester.tap(find.byKey(const Key('note-edit-a')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('note-editor-field')), '   ');
      await tester.tap(find.byKey(const Key('note-editor-save')));
      await tester.pump();
      expect(find.text('批注内容不能为空'), findsOneWidget);
      expect(b.store.single.noteText, '旧');
    });

    testWidgets('编辑卡片取消关闭', (tester) async {
      await pumpPanel(
          tester, backend: backendWith([note('a', kind: 'note', noteText: '旧')]));
      await tester.tap(find.byKey(const Key('note-edit-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorCard), findsNothing);
    });

    testWidgets('点色标 → 选色 → update color', (tester) async {
      final b = backendWith([note('a', color: '#FBC02D')]);
      await pumpPanel(tester, backend: b);
      await tester.tap(find.byKey(const Key('note-color-strip-a')));
      await tester.pumpAndSettle();
      expect(find.text('选择颜色'), findsOneWidget);
      await tester.tap(find.byKey(const Key('panel-color-#43A047')));
      await tester.pumpAndSettle();
      expect(b.store.single.color, '#43A047');
    });
  });

  group('导出流程', () {
    testWidgets('有笔记 → 选 Markdown → picker 返回路径 → export 成功', (tester) async {
      final b = backendWith([note('a')]);
      final picker = _FakePicker(result: '/tmp/notes.md');
      await pumpPanel(tester, backend: b, picker: picker);
      await tester.tap(find.byKey(const Key('notes-export')));
      await tester.pumpAndSettle();
      expect(find.text('导出格式'), findsOneWidget);
      await tester.tap(find.text('Markdown (.md)'));
      await tester.pumpAndSettle();
      expect(picker.calls, ['测试书.md']);
      expect(find.textContaining('已导出 1 条'), findsOneWidget);
    });

    testWidgets('选 JSON → 扩展名 json', (tester) async {
      final b = backendWith([note('a')]);
      final picker = _FakePicker(result: '/tmp/notes.json');
      await pumpPanel(tester, backend: b, picker: picker);
      await tester.tap(find.byKey(const Key('notes-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JSON (.json)'));
      await tester.pumpAndSettle();
      expect(picker.calls, ['测试书.json']);
    });

    testWidgets('用户取消保存框（picker 返回 null）→ 不调用 export', (tester) async {
      final b = backendWith([note('a')]);
      final picker = _FakePicker(result: null);
      await pumpPanel(tester, backend: b, picker: picker);
      await tester.tap(find.byKey(const Key('notes-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Markdown (.md)'));
      await tester.pumpAndSettle();
      // fake export 在 store 非空时返回；取消时 picker 被调用但不应出现导出成功提示
      expect(picker.calls.length, 1);
      expect(find.textContaining('已导出'), findsNothing);
    });

    testWidgets('导出格式对话框取消 → 不调用 picker', (tester) async {
      final picker = _FakePicker(result: '/tmp/x.md');
      await pumpPanel(tester, backend: backendWith([note('a')]), picker: picker);
      await tester.tap(find.byKey(const Key('notes-export')));
      await tester.pumpAndSettle();
      // 点对话框外部关闭
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(picker.calls, isEmpty);
    });

    testWidgets('导出异常 → 提示导出失败', (tester) async {
      final b = _ExportThrowingBackend();
      b.store.add(note('a'));
      final picker = _FakePicker(result: '/tmp/x.md');
      await pumpPanel(tester, backend: b, picker: picker);
      await tester.tap(find.byKey(const Key('notes-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Markdown (.md)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('导出失败'), findsOneWidget);
    });
  });
}
