import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/engines/paged_document_reloader.dart';

void main() {
  group('PagedDocumentReloader.shouldReload / baseUrlFor', () {
    test('href 或 html 变化 → true；均不变 → false（幂等）', () {
      expect(
        PagedDocumentReloader.shouldReload(
          oldHref: 'chapter_0001.xhtml',
          newHref: 'chapter_0002.xhtml',
          oldHtml: 'a',
          newHtml: 'a',
        ),
        isTrue,
      );
      expect(
        PagedDocumentReloader.shouldReload(
          oldHref: 'chapter_0001.xhtml',
          newHref: 'chapter_0001.xhtml',
          oldHtml: 'a',
          newHtml: 'b',
        ),
        isTrue,
      );
      expect(
        PagedDocumentReloader.shouldReload(
          oldHref: 'chapter_0001.xhtml',
          newHref: 'chapter_0001.xhtml',
          oldHtml: 'a',
          newHtml: 'a',
        ),
        isFalse,
      );
    });

    test('baseUrlFor → reader://book/{bookId}/', () {
      expect(PagedDocumentReloader.baseUrlFor('b1'), 'reader://book/b1/');
    });
  });

  group('PagedDocumentReloader.onWidgetUpdated', () {
    late List<String> loadCalls;
    late List<String> styleCalls;
    late PagedDocumentReloader reloader;

    setUp(() {
      loadCalls = <String>[];
      styleCalls = <String>[];
      reloader = PagedDocumentReloader(
        loadData: ({required String html, required String baseUrl}) async {
          loadCalls.add('$baseUrl|$html');
        },
        applyStyle: ({required int fontSize, required String theme}) async {
          styleCalls.add('$fontSize|$theme');
        },
      );
    });

    test('href 变化 → 恰好 1 次 loadData（新 html + reader://book/b1/），不 applyStyle', () async {
      final outcome = await reloader.onWidgetUpdated(
        oldHref: 'chapter_0001.xhtml',
        newHref: 'chapter_0002.xhtml',
        oldHtml: 'old',
        newHtml: 'new',
        bookId: 'b1',
        oldFontSize: 18,
        fontSize: 18,
        oldTheme: 'light',
        theme: 'light',
      );
      expect(outcome, PagedReloadOutcome.reloaded);
      expect(loadCalls, ['reader://book/b1/|new']);
      expect(styleCalls, isEmpty);
    });

    test('html 变化 → 重载', () async {
      final outcome = await reloader.onWidgetUpdated(
        oldHref: 'chapter_0001.xhtml',
        newHref: 'chapter_0001.xhtml',
        oldHtml: 'old',
        newHtml: 'new',
        bookId: 'b1',
        oldFontSize: 18,
        fontSize: 18,
        oldTheme: 'light',
        theme: 'light',
      );
      expect(outcome, PagedReloadOutcome.reloaded);
      expect(loadCalls.length, 1);
    });

    test('仅 fontSize/theme 变化 → applyStyle 1 次、loadData 0 次', () async {
      final outcome = await reloader.onWidgetUpdated(
        oldHref: 'chapter_0001.xhtml',
        newHref: 'chapter_0001.xhtml',
        oldHtml: 'same',
        newHtml: 'same',
        bookId: 'b1',
        oldFontSize: 18,
        fontSize: 22,
        oldTheme: 'light',
        theme: 'dark',
      );
      expect(outcome, PagedReloadOutcome.styled);
      expect(loadCalls, isEmpty);
      expect(styleCalls, ['22|dark']);
    });

    test('href/html 均不变 → none（两者 0 次）', () async {
      final outcome = await reloader.onWidgetUpdated(
        oldHref: 'chapter_0001.xhtml',
        newHref: 'chapter_0001.xhtml',
        oldHtml: 'same',
        newHtml: 'same',
        bookId: 'b1',
        oldFontSize: 18,
        fontSize: 18,
        oldTheme: 'light',
        theme: 'light',
      );
      expect(outcome, PagedReloadOutcome.none);
      expect(loadCalls, isEmpty);
      expect(styleCalls, isEmpty);
    });

    test('bookId 变化 → baseUrl 随新 bookId', () async {
      await reloader.onWidgetUpdated(
        oldHref: 'chapter_0001.xhtml',
        newHref: 'chapter_0002.xhtml',
        oldHtml: 'old',
        newHtml: 'new',
        bookId: 'b2',
        oldFontSize: 18,
        fontSize: 18,
        oldTheme: 'light',
        theme: 'light',
      );
      expect(loadCalls, ['reader://book/b2/|new']);
    });
  });

  group('PagedLoadGate', () {
    test('begin 后 pending 且 done 未完成；complete 后放行', () async {
      final gate = PagedLoadGate();
      expect(gate.pending, isFalse);
      var released = false;
      gate.begin();
      expect(gate.pending, isTrue);
      gate.done.then((_) => released = true);
      await Future<void>.delayed(Duration.zero);
      expect(released, isFalse, reason: '载入未完成时 relayoutAfterLoad 应挂起');
      gate.complete();
      expect(gate.pending, isFalse);
      await gate.done;
      expect(released, isTrue);
    });

    test('未 begin 时 done 立即完成', () async {
      final gate = PagedLoadGate();
      await gate.done;
      expect(gate.pending, isFalse);
    });

    test('重复 complete 不抛错', () {
      final gate = PagedLoadGate();
      gate.begin();
      gate.complete();
      expect(gate.complete, returnsNormally);
    });
  });
}
