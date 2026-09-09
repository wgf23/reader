/// 正文手势命中策略（REQ-007 · ADR D1）。
///
/// 根因 R1-1：`SelectableRegion` 内部的触摸/鼠标识别器在命中文字时赢得 tap
/// 竞技场，父层 `GestureDetector.onTapUp` 不再触发 → 真机点正文（几乎总在文字上）
/// 无法呼出顶底栏。
///
/// 解法：把"是否算一次 tap"与"tap 落到哪个命中区"抽为纯逻辑，由**不参与竞技场**
/// 的 `Listener` 驱动（`Listener` 必然收到 pointer 事件，无论子 `SelectableRegion`
/// 是否赢得竞技场）。命中区语义逐字对齐 `reader_page.dart` 既有 `_onBodyTapUp`。
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 一次正文 tap 的目标动作。
enum BodyTapAction {
  /// 分页模式左边缘 15% → 上一页（章内翻页，章末由 coordinator 续章）。
  prevPage,

  /// 分页模式右边缘 15% → 下一页（章内翻页，章末由 coordinator 续章）。
  nextPage,

  /// 中部 1/3 → 呼出/隐藏顶底栏。
  toggleChrome,

  /// 其余正文区域 → 收起选中工具条并隐藏 Chrome。
  dismiss,
}

/// 命中区解析：逐字对齐既有 `_onBodyTapUp` 语义（`reader_page.dart:181-209`）。
///
/// - 分页模式 `relX<0.15` → [BodyTapAction.prevPage]；
/// - 分页模式 `relX>0.85` → [BodyTapAction.nextPage]；
/// - `0.33<relX<0.67 && 0.25<relY<0.75` → [BodyTapAction.toggleChrome]；
/// - 其余 → [BodyTapAction.dismiss]。
///
/// [chromeVisible]/[hasSelection] 是调用方处理 [BodyTapAction.dismiss] 所需的当前
/// 状态（是否隐藏 Chrome / 是否清空选中），命中区判定本身与二者无关。
BodyTapAction resolveBodyTap({
  required Offset local,
  required Size size,
  required bool pagedMode,
  required bool chromeVisible,
  required bool hasSelection,
}) {
  if (size.width <= 0 || size.height <= 0) return BodyTapAction.dismiss;
  final relX = local.dx / size.width;
  final relY = local.dy / size.height;
  if (pagedMode && relX < 0.15) return BodyTapAction.prevPage;
  if (pagedMode && relX > 0.85) return BodyTapAction.nextPage;
  if (relX > 0.33 && relX < 0.67 && relY > 0.25 && relY < 0.75) {
    return BodyTapAction.toggleChrome;
  }
  return BodyTapAction.dismiss;
}

/// 手动 tap 判定（不进手势竞技场，ADR D1）。
///
/// 判定一次 tap 的四个条件：
/// 1. 单指（第二指按下即失效）；
/// 2. 主键（`buttons & kPrimaryButton != 0`）；
/// 3. 位移 ≤ [slop]（默认 `kTouchSlop` = 18.0）；
/// 4. 时长 ≤ [maxDuration]（默认 `kLongPressTimeout` = 500ms）。
///
/// 时长判定同时用两条路径，保证生产与测试一致：
/// - 事件 `timeStamp` 差值（真实平台时间戳；纯单测用构造事件断言）；
/// - 按下即启动的 [Timer]（widget/integration 测试的合成事件时间戳恒为 0，
///   由 `tester.longPress` 推进假时钟触发，与 Flutter 识别器同构）。
class BodyTapTracker {
  BodyTapTracker({this.slop = kTouchSlop, this.maxDuration = kLongPressTimeout});

  /// 位移阈值（px），默认 Flutter 官方 `kTouchSlop`。
  final double slop;

  /// 长按阈值，默认 Flutter 官方 `kLongPressTimeout`。
  final Duration maxDuration;

  int? _pointer;
  Offset? _start;
  Duration? _downAt;
  bool _valid = false;
  Timer? _longPressTimer;
  final Set<int> _active = <int>{};

  /// 是否正在跟踪一次候选 tap。
  bool get isTracking => _pointer != null;

  /// 按下：仅单指 + 主键开始跟踪；否则本次手势不是 tap。
  void onPointerDown(PointerDownEvent event) {
    _active.add(event.pointer);
    if (_active.length > 1 || (event.buttons & kPrimaryButton) == 0) {
      _valid = false;
      return;
    }
    _pointer = event.pointer;
    _start = event.localPosition;
    _downAt = event.timeStamp;
    _valid = true;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(maxDuration, () {
      if (_pointer == event.pointer) _valid = false;
    });
  }

  /// 移动：位移超过 [slop] 即失效（滚动 / 选柄拖拽 / 横向选词）。
  void onPointerMove(PointerMoveEvent event) {
    if (!_valid || event.pointer != _pointer) return;
    final start = _start;
    if (start != null && (event.localPosition - start).distance > slop) {
      _valid = false;
    }
  }

  /// 取消：系统夺走指针（弹窗等），本次不是 tap。
  void onPointerCancel(PointerCancelEvent event) {
    _active.remove(event.pointer);
    if (event.pointer == _pointer) _clearCurrent();
  }

  /// 抬起：返回 true 表示这是一次 tap（满足单指/主键/位移/时长四条件）。
  bool onPointerUp(PointerUpEvent event) {
    _active.remove(event.pointer);
    if (event.pointer != _pointer) return false;
    final start = _start;
    final downAt = _downAt;
    final withinTime = downAt != null && event.timeStamp - downAt <= maxDuration;
    final withinSlop = start != null && (event.localPosition - start).distance <= slop;
    final ok = _valid && withinTime && withinSlop;
    _clearCurrent();
    return ok;
  }

  /// 释放计时器（页面 dispose 时调用，避免悬挂定时器）。
  void dispose() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _clearCurrent() {
    _pointer = null;
    _start = null;
    _downAt = null;
    _valid = false;
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }
}
