/// 分页 WebView 引擎（REQ-001 / ADR-001）。
///
/// 系统 WebView + CSS columns 分页（Readium Navigator 模式，docs/02 §4.1）：
/// - 章节 HTML 经 `reader://book/{bookId}/{path}` baseUrl 加载；
/// - `shouldInterceptRequest` 拦截该 scheme，从 Rust 核心取资源字节（图片/CSS/字体）；
/// - 注入分页 JS：CSS 多列排版 → 页断点表 → 翻页 = 视口平移（零重排，60fps）；
/// - 字号/主题注入根样式后重排，用文本锚/进度重新定位（不漂移）。
///
/// 注意：本组件只能在真实平台运行（依赖系统 WebView）；widget 测试注入 fake 构建器。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/library_backend.dart';
import 'paged_document_reloader.dart';
import 'paged_js_result.dart';
import 'paged_view_controls.dart';

/// 分页 WebView 的 `InAppWebViewSettings` 工厂（REQ-005 · ADR 决策点2，US-19）。
///
/// `build()` 与 widget 测试共用同一工厂，避免"测的常量与用的常量漂移"：
/// - `disableContextMenu: true` 仅抑制 Android 系统 `ActionMode` 浮动菜单（插件 `return actionMode`），
///   不禁用文本选择，选区仍经 `selectionchange` 回传（US-20）；
/// - `disableContextMenu` 可选参数为将来桌面/iOS 差异化留口（默认同开）。
InAppWebViewSettings buildPagedWebViewSettings({
  bool disableContextMenu = true,
}) =>
    InAppWebViewSettings(
      useShouldInterceptRequest: true,
      transparentBackground: false,
      disableContextMenu: disableContextMenu,
    );

/// 分页 WebView 控件
class PagedWebView extends StatefulWidget {
  const PagedWebView({
    super.key,
    required this.bookId,
    required this.href,
    required this.html,
    required this.backend,
    this.fontSize = 16,
    this.theme = 'light',
    this.onProgress,
    this.onSelectedText,
  });

  final String bookId;
  final String href;
  final String html;
  final LibraryBackend backend;
  final int fontSize;
  final String theme;

  /// 章内进度回调（0..1，由分页 JS 上报）
  final ValueChanged<double>? onProgress;

  /// REQ-003：选区文本回传（最小选区机制，ADR 决策点2；`selectionchange` JS 监听上报）
  final ValueChanged<String>? onSelectedText;

  @override
  State<PagedWebView> createState() => PagedWebViewState();
}

/// 对外暴露 next/prev/goto/relayout 供阅读器页调用
class PagedWebViewState extends State<PagedWebView> implements PagedViewControls {
  InAppWebViewController? _controller;
  late final PagedDocumentReloader _reloader;
  final PagedLoadGate _loadGate = PagedLoadGate();
  PagedJsExecutor? _js;

  static const _scheme = 'reader://book/';

  @override
  void initState() {
    super.initState();
    _reloader = PagedDocumentReloader(
      loadData: ({required String html, required String baseUrl}) async {
        final c = _controller;
        if (c == null) return;
        await c.loadData(data: html, baseUrl: WebUri(baseUrl));
      },
      applyStyle: ({required int fontSize, required String theme}) => _applyStyle(),
    );
  }

  @override
  void didUpdateWidget(PagedWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // REQ-007 D2：href/html 变化 → 重载新文档；仅样式变化 → _applyStyle；都不变 → 幂等。
    final reloading = PagedDocumentReloader.shouldReload(
      oldHref: oldWidget.href,
      newHref: widget.href,
      oldHtml: oldWidget.html,
      newHtml: widget.html,
    );
    if (reloading) _loadGate.begin();
    _reloader.onWidgetUpdated(
      oldHref: oldWidget.href,
      newHref: widget.href,
      oldHtml: oldWidget.html,
      newHtml: widget.html,
      bookId: widget.bookId,
      oldFontSize: oldWidget.fontSize,
      fontSize: widget.fontSize,
      oldTheme: oldWidget.theme,
      theme: widget.theme,
    );
  }

  Future<void> _applyStyle() async {
    final c = _controller;
    if (c == null) return;
    await c.evaluateJavascript(
      source:
          'readerPager.applyStyle(${widget.fontSize}, "${widget.theme}"); readerPager.relayout();',
    );
  }

  Future<WebResourceResponse?> _intercept(
      InAppWebViewController controller, WebResourceRequest request) async {
    final url = request.url.toString();
    if (!url.startsWith(_scheme)) return null;
    final rest = url.substring(_scheme.length);
    final slash = rest.indexOf('/');
    if (slash <= 0) return null;
    final bookId = Uri.decodeComponent(rest.substring(0, slash));
    final path = Uri.decodeComponent(rest.substring(slash + 1));
    try {
      final data = await widget.backend.resource(bookId, path);
      return WebResourceResponse(contentType: _mime(path), data: data);
    } catch (_) {
      return null;
    }
  }

  Future<void> _onLoadStop(InAppWebViewController c, WebUri? _) async {
    await c.evaluateJavascript(source: paginationJs);
    await _applyStyle();
    // REQ-007 D2：新文档（含切章重载）就绪后放行 relayoutAfterLoad。
    _loadGate.complete();
  }

  /// JS → Dart 回调：`readerFlutter`（进度）与 `selectedText`（选区文本，REQ-003）。
  /// flutter_inappwebview 6.x：经 `addJavaScriptHandler` 在控制器上注册。
  void _registerJsHandlers(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'readerFlutter',
      callback: (args) {
        final p = args.isNotEmpty ? args[0] : null;
        widget.onProgress?.call(p is num ? p.toDouble() : 0.0);
        return null;
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'selectedText',
      callback: (args) {
        final text = args.isNotEmpty ? args[0] : null;
        if (text is String && text.isNotEmpty) {
          widget.onSelectedText?.call(text);
        }
        return null;
      },
    );
  }

  // ---- 对外操作（阅读器页调用；REQ-007 D3/D4） ----
  @override
  Future<bool> nextPage() =>
      _js?.runBool('readerPager.next()') ?? Future<bool>.value(false);

  @override
  Future<bool> prevPage() =>
      _js?.runBool('readerPager.prev()') ?? Future<bool>.value(false);

  @override
  Future<bool> gotoPage(int index) =>
      _js?.runBool('readerPager.goto($index)') ?? Future<bool>.value(false);

  /// 当前章总页数（REQ-004：进度条拖动 → 分页按 progression 精确跳页）。
  @override
  Future<int> pageCount() =>
      _js?.runInt('readerPager.pageCount()') ?? Future<int>.value(1);

  @override
  Future<void> relayout() async {
    final c = _controller;
    if (c == null) return;
    await c.evaluateJavascript(source: 'readerPager.relayout()');
  }

  /// REQ-007 D2：若切章重载进行中，先等新文档载入完成（`onLoadStop`）再重排。
  @override
  Future<void> relayoutAfterLoad() async {
    if (_loadGate.pending) await _loadGate.done;
    await relayout();
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialData: InAppWebViewInitialData(
        data: widget.html,
        baseUrl: WebUri('$_scheme${widget.bookId}/'),
      ),
      initialSettings: buildPagedWebViewSettings(),
      onWebViewCreated: (c) {
        _controller = c;
        _js = PagedJsExecutor((source) => c.evaluateJavascript(source: source));
        _registerJsHandlers(c);
      },
      shouldInterceptRequest: _intercept,
      onLoadStop: _onLoadStop,
      onConsoleMessage: (_, __) {},
    );
  }
}

/// 分页脚本：CSS columns → 页断点 → 翻页（视口平移）。
/// JS 通过 `window.flutter_inappwebview.callHandler('readerFlutter', progression)`
/// 向 Dart 上报章内进度。
const String paginationJs = r'''
(function () {
  if (window.readerPager) return window.readerPager;
  var html = document.documentElement;
  var body = document.body;
  var vw = 0, columns = 1, current = 0;
  function applyStyle(fontSize, theme) {
    html.style.fontSize = fontSize + 'px';
    html.style.overflow = 'hidden';
    body.style.margin = '0';
    body.style.padding = '0 24px';
    if (theme === 'dark') { body.style.background = '#121212'; body.style.color = '#e0e0e0'; }
    else if (theme === 'sepia') { body.style.background = '#f5ecd9'; body.style.color = '#3b2f1f'; }
    else { body.style.background = '#ffffff'; body.style.color = '#202124'; }
  }
  function report() {
    var p = columns > 0 ? current / columns : 0;
    try { window.flutter_inappwebview.callHandler('readerFlutter', p); } catch (e) {}
  }
  function render() {
    body.style.transform = 'translateX(' + (-current * vw) + 'px)';
    report();
  }
  function relayout() {
    vw = html.clientWidth - 48;
    body.style.columnWidth = vw + 'px';
    body.style.columnGap = '0px';
    body.style.width = 'auto';
    body.style.transform = 'none';
    columns = Math.max(1, Math.ceil(body.scrollWidth / vw));
    current = Math.min(current, columns - 1);
    render();
    return columns;
  }
  var api = {
    applyStyle: applyStyle,
    relayout: relayout,
    pageCount: function () { return columns; },
    current: function () { return current; },
    goto: function (i) { current = Math.max(0, Math.min(columns - 1, i)); render(); return true; },
    next: function () { if (current < columns - 1) { current++; render(); return true; } return false; },
    prev: function () { if (current > 0) { current--; render(); return true; } return false; }
  };
  window.readerPager = api;
  window.addEventListener('load', function () {
    try { window.readerPager.applyStyle(16, 'light'); window.readerPager.relayout(); } catch (e) {}
  });
  // REQ-003：最小选区回传（ADR 决策点2）——选区文本非空时经 callHandler 上报
  document.addEventListener('selectionchange', function () {
    try {
      var sel = window.getSelection();
      var txt = sel ? sel.toString() : '';
      if (txt && txt.trim().length > 0) {
        window.flutter_inappwebview.callHandler('selectedText', txt);
      }
    } catch (e) {}
  });
  return api;
})();
''';

String _mime(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.svg')) return 'image/svg+xml';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.css')) return 'text/css';
  if (lower.endsWith('.woff2')) return 'font/woff2';
  if (lower.endsWith('.woff')) return 'font/woff';
  if (lower.endsWith('.ttf')) return 'font/ttf';
  if (lower.endsWith('.otf')) return 'font/otf';
  return 'application/octet-stream';
}
