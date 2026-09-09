import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/pages/continuous_scroll_policy.dart';
import 'package:reader_app/services/library_backend.dart';

/// REQ-008 T-002/T-001 [单测]：
/// `resolveVisibleChapter`（顶部锚点 + 迟滞 + 触底）、`chapterProgression`、
/// `proportionalChapterOffset`、`ChapterGeometry.visibleFraction`、`ChapterContentCache`
/// （US-6/US-10 可测出口）。
ChapterGeometry _g(int index, double top, [double height = 500]) =>
    ChapterGeometry(index: index, top: top, height: height);

void main() {
  group('resolveVisibleChapter（D2 顶部锚点 + 迟滞 + 触底）', () {
    test('built 为空 → 保持 current', () {
      expect(
        resolveVisibleChapter(
          built: const [],
          viewportHeight: 800,
          current: 2,
          lastIndex: 5,
        ),
        2,
      );
    });

    test('章顶未越界 → 保持 current', () {
      final built = [_g(0, 0), _g(1, 500)];
      expect(
        resolveVisibleChapter(
          built: built,
          viewportHeight: 800,
          current: 0,
          lastIndex: 2,
        ),
        0,
      );
    });

    test('章顶越过 -hysteresis → 切前', () {
      final built = [_g(0, -500), _g(1, -9), _g(2, 400)];
      expect(
        resolveVisibleChapter(
          built: built,
          viewportHeight: 800,
          current: 0,
          lastIndex: 2,
        ),
        1,
      );
    });

    test('章顶落在迟滞带内（-hysteresis..hysteresis）→ 保持 current', () {
      final built = [_g(0, -500), _g(1, 0), _g(2, 400)];
      expect(
        resolveVisibleChapter(
          built: built,
          viewportHeight: 800,
          current: 0,
          lastIndex: 2,
        ),
        0,
      );
    });

    test('回滚越过 +hysteresis → 切后', () {
      final built = [_g(0, -300), _g(1, 100), _g(2, 600)];
      expect(
        resolveVisibleChapter(
          built: built,
          viewportHeight: 800,
          current: 1,
          lastIndex: 2,
        ),
        0,
      );
    });

    test('回滚未越过 +hysteresis → 保持 current', () {
      final built = [_g(0, -300), _g(1, 5), _g(2, 600)];
      expect(
        resolveVisibleChapter(
          built: built,
          viewportHeight: 800,
          current: 1,
          lastIndex: 2,
        ),
        1,
      );
    });

    test('所有章顶都在视口下方 → 取第一个已构建章（回滚到顶部）', () {
      final built = [_g(0, 24), _g(1, 500)];
      expect(
        resolveVisibleChapter(
          built: built,
          viewportHeight: 800,
          current: 1,
          lastIndex: 1,
        ),
        0,
      );
    });

    test('atEnd==true → 强制末章', () {
      final built = [_g(0, -500), _g(1, -100)];
      expect(
        resolveVisibleChapter(
          built: built,
          viewportHeight: 800,
          current: 0,
          lastIndex: 3,
          atEnd: true,
        ),
        3,
      );
    });

    test('viewportHeight<=0 → 保持 current', () {
      final built = [_g(0, -500)];
      expect(
        resolveVisibleChapter(
          built: built,
          viewportHeight: 0,
          current: 1,
          lastIndex: 2,
        ),
        1,
      );
    });
  });

  group('chapterProgression（D3 章内比例）', () {
    test('章顶在视口顶 → 0.0', () {
      expect(chapterProgression(top: 0, height: 1000), 0.0);
    });

    test('章顶在视口上方半章 → 0.5', () {
      expect(chapterProgression(top: -500, height: 1000), 0.5);
    });

    test('章顶在视口下方 → 夹取 0.0', () {
      expect(chapterProgression(top: 300, height: 1000), 0.0);
    });

    test('滚过章尾 → 夹取 1.0', () {
      expect(chapterProgression(top: -1200, height: 1000), 1.0);
    });

    test('章高<=0 → 0.0（不除零）', () {
      expect(chapterProgression(top: -100, height: 0), 0.0);
    });
  });

  group('proportionalChapterOffset（D4 远跳估算）', () {
    test('首章 → 0', () {
      expect(
        proportionalChapterOffset(index: 0, chapterCount: 5, maxScrollExtent: 4000),
        0.0,
      );
    });

    test('末章 → maxScrollExtent', () {
      expect(
        proportionalChapterOffset(index: 4, chapterCount: 5, maxScrollExtent: 4000),
        4000.0,
      );
    });

    test('中段按章序比例', () {
      expect(
        proportionalChapterOffset(index: 2, chapterCount: 5, maxScrollExtent: 4000),
        2000.0,
      );
    });

    test('index 越界 → 夹取', () {
      expect(
        proportionalChapterOffset(index: 99, chapterCount: 5, maxScrollExtent: 4000),
        4000.0,
      );
    });

    test('单章 / 零高 → 0', () {
      expect(
        proportionalChapterOffset(index: 0, chapterCount: 1, maxScrollExtent: 4000),
        0.0,
      );
      expect(
        proportionalChapterOffset(index: 0, chapterCount: 5, maxScrollExtent: 0),
        0.0,
      );
    });
  });

  group('ChapterGeometry.visibleFraction', () {
    test('章顶在视口上方、章跨满视口 → 1.0', () {
      expect(_g(0, -250, 500).visibleFraction(800), 0.3125);
    });

    test('章在视口内 → 占比正确', () {
      expect(_g(0, 100, 500).visibleFraction(800), 0.625);
    });

    test('章在视口下方 → 0', () {
      expect(_g(0, 900, 500).visibleFraction(800), 0.0);
    });

    test('非法尺寸 → 0', () {
      expect(_g(0, 0, 0).visibleFraction(800), 0.0);
      expect(_g(0, 0, 500).visibleFraction(0), 0.0);
    });
  });

  group('ChapterContentCache（D5 / US-10）', () {
    test('成功记忆化：provider 只调用一次', () {
      var calls = 0;
      final cache = ChapterContentCache(provider: (i) {
        calls++;
        return ChapterData(title: 't$i', text: 'x');
      });
      final r1 = cache.resolve(0);
      final r2 = cache.resolve(0);
      expect(r1.isFailure, isFalse);
      expect(r1.chapter!.title, 't0');
      expect(r2.chapter!.title, 't0');
      expect(calls, 1);
      expect(cache.attemptsOf(0), 1);
    });

    test('失败记忆化：不自动重试、attempts==1', () {
      var calls = 0;
      final cache = ChapterContentCache(provider: (i) {
        calls++;
        throw StateError('boom');
      });
      final r1 = cache.resolve(1);
      final r2 = cache.resolve(1);
      expect(r1.isFailure, isTrue);
      expect(r2.isFailure, isTrue);
      expect(r1.error, isA<StateError>());
      expect(calls, 1, reason: '失败必须记忆化，不进入无限重试');
      expect(cache.attemptsOf(1), 1);
    });

    test('retry 清失败记忆后重新调用 provider（显式、有界）', () {
      var calls = 0;
      final cache = ChapterContentCache(provider: (i) {
        calls++;
        if (calls == 1) throw StateError('boom');
        return const ChapterData(title: '恢复', text: 'x');
      });
      expect(cache.resolve(0).isFailure, isTrue);
      cache.retry(0);
      final r = cache.resolve(0);
      expect(r.isFailure, isFalse);
      expect(r.chapter!.title, '恢复');
      expect(calls, 2);
      expect(cache.attemptsOf(0), 1, reason: 'retry 重置本章计数');
    });

    test('maxAttempts>1 时未显式 retry 仍不自动重试', () {
      var calls = 0;
      final cache = ChapterContentCache(maxAttempts: 3, provider: (i) {
        calls++;
        throw StateError('boom');
      });
      cache.resolve(0);
      cache.resolve(0);
      expect(calls, 1);
      expect(cache.attemptsOf(0), 1);
    });
  });

  group('ChapterSection（D1 每章 item）', () {
    testWidgets('渲染章标题 + 正文（结构 = 既有单章排版）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ChapterSection(
            index: 0,
            chapter: ChapterData(title: '第一章', text: '很久以前，有一座山。'),
            fontSize: 18,
            lineHeight: 1.8,
            fontFamily: null,
            foreground: Colors.black,
          ),
        ),
      ));
      expect(find.text('第一章'), findsOneWidget);
      expect(find.text('很久以前，有一座山。'), findsOneWidget);
    });
  });
}
