<!-- wf-meta: req=REQ-009-notes-search | phase=product-preview | agent=product-reviewer | date=2026-09-09 | gate=passed -->
# REQ-009-notes-search · 阶段5a 产品验收（设计稿 ↔ 真实渲染截图 对照）—— rework-B 后复验

> **视角**：产品/用户（非开发自评）。UI 权威：`docs/wireframes/06-selection-toolbar.svg`、
> `07-annotation-panel.svg`、`04-search.svg`（均 900×640 横屏低保真）。
> **截图来源**：**真实引擎渲染**（`xvfb-run flutter test integration_test/screenshots_test.dart -d linux`
> + `RepaintBoundary.toImage(pixelRatio:3.0)`，真实字体/真实 `ReaderPage`/`SearchPage` + 注入
> `FakeNotesBackend`/`FakeSearchBackend`），**未使用** `app/test/goldens/*.png`（widget 测试 Ahem 方块占位）。
>
> **采集命令**：`bash scripts/ui-screenshots.sh REQ-009`
> **采集结果（rework-B 后复验，2026-09-09）**：**退出码 0**；`screenshots_test.dart` **17 passed / 0 failed**（其中 REQ-009 新增 4 例）；
> 报告 `product-preview-REQ-009-notes-search.html`（4 屏，**1,087,027 B**；总屏数 4 / 视口不一致 4 /
> 无实现截图 0；内嵌 4 张 SVG + 4 张 base64 PNG）。
> **本次复验结论**：首轮 deviation=1（D1）已由 rework-B 修复并复验归零，**deviation = 0 → 闸门5 前置 passed**（见 §2、§8）。
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
| 「第 N 章 · 章节名」的 **N** | 实现为 `Text('第 ${hit.chapterIndex + 1} 章 · ${hit.chapterTitle}')`（`app/lib/pages/search_page.dart:198`），`chapterIndex` = **该书真实章节序号（0 基）**，由 `core/src/api.rs::search` 经 `chapter_indices(book_id)`（`open_book` 章节顺序 `href→序号`）回填，跨书各自 0 基；截图中三条显示 **第 1 / 第 3 / 第 2 章**，与线框 04 示例（各书真实章号）一致 | **通过（rework-B D1 已闭环）** |

**S3 结论：通过。** 结果行「第 N 章」已改为各书真实章节序号（第 1 / 第 3 / 第 2 章，与线框 04 一致），首轮 D1 闭环；其余验收点全部命中。

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
| ~~D1~~ | S3 全文搜索 | 做错（语义）——**已闭环** | **首轮**：结果行「第 N 章」用结果列表序号而非真实章节序号（`search_page.dart:198` `第 ${index + 1} 章`，数据模型无 `chapter_index`），S3 渲染「第 1 / 2 / 3 章」与线框 04 的「第 1 / 3 / 2 章」不符 | **rework-B 修复 + 复验通过（deviation 归零）** |

> **deviation 计数 = 0**（首轮 1 项 D1 经 `REWORK-REQ-009-B` 修复并复验闭环；无新增偏差）。→ 闸门5 前置 **passed**。

### 2.1 D1 闭环复核（rework-B 后，2026-09-09）

| 复核项 | 独立证据 | 结果 |
|---|---|---|
| **渲染代码** | `app/lib/pages/search_page.dart:198` 已改为 `'第 ${hit.chapterIndex + 1} 章 · ${hit.chapterTitle}'`（不再引用结果列表 `index`；`index` 仅用于 `search-locate-N` key） | ✅ |
| **数据回填** | `core/src/api.rs:704 chapter_indices(book_id)`：`open_book` 枚举章节顺序 → `href→0 基序号`；`api.rs:961-978` 按命中 `book_id` 去重逐书回填，跨书各自 0 基，`href` 未命中保持 0 不 panic | ✅ |
| **Rust 端语义** | 独立重跑 `cargo test --release --test notes_search_api` → **1 passed / 0 failed**；用例断言全量命中 `chapter_index == 书库章节序号`，并构造**非首章**（idx≥1）命中证明非列表序号（`core/tests/notes_search_api.rs:229-283`） | ✅ |
| **Dart 端跨书反例** | 独立重跑 `flutter test test/search_page_test.dart` → **12 passed / 0 failed**；`search_page_test.dart:242-271` 构造第 1 条 `chapterIndex=2`（→第 3 章）、第 2 条 `chapterIndex=1`（→第 2 章），断言 `第 3 章 · 第三章`/`第 2 章 · 第二章` 存在且 `第 1 章 · 第三章` 不存在（若用列表序号必失败） | ✅ |
| **真实渲染截图** | 独立重跑 `bash scripts/ui-screenshots.sh REQ-009` → **退出码 0**、**17 passed / 0 failed**；`screenshots_test.dart:596-598` 断言三条分别为 `第 1 章 · 城市与记忆` / `第 3 章 · 城市与符号` / `第 2 章 · 城市与贸易` 后再 `_shot`；`app/screenshots/search_page.png` 重生成（223,092 B，1170×2532，与 HEAD 一致、与修复前版本 sha256 不同） | ✅ |
| **像素级差异定位** | 与修复前截图逐像素比对：全图仅 2 处变化带——dev y 889–915 与 y 1237–1263，均落在 dev x 99–118（逻辑 x 33–39，即「第 N 章」中 **N** 的字符位）。即仅第 2、3 条结果的**章号数字**改变（1/2/3 → 1/3/2），第 1 条（数字不变）及其余文字/按钮/筛选面板零变化 | ✅ |
| **设计同步** | `02-design.md` §3/§4.4/§6.3 已同步 `chapter_index`（标注 rework-B D1，`hit.chapterIndex + 1`）；零 schema 变更（`fts_books` 列不变） | ✅ |

> D1 复核结论：**「第 N 章」= 各书真实章节序号，与线框 04 的「第 1 / 3 / 2 章」语义一致**（非列表顺序 1/2/3）。首轮偏差闭环。

**（首轮修复建议留档，已按方案 1 忠实修复）**：
1. **忠实修复（已采纳）**：`SearchHit`/`SearchHitView`/`SearchHitData` 增 `chapter_index: u32`（`api.rs` 按书库章节顺序回填），UI 渲染 `第 ${hit.chapterIndex + 1} 章 · ${hit.chapterTitle}`；同步更新集成/widget 测试断言。
2. **或降级并改设计/原型**（未采纳）：去掉「第 N 章 · 」前缀、只显示章节名。

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

- **逐屏判定（rework-B 后复验）**：S1 **通过**、S2 **通过**、S3 **通过**、S4 **通过**。
- **deviation 计数 = 0**（首轮 D1：搜索结果「第 N 章」用结果序号而非章节序号 → 已按 rework-B 方案 1 修复并复验闭环；无新增偏差）。
- **闸门5 前置判定：passed** —— 无未授权偏差，允许 release-manager 合并主线（闸门5b）。
- 其余差异（视口方向、查词入口、面板形态/宽度、色值、M3 主题色、工具条样式）均为设计/ADR 已授权取舍或既有基线，不计入 deviation。
- 建议（非阻塞）：补 390×844 竖屏设计稿以支持像素级视觉验收；真机按 US-24 清单执行。
- 遗留（非本闸门阻塞）：Android 真机 US-24 ①–⑧ 未执行（本环境无设备，登记于 `03-review §6.1`）。

---

## 7. 本阶段产物

| 文件 | 变更 |
|---|---|
| `workflow/backlog/REQ-009-notes-search/05b-product-preview.md` | 新增（首轮）+ **本次复验更新（D1 闭环、deviation=0、gate=passed）** |
| `workflow/backlog/REQ-009-notes-search/product-preview.manifest.json` | 新增（4 屏清单） |
| `workflow/backlog/REQ-009-notes-search/product-preview-REQ-009-notes-search.html` | 新增（首轮 4 屏）+ **本次重生成（4 屏，1,087,027 B）** |
| `workflow/rework/REWORK-REQ-009-B.md` | 新增（D1 偏差处置 + developer 修复/复验回填） |
| `app/integration_test/screenshots_test.dart` | 追加 REQ-009 S1–S4 真实截图用例；S3 断言真实章号 1/3/2 |
| `app/screenshots/{selection_toolbar_colors,notes_panel,search_page,notes_jump_temp_highlight}.png` | 真实渲染截图（本次重跑；S3 `search_page.png` 223,092 B 已含修复） |

---

## 8. 复验执行记录（rework-B 后，product-reviewer 独立实跑）

| # | 命令 | 结果 |
|---|---|---|
| 1 | `bash scripts/ui-screenshots.sh REQ-009` | **退出码 0**；cargo build → `screenshots_test.dart` **17 passed / 0 failed** → 报告重生成；4 屏 |
| 2 | `flutter test test/search_page_test.dart` | **12 passed / 0 failed**（含跨书真实章号反例，证明非列表序号） |
| 3 | `cargo test --release --test notes_search_api` | **1 passed / 0 failed**（全量 + 非首章 `chapter_index` == 真实章节序号） |
| 4 | `xvfb-run -a flutter test integration_test/notes_search_integration_test.dart -d linux` | **2/2**（US-10、US-22 真实选词/搜索→定位） |
| 5 | 截图逐像素比对（修复前 vs 修复后 `search_page.png`） | 仅 2 处变化带，均在「第 N 章」数字字符位（逻辑 x 33–39）：第 2、3 条 1/2/3 → 1/3/2 |
| 6 | `app/screenshots/search_page.png` 哈希 | 与 HEAD 一致（`c1a25b4a…`，223,092 B），确认为最新真实渲染 |

> **复验结论**：S3「第 N 章」= 真实章节序号，与线框 04 的「第 1 / 3 / 2 章」语义一致；S1/S2/S4 证据文件字节级未变，判定维持通过。**deviation = 0 → 闸门5 前置 passed**。
