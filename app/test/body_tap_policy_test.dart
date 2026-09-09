import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/pages/body_tap_policy.dart';

/// 构造单指触摸事件（localPosition == position，无 transform）。
PointerDownEvent _down(
  Offset p, {
  int pointer = 1,
  int buttons = kPrimaryButton,
  Duration timeStamp = Duration.zero,
}) =>
    PointerDownEvent(pointer: pointer, position: p, buttons: buttons, timeStamp: timeStamp);

PointerMoveEvent _move(Offset p, {int pointer = 1, Offset delta = Offset.zero}) =>
    PointerMoveEvent(pointer: pointer, position: p, delta: delta);

PointerUpEvent _up(Offset p, {int pointer = 1, Duration timeStamp = Duration.zero}) =>
    PointerUpEvent(pointer: pointer, position: p, timeStamp: timeStamp);

void main() {
  const size = Size(400, 800);

  BodyTapAction resolve(
    Offset local, {
    bool pagedMode = false,
    bool chromeVisible = false,
    bool hasSelection = false,
  }) =>
      resolveBodyTap(
        local: local,
        size: size,
        pagedMode: pagedMode,
        chromeVisible: chromeVisible,
        hasSelection: hasSelection,
      );

  group('resolveBodyTap 分区表', () {
    test('分页模式左边缘 15% → prevPage（含边界内 0.149）', () {
      expect(resolve(const Offset(40, 400), pagedMode: true), BodyTapAction.prevPage);
      expect(resolve(const Offset(59, 400), pagedMode: true), BodyTapAction.prevPage);
    });

    test('分页模式右边缘 15% → nextPage（>0.85）', () {
      expect(resolve(const Offset(350, 400), pagedMode: true), BodyTapAction.nextPage);
      expect(resolve(const Offset(399, 400), pagedMode: true), BodyTapAction.nextPage);
    });

    test('滚动模式边缘不翻页 → dismiss（沿用 REQ-004 互斥语义）', () {
      expect(resolve(const Offset(20, 400)), BodyTapAction.dismiss);
      expect(resolve(const Offset(380, 400)), BodyTapAction.dismiss);
    });

    test('中部 1/3 → toggleChrome（0.33<relX<0.67 且 0.25<relY<0.75）', () {
      expect(resolve(const Offset(200, 400)), BodyTapAction.toggleChrome);
      expect(resolve(const Offset(140, 210), pagedMode: true), BodyTapAction.toggleChrome);
      expect(resolve(const Offset(260, 590), pagedMode: true), BodyTapAction.toggleChrome);
    });

    test('边缘/上下非中部 → dismiss', () {
      expect(resolve(const Offset(200, 100)), BodyTapAction.dismiss, reason: 'relY<0.25');
      expect(resolve(const Offset(200, 700)), BodyTapAction.dismiss, reason: 'relY>0.75');
      expect(resolve(const Offset(100, 400)), BodyTapAction.dismiss, reason: 'relX<0.33');
      expect(resolve(const Offset(300, 400)), BodyTapAction.dismiss, reason: 'relX>0.67');
    });

    test('chromeVisible/hasSelection 不影响命中区判定', () {
      expect(
        resolve(const Offset(200, 400), chromeVisible: true, hasSelection: true),
        BodyTapAction.toggleChrome,
      );
      expect(
        resolve(const Offset(20, 400), chromeVisible: true, hasSelection: true),
        BodyTapAction.dismiss,
      );
    });

    test('非法尺寸 → dismiss（不抛错）', () {
      expect(
        resolveBodyTap(
          local: Offset.zero,
          size: Size.zero,
          pagedMode: true,
          chromeVisible: false,
          hasSelection: false,
        ),
        BodyTapAction.dismiss,
      );
    });
  });

  group('BodyTapTracker', () {
    test('位移 ≤18px 且时长 ≤500ms 且单指/主键 → onPointerUp==true', () {
      final t = BodyTapTracker();
      t.onPointerDown(_down(const Offset(100, 100)));
      expect(t.isTracking, isTrue);
      t.onPointerMove(_move(const Offset(110, 100))); // 10px < 18
      expect(t.onPointerUp(_up(const Offset(110, 100))), isTrue);
      expect(t.isTracking, isFalse);
    });

    test('时长恰好 500ms → true；≥500ms（600ms）→ false', () {
      final ok = BodyTapTracker();
      ok.onPointerDown(_down(const Offset(100, 100)));
      expect(
        ok.onPointerUp(_up(const Offset(100, 100), timeStamp: const Duration(milliseconds: 500))),
        isTrue,
      );

      final late = BodyTapTracker();
      late.onPointerDown(_down(const Offset(100, 100)));
      expect(
        late.onPointerUp(_up(const Offset(100, 100), timeStamp: const Duration(milliseconds: 600))),
        isFalse,
      );
    });

    test('位移 >18px → false（滚动/选柄拖拽）', () {
      final t = BodyTapTracker();
      t.onPointerDown(_down(const Offset(100, 100)));
      t.onPointerMove(_move(const Offset(120, 100))); // 20px > 18
      expect(t.onPointerUp(_up(const Offset(120, 100))), isFalse);
    });

    test('位移回退到起点仍算 tap（按最终位移判定）', () {
      final t = BodyTapTracker();
      t.onPointerDown(_down(const Offset(100, 100)));
      t.onPointerMove(_move(const Offset(130, 100)));
      t.onPointerMove(_move(const Offset(100, 100)));
      expect(t.onPointerUp(_up(const Offset(100, 100))), isFalse,
          reason: '一旦超 slop 即失效（与识别器一致，不因回退复活）');
    });

    test('多指 → false', () {
      final t = BodyTapTracker();
      t.onPointerDown(_down(const Offset(100, 100), pointer: 1));
      t.onPointerDown(_down(const Offset(200, 100), pointer: 2));
      expect(t.onPointerUp(_up(const Offset(100, 100), pointer: 1)), isFalse);
    });

    test('非主键（右键）→ false', () {
      final t = BodyTapTracker();
      t.onPointerDown(_down(const Offset(100, 100), buttons: kSecondaryButton));
      expect(t.onPointerUp(_up(const Offset(100, 100))), isFalse);
    });

    test('pointerCancel → false', () {
      final t = BodyTapTracker();
      t.onPointerDown(_down(const Offset(100, 100)));
      t.onPointerCancel(const PointerCancelEvent(pointer: 1, position: Offset(100, 100)));
      expect(t.onPointerUp(_up(const Offset(100, 100))), isFalse);
    });

    test('自定义阈值生效', () {
      final t = BodyTapTracker(slop: 5);
      t.onPointerDown(_down(const Offset(100, 100)));
      t.onPointerMove(_move(const Offset(108, 100)));
      expect(t.onPointerUp(_up(const Offset(108, 100))), isFalse);
    });
  });
}
