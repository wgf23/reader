import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/engines/paged_view_controls.dart';

import 'fake_paged_view_controls.dart';

void main() {
  test('US-8 章内 nextPage()==true → 不调用 goChapter', () async {
    final controls = FakePagedViewControls(nextResult: true);
    final chapters = <int>[];
    final coordinator = PageTurnCoordinator(controls: controls, goChapter: chapters.add);

    await coordinator.page(1);

    expect(controls.nextCalls, 1);
    expect(controls.prevCalls, 0);
    expect(chapters, isEmpty, reason: '章内翻页不应跳章');
  });

  test('US-8 章末 nextPage()==false → goChapter(+1) 恰好 1 次', () async {
    final controls = FakePagedViewControls(nextResult: false);
    final chapters = <int>[];
    final coordinator = PageTurnCoordinator(controls: controls, goChapter: chapters.add);

    await coordinator.page(1);

    expect(controls.nextCalls, 1);
    expect(chapters, [1]);
  });

  test('US-8 章首 prevPage()==false → goChapter(-1) 恰好 1 次', () async {
    final controls = FakePagedViewControls(prevResult: false);
    final chapters = <int>[];
    final coordinator = PageTurnCoordinator(controls: controls, goChapter: chapters.add);

    await coordinator.page(-1);

    expect(controls.prevCalls, 1);
    expect(controls.nextCalls, 0);
    expect(chapters, [-1]);
  });

  test('US-8 章内 prevPage()==true → 不跳章（左边缘对称）', () async {
    final controls = FakePagedViewControls(prevResult: true);
    final chapters = <int>[];
    final coordinator = PageTurnCoordinator(controls: controls, goChapter: chapters.add);

    await coordinator.page(-1);

    expect(controls.prevCalls, 1);
    expect(chapters, isEmpty);
  });
}
