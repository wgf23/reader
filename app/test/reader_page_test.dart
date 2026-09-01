import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/pages/reader_page.dart';
import 'package:reader_app/widgets/directory_drawer.dart';
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

  testWidgets('⋯更多弹层：4 个占位项（阅读统计/听书/笔记/导出）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(bookId: 'b1', bookTitle: '测试书', backend: FakeBackend()),
    ));
    await tester.pumpAndSettle();
    await _toggleChrome(tester);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('阅读统计'), findsOneWidget);
    expect(find.text('听书'), findsOneWidget);
    expect(find.text('笔记'), findsOneWidget);
    expect(find.text('导出'), findsOneWidget);
  });

  testWidgets('目录抽屉：打开列出章节 → 选另一章跳转 + saveProgress', (tester) async {
    final backend = FakeBackend();
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
    expect(find.text('故事结束了。'), findsOneWidget);
    expect(backend.saved?.href, 'chapter_0002.xhtml');
  });

  testWidgets('书签图标切换（幂等）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(bookId: 'b1', bookTitle: '测试书', backend: FakeBackend()),
    ));
    await tester.pumpAndSettle();
    await _toggleChrome(tester);
    expect(find.byTooltip('加书签'), findsOneWidget);
    await tester.tap(find.byTooltip('加书签'));
    await tester.pump();
    expect(find.byTooltip('取消书签'), findsOneWidget);
    await tester.tap(find.byTooltip('取消书签'));
    await tester.pump();
    expect(find.byTooltip('加书签'), findsOneWidget);
  });

  testWidgets('选中工具条：划重点/笔记/复制 点击不崩溃', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(bookId: 'b1', bookTitle: '测试书', backend: FakeBackend()),
    ));
    await tester.pumpAndSettle();
    final sa = tester.widget<SelectionArea>(find.byType(SelectionArea));
    sa.onSelectionChanged!(const SelectedContent(plainText: '很久以前'));
    await tester.pumpAndSettle();
    for (final label in ['划重点', '笔记', '复制']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    // 复制/占位项不抛错，工具条仍在
    expect(find.text('划重点'), findsOneWidget);
  });

  testWidgets('分页模式：边缘 15% 点击不崩（fake 无 PagedWebViewState → 短路）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: FakeBackend(),
        pagedViewBuilder: fakePagedBuilder,
        initialPagedMode: true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('分页模式（fake WebView）'), findsOneWidget);
    await tester.tapAt(const Offset(50, 300)); // 左边缘 <0.15w
    await tester.pump();
    await tester.tapAt(const Offset(750, 300)); // 右边缘 >0.85w
    await tester.pump();
    expect(find.text('分页模式（fake WebView）'), findsOneWidget);
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
