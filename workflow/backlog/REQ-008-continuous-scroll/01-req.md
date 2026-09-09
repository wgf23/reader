<!-- wf-meta: req=REQ-008-continuous-scroll | phase=requirements | agent=req-analyst | date=2026-09-09 | gate=passed -->
# REQ-008-continuous-scroll · 阅读器连续滚动阅读（章节无缝衔接）—— 需求分析

## 1. 背景与目标

### 1.1 问题现象（用户原始诉求，不可偏离）

- **滚动模式一章读完后必须手动点底栏"下一章"才能继续**：当前滚动模式正文容器
  `SingleChildScrollView` 只挂载 `view.chapters[_chapterIndex]` **一章**的内容，滚到本章末尾即
  到达 `maxScrollExtent`，继续下滑无任何新内容；用户反馈该交互"别扭"（阅读流被打断，需呼出
  底栏再点按钮）。
- **期望**：滚到章末时自动加载并接续下一章内容，形成连续阅读流；到最后一章自然停止。
- **约束（不得破坏）**：阅读进度保存/恢复（`reading_progress`）、Locator 定位（`href + progression`
  契约）、书签、听读同进度（听书跨章朗读）、章节进度显示；分页模式（`pagedMode`）保留可切换。

### 1.2 成功标准与范围划界

**成功标准一句话**：在**真实 `ReaderPage` 滚动模式（真实 `drag`/`fling`）**下，正文滚到章末时
**无需任何点击**即自动接续渲染下一章正文与标题，直至最后一章自然停止；滚动过程中
`reading_progress` 始终写入**当前可见章**的 `href`（`chapter_%04d.xhtml`）与**章内** `progression`
（`0.0..=1.0`），重开可跨章恢复；听读同进度、书签、分页模式、章节进度显示零回退；全部以真实
`integration_test`（滚动模式）+ widget 测试 + 单测分层验证，禁止合成页绕过。

**本期范围（P0，必须）**：

1. 滚动模式连续流：当前章内容之后自动接续下一章（标题 + 正文），滚到底无需点"下一章"。
2. 到最后一章继续滚动自然停止：不越界、不崩溃、不重复加载同一章。
3. 滚动过程中的进度写入：写**当前可见章**的 `href` + 章内 `progression`；跨章后 href 切换、
   progression 归零并按新章重新增长；重开恢复到该位置（跨章恢复）。
4. 章节进度显示（底栏 `_chapterProgress` / `ReaderBottomBar.progress`）：随滚动更新，跨章时切换
   到新章进度；顶栏章节名随可见章更新。
5. 约束零回退：听读同进度（听书跨章）、书签切换、`reading_progress` / `href+progression` 契约、
   分页模式（翻页/切章）保持可用。
6. 失败路径：下一章内容不可用时保留已渲染内容、给出非阻断提示、不崩溃、不重复重试。
7. 性能/内存：不得一次性构建全书所有章节正文；已构建章节数有界（详见 US-11）。

**明确不做（另立 REQ）**：分页模式的章末续章（REQ-001/REQ-007 已交付，本 REQ 仅回归守住）；
听书功能本身（REQ-005/006）；书签持久化/书签列表（NOTE-06，本 REQ 仅守住会话内切换）；
笔记/高亮（NOTE 系列）；全文搜索、翻译/查词（TRANS/REQ-003/006）；阅读器视觉改版（REQ-004）；
`LocatorResolver` 完整实现（`core/src/locator/mod.rs` 仍是 stub，本 REQ 不扩其能力）。

### 1.3 根因 / 现状核实（逐条 Read 源码，含 file:line 证据）

> 结论：本 REQ 是**滚动模式专属**缺口，与既有 REQ 的"分页章间无缝""听书章末连播"是不同
> 机制、不同入口，**不重复**。每条均给出已核对的证据。

| 编号 | 结论 | 证据（已逐条核对） |
|---|---|---|
| **R1** | **滚动模式只挂载当前一章**：`build` 取 `view.chapters[_chapterIndex]` 单章传入 `_buildArticleBody`；滚动分支的 `SingleChildScrollView` 内 `Column` 只有该章的 `Text(chapter.title)` + `Text(chapter.text)`。因此滚到章末即 `maxScrollExtent`，没有下一章内容可滚入。 | `app/lib/pages/reader_page.dart:483`（`final chapter = view.chapters[_chapterIndex];`）、`:521`（`_buildArticleBody(view, chapter, fg)`）、`:633-658`（`return SingleChildScrollView(...)`；`:644` 标题、`:646-654` 正文） |
| **R2** | **`_onScroll` 只算章内进度，无触底检测、不落盘**：监听器仅计算 `_chapterProgress = offset / max`；未调用 `_saveProgress`，也未判断"接近章末"。`grep` 确认 `_saveProgress` 的调用点只有 `_goChapter`(:177)、`_onProgressSeek`(:241)、`_onChapterSelect`(:257)、分页 `onProgress`(:627)——**滚动过程本身不持久化进度**。 | `app/lib/pages/reader_page.dart:117`（`addListener(_onScroll)`）、`:158-164`（`_onScroll` 全文）、`:181-189`（`_saveProgress`，含 300ms 节流 + href 由 `_chapterIndex` 派生） |
| **R3** | **章切换只有手动 `_goChapter`**：`_goChapter(delta)` 改 `_chapterIndex` 并 `setState` 重建；底栏"下一章"即 `onNextChapter: () => _goChapter(1)`。滚动模式没有其它自动续章路径。 | `app/lib/pages/reader_page.dart:166-179`（`_goChapter`）、`:558`（`onNextChapter: () => _goChapter(1)`）、`app/lib/widgets/reader_chrome.dart:123-126`（"下一章"按钮） |
| **R4** | **分页模式已有"章末续章"（非滚动）**：分页翻页走 `PageTurnCoordinator`：`nextPage()` 返回 `false`（章末）才 `goChapter(delta)`；章内翻页成功不跳章。该路径仅分页模式边缘点击触发，与滚动模式无关。 | `app/lib/pages/reader_page.dart:218-222`（`_page` → `PageTurnCoordinator`）、`app/lib/engines/paged_view_controls.dart:37-40`（章末才 `goChapter`）、REQ-007 `01-req.md:50`（R2-2 修复记录）、REQ-007 `01-req.md:114-118`（US-5 分页切章新 href） |
| **R5** | **REQ-001 的"章间无缝"是分页能力，滚动模式当时是占位**：REQ-001 明确"P0 用 Flutter Text 滚动模式渲染章节纯文本（占位实现）""分页模式为主、滚动模式保留"；其 US-6"翻到章末并继续→自动进入下一章第一页（章间无缝）"属于分页/WebView 场景。 | REQ-001 `01-req.md:5-7`、`:20`（US-6）、`:44`（闸门自评"滚动模式是占位，本需求是分页渲染"）；REQ-004 `01-req.md:61-66`（滚动模式仅滑动、无边缘翻页） |
| **R6** | **听书跨章是独立机制，不提供视觉连续滚动**：`ListenPage` 在句完成且 `autoNext` 时 `_loadNextChapter()`，按 href 取句并写 `reading_progress(nextHref, 0.0)`；它是音频连播，不驱动阅读页的滚动视图。 | `app/lib/pages/listen_page.dart:171-176`（autoNext → `_loadNextChapter`）、`:196-230`（加载下一章 + `:219` 写进度）、`reader_page.dart:318-337`（`_openListen` 传 href/progression）、`:340-355`（`_reloadProgress` 重读并跳转） |
| **R7** | **进度/定位契约现状**：`reading_progress` 表为 `(book_id PK, href, progression, updated_at)`；`save_progress` UPSERT、`load_progress` 读单条；Flutter 侧 DTO 即 `ProgressData{href, progression}`；`LocatorResolver` 在 core 仍是 TODO stub（`href + progression` 是当前唯一生效的定位契约）。 | `core/src/store/mod.rs:283-289`（DDL）、`:73-84`（save）、`:87-104`（load）；`app/lib/services/library_backend.dart:44-49`（`ProgressData`）、`:65`/`:67`（save/load）；`core/src/locator/mod.rs:1-13`（stub）；`app/lib/pages/reader_page.dart:148-156`（`_chapterIndexForHref` 解析 `chapter_(\d+).xhtml`） |
| **R8** | **章内进度显示依赖 `_chapterProgress`**：底栏 `Slider(value: progress)` + `'${(progress*100).round()}%'`，由 `_chapterProgress` 驱动；`_onScroll` 当前用 `offset/max`（只挂一章时恰好是章内比例，连续流下会变成全书比例，必须改为章内）。 | `app/lib/widgets/reader_chrome.dart:104-111`、`app/lib/pages/reader_page.dart:555`（`progress: _chapterProgress`）、`:158-164` |
| **R9** | **书签当前是会话内状态**：`_bookmarked` 仅 `setState` 切换图标，无持久化；本 REQ 只要求不破坏该切换语义。 | `app/lib/pages/reader_page.dart:91`（`_bookmarked = false`）、`:560`（`onBookmark: () => setState(() => _bookmarked = !_bookmarked)`） |
| **R10** | **恢复跳转是"整段比例"跳转**：滚动模式 `_jumpToProgress(v)` 直接 `jumpTo(max * v)`；只挂一章时成立，连续流下 `max` 是全书总高，需改为"章起点偏移 + progression × 章高"。 | `app/lib/pages/reader_page.dart:244-253`（`_jumpToProgress`）、`:135`/`:349`（加载/重读进度赋给 `_chapterProgress`） |
| **R11** | **数据已在内存，无新增 IO**：`openBook` 一次性返回 `BookViewData.chapters`（含每章 `title/text`），滚动模式渲染纯 `Text(chapter.text)`，不经过 `chapterHtml`；因此本 REQ 主要是 Flutter 渲染/滚动编排改动，core/schema/FFI 可零变更。 | `app/lib/services/library_backend.dart:32-42`（`BookViewData`/`ChapterData`）、`:56`（`openBook`）、`app/lib/pages/reader_page.dart:597-632`（`chapterHtml` 仅分页分支使用） |

**根因结论（供架构阶段参考，非本阶段实现决定）**：滚动模式"只能读当前章"的唯一根因是 R1（滚动视图只
挂一章）+ R2（无触底检测/无滚动落盘）；章切换能力 R3 只提供了手动入口。R4/R5/R6 分别说明"分页章末
续章""听书章末连播"是**另外的、已交付的机制**，本 REQ 不得改动其语义，只需回归守住。R7/R10 说明
进度/恢复在连续流下必须保持"章内 progression"语义并改为按章定位。

### 1.4 原型权威性与 UI 映射（`docs/wireframes/**` 为 UI 权威规范）

| 屏 / 交互 | 原型图 | 本 REQ 涉及 | 是否改变布局 |
|---|---|---|---|
| 沉浸态滚动正文（连续流） | `docs/wireframes/reader-ui-v2/01-immersive.svg` | 多章正文连续滚动；下一章标题随滚动进入视口 | **零布局改动**（沿用正文排版，无新增视觉元素） |
| 顶底栏呼出态（章节名/进度条/上一章·下一章） | `docs/wireframes/reader-ui-v2/02-menus.svg` | 顶栏章节名随可见章更新；底栏进度条随章内进度更新 | 零布局改动 |
| 失败提示（非阻断） | 无新增原型图 | 复用既有 `OverlayError` 样式（`translation_popup.dart`）呈现"下一章加载失败" | 不新增布局，仅复用现有浮层样式 |

> 结论：本 REQ 是**滚动渲染行为**改动，**无新增视觉元素**；实现阶段禁止对上述线框布局自由发挥
> （闸门3 逐屏核对，deviation=0）。

---

## 2. 用户故事与验收标准（Given/When/Then，必须可测；标注验证层级/原型图）

> **验证层级标注**：`[集成测试]` = 真实 `ReaderPage` + 真实 `drag`/`fling`，跑在
> `app/integration_test/*.dart`（Linux 无 WebView，滚动模式可实跑）；`[widget 测试]` =
> `app/test/*.dart` 注入 fake backend；`[单测]` = 纯函数/可测出口；`[真机]` = Android 真机人工清单。

### 故事 1：连续滚动自动衔接 —— 作为读者，我想要一直往下滚就自然进入下一章，以便不被打断

- **US-1 滚到章末自动出现下一章正文与标题（核心，P0，[集成测试]，01-immersive）**
  - Given 真实 `ReaderPage` 滚动模式，fake backend 提供两章且第一章足够长以产生滚动
    （参考 `app/integration_test/reader_interaction_test.dart:19-42` 的 `_ch1Text` 范式），
    初始 Chrome 隐藏（`find.byTooltip('返回书架')` 为 `findsNothing`），第二章文本不可见
  - When 用真实手势反复 `tester.drag(find.byType(Scrollable).first, const Offset(0, -400))` +
    `pumpAndSettle` 直到 `ScrollableState.position.pixels >= maxScrollExtent - 1.0`
  - Then 第二章正文 `find.text('<第二章文本>')` 为 `findsOneWidget`、第二章标题
    `find.text('<第二章标题>')` 为 `findsOneWidget`；**且期间未点击"下一章"**（此刻
    `find.byType(ReaderBottomBar)` 仍为 `findsNothing`，证明未通过按钮触发）
  - Given 已进入第二章 When 继续 `drag` 向上 Then 第二章内容继续可滚（offset 继续增大）
- **US-2 到最后一章自然停止、不越界、不崩溃、不重复（P0，[集成测试]，01-immersive）**
  - Given 真实 `ReaderPage`，三章（前两章长、末章短）
  - When 连续 `drag` 到底直到 `pixels >= maxScrollExtent - 1.0`，再额外 `drag(0,-400)` 数次
  - Then `pixels` 保持在 `maxScrollExtent`（容差 1.0）不再增长；`tester.takeException()` 为
    `null`；末章正文 `findsOneWidget`（未重复渲染）；不存在不存在的第 4 章文本/标题
  - Given 末章末 When 呼出底栏 Then "下一章"按钮禁用（`TextButton.onPressed == null`，见
    `reader_chrome.dart:123-126`）
- **US-3 滚动过程中写入"当前可见章"的 href + 章内 progression（P0，[集成测试]，01-immersive + 02-menus）**
  - Given 真实 `ReaderPage` 两章、第一章足够长
  - When 仅在第一章内 `drag` 后等待防抖窗口（`pumpAndSettle` + 真实延时 ≥ 350ms）
  - Then `backend.saved?.href == 'chapter_0001.xhtml'` 且 `0.0 <= saved.progression <= 1.0`
  - When 继续 `drag` 直到第二章正文进入视口并停下，再等待防抖窗口
  - Then `backend.saved?.href == 'chapter_0002.xhtml'`；`saved.progression` 为第二章内比例
    （`0.0 <= p <= 1.0`）；**不得**把全书比例写入 `progression`
  - Given 已在第二章内 When 再滚动一小段 Then `href` 保持 `chapter_0002.xhtml` 且 `progression`
    随滚动变化（单调性不作硬性要求，仅要求数值变化/仍在 `[0,1]`）
- **US-4 重开恢复到跨章位置（P0，[集成测试] + [widget 测试]，01-immersive）**
  - Given 承接 US-3 已保存 `href=chapter_0002.xhtml`、`progression=p>0` 的进度
  - When 重建真实 `ReaderPage`（同一 backend 实例）
  - Then 第二章正文可见（`find.text('<第二章文本>')` 为 `findsOneWidget`）；视口滚动偏移落在
    第二章区间内（`pixels >= 第二章起点偏移 - 1.0`，起点可由 fake backend 各章文本长度/可测出口
    确定）；不是停在全书 0% 或第一章
  - Given `progression==0.0` 的章首进度 When 重开 Then 定位到该章起点

### 故事 2：进度显示与导航 —— 作为读者，我想要进度条与章节名反映我正在读的那一章

- **US-5 章内进度随滚动更新、跨章切换到新章进度（P0，[widget 测试]，02-menus）**
  - Given `ReaderPage` 两章（第一章长到可滚动），呼出底栏
  - When 在第一章内滚动 Then 底栏百分比文本（`reader_chrome.dart:111`）与 `Slider.value` 增大，
    且始终 `<= 1.0`
  - When 滚入第二章 Then `Slider.value` 回到接近 `0.0`（新章起点）并随后续滚动重新增大；
    顶栏章节名（`ReaderTopBar.chapter`）显示第二章标题
- **US-6 去重：章末抖动/重复触发不得重复加载同一章（P0，[widget 测试] + [单测]，01-immersive）**
  - Given 两章，已滚到接近第一章末尾
  - When 在章末附近反复小幅 `drag`（±50px 抖动）多次
  - Then 第二章标题在渲染树中 `findsOneWidget`、第二章正文 `findsOneWidget`（不出现两份）；
    不抛重复 Key/重复 GlobalKey 异常（`tester.takeException()` 为 `null`）；已渲染章节数不超过
    `view.chapters.length`（经架构提供的可测出口或 finder 计数断言）
- **US-7 上一章 / 目录跳转在连续流中仍正确（P0，[widget 测试]，02-menus）**
  - Given 连续流已渲染到第二章
  - When 呼出底栏点"上一章" Then 视口滚动到第一章区间（第一章标题可见/`pixels` 减小到第一章范围），
    `backend.saved?.href == 'chapter_0001.xhtml'`
  - When 打开目录选择第三章 Then 视口滚动到第三章、第三章标题可见，
    `backend.saved?.href == 'chapter_0003.xhtml'`
  - 说明：`_goChapter` 在连续流中语义由"重建单章"改为"滚动定位到目标章"，但进度写入语义不变

### 故事 3：约束零回退 —— 作为产品，我想要连续滚动不破坏既有进度/听读/书签/分页

- **US-8 听读同进度：听书跨章与本 REQ 互不破坏（P0，[集成测试] + [widget 测试]，无原型改动）**
  - Given 真实 `ReaderPage` 注入 `ttsBackend`/`ttsEngine` fake（参考
    `app/test/reader_page_test.dart:213-270`），滚动模式
  - When 进入 `ListenPage` 并模拟其写入第二章进度（`backend.saved = ProgressData(href:
    'chapter_0002.xhtml', progression: 0.0)`）后返回
  - Then `_reloadProgress` 后阅读页定位到第二章（第二章正文可见）；返回后连续滚动仍可自动衔接；
    `backend.saved?.href` 仍为听书写入的第二章
  - Given 既有 `app/test/listen_page_test.dart` 的"章末连播/末章停止/下一章加载失败"用例
    （REQ-005 05-delivery.md:64 US-18）When 全量运行 Then 全绿，语义不变
- **US-9 书签 / Locator 契约 / 分页模式零回退（P0，[widget 测试]，02-menus）**
  - Given 连续滚动模式呼出底栏 When 点书签 Then 图标在"加书签/取消书签"间切换（幂等，沿用
    `reader_page_test.dart:321-334`）
  - Given 通过 Aa 面板切换到分页模式 Then 分页构建器/`PagedWebView` 渲染（沿用
    `initialPagedMode`/`pagedViewBuilder`）；底栏"下一章"仍以新 href 重建并保存
    `chapter_0002.xhtml`、`progression==0.0`（沿用 REQ-007 US-5）；再切回滚动模式 Then 连续
    滚动仍工作
  - Given 任意进度写入 Then `href` 恒匹配 `chapter_\d{4}\.xhtml`、`progression ∈ [0,1]`，
    `reading_progress` 表/schema/`ProgressData` DTO 零变更（`store/mod.rs:283-289`、
    `library_backend.dart:44-49`）
- **US-10 下一章不可用时的失败路径（P0，[单测] + [widget 测试]，无原型改动）**
  - Given 架构阶段提供的可注入"章节内容/渲染出口"（如 chapter provider 或渲染回调），当请求
    下一章时抛出异常或返回不可用内容
  - When 滚到章末触发自动衔接
  - Then 已渲染的当前章内容仍保留（当前章正文 `findsOneWidget`）；出现非阻断错误提示
    （可断言文案含"加载"与"失败"或复用 `OverlayError` 组件）；`tester.takeException()` 为
    `null`；同一失败章的重试次数有界（加载出口调用次数 ≤ 1 次/章，不进入无限重试）
  - 说明：若架构选择"一次性挂载全部章节"，则本条以"某章文本为空/渲染异常"为触发条件，
    同样断言不崩溃、保留已渲染内容、有可观察提示

### 故事 4：性能与测试基建 —— 作为发布者，我想要连续流可控、真实验证、可交付

- **US-11 性能/内存：已构建章节数有界，不一次性构建全书（P0，[widget 测试]，无原型改动）**
  - Given 架构阶段提供可测出口（如记录"已构建章节正文 widget 数"或章节构建器调用计数）
  - When 打开一本含 ≥50 章的书并仅滚动到第二章
  - Then 已构建/已渲染的章节正文 widget 数 ≤ 视口内章节数 + 预加载缓冲上限（上限由架构在
    02-adr 定义并写入验收，如 3），**不**等于全书章节数
  - Given 滚动到最后一章 Then 有界性仍成立（不因连续滚动而无限增长；如需保留已读章节，需在
    架构中给出上限与回收策略并断言）
- **US-12 真实 integration_test 范式 + 静态守卫（P0，[集成测试]）**
  - Given 新增 `app/integration_test/reader_continuous_scroll_test.dart`
  - Then 全程真实 `ReaderPage` + 真实 `drag`/`fling`；文件内**不出现**合成
    `ReaderTopBar(`/`ReaderBottomBar(`（由 `app/test/no_synthetic_chrome_test.dart` 扫描
    `integration_test/*.dart` 守卫）；覆盖 US-1/US-2/US-3/US-4/US-8
  - When 运行 `flutter test integration_test -d linux`（xvfb）Then 全部通过
- **US-13 Android 真机验收清单（P0，[真机]）**
  - Given `bash scripts/build-android-local.sh` 产出的 APK 安装于 Android 真机
  - Then 人工逐项通过：① 滚动到底自动出现下一章正文/标题，无需点"下一章"；② 最后一章滚动停止、
    不崩溃；③ 退出重开恢复到滚动到的章节位置；④ 听书跨章后返回阅读页定位一致；⑤ 书签切换、
    Aa 切分页模式后翻页/切章正常

---

## 3. 影响面分析（必须非空）

### 3.1 既有功能（Flutter / interface 层）

- **`app/lib/pages/reader_page.dart`（核心，必改）**：
  - 滚动分支 `_buildArticleBody`（`:633-658`）由"单章 `Text`"改为"多章连续内容"（如
    `CustomScrollView`/`SliverList.builder` 按章构建，或单章渲染 + 触底追加），保留
    `SelectionArea` 选中语义（`contextMenuBuilder` 置空、`onSelectionChanged` 回传，`:636-640`）。
  - `_onScroll`（`:158-164`）增加"当前可见章"判定与触底检测；当前可见章驱动 `_chapterIndex`
    并调用 `_saveProgress(章内 progression)`；章内比例改为"相对当前章起点/高度"而非
    `offset/全书 max`。
  - `_goChapter`（`:166-179`）在连续流中语义变为"滚动定位到目标章"（用于底栏上一/下一章、目录），
    仍写目标章 `progression=0.0`；`_jumpToProgress`（`:244-253`）由"全书比例 jumpTo"改为
    "章起点偏移 + progression×章高"。
  - 顶栏章节名（`:483`/`:547`）与底栏 `_chapterProgress`（`:555`）随可见章更新。
  - `_load`/`_reloadProgress`（`:127-146`/`:340-355`）恢复时按 `href` 定位章 + `progression`
    定位章内偏移；`_chapterIndexForHref`（`:148-156`）沿用。
- **`app/lib/engines/reflow_engine.dart`（接口现状）**：当前为纯抽象骨架（`open/pageCount/goto/
  setStyle`，`:5-19`），**未被 `ReaderPage` 使用**（滚动模式直接渲染 `Text`）。本 REQ 不要求扩接口；
  若架构选择把"连续流章节编排"下沉到引擎，需保持其为可选实现且不改变对外契约（标记供架构决策）。
- **`app/lib/widgets/reader_chrome.dart`（预期零改动）**：`ReaderTopBar.chapter`、`ReaderBottomBar.
  progress/chapterIndex/chapterCount` 入参语义不变（`:7-50`/`:53-132`）；仅由页面传入"可见章"值。
- **`app/lib/pages/listen_page.dart`（预期零改动）**：跨章逻辑（`:196-230`）与进度写入（`:219`）
  不因本 REQ 改动；仅作为回归面。
- **`app/lib/pages/body_tap_policy.dart`（预期零改动）**：`BodyTapTracker` 已把"拖动"判为
  非 tap（位移 > `kTouchSlop` 即失效，`:108-114`），连续滚动的拖拽不会误触 Chrome toggle，
  回归守住即可。

### 3.2 数据模型 / 接口

- **`reading_progress` / `ProgressData`：零变更**。仍为 `(book_id, href, progression, updated_at)`
  （`core/src/store/mod.rs:283-289`）与 DTO `{href, progression}`（`library_backend.dart:44-49`）；
  `saveProgress/loadProgress` 签名不变（`:65`/`:67`）；`user_version` 不变。
- **core / FFI：预期零变更**。`openBook` 已一次性返回全部章节（`library_backend.dart:32-42`），
  连续滚动所需数据已在内存（R11）；`chapterHtml` 仅分页用（`reader_page.dart:597-632`）。若架构
  为"失败路径/懒加载"新增可测出口，应优先用 Flutter 侧注入（如 `chapterProvider`）而非改 FFI。
- **`Locator` 不变式**：`progression` 恒为**章内** `0.0..=1.0`，`href` 恒为章资源路径；连续滚动
  不得把全书进度写入 `progression`。`core/src/locator/mod.rs` 仍为 stub，本 REQ 不扩其能力。

### 3.3 听读进度 / Locator

- **零模型变更**：听书经 `ListenPage` 写 `reading_progress(href, progression)`，阅读页
  `_reloadProgress` 读回并定位（`reader_page.dart:340-355`）。连续滚动必须复用同一契约；跨章恢复
  由 US-4/US-8 覆盖。听书章末连播（`listen_page.dart:171-230`）语义不变，回归确认 REQ-005/006。
- **双向一致**：听书进入时传当前 `href/_chapterProgress`（`reader_page.dart:328-329`），连续滚动
  下该值必须是"当前可见章"的值，否则听书起点错位——US-3 保证可见章驱动 `_chapterIndex`。

### 3.4 书签 / 章节进度显示

- **书签**：当前仅会话内切换（`reader_page.dart:91`/`:560`），本 REQ 只做回归（US-9），不引入
  持久化（NOTE-06 另立）。
- **章节进度显示**：`_chapterProgress` 的语义从"单章 offset/max"变为"当前可见章的章内比例"；
  底栏百分比与 Slider（`reader_chrome.dart:104-111`）零布局改动（US-5）。

### 3.5 分页模式保留

- 分页分支（`reader_page.dart:597-632`）与 `PageTurnCoordinator`（`paged_view_controls.dart`）
  **不改动**；US-9 断言切换后翻页/切章仍以新 href 重建并保存章首进度（沿用 REQ-007 US-5）。
  模式切换入口（Aa 面板 `pagedMode`）不变。

### 3.6 性能 / 内存

- 当前单章渲染内存小；连续流若一次性构建全书所有章节的 `Text`（长书 + 大字号）会显著增加
  widget 树与布局开销。US-11 要求已构建章节数有界（视口 + 缓冲），架构在 02-adr 定义上限与
  回收策略；实现优先 `SliverList.builder`/`ListView.builder` 懒构建。
- `_onScroll` 高频回调需节流（已有 300ms `_saveProgress` 节流，`reader_page.dart:181-189`）；
  可见章判定应避免每次滚动都全量重算。

### 3.7 回归面（非空）

- **Flutter**：`app/test/reader_page_test.dart`（单章"下一章"、目录跳转、进度保存恢复、
  书签、分页切章、听书返回重读）、`reader_page_interaction_coverage_test.dart`、
  `reader_selection_test.dart`、`page_turn_coordinator_test.dart`、`listen_page_test.dart`、
  `screenshot_golden_test.dart`（若滚动正文渲染结构变化可能影响 golden，需同步）。
- **集成**：`app/integration_test/reader_interaction_test.dart`（US-1/2/4/12，REQ-007）、
  `screenshots_test.dart`、`app/test/no_synthetic_chrome_test.dart` 静态守卫。
- **core**：`cargo test --release -p reader_core`（预期零改动，但需全绿）。
- **构建/交付**：`flutter analyze` 0 issues；`bash scripts/ui-screenshots.sh REQ-008`；
  `bash scripts/build-android-local.sh` 出 `dist/reader-android-arm64-vX.Y.Z.apk`；US-13 真机清单。
- **DDD 分层**：改动集中在 `pages/**`（interface），禁止直接 import `src/rust/`；经
  `services/library_backend.dart` 访问后端。

---

## 4. 依赖与优先级

| 项 | 内容 | 依赖/前置 | 优先级 |
|---|---|---|---|
| 连续流渲染 | 多章内容连续滚动、触底自动衔接 | `reader_page.dart` 滚动分支；`BookViewData.chapters` 已在内存 | **P0** |
| 可见章进度 | `_onScroll` 判定可见章 + 写 `href`/章内 `progression` | `_saveProgress`/`_chapterIndexForHref`；`reading_progress` 契约 | **P0** |
| 跨章恢复 | `_load`/`_reloadProgress`/`_jumpToProgress` 按章定位 | `ProgressData`；`_jumpToProgress` 改造 | **P0** |
| 进度显示 | `_chapterProgress` 章内语义 + 顶栏可见章名 | `reader_chrome.dart`（零改动） | **P0** |
| 去重/末章停止 | 有界加载、抖动去重、末章边界 | 架构定义加载状态机 | **P0** |
| 失败路径 | 下一章不可用时不崩溃/有提示/不重试 | **架构提供可测出口**（US-10） | **P0**（架构前置） |
| 性能/内存有界 | 懒构建 + 缓冲上限 | **架构在 02-adr 定义上限**（US-11） | **P0**（架构前置） |
| 听读/书签/分页回归 | 零回退 | REQ-001/003/004/005/006/007 已交付 | **P0** |
| 真实集成测试 | 新增连续滚动集成用例 + 静态守卫 | `app/integration_test/`、`no_synthetic_chrome_test.dart` | **P0** |
| 真机验收 | Android 手动清单 | `scripts/build-android-local.sh` | **P0** |

- **与既有 REQ 关系（复用不重做）**：REQ-001 提供分页渲染/进度模型与"分页章间无缝"（本 REQ 仅
  滚动模式，R4/R5 区分）；REQ-004 提供沉浸态/顶底栏/Aa 模式切换（复用，不改布局）；REQ-005/006
  提供听书跨章与听读同进度（回归守住，R6）；REQ-007 修复了滚动模式手动"下一章"与真实集成测试
  范式（本 REQ 在其基础上把"手动"变"自动"，不改其修复语义，R3/R4）。
- **优先级说明**：全部为 P0（用户直接反馈的阅读流阻断）；无 P1/P2 项。

---

## 5. 风险

1. **连续流与"章内 progression"语义错位（高）**：若把全书滚动比例写入 `progression`，会破坏
   听读同进度与跨设备/重开恢复（`reading_progress` 唯一事实源）。缓解：US-3/US-4/US-9 明确
   `href=可见章`、`progression ∈ [0,1]` 章内值；架构在 02-adr 定义"可见章判定 + 章内比例"公式。
2. **恢复定位改造引入跳变（高）**：`_jumpToProgress` 从"整段比例"改为"章起点 + 章内偏移"，若
   章高在字体/字号/主题变化后重排，偏移会变。缓解：US-4 以"定位到章起点+章内比例"断言；
   架构明确"重排后按章重新计算偏移"；回归分页↔滚动互切位置不跳变（REQ-004 US-16）。
3. **真实集成测试的防抖/时间不确定性（中-高）**：`_saveProgress` 用 `DateTime.now()` 做 300ms
   节流（`reader_page.dart:184-185`），widget 测试假时钟不推进真实墙钟，滚动触发的保存可能被
   节流吞掉。缓解：集成测试用真实延时（`await Future.delayed` ≥ 350ms）后再断言；架构可考虑
   把节流改为可注入/`Timer` 化以便 fake-async 测试；US-3 明确等待防抖窗口。
4. **"可见章"判定抖动导致进度/章节名抖动（中）**：章边界附近小幅滚动可能在两章间反复切换。
   缓解：架构定义稳定判定（如"视口内占比最大/顶部锚点章" + 迟滞），US-5/US-6 断言不重复、
   进度仍在 `[0,1]`。
5. **重复加载/重复渲染（中）**：触底回调可能被多次触发（滚动抖动、`pumpAndSettle` 多次布局）。
   缓解：US-6 断言标题/正文 `findsOneWidget`、无重复 Key 异常；架构用"加载中/已加载"状态位。
6. **性能/内存回归（中）**：一次性挂载全书会拖慢长书。缓解：US-11 有界构建断言；架构定义懒构建
   与回收上限；回归打开大书首屏（READ-01）。
7. **失败路径缺少可测出口（中）**：当前 `openBook` 一次性返回全部文本，"下一章加载失败"不易触发。
   缓解：US-10 要求架构提供可注入章节出口（Flutter 侧优先）；若采用一次性挂载，则以"空章/渲染
   异常"为触发条件并保持同等断言。
8. **既有测试/golden 失配（中）**：滚动正文结构变化可能影响 `screenshot_golden_test.dart`/
   `screenshots_test.dart`。缓解：回归全量 + 截图脚本重跑（`bash scripts/ui-screenshots.sh
   REQ-008`）；如有 golden 变更在测试阶段显式更新并记录。
9. **范围蔓延（中）**：容易顺手做书签持久化、听书改动、分页续章重做。缓解：§1.2 明确不做；
   US-8/US-9 仅回归；分页/听书代码预期零改动。
10. **`ReflowEngine` 接口误扩（低-中）**：该接口目前未被阅读页使用；若架构强行把连续流下沉到
    引擎，可能引入不必要的抽象与回归。缓解：§3.1 标注为"可选、需保持契约"；优先在页面层编排。

---

## 6. 闸门1 自评

- [x] **验收标准全部可测（无"体验好/流畅"类不可测词）**：US-1~US-13 每条均为可断言观察项 ——
  - `[集成测试]`：真实 `drag` 到 `maxScrollExtent` → `find.text('<下一章正文>')`/标题
    `findsOneWidget` 且 `ReaderBottomBar` 仍 `findsNothing`（证明非按钮触发，US-1）；末章
    `pixels == maxScrollExtent`（容差）+ `takeException()==null` + 不重复（US-2）；
    `backend.saved?.href`/`progression` 的取值与范围（US-3）；重开后视口偏移落在目标章区间
    （US-4）；听书写入后返回定位（US-8）；
  - `[widget 测试]`：底栏 `Slider.value`/百分比文本、顶栏章节名（US-5）；`findsOneWidget` 去重 +
    已构建章节数有界（US-6/US-11）；上一章/目录跳转的 `saved.href` 与视口（US-7）；书签图标
    切换、分页切章新 href、`href` 正则与 `progression` 范围（US-9）；失败路径保留内容 +
    提示 + 调用次数有界（US-10）；
  - `[单测]`：可见章判定/章内比例/加载去重/失败重试有界等纯逻辑（US-6/US-10，依赖架构可测出口）；
  - `[真机]`：Android 五项人工清单（US-13）。
  无"体验好""流畅"等不可测措辞；每类均给出可执行断言；每条映射到原型图（01-immersive /
  02-menus，或明确"无新增原型/零布局改动"）。
- [x] **与既有 REQ 无重复**：R4/R5 证据表明"分页章末无缝续章"是 REQ-001/REQ-007 的**分页**能力
  （`PageTurnCoordinator`，`paged_view_controls.dart:37-40`），本 REQ 针对**滚动模式**（R1/R2 的
  `SingleChildScrollView` 单章 + 无触底逻辑），机制与入口均不同；R6 表明听书章末连播是音频机制
  （`listen_page.dart:196-230`），本 REQ 不重做；REQ-004 只定义了滚动模式"仅滑动"，未含自动衔接。
  US-8/US-9 明确为**回归守住**而非重做。故不重复。
- [x] **影响面清单非空**：§3 覆盖 7 类必答项 —— reading_progress 保存/恢复（§3.2，零 schema）、
  Locator 不变式（§3.2/§3.3，章内 progression）、书签（§3.4，会话内切换回归）、听读同进度/听书
  跨章（§3.3/§3.6，回归 + 可见章驱动）、章节进度显示（§3.4，章内语义）、分页模式保留（§3.5，
  零改动）、性能/内存（§3.6，有界构建 US-11）；并含既有功能（§3.1）、接口（§3.2）、回归面
  （§3.7），均附具体 file:line 与约束。
