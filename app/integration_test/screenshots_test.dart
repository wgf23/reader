import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_app/pages/library_page.dart';
import 'package:reader_app/pages/listen_page.dart';
import 'package:reader_app/pages/reader_page.dart';
import 'package:reader_app/services/library_backend.dart';
import 'package:reader_app/services/tts_backend.dart';
import 'package:reader_app/widgets/display_settings_sheet.dart';
import 'package:reader_app/widgets/listen_settings_sheet.dart';
import 'package:reader_app/widgets/reader_chrome.dart';

import '../test/fake_backend.dart';
import '../test/fake_translate_backend.dart';
import '../test/fake_tts_backend.dart';
import '../test/fake_tts_engine.dart';

/// 长文本后端：让正文占满纵向，便于看工具条跟随选词。
class _LongFakeBackend extends FakeBackend {
  @override
  Future<BookViewData> openBook(String id) async => const BookViewData(
        id: 'b1',
        title: '测试书',
        chapters: [
          ChapterData(
            title: '第一章',
            text: 'The morning light filtered through the curtains.\n\n'
                'She opened the book and began to read. The words were interesting.\n\n'
                'A story about a small village by the sea. People lived simple lives.\n\n'
                'Every day the fisherman went out early. He knew the tides well.',
          ),
        ],
      );
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

  testWidgets('screenshot 阅读器·呼出顶底栏', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_pack(Scaffold(
      backgroundColor: Colors.white,
      body: Column(children: [
        ReaderTopBar(
          title: '测试书',
          chapter: '第一章 · 起风了',
          onBack: () {},
          onMore: () {},
        ),
        const Expanded(
          child: Center(
            child: Text('正文 · 沉浸态背景（呼出后 Chrome 浮层）'),
          ),
        ),
        ReaderBottomBar(
          chapterIndex: 0,
          chapterCount: 2,
          progress: 0.42,
          bookmarked: false,
          onPrevChapter: () {},
          onNextChapter: () {},
          onDirectory: () {},
          onBookmark: () {},
          onSettings: () {},
          onProgressChanged: (_) {},
          onProgressSeek: (_) {},
        ),
      ]),
    )));
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
    // 沉浸态默认无 Chrome：先点正文中部 1/3 呼出顶栏，再点「更多」。
    await tester.tapAt(const Offset(195, 422));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await _shot(tester, 'reader_more');
  });
}
