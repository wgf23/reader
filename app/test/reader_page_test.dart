import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/pages/library_page.dart';
import 'package:reader_app/pages/reader_page.dart';

import 'fake_backend.dart';

/// 分页模式的 fake 构建器：不实例化真实 WebView
Widget fakePagedBuilder(
  BuildContext context, {
  required String bookId,
  required String href,
  required String html,
  required dynamic backend,
  required int fontSize,
  required ValueChanged<double> onProgress,
}) {
  return const Center(child: Text('分页模式（fake WebView）'));
}

void main() {
  testWidgets('书架显示书籍，点击可打开阅读器并渲染章节（滚动模式）', (tester) async {
    final backend = FakeBackend();
    await tester.pumpWidget(MaterialApp(home: LibraryPage(backend: backend)));
    await tester.pumpAndSettle();

    expect(find.text('测试书'), findsOneWidget);
    await tester.tap(find.text('测试书'));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderPage), findsOneWidget);
    expect(find.text('第一章'), findsOneWidget);
    expect(find.text('很久以前，有一座山。'), findsOneWidget);

    // 章节切换 → 第二章
    await tester.tap(find.byIcon(Icons.skip_next));
    await tester.pumpAndSettle();
    expect(find.text('故事结束了。'), findsOneWidget);
  });

  testWidgets('滚动模式切换进度：翻章后保存进度，重开恢复到该章', (tester) async {
    final backend = FakeBackend();
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: backend,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('很久以前，有一座山。'), findsOneWidget);

    // 翻到第二章 → 触发进度保存（chapter_0002.xhtml）
    await tester.tap(find.byIcon(Icons.skip_next));
    await tester.pumpAndSettle();
    expect(find.text('故事结束了。'), findsOneWidget);
    expect(backend.saved?.href, 'chapter_0002.xhtml');

    // 重开：恢复到第二章
    await tester.pumpWidget(const SizedBox()); // 卸载
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: backend,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('故事结束了。'), findsOneWidget);
  });

  testWidgets('分页模式：切换后由构建器渲染（fake WebView），不触碰真实平台', (tester) async {
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
    expect(find.text('很久以前，有一座山。'), findsOneWidget); // 默认滚动模式

    // 切换分页模式 → fake 构建器渲染
    await tester.tap(find.byIcon(Icons.auto_stories));
    await tester.pumpAndSettle();
    expect(find.text('分页模式（fake WebView）'), findsOneWidget);
  });
}
