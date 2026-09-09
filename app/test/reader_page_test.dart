import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/pages/listen_page.dart';
import 'package:reader_app/pages/reader_page.dart';
import 'package:reader_app/services/library_backend.dart';
import 'package:reader_app/widgets/directory_drawer.dart';
import 'package:reader_app/widgets/display_settings_sheet.dart';
import 'package:reader_app/widgets/reader_chrome.dart';
import 'package:reader_app/widgets/selection_toolbar.dart';

import 'fake_backend.dart';
import 'fake_notes_backend.dart';
import 'fake_paged_view_controls.dart';
import 'fake_translate_backend.dart';
import 'fake_tts_backend.dart';
import 'fake_tts_engine.dart';

/// 听书测试用句表（与 [_LongTextBackend] 两章文本语义一致，按 href 取句）
const _listenSentences = {
  'chapter_0001.xhtml': ['很久以前，有一座山。'],
  'chapter_0002.xhtml': ['故事结束了。'],
};

/// 长正文（REQ-007）：文字铺满屏幕中部，使 `find.text(_ch1)` 的 center 落在
/// 中部 1/3 命中区（既有 `_center=Offset(400,300)` 空白点属 R1-2 假阳性，已废弃）。
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

/// 分页模式 fake 构建器（不实例化真实 WebView）
Widget fakePagedBuilder(
  BuildContext context, {
  required String bookId,
  required String href,
  required String html,
  required dynamic backend,
  required int fontSize,
  required ValueChanged<double> onProgress,
  ValueChanged<String>? onSelectedText,
}) {
  return const Center(child: Text('分页模式（fake WebView）'));
}

/// 两章长文本后端（滚动模式）。
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

/// 真实点击正文文字 center 呼出/隐藏 Chrome（滚动模式）。
Future<void> _toggleChrome(WidgetTester tester) async {
  await tester.tapAt(tester.getCenter(find.text(_ch1)));
  await tester.pump();
}

void main() {
  testWidgets('沉浸态进入 + 点击正文文字呼出顶底栏 + 底栏下一章', (tester) async {
    final backend = _LongTextBackend();
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(bookId: 'b1', bookTitle: '测试书', backend: backend),
    ));
    await tester.pumpAndSettle();

    // 沉浸态：正文可见，但无顶栏（无"返回书架"）
    expect(find.text('第一章'), findsOneWidget);
    expect(find.text(_ch1), findsOneWidget);
    expect(find.text('返回书架'), findsNothing); // 沉浸态顶栏未渲染

    // 点击正文文字 center → 呼出顶栏 + 底栏
    await _toggleChrome(tester);
    expect(find.byTooltip('返回书架'), findsOneWidget);
    expect(find.text('下一章'), findsOneWidget);
    expect(find.byType(ReaderBottomBar), findsOneWidget);

    // 底栏"下一章" → 第二章
    await tester.tap(find.text('下一章'));
    await tester.pumpAndSettle();
    expect(find.text(_ch2), findsOneWidget);
  });

  testWidgets('点击正文文字再次隐藏 chrome', (tester) async {
    final backend = _LongTextBackend();
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(bookId: 'b1', bookTitle: '测试书', backend: backend),
    ));
    await tester.pumpAndSettle();
    await _toggleChrome(tester);
    expect(find.byTooltip('返回书架'), findsOneWidget);
    await _toggleChrome(tester);
    expect(find.text('返回书架'), findsNothing); // 再次点击中部隐藏
  });

  testWidgets('翻章后保存进度，重开恢复到该章', (tester) async {
    final backend = _LongTextBackend();
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(bookId: 'b1', bookTitle: '测试书', backend: backend),
    ));
    await tester.pumpAndSettle();
    expect(find.text(_ch1), findsOneWidget);

    await _toggleChrome(tester);
    await tester.tap(find.text('下一章'));
    await tester.pumpAndSettle();
    expect(find.text(_ch2), findsOneWidget);
    expect(backend.saved?.href, 'chapter_0002.xhtml');

    // 重开恢复到第二章
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(bookId: 'b1', bookTitle: '测试书', backend: backend),
    ));
    await tester.pumpAndSettle();
    expect(find.text(_ch2), findsOneWidget);
  });

  testWidgets('Aa 面板：弹出且可切换分页模式（不再有右上角按钮）', (tester) async {
    final backend = _LongTextBackend();
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: backend,
        pagedViewBuilder: fakePagedBuilder,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(_ch1), findsOneWidget);

    // 无右上角模式切换按钮（Icons.auto_stories/article_outlined）
    expect(find.byIcon(Icons.auto_stories), findsNothing);
    expect(find.byIcon(Icons.article_outlined), findsNothing);

    await _toggleChrome(tester);
    expect(find.text('Aa'), findsWidgets);
  });

  testWidgets('ReaderSettingsSheet 组件：显示设置可切换（字号/主题/模式）', (tester) async {
    ReaderSettings? emitted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReaderSettingsSheet(
            settings: (fontSize: 18, fontFamily: '系统默认', theme: '浅色', lineHeight: '标准', pagedMode: false),
            onChanged: (s) => emitted = s,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('显示设置'), findsOneWidget);
    expect(find.text('字号'), findsOneWidget);
    expect(find.text('翻页'), findsOneWidget);

    await tester.tap(find.text('深色'));
    await tester.pump();
    expect(emitted?.theme, '深色');

    await tester.tap(find.text('分页模式'));
    await tester.pump();
    expect(emitted?.pagedMode, true);
  });

  testWidgets('分页模式渲染（initialPagedMode）', (tester) async {
    final backend = FakeBackend();
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: backend,
        pagedViewBuilder: fakePagedBuilder,
        initialPagedMode: true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('分页模式（fake WebView）'), findsOneWidget);
  });

  testWidgets('底部进度条拖动触发 saveProgress', (tester) async {
    final backend = _LongTextBackend();
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(bookId: 'b1', bookTitle: '测试书', backend: backend),
    ));
    await tester.pumpAndSettle();
    await _toggleChrome(tester);

    final slider = find.byType(Slider);
    expect(slider, findsOneWidget);
    await tester.drag(slider, const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(backend.saved, isNotNull);
  });

  testWidgets('⋯更多弹层：听书可跳转 ListenPage，其余三项仍占位（US-1/US-25）',
      (tester) async {
    final engine = FakeTtsEngine();
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _LongTextBackend(),
        ttsBackend: FakeTtsBackend(sentences: _listenSentences),
        ttsEngine: engine,
      ),
    ));
    await tester.pumpAndSettle();
    await _toggleChrome(tester);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('阅读统计'), findsOneWidget);
    expect(find.text('听书'), findsOneWidget);
    expect(find.text('笔记'), findsOneWidget);
    expect(find.text('导出'), findsOneWidget);

    await tester.tap(find.text('听书'));
    await tester.pumpAndSettle();
    expect(find.byType(ListenPage), findsOneWidget, reason: '听书项必须真正 push 听书页');
    expect(find.text('导出'), findsNothing, reason: '底部弹层应先关闭');
    expect(engine.spokenIndexes, isNotEmpty, reason: '进入后应从当前句起播');
  });

  testWidgets('听书返回后阅读页重读进度（US-15）', (tester) async {
    final backend = _LongTextBackend();
    final engine = FakeTtsEngine();
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: backend,
        ttsBackend: FakeTtsBackend(sentences: _listenSentences),
        ttsEngine: engine,
      ),
    ));
    await tester.pumpAndSettle();
    await _toggleChrome(tester);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('听书'));
    await tester.pumpAndSettle();
    expect(find.byType(ListenPage), findsOneWidget);

    // 模拟听书写入第二章进度
    backend.saved = const ProgressData(
      href: 'chapter_0002.xhtml',
      progression: 0.0,
    );
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.text(_ch2), findsOneWidget, reason: '返回后应重读进度并跳到第二章');
  });

  testWidgets('US-22 选中工具条"复制"写入系统剪贴板', (tester) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map;
          clipboardText = args['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(bookId: 'b1', bookTitle: '测试书', backend: FakeBackend()),
    ));
    await tester.pumpAndSettle();
    final sa = tester.widget<SelectionArea>(find.byType(SelectionArea));
    sa.onSelectionChanged!(const SelectedContent(plainText: '很久以前'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(clipboardText, '很久以前');
  });

  testWidgets('目录抽屉：打开列出章节 → 选另一章跳转 + saveProgress', (tester) async {
    final backend = _LongTextBackend();
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(bookId: 'b1', bookTitle: '测试书', backend: backend),
    ));
    await tester.pumpAndSettle();
    await _toggleChrome(tester);
    await tester.tap(find.byTooltip('目录'));
    await tester.pumpAndSettle();
    // 抽屉列出章节（条目带序号前缀）
    expect(find.text('1. 第一章'), findsOneWidget);
    expect(find.text('2. 第二章'), findsOneWidget);
    // 选第二章 → 跳转 + 保存 href 更新
    await tester.tap(find.text('2. 第二章'));
    await tester.pumpAndSettle();
    expect(find.text(_ch2), findsOneWidget);
    expect(backend.saved?.href, 'chapter_0002.xhtml');
  });

  testWidgets('书签图标切换（幂等）', (tester) async {
    final notes = FakeNotesBackend(
      chapterTexts: const {'chapter_0001.xhtml': _ch1},
      chapterTitles: const {'chapter_0001.xhtml': '第一章'},
    );
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _LongTextBackend(),
        notesBackend: notes,
      ),
    ));
    await tester.pumpAndSettle();
    await _toggleChrome(tester);
    expect(find.byTooltip('加书签'), findsOneWidget);
    await tester.tap(find.byTooltip('加书签'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('取消书签'), findsOneWidget);
    expect(notes.store.where((a) => a.kind == 'bookmark').length, 1);
    await tester.tap(find.byTooltip('取消书签'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('加书签'), findsOneWidget);
    expect(notes.store.where((a) => a.kind == 'bookmark'), isEmpty);
  });

  testWidgets('选中工具条：复制/高亮(选色)/划线/批注 入口可用', (tester) async {
    final notes = FakeNotesBackend(
      chapterTexts: const {'chapter_0001.xhtml': '很久以前，有一座山。'},
      chapterTitles: const {'chapter_0001.xhtml': '第一章'},
    );
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: FakeBackend(),
        notesBackend: notes,
      ),
    ));
    await tester.pumpAndSettle();
    final sa = tester.widget<SelectionArea>(find.byType(SelectionArea));
    sa.onSelectionChanged!(const SelectedContent(plainText: '很久以前'));
    await tester.pumpAndSettle();
    for (final label in ['复制', '高亮', '划线', '批注', '翻译', '查词']) {
      expect(find.text(label), findsOneWidget, reason: '工具条应含 $label');
    }
    // 点高亮 → 弹出 4 色 → 选绿色 → 落库 kind=highlight + 该色
    await tester.tap(find.text('高亮'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-color-#FBC02D')), findsOneWidget);
    expect(find.byKey(const Key('note-color-#1A73E8')), findsOneWidget);
    expect(find.byKey(const Key('note-color-#43A047')), findsOneWidget);
    expect(find.byKey(const Key('note-color-#E91E63')), findsOneWidget);
    await tester.tap(find.byKey(const Key('note-color-#43A047')));
    await tester.pumpAndSettle();
    expect(
      notes.createCalls.any((c) => c.startsWith('highlight:#43A047:')),
      isTrue,
    );
  });

  testWidgets('US-2 分页模式：左右边缘点击翻页且不 toggle Chrome（注入 fake controls）',
      (tester) async {
    final controls = FakePagedViewControls(nextResult: true, prevResult: true);
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: FakeBackend(),
        pagedViewBuilder: fakePagedBuilder,
        initialPagedMode: true,
        pagedControls: controls,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('分页模式（fake WebView）'), findsOneWidget);

    await tester.tapAt(const Offset(50, 300)); // 左边缘 <0.15w
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(750, 300)); // 右边缘 >0.85w
    await tester.pumpAndSettle();

    expect(controls.prevCalls, 1);
    expect(controls.nextCalls, 1);
    expect(find.byTooltip('返回书架'), findsNothing, reason: '边缘翻页不得 toggle Chrome');
  });

  testWidgets('US-2 长按正文不触发 Chrome toggle', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _LongTextBackend(),
        translateBackend: FakeTranslateBackend(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.longPress(find.text(_ch1));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSelectionToolbar), findsOneWidget);
    expect(find.byTooltip('返回书架'), findsNothing, reason: '长按选中不得误触 Chrome');
  });

  testWidgets('US-5 分页模式：底栏下一章 → fake 构建器收到新 href + 保存章首进度',
      (tester) async {
    final backend = FakeBackend();
    final hrefs = <String>[];
    Widget builder(
      BuildContext context, {
      required String bookId,
      required String href,
      required String html,
      required dynamic backend,
      required int fontSize,
      required ValueChanged<double> onProgress,
      ValueChanged<String>? onSelectedText,
    }) {
      hrefs.add(href);
      return Center(child: Text(href == 'chapter_0002.xhtml' ? '第二章分页' : '第一章分页'));
    }

    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: backend,
        pagedViewBuilder: builder,
        initialPagedMode: true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('第一章分页'), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.text('第一章分页')));
    await tester.pump();
    await tester.tap(find.text('下一章'));
    await tester.pumpAndSettle();

    expect(hrefs.last, 'chapter_0002.xhtml');
    expect(find.text('第二章分页'), findsOneWidget);
    expect(backend.saved?.href, 'chapter_0002.xhtml');
    expect(backend.saved?.progression, 0.0);
  });

  testWidgets('US-9 分页切章后 fontSize 仍按当前 Aa 传入且选中回调仍接线', (tester) async {
    final backend = FakeBackend();
    final fontSizes = <int>[];
    ValueChanged<String>? selectedCallback;
    Widget builder(
      BuildContext context, {
      required String bookId,
      required String href,
      required String html,
      required dynamic backend,
      required int fontSize,
      required ValueChanged<double> onProgress,
      ValueChanged<String>? onSelectedText,
    }) {
      fontSizes.add(fontSize);
      selectedCallback = onSelectedText;
      return Center(child: Text(href == 'chapter_0002.xhtml' ? '第二章分页' : '第一章分页'));
    }

    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: backend,
        pagedViewBuilder: builder,
        initialPagedMode: true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(fontSizes.last, 18, reason: '默认 Aa 字号');
    expect(selectedCallback, isNotNull, reason: 'onSelectedText 必须仍接线');

    await tester.tapAt(tester.getCenter(find.text('第一章分页')));
    await tester.pump();
    await tester.tap(find.text('下一章'));
    await tester.pumpAndSettle();

    expect(find.text('第二章分页'), findsOneWidget);
    expect(fontSizes.last, 18, reason: '切章后仍按当前 Aa 字号');
    expect(selectedCallback, isNotNull, reason: '切章后选中回调仍接线');
  });

  testWidgets('ReaderDirectoryDrawer 组件：列出章节 + 当前高亮 + 选择回调', (tester) async {
    int? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderDirectoryDrawer(
          chapters: const ['第一章', '第二章', '第三章'],
          currentIndex: 1,
          onSelect: (i) => selected = i,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1. 第一章'), findsOneWidget);
    expect(find.text('2. 第二章'), findsOneWidget);
    expect(find.text('3. 第三章'), findsOneWidget);
    await tester.tap(find.text('3. 第三章'));
    await tester.pump();
    expect(selected, 2);
  });
}
