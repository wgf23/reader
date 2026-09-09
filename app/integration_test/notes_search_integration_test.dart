import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_app/pages/reader_page.dart';
import 'package:reader_app/pages/search_page.dart';
import 'package:reader_app/services/library_backend.dart';
import 'package:reader_app/services/search_backend.dart';
import 'package:reader_app/widgets/notes_panel.dart';
import 'package:reader_app/widgets/selection_toolbar.dart';

import '../test/fake_backend.dart';
import '../test/fake_notes_backend.dart';
import '../test/fake_search_backend.dart';

/// REQ-009 真实集成测试（US-10 / US-22）。
///
/// 全程真实 `ReaderPage`/`SearchPage` + 真实 `longPress`/点击/面板/导航，
/// 注入 `FakeNotesBackend`/`FakeSearchBackend`（生产为 Rust）。
/// **不构造**合成顶/底栏（`no_synthetic_chrome_test.dart` 静态守卫）。

const String _ch1Text = '第一章很短，只用来把第二章顶进视口。';

const String _ch2Text = '看不见的城市，卡尔维诺写道：城市是记忆的。'
    '他还说，每一座城市都会把它的记忆藏在街巷的转角里。';

const String _href1 = 'chapter_0001.xhtml';
const String _href2 = 'chapter_0002.xhtml';

/// 两章短文本后端：两章都可见，便于真实长按第二章正文。
class _TwoChapterBackend extends FakeBackend {
  @override
  Future<BookViewData> openBook(String id) async => const BookViewData(
        id: 'b1',
        title: '测试书',
        chapters: [
          ChapterData(title: '第一章', text: _ch1Text, href: _href1),
          ChapterData(title: '第二章', text: _ch2Text, href: _href2),
        ],
      );
}

Widget _reader({
  required FakeNotesBackend notes,
  FakeSearchBackend? search,
}) =>
    MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _TwoChapterBackend(),
        notesBackend: notes,
        searchBackend: search ?? FakeSearchBackend(),
      ),
    );

void _setPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<void> _ensureChrome(WidgetTester tester) async {
  if (find.byTooltip('更多').evaluate().isNotEmpty) return;
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  await tester.tapAt(Offset(size.width / 2, size.height / 2));
  await tester.pumpAndSettle();
}

Future<void> _openNotesPanel(WidgetTester tester) async {
  await _ensureChrome(tester);
  await tester.tap(find.byTooltip('更多'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('笔记'));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('US-10 真实选词 → 高亮 → 笔记面板 → 跳回原文并临时高亮', (tester) async {
    _setPhone(tester);
    final notes = FakeNotesBackend(
      chapterTexts: const {_href1: _ch1Text, _href2: _ch2Text},
      chapterTitles: const {_href1: '第一章', _href2: '第二章'},
    );
    await tester.pumpWidget(_reader(notes: notes));
    await tester.pumpAndSettle();

    // 先真实切到第二章（让当前可见章 == 选区所在章），再真实长按正文。
    await _ensureChrome(tester);
    await tester.tap(find.text('下一章'));
    await tester.pumpAndSettle();

    // 真实长按第二章正文 → 浮动工具条
    final target = find.text(_ch2Text);
    expect(target, findsOneWidget);
    await tester.longPress(target);
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSelectionToolbar), findsOneWidget);

    // 点「高亮」→ 弹出 4 色 → 选蓝色
    await tester.tap(find.text('高亮'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-color-#1A73E8')), findsOneWidget);
    await tester.tap(find.byKey(const Key('note-color-#1A73E8')));
    await tester.pumpAndSettle();

    // 落库一条 highlight + 该色（fake 记录调用参数）
    expect(notes.store.length, 1);
    final created = notes.store.single;
    expect(created.kind, 'highlight');
    expect(created.color, '#1A73E8');
    expect(created.start, isNotNull, reason: '文本锚应解析出 UTF-16 区间');
    expect(tester.takeException(), isNull);

    // 打开笔记面板 → 断言条目（色标 + 片段）
    await _openNotesPanel(tester);
    expect(find.byType(NotesPanel), findsOneWidget);
    expect(find.byKey(Key('note-row-${created.id}')), findsOneWidget);
    expect(find.text(created.snippet!), findsOneWidget);

    // 点条目 → 跳回原文并出现临时高亮
    await tester.tap(find.byKey(Key('note-row-${created.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('temp-highlight')), findsOneWidget,
        reason: '跳转后应出现临时高亮');
    expect(find.byType(NotesPanel), findsNothing, reason: '跳转后面板关闭');
    expect(tester.takeException(), isNull);
  });

  testWidgets('US-22 真实搜索 → 结果 → 定位 → 临时高亮关键词', (tester) async {
    _setPhone(tester);
    const snippet = '卡尔维诺写道：城市是记忆的';
    final search = FakeSearchBackend(hits: const [
      SearchHitData(
        bookId: 'b1',
        bookTitle: '测试书',
        href: _href2,
        chapterTitle: '第二章',
        snippet: snippet,
        ranges: [TextRangeData(start: 7, end: 9)], // 「城市」
      ),
    ]);
    final notes = FakeNotesBackend(
      chapterTexts: const {_href1: _ch1Text, _href2: _ch2Text},
      chapterTitles: const {_href1: '第一章', _href2: '第二章'},
    );
    await tester.pumpWidget(_reader(notes: notes, search: search));
    await tester.pumpAndSettle();

    // 更多 → 搜索 → 真实 SearchPage
    await _ensureChrome(tester);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);

    // 输入关键词 → 全文搜索
    await tester.enterText(find.byKey(const Key('search-field')), '城市');
    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();

    // 结果行 + 关键词高亮（蓝色加粗）+ 统计
    expect(find.text('测试书'), findsWidgets);
    expect(find.textContaining('第 1 章 · 第二章'), findsOneWidget);
    expect(find.byKey(const Key('search-locate-0')), findsOneWidget);
    expect(find.byKey(const Key('search-stats')), findsOneWidget);
    expect(search.queries, contains('城市'));
    expect(tester.takeException(), isNull);

    // 点「定位」→ 回到 ReaderPage 并出现关键词临时高亮
    await tester.tap(find.byKey(const Key('search-locate-0')));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsNothing);
    expect(find.byKey(const Key('temp-highlight')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 让临时高亮超时消失，避免遗留定时器
    await tester.pump(const Duration(seconds: 4));
  });
}
