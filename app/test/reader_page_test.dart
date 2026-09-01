import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/pages/reader_page.dart';
import 'package:reader_app/widgets/display_settings_sheet.dart';
import 'package:reader_app/widgets/reader_chrome.dart';

import 'fake_backend.dart';

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

const _center = Offset(400, 300); // 沉浸态下"正文中部"（呼出/隐藏）

Future<void> _toggleChrome(WidgetTester tester) async {
  await tester.tapAt(_center);
  await tester.pump();
}

void main() {
  testWidgets('沉浸态进入 + 点击中部呼出顶底栏 + 底栏下一章', (tester) async {
    final backend = FakeBackend();
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(bookId: 'b1', bookTitle: '测试书', backend: backend),
    ));
    await tester.pumpAndSettle();

    // 沉浸态：正文可见，但无顶栏（无"返回书架"）
    expect(find.text('第一章'), findsOneWidget);
    expect(find.text('很久以前，有一座山。'), findsOneWidget);
    expect(find.text('返回书架'), findsNothing); // 沉浸态顶栏未渲染

    // 点击中部 → 呼出顶栏 + 底栏
    await _toggleChrome(tester);
    expect(find.byTooltip('返回书架'), findsOneWidget);
    expect(find.text('下一章'), findsOneWidget);
    expect(find.byType(ReaderBottomBar), findsOneWidget);

    // 底栏"下一章" → 第二章
    await tester.tap(find.text('下一章'));
    await tester.pumpAndSettle();
    expect(find.text('故事结束了。'), findsOneWidget);
  });

  testWidgets('点击中部再次隐藏 chrome', (tester) async {
    final backend = FakeBackend();
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(bookId: 'b1', bookTitle: '测试书', backend: backend),
    ));
    await tester.pumpAndSettle();
    await _toggleChrome(tester);
    expect(find.byTooltip('返回书架'), findsOneWidget);
    await _toggleChrome(tester);
    expect(find.text('返回书架'), findsNothing); // 沉浸态顶栏未渲染 // 再次点击中部隐藏
  });

  testWidgets('翻章后保存进度，重开恢复到该章', (tester) async {
    final backend = FakeBackend();
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(bookId: 'b1', bookTitle: '测试书', backend: backend),
    ));
    await tester.pumpAndSettle();
    expect(find.text('很久以前，有一座山。'), findsOneWidget);

    await _toggleChrome(tester);
    await tester.tap(find.text('下一章'));
    await tester.pumpAndSettle();
    expect(find.text('故事结束了。'), findsOneWidget);
    expect(backend.saved?.href, 'chapter_0002.xhtml');

    // 重开恢复到第二章
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(bookId: 'b1', bookTitle: '测试书', backend: backend),
    ));
    await tester.pumpAndSettle();
    expect(find.text('故事结束了。'), findsOneWidget);
  });

  testWidgets('Aa 面板：弹出且可切换分页模式（不再有右上角按钮）', (tester) async {
    final backend = FakeBackend();
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: backend,
        pagedViewBuilder: fakePagedBuilder,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('很久以前，有一座山。'), findsOneWidget);

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
    final backend = FakeBackend();
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
}
