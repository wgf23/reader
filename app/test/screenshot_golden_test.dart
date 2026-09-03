import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/pages/library_page.dart';
import 'package:reader_app/pages/reader_page.dart';
import 'package:reader_app/services/library_backend.dart';
import 'package:reader_app/widgets/display_settings_sheet.dart';

import 'fake_backend.dart';
import 'fake_translate_backend.dart';

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
                'Every day the fisherman went out early. He knew the tides well.\n\n'
                'The children played on the shore, laughing in the warm sun.',
          ),
        ],
      );
}

void _setPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('golden 库页', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(MaterialApp(home: LibraryPage(backend: FakeBackend())));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/library.png'));
  });

  testWidgets('golden 阅读器沉浸态', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _LongFakeBackend(),
        translateBackend: FakeTranslateBackend(),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/reader_immersive.png'));
  });

  testWidgets('golden 阅读器长按选中 → 工具条', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _LongFakeBackend(),
        translateBackend: FakeTranslateBackend(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.longPressAt(const Offset(200, 300));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/reader_selected.png'));
  });

  testWidgets('golden 阅读器呼出顶底栏', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: _LongFakeBackend(),
        translateBackend: FakeTranslateBackend(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195, 422));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/reader_chrome.png'));
  });

  testWidgets('golden Aa 设置面板', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            child: ReaderSettingsSheet(
              settings: (fontSize: 18, fontFamily: '系统默认', theme: '浅色', lineHeight: '标准', pagedMode: false),
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/aa_panel.png'));
  });
}
