// REQ-009 · SearchPage 边界与异常测试（US-18/19/20，线框 04）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/pages/search_page.dart';
import 'package:reader_app/services/search_backend.dart';

import 'fake_search_backend.dart';

class _ThrowingSearch implements SearchBackend {
  @override
  Future<List<SearchHitData>> search(String query, SearchScopeData scope) async =>
      throw Exception('boom');
}

/// 挂起直至外部完成的搜索后端（验证 loading 态）。
class _PendingSearch implements SearchBackend {
  final Completer<List<SearchHitData>> completer =
      Completer<List<SearchHitData>>();
  SearchScopeData? lastScope;

  @override
  Future<List<SearchHitData>> search(String query, SearchScopeData scope) {
    lastScope = scope;
    return completer.future;
  }
}

SearchHitData hit({
  String bookId = 'b1',
  String bookTitle = '看不见的城市',
  String href = 'chapter_0001.xhtml',
  String chapterTitle = '城市与记忆',
  String snippet = '看不见的城市，卡尔维诺写道。',
  List<TextRangeData> ranges = const [TextRangeData(start: 4, end: 6)],
}) =>
    SearchHitData(
      bookId: bookId,
      bookTitle: bookTitle,
      href: href,
      chapterTitle: chapterTitle,
      snippet: snippet,
      ranges: ranges,
    );

Future<void> pumpSearch(
  WidgetTester tester, {
  required SearchBackend backend,
  String? initialBookId = 'b1',
}) async {
  await tester.pumpWidget(MaterialApp(
    home: SearchPage(
      searchBackend: backend,
      initialBookId: initialBookId,
      initialBookTitle: '看不见的城市',
    ),
  ));
  await tester.pumpAndSettle();
}

bool hasBlueBoldSpan(WidgetTester tester, String text) {
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    final span = t.textSpan;
    if (span is! TextSpan) continue;
    for (final c in span.children ?? const <InlineSpan>[]) {
      if (c is TextSpan &&
          c.text == text &&
          c.style?.color == const Color(0xFF1A73E8) &&
          c.style?.fontWeight == FontWeight.bold) {
        return true;
      }
    }
  }
  return false;
}

void main() {
  testWidgets('初始态提示 + 空查询提示', (tester) async {
    await pumpSearch(tester, backend: FakeSearchBackend());
    expect(find.textContaining('输入关键词后点击'), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();
    expect(find.text('请输入关键词'), findsOneWidget);
  });

  testWidgets('命中渲染：书名/章节/关键词蓝加粗/结果数耗时', (tester) async {
    await pumpSearch(
      tester,
      backend: FakeSearchBackend(hits: [hit()]),
    );
    await tester.enterText(find.byKey(const Key('search-field')), '城市');
    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();

    expect(find.text('看不见的城市'), findsOneWidget);
    expect(find.textContaining('第 1 章 · 城市与记忆'), findsOneWidget);
    expect(hasBlueBoldSpan(tester, '城市'), isTrue,
        reason: '关键词应渲染为蓝色加粗');
    final stats = tester.widget<Text>(find.byKey(const Key('search-stats')));
    expect(stats.data, contains('结果 1 条'));
    expect(stats.data, contains('s'));
  });

  testWidgets('无命中 → 未找到相关结果', (tester) async {
    await pumpSearch(tester, backend: FakeSearchBackend(hits: const []));
    await tester.enterText(find.byKey(const Key('search-field')), 'zzz');
    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();
    expect(find.text('未找到相关结果'), findsOneWidget);
  });

  testWidgets('键盘提交（onSubmitted）也能触发搜索', (tester) async {
    final backend = FakeSearchBackend(hits: [hit()]);
    await pumpSearch(tester, backend: backend);
    await tester.enterText(find.byKey(const Key('search-field')), '城市');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(backend.queries, contains('城市'));
  });

  testWidgets('搜索失败 → 错误态', (tester) async {
    await pumpSearch(tester, backend: _ThrowingSearch());
    await tester.enterText(find.byKey(const Key('search-field')), '城市');
    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('搜索失败'), findsOneWidget);
  });

  testWidgets('搜索挂起 → loading 且按钮禁用，完成后恢复', (tester) async {
    final pending = _PendingSearch();
    await pumpSearch(tester, backend: pending);
    await tester.enterText(find.byKey(const Key('search-field')), '城市');
    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('search-submit')))
          .onPressed,
      isNull,
    );
    pending.completer.complete([hit()]);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('范围筛选：切到当前书籍 → scope.allBooks=false + bookId', (tester) async {
    final backend = FakeSearchBackend(hits: [hit()]);
    await pumpSearch(tester, backend: backend);
    await tester.tap(find.byKey(const Key('scope-current')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), '城市');
    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();
    final scope = backend.scopes.last;
    expect(scope.allBooks, isFalse);
    expect(scope.bookId, 'b1');
  });

  testWidgets('格式筛选：默认 EPUB+MOBI；取消 EPUB 后仅 MOBI', (tester) async {
    final backend = FakeSearchBackend(hits: [hit()]);
    await pumpSearch(tester, backend: backend);
    expect(backend.scopes, isEmpty);
    await tester.tap(find.byKey(const Key('format-EPUB')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), '城市');
    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();
    expect(backend.scopes.last.formats, ['MOBI']);

    await tester.tap(find.byKey(const Key('format-PDF')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();
    expect(backend.scopes.last.formats, containsAll(<String>['PDF', 'MOBI']));
  });

  testWidgets('定位按钮 → Navigator.pop 返回命中', (tester) async {
    SearchHitData? popped;
    final backend = FakeSearchBackend(hits: [hit()]);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                popped = await Navigator.of(ctx).push<SearchHitData>(
                  MaterialPageRoute<SearchHitData>(
                    builder: (_) => SearchPage(
                      searchBackend: backend,
                      initialBookId: 'b1',
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), '城市');
    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-locate-0')));
    await tester.pumpAndSettle();
    expect(popped?.bookId, 'b1');
    expect(popped?.snippet, contains('城市'));
  });

  testWidgets('snippet 区间越界被 clamp，不抛异常', (tester) async {
    await pumpSearch(
      tester,
      backend: FakeSearchBackend(hits: [
        hit(snippet: '短', ranges: const [TextRangeData(start: 5, end: 99)]),
      ]),
    );
    await tester.enterText(find.byKey(const Key('search-field')), 'x');
    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('无范围（ranges 空）也能渲染结果行', (tester) async {
    await pumpSearch(
      tester,
      backend: FakeSearchBackend(hits: [hit(ranges: const [])]),
    );
    await tester.enterText(find.byKey(const Key('search-field')), '城市');
    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 章'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('多条结果 → 渲染分隔线；范围可切回全部书籍', (tester) async {
    final backend = FakeSearchBackend(hits: [
      hit(bookTitle: '书一'),
      hit(bookTitle: '书二', chapterTitle: '第二章'),
    ]);
    await pumpSearch(tester, backend: backend);
    await tester.enterText(find.byKey(const Key('search-field')), '城市');
    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();
    expect(find.text('书一'), findsOneWidget);
    expect(find.text('书二'), findsOneWidget);
    expect(find.byType(Divider), findsWidgets, reason: '多条结果应有分隔线');

    await tester.tap(find.byKey(const Key('scope-current')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scope-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();
    expect(backend.scopes.last.allBooks, isTrue);
  });
}
