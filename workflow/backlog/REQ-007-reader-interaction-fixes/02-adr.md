<!-- wf-meta: req=REQ-007-reader-interaction-fixes | phase=architecture | agent=architect | date=2026-09-09 | gate=passed -->
# REQ-007 · 架构决策记录（ADR：中部点击手势可达性 / 分页切章重载 / JS 布尔解析 / 翻页决策可测 / 翻译未配置引导 / 真实集成测试）

## 决策（一句话）

把三个 P0 缺陷拆成**六个可独立验收的决策点**：① 用**不参与手势竞技场的 `Listener` + 手动 tap 判定**替代被 `SelectableRegion` 吞掉的 `GestureDetector.onTapUp`（阈值 `kTouchSlop`/`kLongPressTimeout`，命中区语义逐字保留）；② `PagedWebView.didUpdateWidget` 检测 `href/html` 变化后经**可测的 `PagedDocumentReloader`** 调 `controller.loadData(newHtml, baseUrl: reader://book/{bookId}/)`，`onLoadStop` 重新注入 `paginationJs` + `_applyStyle` 后再 relayout；③ 抽纯函数 `parseJsBool` + 可注入 `PagedJsExecutor` 修 `_runBool`；④ 抽 `PagedViewControls` 接口 + `PageTurnCoordinator` 使"章内翻页→章末续章"可单测；⑤ 错误文案**仅追加**"设置"引导、`OverlayError` 增**可选**"去设置"按钮（仅翻译未配置时出现），`ReaderPage` 直接 push `SettingsPage(translateBackend: widget.translateBackend)`；⑥ 新增真实 `integration_test/reader_interaction_test.dart` 并删除/改写 `screenshots_test.dart:147-179` 合成页。**零 schema 变更、零新增依赖、零布局自创**（唯一 UI 增量 = 错误浮层一个按钮）。

---

## 决策点 D1：中部点击（含点在文字上）可靠 toggle 顶底栏（R1-1/R1-2，US-1/US-2/US-3）

**现状（已核实）**：`reader_page.dart:483-492` 用 `GestureDetector(behavior: translucent, onTapUp: _onBodyTapUp)` 包 `SelectionArea`（`:594-619`）。Flutter SDK `selectable_region.dart:688-720` 在 `SelectableRegion` 内注册 `TapAndHorizontalDragGestureRecognizer`（非鼠标设备，`onTapUp: _handleMouseTapUp`）与 `:653-671` 的 `TapAndPanGestureRecognizer`（鼠标），经 `:1977-1979` 的 `RawGestureDetector` 进入竞技场；命中文字时子识别器在 pointer-up 阶段先于父 `TapGestureRecognizer` 解决竞技场 → 父 `onTapUp` 不触发（R1-1）。R1-2 的测试假阳性（`reader_page_test.dart:37-42`、`screenshots_test.dart:147-179/:247`）使缺陷长期未被发现。

### 备选

- **A（选）：父层改用 `Listener`（`onPointerDown/Up/Cancel/Move`）做手动 tap 判定，`Listener` 不进竞技场，故必然收到 pointer 事件；用纯函数 `resolveBodyTap` 保留既有命中区语义**
  - 做法：
    ```dart
    // 手动 tap 判定：位移 <= kTouchSlop(18.0) 且 时长 <= kLongPressTimeout(500ms) 且 单指/主键
    Positioned.fill(child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _tracker.down,
      onPointerMove: _tracker.move,
      onPointerUp: (e) { if (_tracker.isTap(e)) _applyTap(resolveBodyTap(...)); },
      onPointerCancel: _tracker.cancel,
      child: Container(color: bg, child: _buildArticleBody(...)), // 移除外层 GestureDetector
    )),
    ```
  - 命中区（`resolveBodyTap`，逐字对齐 `_onBodyTapUp:181-209`）：分页模式 `relX<0.15`→上一页；`relX>0.85`→下一页；`0.33<relX<0.67 && 0.25<relY<0.75`→toggleChrome；其余→`dismiss`（清选中 + 隐藏 Chrome）。
  - 优点：`Listener` 与竞技场正交，子 `SelectableRegion` 无论如何获胜都不影响 toggle；长按/拖拽/滚动/进度条拖动全部不受影响（详见命中层级图）；判定逻辑抽为纯函数，可 [单测] 断言阈值与分区。
  - 缺点：需自行维护"何为一次 tap"（位移/时长/多指/主键），实现面比一行 `onTapUp` 大；阈值需与 Flutter 常量对齐。
- **B：自定义 `RawGestureDetector` + 可获胜的 `TapGestureRecognizer`（如 `addAllowedPointer` 内 `resolve(accepted)` 抢先）**
  - 优点：仍是"手势识别器"模型，与 Flutter 语义一致。
  - 缺点：抢先接受会**同时吞掉** `SelectableRegion` 的单击（清选区/光标）与双击选词，且与 `Scrollable` 的垂直拖拽竞争窗口难以两全（过早 accept 会破坏滚动/长按）；等价于把 R1-1 的冲突反向转嫁，风险高。**拒绝**。
- **C：把 toggle 接进 `SelectionArea.onSelectionChanged` / 空白点击回调**
  - 缺点：`onSelectionChanged` 只在选区变化时触发，点空白/点文字（无选区变化）不可达；无"空白点击"回调。**不满足 US-1 第二句**。**拒绝**。
- **D：在正文之上再叠一个透明 `GestureDetector` 兄弟层**
  - 缺点：全屏透明层会拦截所有 pointer，破坏长按选中/选柄拖拽/滚动。**拒绝**。

### 选择与理由

选 **A**。US-2 的核心约束是"**不误伤**长按选中、拖拽选柄、垂直滚动、进度条拖动、边缘热区"，只有"不参与竞技场"的 `Listener` 能同时满足"必被通知"与"不抢竞技场胜利"；`SelectableRegion` 的识别器继续在竞技场内正常工作，长按选中/选柄拖拽/横向选词零回归。阈值取 Flutter 官方常量 `kTouchSlop = 18.0`、`kLongPressTimeout = 500ms`，与 SDK 长按识别器判定一致。

### 命中层级图（Stack，自顶向下）

```
┌─ Flutter Overlay（不在本 Stack 内）──────────────────────────────┐
│  SelectionOverlay：选区两端选柄 + 选区浮动工具条（04-selection） │  ← 选柄拖拽走此层，Listener 不参与
└─────────────────────────────────────────────────────────────────┘
ReaderPage.body = Stack（自顶向下）
 1. if (_chromeVisible) Positioned(top) ReaderTopBar      ┐ 点击返回/更多/底栏控件
 2. if (_chromeVisible) Positioned(bottom) ReaderBottomBar ┘ 由 Chrome 消费，body Listener 收不到
 3. if (_selectedText != null) Positioned 工具条 + 结果卡片（含 OverlayError"去设置"）
 4. Positioned.fill  Listener(behavior: translucent)          ← 手动 tap 判定（本决策）
      └─ Container(color: bg)                                ← 铺满 body，保证空白处可命中
           └─ SingleChildScrollView(_scrollController)       ← VerticalDragGestureRecognizer 仍赢垂直拖拽
                └─ SelectionArea
                     └─ SelectableRegion 内部 RawGestureDetector
                          ├─ LongPressGestureRecognizer（长按选中，500ms）
                          ├─ TapAndHorizontalDragGestureRecognizer（触摸：单击/横向拖选）
                          ├─ TapAndPanGestureRecognizer（鼠标）
                          └─ TapGestureRecognizer（右键）
```
- **手势矩阵**：长按 → 时长 ≥ `kLongPressTimeout` → `BodyTapTracker` 判非 tap（长按选中正常）；拖拽 → 位移 > `kTouchSlop` → 判非 tap（滚动/选柄正常）；选柄 → 指针命中 Overlay，Listener 根本收不到；进度条/Chrome → 命中第 1/2 层，body Listener 收不到；边缘热区 → `resolveBodyTap` 在分页模式优先返回 prev/next。

### 影响
- `reader_page.dart`：移除外层 `GestureDetector`，改由既有 `Listener` 承载 tap 判定（`_lastDataPointer` 记录职责保留）；新增 `_applyTap(BodyTapAction)` 替换 `_onBodyTapUp`；`_page` 见 D4。
- 新增 `app/lib/pages/body_tap_policy.dart`（interface）：`BodyTapAction` + `resolveBodyTap` + `BodyTapTracker`，纯逻辑可 [单测]。
- 回归面：`reader_selection_test.dart`（长按/工具条定位）、`reader_page_test.dart`（中部 toggle 落点改为文字 center）、goldens（呼出态截图落点变化）。

### 降级线（授权）
若某类指针（如手写笔/精密指针）在真机上出现"点文字被判为拖拽"或"轻扫被误判为 tap"：**降级为按 `PointerDeviceKind` 分路**——对可疑设备提高位移阈值至 `kTouchSlop * 2` 或改用 `RawGestureDetector` 的自定义 `TapGestureRecognizer`（仅对该设备类型启用），**命中区语义、阈值常量、US-1/US-2 断言不变**。禁止为此改动任何布局。

---

## 决策点 D2：分页切章重载（R2-1，US-5/US-6）

**现状（已核实）**：`PagedWebView.didUpdateWidget`（`paged_web_view.dart:70-75`）只处理 `fontSize/theme`；`InAppWebView.initialData`（`:159-163`）仅作为创建参数生效（插件无 `didUpdateWidget` 处理），故 `_chapterIndex` 变化后 WebView 仍显示旧章。控制器具备 `loadData(data, baseUrl:)`（`flutter_inappwebview_android .../in_app_webview_controller.dart:1815`）。

### 备选

- **A（选）：`didUpdateWidget` 检测 `href/html` 变化 → `controller.loadData(data: newHtml, baseUrl: WebUri('reader://book/$bookId/'))`；把"是否重载 + 重载参数 + 样式分支"抽为可注入的 `PagedDocumentReloader`**
  - 做法：
    ```dart
    // app/lib/engines/paged_document_reloader.dart（interface）
    enum PagedReloadOutcome { none, styled, reloaded }
    typedef PagedLoadData = Future<void> Function({required String html, required String baseUrl});
    typedef PagedApplyStyle = Future<void> Function({required int fontSize, required String theme});

    class PagedDocumentReloader {
      PagedDocumentReloader({required PagedLoadData loadData, required PagedApplyStyle applyStyle});
      static bool shouldReload({required String oldHref, required String newHref,
                                required String oldHtml, required String newHtml}) =>
          oldHref != newHref || oldHtml != newHtml;
      static String baseUrlFor(String bookId) => 'reader://book/$bookId/';
      Future<PagedReloadOutcome> onWidgetUpdated({
        required String oldHref, required String newHref,
        required String oldHtml, required String newHtml,
        required String bookId,
        required int oldFontSize, required int fontSize,
        required String oldTheme, required String theme,
      }) async {
        if (shouldReload(...)) {
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
    ```
    `PagedWebViewState.didUpdateWidget` 调用 `_reloader.onWidgetUpdated(...)`；`_reloader` 在 `initState` 以闭包绑定 `_controller`（`loadData` 为 null 时安全短路）。
  - 优点：US-6 可在**不实例化 WebView** 的前提下单测（注入 spy `loadData/applyStyle`，断言调用次数与参数）；幂等（href/html 均不变→`none`）；样式变化仍走既有 `_applyStyle`；不重建平台视图（无闪烁、控制器/JS handler 不重注册）。
  - 缺点：需新增一个引擎内小类；重载完成后的 relayout 时序需额外处理（见下）。
- **B：`ReaderPage` 侧用 `ValueKey(href)` 强制重建 `PagedWebView`**
  - 做法：`PagedWebView(key: ValueKey(href), ...)` 替换 `GlobalKey<PagedWebViewState>`。
  - 优点：改动最小，新章天然加载新文档。
  - 缺点：与 `_pagedKey`（`GlobalKey`）冲突，`_page`/`_onProgressSeek`/`_jumpToProgress` 全部依赖 `_pagedKey.currentState`，需整体改写调用面；销毁/重建平台视图有启动成本与闪烁；`onLoadStop`/JS handler 重注册；US-6 的"重载参数"无可断言出口。**拒绝**（仅作 A 失效时的降级备选）。
- **C：改 `initialData` 或 `loadUrl('data:...')`**
  - 缺点：`initialData` 不响应更新（已核实）；data URL 会破坏 `reader://` baseUrl 与 `shouldInterceptRequest` 资源拦截（图片/CSS）。**拒绝**。

### 选择与理由

选 **A**。US-6 明确要求"架构阶段提供可测出口（纯函数/可注入执行器）"，`PagedDocumentReloader` 同时满足"决策可断言 + 重载参数可断言 + 样式分支不重载"；不重建平台视图，保住 `_pagedKey` 既有调用面（`_page`/进度条/relayout）。

### 重载时序（与 `onLoadStop`→`paginationJs`→`_applyStyle` 的接线）

```
用户点"下一章"
  → ReaderPage._goChapter(+1)：setState(_chapterIndex=next, _chapterProgress=0.0)
  → FutureBuilder 取新章 chapterHtml → 同 GlobalKey 重建 PagedWebView(href:new, html:new)
  → PagedWebViewState.didUpdateWidget → PagedDocumentReloader.shouldReload=true
        → controller.loadData(data:newHtml, baseUrl:WebUri('reader://book/{bookId}/'))
  → WebView 触发 onLoadStop
        → evaluateJavascript(paginationJs)         // 新文档重建 window.readerPager
        → _applyStyle()（applyStyle + relayout）    // 新文档 relayout 到第 0 页
        → readerFlutter 上报 progression=0.0
  → ReaderPage._jumpToProgress(0.0)（分页分支）改为 await state.relayoutAfterLoad()
        // PagedLoadGate：若重载进行中，先 await 载入完成再 relayout；否则立即 relayout
```
- **可测出口**：`PagedLoadGate`（`begin()/pending/done/complete()`）单测断言"载入未完成时 `relayoutAfterLoad` 挂起、完成后放行"，使"重载完成后再 relayout"这一时序有可断言代理；真实 WebView 时序由 US-17 真机清单兜底。
- **幂等**：`fontSize/theme` 变化走 `styled`（既有 `_applyStyle`），不调 `loadData`；href/html 均不变返回 `none`。

### 影响
- 新增 `app/lib/engines/paged_document_reloader.dart`（interface）。
- `paged_web_view.dart`：`didUpdateWidget` 改调 reloader；`_onLoadStop` 末尾完成 `PagedLoadGate`；`PagedWebViewState` 增 `relayoutAfterLoad()`。
- `reader_page.dart`：分页分支的 `_jumpToProgress` 改调 `relayoutAfterLoad()`（`_onProgressSeek` 的 `gotoPage` 不变）。
- 回归面：`fontSize/theme` 既有样式路径不变；`disableContextMenu`/`onSelectedText`/`onProgress` 接线不变。

### 降级线（授权）
若真机上 `loadData` 后 `onLoadStop` 不触发或 `readerPager` 未重建：**降级为方案 B**（`ReaderPage` 用 `ValueKey(href)` 重建 `PagedWebView`），并保留 `PagedDocumentReloader.shouldReload` 纯函数单测（仍满足 US-6 的"决策可断言"），`_pagedKey` 调用面改为经 `ReaderPage` 持有的可空 controls 接口（见 D4）。降级只改重建方式，不改 `_goChapter`/进度语义。

---

## 决策点 D3：JS 布尔返回值解析（R2-2，US-7）

**现状（已核实）**：`_runBool`（`paged_web_view.dart:108-113`）把 `evaluateJavascript` 结果与字符串 `'true'` 比较；插件对 JS 结果 `json.decode`（`in_app_webview_controller.dart:1923-1936`），布尔返回 Dart `bool`，故 `v == 'true'` 恒 false → `nextPage/prevPage` 恒 false → `_page` 恒回退 `_goChapter`。

### 备选

- **A（选）：抽纯函数 `parseJsBool(dynamic)` + 可注入 `PagedJsExecutor`**
  ```dart
  // app/lib/engines/paged_js_result.dart（interface，不 import flutter_inappwebview）
  bool parseJsBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1';
    }
    return false;
  }
  typedef JsEvaluator = Future<dynamic> Function(String source);
  class PagedJsExecutor {
    PagedJsExecutor(this._evaluate);
    Future<bool> runBool(String source) async => parseJsBool(await _evaluate(source));
    Future<int> runInt(String source, {int fallback = 1}) async { ... }
  }
  ```
  `PagedWebViewState.onWebViewCreated` 构造 `_js = PagedJsExecutor((s) => c.evaluateJavascript(source: s))`；`nextPage/prevPage/gotoPage` 走 `runBool`，`pageCount` 走 `runInt`。
  - 优点：兼容 `bool`/`'true'`/`'false'`/`null`/`num`；纯函数不依赖 WebView，[单测] 直接覆盖 US-7 全部分支；`PagedJsExecutor` 注入 fake evaluator 可断言"`nextPage()` 调用 JS `readerPager.next()` 并解析返回值"。
  - 缺点：新增一个引擎内文件；`pageCount` 改用 `runInt` 属顺手统一，行为等价（原 `int.tryParse('$v')` 对 num 也成立）。
- **B：只改 `_runBool` 内联 `v is bool ? v : v == 'true'`**
  - 优点：一行改动。
  - 缺点：无可测出口（US-7 要求"架构阶段提供的可测 JS 执行出口"）；漏掉 `num`/`null` 分支。**不满足验收**。
- **C：改 JS 端返回字符串 `'true'/'false'` 以匹配旧 Dart 比较**
  - 缺点：`json.decode('true')` 仍可能还原为 bool，且要改 `paginationJs` 全部分支，方向错误。**拒绝**。

### 选择与理由

选 **A**。US-7 要求同时兼容 Dart `bool` 与字符串 `'true'`（以及 `false`/`'false'`/`null`/非布尔不抛错），纯函数是唯一能穷举断言的形态；把 evaluator 抽出来顺带解决"无法在无 WebView 环境验证 `nextPage()`"的问题。

### 影响
- 新增 `app/lib/engines/paged_js_result.dart`；`paged_web_view.dart` 删除 `_runBool` 内联比较，改委托 `PagedJsExecutor`。
- 回归面：`gotoPage` 返回值语义（bool）不变；`pageCount` fallback=1 不变。

### 降级线（授权）
若插件在某平台返回包装对象（如 `{'value': true}`）而非裸值：在 `parseJsBool` 增加"单键 Map 解包"分支（`v is Map && v.length==1` 时递归解析其 value），**US-7 断言不变**。

---

## 决策点 D4：`_page` 章内/章末决策可测（US-8）

**现状（已核实）**：`_page`（`reader_page.dart:211-216`）依赖 `_pagedKey.currentState`（真实 WebView state），widget/单测环境不可用；现有 `reader_page_test.dart:320-337` 只能断言"边缘点击不崩（短路）"，无法验证"章内翻页不跳章、章末才续章"。

### 备选

- **A（选）：抽 `PagedViewControls` 接口 + `PageTurnCoordinator`，`ReaderPage` 增可选注入**
  ```dart
  // app/lib/engines/paged_view_controls.dart（interface）
  abstract class PagedViewControls {
    Future<bool> nextPage();
    Future<bool> prevPage();
    Future<int> pageCount();
    Future<bool> gotoPage(int index);
    Future<void> relayout();
    Future<void> relayoutAfterLoad();
  }
  class PageTurnCoordinator {
    PageTurnCoordinator({required this.controls, required this.goChapter});
    final PagedViewControls controls;
    final void Function(int delta) goChapter;
    Future<void> page(int delta) async {
      final ok = delta < 0 ? await controls.prevPage() : await controls.nextPage();
      if (!ok) goChapter(delta);
    }
  }
  ```
  `PagedWebViewState implements PagedViewControls`；`ReaderPage` 增 `final PagedViewControls? pagedControls;`，`_page(delta)` 取 `widget.pagedControls ?? _pagedKey.currentState`，经 `PageTurnCoordinator` 执行。
  - 优点：US-8 可用 fake controls（`nextPage→true/false`）+ spy `goChapter` 直接单测"章内不跳章/章末跳章/左边缘对称"；`ReaderPage` 分页边缘手势可 widget 测试（注入 fake controls，不再依赖 `_pagedKey`）；生产路径零行为变化。
  - 缺点：新增接口 + 让 `PagedWebViewState` 实现接口；`ReaderPage` 构造多一个可选参数。
- **B：把 `_page` 改为 `@visibleForTesting` 公开方法，测试直接调**
  - 缺点：仍依赖 `_pagedKey.currentState`，无 WebView 即不可测；把测试缝暴露在页面 API 上，破坏封装。**不满足可测性**。
- **C：在 Dart 侧 fake 一个 `PagedWebView` 子类注入 `GlobalKey`**
  - 缺点：`GlobalKey<PagedWebViewState>` 要求真实 State 类型；fake 子类仍会构建 `InAppWebView`（Linux 无平台实现）。**不可行**。

### 选择与理由

选 **A**。与 D3 的"注入执行器"同构（REQ-005 `buildPagedWebViewSettings` 可测工厂、REQ-006 `ScrollController` 可注入先例）；把"翻页是否成功 → 是否续章"的编排从页面私有状态里解耦，是唯一能让 US-8 在无 WebView 环境闭环的方案。

### 影响
- 新增 `app/lib/engines/paged_view_controls.dart`；`PagedWebViewState implements PagedViewControls`（`relayoutAfterLoad` 见 D2）。
- `reader_page.dart`：新增可选 `pagedControls`；`_page` 委托 `PageTurnCoordinator`。
- 测试：新增 `app/test/fake_paged_view_controls.dart`；`reader_page_test.dart` 的分页边缘用例可注入 fake 断言"不 toggle + 调 nextPage"。

### 降级线（授权）
若让 `State` 类 `implements` 接口引发既有调用面编译问题：改为**适配器** `_PagedWebViewControlsAdapter`（组合 `GlobalKey<PagedWebViewState>`，逐方法转发），`ReaderPage` 内部持适配器；`PageTurnCoordinator` 契约与 US-8 断言不变。

---

## 决策点 D5：翻译未配置引导（R3-2/R3-3，US-11/US-12）

**现状（已核实）**：无 key + 离线未命中错误 `Error::NotConfigured("未配置在线翻译 API Key（{pname}），且离线翻译未命中（请先安装内置词库）")`（`translation.rs:562-567`，Display 前缀"翻译服务未配置："，`error.rs:31-33`）**不含"设置"**；`ReaderPage._doTranslate` catch 仅塞 `OverlayError(message, onRetry)`（`reader_page.dart:386-392`、`:545-546`）；`OverlayError` 只有 message+重试（`translation_popup.dart:147-181`）。R3-3：`SettingsPage` 在应用内无运行期入口（`main.dart:19` → `LibraryPage` 无设置入口）。

### 备选

- **A（选）：core 错误文案**仅追加**"设置"引导 + `OverlayError` 增**可选** `onOpenSettings` + `ReaderPage` 按"未配置"判定直接 push `SettingsPage(translateBackend: widget.translateBackend)`**
  - core（`translation.rs:564-566`，只追加不改既有子串）：
    ```rust
    return Err(Error::NotConfigured(format!(
        "未配置在线翻译 API Key（{pname}），且离线翻译未命中（请先安装内置词库）；请在「设置」中配置在线翻译或导入词库"
    )));
    ```
  - Dart 契约：
    ```dart
    // app/lib/widgets/translation_popup.dart（interface widget，未在 ddd-rules 声明，按 pages 同级纪律）
    bool isTranslationNotConfiguredError(String message) =>
        message.contains('未配置在线翻译 API Key') ||
        message.contains('未配置翻译后端');

    class OverlayError extends StatelessWidget {
      const OverlayError({
        super.key, required this.message, required this.onRetry,
        this.onOpenSettings,                 // 可选：非 null 才渲染"去设置"
        this.openSettingsLabel = '去设置',
      });
    }
    ```
    ```dart
    // app/lib/pages/reader_page.dart
    OverlayError(
      message: _translationError!,
      onRetry: _doTranslate,
      onOpenSettings: isTranslationNotConfiguredError(_translationError!)
          ? _openTranslateSettings : null,
    ),
    // 查词错误保持不变：OverlayError(message: _lookupError!, onRetry: _doLookup) → 无"去设置"

    void _openTranslateSettings() => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsPage(translateBackend: widget.translateBackend)));
    ```
  - 优点：错误文案"追加"满足 US-11 的三段子串并存且不破坏 REQ-006 `contains` 断言；"去设置"按钮**仅**在翻译未配置时出现（查词错误结构上无该回调）；`SettingsPage` 收到与 `ReaderPage` 同一注入 backend（US-12 可断言，测试环境不落到默认 Rust 后端）；R3-3 的不可达问题由该入口解决，无需改书架页（P1 可选）。
  - 缺点：`OverlayError` 新增两个可选字段；新增 golden 差异（仅错误态，见影响）。
- **B：在 `_doTranslate` 里直接弹 `SnackBar`/`showDialog` 引导**
  - 缺点：US-12 要求 `find.text('去设置')` 在**错误浮层**内出现；SnackBar/Dialog 与 `OverlayError` 双入口，破坏 04-selection 的浮层体系。**拒绝**。
- **C：所有翻译错误都显示"去设置"**
  - 缺点：网络失败时引导去设置是误导，且 US-12 隐含"仅未配置"。**拒绝**。
- **D：用异常类型（`NotConfiguredException`）而非文案子串判定**
  - 优点：不耦合文案。
  - 缺点：`TranslateBackend.translate` 现抛 `Exception('$e')`（`reader_page.dart:390`），要引入异常类型需改 services/桥接契约，超出本期最小修复；作为降级线更合适。

### 选择与理由

选 **A**。"未配置"的识别以 core 文案契约（`未配置在线翻译 API Key`）为锚，集中在一个 `isTranslationNotConfiguredError` 谓词里，避免散落；`OverlayError` 的可选参数保证不传时行为与现状逐字一致（既有测试/golden 零回归）；查词错误与翻译错误在 `ReaderPage` 中本就分属不同字段与 `OverlayError` 实例，结构上天然隔离。

### 影响
- `core/src/dict/translation.rs`：`Error::NotConfigured` 文案追加"；请在「设置」中配置在线翻译或导入词库"；`Error::NotConfigured`/`Error::Network` 类型与 Display 前缀不变；缓存/策略/回退语义零改动。
- `app/lib/widgets/translation_popup.dart`：`OverlayError` 可选按钮 + `isTranslationNotConfiguredError`。
- `app/lib/pages/reader_page.dart`：import `settings_page.dart`；`_openTranslateSettings`；错误浮层条件传参。
- 测试/golden：`translate_reader_test.dart` 新增"去设置"断言；错误态 golden 若存在需同步；`settings_page_test.dart`/`no_hardcoded_key_test.dart` 不受影响。

### 降级线（授权）
若"文案子串判定"被判定为脆弱（后续 i18n/文案调整）：降级为 **D**——Dart services 抛 `TranslateException(message, kind: TranslateFailureKind.notConfigured)`，`isTranslationNotConfiguredError` 改判 `kind`；**不要求改 Rust 契约**，US-12 断言不变。

---

## 决策点 D6：真实集成测试结构（R1-2，US-3/US-14；平台约束）

**现状（已核实）**：`app/integration_test/` 仅 `screenshots_test.dart`；`:147-179` 用合成 `Column(ReaderTopBar, ReaderBottomBar)` 伪造呼出态；`:247` 的 `tapAt(195,422)` 落在文字下方空白（假阳性）。`flutter_inappwebview` 无 Linux 平台实现（`ui-screenshots.sh:34` 以 `xvfb-run -a flutter test integration_test/screenshots_test.dart -d linux` 运行）。

### 备选

- **A（选）：新增 `reader_interaction_test.dart` 用真实 `ReaderPage`（滚动模式）覆盖 US-1/2/4/12；`screenshots_test.dart:147-179` 删除合成页、改由真实 ReaderPage + `tapAt` 文字 center 产生 `reader_chrome`；`:247` 落点改文字 center；分页路径只做 widget/单测 + 真机**
  - 优点：真实点击/长按/拖拽，直接证伪 R1-2 的假阳性；Linux xvfb 可跑（滚动模式不实例化 WebView）；与 US-14/US-3 逐条对应。
  - 缺点：分页在 Linux 无法实跑，须靠 US-6/7/8 可测出口 + US-17 真机；`reader_more` 截图依赖文字 center 命中。
- **B：用 `flutter_inappwebview` 的 WebView mock 在 Linux 跑分页集成测试**
  - 缺点：插件无 Linux 实现，无官方 mock；自建 fake platform view 成本高且不验证真实重载。**拒绝**。
- **C：保留合成页，仅新增真实用例**
  - 缺点：违反 US-3"必须删除/改写"；假阳性继续存在。**拒绝**。

### 选择与理由

选 **A**。测试分层明确：**[集成测试]** 真实 ReaderPage（滚动）覆盖手势/切章/引导；**[widget 测试]** 分页 fake 构建器覆盖 US-5/US-9、注入 controls 覆盖 US-2 分页边缘、US-12/US-13；**[单测]** 覆盖 US-6/7/8 可测出口；**[真机]** 覆盖 US-17 分页翻页/切章。

### 影响
- 新增 `app/integration_test/reader_interaction_test.dart`（US-1/2/4/12）。
- `screenshots_test.dart`：删除 `:147-179` 合成 Column；`reader_chrome` 改真实 ReaderPage 点击文字；`:247` 改 `tapAt(tester.getCenter(find.text(...)))`；`ReaderTopBar/ReaderBottomBar` import 移除。
- 新增 `app/test/no_synthetic_chrome_test.dart`（[单测] 静态守卫）：扫描 `app/integration_test/*.dart`，断言不含 `ReaderTopBar(`/`ReaderBottomBar(` 直接构造（US-3/US-14）。
- 平台约束记录：Linux 无 WebView → 分页只做 widget/单测 + 真机；`ui-screenshots.sh` 仍走 xvfb。

### 降级线（授权）
若 Linux xvfb 下真实长按/拖拽在集成测试中不稳定（CI 抖动）：把 US-2 的滚动/长按断言降级到 [widget 测试]（`reader_selection_test.dart` 已有真实长按），集成测试保留 US-1/US-4/US-12 的 `tapAt`；**"禁止合成页"的约束不降级**，US-14 仍以真实 ReaderPage 为准。

---

## 关联裁定（次要决策，供 02-design/02-plan 引用）

1. **UI 增量唯一性**：本 REQ 唯一视觉增量 = `OverlayError` 在"翻译未配置"时多一个"去设置"按钮；顶栏/底栏/工具条/设置页布局零改动（逐屏映射见 02-design §5）。
2. **可测出口清单**：`BodyTapTracker`/`resolveBodyTap`（D1）、`PagedDocumentReloader`/`PagedLoadGate`（D2）、`parseJsBool`/`PagedJsExecutor`（D3）、`PagedViewControls`/`PageTurnCoordinator`（D4）——均为 interface 层纯 Dart，不 import `package:reader_app/src/rust/`。
3. **DDD 归属**：`core/src/dict`（domain）仅追加文案，仍禁依赖 `crate::store/api/library`；`app/lib/pages|widgets|engines` 属 interface，经 `services` 取 DTO；`translation_popup.dart` 未被 ddd-rules 声明，按 pages 同级纪律人工核对 import 面（沿用 REQ-005/006 处置）。
4. **零 schema**：`reading_progress`/`translation_cache`/`settings` 表与 `user_version` 零变更；无 FRB 再生成（Rust 无签名/DTO 变化）。
5. **无新增依赖**：不引入任何 pub/crate；`flutter_inappwebview` 既有 API `loadData` 即满足。
6. **`_lastDataPointer` 保留**：D1 改用手动 tap 判定后，`_lastDataPointer`（工具条定位）继续由 `Listener.onPointerDown/Up/Move` 维护，行为不变。
7. **分页重载不触发自动续章**：`_goChapter` 后 `_jumpToProgress(0.0)` 在分页分支改调 `relayoutAfterLoad()`，不改变 `_goChapter`/`_saveProgress` 语义。
8. **文档同步风险**：`docs/03`/`docs/04` 无需改签名（零接口变更）；仅"分页重载时序/手势手动判定"可在开发阶段补一句注释，非闸门项。

## 影响汇总
- **Rust**：`core/src/dict/translation.rs`（US-11 文案追加，唯一改动）；零签名/DTO/schema/迁移。
- **Dart（新增）**：`engines/paged_document_reloader.dart`、`engines/paged_js_result.dart`、`engines/paged_view_controls.dart`、`pages/body_tap_policy.dart`；`test/fake_paged_view_controls.dart`、`integration_test/reader_interaction_test.dart`、`test/no_synthetic_chrome_test.dart`。
- **Dart（修改）**：`pages/reader_page.dart`（手势层/`_page`/错误浮层/设置跳转/可选 `pagedControls`）、`engines/paged_web_view.dart`（reloader/js executor/controls/gate）、`widgets/translation_popup.dart`（可选按钮 + 谓词）、`integration_test/screenshots_test.dart`（去合成页）、`test/reader_page_test.dart`、`test/translate_reader_test.dart`。
- **数据模型**：零变更（`reading_progress`/`Locator`/`translation_cache`/`settings`）。
- **回归面**：core 全量、Flutter widget/FFI/goldens、`ui-screenshots.sh`、CRAP/DDD 闸门、Android 真机清单。

## 闸门2 自评（ADR 部分）
- [x] **备选 ≥2 且给出理由**：D1 四备选（A/B/C/D）、D2 三备选（A/B/C）、D3 三备选（A/B/C）、D4 三备选（A/B/C）、D5 四备选（A/B/C/D）、D6 三备选（A/B/C），每点含选择理由与拒绝论证；六点均有降级线授权。
- [x] **与既有约定一致**：Locator/`reading_progress` 零变更（唯一事实源，听读同进度）；限界上下文不跨越（`core/src/dict` 仍 domain、零新表）；ddd-rules 合规（interface 不 import 生成物、domain 不依赖 store/api/library）；REQ-001/003/004/005/006 能力复用不重做（REQ-006 文案断言以"追加"保全）。
- [x] **原型权威**：D1/D2/D5 与 `reader-ui-v2/01-immersive.svg`/`02-menus.svg`/`04-selection.svg`、`08-translation.svg`、`03-settings.svg` 逐屏对应（02-design §5）；未自创布局，唯一 UI 增量为错误浮层一个按钮。
- [x] **可测性**：US-6/7/8 的可测出口全部落定（D2/D3/D4），US-1/2/3/4/12/14 的真实集成测试结构落定（D6）。
- [ ] **待同步项（非本阶段闸门项）**：`docs/03`/`docs/04` 可补"分页重载时序/手势手动判定"注释，开发/交付阶段处理；本阶段按纪律只产出 3 份产物。
