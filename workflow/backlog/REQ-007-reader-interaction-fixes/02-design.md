<!-- wf-meta: req=REQ-007-reader-interaction-fixes | phase=architecture | agent=architect | date=2026-09-09 | gate=passed -->
# REQ-007 · 模块/接口设计（手势可达性 / 分页重载 / JS 解析 / 翻页决策 / 翻译引导 / 真实集成测试）

> 依据：`01-req.md`（US-1..US-17 + R1-1/R1-2/R2-1/R2-2/R2-3/R3-1/R3-2/R3-3）、`02-adr.md`（D1..D6）。
> DDD 分层标注：**interface** = `core/src/api.rs`、`app/lib/pages`、`app/lib/engines`（禁 import `package:reader_app/src/rust/`、`src/rust/`）；**application** = `core/src/library`、`app/lib/services`；**domain** = `core/src/dict` 等（禁依赖 `crate::store/api/library`）；**infrastructure** = `core/src/store`、`app/lib/src/rust`。
> 硬约束：零 schema 变更、零新增依赖、零布局自创。

---

## 1. 模块与职责变化

| 模块 | 层 | 变化 | 对应决策 |
|---|---|---|---|
| `app/lib/pages/body_tap_policy.dart` | interface（新） | `BodyTapAction` + `resolveBodyTap(...)` + `BodyTapTracker`：手动 tap 判定与命中区解析（纯逻辑） | D1 |
| `app/lib/pages/reader_page.dart` | interface（改） | 移除外层 `GestureDetector.onTapUp`，由既有 `Listener` 承载 tap 判定；`_applyTap` 替代 `_onBodyTapUp`；`_page` 委托 `PageTurnCoordinator`；错误浮层按"未配置"传 `onOpenSettings`；新增 `_openTranslateSettings`；新增可选 `pagedControls` | D1/D4/D5 |
| `app/lib/engines/paged_document_reloader.dart` | interface（新） | `PagedDocumentReloader`（`shouldReload` 纯函数 + 可注入 `loadData/applyStyle`）+ `PagedLoadGate`（重载完成门） | D2 |
| `app/lib/engines/paged_web_view.dart` | interface（改） | `didUpdateWidget` 委托 reloader；`onLoadStop` 末尾完成 gate；`PagedWebViewState implements PagedViewControls`；`_runBool` 改委托 `PagedJsExecutor`；`pageCount` 改 `runInt`；新增 `relayoutAfterLoad` | D2/D3/D4 |
| `app/lib/engines/paged_js_result.dart` | interface（新） | `parseJsBool` 纯函数 + `PagedJsExecutor`（可注入 evaluator） | D3 |
| `app/lib/engines/paged_view_controls.dart` | interface（新） | `PagedViewControls` 抽象 + `PageTurnCoordinator`（章内/章末编排） | D4 |
| `app/lib/widgets/translation_popup.dart` | interface（改，未在 ddd-rules 声明） | `OverlayError` 增可选 `onOpenSettings`/`openSettingsLabel`；顶层谓词 `isTranslationNotConfiguredError` | D5 |
| `app/lib/pages/settings_page.dart` | interface（零改动） | 作为"去设置"目标被 push，接收注入的 `translateBackend` | D5 |
| `core/src/dict/translation.rs` | domain（改） | US-11 错误文案**追加**"设置"引导（`translate_auto` 的 `NotConfigured` 分支）；策略/回退/缓存逻辑零改动 | D5 |
| `app/lib/services/*` | application（零改动） | `TranslateBackend` 契约不变；`SettingsPage` 复用注入 backend | D5 |
| `app/test/*`、`app/integration_test/*` | 测试（改/新） | 见 §6 | D1..D6 |

---

## 2. 接口签名（Rust / Dart）

### 2.1 Rust（domain，唯一改动：文案追加，无签名变化）

```rust
// core/src/dict/translation.rs:562-567（translate_auto 的"无 key + 离线未命中"分支）
if online_unconfigured || online.is_empty() {
    let pname = first_unconfigured.unwrap_or_else(|| "deepl".to_string());
    return Err(Error::NotConfigured(format!(
        // 原三段语义逐字保留，仅追加"设置"引导（US-11 断言三段子串并存）
        "未配置在线翻译 API Key（{pname}），且离线翻译未命中（请先安装内置词库）\
         ；请在「设置」中配置在线翻译或导入词库"
    )));
}
// Error::NotConfigured Display 前缀 "翻译服务未配置："（core/src/error.rs:31-33）不变；
// translate_routed/translate_auto/translate_explicit/缓存键/FALLBACK_REASON_* 全部不变；
// 无新增 FFI/DTO → 无 FRB 再生成。
```

### 2.2 Dart — 手势（interface）

```dart
// app/lib/pages/body_tap_policy.dart（新）
enum BodyTapAction { prevPage, nextPage, toggleChrome, dismiss }

/// 命中区解析：逐字对齐 reader_page.dart:181-209 的既有语义。
BodyTapAction resolveBodyTap({
  required Offset local,        // PointerUpEvent.localPosition（相对 body）
  required Size size,           // LayoutBuilder constraints.biggest
  required bool pagedMode,
  required bool chromeVisible,
  required bool hasSelection,
});

/// 手动 tap 判定：不进手势竞技场（D1）。
class BodyTapTracker {
  BodyTapTracker({this.slop = kTouchSlop, this.maxDuration = kLongPressTimeout});
  final double slop;                 // 18.0
  final Duration maxDuration;        // 500ms
  bool get isTracking;
  void onPointerDown(PointerDownEvent e);   // 仅主键、单指；记录起点/时间戳
  void onPointerMove(PointerMoveEvent e);   // 超 slop 即失效
  void onPointerCancel(PointerCancelEvent e);
  bool onPointerUp(PointerUpEvent e);       // true=一次 tap（位移<=slop 且时长<=maxDuration）
}
```

### 2.3 Dart — 分页重载 / JS 解析 / 翻页决策（interface）

```dart
// app/lib/engines/paged_document_reloader.dart（新）
enum PagedReloadOutcome { none, styled, reloaded }
typedef PagedLoadData = Future<void> Function({required String html, required String baseUrl});
typedef PagedApplyStyle = Future<void> Function({required int fontSize, required String theme});

class PagedDocumentReloader {
  PagedDocumentReloader({required PagedLoadData loadData, required PagedApplyStyle applyStyle});
  static bool shouldReload({required String oldHref, required String newHref,
                            required String oldHtml, required String newHtml});
  static String baseUrlFor(String bookId);   // 'reader://book/$bookId/'
  Future<PagedReloadOutcome> onWidgetUpdated({
    required String oldHref, required String newHref,
    required String oldHtml, required String newHtml,
    required String bookId,
    required int oldFontSize, required int fontSize,
    required String oldTheme, required String theme,
  });
}

/// 重载完成门：保证"新文档载入完成后再 relayout"（US-6 时序可断言代理）。
class PagedLoadGate {
  bool get pending;
  Future<void> get done;      // begin 后未 complete 时挂起
  void begin();
  void complete();
}
```

```dart
// app/lib/engines/paged_js_result.dart（新；不 import flutter_inappwebview）
bool parseJsBool(dynamic v);      // bool→原值；num→!=0；'true'/'1'→true；'false'/null/其它→false
typedef JsEvaluator = Future<dynamic> Function(String source);

class PagedJsExecutor {
  PagedJsExecutor(JsEvaluator evaluate);
  Future<bool> runBool(String source);                  // parseJsBool(await evaluate(source))
  Future<int> runInt(String source, {int fallback = 1}); // num / int.parse('$v')，<=0→fallback
}
```

```dart
// app/lib/engines/paged_view_controls.dart（新）
abstract class PagedViewControls {
  Future<bool> nextPage();
  Future<bool> prevPage();
  Future<int> pageCount();
  Future<bool> gotoPage(int index);
  Future<void> relayout();
  Future<void> relayoutAfterLoad();
}

class PageTurnCoordinator {
  PageTurnCoordinator({required PagedViewControls controls, required void Function(int delta) goChapter});
  final PagedViewControls controls;
  final void Function(int delta) goChapter;
  Future<void> page(int delta);   // ok? 不跳章 : goChapter(delta)
}
```

### 2.4 Dart — 翻译引导（interface）

```dart
// app/lib/widgets/translation_popup.dart（改）
/// "未配置"识别谓词：仅翻译未配置返回 true（查词错误不得命中）。
bool isTranslationNotConfiguredError(String message) =>
    message.contains('未配置在线翻译 API Key') || message.contains('未配置翻译后端');

class OverlayError extends StatelessWidget {
  const OverlayError({
    super.key,
    required this.message,
    required this.onRetry,
    this.onOpenSettings,                 // null → 不渲染"去设置"（现状逐字不变）
    this.openSettingsLabel = '去设置',
  });
  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onOpenSettings;
  final String openSettingsLabel;
}
```

```dart
// app/lib/pages/reader_page.dart（改）
const ReaderPage({
  ...,
  this.pagedControls,   // PagedViewControls?：测试注入 fake 分页控件（D4）
});

void _openTranslateSettings() {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => SettingsPage(translateBackend: widget.translateBackend), // R3-3：直接 push + 透传
  ));
}
```

### 2.5 生产接线（`PagedWebViewState`）

```dart
class PagedWebViewState extends State<PagedWebView> implements PagedViewControls {
  late final PagedDocumentReloader _reloader;
  final PagedLoadGate _loadGate = PagedLoadGate();
  PagedJsExecutor? _js;

  @override
  void initState() {
    super.initState();
    _reloader = PagedDocumentReloader(
      loadData: ({required html, required baseUrl}) async {
        final c = _controller;
        if (c == null) return;
        await c.loadData(data: html, baseUrl: WebUri(baseUrl));
      },
      applyStyle: ({required fontSize, required theme}) => _applyStyle(),
    );
  }

  @override
  void didUpdateWidget(PagedWebView old) {
    super.didUpdateWidget(old);
    final reloading = PagedDocumentReloader.shouldReload(
        oldHref: old.href, newHref: widget.href,
        oldHtml: old.html, newHtml: widget.html);
    if (reloading) _loadGate.begin();
    _reloader.onWidgetUpdated(
      oldHref: old.href, newHref: widget.href, oldHtml: old.html, newHtml: widget.html,
      bookId: widget.bookId,
      oldFontSize: old.fontSize, fontSize: widget.fontSize,
      oldTheme: old.theme, theme: widget.theme,
    );
  }

  Future<void> _onLoadStop(InAppWebViewController c, WebUri? _) async {
    await c.evaluateJavascript(source: paginationJs);  // 新文档重建 window.readerPager
    await _applyStyle();                                // applyStyle + relayout
    _loadGate.complete();                               // 放行 relayoutAfterLoad
  }

  @override
  Future<void> relayoutAfterLoad() async {
    if (_loadGate.pending) await _loadGate.done;
    await relayout();
  }

  @override
  Future<bool> nextPage() async => _js?.runBool('readerPager.next()') ?? false;
  @override
  Future<bool> prevPage() async => _js?.runBool('readerPager.prev()') ?? false;
  @override
  Future<int> pageCount() async => _js?.runInt('readerPager.pageCount()') ?? 1;
  // gotoPage/relayout 保持既有 evaluateJavascript 实现
}
```

---

## 3. 数据模型变化

**零变更**（预期）。逐项确认：

| 项 | 结论 |
|---|---|
| `reading_progress`（`href = chapter_%04d.xhtml` + `progression`） | 零变更；切章仍写章首 `progression=0.0`（`reader_page.dart:176`） |
| `Locator` / `TextAnchor` / `Rect`（`core/src/types.rs`） | 零变更 |
| `translation_cache`（键 `(原文, from, to, 真实 provider)`） | 零变更；失败不写缓存语义不变 |
| `settings`（`translate.default_provider` 默认 `auto`） | 零变更；无新键 |
| `user_version` / 迁移 | 零变更 |
| FRB 桥接 DTO / 生成物 | 零变更（无新 FFI） |

---

## 4. 关键时序

### 4.1 中部点击（含点在文字上）toggle 顶底栏（US-1/US-2）

```
用户手指按下（可能在文字上）
  → SelectableRegion 识别器进入竞技场（TapAndHorizontalDrag / LongPress）
  → 祖先 Listener.onPointerDown（不进竞技场，必收）：BodyTapTracker 记录 pointer/起点/时间戳
用户抬起
  ├─ 若 时长 >= kLongPressTimeout(500ms) 或 位移 > kTouchSlop(18px) 或 多指/非主键
  │     → tracker.onPointerUp 返回 false → 不 toggle（长按选中/滚动/选柄拖拽继续）
  └─ 若为一次 tap
        → resolveBodyTap(local, size, pagedMode, chromeVisible, hasSelection)
             ├─ 分页 && relX<0.15 → _page(-1)
             ├─ 分页 && relX>0.85 → _page(+1)
             ├─ 0.33<relX<0.67 && 0.25<relY<0.75 → setState(_chromeVisible = !_chromeVisible)
             └─ 其余 → 清 _selectedText/_resetPopups + 隐藏 Chrome
```
- **不误伤**：选柄在 Overlay（Listener 收不到）；进度条/Chrome 在 Stack 上层（Listener 收不到）；垂直拖拽/横向选词位移超 slop（不 toggle）。

### 4.2 分页切章重载 + relayout（US-5/US-6）

```
点底栏"下一章" / 章末边缘翻页
  → _goChapter(+1): setState(_chapterIndex=next, _chapterProgress=0.0); _saveProgress(0.0)
  → 重建 → FutureBuilder(chapterHtml(newHref)) → PagedWebView(href:new, html:new)（同 GlobalKey）
  → didUpdateWidget: shouldReload(oldHref,newHref,oldHtml,newHtml)==true → _loadGate.begin()
      → _reloader.loadData(html:newHtml, baseUrl:'reader://book/{bookId}/')  // controller.loadData
  → onLoadStop: evaluateJavascript(paginationJs) → _applyStyle() → _loadGate.complete()
  → _jumpToProgress(0.0)（分页分支）→ state.relayoutAfterLoad()（gate 已放行）→ readerPager.relayout()
  → 新章第 0 页；onProgress 上报 0.0
样式变化（fontSize/theme）：shouldReload==false → _applyStyle()（既有路径），不 loadData（幂等）
href/html 均不变：none，不重载
```

### 4.3 翻译未配置引导（US-11/US-12）

```
选中文本 → 点"翻译" → backend.translate 抛 Err(NotConfigured(含"设置"))
  → _doTranslate catch → _translationError = '$e'
  → 错误浮层：isTranslationNotConfiguredError(_translationError)==true
        → OverlayError(message, onRetry: _doTranslate, onOpenSettings: _openTranslateSettings)
        → 渲染"重试" + "去设置"
  → 点"去设置" → Navigator.push(SettingsPage(translateBackend: widget.translateBackend))
        → SettingsPage 用同一注入 backend 读/写 DeepL key 与策略（R3-3 入口打通）
查词失败：_lookupError 走 OverlayError(message, onRetry: _doLookup)（无 onOpenSettings）→ 无"去设置"
网络失败：文案不含"未配置在线翻译 API Key" → 无"去设置"（仅重试）
```

---

## 5. 逐屏映射原型图（`docs/wireframes/**` 为 UI 权威；禁止自创布局）

| 原型图 | 涉及交互 | 本设计落点 | 布局变化 |
|---|---|---|---|
| `reader-ui-v2/01-immersive.svg` | 沉浸态、中部 1/3 呼出/隐藏、左右 15% 翻页热区、长按选词 | `resolveBodyTap` 命中区与热区比例逐字保留；`Listener` 手动判定（D1） | **无**（仅修手势可达性） |
| `reader-ui-v2/02-menus.svg` | 顶栏返回/书名·章节/更多；底栏上一章·目录·进度条·书签·Aa·下一章 | `_goChapter` + 分页重载（D2）；`ReaderBottomBar` 零改动 | **无** |
| `reader-ui-v2/04-selection.svg` | 选中浮动工具条（划重点/笔记/翻译/查词/复制）+ 结果卡片 | 工具条零改动；结果卡片区域在"翻译未配置"时 `OverlayError` 多一个"去设置"按钮（D5） | **仅错误浮层 +1 按钮** |
| `08-translation.svg` | 选句翻译卡片、标签、查词卡片 | 文案追加"设置"引导；`TranslationResultCard` 标签（在线/离线/缓存）零改动（REQ-006） | **无** |
| `03-settings.svg` | 设置页（词典与翻译 / DeepL Provider + key） | "去设置"目标页；直接 push 并透传 `translateBackend`；页面本身零改动 | **无** |
| `reader-ui-v2/03-settings.svg` | Aa 显示设置面板 | 本 REQ 不涉及（零改动） | **无** |
| `docs/wireframes/README.md` | 线框清单/评审要点 | 无新增屏；无清单变更（截图清单在交付阶段同步） | — |

> 偏差目标 = 0；唯一允许的 UI 增量是 `04-selection` 结果卡片体系内错误态的一个按钮（不改变工具条/卡片/顶底栏/设置页布局）。

---

## 6. 测试分层与可测出口映射（供 02-plan 引用）

| 层 | 文件 | 覆盖 US | 可测出口 |
|---|---|---|---|
| [单测] | `app/test/body_tap_policy_test.dart` | US-2 | `BodyTapTracker`（位移/时长/多指/主键）+ `resolveBodyTap` 分区表 |
| [单测] | `app/test/paged_document_reloader_test.dart` | US-6 | `shouldReload` + spy `loadData/applyStyle` + `PagedLoadGate` |
| [单测] | `app/test/paged_js_result_test.dart` | US-7 | `parseJsBool` 全分支 + `PagedJsExecutor` 注入 fake evaluator |
| [单测] | `app/test/page_turn_coordinator_test.dart` | US-8 | fake `PagedViewControls` + spy `goChapter`（章内 true 不跳章/章末 false 跳章/左右对称） |
| [单测] | `app/test/no_synthetic_chrome_test.dart` | US-3/US-14 | 扫描 `integration_test/*.dart` 无 `ReaderTopBar(`/`ReaderBottomBar(` |
| [单测] | `core/src/dict/translation.rs` 内嵌测试 | US-10/US-11 | `translate_routed` 的 `provider=="deepl"`/`from_cache==false`；错误串含三段子串 |
| [widget] | `app/test/reader_page_test.dart` | US-2/US-4/US-5/US-9 | fake 构建器捕获 `href=='chapter_0002.xhtml'`；注入 `pagedControls` 断言边缘不 toggle；文字 center toggle |
| [widget] | `app/test/translate_reader_test.dart` | US-12/US-13 | `find.text('去设置')`、`find.byType(SettingsPage)`、注入 backend 透传；查词无"去设置"；在线/离线标签 |
| [集成测试] | `app/integration_test/reader_interaction_test.dart` | US-1/US-2/US-4/US-12 | 真实 ReaderPage + 真实 `tapAt`/`longPress`/`drag` |
| [集成测试] | `app/integration_test/screenshots_test.dart` | US-3 | 删除合成页；`reader_chrome`/`reader_more` 由真实点击文字产生 |
| [真机] | 交付清单 | US-17 | 分页模式翻页/切章/呼出/去设置 |

**平台约束**：`flutter_inappwebview` 无 Linux 实现 → `flutter test integration_test -d linux`（xvfb）只跑滚动模式；分页走 [widget 测试] + [单测]，真机由 US-17 兜底。

---

## 7. 与既有约定的兼容性

- [x] **不破坏 Locator 模型**：`Locator`/`TextAnchor`/`Rect` 零改动；分页切章仍写 `chapter_%04d.xhtml` + `progression=0.0`（US-5）。
- [x] **不跨越限界上下文**：翻译文案改动在 `core/src/dict`（domain），不新增表/上下文；分页/手势在 interface 层；无 application/infrastructure 依赖倒置。
- [x] **听读同进度不变式保持**：唯一事实源仍 `reading_progress`；手势/分页改动不触碰 `ListenPage`/`saveProgress` 语义；`_reloadProgress`（听书返回）逻辑不变。
- [x] **ddd-rules 合规**：新增 Dart 文件均在 `pages`/`engines`（interface），不 import `package:reader_app/src/rust/`、`src/rust/`；`core/src/dict` 只 `use crate::types/error/dict`；`translation_popup.dart` 未被 ddd-rules 声明，按 pages 同级纪律（沿用 REQ-005/006 处置，规则表冻结）。
- [x] **REQ-001/003/004/005/006 复用不重做**：分页渲染/进度（001）、选中→翻译/查词（003）、沉浸态/顶底栏/热区（004）、`disableContextMenu`/选区回传/听书（005）、`auto` 策略/回退标签（006）均只做可达性/引导增量；`translate_cached` 2 元组、缓存键、`fallback_reason`、错误三段子串（`contains`）全部保留。
- [x] **无新增依赖**：不新增 pub/crate；重载用插件既有 `loadData`。
- [x] **golden/截图影响已列**：错误浮层错误态（若存在 golden）+ `reader_chrome`/`reader_more` 截图落点变化 → 在 T-006/T-008 同步更新；`ui-screenshots.sh REQ-007` 退出码 0。
- [x] **零布局自创**：顶栏/底栏/工具条/设置页布局零改动；唯一增量 = 错误浮层"去设置"按钮（§5）。

---

## 8. 设计取舍与风险登记

1. **手动 tap 判定 vs 竞技场**（D1）：以 `Listener` 绕开竞技场，代价是自维护阈值；以纯函数 + [单测] 覆盖位移/时长/多指/主键矩阵，[集成测试] 用真实手势兜底。
2. **Linux 无 WebView**（风险2）：分页重载/JS 解析/翻页决策全部抽为可注入出口（D2/D3/D4），US-6/7/8 在 Linux 可验收；真机 US-17 兜底。
3. **重载时序竞态**（风险3）：`PagedLoadGate` 保证"载入完成后再 relayout"；`_jumpToProgress(0.0)` 分页分支改 `relayoutAfterLoad()`。
4. **文案子串判定**（风险5）：集中在 `isTranslationNotConfiguredError` 一处；降级线为异常类型（不改 Rust）。
5. **`OverlayError` 按钮污染**（风险6）：`onOpenSettings` 可选 + 仅翻译未配置时传值；查词结构上不传。
6. **设置页不可达/后端注入**（风险7）：直接 push + 透传 `widget.translateBackend`；null 时 `SettingsPage` 回退默认 Rust 后端（生产正确）。
7. **合成页清理**（风险8）：`no_synthetic_chrome_test.dart` 静态守卫 + 截图脚本退出码 0；清单在交付阶段同步。
