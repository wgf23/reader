import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/pages/reader_page.dart';
import 'package:reader_app/pages/settings_page.dart';
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

    // 工具条含 划重点/笔记/翻译/查词/复制（无"取消"——取消改为点正文空白处）
    expect(find.text('划重点'), findsOneWidget);
    expect(find.text('笔记'), findsOneWidget);
    expect(find.text('翻译'), findsOneWidget);
    expect(find.text('查词'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);

    // 点击翻译 → loading → 结果
    await tester.tap(find.text('翻译'));
    await tester.pump(); // loading 帧
    expect(find.text('翻译中…'), findsOneWidget);
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
      initialPagedMode: true,
    )));
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

  testWidgets('translateBackend 为 null 时工具条仍显示翻译/查词，点翻译提示未配置（REQ-004 加固）',
      (tester) async {
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
    // 翻译/查词无条件显示（避免用户看不到入口）
    expect(find.text('翻译'), findsOneWidget);
    expect(find.text('查词'), findsOneWidget);
    expect(find.text('划重点'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    // 点击翻译 → 提示未配置（而非静默）
    await tester.tap(find.text('翻译'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未配置翻译后端'), findsOneWidget);
  });

  // ---------- REQ-006：译文来源标签 + 回退提示（US-18） ----------

  testWidgets('US-18 译文卡片标签：在线/离线/缓存 + provider 名 + 回退提示', (tester) async {
    Future<void> pumpCard(TranslationData t) => tester.pumpWidget(
          wrap(Scaffold(body: TranslationResultCard(translation: t))),
        );

    await pumpCard(const TranslationData(
      text: 'Hello', from: 'en', to: 'zh', provider: 'deepl', fromCache: false));
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('deepl'), findsOneWidget);

    await pumpCard(const TranslationData(
      text: 'Hello', from: 'en', to: 'zh', provider: 'offline', fromCache: false));
    expect(find.text('离线'), findsOneWidget);
    expect(find.text('offline'), findsOneWidget);
    expect(find.text('在线'), findsNothing);

    await pumpCard(const TranslationData(
      text: 'Hello', from: 'en', to: 'zh', provider: 'deepl', fromCache: true));
    expect(find.text('缓存'), findsOneWidget);
    expect(find.text('deepl'), findsOneWidget);

    await pumpCard(const TranslationData(
      text: 'Hello',
      from: 'en',
      to: 'zh',
      provider: 'offline',
      fromCache: false,
      fallbackReason: '在线失败，已回退离线',
    ));
    expect(find.text('在线失败，已回退离线'), findsOneWidget);
  });

  testWidgets('US-17/18 翻译结果经 ReaderPage 渲染 provider 与回退提示', (tester) async {
    final translate = FakeTranslateBackend(
      translationProvider: 'offline',
      fallbackReason: '未配置在线翻译 API Key，已回退离线',
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
    await tester.tap(find.text('翻译'));
    await tester.pumpAndSettle();

    expect(find.byType(TranslationResultCard), findsOneWidget);
    expect(find.text('离线'), findsOneWidget);
    expect(find.text('offline'), findsOneWidget);
    expect(find.textContaining('未配置在线翻译 API Key'), findsOneWidget);
  });

  // ---------- REQ-007：翻译未配置引导（US-12）+ 来源标签（US-13） ----------

  testWidgets('US-12 无 key 翻译错误浮层：文案含"设置" + 去设置/重试，点击去设置进入设置页且透传同一 backend',
      (tester) async {
    final translate = FakeTranslateBackend(
      translateFailures: 1,
      translateError: '翻译服务未配置：未配置在线翻译 API Key（deepl），'
          '且离线翻译未命中（请先安装内置词库）；请在「设置」中配置在线翻译或导入词库',
      installedDicts: const [
        DictInfoData(id: 'd1', name: 'REQ007测试词库', wordCount: 1, path: '/tmp/d1.ifo'),
      ],
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
    await tester.tap(find.text('翻译'));
    await tester.pumpAndSettle();

    expect(find.byType(OverlayError), findsOneWidget);
    expect(find.textContaining('设置'), findsWidgets);
    expect(find.text('去设置'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    // 透传同一注入实例：SettingsPage 用该 fake 的 listDicts 渲染出专属词库名。
    expect(find.text('REQ007测试词库'), findsOneWidget,
        reason: '必须透传 ReaderPage 的同一 translateBackend，不得落到默认 Rust 后端');
  });

  testWidgets('US-12 查词失败不出现"去设置"（避免与词典引导串扰）', (tester) async {
    final translate = FakeTranslateBackend(
      lookupError: '未安装词库，请先在设置中导入',
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
    selectionArea.onSelectionChanged!(const SelectedContent(plainText: '很'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查词'));
    await tester.pumpAndSettle();

    expect(find.byType(OverlayError), findsOneWidget);
    expect(find.textContaining('未安装词库'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('去设置'), findsNothing);
  });

  testWidgets('US-13 在线链路：provider=deepl 且未缓存 → 卡片显示"在线"+"deepl"',
      (tester) async {
    final translate = FakeTranslateBackend(
      translationProvider: 'deepl',
      fromCache: false,
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
    await tester.tap(find.text('翻译'));
    await tester.pumpAndSettle();

    expect(find.byType(TranslationResultCard), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('deepl'), findsOneWidget);
  });
}
