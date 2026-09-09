/// 阅读进度落盘：尾沿防抖（REQ-008 · ADR D6 / US-3）。
///
/// 分层：`app/lib/pages` = interface；只 import `dart:async`，不触碰桥接生成物。
///
/// 语义：
/// - [schedule]：记录最新位置并重置 [debounce] 计时器（**尾沿**）；到期以"最后一次"值落盘。
/// - [flush]：立即落盘并取消挂起计时器（切章/进度条松手/目录/听书返回/切模式/dispose）。
/// - [dispose]：仅释放计时器（不落盘；退出强刷由调用方显式 `flush`）。
library;

import 'dart:async';

/// 落盘回调（href + 章内 progression）。
typedef ProgressSave = Future<void> Function(String href, double progression);

/// 尾沿防抖落盘器（D6 / US-3）。
class ProgressSaver {
  ProgressSaver({
    required ProgressSave save,
    this.debounce = const Duration(milliseconds: 300),
  }) : _save = save;

  final ProgressSave _save;
  final Duration debounce;

  Timer? _timer;
  String? _pendingHref;
  double? _pendingProgression;

  /// 记录最新位置并重置尾沿计时器；到期以最后一次值落盘。
  void schedule(String href, double progression) {
    _pendingHref = href;
    _pendingProgression = progression;
    _timer?.cancel();
    _timer = Timer(debounce, _fire);
  }

  /// 立即落盘并取消计时器（使用入参值，不依赖挂起值）。
  Future<void> flush(String href, double progression) async {
    _cancelPending();
    await _save(href, progression);
  }

  /// 释放计时器（dispose）。挂起的尾沿值不落盘；退出强刷由调用方显式 `flush`。
  void dispose() {
    _cancelPending();
  }

  void _fire() {
    _timer = null;
    final href = _pendingHref;
    final progression = _pendingProgression;
    _pendingHref = null;
    _pendingProgression = null;
    if (href == null || progression == null) return;
    _save(href, progression);
  }

  void _cancelPending() {
    _timer?.cancel();
    _timer = null;
    _pendingHref = null;
    _pendingProgression = null;
  }
}
