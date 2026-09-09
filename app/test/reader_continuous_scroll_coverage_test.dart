import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/engines/paged_view_controls.dart';
import 'package:reader_app/engines/tts_engine.dart';
import 'package:reader_app/pages/continuous_scroll_policy.dart';
import 'package:reader_app/pages/listen_page.dart';
import 'package:reader_app/pages/reader_page.dart';
import 'package:reader_app/services/library_backend.dart';
import 'package:reader_app/services/tts_backend.dart';

import 'fake_backend.dart';
import 'fake_paged_view_controls.dart';
import 'fake_tts_backend.dart';
import 'fake_tts_engine.dart';

/// REQ-008 阶段4 测试补强（仅测试文件，不改生产代码）：
/// 覆盖开发阶段未被现有用例触达的边界/异常分支：
/// - `ChapterContentCache` `maxAttempts` 边界（防御分支，provider 调用有界）；
/// - `resolveVisibleChapter` 向后回滚且 `current` 不在已构建集合（远跳/回收后）；
/// - `reader_page` 恢复定位到"未构建的远章"时的有界步进（惰性列表）；
/// - 分页模式 `onProgress` → `_saveProgress` 落盘接线；
/// - 分页模式听书返回 → `_reloadProgress` 分页重排接线（US-9 回归）。
///
/// 均为**新增**断言，不修改既有测试/生产代码。

String _title(int i) => '第${i + 1}章';

String _text(int i) => List<String>.generate(
      30,
      (j) =>
          '第${i + 1}章第${j + 1}段，这是一段用于连续滚动阅读测试的正文，'
          '需要足够长以产生滚动并跨越视口，从而验证可见章判定与章内进度。',
    ).join();

/// 章节高度刻意不均匀：首章极短 → SliverList 估算的总高偏小，
/// 使"恢复到远章"必须走 `_scrollToChapter` 的有界步进（而非一次估算命中）。
class _UnevenBackend extends FakeBackend {
  _UnevenBackend(this.count);

  final int count;

  @override
  Future<BookViewData> openBook(String id) async => BookViewData(
        id: 'b1',
        title: '测试书',
        chapters: List<ChapterData>.generate(
          count,
          (i) => ChapterData(title: _title(i), text: i == 0 ? '短' : _text(i)),
        ),
      );
}

Widget _pagedApp(
  LibraryBackend backend, {
  PagedViewBuilder? builder,
  PagedViewControls? controls,
  TtsBackend? ttsBackend,
  TtsEngine? ttsEngine,
}) =>
    MaterialApp(
      home: ReaderPage(
        bookId: 'b1',
        bookTitle: '测试书',
        backend: backend,
        pagedViewBuilder: builder,
        pagedControls: controls,
        initialPagedMode: true,
        ttsBackend: ttsBackend,
        ttsEngine: ttsEngine,
      ),
    );

void main() {
  group('continuous_scroll_policy 边界补强', () {
    test('ChapterContentCache maxAttempts=0：provider 零调用且返回有界失败', () {
      var calls = 0;
      final cache = ChapterContentCache(
        maxAttempts: 0,
        provider: (i) {
          calls++;
          return const ChapterData(title: 't', text: 'x');
        },
      );
      final r1 = cache.resolve(0);
      final r2 = cache.resolve(0);
      expect(r1.isFailure, isTrue);
      expect(r2.isFailure, isTrue, reason: '记忆化，不重复进入防御分支');
      expect(calls, 0, reason: 'maxAttempts=0 时不得调用 provider（有界）');
      expect(cache.attemptsOf(0), 0);
      expect(r1.attempts, 0);
    });

    test('向后回滚且 current 不在已构建集合 → 取最靠上的已构建章', () {
      final built = [const ChapterGeometry(index: 0, top: 100, height: 500)];
      expect(
        resolveVisibleChapter(
          built: built,
          viewportHeight: 800,
          current: 2, // 第 3 章已被回收，不在 built 内
          lastIndex: 3,
        ),
        0,
      );
    });
  });

  testWidgets('恢复定位到未构建的远章：有界步进最终落到目标章（不崩溃）',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final backend = _UnevenBackend(40);
    // 恢复到第 30 章章首（惰性列表下目标章尚未构建）。
    backend.saved = const ProgressData(
      href: 'chapter_0030.xhtml',
      progression: 0.0,
    );
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(bookId: 'b1', bookTitle: '测试书', backend: backend),
    ));
    await tester.pumpAndSettle();

    expect(find.text(_text(29)), findsOneWidget,
        reason: '远章恢复必须有界步进到目标章（非停在第一章/全书 0%）');
    expect(tester.takeException(), isNull);
  });

  testWidgets('分页模式 onProgress 回调 → _saveProgress 立即落盘（US-9 回归）',
      (tester) async {
    final backend = FakeBackend();
    var fired = false;
    Widget builder(
      BuildContext context, {
      required String bookId,
      required String href,
      required String html,
      required dynamic backend,
      required int fontSize,
      required ValueChanged<double> onProgress,
      ValueChanged<String>? onSelectedText,
    }) {
      if (!fired) {
        fired = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => onProgress(0.42));
      }
      return const Center(child: Text('分页模式（fake WebView）'));
    }

    await tester.pumpWidget(_pagedApp(backend, builder: builder));
    await tester.pumpAndSettle();

    expect(backend.saved?.href, 'chapter_0001.xhtml');
    expect(backend.saved?.progression, 0.42,
        reason: '分页 onProgress 必须经 _saveProgress 落盘');
  });

  testWidgets('分页模式听书返回 → _reloadProgress 分页重排接线（US-9 回归）',
      (tester) async {
    const sentences = {
      'chapter_0001.xhtml': ['很久以前，有一座山。'],
      'chapter_0002.xhtml': ['故事结束了。'],
    };
    final backend = FakeBackend();
    final controls = FakePagedViewControls();
    final engine = FakeTtsEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(_pagedApp(
      backend,
      builder: (context,
              {required bookId,
              required href,
              required html,
              required backend,
              required fontSize,
              required onProgress,
              onSelectedText}) =>
          const Center(child: Text('分页模式（fake WebView）')),
      controls: controls,
      ttsBackend: FakeTtsBackend(sentences: sentences),
      ttsEngine: engine,
    ));
    await tester.pumpAndSettle();

    // 中部点击呼出 Chrome → 更多 → 听书。
    await tester.tapAt(tester.getCenter(find.text('分页模式（fake WebView）')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('听书'));
    await tester.pumpAndSettle();
    expect(find.byType(ListenPage), findsOneWidget);

    // 模拟听书写入第二章进度后返回。
    backend.saved = const ProgressData(
      href: 'chapter_0002.xhtml',
      progression: 0.0,
    );
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(controls.relayoutAfterLoadCalls, 1,
        reason: '分页模式重读进度后必须触发重排');
    expect(tester.takeException(), isNull);
  });
}
