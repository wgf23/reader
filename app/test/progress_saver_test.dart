import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/pages/progress_saver.dart';

/// REQ-008 T-003 [单测]：`ProgressSaver` 尾沿防抖（US-3）。
///
/// `testWidgets` 提供 FakeAsync，`tester.pump(Duration)` 推进假时钟以驱动 Timer。
void main() {
  testWidgets('300ms 内多次 schedule → 尾沿只落盘 1 次且为最后一次值', (tester) async {
    final saved = <List<Object?>>[];
    final saver = ProgressSaver(
      save: (href, p) async => saved.add([href, p]),
    );
    addTearDown(saver.dispose);

    saver.schedule('chapter_0001.xhtml', 0.1);
    await tester.pump(const Duration(milliseconds: 100));
    saver.schedule('chapter_0001.xhtml', 0.2);
    await tester.pump(const Duration(milliseconds: 100));
    saver.schedule('chapter_0002.xhtml', 0.3);
    await tester.pump(const Duration(milliseconds: 100));
    expect(saved, isEmpty, reason: '尾沿未到期不落盘');

    await tester.pump(const Duration(milliseconds: 300));
    expect(saved.length, 1);
    expect(saved.single[0], 'chapter_0002.xhtml');
    expect(saved.single[1], 0.3);
  });

  testWidgets('flush → 立即落盘并取消挂起计时器', (tester) async {
    final saved = <List<Object?>>[];
    final saver = ProgressSaver(
      save: (href, p) async => saved.add([href, p]),
    );
    addTearDown(saver.dispose);

    saver.schedule('chapter_0001.xhtml', 0.9);
    await saver.flush('chapter_0001.xhtml', 0.5);
    expect(saved.length, 1);
    expect(saved.single[1], 0.5);

    // 挂起的尾沿计时器已被取消：推进 300ms 不再追加。
    await tester.pump(const Duration(milliseconds: 300));
    expect(saved.length, 1);
  });

  testWidgets('dispose 取消挂起计时器（不再触发）', (tester) async {
    final saved = <List<Object?>>[];
    final saver = ProgressSaver(
      save: (href, p) async => saved.add([href, p]),
    );

    saver.schedule('chapter_0001.xhtml', 0.7);
    saver.dispose();
    await tester.pump(const Duration(milliseconds: 300));
    expect(saved, isEmpty, reason: 'dispose 后挂起计时器不得再触发');
  });

  testWidgets('可注入 debounce（缩短窗口便于断言）', (tester) async {
    final saved = <List<Object?>>[];
    final saver = ProgressSaver(
      save: (href, p) async => saved.add([href, p]),
      debounce: const Duration(milliseconds: 50),
    );
    addTearDown(saver.dispose);

    saver.schedule('chapter_0001.xhtml', 0.4);
    await tester.pump(const Duration(milliseconds: 49));
    expect(saved, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(saved.length, 1);
    expect(saved.single[1], 0.4);
  });

  testWidgets('flush 无挂起值时也落盘（入参为准）', (tester) async {
    final saved = <List<Object?>>[];
    final saver = ProgressSaver(
      save: (href, p) async => saved.add([href, p]),
    );
    addTearDown(saver.dispose);

    await saver.flush('chapter_0003.xhtml', 0.0);
    expect(saved.single[0], 'chapter_0003.xhtml');
    expect(saved.single[1], 0.0);
  });
}
