<!-- wf-meta: req=REQ-004 | phase=architecture | agent=architect | date=2025-09-01 | gate=passed -->
# REQ-004 · 架构决策记录（ADR：两模式选中统一 / 手势分层 / 进度条语义 / UiState 管理）

## 决策
阅读器页按 `docs/wireframes/reader-ui-v2/`（README + 01-immersive.svg + 02-menus.svg +
03-settings.svg + 04-selection.svg，**权威规范**）重构为沉浸态容器 + 工具浮层：**两模式选中收敛到
单一 `SelectionToolbar` 组件与单一选中状态**（分页模式 JS 选区回传增强带矩形坐标、滚动模式固定基准位
兜底）；**手势采用 Stack 分层 + 透明 tap-only 手势层**（左/右 15% 翻页热区、中部 1/3 呼出热区、
其余委托引擎，滚动模式不拦截边缘）；**进度条语义 = 章内进度（progression 0..1）**，分页/滚动两模式
各自换算、保存仍走既有 `saveProgress(href, progression)`（core/api/表零改动）；**UiState 全部为
ReaderPage 局部 setState**（不引入 Riverpod，与现状一致，状态仅页面子树内共享）。

原型映射：本 ADR 全部决策以 `docs/wireframes/reader-ui-v2/*` 四图为最终交互依据；任何与既有代码的
偏差均以原型为准（docs/07 §4.3 教训固化：禁止自创布局）。

---

## 决策点 1：两模式选中逻辑统一（"选中 → 浮动工具条"如何收敛）

### 现状（已核实，对应 01-req §3/§5 风险2）
- 滚动模式：`SelectionArea.onSelectionChanged` → `SelectedContent.plainText`（REQ-003 已接入）；
- 分页模式：`paginationJs` 的 `selectionchange` 监听 → `callHandler('selectedText', 文本)` →
  `PagedWebView.onSelectedText`（REQ-003 已接入）；
- 两入口在 `reader_page.dart` 已收敛到同一 `_onSelectedText(String)` 状态，但工具条是**内嵌行式**
  （翻译/查词/取消三 ActionChip），不是原型 04-selection.svg 的浮动工具条；且**两模式均无选区几何**。

### 备选
- **A1（选）：单一 `SelectionToolbar` 组件 + 单一选中状态 + "尽力定位"双轨**
  ① 选中状态唯一（`_selectedText`，两引擎回调已收敛，REQ-003 基础保留）；② 新浮动工具条组件
  `SelectionToolbar`（恰好 5 入口：划重点/笔记/翻译/查词/复制 + 笔记 4 色圆点，04-selection.svg），
  滚动/分页渲染**同一组件类型与同一 key 前缀**（US-15 断言点）；③ 定位双轨：分页模式把 JS
  `selectionchange` 回传**增强为 文本 + 选区视口矩形**（`getBoundingClientRect`，~15 行 JS，经既有
  `selectedText` handler 多参数回传，Dart 侧向后兼容解析：仅 1 参=旧行为、≥5 参=文本+矩形）→ 工具条
  锚定在选中文本上方；滚动模式 `SelectionArea` 无选区几何 API → 工具条**视口顶部固定基准位**呈现
  （01-req §5 风险2 已授权的降级线，明确记入本 ADR）。④ 翻译/查词/复制动作与 REQ-003 完全同路径
  （`_doTranslate`/`_doLookup` 复用；`translateBackend == null` 时隐藏翻译/查词，零注入行为不变）。
  优点：US-14/US-15 全部可测成立（同一组件、同一行为、顺序断言）；分页定位精确对齐原型"选中文本
  上方"；滚动降级线被 01-req 明确授权，不阻塞；JS 增强向后兼容（既有 fake 构建器与测试零改动）。
  缺点：滚动模式定位是近似（不影响验收断言，deviation 以"工具条存在且可操作"为准）；JS 矩形是
  尽力坐标（跨列选区时 clamp 视口，不影响行为）。
- **A2：彻底抽象 `SelectionBridge` 接口（两引擎各自实现完整 bridge：文本 + 几何 + 清除/锚定）**
  滚动模式也实现精确几何（自绘/`TextPainter` 布局计算或扩展 `SelectableRegion`），ReaderPage 只面向
  接口编程。
  优点：接口最"正统"，未来笔记 REQ（NOTE-01 TextSelection 锚定）可直接挂。缺点：滚动模式精确几何
  Flutter 无现成 API（`SelectionArea` 回调不含矩形），需自绘选区层或侵入式布局计算，实现成本高、
  widget 测试对像素断言脆弱（翻页/滚动后几何漂移）；本期验收（US-14/15）不要求像素级定位，接口先行
  属过度设计；`reflow_engine.selectText`（REQ-003 遗留 TODO）也明确本期不兜底（分页坐标已由 JS
  提供）。记录为**笔记 REQ 的升级路径**（届时按 NOTE-01 引入 TextSelection + Locator 锚定时再抽
  bridge）。
- **A3：最小改动——保留两套入口，只把行式工具条换成浮动组件**
  不建统一状态/组件约定，滚动与分页各自渲染工具条实例。
  缺点：US-15"同一组件、同一控件集合"只能靠"碰巧相同"维持，无结构保证；状态/定位仍散落 page，
  NOTE 系列还需再重构；"统一"名不副实。**拒绝**。

### 选择与理由
选 **A1**。REQ-003 已把两引擎回调收敛到同一 `_onSelectedText`，本决策在此基线上补齐"同一浮动工具条
组件 + 定位"即可 100% 满足 US-14/US-15；分页矩形增强成本 ~15 行 JS + 1 个可选回调，换取对
04-selection.svg"选中文本上方"的精确呈现；滚动降级线是 01-req §5 风险2 明确授权（"分页模式沿用
REQ-003 既有最小选区回传、工具条固定位置呈现（记入 02-adr）"）。A2 的几何成本本期无验收回报，
其接口价值（TextSelection 锚定）归 NOTE 系列。

### 影响
- `app/lib/engines/paged_web_view.dart`：JS `selectionchange` 回传增强（文本+矩形，多参数）；
  `PagedWebView` 新增可选 `ValueChanged<Rect?>? onSelectionRect`（`onSelectedText` 原样保留，向后兼容）。
- `app/lib/pages/reader_page.dart`：内嵌行式 `_buildSelectionToolbar` 删除，换 `SelectionToolbar`
  组件 + 定位逻辑（分页矩形 / 滚动基准位）；`_onSelectedText`/`_doTranslate`/`_doLookup`/
  `_cancelSelection`/`_resetPopups` 复用。
- `app/lib/widgets/selection_toolbar.dart`：**新增**（interface 层，5 入口）。
- 测试：`translate_reader_test.dart` 对行式工具条的断言改为浮动工具条（5 入口）；fake 分页构建器
  零改动（`onSelectedText` 仍在）；新增"两模式同一组件"断言。

---

## 决策点 2：手势层与沉浸/呼出（中央呼出 vs 边缘翻页 vs 滑动/长按如何不冲突）

### 备选
- **A1（选）：Stack 分层 + 透明 tap-only 手势层（命中区规则化，层间优先级固定）**
  `ReaderPage` 主体为 Stack（自下而上）：
  ```
  0. ArticleBody       渲染引擎容器（WebView / 滚动视图 + SelectionArea）：滑动、长按选中、
                       缩放等原生手势由引擎自行处理；
  1. ReaderGestureLayer 全屏透明层，GestureDetector **只注册 onTapUp**（不注册 drag/scale）：
                       按命中区规则裁决"边缘翻页 / 中部呼出 / 忽略"；
  2. ReaderChromeOverlay 顶栏(64) + 底栏(~100)：呼出态淡入；按钮/Slider 自身消费其区域点击；
  3. SettingsSheet / DirectoryDrawer：打开时自带全屏遮罩，消费面板外点击（关闭面板/抽屉）；
  4. SelectionToolbar + 翻译/查词浮层：最高层，选中操作独立于 chrome 可见性。
  ```
  命中区规则（`onTapUp(localPosition)`，宽 w 高 h）：
  | 条件 | 动作 |
  |---|---|
  | 面板/抽屉打开 | 遮罩消费（关闭面板/抽屉），不翻页、不切换 chrome |
  | x < 0.15w 且分页模式 | `prevPage()`（第 1 页越界 no-op） |
  | x > 0.85w 且分页模式 | `nextPage()`（末页越界 no-op） |
  | 边缘 15% 且**滚动模式** | **忽略**（不拦截；tap 对滚动视图无副作用，US-4） |
  | 0.33w ≤ x ≤ 0.66w 且 0.1h ≤ y ≤ 0.9h | `toggleChrome()`（呼出⇄沉浸） |
  | 其余 | 忽略 |
  
  互斥保证：① **滑动 vs tap**——手势层不声明 drag，滑动越过 touch slop 时 tap 在竞技场失败，
  滚动/WebView 滑动胜出（US-4 滚动偏移变化正常）；② **长按选中 vs tap**——长按超时取消 tap，
  SelectionArea/WebView 长按胜出（US-14）；③ **拖动进度条 vs 翻页**——Slider 在 2 层之上，拖动期间
  点击不达手势层（US-9 风险1）；④ **边缘 vs 呼出**——命中区分支互斥（边缘先判，不进中部），
  边缘点击只翻页不切换 chrome（US-2 末句）；⑤ **呼出态中部点击**——浮层间隙仍可命中手势层 →
  隐藏（US-2）。
  优点：分层职责单一、命中区可表格化（widget 测试用 `tapAt` 坐标直接断言，US-17②③⑦）；
  tap-only 手势层天然不吞滑动/长按，避免"误吞滑动起点"（01-req §5 风险1）；滚动模式边缘"不拦截"
  由分支跳过实现，可测。缺点：需在 build 中维护 5 层 Stack（结构清晰，成本低）。
- **A2：单一 GestureDetector 包住整个 body，onTapUp 判定 + onVerticalDrag 转发**
  缺点：`GestureDetector` 声明 drag 会与 WebView/`SingleChildScrollView` 的 drag 在竞技场竞争，
  出现"滚动响应迟钝/被抢"；WebView 内部手势（长按/双指）与 Flutter 手势层边界模糊；滚动模式边缘
  点击"不拦截"需手动透传，语义别扭。**拒绝**。
- **A3：把命中区做进 ArticleBody 内部（引擎感知命中区）**
  由渲染引擎自己消费点击（WebView 注入 JS 点击分区、滚动视图内嵌套 detector）。
  缺点：引擎与 UI 策略耦合，分页/滚动两套实现无法统一；测试需分别 mock；与"渲染引擎可不同、
  交互统一"的目标相悖。**拒绝**。

### 选择与理由
选 **A1**。手势层只做"tap 裁决"，把滑动/长按/缩放留给引擎原生手势——这是 Flutter 手势竞技场
的标准用法，也是"两模式统一 UI 交互、渲染引擎可不同"（01-req 目标）的直接体现；命中区表格可直接
翻译为 US-2/3/4/9/17 的坐标断言。A2/A3 均破坏手势仲裁或引擎解耦。

### 影响
- `reader_page.dart` build 结构改为 5 层 Stack；新增 `_ReaderGestureLayer`（私有）或独立 widget
  （测试按类型断言用，取 `ReaderGestureLayer` 公开类便于 `find.byType`）。
- 呼出热区坐标常量集中定义（`kEdgeZone=0.15`、`kCenterZoneLeft=1/3`、`kCenterZoneRight=2/3`、
  垂直 0.1~0.9），widget 测试与实现共用同一常量文件（防漂移）。
- 动画：呼出/隐藏用 `AnimatedOpacity` + `IgnorePointer`（隐藏时浮层不拦截点击），或
  `AnimatedSlide`（底栏下滑入）；以 02-menus.svg"淡入"为准（AnimatedOpacity，300ms）。

---

## 决策点 3：进度条语义（"章内进度"还是"全书进度"；两模式位置换算）

### 备选
- **A1（选）：章内进度（progression 0..1）+ 百分比文本；保存语义不变**
  进度条滑块值 = **当前章内 progression**，与 `reading_progress(href, progression)`（REQ-001 落库
  语义，`core/src/api.rs progress_save(id, href, progression)`）与 docs/04 §3 `Locator.progression`
  （"章内进度 0.0..=1.0（页/列粒度）"）完全同构；右侧百分比文本 = `progression × 100`（02-menus.svg
  "42% · 位置 1304/3120" 的 42% 即章内百分比；位置计数按模式给"第 x/y 页"或章内字符比例，developer
  对齐原型且可断言）。
  两模式换算（纯函数，`app/lib/engines/progress_mapper.dart`，可单测）：
  - 分页：显示值 = 引擎 `onProgress` 回传的 `current/columns`（REQ-001 JS 既有语义，不动）；
    拖动松手 `v` → 目标页 `target = round(v × (pageCount − 1))` clamp `[0, pageCount−1]` →
    `pagedKey.currentState.gotoPage(target)` → JS 重报 progression → `saveProgress(href, prog)`。
  - 滚动：显示值 = `offset / maxScrollExtent`（`ScrollController` 监听，节流）；拖动松手 `v` →
    `controller.jumpTo(v × maxScrollExtent)` → `saveProgress(href, prog)`。
  - **互切不跳变**（US-16）：页面常驻 `_progression`；切到分页 → 等首次 `onProgress`（页数就绪）
    后 `gotoPage(round(prog × (n−1)))`；切到滚动 → 等 `maxScrollExtent > 0` 后 `jumpTo(prog × max)`
    （pending 机制，见 02-design §7）。
  优点：core/api.rs/表**零改动**（01-req §3 影响面收敛为"纯 UI 层映射"）；与听读同进度不变式
  （docs/04 §9.1：`reading_progress` 唯一事实源）天然兼容——保存的仍是 `href + progression`；
  READ-07 全书进度条留后续 REQ 自然演进。缺点：拖动不能跨章（本期验收 US-9 无跨章要求，
  READ-07 P1 记录）。
- **A2：全书进度（跨章百分比）**
  进度条值 = 全书百分比，需 core 新增"全书进度 ↔ 章内位置"查询/换算接口（遍历章权重）→
  `api.rs` 新增桥接 + FRB 再生成 + docs/03 §4 契约同步（01-req §3 已列此成本）；拖动跨章需
  章定位 + 引擎切换链，且保存仍须落回 `href+progression`（模型不承载全书进度主键）。
  优点：原型"42%"可理解为全书百分比（Kindle 语义）。缺点：触碰 core 面大、与既有章内模型错位、
  收益仅展示层语义差异；01-req §5 风险4 已倾向"均归一为 href + progression 既有模型"。记录为
  READ-07（P1）候选，本期不做。
- **A3：混合——显示章内、拖动到章边界自动续章**
  拖动到 100% 自动进下一章 0%。
  缺点：拖动语义跨章后与"松手跳转 + saveProgress"验收耦合复杂，且跨章需引擎上下文切换；
  超出 US-9 验收面。**不做**（记 READ-07）。

### 选择与理由
选 **A1**。与既有进度模型（href+progression=章内）、docs/04 Locator、听读同进度不变式零冲突，
core 零改动；两模式换算为纯函数可单测（US-16 互切回归有锚点）；README §3.3"拖动实时预览章节，
松手跳转"语义（章内）被完整满足。

### 影响
- `app/lib/engines/progress_mapper.dart`：**新增** 纯函数（`progressionToPage`/`pageToProgression`/
  `progressionToOffset`/`offsetToProgression`/`pageToPercent` 等，纯 Dart 可单测）。
- `app/lib/engines/paged_web_view.dart`：暴露 `Future<int> pageCount()`（JS `pageCount()`，已有
  `next/prev/gotoPage/relayout` 复用）。
- `app/lib/pages/reader_page.dart`：`_progression` 状态 + pending 互切机制 + 滚动模式
  `ScrollController`（ReaderPage 持有，供进度条 `jumpTo`）；`saveProgress` 500ms 节流保留。
- 百分比/位置文本：`ProgressSlider` 组件渲染（02-menus.svg"42% · 位置 …"）。

---

## 决策点 4：UiState 管理（沉浸/呼出、Aa 面板、抽屉、书签——局部 setState 还是引入状态管理）

### 现状（已核实）
- 工程**未启用 Riverpod**（`app/pubspec.yaml` 中 `# riverpod: ^2` 为 P0 按需启用注释，依赖未引入）；
- 现有页面全部为 `StatefulWidget + setState`（reader_page/settings_page/library_page），测试直接
  断言状态行为；docs/03 §3.1"状态管理：Riverpod"为设计文档远期表述，现状未落地。

### 备选
- **A1（选）：ReaderPage 局部 setState + UI 态字段组（不引入任何状态管理库）**
  页面私有 UI 态：`_uiVisible`（沉浸⇄呼出）、`_settingsOpen`（Aa 面板）、`_drawerOpen`（目录抽屉）、
  `_bookmarked`（当前页书签图标态，内存态）、`_dragPreview`（进度条拖动预览）、`_progression`；
  阅读设置 `ReaderStyle`（字号/字体/主题/行距/翻页模式，会话级内存，持久化归后续 READ 系列）；
  状态机以显式方法表达（`_toggleChrome()` 等，见 02-design §5）。
  优点：零依赖、与现状一致（测试/闸门零适配）；状态全部在页面子树内共享（顶/底栏/面板/抽屉均为
  ReaderPage 直属子树，回调透传即可，无跨页共享需求）；widget 测试直接断言（呼出/隐藏/Aa/抽屉/
  书签/进度）。缺点：无全局响应式（本页不需要）。
- **A2：引入 Riverpod（Provider/Notifier）托管 UI 态**
  docs/03 §3.1 远期方向。缺点：新增依赖 + 全页重构 + 既有全部测试包 `ProviderScope`（回归面大）；
  UI 态无跨页/跨组件共享需求（Aa 设置持久化也属后续 READ 系列，本期仅会话级），收益不抵成本。
  记录：设置持久化 REQ 落地时再评估 Riverpod。
- **A3：自研 `ReaderUiController extends ChangeNotifier` + `AnimatedBuilder` 聚合状态机**
  把 UI 态从 build 提出。优点：状态机可单测。缺点：与 Flutter `setState` 重复造轮子，多一层间接，
  且控制器需注入 ReaderPage 子树（测试复杂度上升）；状态机逻辑本身已在 A1 的显式方法中可测。
  **不做**。

### 选择与理由
选 **A1**。"最小方案"约束（01-req 与任务书均要求）下唯一同时满足"零依赖 + 可测 + 不重构既有
测试面"的选项；状态机用显式方法表达（`_enterImmersive`/`_revealChrome` 两态迁移），配合
02-design §5 的状态机表即可在 widget 测试中完整覆盖 US-1/2/11 的状态迁移。

### 影响
- `reader_page.dart` 重构为 UI 态字段组 + 显式状态机方法；`ReaderStyle` 值对象随 `settings_sheet.dart`
  定义（Aa 面板与 ArticleBody 共用）。
- 书签：内存 `_bookmarked`（当前页图标态，幂等切换、切章/翻页重置），不建数据模型（NOTE-06 P1）。
- 测试：无需 ProviderScope；既有注入点（backend/translateBackend/pagedViewBuilder）不变。

---

## 关联裁定（次要决策，记录供 02-design/02-plan 引用）
1. **Aa 面板/目录抽屉关闭后的 chrome 态**：关闭后**保持呼出态**（工具栏仍可见）——用户刚在调整
   设置/选章，立即回沉浸态体验割裂；"点击中部"才隐藏（US-11"两种均需被断言其一"→ 定为保持呼出，
   测试断言呼出态）。
2. **隐藏 chrome 的连带动作**：呼出 → 沉浸时若 Aa 面板/目录抽屉开着，一并关闭（它们是 chrome
   派生层，与"回到沉浸"语义一致）；**选中工具条与翻译/查词浮层不受 chrome 可见性影响**（属选中
   操作，04-selection.svg 独立于 01/02 图）。
3. **默认模式**：保持现状默认**滚动模式**（`_pagedMode=false`）；Aa 面板"翻页"行单选默认勾选
   "滚动模式"（03-settings.svg）。
4. **百分比/位置文本格式**：百分比 = `round(progression×100)%`；位置计数分页 = "第 x/y 页"、
   滚动 = 章内滚动比例（developer 对齐 02-menus.svg"42% · 位置 …"布局语义，可断言百分比文本，
   位置计数格式以 02-design §7 为准）。
5. **书签**：本期仅"当前页加/取消 + 图标态"（幂等、切章/翻页重置）；书签列表/跳转/持久化属
   NOTE-06 P1。
6. **错误/加载态**：ReaderPage 全局无 AppBar（含 error/loading 态，用居中内容 + SafeArea 返回
   按钮），保证 US-1/US-13 的 `find.byType(AppBar) == 0` 断言在任意正文态成立。

## 影响汇总
- **接口（Dart）**：`PagedWebView` 新增 `pageCount()` + `onSelectionRect` + `fontFamily/lineHeight`
  样式参数（均向后兼容默认值）；`LibraryBackend`/`TranslateBackend` **零改动**；新增 5 个 widget
  文件 + `progress_mapper.dart` 纯函数。
- **数据模型**：core/表/迁移**零改动**（进度条=章内 progression，纯 UI 层映射）。
- **手势**：5 层 Stack + tap-only 手势层 + 命中区常量；呼出/隐藏 AnimatedOpacity 300ms。
- **状态**：ReaderPage 局部 setState（零新依赖）；ReaderStyle 会话级（持久化归 READ 系列）。
- **回归面**：既有 translate_reader_test 工具条断言改浮动工具条；reader_page_test 全量重写；
  其余页面/服务/engines 测试零改动但需回归（T-009）。

## 闸门2 自评（ADR 部分）
- [x] 备选 ≥2 且给出理由：4 个决策点各含 ≥2 备选（A1/A2/A3、A1/A2/A3、A1/A2/A3、A1/A2/A3）
      并给出选择理由与拒绝论证（A2 决策点1 过度设计、A2/A3 决策点2 破坏手势仲裁、A2 决策点3 触碰
      core、A2/A3 决策点4 引入依赖/重复造轮子）；降级线（滚动模式工具条固定位）为 01-req §5 风险2
      明确授权并记入本 ADR。
- [x] 与既有约定一致：进度模型（href+progression=章内，docs/04 §3 Locator）、听读同进度不变式
      （docs/04 §9.1）、ddd-rules 冻结零改动、现状零 Riverpod、REQ-001/003 能力复用不重做；
      原型四图逐项映射（见各决策点）。
