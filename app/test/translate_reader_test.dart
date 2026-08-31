import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/pages/reader_page.dart';
import 'package:reader_app/services/translate_backend.dart';
import 'package:reader_app/widgets/translation_popup.dart';

import 'fake_backend.dart';
import 'fake_translate_backend.dart';

/// 分页模式的 fake 构建器：捕获 onSelectedText 回调供测试触发选中
class PagedSelectionCapture {
  ValueChanged<String>? onSelectedText;
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('US-15 滚动模式：选中文本 → 工具条出现 → 翻译浮层（loading→结果+缓存标记）',
      (tester) async {
    final translate = FakeTranslateBackend(fromCache: true, delay: const Duration(milliseconds: 200));
    await tester.pumpWidget(wrap(ReaderPage(
      bookId: 'b1',
      bookTitle: '测试书',
      backend: FakeBackend(),
      translateBackend: translate,
    )));
    await tester.pumpAndSettle();
    expect(find.text('很久以前，有一座山。'), findsOneWidget);

    // 触发 SelectionArea 选中（前 4 字符 "很久以前"）
    final selectionArea =
        tester.widget<SelectionArea>(find.byType(SelectionArea));
    selectionArea.onSelectionChanged!(const SelectedContent(plainText: '很久以前'));
    await tester.pumpAndSettle();

    // 工具条含"翻译/查词/取消"
    expect(find.text('翻译'), findsOneWidget);
    expect(find.text('查词'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    // 点击翻译 → loading → 结果
    await tester.tap(find.text('翻译'));
    await tester.pump(); // loading 帧
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(TranslationResultCard), findsOneWidget);
    expect(find.textContaining('译文:Hello world'), findsOneWidget);
    expect(find.text('缓存'), findsOneWidget, reason: 'fromCache=true 应显示缓存标记');
    expect(find.text('echo'), findsOneWidget);
    expect(translate.lastTranslatedText, '很久以前');
  });

  testWidgets('US-15 翻译失败显示错误文案与"重试"按钮，点击重试成功', (tester) async {
    final translate = FakeTranslateBackend(translateFailures: 1);
    await tester.pumpWidget(wrap(ReaderPage(
      bookId: 'b1',
      bookTitle: '测试书',
      backend: FakeBackend(),
      translateBackend: translate,
    )));
    await tester.pumpAndSettle();

    final selectionArea =
        tester.widget<SelectionArea>(find.byType(SelectionArea));
    selectionArea.onSelectionChanged!(const SelectedContent(plainText: '很久以前'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('翻译'));
    await tester.pumpAndSettle();

    // 错误态：文案 + 重试按钮
    expect(find.byType(OverlayError), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining('网络请求失败'), findsOneWidget);

    // 点击重试 → 成功（不丢原文：第二次仍以同一文本调用）
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.byType(TranslationResultCard), findsOneWidget);
    expect(translate.translateCalls, 2);
    expect(translate.lastTranslatedText, '很久以前');
  });

  testWidgets('US-16 查词卡片：词条/音标/词性/释义渲染', (tester) async {
    final translate = FakeTranslateBackend(
      lookupResult: const DictEntryData(
        word: 'apple',
        phonetic: '/ˈæp.əl/',
        pos: 'n.',
        definition: '苹果；苹果树',
        example: 'an apple a day',
      ),
    );
    await tester.pumpWidget(wrap(ReaderPage(
      bookId: 'b1',
      bookTitle: '测试书',
      backend: FakeBackend(),
      translateBackend: translate,
    )));
    await tester.pumpAndSettle();

    final selectionArea =
        tester.widget<SelectionArea>(find.byType(SelectionArea));
    selectionArea.onSelectionChanged!(const SelectedContent(plainText: '很久以前'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查词'));
    await tester.pumpAndSettle();

    expect(find.byType(DictResultCard), findsOneWidget);
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('n.'), findsOneWidget);
    expect(find.text('/ˈæp.əl/'), findsOneWidget);
    expect(find.textContaining('苹果'), findsOneWidget);
    expect(find.textContaining('例句'), findsOneWidget);
  });

  testWidgets('US-16 未收录显示"未找到"；无词库显示引导文案（US-2/US-3 映射）',
      (tester) async {
    // 未收录：lookup 返回 null
    final translate1 = FakeTranslateBackend(lookupResult: null);
    await tester.pumpWidget(wrap(ReaderPage(
      bookId: 'b1',
      bookTitle: '测试书',
      backend: FakeBackend(),
      translateBackend: translate1,
    )));
    await tester.pumpAndSettle();
    final sa1 = tester.widget<SelectionArea>(find.byType(SelectionArea));
    sa1.onSelectionChanged!(const SelectedContent(plainText: '很'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查词'));
    await tester.pumpAndSettle();
    expect(find.text('未找到该词'), findsOneWidget);

    // 无词库：lookup 抛"未安装词库"错误 → 引导文案
    final translate2 = FakeTranslateBackend(
      lookupError: '未安装词库，请先在设置中导入',
    );
    await tester.pumpWidget(wrap(ReaderPage(
      bookId: 'b1',
      bookTitle: '测试书',
      backend: FakeBackend(),
      translateBackend: translate2,
    )));
    await tester.pumpAndSettle();
    final sa2 = tester.widget<SelectionArea>(find.byType(SelectionArea));
    sa2.onSelectionChanged!(const SelectedContent(plainText: '很'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查词'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未安装词库'), findsOneWidget);
  });

  testWidgets('US-15 分页模式：选中回调产生 → 同一翻译入口可用', (tester) async {
    // fake 构建器捕获 onSelectedText，模拟 JS 选区回传
    final capture = PagedSelectionCapture();
    Widget fakeBuilder(
      BuildContext context, {
      required String bookId,
      required String href,
      required String html,
      required dynamic backend,
      required int fontSize,
      required ValueChanged<double> onProgress,
      ValueChanged<String>? onSelectedText,
    }) {
      capture.onSelectedText = onSelectedText;
      return const Center(child: Text('分页模式（fake WebView）'));
    }

    final translate = FakeTranslateBackend();
    await tester.pumpWidget(wrap(ReaderPage(
      bookId: 'b1',
      bookTitle: '测试书',
      backend: FakeBackend(),
      translateBackend: translate,
      pagedViewBuilder: fakeBuilder,
    )));
    await tester.pumpAndSettle();
    // 切分页模式
    await tester.tap(find.byIcon(Icons.auto_stories));
    await tester.pumpAndSettle();
    expect(find.text('分页模式（fake WebView）'), findsOneWidget);

    // 模拟 JS 选区回传 → 工具条出现 → 翻译可用
    capture.onSelectedText!('很久以前');
    await tester.pumpAndSettle();
    expect(find.text('翻译'), findsOneWidget);
    await tester.tap(find.text('翻译'));
    await tester.pumpAndSettle();
    expect(find.byType(TranslationResultCard), findsOneWidget);
  });

  testWidgets('translateBackend 为 null 时无翻译/查词入口（既有行为零回归）', (tester) async {
    await tester.pumpWidget(wrap(ReaderPage(
      bookId: 'b1',
      bookTitle: '测试书',
      backend: FakeBackend(),
    )));
    await tester.pumpAndSettle();
    final selectionArea =
        tester.widget<SelectionArea>(find.byType(SelectionArea));
    selectionArea.onSelectionChanged!(const SelectedContent(plainText: '很久以前'));
    await tester.pumpAndSettle();
    expect(find.text('翻译'), findsNothing);
    expect(find.text('查词'), findsNothing);
  });
}
