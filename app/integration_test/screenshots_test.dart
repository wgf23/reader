import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_app/pages/library_page.dart';
import 'package:reader_app/pages/listen_page.dart';
import 'package:reader_app/pages/reader_page.dart';
import 'package:reader_app/pages/search_page.dart';
import 'package:reader_app/pages/settings_page.dart';
import 'package:reader_app/services/library_backend.dart';
import 'package:reader_app/services/notes_backend.dart';
import 'package:reader_app/services/search_backend.dart';
import 'package:reader_app/services/translate_backend.dart';
import 'package:reader_app/services/tts_backend.dart';
import 'package:reader_app/widgets/display_settings_sheet.dart';
import 'package:reader_app/widgets/listen_settings_sheet.dart';
import 'package:reader_app/widgets/notes_panel.dart';
import 'package:reader_app/widgets/selection_toolbar.dart';
import 'package:reader_app/widgets/translation_popup.dart';

import '../test/fake_backend.dart';
import '../test/fake_notes_backend.dart';
import '../test/fake_search_backend.dart';
import '../test/fake_translate_backend.dart';
import '../test/fake_tts_backend.dart';
import '../test/fake_tts_engine.dart';

/// `_LongFakeBackend` 的正文文本（用于真实点击文字 center 呼出 Chrome）。
const String _readerText = 'The morning light filtered through the curtains.\n\n'
    'She opened the book and began to read. The words were interesting.\n\n'
    'A story about a small village by the sea. People lived simple lives.\n\n'
    'Every day the fisherman went out early. He knew the tides well.';

/// 长文本后端：让正文占满纵向，便于看工具条跟随选词。
class _LongFakeBackend extends FakeBackend {
  @override
  Future<BookViewData> openBook(String id) async => const BookViewData(
        id: 'b1',
        title: '测试书',
        chapters: [
          ChapterData(
            title: '第一章',
            text: _readerText,
          ),
        ],
      );
}

/// REQ-008：连续滚动截图语料（第一章足够长 → 第二章靠真实滚动进入视口）。
const String _continuousCh1 = '第一章的正文从这里开始。'
    '他沿着河岸慢慢走着，看水面上浮起的薄雾，听远处传来的钟声。'
    '这样的清晨他已经经历过无数次，可每一次都像第一次那样新鲜。'
    '他想起年轻时读过的那些书，想起书里写过的人和事，'
    '想起自己曾经以为永远不会忘记的名字，如今也只剩一个模糊的轮廓。'
    '河水向东流去，不曾回头，就像时间一样，把一切都带向远方。';

const String _continuousCh2Title = '第二章 · 起风了';
const String _continuousCh2 = '风从山谷里吹来，带着青草与泥土的气息。'
    '他站在窗前，望着远处起伏的山脊，忽然觉得，'
    '故事其实才刚刚开始。';

final String _continuousCh1Long = List<String>.generate(
  40,
  (i) => '第${i + 1}段：$_continuousCh1',
).join();

/// 两章长文本后端：第一章很长，真实滚动后才能看到第二章。
class _ContinuousScrollShotBackend extends FakeBackend {
  @override
  Future<BookViewData> openBook(String id) async => BookViewData(
        id: 'b1',
        title: '测试书',
        chapters: [
          ChapterData(title: '第一章', text: _continuousCh1Long),
          const ChapterData(title: _continuousCh2Title, text: _continuousCh2),
        ],
      );
}

/// 真实 drag 直到目标进入视口（REQ-008 连续滚动截图用）。
Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  final viewportHeight =
      tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (var i = 0; i < 200; i++) {
    if (finder.evaluate().isNotEmpty) {
      final dy = tester.getTopLeft(finder).dy;
      if (dy >= 0 && dy < viewportHeight) return;
    }
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pump();
  }
  fail('真实滚动未能使目标进入视口');
}

/// 听书页截图语料：与 [FakeTtsBackend] 句表一致，标题/文风贴合线框 09。
const Map<String, List<String>> _listenSentences = {
  'chapter_0001.xhtml': [
    '风从山谷里吹来，带着青草与泥土的气息。',
    '他站在窗前，望着远处起伏的山脊。',
    '那一刻，他忽然想起许多年前的那个清晨。',
    '于是故事就这样开始了。',
  ],
  'chapter_0002.xhtml': ['第四章句一。', '第四章句二。'],
};

/// 与 [_listenSentences] 文本一致的听书后端（复用 [FakeBackend]，只改章节文本/标题）。
class _ListenShotBackend extends FakeBackend {
  @override
  Future<BookViewData> openBook(String id) async => const BookViewData(
        id: 'b1',
        title: '测试书',
        chapters: [
          ChapterData(
            title: '第三章 · 起风了',
            text: '风从山谷里吹来，带着青草与泥土的气息。'
                '他站在窗前，望着远处起伏的山脊。'
                '那一刻，他忽然想起许多年前的那个清晨。'
                '于是故事就这样开始了。',
          ),
          ChapterData(title: '第四章', text: '第四章句一。第四章句二。'),
        ],
      );
}

/// REQ-006 · S1 自动滚动语料：30 句（每句约 24 字），确保正文远超一屏，
/// 靠后的句必须靠自动滚动才能进入 390×844 视口。
final List<String> _longListenSentenceList = List<String>.generate(
  30,
  (i) => '这是第${i + 1}句，用来验证听书跟读时当前句会自动滚动进视口。',
);

final Map<String, List<String>> _longListenSentences = {
  'chapter_0001.xhtml': _longListenSentenceList,
  'chapter_0002.xhtml': const ['第四章句一。', '第四章句二。'],
};

/// 与 [_longListenSentences] 文本一致的听书后端（长章节，触发滚动）。
class _LongListenShotBackend extends FakeBackend {
  @override
  Future<BookViewData> openBook(String id) async => BookViewData(
        id: 'b1',
        title: '测试书',
        chapters: [
          ChapterData(
            title: '第三章 · 起风了',
            text: _longListenSentences['chapter_0001.xhtml']!.join(),
          ),
          const ChapterData(title: '第四章', text: '第四章句一。第四章句二。'),
        ],
      );
}

/// REQ-009：笔记/搜索截图语料（两章，带 href，供真实 ReaderPage 选词/面板/跳转）。
const String _req009Ch1 = '第一章的正文从这里开始。'
    '他沿着河岸慢慢走着，看水面上浮起的薄雾，听远处传来的钟声。'
    '这样的清晨他已经经历过无数次，可每一次都像第一次那样新鲜。';
const String _req009Ch2 = '看不见的城市，卡尔维诺写道：城市是记忆的。'
    '他还说，每一座城市都会把它的记忆藏在街巷的转角里。';
const String _req009Href1 = 'chapter_0001.xhtml';
const String _req009Href2 = 'chapter_0002.xhtml';

class _NotesSearchShotBackend extends FakeBackend {
  @override
  Future<BookViewData> openBook(String id) async => const BookViewData(
        id: 'b1',
        title: '测试书',
        chapters: [
          ChapterData(title: '第一章', text: _req009Ch1, href: _req009Href1),
          ChapterData(title: '第二章', text: _req009Ch2, href: _req009Href2),
        ],
      );
}

AnnotationData _shotNote(
  String id, {
  String kind = 'highlight',
  String? color = '#FBC02D',
  String? snippet,
  String? noteText,
  String href = _req009Href1,
  double progression = 0.1,
  int? start,
  int? end,
  required int updatedAt,
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
      createdAt: updatedAt,
      updatedAt: updatedAt,
      syncStatus: 'local',
    );

/// 预置 6 条笔记（两章 + 书签），用于真实笔记面板截图（线框 07）。
FakeNotesBackend _notesShotBackend() {
  final b = FakeNotesBackend(
    chapterTitles: const {
      _req009Href1: '第一章',
      _req009Href2: '第二章',
    },
  );
  b.store.addAll([
    _shotNote('n1',
        snippet: '多年以后，面对行刑队，奥雷里亚诺…',
        noteText: '布恩迪亚家族命运的伏笔',
        updatedAt: 1700300000),
    _shotNote('n2',
        color: '#1A73E8',
        snippet: '冰块在箱中散发寒气的那个下午…',
        noteText: '童年记忆与孤独的意象',
        updatedAt: 1700200000),
    _shotNote('n3',
        snippet: '他想着吉卜赛人的磁铁，觉得世界…',
        noteText: '魔幻现实主义的引入',
        updatedAt: 1700100000),
    _shotNote('n4',
        color: '#1A73E8',
        href: _req009Href2,
        progression: 0.5,
        snippet: '城市是记忆的',
        noteText: '上校形象的铺垫',
        start: 14,
        end: 20,
        updatedAt: 1700000000),
    _shotNote('n5',
        href: _req009Href2,
        progression: 0.6,
        snippet: '阿玛兰塔·乌苏拉回到马孔多…',
        noteText: '结局的预示',
        updatedAt: 1699900000),
    _shotNote('n6',
        kind: 'bookmark',
        color: null,
        href: _req009Href2,
        progression: 0.0,
        snippet: '书签：第二章开头',
        updatedAt: 1699800000),
  ]);
  return b;
}

/// 用 RepaintBoundary.toImage 把真实引擎渲染转成 PNG（桌面集成测试不支持 takeScreenshot）。
Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final boundary = tester
      .renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  final image = await boundary.toImage(pixelRatio: 3.0);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('screenshots/$name.png');
  await file.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('SAVED_SCREENSHOT $name -> ${file.path} (${bytes.lengthInBytes} bytes)');
}

void _setPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Widget _pack(Widget child) => RepaintBoundary(
      child: MaterialApp(debugShowCheckedModeBanner: false, home: child),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget reader() => _pack(ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _LongFakeBackend(),
        translateBackend: FakeTranslateBackend(),
      ));

  testWidgets('screenshot 库页', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_pack(LibraryPage(backend: FakeBackend())));
    await _shot(tester, 'library');
  });

  testWidgets('screenshot 阅读器·沉浸态', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(reader());
    await _shot(tester, 'reader_immersive');
  });

  testWidgets('screenshot 阅读器·连续滚动到第二章（REQ-008）', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_pack(ReaderPage(
      bookId: 'b1',
      bookTitle: '测试书',
      backend: _ContinuousScrollShotBackend(),
    )));
    await tester.pumpAndSettle();
    // 真实 drag 滚到第二章（无需点"下一章"），第二章标题进入视口后截图。
    await _scrollUntilVisible(tester, find.text(_continuousCh2Title));
    await _shot(tester, 'reader_continuous_scroll_chapter2');
  });

  testWidgets('screenshot 阅读器·呼出顶底栏（真实点击正文文字）', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(reader());
    await tester.pumpAndSettle();
    // 真实点击正文文字 center 呼出 Chrome（禁止合成页，US-3）。
    await tester.tapAt(tester.getCenter(find.text(_readerText)));
    await _shot(tester, 'reader_chrome');
  });

  testWidgets('screenshot 阅读器·长按选词工具条', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(reader());
    await tester.pumpAndSettle();
    await tester.longPressAt(const Offset(200, 300));
    await _shot(tester, 'reader_selected');
  });

  testWidgets('screenshot Aa 显示设置面板', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_pack(Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ReaderSettingsSheet(
            settings: const (
              fontSize: 18,
              fontFamily: '系统默认',
              theme: '浅色',
              lineHeight: '标准',
              pagedMode: false,
            ),
            onChanged: (_) {},
          ),
        ),
      ),
    )));
    await _shot(tester, 'aa_panel');
  });

  testWidgets('screenshot 听书·跟读控制条（线框 09）', (tester) async {
    _setPhone(tester);
    final engine = FakeTtsEngine();
    addTearDown(engine.dispose);
    await tester.pumpWidget(_pack(ListenPage(
      bookId: 'b1',
      bookTitle: '测试书',
      href: 'chapter_0001.xhtml',
      progression: 0.0,
      backend: _ListenShotBackend(),
      ttsBackend: FakeTtsBackend(sentences: _listenSentences),
      ttsEngine: engine,
    )));
    await _shot(tester, 'listen_player');
  });

  testWidgets('screenshot 听书设置面板（线框 10）', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_pack(Scaffold(
      body: ListenSettingsSheet(
        settings: const ListenSettingsData(
          voiceId: 'system_male',
          speed: 1.0,
          autoNext: true,
        ),
        onSettingsChanged: (_) {},
        onClose: () {},
      ),
    )));
    await _shot(tester, 'listen_settings');
  });

  testWidgets('screenshot 阅读器·更多菜单（听书入口）', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(reader());
    await tester.pumpAndSettle();
    // 沉浸态默认无 Chrome：先真实点击正文文字 center 呼出顶栏，再点「更多」。
    await tester.tapAt(tester.getCenter(find.text(_readerText)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await _shot(tester, 'reader_more');
  });

  // ==================== REQ-006 新增 UI（S1/S2/S3/S4） ====================

  testWidgets('screenshot 听书·当前句自动滚动进视口（REQ-006 S1）', (tester) async {
    _setPhone(tester);
    final engine = FakeTtsEngine();
    addTearDown(engine.dispose);
    await tester.pumpWidget(_pack(ListenPage(
      bookId: 'b1',
      bookTitle: '测试书',
      href: 'chapter_0001.xhtml',
      progression: 0.0,
      backend: _LongListenShotBackend(),
      ttsBackend: FakeTtsBackend(sentences: _longListenSentences),
      ttsEngine: engine,
    )));
    await tester.pumpAndSettle();
    // 初始为第 0 句（offset=0）；模拟平台 onStart 推进到靠后的第 21 句，
    // 断言 ScrollController 偏移 > 0（自动滚动代理），再截图为证。
    engine.emitStarted(20);
    await tester.pumpAndSettle();
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.pixels, greaterThan(0.0),
        reason: '当前句变化后应自动滚动进视口（offset > 0）');
    await _shot(tester, 'listen_follow_scroll');
  });

  testWidgets('screenshot 听书设置·系统默认音色提示（REQ-006 S2）', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_pack(Scaffold(
      body: ListenSettingsSheet(
        settings: const ListenSettingsData(
          voiceId: 'system_male',
          speed: 1.0,
          autoNext: true,
        ),
        voiceFallback: true,
        onSettingsChanged: (_) {},
        onClose: () {},
      ),
    )));
    await _shot(tester, 'listen_settings_fallback');
  });

  testWidgets('screenshot 翻译译文卡片来源标签（REQ-006 S3）', (tester) async {
    _setPhone(tester);
    TranslationData card({
      required String provider,
      required bool fromCache,
      String? fallbackReason,
    }) =>
        TranslationData(
          text: '多年以后，面对行刑队，奥雷里亚诺·布恩迪亚上校将会回想起'
              '父亲带他去看冰块的那个下午。',
          from: 'auto',
          to: 'zh',
          provider: provider,
          fromCache: fromCache,
          fallbackReason: fallbackReason,
        );
    await tester.pumpWidget(_pack(Scaffold(
      backgroundColor: Colors.white,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 在线（provider=deepl，未缓存）
          TranslationResultCard(
            translation: card(provider: 'deepl', fromCache: false),
          ),
          // 离线（provider=offline）
          TranslationResultCard(
            translation: card(provider: 'offline', fromCache: false),
          ),
          // 缓存（fromCache=true，provider=deepl）
          TranslationResultCard(
            translation: card(provider: 'deepl', fromCache: true),
          ),
          // 回退提示（在线失败，已回退离线）
          TranslationResultCard(
            translation: card(
              provider: 'offline',
              fromCache: false,
              fallbackReason: '在线失败，已回退离线',
            ),
          ),
        ],
      ),
    )));
    await _shot(tester, 'translation_cards');
  });

  testWidgets('screenshot 设置页·翻译策略与掩码 key（REQ-006 S4）', (tester) async {
    _setPhone(tester);
    final backend = FakeTranslateBackend(
      configProvider: 'auto',
      hasDeeplKey: true,
      deeplKeyMasked: '••••••••',
    );
    await tester.pumpWidget(_pack(SettingsPage(translateBackend: backend)));
    await tester.pumpAndSettle();
    expect(find.text('翻译策略'), findsOneWidget);
    expect(find.text('自动（在线优先）'), findsOneWidget);
    await _shot(tester, 'settings_translate');
  });

  // ==================== REQ-009 新增 UI（S1/S2/S3/S4） ====================

  testWidgets('screenshot 选词工具条·四色高亮（REQ-009 S1）', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_pack(ReaderPage(
      bookId: 'b1',
      bookTitle: '测试书',
      backend: _LongFakeBackend(),
      notesBackend: _notesShotBackend(),
    )));
    await tester.pumpAndSettle();
    // 真实长按选词 → 浮动工具条；点「高亮」展开 4 色选色（线框 06）。
    await tester.longPressAt(const Offset(200, 300));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSelectionToolbar), findsOneWidget);
    await tester.tap(find.text('高亮'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-color-#1A73E8')), findsOneWidget);
    await _shot(tester, 'selection_toolbar_colors');
  });

  testWidgets('screenshot 笔记面板·章节分组（REQ-009 S2）', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_pack(ReaderPage(
      bookId: 'b1',
      bookTitle: '测试书',
      backend: _NotesSearchShotBackend(),
      notesBackend: _notesShotBackend(),
    )));
    await tester.pumpAndSettle();
    // 沉浸态默认无 Chrome：真实点击正文 center 呼出顶栏 → 更多 → 笔记。
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width / 2, size.height / 2));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesPanel), findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(NotesPanel), matching: find.text('第一章')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: find.byType(NotesPanel), matching: find.text('第二章')),
      findsOneWidget,
    );
    await _shot(tester, 'notes_panel');
  });

  testWidgets('screenshot 全文搜索·结果与筛选（REQ-009 S3）', (tester) async {
    _setPhone(tester);
    const snippet1 = '……在《看不见的城市》里，卡尔维诺写道：城市是记忆的……';
    const snippet2 = '……一家人的故事里，卡尔维诺始终关注日常的……';
    const snippet3 = '……柯希莫在树上度过一生，卡尔维诺借此探讨自由……';
    final search = FakeSearchBackend(hits: const [
      SearchHitData(
        bookId: 'b1',
        bookTitle: '看不见的城市',
        href: _req009Href1,
        chapterTitle: '城市与记忆',
        snippet: snippet1,
        ranges: [TextRangeData(start: 13, end: 17)],
      ),
      SearchHitData(
        bookId: 'b2',
        bookTitle: '马可瓦尔多',
        href: _req009Href1,
        chapterTitle: '城市与符号',
        snippet: snippet2,
        ranges: [TextRangeData(start: 10, end: 14)],
      ),
      SearchHitData(
        bookId: 'b3',
        bookTitle: '树上的男爵',
        href: _req009Href1,
        chapterTitle: '城市与贸易',
        snippet: snippet3,
        ranges: [TextRangeData(start: 13, end: 17)],
      ),
    ]);
    await tester.pumpWidget(_pack(SearchPage(
      searchBackend: search,
      initialBookId: 'b1',
      initialBookTitle: '看不见的城市',
    )));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), '卡尔维诺');
    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-stats')), findsOneWidget);
    expect(find.byKey(const Key('search-locate-0')), findsOneWidget);
    await _shot(tester, 'search_page');
  });

  testWidgets('screenshot 笔记跳回原文·临时高亮（REQ-009 S4）', (tester) async {
    _setPhone(tester);
    final notes = _notesShotBackend();
    await tester.pumpWidget(_pack(ReaderPage(
      bookId: 'b1',
      bookTitle: '测试书',
      backend: _NotesSearchShotBackend(),
      notesBackend: notes,
    )));
    await tester.pumpAndSettle();
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width / 2, size.height / 2));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();
    // 点第二章笔记条目 → 面板关闭 + 跳回原文 + 临时高亮（线框 07）。
    await tester.tap(find.byKey(const Key('note-row-n4')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('temp-highlight')), findsOneWidget);
    await _shot(tester, 'notes_jump_temp_highlight');
    // 让临时高亮超时清除，避免遗留定时器。
    await tester.pump(const Duration(seconds: 4));
  });
}
