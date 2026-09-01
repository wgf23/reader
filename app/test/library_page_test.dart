import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/pages/library_page.dart';
import 'package:reader_app/pages/reader_page.dart';

import 'fake_backend.dart';

const _center = Offset(400, 300);

Future<void> _toggleChrome(WidgetTester tester) async {
  await tester.tapAt(_center);
  await tester.pump();
}

void main() {
  testWidgets('书架显示书籍，点击进入阅读器（沉浸态）并底栏翻章', (tester) async {
    final backend = FakeBackend();
    await tester.pumpWidget(MaterialApp(home: LibraryPage(backend: backend)));
    await tester.pumpAndSettle();

    expect(find.text('测试书'), findsOneWidget);
    expect(find.textContaining('epub'), findsOneWidget);

    await tester.tap(find.text('测试书'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderPage), findsOneWidget);
    // 沉浸态：正文可见
    expect(find.text('第一章'), findsOneWidget);
    expect(find.text('很久以前，有一座山。'), findsOneWidget);

    // 呼出 chrome → 底栏下一章
    await _toggleChrome(tester);
    await tester.tap(find.text('下一章'));
    await tester.pumpAndSettle();
    expect(find.text('故事结束了。'), findsOneWidget);
  });
}
