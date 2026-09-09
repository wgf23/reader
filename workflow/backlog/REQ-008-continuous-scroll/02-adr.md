<!-- wf-meta: req=REQ-008-continuous-scroll | phase=architecture | agent=architect | date=2026-09-09 | gate=passed -->
# REQ-008 · 架构决策记录（ADR：滚动模式连续滚动 / 可见章与章内进度 / 跨章恢复 / 失败路径 / 节流可测 / 测试基建）

## 决策（一句话）

把滚动正文从「`SingleChildScrollView` 只挂 `view.chapters[_chapterIndex]` 单章」改为
**`SelectionArea` + `CustomScrollView` + `SliverList.builder` 按章懒构建的连续流**：所有章
按目录顺序排入同一可滚动列表，`SliverList` 只构建视口 + 缓冲内的章（自动回收，落实 US-11 有界）；
`_onScroll` 用**已构建章的 `RenderAbstractViewport.getOffsetToReveal` 几何**做「顶部锚点 + 迟滞 +
触底锁」的可见章判定（D2），并写**可见章的 `href` + 章内 `progression`**（D3，Locator 不变式）；
`_goChapter`/目录/恢复统一改为「滚动定位到目标章起点 + `progression×章高`」（D4）；下一章内容出口
抽为**可注入 `ChapterContentProvider` + 记忆化缓存**（D5，US-10）；300ms 进度落盘改为**可注入
`ProgressSaver` 的尾沿防抖**（D6，修掉"最后一次滚动不落盘"并让 widget 假时钟可断言）；**零 schema、
零 FFI、零新增依赖、零布局自创**（唯一行为性增量 = 章与章之间一个既定间距，见 02-design §5）。

---

## 决策点 D1：连续流渲染编排（US-1/US-2/US-11）

**现状（已核实）**：`reader_page.dart:483` 取 `view.chapters[_chapterIndex]` 单章，`:521` 传入
`_buildArticleBody`；滚动分支 `:633-658` 为 `SingleChildScrollView` + `SelectionArea` + `Column`
（`Text(chapter.title)` + `Text(chapter.text)`）。滚到章末即 `maxScrollExtent`，无下一章可滚入（R1）。
数据已在内存：`openBook` 一次性返回全部章（`library_backend.dart:32-42`，R11）。

### 备选

- **A（选）：`CustomScrollView` + `SliverList.builder` 按章懒构建全书**
  - 做法：`SelectionArea(child: CustomScrollView(controller: _scrollController, cacheExtent: 250,
    slivers: [SliverPadding(padding: EdgeInsets.fromLTRB(24,24,24,64), sliver:
    SliverList.builder(itemCount: view.chapters.length, itemBuilder: (ctx,i) =>
    ChapterSection(key: _chapterKeys[i], index: i, ...))))]))`。
  - 优点：**懒构建 + 自动回收是 `SliverList` 内建语义**——视口外的章 element 被卸载，已构建章数天然
    有界（视口 + `cacheExtent`），US-11 无需自研虚拟化；每章一个 item，天然去重（US-6）；滚动到底
    自动接续、末章自然停止（US-1/US-2）；选中语义由外层 `SelectionArea` 统一承载，可跨章选中。
  - 缺点：`maxScrollExtent` 是随构建增长**估算值**，远跳/恢复需另做定位（见 D4）；`find.byType(SingleChildScrollView)`
    的既有集成断言需同步（已列入 02-plan 冲突清单）。
- **B：单章 `SingleChildScrollView` + 触底 `setState` 追加下一章（滑窗）**
  - 做法：维护 `[_windowStart,_windowEnd]`，`NotificationListener` 触底追加、触顶前插；超过上限回收。
  - 优点：偏移是 `SingleChildScrollView` 的连续量，`_jumpToProgress` 直觉简单。
  - 缺点：**自研虚拟化**——前插/回收时必须用 `GlobalKey` 量出被移除高度并 `jumpTo(offset - removedHeight)`
    才能不跳屏，回收边界极易产生"滚动抖动"；有界性与正确性都得自己证明，测试面更大。**拒绝**（保留为
    A 在 `SelectionArea`+sliver 兼容性问题出现时的降级备选）。
- **C：一次性挂载全书所有章（`Column(children: chapters.map(...))`）**
  - 优点：无定位/懒加载复杂度。
  - 缺点：**违反 US-11**（长书 + 大字号一次性构建全书 `Text`，内存/布局开销大）；打开即卡。**拒绝**。

### 选择与理由

选 **A**。US-11 的"已构建章节数有界"与 US-6 的"不重复渲染"正是 `SliverList.builder` 的既有保证，
不应自研虚拟化去承担 B 的偏移补偿风险；`SelectionArea` 包 `CustomScrollView` 是 Flutter 官方支持的
组合（选中容器包滚动视图），能保住 `contextMenuBuilder: SizedBox.shrink()` 与 `onSelectionChanged`
既有语义（`:636-640`）。

### 有界构建上限与回收策略（写入 US-11 验收）

- 显式 `cacheExtent: 250.0`（Flutter 默认值，写明便于断言）。
- 已构建章数上界定义：`ceil(viewportHeight / minChapterHeight) + 2`（前 1 + 后 1 缓冲）。
  验收测试用「每章 ≥ 一屏」的语料 → 上界 = **3**；断言 `find.byType(ChapterSection)` 计数 ≤ 3，
  且 `!= 全书章数`。
- 回收：由 `SliverList` 在 element 卸载时自动完成，**不保留已读章**（无额外 LRU）；滚动到最后一章时
  有界性仍成立。
- 可测出口：`ChapterSection` 为公开 widget（每章一个），widget 测试以 `find.byType(ChapterSection)` 计数。

### 影响
- `reader_page.dart` 滚动分支重写为 sliver 列表；新增公开 `ChapterSection`（放 `pages/continuous_scroll_policy.dart`
  或 `reader_page.dart` 同文件，最终由开发定，均属 interface 层）。
- 既有集成断言 `find.byType(SingleChildScrollView)` 需改（`reader_interaction_test.dart:139-140`）。
- 单章 golden 视觉目标不变（`SliverPadding` 等价于原 `padding`，单章无章间距）。

### 降级线（授权）
若 `SelectionArea` 包 `CustomScrollView` 在某平台出现选中/滚动冲突，或 `SliverList` 的估算
`maxScrollExtent` 导致恢复定位不可接受：**降级为 B（滑窗追加）**，但必须保留：① 有界上限（
`windowSize = viewport 章数 + 2`）；② `resolveVisibleChapter`/`chapterProgression` 纯函数与断言不变；
③ `ChapterContentProvider`/`ProgressSaver` 契约不变。**禁止**退化为 C（一次性全书）。

---

## 决策点 D2：可见章判定与迟滞（US-5/US-6/US-7）

**现状（已核实）**：无"可见章"概念——`_chapterIndex` 仅由 `_goChapter`/目录/恢复赋值；`_onScroll`
只算 `offset/max`（`:158-164`）。连续流下必须从滚动位置反推"当前可见章"，且章末小幅抖动不得让
`_chapterIndex` 反复横跳（风险 §5.4）。

### 备选

- **A（选）：顶部锚点章 + 迟滞 + 触底锁**
  - 规则：用已构建章的几何（`top` = 章顶相对视口顶的 px，向上为负）：
    `candidate = 最后一个 top <= hysteresis 的已构建章`（即其起点已到达/越过视口顶部）。
    - 向前切换（`candidate > current`）：要求 `candidate.top <= -hysteresis` 才切换；
    - 向后切换（`candidate < current`）：要求 `current.top >= +hysteresis` 才切换；
    - 触底（`pixels >= maxScrollExtent - 1.0`）→ 强制末章（处理短末章无法顶到视口顶）；
    - 程序化跳转（`_goChapter`/目录/恢复/切回滚动）后置 `_chapterLocked=true`，直到用户真实拖动
      （`ScrollStartNotification.dragDetails != null`）才解锁，避免短末章/远跳后被立即反判。
  - 优点：语义稳定（"阅读位置 = 屏幕顶端"），与 `reading_progress` 直觉一致；章内 `progression`
    单调可算（D3）；短末章靠触底锁正确落到末章；迟滞把章边界的像素级抖动隔离。
  - 缺点：需要"已构建章几何"（依赖 `GlobalKey`），比纯算术略重；用户若期望"新章占屏一半才切"
    需要适应（见降级线）。
- **B：视口内占比最大章**
  - 优点：标题/进度更贴近"当前正在看的那一屏"。
  - 缺点：**短末章永远无法成为占比最大**——US-7 目录跳到短章 3、US-2 末章短时会被判回章 2，
    必须再加"触底特判 + 程序化锁"，复杂度并不更低；且章内 `progression` 在切换点附近非单调。
    **拒绝**（保留为降级备选）。

### 选择与理由

选 **A**。US-3/US-5 的观察点（跨章后 `href` 切换、进度归零再增长）在"章顶越过视口顶"这一刻
定义最清晰、最可测；US-7 的目录/上一章跳转通过 `ensureVisible(alignment: 0.0)` 使目标章顶对齐
视口顶，判定自然落在目标章，不依赖可见占比。判定抽为纯函数 `resolveVisibleChapter(...)`，可用
构造几何直接 [单测]（US-6）。

### 影响
- 新增 `ChapterGeometry` + `resolveVisibleChapter(...)` 纯函数（interface）。
- `reader_page.dart` 增 `List<GlobalKey> _chapterKeys`、`_chapterLocked`、`NotificationListener<ScrollNotification>`。
- 顶栏章节名（`:547`）与底栏 `_chapterIndex`（`:553-554`）随判定更新。

### 降级线（授权）
若产品/真机反馈"顶部锚点"不符合预期（如希望新章过半即切换）：**降级为 B（占比最大 + 迟滞 + 触底锁 +
程序化锁）**，只替换 `resolveVisibleChapter` 内部策略，**US-3/US-5/US-6/US-7 的断言与 `href`/`progression`
契约不变**（切章时机可能整体后移半屏，测试用例按新策略微调滚动距离，属允许的测试实现细节）。

---

## 决策点 D3：章内 progression 语义与读写（US-3/US-9）

**现状（已核实）**：`_onScroll` 写 `_chapterProgress = offset/max`（`:158-164`），单章时恰好是章内
比例，连续流下 `max` 是全书总高 → 会变成全书比例；且 `_onScroll` 不落盘（R2/R8）。

### 备选

- **A（选）：可见章的章内比例 = `(scrollOffset - 章顶偏移) / 章高`，落盘写"可见章 href + 章内值"**
  - 章顶偏移由 `RenderAbstractViewport.getOffsetToReveal(box, 0.0).offset` 取得（与
    `Scrollable.ensureVisible` 同源，精确）；`progression = (-top) / height`（`top` 为章顶相对视口顶），
    `clamp(0,1)`。
  - 落盘：`_chapterIndex` 派生 `href = 'chapter_%04d.xhtml'`（沿用 `:187`），`progression` 恒 ∈ [0,1]。
  - 优点：**严格满足 Locator 不变式**（`docs/04 §3`：`progression` 是章内 0..=1）；听书/书签/跨设备
    契约零变；`_chapterProgress` 底栏语义（`reader_chrome.dart:104-111`）零改动。
- **B：沿用 `offset / max`（全书比例）**
  - 缺点：直接违反 Locator 不变式与 US-3/US-9；听书起点、重开恢复全错位。**拒绝**。
- **C：用首字符索引 / 字符比例**
  - 优点：重排后稳定。
  - 缺点：`ChapterData` 只有纯文本、无渲染字符偏移映射；且要改契约。**本 REQ 不选**（作为未来
    `LocatorResolver` 完整实现的方向，`core/src/locator/mod.rs` 仍 stub，§1.2 明确不做）。

### 选择与理由

选 **A**。它把"当前可见章 + 章内几何比例"作为唯一事实源，写盘值恒满足 `href + progression` 契约，
`_openListen` 传入的 `href/_chapterProgress`（`:328-329`）自然变成"当前可见章"的值，听读同进度无需
改 `ListenPage`。

### 影响
- `_onScroll` 重写（更新 `_chapterProgress`、按需 `setState`、调度落盘）。
- `_saveProgress` 改为经 `ProgressSaver`（D6）；`href` 派生沿用 `_chapterIndex`。
- 底栏 `Slider`/百分比、顶栏章节名语义不变（零布局改动）。

### 降级线（授权）
若某平台 `getOffsetToReveal` 在 sliver 子节点上不可用/返回异常：降级为
`chapterTop = box.localToGlobal(Offset.zero, ancestor: viewportRenderObject).dy + scrollOffset`
的等价算法（同一纯函数签名 `chapterProgression(top,height)` 不变），**断言不变**。

---

## 决策点 D4：恢复定位（US-4/US-7/US-9）

**现状（已核实）**：`_jumpToProgress(v)` 滚动分支 `jumpTo(max*v)`（`:244-253`），`max` 是全书总高 →
连续流下错位；`_load`/`_reloadProgress`（`:127-146`/`:340-355`）只设 `_chapterIndex`/`_chapterProgress`。

### 备选

- **A（选）：目标章 `Scrollable.ensureVisible(alignment: 0.0)` + `progression×章高`；未构建章先比例估算 + 有界校正**
  - `_scrollToChapter(index, progression)`：
    1. 若 `_chapterKeys[index].currentContext != null` → `ensureVisible(alignment: 0.0, duration: zero)`
       把目标章顶对齐视口顶，再 `jumpTo(offset + progression * box.size.height)`；
    2. 否则先 `jumpTo(proportionalChapterOffset(index, count, maxScrollExtent))`（按章序比例估算），
       再 `await SchedulerBinding.instance.endOfFrame` 逐帧检查，最多 `min(chapterCount, 50)` 次视口步进；
       目标构建后回到步骤 1；定位完置 `_chapterLocked=true`。
  - 恢复/目录/上一章下一章/切回滚动全部复用该方法。
  - 优点：目标章一旦构建即**精确对齐**（不依赖估算精度）；估算只用于"把目标带进构建范围"；
    纯函数 `proportionalChapterOffset` 可 [单测]；US-4 断言"`pixels >= 章 2 起点 - 1.0`"直接成立。
  - 缺点：远跳（如 50 章跳到第 40 章）可能需要若干帧步进（一次性，非滚动中）；首帧会先显示章 0
    再定位（见降级线）。
- **B：`TextPainter` 预量各章高度，精确算出 `initialScrollOffset`**
  - 优点：一次定位、无步进。
  - 缺点：**复制 Flutter 排版逻辑**（字体回退、`textScaler`、换行、标点挤压）易与真实布局有偏差，
    维护成本高；一旦偏差仍要校正。**不选**（作为 A 首帧闪烁不可接受时的降级）。
- **C：`ListView.builder` + `ScrollController(initialScrollOffset)` 估算**
  - 缺点：仍需估算高度；与 A 同源问题，无额外收益。**拒绝**。

### 选择与理由

选 **A**。它把"精确定位"交给 Flutter 自己的 `ensureVisible`（与滚动位置同源），把"把目标带进视口"
交给廉价估算 + 有界步进，**不需要复制排版**；同时天然处理 `progression==0`（章首）与 `progression>0`。
US-4 的 [widget 测试] 可用可注入的 `ChapterContentProvider` + 2 章语料直接断言偏移区间。

### 影响
- `_jumpToProgress`/`_goChapter`/`_onChapterSelect`/`_load`/`_reloadProgress` 全部改为
  `_scrollToChapter(target, progression)`；分页分支 `relayoutAfterLoad()` 语义不变。
- 切回滚动模式（Aa 面板 `pagedMode=false`）后 post-frame 重新 `_scrollToChapter(_chapterIndex, _chapterProgress)`。
- **字号/字体/主题/行距变更后重排**：`ReaderSettingsSheet.onChanged` 里 `setState` 会重建 sliver，
  章高随之变化，旧 `scrollOffset` 不再对应原章内位置；因此在设置变更后 post-frame
  `_scrollToChapter(_chapterIndex, _chapterProgress)` 重新锚定（**用"章序号 + 章内比例"而非绝对偏移**，
  与 Locator 语义一致，满足风险 §5.2 与 REQ-004 US-16 分页↔滚动互切不跳变）。
- 新增纯函数 `proportionalChapterOffset(...)`。

### 降级线（授权）
若首帧闪烁明显或远跳步进过慢：**降级为 B**（`TextPainter` 估算精确初始偏移），但必须：① 估算函数为
纯函数并 [单测]；② 保留 `ensureVisible` 校正兜底；③ US-4/US-7 断言不变。

---

## 决策点 D5：失败路径可测出口（US-10）

**现状（已核实）**：`BookViewData.chapters` 一次性在内存，滚动渲染直接取 `chapter.text`，
"下一章加载失败"在现状下**无法触发**（风险 §5.7）；`openBook` 失败只走 `_error` 整页错误
（`:143-145`/`:477-479`）。

### 备选

- **A（选）：`ReaderPage` 增可注入 `ChapterContentProvider` + 记忆化 `ChapterContentCache` + 内联 `OverlayError`**
  - 默认 provider = `(i) => view.chapters[i]`（生产永不失败）；测试注入"对某章抛异常"的闭包。
  - `ChapterContentCache.resolve(i)`：首次调用 provider；成功缓存；失败**记忆化**并记录 `attempts`，
    同一章 `provider` 调用次数 ≤ `maxAttempts`（默认 1，无自动重试）；`retry(i)` 仅在用户点"重试"时
    清失败记忆（显式、有界）。
  - 失败章位置渲染 `OverlayError(message: '第 N 章加载失败，请稍后重试', onRetry: ...)`（复用既有样式，
    `translation_popup.dart:147-181`），**已渲染的相邻章保留**，不抛异常。
  - 优点：纯 Flutter 侧注入，**不改 FFI/`BookViewData`**（符合 §3.2 偏好）；调用计数可直接由测试闭包统计；
    提示文案可断言（含"加载"/"失败"）。
- **B：让 fake backend 的 `openBook` 对某章抛异常**
  - 缺点：`openBook` 一次性返回全书，失败会走整页 `_error`，**无法模拟"滚到章末时下一章失败"**，
    且整页错误违反"保留已渲染内容"。**拒绝**。
- **C：新增 FFI"按章懒加载"接口以制造失败点**
  - 缺点：改 core/桥接契约，超出本 REQ（数据已在内存 R11），引入 schema/FFI 风险。**拒绝**。

### 选择与理由

选 **A**。US-10 要的是"可注入的章节内容/渲染出口"（01-req §3.2 明确"Flutter 侧优先，避免改 FFI"）；
`ChapterContentCache` 同时满足"可触发失败 + 有界重试 + 不重复调用"三个断言点，且生产路径零行为变化。

### 影响
- 新增 `ChapterContentProvider`/`ChapterContentCache`/`ChapterResolution`（interface）。
- `ReaderPage` 增可选 `chapterProvider`；`_load` 后建缓存。
- 失败章渲染 `OverlayError`（不新增视觉体系）。

### 降级线（授权）
若内联 `OverlayError` 在 sliver 列表内尺寸/定位不合适：改用**等价可断言的内联错误卡片**
（文案仍含"加载"/"失败"，`findsOneWidget`），或改为顶部浮层 `OverlayError`。**US-10 断言
（保留已渲染内容 + 可观察提示 + 调用次数 ≤1/章 + `takeException()==null`）不变。**

---

## 决策点 D6：节流/防抖可测化（US-3）

**现状（已核实）**：`_saveProgress` 用 `DateTime.now()` 做**前沿** 300ms 节流（`:181-189`），
滚动过程根本不调用它（R2）。集成测试用真实延时可行，但 widget 假时钟不推进墙钟；且前沿节流会在
"停止滚动后不再有事件"时**丢掉最后一次位置**。

### 备选

- **A（选）：`ProgressSaver` 尾沿防抖（`Timer(300ms)`）+ 显式动作 `flush()`**
  - `schedule(href, progression)`：记录最新值、重置 300ms 计时器（尾沿）；
  - `flush(href, progression)`：立即保存并取消计时器（用于切章/进度条松手/目录/听书返回/`dispose`/切模式）；
  - 注入 `save` 回调与 `debounce`（默认 300ms，测试可缩短或 `tester.pump(300ms)` 触发）。
  - 优点：widget 测试用 `tester.pump(Duration(milliseconds:300))` 推进假时钟即可断言落盘；**修掉
    "停止滚动后最后一次不落盘"**；显式动作保持既有"立即 `backend.saved`"断言不破。
- **B：注入 `DateTime Function() now` 的可测时钟（保留前沿节流）**
  - 优点：改动小。
  - 缺点：仍会丢最后一次滚动位置（前沿语义）；测试需注入时钟并手动推进，不如 Timer 直观。**不选**。
- **C：保持 `DateTime.now()` 前沿节流不动，只靠集成测试真实延时**
  - 缺点：US-3 的 widget 层不可断言（风险 §5.3 未消解）；丢尾问题仍在。**拒绝**。

### 选择与理由

选 **A**。US-3 要求"滚动过程中写入可见章 href + 章内 progression"，尾沿防抖是正确语义；`Timer` 与
`tester.pump(Duration)` 天然配合，无需引入时钟抽象。既有 `reader_page_test.dart` 的落盘断言走
`flush()` 路径（`_goChapter`/`_onProgressSeek`/`_onChapterSelect`/`_reloadProgress`），保持立即写入。

### 影响
- 新增 `app/lib/pages/progress_saver.dart`（interface）。
- `reader_page.dart`：删除 `_lastSave`/内联节流；滚动走 `schedule`，显式动作走 `flush`；`dispose` flush。
- 分页 `onProgress`（`:627`）改为 `flush`（页切换频率低）。

### 降级线（授权）
若尾沿防抖导致退出前最后一次未落盘：在 `dispose`/`WidgetsBindingObserver.didChangeAppLifecycleState`
（paused/inactive）显式 `flush`；`flush` 失败静默（不阻断返回），**US-3 断言不变**。

---

## 决策点 D7：`reflow_engine.dart` 定位（范围控制）

**现状（已核实）**：`app/lib/engines/reflow_engine.dart:5-19` 为纯抽象骨架（`open/pageCount/goto/
setStyle`），**未被 `ReaderPage` 使用**；滚动模式直接渲染 `Text`（01-req §3.1/风险 §5.10）。

### 备选

- **A（选）：本 REQ 不扩 `ReflowEngine`，连续流编排留在页面层**
  - 理由：数据已在内存、渲染是 Flutter 原生 `Text`；把连续流下沉到引擎会引入不必要的抽象与回归面，
    且 `ReflowEngine` 当前契约（`pageCount`/`goto(totalProgression)`）是分页/全书进度语义，与"章内
    progression"不同构，强行扩会污染契约。
- **B：扩展 `ReflowEngine` 承载连续流（`chapters`/`gotoChapter`/`visibleChapter`）**
  - 缺点：该接口未被使用、无实现，扩展即"为抽象而抽象"；`goto(totalProgression)` 与 Locator 章内
    语义冲突需重定义，回归面大。**拒绝**。
- **C：删除 `ReflowEngine`**
  - 缺点：属其他 REQ/未来能力预留（docs/03 §3.2/§12），超范围。**拒绝**。

### 选择与理由

选 **A**。保持 `ReflowEngine` 对外契约零变更；连续流相关纯逻辑放 `app/lib/pages/*`（interface），
与 `body_tap_policy.dart` 同层同纪律。

### 影响
- `reflow_engine.dart` 零改动。
- 无 FFI/引擎契约变更。

### 降级线（授权）
若后续需要多渲染后端共享连续流：另立 REQ，先补 `ReflowEngine` 的连续流契约与实现，**本 REQ 不预埋**。

---

## 决策点 D8：测试基建（US-1/US-2/US-3/US-4/US-8/US-12）

**现状（已核实）**：真实集成范式在 `app/integration_test/reader_interaction_test.dart`（REQ-007），
静态守卫 `app/test/no_synthetic_chrome_test.dart` 已扫描 `integration_test/*.dart`。

### 备选

- **A（选）：新增 `app/integration_test/reader_continuous_scroll_test.dart`（真实 `ReaderPage` + 真实
  `drag`/`fling`，覆盖 US-1/2/3/4/8），复用并确保 `no_synthetic_chrome_test.dart` 扫描覆盖新文件**
  - 优点：直接证伪"合成页假绿"；Linux xvfb 可跑（滚动模式不实例化 WebView）；与 US-12 逐条对应。
  - 缺点：滚动到 `maxScrollExtent` 的循环需设迭代上限（防惰性列表估算导致死循环）。
- **B：把连续滚动用例并入既有 `reader_interaction_test.dart`**
  - 缺点：该文件是 REQ-007 手势用例，混入连续流语义会降低可读性与追溯性；US-12 明确要求"新增"文件。
    **不选**。
- **C：用合成 `Column(ReaderTopBar, ReaderBottomBar)` 造场景**
  - 缺点：违反 US-12 与静态守卫，且无法验证真实滚动。**拒绝**。

### 选择与理由

选 **A**。测试分层：**[集成测试]** 真实 `ReaderPage` 滚动覆盖 US-1/2/3/4/8；**[widget 测试]**
`reader_continuous_scroll_test.dart` 覆盖 US-5/6/7/9/10/11；**[单测]** `continuous_scroll_policy_test.dart`
覆盖 `resolveVisibleChapter`/`chapterProgression`/`proportionalChapterOffset`/`ChapterContentCache`，
`progress_saver_test.dart`（`testWidgets` + `pump`）覆盖防抖；**[真机]** US-13 清单。

### 影响
- 新增两个测试文件 + 两个 [单测] 文件；`reader_interaction_test.dart:139-140` 的
  `find.byType(SingleChildScrollView)` 改为 `find.byType(CustomScrollView)`；
  `screenshots_test.dart` 增一张"连续滚动到第二章"真实截图供产品对照（见 02-plan T-007）。
- `no_synthetic_chrome_test.dart` 现有实现自动覆盖新文件（扫描目录），无需改扫描逻辑；可增补"新文件存在"正向断言。

### 降级线（授权）
若 Linux xvfb 下真实 `drag` 到 `maxScrollExtent` 不稳定：US-1/US-2 保留"真实 `drag` 到出现第二章"
（不必严格到 `maxScrollExtent-1`），US-3 保留真实滚动 + 防抖窗口；**"禁止合成页"不降级**，静态守卫
`no_synthetic_chrome_test.dart` 必须绿。

---

## 关联裁定（次要决策，供 02-design/02-plan 引用）

1. **零布局自创**：唯一行为性增量 = 章与章之间的既定间距（`chapterGap = 32`，复用正文留白，非新控件/
   新颜色/新字号）；顶栏/底栏/工具条/Aa 面板/设置页布局零改动（逐屏见 02-design §5）。
2. **可测出口清单**：`resolveVisibleChapter`/`chapterProgression`/`proportionalChapterOffset`（D2/D3/D4）、
   `ChapterContentCache`（D5）、`ProgressSaver`（D6）、`ChapterSection`（US-11 计数）——均在 `app/lib/pages`
   （interface），不 import `package:reader_app/src/rust/`。
3. **DDD 归属**：改动全部在 `app/lib/pages/**`（interface）；`app/lib/services/**`（application）零改动；
   `core/**`（domain/infrastructure）零改动；无跨限界上下文。
4. **零 schema / 零 FFI**：`reading_progress`（`(book_id,href,progression,updated_at)`）、`ProgressData`、
   `BookViewData`/`ChapterData`、`Locator` 全零变更；无 FRB 再生成。
5. **无新增依赖**：仅用 Flutter SDK 既有 API（`CustomScrollView`/`SliverList`/`SelectionArea`/
   `RenderAbstractViewport`/`Scrollable.ensureVisible`/`Timer`）。
6. **进度唯一事实源**：`reading_progress` 不变；听读同进度靠"可见章 href + 章内 progression"天然成立。
7. **分页模式零改动**：`PageTurnCoordinator`/`PagedWebView`/`pagedViewBuilder` 路径不改，仅切回滚动时
   重新定位到 `_chapterIndex`。
8. **文档同步（非闸门项）**：`docs/03`/`docs/04` 无签名变更；可在开发阶段补"连续滚动可见章判定"注释。

## 影响汇总
- **Dart（新增）**：`app/lib/pages/continuous_scroll_policy.dart`（`ChapterContentProvider`/`ChapterContentCache`/
  `ChapterResolution`/`ChapterGeometry`/`resolveVisibleChapter`/`chapterProgression`/`proportionalChapterOffset`）、
  `app/lib/pages/progress_saver.dart`（`ProgressSaver`）；`app/test/continuous_scroll_policy_test.dart`、
  `app/test/progress_saver_test.dart`、`app/test/reader_continuous_scroll_test.dart`、
  `app/integration_test/reader_continuous_scroll_test.dart`；`product-preview.manifest.json`（REQ-008）。
- **Dart（修改）**：`app/lib/pages/reader_page.dart`（滚动分支重写、`_onScroll`/`_goChapter`/
  `_jumpToProgress`/`_onProgressSeek`/`_onChapterSelect`/`_load`/`_reloadProgress`/`_openListen` 接线、
  `chapterProvider` 可选注入）、`app/integration_test/reader_interaction_test.dart`（1 处 finder）、
  `app/integration_test/screenshots_test.dart`（增连续滚动截图）、`app/test/screenshot_golden_test.dart`
  （若像素变化则更新 golden）。
- **Rust / 数据模型 / 依赖**：零变更。
- **回归面**：`cargo test --release`、`flutter test`、`flutter test integration_test -d linux`、
  `flutter analyze`（0 issues）、DDD lint（违规 0）、`bash scripts/ui-screenshots.sh REQ-008`、
  `bash scripts/build-android-local.sh`、Android 真机 US-13。

## 闸门2 自评（ADR 部分）
- [x] **备选 ≥2 且给出理由**：D1 三备选（A/B/C）、D2 两备选（A/B）、D3 三备选（A/B/C）、
  D4 三备选（A/B/C）、D5 三备选（A/B/C）、D6 三备选（A/B/C）、D7 三备选（A/B/C）、D8 三备选（A/B/C）；
  每点含选择理由与拒绝论证，且均有降级线授权。
- [x] **与既有约定一致**：Locator 章内 `progression` 不变式保持（D3）；限界上下文不跨越（改动全在
  interface 层）；听读同进度以"可见章 href + 章内值"延续；ddd-rules 合规（新增文件在 `pages`，不 import
  生成物）；REQ-001/004/005/006/007 能力复用不重做。
- [x] **原型权威**：D1/D2/D3/D4 与 `reader-ui-v2/01-immersive.svg`/`02-menus.svg` 逐屏对应（02-design §5）；
  未自创布局（唯一行为性增量 = 章间距，非控件）。
- [x] **可测性落定**：US-3/6/10/11 的可测出口（`ProgressSaver`/`resolveVisibleChapter`/`ChapterContentCache`/
  `ChapterSection`）全部落定；US-1/2/4/8/12 的真实集成测试结构落定（D8）。
- [ ] **待同步项（非本阶段闸门项）**：REQ-008 `product-preview.manifest.json` 与
  `docs/03`/`docs/04` 注释在开发/交付阶段完成；不阻塞闸门2。
