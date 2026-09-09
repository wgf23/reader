// REQ-009 · ReaderPage 笔记/搜索接线边界测试（US-1/2/3/4/5/8/9/11/12/14/16/17/19）。
//
// 覆盖 reader_page.dart 新增分支：选词→划线/批注、批注编辑器校验、笔记面板开合、
// 面板条目跳转+临时高亮、书签、导出（含取消/失败/空态）、搜索页→命中定位（同书/跨书）、
// initialTarget 临时高亮与超时清除、滚动清除临时高亮、错误提示。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/pages/reader_page.dart';
import 'package:reader_app/pages/search_page.dart';
import 'package:reader_app/services/export_path_picker.dart';
import 'package:reader_app/services/library_backend.dart';
import 'package:reader_app/services/notes_backend.dart';
import 'package:reader_app/services/search_backend.dart';
import 'package:reader_app/widgets/note_editor_card.dart';
import 'package:reader_app/widgets/notes_panel.dart';

import 'fake_backend.dart';
import 'fake_notes_backend.dart';
import 'fake_search_backend.dart';

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

const String _ch2 =
    '故事结束了，年轻人终于翻过了那座山。'
    '他站在山巅，回望来时的路，忽然明白了很多事情。'
    '山风吹过，带走了他的疲惫，也带走了那些年少时的迷茫。'
    '他知道，山的那一边，还有更多的山在等着他。';

class _TwoChapterBackend extends FakeBackend {
  @override
  Future<BookViewData> openBook(String id) async => BookViewData(
        id: id,
        title: '测试书',
        chapters: const [
          ChapterData(
              title: '第一章', text: _ch1, href: 'chapter_0001.xhtml'),
          ChapterData(
              title: '第二章', text: _ch2, href: 'chapter_0002.xhtml'),
        ],
      );
}

class _ThrowingNotes extends FakeNotesBackend {
  _ThrowingNotes({this.createError, this.listError, this.toggleError, this.resolveError});
  final bool? createError;
  final bool? listError;
  final bool? toggleError;
  final bool? resolveError;

  @override
  Future<AnnotationData> create({
    required String bookId,
    required String href,
    required String text,
    required double progression,
    required String kind,
    String? color,
    String? noteText,
  }) async {
    if (createError == true) throw Exception('create failed');
    return super.create(
      bookId: bookId,
      href: href,
      text: text,
      progression: progression,
      kind: kind,
      color: color,
      noteText: noteText,
    );
  }

  @override
  Future<List<NoteGroupData>> list(String bookId) async {
    if (listError == true) throw Exception('list failed');
    return super.list(bookId);
  }

  @override
  Future<BookmarkToggleData> toggleBookmark({
    required String bookId,
    required String href,
    required double progression,
    String? snippet,
  }) async {
    if (toggleError == true) throw Exception('toggle failed');
    return super.toggleBookmark(
        bookId: bookId, href: href, progression: progression, snippet: snippet);
  }

  @override
  Future<ProgressData> resolve(String noteId) async {
    if (resolveError == true) throw Exception('resolve failed');
    return super.resolve(noteId);
  }
}

class _ExportThrowingNotes extends FakeNotesBackend {
  @override
  Future<ExportSummaryData> export(
          String bookId, String fmt, String outPath) async =>
      throw Exception('io');
}

class _Picker implements ExportPathPicker {
  _Picker(this.result);
  final String? result;
  final List<String> calls = <String>[];
  @override
  Future<String?> pick(
      {required String suggestedName, required String extension}) async {
    calls.add('$suggestedName.$extension');
    return result;
  }
}

AnnotationData _note(
  String id, {
  String href = 'chapter_0001.xhtml',
  String kind = 'highlight',
  String? color = '#FBC02D',
  int? start = 0,
  int? end = 4,
  double progression = 0.0,
  String? snippet = '很久以前',
  String? noteText,
}) =>
    AnnotationData(
      id: id,
      bookId: 'b1',
      kind: kind,
      color: color,
      href: href,
      progression: progression,
      snippet: snippet,
      noteText: noteText,
      start: start,
      end: end,
      createdAt: 1700000000,
      updatedAt: 1700000000,
      syncStatus: 'local',
    );

Future<void> _toggleChrome(WidgetTester tester) async {
  await tester.tapAt(tester.getCenter(find.text(_ch1)));
  await tester.pump();
}

Future<void> _openMore(WidgetTester tester) async {
  if (find.byTooltip('更多').evaluate().isEmpty) {
    await _toggleChrome(tester);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byTooltip('更多'));
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, String text) async {
  final sa = tester.widget<SelectionArea>(find.byType(SelectionArea));
  sa.onSelectionChanged!(SelectedContent(plainText: text));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('选词→划线/批注落库；批注编辑器空文本拦截 + 取消', (tester) async {
    final notes = FakeNotesBackend(
      chapterTexts: const {'chapter_0001.xhtml': _ch1},
      chapterTitles: const {'chapter_0001.xhtml': '第一章'},
    );
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: notes,
      ),
    ));
    await tester.pumpAndSettle();

    await _select(tester, '很久以前');
    await tester.tap(find.text('划线'));
    await tester.pumpAndSettle();
    expect(notes.createCalls.any((c) => c.startsWith('underline:')), isTrue);

    // 批注：打开编辑器 → 空文本拦截 → 输入 → 保存
    await _select(tester, '有一座山');
    await tester.tap(find.text('批注'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorCard), findsOneWidget);
    await tester.tap(find.byKey(const Key('note-editor-save')));
    await tester.pumpAndSettle();
    expect(find.text('批注内容不能为空'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('note-editor-field')), '我的批注');
    await tester.tap(find.byKey(const Key('note-editor-save')));
    await tester.pumpAndSettle();
    expect(notes.store.any((a) => a.kind == 'note' && a.noteText == '我的批注'),
        isTrue);

    // 编辑器「取消」关闭
    await _select(tester, '老人');
    await tester.tap(find.text('批注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorCard), findsNothing);
  });

  testWidgets('创建笔记失败 → 提示创建笔记失败', (tester) async {
    final notes = _ThrowingNotes(createError: true);
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: notes,
      ),
    ));
    await tester.pumpAndSettle();
    await _select(tester, '很久以前');
    await tester.tap(find.text('高亮'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('note-color-#FBC02D')));
    await tester.pumpAndSettle();
    expect(find.textContaining('创建笔记失败'), findsOneWidget);
  });

  testWidgets('笔记面板：更多→笔记打开；点外关闭；点条目跳转+临时高亮', (tester) async {
    final notes = FakeNotesBackend(
      chapterTexts: const {
        'chapter_0001.xhtml': _ch1,
        'chapter_0002.xhtml': _ch2,
      },
      chapterTitles: const {
        'chapter_0001.xhtml': '第一章',
        'chapter_0002.xhtml': '第二章',
      },
    );
    notes.store.addAll([
      _note('n1', href: 'chapter_0001.xhtml', snippet: '很久以前'),
      _note('n2', href: 'chapter_0002.xhtml', snippet: '故事结束'),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: notes,
      ),
    ));
    await tester.pumpAndSettle();

    await _openMore(tester);
    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesPanel), findsOneWidget);
    expect(find.byKey(const Key('notes-scrim')), findsOneWidget);

    // 点外关闭
    await tester.tap(find.byKey(const Key('notes-scrim')));
    await tester.pumpAndSettle();
    expect(find.byType(NotesPanel), findsNothing);

    // 再次打开 → 点第二章条目 → 跳转并出现临时高亮
    await _openMore(tester);
    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('note-row-n2')));
    await tester.pumpAndSettle();
    expect(find.byType(NotesPanel), findsNothing);
    expect(find.text(_ch2), findsOneWidget);
    expect(find.byKey(const Key('temp-highlight')), findsOneWidget);
  });

  testWidgets('面板条目 resolve 失败 → 降级按 note.href 跳转', (tester) async {
    final notes = _ThrowingNotes(resolveError: true);
    notes.store.add(_note('n1', href: 'chapter_0002.xhtml', snippet: '故事结束'));
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: notes,
      ),
    ));
    await tester.pumpAndSettle();
    await _openMore(tester);
    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('note-row-n1')));
    await tester.pumpAndSettle();
    expect(find.text(_ch2), findsOneWidget);
  });

  testWidgets('书签切换失败 → 提示书签操作失败', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: _ThrowingNotes(toggleError: true),
      ),
    ));
    await tester.pumpAndSettle();
    await _toggleChrome(tester);
    await tester.tap(find.byTooltip('加书签'));
    await tester.pumpAndSettle();
    expect(find.textContaining('书签操作失败'), findsOneWidget);
  });

  testWidgets('更多→导出：有笔记→选格式→picker→成功提示', (tester) async {
    final notes = FakeNotesBackend();
    notes.store.add(_note('n1'));
    final picker = _Picker('/tmp/out.md');
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: notes,
        exportPathPicker: picker,
      ),
    ));
    await tester.pumpAndSettle();
    await _openMore(tester);
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Markdown (.md)'));
    await tester.pumpAndSettle();
    expect(picker.calls, ['测试书.md']);
    expect(find.textContaining('已导出 1 条'), findsOneWidget);
  });

  testWidgets('更多→导出：picker 取消 → 不调用 export', (tester) async {
    final notes = FakeNotesBackend();
    notes.store.add(_note('n1'));
    final picker = _Picker(null);
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: notes,
        exportPathPicker: picker,
      ),
    ));
    await tester.pumpAndSettle();
    await _openMore(tester);
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JSON (.json)'));
    await tester.pumpAndSettle();
    expect(picker.calls, ['测试书.json']);
    expect(find.textContaining('已导出'), findsNothing);
  });

  testWidgets('更多→导出：无笔记 → 提示暂无笔记', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: FakeNotesBackend(),
        exportPathPicker: _Picker('/tmp/x.md'),
      ),
    ));
    await tester.pumpAndSettle();
    await _openMore(tester);
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    expect(find.text('暂无笔记'), findsOneWidget);
  });

  testWidgets('更多→导出：读取笔记失败 → 提示读取笔记失败', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: _ThrowingNotes(listError: true),
        exportPathPicker: _Picker('/tmp/x.md'),
      ),
    ));
    await tester.pumpAndSettle();
    await _openMore(tester);
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    expect(find.textContaining('读取笔记失败'), findsOneWidget);
  });

  testWidgets('更多→搜索 → 定位命中（同书）→ 返回并临时高亮', (tester) async {
    final notes = FakeNotesBackend();
    final search = FakeSearchBackend(hits: [
      const SearchHitData(
        bookId: 'b1',
        bookTitle: '测试书',
        href: 'chapter_0002.xhtml',
        chapterTitle: '第二章',
        chapterIndex: 1,
        snippet: '故事结束',
        ranges: [TextRangeData(start: 0, end: 4)],
      ),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: notes,
        searchBackend: search,
      ),
    ));
    await tester.pumpAndSettle();
    await _openMore(tester);
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);
    await tester.enterText(find.byKey(const Key('search-field')), '故事');
    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-locate-0')));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsNothing);
    expect(find.text(_ch2), findsOneWidget);
    expect(find.byKey(const Key('temp-highlight')), findsOneWidget);
  });

  testWidgets('搜索命中跨书 → push 新 ReaderPage 携带 initialTarget', (tester) async {
    final search = FakeSearchBackend(hits: [
      const SearchHitData(
        bookId: 'b2',
        bookTitle: '另一本书',
        href: 'chapter_0001.xhtml',
        chapterTitle: '第一章',
        chapterIndex: 0,
        snippet: '很久以前',
        ranges: [TextRangeData(start: 0, end: 4)],
      ),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: FakeNotesBackend(),
        searchBackend: search,
      ),
    ));
    await tester.pumpAndSettle();
    await _openMore(tester);
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), '很久');
    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-locate-0')));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderPage, skipOffstage: false), findsNWidgets(2),
        reason: '跨书应 push 新 ReaderPage（旧页 offstage）');
    expect(find.byKey(const Key('temp-highlight')), findsOneWidget);
  });

  testWidgets('initialTarget：定位到目标章 + 临时高亮 3 秒后自动清除', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: FakeNotesBackend(),
        initialTarget: const ReaderTarget(
          href: 'chapter_0002.xhtml',
          progression: 0.0,
          tempStart: 0,
          tempEnd: 4,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(_ch2), findsOneWidget);
    expect(find.byKey(const Key('temp-highlight')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const Key('temp-highlight')), findsNothing);
  });

  testWidgets('initialTarget 无临时区间 → 不显示临时高亮', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: FakeNotesBackend(),
        initialTarget: const ReaderTarget(
          href: 'chapter_0002.xhtml',
          progression: 0.2,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('temp-highlight')), findsNothing);
  });

  testWidgets('点击正文清除临时高亮', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: FakeNotesBackend(),
        initialTarget: const ReaderTarget(
          href: 'chapter_0002.xhtml',
          progression: 0.0,
          tempStart: 0,
          tempEnd: 4,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('temp-highlight')), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.text(_ch2)));
    await tester.pump();
    expect(find.byKey(const Key('temp-highlight')), findsNothing);
  });

  testWidgets('笔记加载失败静默（不阻断阅读）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: _ThrowingNotes(listError: true),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(_ch1), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('批注编辑器「删除」仅关闭弹窗（不落库）', (tester) async {
    final notes = FakeNotesBackend(
      chapterTexts: const {'chapter_0001.xhtml': _ch1},
    );
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: notes,
      ),
    ));
    await tester.pumpAndSettle();
    await _select(tester, '很久以前');
    await tester.tap(find.text('批注'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorCard), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorCard), findsNothing);
    expect(notes.store, isEmpty);
  });

  testWidgets('更多→导出：export 抛异常 → 提示导出失败', (tester) async {
    final notes = _ExportThrowingNotes();
    notes.store.add(_note('n1'));
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: notes,
        exportPathPicker: _Picker('/tmp/x.md'),
      ),
    ));
    await tester.pumpAndSettle();
    await _openMore(tester);
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Markdown (.md)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('导出失败'), findsOneWidget);
  });

  testWidgets('笔记面板关闭按钮 → 面板消失', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: FakeNotesBackend(),
      ),
    ));
    await tester.pumpAndSettle();
    await _openMore(tester);
    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesPanel), findsOneWidget);
    await tester.tap(find.byKey(const Key('notes-close')));
    await tester.pumpAndSettle();
    expect(find.byType(NotesPanel), findsNothing);
  });
}
