import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/pages/library_page.dart';
import 'package:reader_app/pages/reader_page.dart';

import 'fake_backend.dart';

void main() {
  testWidgets('书架显示书籍，点击可打开阅读器并渲染章节', (tester) async {
    final backend = FakeBackend();
    await tester.pumpWidget(MaterialApp(home: LibraryPage(backend: backend)));
    await tester.pumpAndSettle();

    // 书架出现书籍
    expect(find.text('测试书'), findsOneWidget);
    expect(find.textContaining('epub'), findsOneWidget);

    // 点击进入阅读器 → 章节文本渲染（滚动模式）
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
}
