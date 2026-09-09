/// 分页控件抽象与翻页决策编排（REQ-007 · ADR D4）。
///
/// 根因：`_page` 依赖 `_pagedKey.currentState`（真实 WebView state），widget/单测
/// 环境不可用 → "章内翻页不跳章、章末才续章"无法验收。把该编排抽为可注入接口后，
/// 用 fake controls + spy `goChapter` 即可单测。
library;

/// 分页视图对外操作契约（生产由 `PagedWebViewState` 实现）。
abstract class PagedViewControls {
  /// 下一页；返回 false 表示已在章末（需续章）。
  Future<bool> nextPage();

  /// 上一页；返回 false 表示已在章首（需续章）。
  Future<bool> prevPage();

  /// 当前章总页数。
  Future<int> pageCount();

  /// 跳转到指定页。
  Future<bool> gotoPage(int index);

  /// 立即重排（不等待重载门）。
  Future<void> relayout();

  /// 新文档载入完成后再重排（切章重载时序，见 D2）。
  Future<void> relayoutAfterLoad();
}

/// 翻页决策：章内翻页成功则不跳章；失败（章首/章末）才 `goChapter(delta)`。
class PageTurnCoordinator {
  PageTurnCoordinator({required this.controls, required this.goChapter});

  final PagedViewControls controls;
  final void Function(int delta) goChapter;

  /// delta<0 上一页，delta>0 下一页。
  Future<void> page(int delta) async {
    final ok = delta < 0 ? await controls.prevPage() : await controls.nextPage();
    if (!ok) goChapter(delta);
  }
}
