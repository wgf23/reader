/// 分页文档重载与载入完成门（REQ-007 · ADR D2）。
///
/// 根因 R2-1：`PagedWebView.didUpdateWidget` 只处理 `fontSize/theme`，
/// `InAppWebView.initialData` 仅作为创建参数生效 → 切章后 WebView 仍显示旧章。
///
/// 本文件把"是否重载 / 重载参数 / 样式分支"抽为可注入出口，使 US-6 在无
/// WebView 环境（Linux 单测）可断言：href/html 变化 → `loadData(newHtml,
/// baseUrl: reader://book/{bookId}/)`；仅样式变化 → `applyStyle`；都不变 → 幂等。
library;

import 'dart:async';

/// 一次 `didUpdateWidget` 的处理结果。
enum PagedReloadOutcome {
  /// href/html 与样式均未变化（幂等，不重载、不重排）。
  none,

  /// 仅样式变化（走既有 `_applyStyle`，不重载文档）。
  styled,

  /// href/html 变化 → 已触发新文档加载。
  reloaded,
}

/// 重载出口（生产注入 `controller.loadData`；测试注入 spy）。
typedef PagedLoadData = Future<void> Function({
  required String html,
  required String baseUrl,
});

/// 样式出口（生产注入 `_applyStyle`；测试注入 spy）。
typedef PagedApplyStyle = Future<void> Function({
  required int fontSize,
  required String theme,
});

/// 分页文档重载决策器。
class PagedDocumentReloader {
  PagedDocumentReloader({
    required PagedLoadData loadData,
    required PagedApplyStyle applyStyle,
  })  : _loadData = loadData,
        _applyStyle = applyStyle;

  final PagedLoadData _loadData;
  final PagedApplyStyle _applyStyle;

  /// href 或 html 任一变化即需重载。
  static bool shouldReload({
    required String oldHref,
    required String newHref,
    required String oldHtml,
    required String newHtml,
  }) =>
      oldHref != newHref || oldHtml != newHtml;

  /// 分页文档 baseUrl：`reader://book/{bookId}/`（与初始加载一致）。
  static String baseUrlFor(String bookId) => 'reader://book/$bookId/';

  /// `didUpdateWidget` 委托入口：重载优先于样式；都不变则幂等。
  Future<PagedReloadOutcome> onWidgetUpdated({
    required String oldHref,
    required String newHref,
    required String oldHtml,
    required String newHtml,
    required String bookId,
    required int oldFontSize,
    required int fontSize,
    required String oldTheme,
    required String theme,
  }) async {
    if (shouldReload(
      oldHref: oldHref,
      newHref: newHref,
      oldHtml: oldHtml,
      newHtml: newHtml,
    )) {
      await _loadData(html: newHtml, baseUrl: baseUrlFor(bookId));
      return PagedReloadOutcome.reloaded;
    }
    if (oldFontSize != fontSize || oldTheme != theme) {
      await _applyStyle(fontSize: fontSize, theme: theme);
      return PagedReloadOutcome.styled;
    }
    return PagedReloadOutcome.none;
  }
}

/// 重载完成门：保证"新文档载入完成（onLoadStop）后再 relayout"的时序可断言。
class PagedLoadGate {
  Completer<void>? _completer;

  /// 是否处于"已 begin 且尚未 complete"的挂起态。
  bool get pending => _completer != null && !_completer!.isCompleted;

  /// begin 后未 complete 时挂起；否则立即完成。
  Future<void> get done => _completer?.future ?? Future<void>.value();

  /// 开始一次重载（在 `loadData` 前调用）。
  void begin() {
    _completer = Completer<void>();
  }

  /// 新文档载入完成（`onLoadStop` 末尾调用），放行 [done]。
  void complete() {
    final c = _completer;
    if (c != null && !c.isCompleted) c.complete();
  }
}
