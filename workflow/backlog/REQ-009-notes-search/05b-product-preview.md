<!-- wf-meta: req=REQ-009-notes-search | phase=product-preview | agent=product-reviewer | date=2026-09-09 | gate=failed -->
# REQ-009-notes-search · 阶段5a 产品验收（设计稿 ↔ 真实渲染截图 对照）

> **视角**：产品/用户（非开发自评）。UI 权威：`docs/wireframes/06-selection-toolbar.svg`、
> `07-annotation-panel.svg`、`04-search.svg`（均 900×640 横屏低保真）。
> **截图来源**：**真实引擎渲染**（`xvfb-run flutter test integration_test/screenshots_test.dart -d linux`
> + `RepaintBoundary.toImage(pixelRatio:3.0)`，真实字体/真实 `ReaderPage`/`SearchPage` + 注入
> `FakeNotesBackend`/`FakeSearchBackend`），**未使用** `app/test/goldens/*.png`（widget 测试 Ahem 方块占位）。
>
> **采集命令**：`bash scripts/ui-screenshots.sh REQ-009`
> **采集结果**：**退出码 0**；`screenshots_test.dart` **17 passed / 0 failed**（其中 REQ-009 新增 4 例）；
> 报告 `product-preview-REQ-009-notes-search.html`（4 屏，1,081,241 B；总屏数 4 / 视口不一致 4 /
> 无实现截图 0；内嵌 4 张 SVG + 4 张 base64 PNG）。
>
> **判定方法说明**：本轮评审为纯文本环境（模型不支持图像输入），故逐屏判定基于**真实渲染 PNG 的
> 像素/几何分析**（唯一色数、色彩饱和度、行/列墨迹聚类、色块 bbox、区域色彩统计），证据均为可复算
> 坐标；并交叉引用本阶段独立复跑的真实集成测试与源码核对。所有证据来自真实引擎输出，非开发口述。

---

## 0. 独立复核命令（本阶段实跑）

| # | 命令 | 结果 |
|---|---|---|
| 1 | `bash scripts/ui-screenshots.sh REQ-009` | **退出码 0**；cargo build → 集成截图（17 passed/0 failed）→ 报告生成；4 屏 |
| 2 | `xvfb-run -a flutter test integration_test/screenshots_test.dart -d linux` | **17 passed / 0 failed**（含 REQ-009 S1–S4 真实长按/点击/面板/跳转） |
| 3 | `xvfb-run -a flutter test integration_test/notes_search_integration_test.dart -d linux`（03-review 记录） | **2/2**（US-10 选词→高亮→面板→跳回；US-22 搜索→结果→定位） |
| 4 | `flutter test test/no_synthetic_chrome_test.dart` | 绿（新截图用例不构造 `ReaderTopBar(`/`ReaderBottomBar(`） |
| 5 | `flutter analyze integration_test/screenshots_test.dart` | **No issues found!** |

新增/变更的截图用例与产物（`app/integration_test/screenshots_test.dart` 追加，未新建文件）：

| 截图用例 | 产物 PNG | 尺寸 | 字节 |
|---|---|---|---|
| screenshot 选词工具条·四色高亮（REQ-009 S1） | `selection_toolbar_colors.png` | 1170×2532 | 139,576 |
| screenshot 笔记面板·章节分组（REQ-009 S2） | `notes_panel.png` | 1170×2532 | 203,758 |
| screenshot 全文搜索·结果与筛选（REQ-009 S3） | `search_page.png` | 1170×2532 | 223,079 |
| screenshot 笔记跳回原文·临时高亮（REQ-009 S4） | `notes_jump_temp_highlight.png` | 1170×2532 | 220,959 |

> 4 张截图唯一色数 992 / 1460 / 1340 / 1441（真实字体抗锯齿，**非 Ahem 方块**），非空白、非占位。

---

## 1. 逐屏对照表

### S1 选词浮动工具条 · 四色高亮 —— 线框 `06-selection-toolbar.svg`

- 设计稿：`docs/wireframes/06-selection-toolbar.svg`（900×640 横屏）
- 实现截图：`app/screenshots/selection_toolbar_colors.png`（真实 `ReaderPage` 长按选词 → 点「高亮」展开）

| 设计意图 / 验收点 | 实现证据（真实渲染像素/几何） | 判定 |
|---|---|---|
| 浮动工具条随选区定位、不遮挡正文 | 工具条落在选区上方逻辑 y≈240–280（正文选中行之下方为选柄/选区），水平居中（中心 x≈195=390/2） | 通过 |
| 动作入口：复制 / 高亮 / 划线 / 批注 / 翻译 | 动作行（dev y 722–841）检测到 **6 个等距墨迹簇**，逻辑 x=53–76 / 106–128 / 157–180 / 209–232 / 261–284 / 313–336（间距≈52），即 6 个「图标+文字」按钮 | 通过 |
| 保留「查词」入口（REQ-003 授权） | 第 6 簇存在，与 02-design §6.1「复制/高亮/划线/批注/翻译/查词」一致 | 通过（tradeoff） |
| 高亮 4 色点（黄/蓝/绿/粉） | 展开的色点行（逻辑 y 293–319）检测到 **4 个 26×26 圆形色块**，中心 cx=137.8 / 175.8 / 213.8 / 251.8（等距 38），颜色为 `#FBC02D` / `#1A73E8` / `#43A047` / `#E91E63`，顺序与线框一致 | 通过 |
| 选色后落库 `kind=highlight` + 所选色 | 集成 US-10 断言：点蓝点后 `notes.store` 落库 `kind=highlight, color=#1A73E8`、`start!=null`、`takeException()==null` | 通过 |
| 拖动两端蓝色手柄调整选区 | `SelectionArea` 内建（02-design §6.1「不额外实现」），非本 REQ 新增 | 通过 |

**S1 结论：通过。** 6 入口 + 4 色点齐全、顺序与线框一致；色值与「点开高亮再选色」为已授权取舍。

---

### S2 笔记面板 · 章节分组 —— 线框 `07-annotation-panel.svg`

- 设计稿：`docs/wireframes/07-annotation-panel.svg`（900×640 横屏）
- 实现截图：`app/screenshots/notes_panel.png`（真实 `ReaderPage` 覆盖层，预置两章 6 条笔记）

| 设计意图 / 验收点 | 实现证据（真实渲染像素/几何） | 判定 |
|---|---|---|
| 右侧 360px 白面板、左侧竖边框 | 面板左缘 dev x≈117（逻辑 39），面板宽 351 逻辑（390−39）；`min(360, 屏宽*0.9)` = 351（ADR D7 降级线） | 通过（tradeoff） |
| 打开时主体调暗、点外关闭 | 面板左侧阅读器区域像素 = `(189,190,193)`（白底叠加 `Colors.black26` 的理论值 188.7）→ 主体确已调暗；scrim `GestureDetector` 点外关闭（US-9 widget 测试） | 通过 |
| 标题「笔记」+ ✕ / 搜索框「搜索笔记」 | 面板内行带：逻辑 y 24–39（标题行）、y 60–100（搜索框）；`NotesPanel` 头部 + `Key('notes-search')`（hint「搜索笔记」） | 通过 |
| 章节分组（组头章节名） | 面板内检测到 **2 个分组头**（逻辑 y 123–135「第一章」、y 338–350「第二章」），组内共 6 条 | 通过 |
| 色标（左竖条 == color） | 检测到色标竖条：**黄 3 条、蓝 2 条**（`#FBC02D` 5,654 px / `#1A73E8` 3,168 px，比例≈3:2，与预置 3 黄 2 蓝吻合），竖条 x=逻辑 51、宽 4 逻辑 px | 通过 |
| 原文片段 / 批注 / 时间（MM-dd） | 每行带含片段行 + 批注行；时间 `_timeLabel` → `MM-dd`（线框 `01-12` 样式）；6 行均在（逻辑 y 151/211/271/366/426/489 起） | 通过 |
| 底部「导出」（左）/「全部删除」（右，红字） | 底部栏逻辑 y 804–836：左侧 `FilledButton` 导出（M3 主题色 bbox 逻辑 x 51–127）；右侧红字 `全部删除`（`#D93025` bbox 逻辑 x 310–364） | 通过 |
| 编辑批注卡片 / 多选批量删除 / 点外关闭 | 静态帧未展开；由 `notes_panel_test.dart` / `reader_notes_test.dart` 覆盖（US-11/12/13/9），交互控件与线框 07 一致 | 通过（见 §5 gap） |
| （并入）书签行 🔖 无色标 | 面板内检测到黄色书签图标（`Icons.bookmark` `#FBC02D`），该行无色标竖条 | 通过 |

**S2 结论：通过。** 线框 07 的结构元素（面板/标题/搜索/分组/色标/片段/批注/时间/导出/全部删除/调暗/点外关闭/书签行）逐项命中。

---

### S3 全文搜索 · 结果与筛选 —— 线框 `04-search.svg`

- 设计稿：`docs/wireframes/04-search.svg`（900×640 横屏）
- 实现截图：`app/screenshots/search_page.png`（真实 `SearchPage`，复刻线框三本书/三章）

| 设计意图 / 验收点 | 实现证据（真实渲染像素/几何） | 判定 |
|---|---|---|
| 顶部搜索框 + 放大镜 +「全文搜索」按钮 | 搜索栏逻辑 y 75–92：左侧放大镜 + `Key('search-field')` + 右侧 `FilledButton('全文搜索')` | 通过 |
| 结果行：书名（粗） | 3 条结果的书名行（逻辑 y 125 / 260 / 376 起），`FontWeight.bold` | 通过 |
| 上下文关键词**蓝色加粗** | 结果区检测到 4 处 `#1A73E8` 蓝色文本带（逻辑 y 200–212 / 316–328 / 335–347 / 451–463），为 3 条命中的「卡尔维诺」span（其中第 2 条跨行断成两段） | 通过 |
| 「定位」按钮 | 每条结果右侧 `OutlinedButton('定位')`；`Key('search-locate-0')` 存在（集成 US-22 点击后跳转） | 通过 |
| 右侧筛选面板：按范围（全部书籍/当前书籍） | 筛选面板（`#ECEEF1`，逻辑 x 210–382）；「全部书籍」选中态为蓝色实心单选（`#1A73E8` bbox 逻辑 x 224–238, y 196–210） | 通过 |
| 按格式（EPUB/PDF/MOBI，复选） | 3 个 `CheckboxListTile`；默认 `_formats={'EPUB','MOBI'}` 与线框勾选状态（EPUB✓ PDF✗ MOBI✓）一致 | 通过 |
| 「结果 N 条 · X.XXs」 | 面板底部 `Key('search-stats')` → `结果 ${_hits.length} 条 · ${_elapsed.toStringAsFixed(2)}s` | 通过 |
| 空态 / 空查询提示 | `未找到相关结果` / `请输入关键词`（widget 测试覆盖 US-18） | 通过 |
| 「第 N 章 · 章节名」的 **N** | 实现为 `Text('第 ${index + 1} 章 · ${hit.chapterTitle}')`（`search_page.dart:198`），`index` = 结果列表序号；截图中三条显示 **第 1 / 第 2 / 第 3 章**，而线框示例为 **第 1 / 第 3 / 第 2 章**（各书真实章号） | **偏差（做错）** |

**S3 结论：有偏差（1 项，见 §2）。** 除「第 N 章」语义外，其余验收点全部命中。

---

### S4 笔记跳回原文 · 临时高亮 —— 线框 `07-annotation-panel.svg`

- 设计稿：`docs/wireframes/07-annotation-panel.svg`（点击条目跳回原文并临时高亮）
- 实现截图：`app/screenshots/notes_jump_temp_highlight.png`（点第二章笔记条目后）

| 设计意图 / 验收点 | 实现证据（真实渲染像素/几何） | 判定 |
|---|---|---|
| 点条目 → 面板关闭 + 阅读器定位到目标 | 面板消失；跳转后顶/底栏仍在（顶栏 y≈60、底栏 y≈2450 检测到 chrome 面色） | 通过 |
| 临时高亮覆盖命中区间 | 检测到 `Color(0x331A73E8)` 合成色 `(209,227,250)` 的**两块背景矩形**：逻辑 x 280–352,y 268–299 与 x 24–60,y 300–332——为同一 6 字区间「城市是记忆的」跨行换行后的两段，总覆盖≈6 字，**精确匹配锚点 [14,20)** | 通过 |
| 临时高亮颜色区别于持久化高亮 | 该屏**未**检测到持久化色 `#1A73E8` 实心像素（temp 覆盖优先，`composeSpans` 语义），颜色为 20% 蓝 | 通过 |
| 跳转更新 `reading_progress` / 听读同进度 | `_jumpTo` 复用 `_changeChapter` + `ProgressSaver`（02-design §4.3）；集成 US-10 断言跳转位置与 `Key('temp-highlight')` | 通过 |
| 临时高亮超时/滚动/点击消失 | `_scheduleTempClear` Timer(3s) + 滚动/点击清除（reader_notes_test 覆盖）；本截图后 `pump(4s)` 清理定时器 | 通过 |

**S4 结论：通过。** 临时高亮按文本锚精确覆盖命中文本（跨行正确分段），与持久化高亮颜色可区分。

---

## 2. 偏差清单

| # | 屏 | 类型（少做 / 做错 / 发明） | 证据 | 判定 |
|---|---|---|---|---|
| **D1** | S3 全文搜索 | **做错（语义）** | 结果行「第 N 章」用**结果列表序号**而非**书籍章节序号**：`search_page.dart:171` `itemBuilder: (context, i) => _resultRow(i, _hits[i])` + `:198` `'第 ${index + 1} 章 · ${hit.chapterTitle}'`。线框 04 示例三条结果为「第 1 / 3 / 2 章」（各书真实章号，非顺序号）。S3 截图复刻线框同三本书/三章，实际渲染为「第 1 / 2 / 3 章」，其中第 2、3 条与线框不符。集成测试 `notes_search_integration_test.dart:166` 断言 `'第 1 章 · 第二章'`（命中所在章为第二章却显示第 1 章），锁定该行为。数据模型 `SearchHit`/`SearchHitView`/`SearchHitData` 无章节序号字段（`core/src/types.rs:307`、`core/src/api.rs:187`、`app/lib/services/search_backend.dart:14`），UI 无法取到真实章号 | **偏差 → rework-B** |

> **deviation 计数 = 1**（未授权偏差 1 项）。→ 闸门5 前置 **failed**，需 `workflow/rework/REWORK-REQ-009-B.md`。

**修复建议（供架构裁定）**：
1. **忠实修复（推荐）**：`SearchHit`/`SearchHitView`/`SearchHitData` 增 `chapter_index: u32`（由 `api.rs` 按书库章节顺序回填，或索引时随章写入），UI 渲染 `第 ${hit.chapterIndex + 1} 章 · ${hit.chapterTitle}`；同步更新集成/widget 测试断言。
2. **或降级并改设计/原型**：若架构判定真实章号超出本期范围，则去掉「第 N 章 · 」前缀、只显示章节名，并同步修订 `02-design §6.3` 与线框 04，避免"第 N 章"与章节名自相矛盾（如「第 1 章 · 第二章」）。

> 说明：D1 为**单行、用户可见**的标签语义问题，根因在数据模型缺章节序号（架构级），故按流程记 rework-B。

---

## 3. 授权取舍 / 低风险差异说明（**非偏差，不计入 deviation**）

1. **视口方向不一致（4/4）**：设计稿 **900×640 横屏**，实现 **390×844 竖屏**。→ REQ-004~008 已沿用既有 tradeoff；报告脚本自动标注「⚠ 视口不一致」，不构成阻塞。
2. **「查词」入口保留（S1）**：线框 06 未画「查词」，01-req §1.5 明确保留（REQ-003 回归），02-design §6.1 授权。
3. **高亮四色「点开后展开」（S1）**：02-design §6.1「「高亮」→ 展开 4 色选色」授权；线框把色点画在「高亮」下方，实现为工具条下方独立一行，语义一致。
4. **四色色值**：实现 `#FBC02D/#1A73E8/#43A047/#E91E63`，线框 `#F9AB00/#1A73E8/#34A853/#F06292`。→ ADR C15 / 02-design §6.1「复用工具栏既有 4 色，不引入新色板」授权。
5. **面板宽度 min(360, 屏宽*0.9)=351**（S2）：ADR D7 降级线授权；竖屏下仍为「右侧覆盖层 + 点外关闭」语义。
6. **M3 主题色**：`FilledButton`（导出/全文搜索）与 `Checkbox` 用 M3 主题主色（紫），线框示意蓝；`Radio`（全部书籍）显式蓝 `#1A73E8`。→ 既有 App 主题基线（REQ-004 起），非本 REQ 引入，同 REQ-008 §4.3 口径。
7. **工具条「图标+文字」按钮**：线框为低保真纯文字；实现沿用 REQ-003 既有工具条样式（图标+文字），动作集合一致。
8. **书签行并入面板（S2）**：线框 07 未画书签行，02-design §6.2「（并入）书签行」授权。

---

## 4. 结构性结论：视口方向不一致（4/4）

- 4 张设计稿均为 900×640 横屏，实现截图 1170×2532 竖屏；脚本对 4 屏全部标注「⚠ 视口不一致」。
- **竖屏适配合理性**：
  - 06 工具条：6 按钮 + 4 色点均落在 390 宽内（最右簇逻辑 336 < 390），无溢出。**合理。**
  - 07 面板：`min(360, 0.9*屏宽)` 在竖屏收窄到 351，控件纵向堆叠正常。**合理。**
  - 04 搜索：筛选面板固定 172 逻辑宽，结果区自适应；390 宽下筛选面板 + 结果区并存无横向挤压。**合理。**
- **限制与建议**：横屏低保真稿只能校验「结构/元素有无/行为/文案」，无法校验横向比例/间距级视觉还原。若需像素级视觉验收，建议补 **390×844 竖屏设计稿**。当前**不构成 D1 之外的新偏差**。

---

## 5. Gap / 未覆盖说明（静态帧无法覆盖，由其它层级承担）

| 项 | 说明 | 处置 |
|---|---|---|
| 编辑批注卡片 / 改色 / 多选批量删除 / 二次确认 | 静态帧未展开 | `notes_panel_test.dart`、`reader_notes_test.dart`（US-11/12/13，绿） |
| 导出保存框 / 空笔记提示 / 移动端路径 | 依赖平台对话框 | widget 测试（US-16/17）+ 真机 US-24⑤ |
| 面板搜索过滤 / 空态 | 静态帧未输入关键词 | `notes_panel_test.dart`（US-7，绿） |
| 真实 FTS5 CJK 搜索（2 字词） | 需 Rust 引擎 | `cargo test --release --test notes_search`（03-review：城市/卡尔维诺/记忆均命中，≤100ms） |
| Android 真机 US-24 ①–⑧ | 本环境无设备 | **未执行**，遗留登记（03-review §6.1） |

---

## 6. 结论

- **逐屏判定**：S1 **通过**、S2 **通过**、S3 **有偏差（D1）**、S4 **通过**。
- **deviation 计数 = 1**（D1：搜索结果「第 N 章」用结果序号而非章节序号，与线框 04 不符）。
- **闸门5 前置判定：failed** —— 需 `workflow/rework/REWORK-REQ-009-B.md` 回架构/开发修正后重跑闸门3–5a。
- 其余差异（视口方向、查词入口、面板形态/宽度、色值、M3 主题色、工具条样式）均为设计/ADR 已授权取舍或既有基线，不计入 deviation。
- 建议（非阻塞）：补 390×844 竖屏设计稿以支持像素级视觉验收；真机按 US-24 清单执行。

---

## 7. 本阶段产物

| 文件 | 变更 |
|---|---|
| `workflow/backlog/REQ-009-notes-search/05b-product-preview.md` | 新增（本报告） |
| `workflow/backlog/REQ-009-notes-search/product-preview.manifest.json` | 新增（4 屏清单） |
| `workflow/backlog/REQ-009-notes-search/product-preview-REQ-009-notes-search.html` | 新增（4 屏，1,081,241 B） |
| `workflow/rework/REWORK-REQ-009-B.md` | 新增（D1 偏差处置） |
| `app/integration_test/screenshots_test.dart` | 追加 REQ-009 S1–S4 真实截图用例 |
| `app/screenshots/{selection_toolbar_colors,notes_panel,search_page,notes_jump_temp_highlight}.png` | 新增真实渲染截图 |
