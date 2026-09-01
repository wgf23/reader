<!-- wf-meta: req=REQ-004 | phase=requirements | agent=req-analyst | date=2025-09-01 | gate=passed -->
# REQ-004 · 阅读器页交互重构（沉浸态 + 工具 Chrome + 选中统一）—— 需求分析

## 1. 背景与目标

**痛点**：当前 `reader_page.dart` 把"分页/滚动切换、字号、目录"三个功能按钮直接塞在右上角 AppBar 的
`actions` 里，用户无法判断用途；无沉浸态（常驻 AppBar 中断阅读）；翻页只靠底部两个按钮、进度不可拖、
目录/字号/主题入口散落多处 —— 阅读体验明显低于既有原型图质量（`docs/wireframes/reader-ui-v2/*`）。

**目标**：按 **reader-ui-v2 原型**（四张图 + README 交互逻辑，参考 Kindle）重构阅读器页：
沉浸阅读态 + 点击中部呼出/隐藏工具 Chrome + 边缘热区翻页 + Aa 显示设置面板 + 可拖进度条 + 目录抽屉 +
书签 + 长按选词浮动工具条。成功标准一句话：**打开书即进入无任何常驻 Chrome 的沉浸态，阅读器全部交互
逐屏符合 reader-ui-v2 四张原型图，既有翻译/查词（REQ-003）与读书进度（REQ-001）零回归**。

**原型权威性**：`docs/wireframes/reader-ui-v2/README.md` + `01-immersive.svg` + `02-menus.svg` +
`03-settings.svg` + `04-selection.svg` 为 UI 交互的**权威规范**；本 REQ 的每条验收标准均映射到具体
图/交互（见 §2 各条标注），实现阶段禁止对布局/交互自由发挥（闸门3 由 orchestrator 逐屏核对，deviation=0）。

**已拍板决策（用户确认，直接纳入）**：
1. 顶栏"⋯ 更多"菜单项：阅读统计 / 听书 / 笔记 / 导出 —— **本期只做占位菜单项**，动作可 TODO（点击不崩溃）；
2. **滚动模式不用边缘翻页**（只靠滑动）；边缘翻页仅分页模式；
3. 书架页本期不动（其微调另立 REQ）。

**边界划界（本 REQ 明确）**：
- 必做：沉浸态状态机、顶/底栏浮层、Aa 面板（字号/字体/主题/行距/翻页模式）、可拖进度条、目录抽屉、
  书签按钮（图标态）、选中浮动工具条（划重点/笔记/翻译/查词/复制）、右上角三按钮移除、既有功能零回归。
- 占位（入口存在、动作 TODO）：⋯ 更多四项、工具条"划重点/笔记"（NOTE 系列后续 REQ）、"复制"本期
  接系统剪贴板即可、书签仅"当前页加/取消 + 图标态"（完整书签列表/跳转属 NOTE-06 P1，后续 REQ）。
- 不做：书架页调整（另立 REQ）、听书功能本体（LISTEN 系列，`listen_page.dart` 不动）、阅读统计本体
  （READ-08 P2）、笔记导出本体（NOTE-07）、目录树层级折叠展开（按现有 `view.chapters` 扁平列表）。

## 2. 用户故事与验收标准（Given/When/Then，必须可测；每条标注原型图映射）

### 故事 1：沉浸态 —— 作为所有用户，我想要打开书就是干净的全屏正文，以便沉浸阅读不被工具打断
- **US-1 打开书进入沉浸态（01-immersive.svg 整图）**
  - Given 书架页点击某本书封面，`backend.openBook` 成功返回
  - When 阅读器加载完成、正文渲染可见
  - Then 屏幕上**不存在常驻 AppBar**、**不存在常驻底栏/工具按钮**：widget 树中无
    `AppBar(actions: [模式切换/字号/目录])`、无常驻翻页行；正文区占满可用区域（可断言
    `find.byType(AppBar)` 为 0、正文容器为全屏尺寸）；顶部标题"第三章 · 起风了"即正文起始内容。
- **US-2 点击正文中部 1/3 → 呼出顶栏+底栏；再点中部 → 隐藏（01-immersive.svg 中央热区 +
  02-menus.svg 呼出态）**
  - Given 沉浸态（US-1）
  - When 在正文**水平中部 1/3（屏宽 1/3~2/3）× 正文中部垂直区域**内点击（如坐标 (0.5×宽, 0.5×高)）
  - Then 顶栏 + 底栏**淡入出现**，布局即 02-menus.svg：顶栏含 ← 返回 / 书名（大）· 章节名（小）/
    ⋯ 更多；底栏含 上一章 / ☰ 目录 / 进度条+百分比 / 🔖书签 / Aa / 下一章（widget 断言各控件存在且可见）。
  - Given 顶栏+底栏可见（呼出态）
  - When 再次点击同一中部 1/3 区域
  - Then 顶栏+底栏**淡出隐藏**，回到沉浸态（控件不可见/从树中移除）。
  - Given 沉浸态 When 点击**左/右边缘热区**（x < 15% 宽 或 x > 85% 宽）Then 不切换工具栏可见性
    （边缘点击只翻页，见 US-3，二者互斥不串扰）。

### 故事 2：翻页与导航 —— 作为所有用户，我想要点边缘翻页、上滑滚动，以便流畅阅读
- **US-3 分页模式：左右边缘 15% 点击翻页（01-immersive.svg 左右热区，标注"左/右边缘15%"）**
  - Given 处于**分页模式**（Aa 面板"翻页"选分页），当前章节第 N 页
  - When 点击屏幕**左侧 15% 宽**热区内任意高度点（x < 0.15×宽）
  - Then 翻到上一页（分页引擎 page −1；边界：第一页不越界、不报错）。
  - When 点击屏幕**右侧 15% 宽**热区（x > 0.85×宽）Then 翻到下一页（page +1）。
  - Given 分页模式第 1 页 When 点左侧热区 Then 页不变（边界断言）；Given 末页 When 点右侧热区
    Then 页不变或按既有 REQ-001 行为（到章末不越界）。
- **US-4 滚动模式：无边缘翻页、只靠滑动（README §3.1 + 已拍板决策 2）**
  - Given 处于**滚动模式**
  - When 点击左/右边缘 15% 热区
  - Then **不触发任何翻页**（当前章节滚动偏移不变、无页切换回调），边缘热区在该模式下不拦截事件。
  - When 在正文区上/下滑动 Then 内容随滑动正常滚动（`SingleChildScrollView` 偏移变化，可断言
    scroll offset 前后不同）。
- **US-5 顶栏：← 返回 / 书名·章节名 / ⋯ 更多（02-menus.svg 顶部浮层）**
  - Given 工具栏已呼出
  - Then 顶栏左侧为"← 返回"按钮、中间为"书名（大字）+ 章节名（小字）"、右侧为"⋯ 更多"按钮
    （02-menus.svg：书名"百年孤独"、章节名"第三章 · 起风了"小字）。
  - When 点击"← 返回" Then 阅读器 pop，回到书架页（路由返回）。
  - When 点击"⋯ 更多" Then 弹出下拉菜单，**恰好含 4 项且顺序为：阅读统计 / 听书 / 笔记 / 导出**
    （04 项均可断言文本）。
  - Given 菜单已弹出 When 依次点击"阅读统计/听书/笔记/导出"任一占位项 Then 不崩溃、无异常，
    动作可为 TODO（Toast/提示"即将上线"或静默）；**本期不打开任何新页面**。
- **US-6 底栏：上一章 / ☰ 目录 / 可拖进度条+百分比 / 🔖书签 / Aa / 下一章（02-menus.svg 底部浮层）**
  - Given 工具栏已呼出
  - Then 底栏自左至右依次为：◀ 上一章、☰ 目录、进度条（Slider）+ 百分比文本、🔖 书签、Aa 按钮、
    下一章 ▶（用控件类型/语义顺序断言布局顺序，与 02-menus.svg 一致）。
- **US-7 上一章/下一章（02-menus.svg 两侧按钮）**
  - Given 当前章节 i 且 0 < i（非第一章）When 点击"上一章" Then 跳转章节 i−1 开头，进度保存为该章起点。
  - Given 当前章节 i 且 i < N−1（非末章）When 点击"下一章" Then 跳转章节 i+1 开头。
  - Given 第一章 When 点"上一章" Then 无操作（按钮禁用或不越界）；Given 末章 When 点"下一章" Then 无操作。
- **US-8 目录抽屉（02-menus.svg"☰ 目录" + README §3.3"侧拉目录抽屉（章节列表+当前章高亮）"）**
  - Given 工具栏已呼出
  - When 点击"☰ 目录"
  - Then 从侧边拉出**目录抽屉**：按 `view.chapters` 顺序列出全部章节标题，**当前章节条目高亮**
    （可断言高亮样式/选中标记）；抽屉覆盖正文侧边（02-menus.svg 底栏"目录"入口语义）。
  - When 点击抽屉中任一章节条目 j（j ≠ 当前）Then 抽屉关闭并跳转章节 j、`saveProgress` 被调用；
    When 点击当前章节条目 Then 抽屉关闭、章节不变。
  - When 点击抽屉外遮罩/关闭按钮 Then 抽屉关闭、章节不变（无跳转）。
- **US-9 可拖进度条 + 百分比（02-menus.svg"42% · 位置 1304/3120" + README §3.3"拖动实时预览，松手跳转"）**
  - Given 工具栏已呼出、已加载章节数据（已知章节数 N 与当前位置）
  - Then 进度条右侧显示**百分比文本**（格式如"42%"或"42% · 位置 x/y"，与原型一致；值来自当前进度映射）。
  - When 拖动进度条滑块到新位置（测试注入 drag）Then 拖动过程中实时更新预览（百分比/章节预览文本）；
    松手后**跳转到目标位置**并调用 `saveProgress`（进度持久化，REQ-001 通路）。
  - Given 进度条拖动中 When 松手前发生页面手势 Then 拖动与翻页互斥（拖动不触发边缘翻页，见 §5 风险1）。
- **US-10 书签（02-menus.svg"🔖 书签" + README §3.3"当前页加/取消书签（书签图标状态）"）**
  - Given 工具栏已呼出、当前页无书签 When 点击"🔖 书签" Then 当前页被标记书签，图标切换为
    "已书签"态（可断言图标/颜色/语义变化）；重复点击同一页不产生重复书签（幂等）。
  - Given 当前页已有书签 When 再次点击 Then 书签取消，图标恢复未书签态。

### 故事 3：Aa 显示设置 —— 作为所有用户，我想要在底部面板集中调字号/字体/主题/行距/翻页，以便读得舒服
- **US-11 Aa 面板打开/关闭（03-settings.svg 整图）**
  - Given 工具栏已呼出 When 点击底栏"Aa"按钮
  - Then 底部弹出**显示设置面板**（覆盖下半屏，正文淡化），面板**恰好含 5 行**：字号（滑块 + A−/A+ +
    pt 值）、字体（系统默认/衬线/无衬线）、主题（浅色/深色/护眼）、行距（紧凑/标准/宽松）、翻页
    （分页模式/滚动模式单选），面板标题"显示设置" + ✕（03-settings.svg 布局可逐项断言）。
  - When 点击 ✕ 或面板外区域 Then 面板关闭，回到正文（工具栏保持呼出态或回到沉浸态——以 02-adr
    定为准，两种均需被 widget 测试断言其一）。
- **US-12 Aa 面板各项即时生效（03-settings.svg 各控件 + README §3.4）**
  - 字号：Given 面板打开 When 拖动字号滑块或点 A+/A− Then 正文字号即时变化（滚动模式 `Text` 字号 /
    分页模式 `PagedWebView.fontSize` 参数重载，REQ-001 既有能力），面板显示当前 pt 值（如 18 pt）；
    字号范围沿用既有 `[14,16,18,20,24]`。
  - 字体：When 选"衬线/无衬线/系统默认" Then 正文字体族切换（滚动模式 TextStyle / 分页模式 WebView
    CSS 字体，按 02-adr 定实现，widget 断言字体族属性变化）。
  - 主题：When 选"深色/护眼/浅色" Then 正文区（及面板）背景/文字颜色切换为对应主题
    （浅色=白底深字、深色=深底浅字、护眼=米黄底深字，03-settings.svg 色样）。
  - 行距：When 选"紧凑/标准/宽松" Then 正文行距变化（滚动模式 `height` 参数；分页模式经既有 CSS
    机制，按 02-adr 定）。
  - 翻页模式：When 选"滚动模式" Then 立即从分页渲染切换为滚动渲染（渲染组件切换可断言）；
    When 再选"分页模式" Then 切回分页渲染，位置不丢（互切回归，见 US-16）。
- **US-13 右上角三个原按钮移除（README §四"与现状的差异"）**
  - Given 打开任意书、任意 UI 态（沉浸/呼出/面板）
  - Then 界面**不存在**右上角三个原按钮（模式切换 / 字号 / 目录），即无原
    `AppBar.actions` 中的 `IconButton(模式切换)`、`PopupMenuButton(字号)`、`PopupMenuButton(目录)`
    （widget 断言三者 `findsNothing`）；**模式切换入口仅存在于 Aa 面板"翻页"行（03-settings.svg）**，
    字号入口仅存在于 Aa 面板，目录入口仅存在于底栏 ☰（02-menus.svg）。

### 故事 4：选中与查词 —— 作为陈老师，我想要长按/选中文本出浮动工具条并查词/翻译，以便不打断阅读
- **US-14 长按/选中 → 浮动工具条（04-selection.svg 顶部浮动工具条）**
  - Given 滚动模式，正文含可选中文本
  - When 长按/拖拽选中一段文本
  - Then 选中文本上方出现**浮动工具条**，**恰好含 5 项且顺序为：划重点 / 笔记 / 翻译 / 查词 / 复制**
    （04-selection.svg；"笔记"项带 4 色圆点装饰可一并断言）。
  - When 点击"查词" Then 出现**词典卡片**（04-selection.svg 底部卡片：词名/音标/词性/释义/例句），
    **完全离线可用**（REQ-003 `dict_lookup`，零网络），行为与 REQ-003 US-16 一致（未收录→"未找到"、
    无词库→导入引导文案）。
  - When 点击"翻译" Then 出现**译文浮层**（REQ-003 `translate`，含 loading/错误+重试/Provider 名/
    缓存标记，行为与 REQ-003 US-15 一致）。
  - When 点击"复制" Then 选中文本写入系统剪贴板（可断言 `Clipboard.getData` 返回选中文本）。
  - When 点击"划重点"或"笔记" Then 不崩溃（本期占位，动作 TODO，提示"即将上线"或静默）。
  - When 点击工具条外/取消 Then 工具条与选中态关闭（沿用 REQ-003 取消行为）。
- **US-15 两模式选中逻辑统一（04-selection.svg + README §3.1/3.5"长按/选中文本 → 浮动工具条"）**
  - Given **分页模式**（WebView）When 长按选中文本（JS 选区回传 `onSelectedText`，REQ-003 既有能力）
    Then 弹出**与滚动模式完全相同的浮动工具条**（同一组件、同一控件集合"划重点/笔记/翻译/查词/复制"）。
  - Given 滚动模式 When 选中 Then 同一工具条组件实例（可断言两模式渲染的工具栏 key/类型一致）。
  - 断言点：两模式选中后，翻译/查词入口行为完全一致（US-14 复用），无各自独立实现。

### 故事 5：零回归与测试 —— 作为发布者，我想要重构不动既有能力，以便安全交付
- **US-16 既有功能零回归（REQ-001 进度 / REQ-003 翻译查词 / 听书占位）**
  - 读书进度（REQ-001）：Given 书中有已保存进度（章节+页/滚动位置）When 重新打开该书
    Then 恢复到上次章节与位置（`loadProgress` 通路不变）；When 翻页/切章/拖动进度条 Then `saveProgress`
    按既有语义持久化（href + progression）；**分页↔滚动互切后位置语义不跳变**（见 §5 风险4）。
  - 翻译/查词（REQ-003）：Given 注入 `translateBackend` When 选中文本点翻译/查词
    Then 译文浮层/词典卡片与 REQ-003 行为逐项一致（loading/错误重试/缓存标记/离线查词）；Given 未注入
    `translateBackend` When 选中 Then 翻译/查词入口隐藏（既有零注入行为不变）。
  - 听书占位：Given 工具栏呼出 When 展开"⋯ 更多" Then 含"听书"项（占位，点击不崩溃）；
    `listen_page.dart` 及其测试零改动。
- **US-17 widget 测试覆盖关键交互（对应本 REQ 全部核心交互）**
  - Given 测试注入 fake 后端 / fake `pagedViewBuilder`（既有注入点）
  - Then widget 测试覆盖并断言：① 沉浸态进入（无 AppBar/无工具 Chrome，US-1）；② 中部点击呼出/
    再点隐藏（US-2）；③ 分页模式边缘 15% 点击翻页、滚动模式边缘点击不翻页（US-3/US-4）；④ 顶栏
    ⋯ 更多四占位项（US-5）；⑤ 底栏六控件顺序（US-6）；⑥ 目录抽屉打开/章节跳转/当前章高亮（US-8）；
    ⑦ 进度条拖动预览与松手跳转 + 百分比显示（US-9）；⑧ Aa 面板打开、五选项行、字号/主题/翻页模式
    切换生效（US-11/US-12）；⑨ 选中浮动工具条五入口 + 查词卡片/译文浮层（US-14）；⑩ 右上角三按钮
    不存在断言（US-13）。

## 3. 影响面分析（必须非空）

- **app/lib/pages/reader_page.dart（核心重构，interface 层）**：删除常驻 AppBar 与右上角三个按钮
  （模式切换/字号/目录，含 `_fontSizes` 字号菜单与目录 PopupMenu）；新增**沉浸态状态机**（UI 可见性
  `_uiVisible` + 淡入淡出动画）；新增手势层：中央 1/3 呼出热区、左右 15% 边缘翻页热区（分页模式）、
  与 WebView/滚动视图的手势仲裁；新增顶栏浮层（← 返回/书名·章节名/⋯ 更多）+ 底栏浮层（上一章/☰
  目录/进度条/书签/Aa/下一章）；Aa 面板弹层；目录抽屉；进度条状态与拖动跳转逻辑（映射到既有
  `_goChapter`/`saveProgress`）；选中逻辑收敛（现有内嵌行式 `_buildSelectionToolbar` 被浮动工具条
  取代，`_onSelectedText`/`_doTranslate`/`_doLookup`/`_resetPopups` 复用）。
- **新增 widgets（app/lib/widgets/，interface 层）**：`directory_drawer.dart`（章节列表 + 当前章
  高亮 + 遮罩关闭）、`progress_slider.dart`（可拖 Slider + 百分比/位置文本 + 拖动预览）、
  `settings_sheet.dart`（Aa 面板：字号/字体/主题/行距/翻页模式五区块）、`selection_toolbar.dart`
  （浮动工具条：划重点/笔记/翻译/查词/复制，两模式共用）；翻译/查词浮层**复用**既有
  `translation_popup.dart`（零改动或仅微调定位）。
- **engines 选中能力统一（app/lib/engines/）**：分页模式 JS 选区回传（`paged_web_view.dart`
  `onSelectedText`，REQ-003 已实现）与滚动模式 `SelectionArea.onSelectionChanged`（现内联于
  reader_page）收敛到同一浮动工具条状态与定位逻辑；`reflow_engine.dart` 的 `selectText`（REQ-003
  遗留 TODO）是否本期兜底由架构阶段确认（若分页模式坐标定位工具条需要）。
- **既有 widget 测试更新（app/test/）**：`reader_page_test.dart` 等既有用例断言了"右上角按钮/
  行式选中工具条/底部两按钮/AppBar"结构，全部需要重写或更新；新增 US-1~US-17 用例；其余页面
  （library/listen/settings/notes）测试零改动但需回归。
- **ddd-rules 层归属（workflow/rules/ddd-rules.toml）**：`pages/**` 与 `widgets/**` 均已声明属
  **interface 层**，本 REQ 不修改规则表，但新增 4 个 widget 文件与重构后的 reader_page 必须通过
  ddd-lint（违规=0）；interface 层禁止直接 import Rust 生成物（只能经 services）。
- **进度模型 / Locator（core，可能零改动）**：进度条"章内进度 vs 全书进度"语义（§5 风险4）如只需
  UI 层映射，则 core `reading_progress`（href + progression）零改动；如需全书进度查询接口则触碰
  `core/src/api.rs` + FRB 再生成（interface 层，需新增桥接函数并同步 docs/03 §4 契约），由架构阶段
  决策后计入影响。
- **回归面（非空）**：core 全量测试（library/进度/Locator 零行为变化确认）；既有 Flutter widget
  测试（reader_page_test 更新 + 其余页面回归）；FFI 端到端（打开书/翻页/进度）；workflow 闸门
  （CRAP/DDD/变异）；`paged_web_view.dart` 与 `translation_popup.dart` 的既有测试（确认复用组件
  不回归）。

## 4. 依赖与优先级

- **既有渲染引擎（前置）**：`PagedWebView`（REQ-001：分页渲染、`fontSize` 参数重载、`onProgress`
  进度回传、`onSelectedText` 选区回传已具备，本 REQ 消费不重做）；滚动模式
  `SingleChildScrollView + SelectionArea`（已有）。
- **REQ-003 翻译/查词（前置）**：`translateBackend` 注入、`TranslationResultCard`/`DictResultCard`/
  `OverlayError`（`translation_popup.dart`）、`_doTranslate`/`_doLookup` 状态机全部复用；未注入时
  入口隐藏行为保留。
- **听书占位**：仅"⋯ 更多"菜单占位项，**不依赖** LISTEN 系列实现；`listen_page.dart` 不动。
- **占位项依赖**：划重点/笔记（NOTE-01/03 P0，后续 REQ）、书签完整功能（NOTE-06 P1）、阅读统计
  （READ-08 P2）、导出（NOTE-07 P1）——本 REQ 仅预留入口与图标态，不建数据模型。
- **优先级**：本 REQ **P0**（阅读器页为核心体验；README 状态"确认后按此实现 REQ-004"；用户已确认
  三项决策）。书架微调（README 待确认问题 3）另立 REQ，不占本期。

## 5. 风险

1. **手势冲突（高）**：沉浸态下中央呼出热区、左右 15% 边缘翻页热区、正文滑动/WebView 内部手势、
   长按选中的手势竞争 —— 边缘热区可能误吞滑动起点、呼出态下点击可能误触翻页；滚动模式下边缘不拦截
   （已定决策）仍需验证不误吞滑动。缓解：架构阶段出手势命中测试层级图（热区 vs 正文容器 vs WebView）；
   widget 测试覆盖"边缘点击 vs 滑动起点""拖动进度条不触发翻页"互斥用例（US-2/US-9/US-17）。
2. **两模式选中逻辑统一（中-高）**：分页模式选区来自 WebView JS 回传（仅文本、无坐标或坐标需增强
   JS 注入），滚动模式选区来自 Flutter 原生 —— 浮动工具条定位、选区归一（trim/跨行合并）需统一抽象；
   若分页模式坐标回传缺失，工具条定位需兜底方案（固定位置/按文本长度估算）。缓解：统一工具条组件 +
   定位抽象（架构阶段出设计）；必要时降级——分页模式沿用 REQ-003 既有最小选区回传、工具条固定位
   置呈现（记入 02-adr）。
3. **Aa 字号在 WebView 分页下的重排（中）**：分页模式调字号 → WebView 分页重排（REQ-001 已有
   `fontSize` 参数重载能力）；需回归确认重排后页位置不丢、进度不漂移、笔记锚定不漂移（NOTE 未上线
   时至少进度稳定）。缓解：US-12 断言 + 分页↔滚动互切回归（US-16）。
4. **进度条两模式位置语义（中）**：分页模式百分比=章内页位置 vs 全书位置、滚动模式=滚动偏移百分比，
   语义不一会导致模式互切时进度跳变/恢复位置错乱。缓解：架构阶段定统一映射（均归一为
   `href + progression` 既有模型），并加"分页↔滚动互切进度不变"回归用例（US-16）；若需全书百分比
   则评估 api.rs 新增接口（§3 影响面已列）。
5. **范围蔓延（中）**：占位项（⋯ 更多四项、划重点/笔记）与书架微调容易被顺手实现。缓解：§1 边界
   划界 + US-5/US-14 仅占位断言；书架另立 REQ。
6. **既有测试重构量（低-中）**：reader_page_test 结构断言（AppBar/行式工具条/底部两按钮）全量失效，
   重写量大。缓解：US-17 直接把新交互测试列为验收，重写测试即实现的一部分。

## 6. 闸门1 自评

- [x] **验收标准全部可测**：US-1~US-17 每条均为可断言观察项 —— 控件存在性/顺序/数量
  （`find.byType`、`findsNothing`、`findsNWidgets`）、点击坐标（中部 1/3、左右 15% 热区）、状态切换
  （呼出/隐藏、书签图标态、主题色、滚动偏移前后值）、回调触发（`saveProgress`/`translate`/`lookup`
  /`Clipboard.getData`）、文本内容（菜单四占位项、工具条五入口、百分比文本）；无"体验好"类不可测词；
  每条标注了 reader-ui-v2 原型图映射（01-immersive/02-menus/03-settings/04-selection + README 章节）。
- [x] **与既有 REQ 无重复**：REQ-001（WebView 分页渲染/进度）与 REQ-003（翻译/查词/选区回传）能力
  全部**复用不重做**（US-15/US-16 明确为消费既有能力）；READ-07 进度条拖动、NOTE-06 书签、NOTE-01/03
  划重点/笔记、LISTEN-01 听书、READ-08 阅读统计、NOTE-07 导出均为**产品层用户故事**，本 REQ 只按
  原型实现其 UI 交互与占位入口，功能本体明确划给对应后续 REQ（§1 边界划界）；书架微调显式排除
  （另立 REQ）。
- [x] **影响面清单非空**：reader_page.dart 重构（沉浸态/顶底栏/Aa 面板/手势层/选中收敛）、4 个新增
  widgets、engines 选中统一（分页 JS 回传 + 滚动 SelectionArea → 同一工具条）、既有 widget 测试更新
  （reader_page_test 全量重写 + 新增 US-1~17）、ddd-rules 层归属复核（interface 层新增文件过 lint）、
  进度模型/Locator（UI 映射，core 大概率零改动 + 可能的 api 接口决策）、回归面（core 全量/既有 widget/
  FFI/闸门）共 7 类，均列具体条目与约束。
