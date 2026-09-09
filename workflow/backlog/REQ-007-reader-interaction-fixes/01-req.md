<!-- wf-meta: req=REQ-007-reader-interaction-fixes | phase=requirements | agent=req-analyst | date=2026-09-09 | gate=passed -->
# REQ-007-reader-interaction-fixes · 阅读器交互修复（中部呼出 / 切章 / 在线翻译引导）—— 需求分析

## 1. 背景与目标

### 1.1 问题现象（用户原始诉求，不可偏离）

- **问题1 · 点击正文中部无法呼出顶底栏（P0）**：真机阅读器页点击正文中部，顶栏/底栏（Chrome）不出现。
  REQ-005 集成测试 `tapAt` 中部也未真正触发 `_onBodyTapUp` 的 toggle（当时以合成页绕过），说明该交互在
  真实运行时不可靠。
- **问题2 · 无法切换到下一章（P0）**：真机阅读器无法切到下一章 —— 底栏"下一章"按钮、边缘翻页到章末
  续章均无效。
- **问题3 · 在线翻译引导（P0）**：0.7.0 已加 DeepL 配置（设置页 → 在线翻译 Provider (DeepL) → API Key）。
  需确认 auto 策略下选中文本能触发在线翻译；未配 key 时给明确引导（指向设置页），而不是只显示
  "离线翻译未命中"。

### 1.2 成功标准与范围划界

**成功标准一句话**：在**真实 `ReaderPage`（真实点击/手势）**下，点击正文文字可靠呼出/隐藏顶底栏；滚动
模式底栏"下一章"与分页模式切章/章内翻页均正确；选中文本翻译时 `auto`+已配 key 走在线
（`provider=="deepl"`、`fromCache==false`），未配 key 时错误文案含"设置"引导且 UI 提供"去设置"入口直达
设置页；全部以 `integration_test`（滚动模式）+ widget 测试 + 单测分层验证，禁止合成页绕过。

**本期范围（P0，必须）**：

1. 问题1：中部点击（**包括点在正文文字上**）可靠 toggle 顶底栏；不得回退长按选中、滑动滚动、边缘
   热区、进度条拖动等既有手势。
2. 问题2：滚动模式底栏"下一章"正常（守住既有能力）；分页模式底栏"下一章"与边缘翻页正确
   （章内翻页 → 章末才续章），核心是 `PagedWebView` 切章重载 + JS 返回值解析两处根因。
3. 问题3：确认 `auto`+key 在线链路；未配 key + 离线未命中时错误文案含"设置"引导，UI 提供"去设置"
   按钮并跳转 `SettingsPage`。
4. 测试基建：交互 bug **必须用真实 `integration_test`**（`app/integration_test/*.dart`，真实 `ReaderPage`
   + 真实 `tapAt`/`longPress`/`drag`）验证；**禁止**直接拼 `ReaderTopBar`/`ReaderBottomBar` 的合成页绕过
   （现 `app/integration_test/screenshots_test.dart:147-179` 必须替换为真实 ReaderPage 呼出态）。

**明确不做（另立 REQ）**：TTS/听书（REQ-005/006）、笔记/划重点（NOTE 系列）、Provider 启停进阶管理
（TRANS-03）、生词本（TRANS-04）、对照阅读（TRANS-05）、key 加密/系统钥匙串、WebView 原生选择菜单
（REQ-005 已处理）、阅读器视觉改版（REQ-004 已定）。

### 1.3 根因核实（逐条 Read 源码，含与 orchestrator 预调查的对照）

> 每条均给出 file:line 证据；"一致"=与 orchestrator 预调查一致（本阶段独立复核通过），
> "补充"=预调查结论正确但证据/机制需细化，"新增"=预调查未列。

| 编号 | 结论 | 证据（已逐条核对） | 对照预调查 |
|---|---|---|---|
| **R1-1** | **手势竞技场被 SelectionArea 吞掉 tap**：`GestureDetector(onTapUp:)` 包裹 `SelectionArea`；`SelectionArea` 内部 `SelectableRegion` 注册了触摸识别器 `TapAndHorizontalDragGestureRecognizer`（非鼠标）与 `TapAndPanGestureRecognizer`（鼠标），二者均带 `onTapUp`，在命中文字时赢得 tap 竞技场，父 `GestureDetector.onTapUp` 不再触发。真机正文铺满屏幕 → 用户几乎总点到文字 → 顶底栏永不出现。 | `app/lib/pages/reader_page.dart:483-492`（`GestureDetector` 包 `SelectionArea` 的正文树 `:594-619`）；Flutter SDK `packages/flutter/lib/src/widgets/selectable_region.dart:459-465`（右击 TapGestureRecognizer）、`:684-720`（触摸 `TapAndHorizontalDragGestureRecognizer`，`:712-713` onTapDown/onTapUp）、`:1977-1979`（`RawGestureDetector(gestures: _gestureRecognizers)`） | **一致**（补充 SDK 侧机制证据） |
| **R1-2** | **测试/截图假阳性**：既有 widget 测试 `tapAt(Offset(400,300))` 与集成截图 `tapAt(195,422)` 均落在**单行正文下方的空白**（非文字），故"能呼出"是假阳性；"呼出顶底栏"截图用合成 `Column(ReaderTopBar, ReaderBottomBar)` 绕过真实交互。 | `app/test/reader_page_test.dart:37-42,45-67`（`_center=Offset(400,300)`，FakeBackend 单行文本）；`app/integration_test/screenshots_test.dart:247`（`tapAt(195,422)`）、`:147-179`（合成 Column） | **一致** |
| **R2-1** | **分页模式切章不重载 WebView**：`PagedWebView.didUpdateWidget` 只处理 `fontSize`/`theme`，不处理 `href`/`html` 变化；`InAppWebView.initialData` 仅作为创建参数生效（插件 widget 无 didUpdateWidget 处理），故 `_chapterIndex` 变化后 WebView 仍显示旧章 → 底栏"下一章"、章末续章视觉上无效。 | `app/lib/engines/paged_web_view.dart:70-75`（didUpdateWidget）、`:159-163`（`initialData`）；插件 `flutter_inappwebview-6.1.5/lib/src/in_app_webview/in_app_webview.dart:307`（initialData 进 creation params，全文无 didUpdateWidget 处理）；控制器有 `loadData`（`flutter_inappwebview_android-1.1.3/.../in_app_webview_controller.dart:1815`） | **一致** |
| **R2-2** | **JS 布尔返回值解析错误**：`_runBool` 把 `evaluateJavascript` 结果与字符串 `'true'` 比较；插件对 JS 结果做 `json.decode`，布尔返回 Dart `bool`，故 `v == 'true'` 恒 false → `nextPage/prevPage` 恒返回 false → `_page()` 恒回退 `_goChapter(delta)`，分页模式边缘点击直接跳章、章内永不翻页。 | `app/lib/engines/paged_web_view.dart:108-113`；插件 `flutter_inappwebview_android-1.1.3/.../in_app_webview_controller.dart:1923-1936`（`json.decode(data)`）；`app/lib/pages/reader_page.dart:211-216`（`_page` 回退 `_goChapter`） | **一致** |
| **R2-3** | **滚动模式底栏切章正常（验证基线，非缺陷）**：`_goChapter` 改 `_chapterIndex` 后滚动模式重建正文 Text，widget 测试已覆盖。 | `app/lib/pages/reader_page.dart:155-168`（`_goChapter`）、`:594-619`（滚动正文）；`app/test/reader_page_test.dart:45-67`（下一章 → 第二章） | **一致** |
| **R3-1** | **`auto` 策略已实现且为默认**：默认 provider 已是 `"auto"`（REQ-006 由 offline 改），`translate_auto` 在线优先→失败/无 key 回退离线；有 key 时走 DeepL。 | `core/src/store/translation.rs:19-21`（`DEFAULT_PROVIDER="auto"`）；`core/src/dict/translation.rs:433-570`（`translate_routed`/`translate_auto`）；`core/src/api.rs:321-344`（`translate` 走 `translate_routed`）；`docs/03-architecture.md:219-229`、`docs/04-module-design.md:157-180` | **一致**（补充"默认值已由 offline 改 auto"） |
| **R3-2** | **无 key 文案缺"设置"引导、UI 无设置入口**：无 key + 离线未命中时错误为 `Error::NotConfigured("未配置在线翻译 API Key（deepl），且离线翻译未命中（请先安装内置词库）")`，`Display` 前缀"翻译服务未配置："，**不含"设置"**；`ReaderPage._doTranslate` 仅将其塞进 `OverlayError`（只有"重试"按钮），无"去设置"入口。 | `core/src/error.rs:31-33`；`core/src/dict/translation.rs:562-567`；`app/lib/pages/reader_page.dart:386-392`（catch 写 `_translationError`）、`:545-546`（`OverlayError(onRetry: _doTranslate)`）；`app/lib/widgets/translation_popup.dart:147-181`（OverlayError 仅 message+重试） | **一致** |
| **R3-3** | **（新增发现）SettingsPage 运行期不可达**：应用根仅 `home: LibraryPage`，`LibraryPage` 无任何设置入口；全 `app/lib` 中 `SettingsPage` 仅被自身文件引用，另一处引用在 `integration_test/screenshots_test.dart:351`。即用户所述"设置页 → 在线翻译 Provider"路径在交付代码中**没有运行期入口**。本 REQ 的"去设置"引导因此需直接 push `SettingsPage`（并透传 `translateBackend`）。 | `app/lib/main.dart:19`（`home: const LibraryPage()`）；`app/lib/pages/library_page.dart` 全文无 `SettingsPage`；`grep -rln "SettingsPage" app/lib/` 仅 `settings_page.dart`；`app/integration_test/screenshots_test.dart:351` | **新增**（预调查未列） |

**根因结论（供架构阶段参考，非本阶段实现决定）**：问题1 的唯一根因是 R1-1（R1-2 是让缺陷长期未被
发现的测试假阳性）；问题2 是两处独立根因叠加 —— R2-1（分页切章不重载）与 R2-2（JS 布尔解析恒 false），
且滚动模式切章本身正常（R2-3）；问题3 的在线链路本身已具备（R3-1），缺的是无 key 时的引导文案与
"去设置"入口（R3-2），另有 R3-3 使设置页在应用内不可达（本 REQ 用引导入口解决）。

### 1.4 原型权威性与 UI 映射（`docs/wireframes/**` 为 UI 权威规范）

| 屏 / 交互 | 原型图 | 本 REQ 涉及 | 是否改变布局 |
|---|---|---|---|
| 沉浸态 + 中部点击呼出/隐藏 | `docs/wireframes/reader-ui-v2/01-immersive.svg` | 中部点击 toggle 顶底栏（含点在文字上） | 不改布局，仅修手势可达性 |
| 顶栏/底栏呼出态 | `docs/wireframes/reader-ui-v2/02-menus.svg` | 底栏"下一章"、顶栏返回 | 不改布局 |
| 选中浮动工具条 + 翻译/查词 | `docs/wireframes/reader-ui-v2/04-selection.svg` | 翻译入口复用；错误浮层新增"去设置"动作 | 仅错误浮层增加一个按钮 |
| 翻译浮层/词典卡片 | `docs/wireframes/08-translation.svg` | 无 key 错误文案与引导 | 不改布局 |
| 设置页 | `docs/wireframes/03-settings.svg`（+ 现有"词典与翻译"区块） | "去设置"目标页（既有 DeepL Provider/key 配置） | 不改布局 |

> 实现阶段禁止对上述线框布局自由发挥（闸门3 逐屏核对，deviation=0）。

---

## 2. 用户故事与验收标准（Given/When/Then，必须可测；标注问题号/根因号/原型图/验证方式）

> **验证方式标注**：`[集成测试]` = 真实 `ReaderPage` + 真实点击/手势，跑在 `app/integration_test/*.dart`
> （Linux 仅滚动模式，因 `flutter_inappwebview` 无 linux 平台支持）；`[widget 测试]` = `app/test/*.dart`
> 注入 fake；`[单测]` = Rust/Dart 纯函数或可测出口；`[真机]` = Android 真机/人工清单（CI 不可自动化）。

### 故事 1：问题1 · 点击正文中部可靠呼出/隐藏顶底栏 —— 作为所有用户，我想要点屏幕中间就能调出工具、再点回到沉浸

- **US-1 点击正文文字 toggle 顶底栏（R1-1/R1-2，P0，[集成测试]，01-immersive + 02-menus）**
  - Given 真实 `ReaderPage`（滚动模式，长文本 fake backend 使正文文字铺满屏幕中部），初始 `_chromeVisible==false`
  - When `tester.tapAt(tester.getCenter(find.text('<正文中的一段文字>')))`（**点在文字上**，非文字下方空白）
  - Then 顶栏出现：`find.byTooltip('返回书架')` 为 `findsOneWidget`、`find.byType(ReaderBottomBar)` 为
    `findsOneWidget`、`find.text('下一章')` 为 `findsOneWidget`
  - Given 顶底栏已呼出 When 再次 `tapAt` 同一段文字的 center Then 顶底栏隐藏：
    `find.byTooltip('返回书架')` 为 `findsNothing`、`find.byType(ReaderBottomBar)` 为 `findsNothing`
  - Given 沉浸态 When 点击正文**文字下方空白** Then 同样 toggle（两种落点都成立）
- **US-2 呼出/隐藏不误伤长按选中与滚动（R1-1，P0，[集成测试] + [widget 测试]，01-immersive）**
  - Given 真实 `ReaderPage` 滚动模式、沉浸态
  - When `tester.longPress(find.text('<正文文字>'))` Then `find.byType(ReaderSelectionToolbar)` 为
    `findsOneWidget`，且 `find.byTooltip('返回书架')` 为 `findsNothing`（长按选中**不得**误触 Chrome toggle）
  - When 在正文区 `tester.drag(find.byType(SingleChildScrollView), const Offset(0, -200))` Then 滚动偏移 > 0
    且 Chrome 可见性不变
  - Given 分页模式（widget 注入 fake 分页构建器）When 点击左右边缘热区 Then 不触发 Chrome toggle
    （沿用 REQ-004 US-2/US-3 互斥语义）
- **US-3 呼出态截图/集成用例禁止合成页（R1-2，P0，[集成测试]，02-menus）**
  - Given `app/integration_test/screenshots_test.dart`
  - Then 不存在直接拼 `ReaderTopBar`/`ReaderBottomBar` 的合成页面（当前 `:147-179` 必须删除/改写）；
    `reader_chrome` 呼出态截图由真实 `ReaderPage` + `tapAt` 正文文字产生；
    `reader_more`（更多菜单）截图同样由真实 ReaderPage 点击正文文字呼出后产生（替换 `:247` 的空白点）
  - Given 运行 `bash scripts/ui-screenshots.sh REQ-007` Then 退出码 0、截图产物更新

### 故事 2：问题2 · 切章与翻页 —— 作为所有用户，我想要底栏"下一章"和边缘翻页都真的翻到下一章

- **US-4 滚动模式底栏"下一章"（R2-3 回归基线，P0，[集成测试]，02-menus）**
  - Given 真实 `ReaderPage` 滚动模式（fake backend 两章），沉浸态
  - When `tapAt` 正文文字呼出 Chrome → `tester.tap(find.text('下一章'))`
  - Then 下一章正文出现（`find.text('<第二章文字>')` 为 `findsOneWidget`），
    且 `backend.saved?.href == 'chapter_0002.xhtml'`（进度保存）
  - Given 末章 When 点"下一章" Then 按钮禁用（`TextButton.onPressed == null`）或章节不变（不越界）
- **US-5 分页模式底栏"下一章"以新 href 重建分页视图（R2-1，P0，[widget 测试]，02-menus）**
  - Given `ReaderPage(initialPagedMode: true, pagedViewBuilder: <捕获 href 并按其渲染不同文本的 fake>)`
  - When 呼出 Chrome → 点"下一章"
  - Then fake 构建器**收到** `href == 'chapter_0002.xhtml'` 且页面渲染出第二章文本；
    `backend.saved?.href == 'chapter_0002.xhtml'`；章节位置归零（progression==0.0）
- **US-6 PagedWebView 在 href/html 变化时重载文档（R2-1，P0，[单测]）**
  - Given 架构阶段提供的可测出口（如把"是否重载"抽为纯函数/方法，或允许注入 controller/JS 执行器）
  - When `didUpdateWidget` 检测到 `old.href != new.href`（或 `old.html != new.html`）
  - Then 触发**加载新文档**（以新 html + `reader://book/{bookId}/` baseUrl 调用等价于 `loadData` 的重载出口，
    断言重载调用次数/参数）
  - Given 仅 `fontSize`/`theme` 变化 Then 仍只走既有 `_applyStyle`（`paged_web_view.dart:70-84`），不重载
  - Given href/html 均不变 Then 不重载（幂等）
- **US-7 JS 布尔返回值解析正确（R2-2，P0，[单测]）**
  - Given 架构阶段提供的可测 JS 执行出口
  - When `evaluateJavascript` 返回 Dart `bool true` Then `nextPage()`/`prevPage()` 返回 `true`；
    返回字符串 `'true'`（兼容路径）同样返回 `true`
  - When 返回 `false`/`'false'`/`null`/非布尔 Then 返回 `false`（不抛错）
- **US-8 边缘点击章内翻页、章末才续章（R2-2，P0，[单测] + [真机]，01-immersive + 02-menus）**
  - Given 可注入 fake 分页控制器（架构阶段提供可测出口）
  - When 章内 `nextPage()` 返回 `true` Then `_page(1)` **不**调用 `_goChapter`（章节索引不变）；
    When `nextPage()` 返回 `false`（章末）Then `_goChapter(1)`（章节索引 +1）
  - 左边缘对称：`prevPage()` 章内 `true` 不跳章；章首 `false` → `_goChapter(-1)`
  - [真机] Given Android 真机分页模式、章节多于一屏 When 点右边缘 Then 章内翻页（正文变化、章节名不变）；
    到章末再点 Then 进入下一章
- **US-9 分页切章不丢既有能力（R2-1/R2-2 回归，P0，[widget 测试]）**
  - Given 分页模式（fake 构建器）When 切章 Then 分页构建器/`PagedWebView` 的 `fontSize`/`theme` 参数
    仍按当前 Aa 设置传入；`onProgress`、`onSelectedText` 回调仍被接线（选中工具条仍可用）
  - 说明：REQ-005 US-19/US-20 的 `disableContextMenu: true` 与选区回传不得因本 REQ 回退

### 故事 3：问题3 · 在线翻译与未配置引导 —— 作为陈老师，我想要配了 key 就真走在线、没配时能一键去设置

- **US-10 `auto`+key 走在线（R3-1 回归确认，P0，[单测]）**
  - Given `TranslationService` 策略 `auto`、已配置 DeepL key、注入 DeepL stub Provider
  - When `translate_routed(text, from, to)`（经 `api.rs translate` 通路）
  - Then `translation.provider == "deepl"`、`from_cache == false`、译文非空；不返回"离线未命中"错误
  - 断言既有用例 `core/src/dict/translation.rs:1651-1671` 继续通过；本 REQ 可增补一条显式
    `provider=="deepl" && !from_cache` 断言
- **US-11 无 key + 离线未命中：文案含"设置"引导（R3-2，P0，[单测]）**
  - Given 策略 `auto`、未配置任何在线 key、离线 Provider 未命中
  - When `translate_routed(...)` Then 返回 `Err`，其 `to_string()` **同时包含**
    `"未配置在线翻译 API Key"`、`"设置"`、`"离线翻译未命中"` 三段语义；失败不写缓存
  - Given 无 key 但离线命中 Then 返回 offline 结果且 `fallback_reason` 为
    `"未配置在线翻译 API Key，已回退离线"`（既有 REQ-006 语义不破）
- **US-12 无 key 错误浮层提供"去设置"入口（R3-2，P0，[widget 测试] + [集成测试]，04-selection + 08-translation）**
  - Given 真实 `ReaderPage` 注入 `translateBackend`（其 `translate` 抛出无 key 错误文案，含"设置"引导），
    选中一段文本
  - When 点工具条"翻译" → 失败
  - Then 错误浮层文案含 `"设置"`；`find.text('去设置')` 为 `findsOneWidget`；`find.text('重试')` 仍存在
  - When 点击"去设置" Then `find.byType(SettingsPage)` 为 `findsOneWidget`，且 `SettingsPage` 收到
    `ReaderPage` 的同一 `translateBackend` 实例（fake 可断言）；**不使用**未注入的默认 Rust 后端
  - Given 工具条"查词"失败 Then 不出现"去设置"（词典引导仍走既有"未安装词库"文案，避免串扰）
- **US-13 在线/离线来源标签回归（R3-1/R3-2，P0，[widget 测试]，08-translation）**
  - Given `FakeTranslateBackend(translationProvider: 'deepl', fromCache: false)` 经 ReaderPage 翻译
    Then 译文卡片显示 `"在线"` 与 `"deepl"`
  - Given `provider: 'offline'` + `fallbackReason: '未配置在线翻译 API Key，已回退离线'`
    Then 显示 `"离线"` 与回退提示（沿用 REQ-006 US-18）

### 故事 4：测试与回归 —— 作为发布者，我想要真实交互可验证、旧能力不破

- **US-14 真实 integration_test 覆盖三大问题（P0，[集成测试]）**
  - Given 新增/扩展 `app/integration_test/`（如 `reader_interaction_test.dart`），全程真实 `ReaderPage` +
    真实 `tapAt`/`longPress`/`drag`，**不出现** `ReaderTopBar(`/`ReaderBottomBar(` 直接构造
  - Then 覆盖：① 正文文字上 tap toggle（US-1）；② 长按选中不误触 Chrome（US-2）；③ 滚动模式"下一章"
    （US-4）；④ 无 key 翻译 →"去设置"→ `SettingsPage`（US-12）
  - Given 运行 `flutter test integration_test -d linux`（xvfb）Then 全部通过
- **US-15 widget 测试覆盖分页与手势矩阵（P0，[widget 测试]）**
  - Given 注入 fake `LibraryBackend`/`translateBackend`/`pagedViewBuilder`
  - Then 覆盖：分页模式"下一章"收到新 href（US-5）、边缘点击不 toggle（US-2）、长按选中不 toggle
    （US-2）、"去设置"跳转与注入（US-12）、来源标签（US-13）；既有 `reader_page_test.dart` 中
    依赖"空白点呼出"的用例更新为"点文字呼出"（不得再依赖空白落点）
- **US-16 零回归（P0，[单测]/[widget 测试]/[集成测试]）**
  - Given REQ-001 进度/分页、REQ-003 翻译查词、REQ-004 阅读器 UI、REQ-005 听书/原生菜单、REQ-006 在线
    翻译既有测试
  - When 运行 `cargo test --release -p reader_core` 与 `flutter test` Then 全绿；`reading_progress`/`Locator`
    语义、`translation_cache` 缓存键、`translate` 错误语义、`disableContextMenu`/选区回传均不变
  - Given 既有 `translate_reader_test.dart` 对无 key 文案的 `textContaining('未配置在线翻译 API Key')` 断言
    When 文案追加"设置"引导 Then 仍通过（子串保留）
- **US-17 Android 真机验收清单（P0，[真机]）**
  - Given release/debug APK 安装于 Android 真机
  - Then 人工逐项通过：① 分页模式点正文文字呼出顶底栏、再点隐藏；② 分页模式边缘章内翻页、章末续章；
    ③ 底栏"下一章"正文更新；④ 长按选中仍出浮动工具条；⑤ 未配 key 翻译出现"去设置"并可进入设置页

---

## 3. 影响面分析（必须非空）

### 3.1 既有功能（Flutter / interface 层）

- **`app/lib/pages/reader_page.dart`（核心）**：手势层重构以解决 R1-1 —— `GestureDetector(onTapUp)` 与
  `SelectionArea` 竞技场冲突的修法（架构阶段定：如改用不参与竞技场的 `Listener` 手动 tap 判定、或把
  toggle 接入选区空白点击、或调整命中层级），必须保持 `_onBodyTapUp` 既有语义：左右 15% 边缘（分页）优先、
  中部 1/3 toggle、其余区域收起选中/隐藏 Chrome（`:181-209`）；不得回退长按选中、滚动、进度条拖动。
  P2：`_page`/`_goChapter` 语义不变（`:211-216`），修好 R2-2 后自然形成"章内翻页→章末续章"。
  P3：`_doTranslate` catch（`:386-392`）需把"是否设置引导"传给错误浮层；新增"去设置"动作
  （push `SettingsPage(translateBackend: widget.translateBackend)`）。
- **`app/lib/engines/paged_web_view.dart`**：`didUpdateWidget` 增加 href/html 变化检测并触发重载
  （`:70-75`）；`_runBool` 返回值解析改为兼容 Dart `bool`/字符串（`:108-113`）；保留 `_applyStyle`
  （fontSize/theme）、`onLoadStop` 注入 `paginationJs`、`onProgress`/`onSelectedText` 回传、
  `buildPagedWebViewSettings(disableContextMenu: true)`（REQ-005 不得回退）。
- **`app/lib/widgets/translation_popup.dart`**：`OverlayError` 增加**可选**动作（如 `onOpenSettings`/
  额外按钮"去设置"），不传时行为与现状一致（`:147-181`）；`TranslationResultCard` 标签逻辑不变
  （REQ-006 已修，`:19-23`）。
- **`app/lib/pages/settings_page.dart`（可能零改动）**：作为"去设置"目标页被 push；其 `_load`/`getConfig`/
  key 回填已具备（`:54-72`）。**注**：R3-3 指出其当前无应用内入口，本 REQ 的引导即入口之一；是否在书架页
  补设置入口列为 P1（见 §4），不阻塞 P0。
- **`app/lib/widgets/reader_chrome.dart`（预期零改动）**：顶底栏布局与按钮回调不变；US-4/US-5 仅验证行为。

### 3.2 数据模型 / 接口

- **`reading_progress` / `Locator`：零变更**。切章仍走 `href = chapter_%04d.xhtml` + `progression` 约定
  （`reader_page.dart:176`、`:669-672`），无 schema/迁移，`user_version` 不变。
- **翻译核心（`core/src/dict/translation.rs`）**：仅 US-11 的错误文案追加"设置"引导（`:562-567`）；
  `translate_routed`/`translate_auto` 策略逻辑不变；`FALLBACK_REASON_*` 常量不变。既有断言用 `contains`
  （`:1724-1725`），追加不破坏。
- **翻译桥接（`core/src/api.rs`）**：`translate`/`translate_get_config`/`translate_set_strategy` 签名不变；
  无 FRB 再生成需求（除非架构选择改 DTO，本 REQ 不要求）。
- **`settings` 表 / `translation_cache` 表**：无 schema 变更；`translate.default_provider` 默认 `auto`
  （`store/translation.rs:21`）沿用。
- **`flutter_inappwebview` 插件 API**：重载需用 `InAppWebViewController.loadData(data, baseUrl:)`
  （`flutter_inappwebview_android-1.1.3/.../in_app_webview_controller.dart:1815`）；**无新增依赖**。

### 3.3 听读进度 / Locator

- **零模型变更**：三大问题均不触碰 `Locator`/句↔Locator/`reading_progress`；分页切章后仍写 `progression=0.0`
  的章首进度（US-5）。听书（`ListenPage`/`SystemTtsEngine`）不在本期范围，**不得**因手势层重构或分页重载
  受影响（回归确认 REQ-005/006 用例）。

### 3.4 测试面

- **新增**：`app/integration_test/reader_interaction_test.dart`（真实 ReaderPage，滚动模式覆盖 US-1/2/4/12）；
  `app/test/` 下 PagedWebView 重载与 `_runBool` 解析单测（US-6/US-7，依赖架构提供的可测出口）；
  `_page` 章内/章末决策单测（US-8，依赖可注入 fake 分页控制器）。
- **更新**：`app/integration_test/screenshots_test.dart`（删除 `:147-179` 合成 Column，`reader_chrome`/
  `reader_more` 改真实点击文字，`:247` 落点改文字 center）；`app/test/reader_page_test.dart`
  （新增分页"下一章"新 href 断言、手势矩阵；`_toggleChrome` 落点改为文字 center 或显式空白并注明）；
  `app/test/translate_reader_test.dart`（新增无 key 引导 + "去设置"跳转 + 注入透传）。
- **回归**：`reader_selection_test.dart`（长按选中）、`settings_page_test.dart`（getConfig/回填）、
  `translate_ffi_test.dart`、`no_hardcoded_key_test.dart`、`screenshot_golden_test.dart`（错误浮层若新增
  按钮可能影响 golden，需同步）。
- **Rust**：`core/src/dict/translation.rs` 单测（US-10/US-11）；`cargo test --release` 全量。

### 3.5 回归面（非空）

- **core**：`dict`/`translation`/`store::translation` 既有单测；`translate_routed` 策略/回退/缓存语义不变。
- **Flutter**：`reader_page_test.dart`、`reader_selection_test.dart`、`translate_reader_test.dart`、
  `settings_page_test.dart`、`listen_page_test.dart`（听书不受影响）、goldens/截图。
- **集成/构建**：`bash scripts/ui-screenshots.sh REQ-007`（Linux + xvfb）；Android 真机手工清单（US-17）；
  `bash scripts/build-android-local.sh` 出 APK。
- **闸门**：DDD 分层（`pages/**`/`widgets/**`/`engines/**` 属 interface，禁直接 import `src/rust/`；翻译
  文案改动在 core domain，不引入 store 依赖）、CRAP、变异分数；`flutter_inappwebview` 平台约束（Linux 无
  WebView → 分页只做 widget/单测 + 真机）。

---

## 4. 依赖与优先级

| 项 | 内容 | 依赖/前置 | 优先级 |
|---|---|---|---|
| P1 手势修复 | 中部点击（含文字）可靠 toggle | REQ-004 手势层；Flutter `SelectableRegion` 行为 | **P0** |
| P1 测试基建 | 真实 integration_test + 去合成页 | `app/integration_test/` 现有 harness、`screenshots_test.dart` | **P0** |
| P2 分页重载 | `didUpdateWidget` 处理 href/html | `PagedWebView`、插件 `loadData` | **P0** |
| P2 JS 解析 | `_runBool` 兼容 Dart bool | `PagedWebView`、插件 `evaluateJavascript` | **P0** |
| P2 滚动切章 | 既有能力回归守住 | `_goChapter`/`reader_page_test.dart:45-67` | **P0** |
| P3 在线链路 | `auto`+key → deepl | REQ-006 已交付（`translation.rs:451-570`） | **P0**（确认） |
| P3 引导文案 | 错误含"设置"+ 去设置按钮 | `translation.rs:562-567`、`OverlayError`、`SettingsPage` | **P0** |
| 设置页入口 | 书架页补设置入口（R3-3） | `LibraryPage`/`SettingsPage` | P1（可选，不阻塞 P0） |
| 可测出口 | 分页重载/`_runBool`/`_page` 的测试缝 | 架构阶段在 02-adr 落定 | **P0**（架构前置） |
| TTS/笔记/Provider 进阶 | — | — | 不做（另立 REQ） |

- **与既有 REQ 关系**：REQ-001 提供分页渲染/进度（复用）；REQ-003 提供选中→翻译/查词通路（复用）；
  REQ-004 提供沉浸态/顶底栏/热区（本 REQ 修其手势可达性，不改布局）；REQ-005 提供 `disableContextMenu`/
  选区回传/听书（回归守住）；REQ-006 提供 `auto` 策略/在线翻译/回退标签（本 REQ 仅补引导入口）。能力
  **复用不重做**。
- **优先级说明**：三问题均为用户反馈 **P0**；P1 仅"书架页设置入口"为可选增强。

---

## 5. 风险

1. **手势修复回退风险（高）**：修 R1-1 时若简单"移除 `GestureDetector`"或改命中层级，可能破坏长按选中/
   拖拽选柄/垂直滚动/边缘热区/进度条拖动。缓解：US-2 手势矩阵 + US-16 全量回归；架构阶段出手势命中
   层级图；REQ-005 的 `disableContextMenu`/选区回传专项回归。
2. **Linux 无真实 WebView，分页修复"测不到"（高）**：`flutter_inappwebview` 不支持 Linux，分页模式无法在
   Linux integration_test 实跑，存在"widget/单测绿、真机仍坏"的风险。缓解：US-6/US-7/US-8 用可测出口
   覆盖重载与返回值解析；US-17 Android 真机清单逐项验收；交付文档记录未覆盖项。
3. **重载时机与进度/样式竞态（中-高）**：`loadData` 后 `onLoadStop` 才注入 `paginationJs`/applyStyle；若
   `_jumpToProgress(0.0)`/`relayout` 早于新文档就绪，可能作用在旧文档或空文档上。缓解：US-5 断言切章后
   渲染新章文本 + `progression=0.0`；架构明确"重载完成后再 relayout"的时序。
4. **JS 返回值类型多样（中）**：插件 `json.decode` 可能返回 `bool`/`num`/`String`/`null`；修 `_runBool` 时
   只处理 `bool` 可能漏掉字符串路径。缓解：US-7 明确兼容 `bool` 与 `'true'`，其余按 false。
5. **错误文案改动破坏既有断言（中）**：REQ-006 测试断言 `contains("未配置在线翻译 API Key")`/
   `contains("离线翻译未命中")`。缓解：US-11 要求"追加"而非替换；US-16 全量回归。
6. **`OverlayError` 新增按钮影响 golden/其它错误（中）**：`OverlayError` 同时用于翻译与查词错误；新增
   "去设置"若成为默认按钮会污染查词错误。缓解：US-12 明确"去设置"仅在翻译未配置时出现；golden 同步。
7. **设置页不可达 / 后端初始化（中）**：R3-3 显示 `SettingsPage` 无应用内入口；从阅读器 push 时若
   `translateBackend` 为 null 会走默认 Rust 后端，测试环境可能抛错。缓解：US-12 要求透传注入的
   `translateBackend`；`SettingsPage._load` 已有 catch 兜底（`:68-71`）；书架页入口列为 P1。
8. **合成页清理带来的截图清单变化（低-中）**：删除合成 `reader_chrome` 后，`product-preview.manifest.json`
   的截图与设计稿对照可能失配。缓解：US-3 要求脚本退出码 0；清单/对照在交付阶段同步。
9. **范围蔓延（中）**：容易顺手做书架设置入口、Provider 管理、手势大改。缓解：§1.2 划界；仅 P1 可选。

---

## 6. 闸门1 自评

- [x] **验收标准全部可测（无"体验好"类不可测词）**：US-1~US-17 每条均为可断言观察项 ——
  - 集成测试：真实 `ReaderPage` 文字 center 的 `tapAt` → `find.byTooltip('返回书架')`/`find.byType(ReaderBottomBar)`
    存在性；`longPress` → `ReaderSelectionToolbar` 出现且 Chrome 不出现；`drag` 后滚动偏移 > 0；
    点"下一章" → 下一章文本 + `backend.saved?.href`；点"去设置" → `find.byType(SettingsPage)`；
  - widget 测试：分页 fake 构建器捕获 `href == 'chapter_0002.xhtml'`、错误浮层 `find.text('去设置')`、
    译文卡片 `"在线"`/`"deepl"`/`"离线"`；
  - 单测：`translate_routed` 的 `provider=="deepl"`/`from_cache==false`、错误串 `contains("设置")` 等三段、
    `_runBool` 对 `bool true`/`'true'`/`false`/`null` 的返回、重载出口调用次数、`_page` 章内/章末决策；
  - [真机]：Android 分页翻页/切章/呼出/去设置 —— 明确标注为人工清单。
  每条标注了问题号/根因号/原型图映射（01-immersive/02-menus/04-selection/08-translation/03-settings）。
- [x] **与既有 REQ 无重复**：REQ-004（沉浸态/顶底栏/热区）本 REQ 只修手势可达性（US-1~US-3），不重做
  布局；REQ-001 分页渲染/进度、REQ-003 翻译查词通路、REQ-005 原生菜单/选区回传、REQ-006 `auto` 策略/
  在线翻译/回退标签均**复用不重做**（US-4/US-6/US-9/US-10/US-13/US-16 明确为回归确认）；US-11/US-12 的
  "设置引导/去设置入口"为 REQ-006 明确遗留（其 §1.2 未含引导 UI），非重复。
- [x] **影响面清单非空**：§3 覆盖 Flutter（`reader_page`/`paged_web_view`/`translation_popup`/`settings_page`/
  `reader_chrome`）、数据模型与接口（`reading_progress`/`Locator` 零变更、翻译错误文案、桥接签名不变、
  插件 `loadData`）、听读进度（零模型变更）、测试面（新增集成/widget/单测 + 更新截图/reader_page/translate
  测试 + core 回归）、回归面（core/Flutter/集成/构建/闸门），均列具体 file:line 与约束。
