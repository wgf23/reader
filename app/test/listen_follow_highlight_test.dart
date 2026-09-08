// REQ-006 · US-7：ListenFollowHighlight 自动滚动的边界/异常路径补测。
//
// 覆盖 `offsetForHighlight` 纯函数的单调性与上下界 clamp、注入 controller 的
// 重新挂载（didUpdateWidget 换 controller）、越界高亮区间 clamp、autoScroll=false
// 的对照路径。生产代码零改动。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/widgets/listen_follow_highlight.dart';

const _baseText =
    '第一句。第二句。第三句。第四句。第五句。第六句。第七句。第八句。'
    '第九句。第十句。第十一句。第十二句。第十三句。第十四句。第十五句。';

/// 足够长以在 800x600 测试视口内产生 `maxScrollExtent > 0`。
final _longText = _baseText * 60;

const _style = TextStyle(fontSize: 17, height: 1.8);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('offsetForHighlight（纯函数）', () {
    test('highlightStart 递增 → 偏移单调不减', () {
      final offsets = <double>[];
      for (var start = 0; start < _longText.length; start += 50) {
        offsets.add(ListenFollowHighlight.offsetForHighlight(
          text: _longText,
          highlightStart: start,
          style: _style,
          maxWidth: 300,
          textScaler: 1.0,
          viewportHeight: 400,
          maxScrollExtent: 100000,
        ));
      }
      for (var i = 1; i < offsets.length; i++) {
        expect(offsets[i], greaterThanOrEqualTo(offsets[i - 1]),
            reason: '句序号增大时目标偏移不得回退');
      }
    });

    test('负偏移与超界均被 clamp 到 [0, maxScrollExtent]', () {
      final low = ListenFollowHighlight.offsetForHighlight(
        text: _longText,
        highlightStart: -10,
        style: _style,
        maxWidth: 300,
        textScaler: 1.0,
        viewportHeight: 400,
        maxScrollExtent: 100000,
      );
      expect(low, 0, reason: '起始句目标偏移应为 0（不回弹到负）');

      final high = ListenFollowHighlight.offsetForHighlight(
        text: _longText,
        highlightStart: _longText.length - 1,
        style: _style,
        maxWidth: 300,
        textScaler: 1.0,
        viewportHeight: 400,
        maxScrollExtent: 1,
      );
      expect(high, lessThanOrEqualTo(1), reason: '不得超过 maxScrollExtent');

      // maxWidth<=0 走 infinity 兜底分支，不得抛异常
      expect(
        () => ListenFollowHighlight.offsetForHighlight(
          text: _longText,
          highlightStart: 3,
          style: _style,
          maxWidth: 0,
          textScaler: 1.0,
          viewportHeight: 400,
          maxScrollExtent: 100000,
        ),
        returnsNormally,
      );
    });
  });

  testWidgets('US-7 注入 controller：句变化触发滚动回调，换 controller 后仍生效',
      (tester) async {
    final c1 = ScrollController();
    final c2 = ScrollController();
    addTearDown(c1.dispose);
    addTearDown(c2.dispose);
    final scrolled = <double>[];

    await tester.pumpWidget(_wrap(ListenFollowHighlight(
      text: _longText,
      highlightStart: 0,
      highlightEnd: 3,
      controller: c1,
      onScrolled: scrolled.add,
    )));
    await tester.pumpAndSettle();
    expect(scrolled, isNotEmpty, reason: '初始句应滚动进视口');

    // 句变化 → didUpdateWidget 重新计算并滚动
    final n1 = scrolled.length;
    await tester.pumpWidget(_wrap(ListenFollowHighlight(
      text: _longText,
      highlightStart: _longText.length ~/ 2,
      highlightEnd: _longText.length ~/ 2 + 4,
      controller: c1,
      onScrolled: scrolled.add,
    )));
    await tester.pumpAndSettle();
    expect(scrolled.length, greaterThan(n1), reason: '句变化应再次滚动');

    // 换 controller → didUpdateWidget 先 detach 再 attach 新 controller
    final n2 = scrolled.length;
    await tester.pumpWidget(_wrap(ListenFollowHighlight(
      text: _longText,
      highlightStart: _longText.length - 10,
      highlightEnd: _longText.length - 6,
      controller: c2,
      onScrolled: scrolled.add,
    )));
    await tester.pumpAndSettle();
    expect(scrolled.length, greaterThan(n2), reason: '换 controller 后应挂到新 controller 并滚动');
    expect(c2.offset, greaterThan(0));
  });

  testWidgets('US-7 autoScroll=false 不滚动（对照路径）', (tester) async {
    final c = ScrollController();
    addTearDown(c.dispose);
    final scrolled = <double>[];

    await tester.pumpWidget(_wrap(ListenFollowHighlight(
      text: _longText,
      highlightStart: _longText.length ~/ 2,
      highlightEnd: _longText.length ~/ 2 + 4,
      controller: c,
      autoScroll: false,
      onScrolled: scrolled.add,
    )));
    await tester.pumpAndSettle();
    expect(scrolled, isEmpty, reason: 'autoScroll=false 不应触发滚动');

    await tester.pumpWidget(_wrap(ListenFollowHighlight(
      text: _longText,
      highlightStart: _longText.length - 10,
      highlightEnd: _longText.length - 6,
      controller: c,
      autoScroll: false,
      onScrolled: scrolled.add,
    )));
    await tester.pumpAndSettle();
    expect(scrolled, isEmpty, reason: 'autoScroll=false 句变化也不滚动');
  });

  testWidgets('highlightStart 超过文本长度 → build 内 clamp，不抛异常', (tester) async {
    await tester.pumpWidget(_wrap(const ListenFollowHighlight(
      text: '短文本',
      highlightStart: 999,
      highlightEnd: 1000,
      autoScroll: false,
    )));
    expect(find.byKey(const Key('listen-follow-text')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final rich = tester.widget<RichText>(
      find.byKey(const Key('listen-follow-text')),
    );
    final span = rich.text as TextSpan;
    // start/end 均 clamp 到 text.length → 三段中前两段为空，末段为空串
    final children = span.children!.cast<TextSpan>();
    expect(children[0].text, '短文本');
    expect(children[1].text, '');
    expect(children[2].text, '');
  });
}
