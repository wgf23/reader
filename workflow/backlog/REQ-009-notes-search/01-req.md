<!-- wf-meta: req=REQ-009 | phase=requirements | agent=req-analyst | date=2026-09-09 | gate=passed -->
# REQ-009-notes-search · 笔记（NOTE-01~07）+ 全文搜索（READ-06）—— 需求分析

## 1. 背景与目标

### 1.1 问题现象（用户原始诉求，不可偏离）

- **选中文字后"划重点/笔记"无任何反应**：浮动工具条已渲染，但 `reader_page.dart` 的
  `_onSelectionAction` 对 `highlight`/`note` 直接 `break`（占位），用户无法创建任何持久化笔记。
- **没有任何笔记能力落地**：`core/src/notes/mod.rs` 只有 `AnnotationService` 空壳（15 行 TODO），
  `annotations` 表未建；`notes_page.dart` 仅 14 行骨架；书签仅会话内切换（不落库）；导出按钮为占位。
- **没有全文搜索**：`core/src/search/mod.rs` 只有 `SearchService` 空壳（11 行 TODO），
  `fts_books` 虚拟表未建；`search_page.dart` 仅 14 行骨架。
- **期望**：选中文字可多色高亮/划线/批注并持久化；笔记面板按章节浏览全书笔记并跳回原文；
  可编辑/改色/删除；书签当前页；导出 Markdown/JSON；全书/全文搜索并定位跳转。

### 1.2 成功标准与范围划界

**成功标准一句话**：在**真实 `ReaderPage`** 中选中文字 → 浮动工具条创建 **≥4 色高亮/划线/批注**并持久化到
SQLite（迁移 v4：`annotations` 表）；**真实笔记面板**按章节列出全书笔记（色标+原文片段+批注+时间），
点击条目**跳回原文并临时高亮**；可编辑/改色/删除（面板内多选批量删除+二次确认+锚点数据清理）；
可书签当前页并在书签列表跳转；可导出 Markdown/JSON（含书名/章节/锚点/原文片段/批注/时间，空笔记提示）；
**全书/全文搜索（FTS5）**返回关键词高亮的结果列表并可定位跳转 + 范围筛选（全部书籍/当前书籍 + 按格式）；
全程以**真实 `integration_test`（选词→高亮→面板→跳回；搜索→结果→跳转）**+ widget 测试 + 单测分层验证，
禁止合成页绕过；不破坏 `reading_progress` / Locator 不变式 / 听读同进度 / 既有选词翻译查词。

**本期范围（P0/P1，必须）**：

**A · 笔记 NOTE-01~07（P0）**

1. **NOTE-01 高亮**：选中文字 → 工具条高亮入口 → **≥4 色**可选 → 高亮持久化；换字号/换主题/重新分页后
   高亮**不丢失**（文本锚点重定位）；同一段可叠加不同色高亮。
2. **NOTE-02 划线**：与高亮同一工具条入口，单线样式；其余行为同高亮。
3. **NOTE-03 批注**：工具条"批注"弹输入框；批注与锚点一起持久化；可对已有高亮追加批注；可编辑/删除。
4. **NOTE-04 笔记面板**：按章节分组列出全书笔记（色标+原文片段+批注+时间）；面板内搜索笔记；
   点击条目跳回原文并**临时高亮**该位置；面板可打开/关闭、点击面板外空白关闭。
5. **NOTE-05 整理**：任意笔记可编辑/改色/删除；面板内**多选批量删除**；删除前**二次确认**；
   删除后锚点数据（含界面高亮）一并清理。
6. **NOTE-06 书签**：阅读中一键书签当前页并持久化；书签列表可跳转（与笔记面板并列或并入）。
7. **NOTE-07 导出**：Markdown 与 JSON 两种格式；内容含书名/章节/锚点/原文片段/批注/时间；
   桌面端弹保存对话框；导出不阻塞；**空笔记给出提示**。

**B · 全文搜索 READ-06（P1，本期必做）**

8. 全书/全文搜索：结果列表（书名 + 章节名 + 上下文片段 + 命中数/耗时）+ **关键词高亮** + 定位跳转。
9. 范围筛选：**全部书籍 / 当前书籍**；**按格式**筛选（EPUB/PDF/MOBI…）为线框 04 的筛选面板 UI 元素。
10. 索引在书籍导入/打开时构建；既有书库在 v4 迁移/首次搜索时回填索引。

**明确不做（另立 REQ / 回归守住）**：

- 笔记跨设备同步（NOTE-08，P2 接口预留，`sync_status` 列已预留但本期不实现同步协议）。
- 桌面快捷键体系（`N` 笔记面板 / `Ctrl+F` 搜索 / `Ctrl+H` 高亮）——归 SET-02（P1 另立 REQ），
  本 REQ 只保证对应动作可由 UI 触发。
- 听书跟读高亮（LISTEN-08，REQ-005/006 已交付，`listen_follow_highlight.dart`）——**临时**渲染，
  与笔记持久化高亮是两套机制，本 REQ 仅回归守住，不改其语义。
- 选词翻译/查词/复制（REQ-003 已交付）——回归守住，不改入口语义。
- PDF 文本层高亮/批注锚定（page+rect）：当前阅读器只渲染 reflow 纯文本章节，PDF 不在本期
  （书签仍以当前 Locator 落库，PDF 分支随 PDF 渲染 REQ）。
- 章节级"当前章节内搜索"：归入"当前书籍"范围 + 结果跳转，不单列章节级筛选。
- 跨设备/云同步、`LocatorResolver` 的 CFI 精确锚（本期实现文本锚 + progression 降级链即可）。

### 1.3 根因 / 现状核实（逐条 Read 源码，含 file:line 证据）

> 结论：本 REQ 是**笔记与搜索两个核心能力的从零落地**（模块桩 + 表缺失 + 桥接缺失 + UI 骨架），
> 与既有 REQ 的"选词翻译/查词"（REQ-003）、"听书跟读临时高亮"（REQ-005/006）是**不同机制、
> 不同数据、不同入口**，不重复（详见 §1.4）。

| 编号 | 结论 | 证据（已逐条核对） |
|---|---|---|
| **R1** | **笔记领域服务是空壳**：`AnnotationService` 仅占位，create/update/delete/list/resolve/export 全为 TODO。 | `core/src/notes/mod.rs:1-15` |
| **R2** | **搜索领域服务是空壳**：`SearchService` 仅占位，index_book/query 全为 TODO。 | `core/src/search/mod.rs:1-11` |
| **R3** | **锚定解析器是空壳**：`LocatorResolver` 的 `from_selection/resolve/text_at` 全为 TODO（笔记锚点依赖它）。 | `core/src/locator/mod.rs:1-13` |
| **R4** | **笔记值对象未定义**：`TextSelection` / `NoteKind` 等仍是 TODO 注释。 | `core/src/types.rs:179-180` |
| **R5** | **选词动作占位**：`_onSelectionAction` 对 `highlight`/`note` 直接 `break`，仅 translate/lookup/copy 生效。 | `app/lib/pages/reader_page.dart:623-636`（占位在 `:631-634`） |
| **R6** | **两个页面是骨架**：`NotesPage`、`SearchPage` 各 14 行，仅 Scaffold + 占位文案。 | `app/lib/pages/notes_page.dart:1-14`、`app/lib/pages/search_page.dart:1-14` |
| **R7** | **表未建、迁移停在 v3**：`migrate_conn` 只建到 v3（translation_cache/settings），**无 `annotations`、无 `fts_books`**，`user_version=3`。 | `core/src/store/mod.rs:252-319`（v3 在 `:294-318`） |
| **R8** | **桥接缺失**：`api.rs` 只有书库/进度/词典/翻译/听书桥接，**无 notes_*/search 函数、无相关 DTO**。 | `core/src/api.rs:1-532`（imports `:12-18` 无 notes/search；TTS 段止于 `:526`） |
| **R9** | **书签仅会话内**：`_bookmarked` 只有 `setState` 切换图标，无持久化、无书签列表。 | `app/lib/pages/reader_page.dart:113`、`:724` |
| **R10** | **工具条缺"划线"**：现有动作是 划重点/笔记(带 4 色点)/翻译/查词/复制；NOTE-02 的"划线"无入口；线框 06 要求 复制/高亮(4 色)/划线/批注/翻译。 | `app/lib/widgets/selection_toolbar.dart:26-31`、`:55`（色点） |
| **R11** | **章节正文是单个 `Text`**：`ChapterSection` 用 `Text(chapter.text)` 整体渲染，无法内联多色 span；持久化高亮/临时高亮都需改造为 `Text.rich`/`RichText` 分段。 | `app/lib/pages/continuous_scroll_policy.dart:188-228`（正文 `:216-224`） |
| **R12** | **选区只拿到纯文本、无字符偏移**：滚动模式 `SelectionArea.onSelectionChanged` → `SelectedContent.plainText`；`SelectedContent` 本身无 start/end（`SelectedContentRange` 只能经 `SelectionHandler.getSelection` 获取，未接入）。生成 `TextAnchor{start,end}` 需要偏移 → 需锚点解析策略。 | `app/lib/pages/reader_page.dart:540`（`_sliceSelection`）、`:799`（`onSelectionChanged`）；Flutter SDK `packages/flutter/lib/src/rendering/selection.dart:200-214`（`SelectedContent` 仅 `plainText`）、`:125-194`（`SelectedContentRange` 另取） |
| **R13** | **章节身份未暴露到 Flutter**：桥接 `ChapterView` 只有 title/text，Dart `ChapterData` 同样无 `href`；搜索命中/笔记锚点需要章节 `href`。 | `core/src/api.rs:31-42`、`:213-219`；`app/lib/services/library_backend.dart:25-30` |
| **R14** | **导入不建索引**：`LibraryService::import_file` 只做解析→规范化→入库，无 FTS 索引调用；`SearchService` 无任何调用点。 | `core/src/library/mod.rs:32-60`；`grep` 全仓 `search::/index_book` 仅命中 stub 自身 |
| **R15** | **FTS5 已在 bundled SQLite 中编译**：`rusqlite` 用 `bundled`，libsqlite3-sys 构建脚本无条件开启 `-DSQLITE_ENABLE_FTS5`。但 `unicode61` 对 CJK 只按整段连续汉字成 token，2 字中文词查不到（见 §5 风险1 实测）。 | `core/Cargo.toml:18`；`~/.cargo/registry/src/*/libsqlite3-sys-0.38.2/build.rs:159`；SQLite 3.53.1 实测 |
| **R16** | **导出路径无通道**：`notes_export` 桥接不存在，UI 无保存对话框/路径选择；桌面与移动端路径策略未定义。 | `core/src/notes/mod.rs:14`、`app/lib/pages/reader_page.dart:468`（导出占位） |

### 1.4 与既有 REQ 无重复的证明（逐条 file:line 证据）

| 既有能力 | 证据 | 与 REQ-009 的边界 |
|---|---|---|
| REQ-003 选词工具条（翻译/查词/复制） | `reader_page.dart:625-630`（translate/lookup/copy 已实现）、`selection_toolbar.dart:28-30`、REQ-003 `01-req.md:96-103`（US-15/16） | 同一工具条，但**动作正交**：REQ-003 消费选中纯文本做查/译；本 REQ 新增高亮/划线/批注的**持久化写入**。`_onSelectionAction` 的 `highlight/note` 分支是占位（`reader_page.dart:631-634`），REQ-003 明确"完整选区机制归笔记 REQ"（REQ-003 `02-design.md:393-395`）。 |
| REQ-005/006 听书跟读高亮 | `listen_follow_highlight.dart:1-9`、`:186-190`（`RichText` 背景色 `0x401A73E8`，由 `charStart/charEnd` 切片）；REQ-005 `01-req.md:202-207`（US-17） | **临时 vs 持久**：跟读高亮是听书运行态、单色、由 TTS 句事件驱动、不入库；本 REQ 高亮是用户创建的**多色持久化笔记**（`annotations` 表 + Locator 锚点），二者数据源与生命周期不同，本 REQ 仅回归守住。 |
| REQ-003 翻译缓存 | `core/src/store/mod.rs:294-318`（`translation_cache`）、`core/src/types.rs:162-168`（`TranslationCacheRepository`） | 数据与领域无关；本 REQ 新增 `annotations`/`fts_books`，不触碰翻译缓存 schema 与行为。 |
| REQ-008 连续滚动 | `continuous_scroll_policy.dart:188-228`、REQ-008 `01-req.md:37-40`（明确"笔记/高亮 NOTE 系列、全文搜索另立 REQ"） | REQ-008 明确把笔记/搜索划出；本 REQ 在其连续流渲染基础上增加**笔记 span 渲染 + 跳回定位**，不改滚动/进度语义。 |
| REQ-003 `TextSelection` 归属声明 | REQ-003 `02-design.md:393-395`（`TextSelection` 归笔记 REQ） | 本 REQ 正是定义 `TextSelection`/`NoteKind`/`Annotation` 的 REQ，无冲突。 |

> 结论：**不重复**。REQ-005/006 的高亮是 TTS 跟读临时渲染；REQ-003 是翻译/查词；REQ-008 是滚动编排；
> 本 REQ 首次引入**持久化用户笔记（NOTE 系列）**与**全文搜索（READ-06）**两套新数据与领域服务。

### 1.5 原型权威性与 UI 映射（`docs/wireframes/**` 为 UI 权威规范）

| 屏 / 交互 | 原型图 | 本 REQ 涉及 | 布局约束 |
|---|---|---|---|
| 文本选择与浮动工具条 | `docs/wireframes/06-selection-toolbar.svg` | 工具条含**复制 / 高亮（4 色）/ 划线 / 批注 / 翻译**；随选区定位、不遮挡正文；长按/双击选中；拖动两端手柄调整 | 以 06 为准；既有"查词"入口（REQ-003）保留 |
| 笔记面板 | `docs/wireframes/07-annotation-panel.svg` | 右侧 360px 面板；标题"笔记" + ✕；搜索框"搜索笔记"；章节分组 + 色标 + 原文片段 + 批注 + 时间；点击条目跳回原文并临时高亮；底部"导出 / 全部删除"；编辑批注卡片（保存/删除）；打开时主体调暗、点外部关闭 | 以 07 为准 |
| 全文搜索 | `docs/wireframes/04-search.svg` | 顶部搜索框 + "全文搜索"按钮；结果行=书名 + "第 N 章 · 章节名" + 上下文（关键词蓝色加粗）+ "定位"按钮；右侧筛选面板=按范围（全部书籍/当前书籍）+ 按格式（EPUB/PDF/MOBI 复选）+ 结果数与耗时；点击定位跳转并高亮关键词 | 以 04 为准 |
| 阅读器底栏书签入口 | `docs/wireframes/reader-ui-v2/02-menus.svg:31-32` | 底栏 🔖 书签按钮（NOTE-06） | 复用既有底栏，零布局改版 |
| 阅读器顶栏搜索/笔记入口 | `docs/wireframes/05-reader.svg:15`（⌕ 搜索）、`reader_page.dart:467-468`（⋯更多：笔记/导出） | 搜索/笔记/导出的**入口可达**（顶栏或"更多"菜单） | 入口位置由架构在 02-design 定，不新增视觉样式 |

> 结论：本 REQ **新增**笔记面板与搜索页两个屏（07/04），并**扩展**选词工具条（06）；
> 实现阶段禁止对线框布局自由发挥（闸门3/5a 逐屏核对，deviation=0）。

---

## 2. 用户故事与验收标准（Given/When/Then，必须可测；标注验证层级/原型图）

> **验证层级标注**：`[集成测试]` = 真实 `ReaderPage`/`SearchPage`/真实面板 + 真实手势，跑在
> `app/integration_test/*.dart`（注入 fake 笔记/搜索 backend，**不构造**合成页；静态守卫见
> `app/test/no_synthetic_chrome_test.dart:8-27`）；`[widget 测试]` = `app/test/*.dart` 注入 fake；
> `[单测]` = 纯函数/服务出口（Rust `cargo test` 或 Dart 纯逻辑）；`[真机]` = Android 真机人工清单。
> **选区触发范式**：真实长按正文（`reader_selection_test.dart:36` 的 `tester.longPress`），再点真实工具条。

### 故事 1：创建笔记（选中 → 高亮/划线/批注）—— 作为小林，我想要标记重点并持久保存

- **US-1 选中文字多色高亮并持久化（NOTE-01，P0，[集成测试][单测]，线框 06/07）**
  - Given 真实 `ReaderPage`（滚动模式）+ 注入 fake 笔记 backend，正文含可选中文字
  - When 真实 `longPress` 选中文字 → 工具条出现 → 点"高亮"并选 4 色之一（黄/蓝/绿/粉，见
    `selection_toolbar.dart:55` 与线框 06 的四色点）→ 确认
  - Then 调用笔记创建出口，落库一条 `kind=highlight`、`color` 等于所选色、`snippet` 为选中原文、
    `locator_json` 可解析（`book_id/href/progression∈[0,1]/text.snippet` 非空）的 `Annotation`；
    页面上该文字以所选色**高亮渲染**（可断言存在带该背景色的 span 且其文本 == `snippet`）
  - Given 同一段文字 When 依次用另一种颜色创建高亮 Then 两条 `Annotation` 均存在，渲染层两段颜色
    可区分（叠加/分段均可，不丢任一条）
  - Given 重启（重建 `ReaderPage` 并重新 `notes_list`）When 打开该书 Then 已落库高亮按锚点重新渲染
- **US-2 划线（NOTE-02，P0，[集成测试]，线框 06）**
  - Given 选中文字 When 点工具条"划线" Then 落库 `kind=underline`；渲染为**装饰线**（
    `TextDecoration.underline` 或等价）而非背景填充；其余（锚点/持久化/重定位）行为同 US-1
  - Given 已存在高亮 When 对同一段划线 Then 高亮与划线两条记录并存，互不覆盖
- **US-3 批注（NOTE-03，P0，[集成测试]，线框 06/07）**
  - Given 选中文字 When 点"批注" → 输入框出现 → 输入文本并保存 Then 落库 `kind=note`、
    `note_text` 为输入内容、锚点与片段同 US-1；面板可见该批注（US-6）
  - Given 已存在高亮 When 对其追加批注 Then 允许以同一锚点新增 `kind=note`（或经架构定义的关联），
    高亮与批注可同时检索到
  - Given 输入为空 When 保存 Then 不落库（或按架构定义为无批注的高亮），不产生空 `note_text` 记录；
    给出可观察提示
- **US-4 换字号/换主题/重新分页后锚点重定位不丢失（NOTE-01/02/03，P0，[集成测试][单测]）**
  - Given 已创建高亮/划线/批注 When 经 Aa 面板切换字号（如 18→28）/主题（浅色→深色）/行距后重排
    Then 各笔记仍按**文本锚点**定位到同一段原文（断言带色 span 的文本 == `snippet`），不丢失、不漂移到相邻段
  - Given 锚点文本在重排后无法精确匹配 When 解析 Then 走 `progression` 降级并在 UI 标记"位置可能不精确"
    （不静默丢失；领域规则见 docs/04 §3/§8）
  - Given 同一 `snippet` 在章内出现多次 When 创建笔记 Then 锚点必须消歧（结合当前 `progression`/偏移），
    重开后仍落在创建时的那一处
- **US-5 同段叠加多色高亮与批注（NOTE-01/03，P0，[单测][集成测试]）**
  - Given 章文本、两条部分重叠的选中区间与一条批注 When 全部创建 Then `notes_list` 返回 3 条记录，
    各自 `locator.text.start/end` 正确；渲染层能同时呈现重叠区域（后创建者可见/分段着色，不崩溃）

### 故事 2：笔记面板与跳转 —— 作为陈老师，我想要浏览全书笔记并回到原文

- **US-6 面板按章节分组展示（NOTE-04，P0，[widget 测试][集成测试]，线框 07）**
  - Given 该书含 2 章、共 5 条笔记 When 打开笔记面板 Then 面板按章节分组（组头显示章节名，如"第一章"），
    每组内每条含：**色标**（左竖条颜色 == `color`）+ **原文片段** + **批注**（无批注则仅片段）+ **时间**
    （线框 07 的 `01-12` 样式，格式可断言）；组与条目顺序稳定（按 `updated_at` 或创建顺序，架构定）
  - Given 无任何笔记 When 打开面板 Then 显示空态提示（如"暂无笔记"），不崩溃
- **US-7 面板内搜索笔记（NOTE-04，P0，[widget 测试]，线框 07）**
  - Given 面板有多条笔记 When 在"搜索笔记"框输入命中片段/批注的关键词 Then 列表仅保留匹配条目
    （大小写/空白归一按架构定义）；清空关键词 Then 恢复全部
  - Given 关键词无命中 Then 显示"无匹配"空态（可断言文案），不崩溃
- **US-8 点击条目跳回原文并临时高亮（NOTE-04，P0，[集成测试]，线框 07）**
  - Given 笔记面板已打开且含一条位于第二章的笔记 When 点击该条目 Then 面板关闭（或保留，按架构），
    阅读器定位到该笔记 `Locator`（目标章正文可见、滚动偏移落在该章区间内），且出现**临时高亮**
    （可断言：存在已知 key/组件的临时高亮覆盖 `snippet`，且其颜色区别于持久化高亮，如线框 07 的蓝色）
  - Given 临时高亮显示后 When 等待超时/再次滚动或点击 Then 临时高亮消失，持久化高亮仍在
  - Given 点击条目 When 跳转完成 Then `reading_progress` 被更新为跳转位置（复用既有定位/落盘路径），
    听读同进度不变
- **US-9 面板打开/关闭与点外部关闭（NOTE-04，P0，[widget 测试]，线框 07）**
  - Given 阅读器 When 通过入口打开笔记面板 Then 面板可见（标题"笔记"+搜索框+列表+底部"导出/全部删除"）
  - Given 面板打开 When 点击面板外空白区域 Then 面板关闭（阅读器主体恢复正常）
  - Given 面板打开 When 点 ✕ Then 面板关闭；桌面端快捷键（`N`）归 SET-02，本 REQ 不要求
- **US-10 真实集成测试：选词→高亮→面板显示→跳回原文（NOTE-01/04，P0，[集成测试]）**
  - Given 新增 `app/integration_test/notes_search_integration_test.dart`，全程真实 `ReaderPage` +
    真实 `longPress`/点击 + 真实面板 widget；文件内**不出现**合成
    `ReaderTopBar(`/`ReaderBottomBar(`（`no_synthetic_chrome_test.dart` 守卫）
  - When 选中第二章一段文字 → 点"高亮"选色 → 打开笔记面板 → 断言面板出现该条（色标+片段）→
    点该条 → 断言阅读器跳回第二章该位置且出现临时高亮
  - Then 全程 `tester.takeException() == null`；运行 `flutter test integration_test -d linux`（xvfb）通过；
    覆盖 US-1/US-6/US-8

### 故事 3：笔记整理与书签 —— 作为小林，我想要编辑/删除/改色并收藏位置

- **US-11 编辑批注 / 改色（NOTE-05，P0，[widget 测试][集成测试]，线框 07）**
  - Given 面板中一条批注 When 打开编辑卡片 → 修改文本 → 保存 Then `notes_update` 落库，
    面板与原文锚点展示更新后的批注（`updated_at` 增大）
  - Given 面板中一条高亮 When 改色 Then 落库 `color` 更新，面板色标与原文高亮颜色同步变化
  - Given 编辑卡片 When 点"删除" Then 进入 US-12 的二次确认流程
- **US-12 删除 + 二次确认 + 锚点清理（NOTE-05，P0，[单测][集成测试]，线框 07）**
  - Given 一条笔记 When 触发删除 Then **先弹二次确认**（文案含"删除"/"确认"，可断言）；
    取消则记录与界面高亮均保留
  - Given 确认删除 Then 该 `annotations` 行被删除（`notes_list` 不再返回）、其 `locator_json` 一并清除、
    **原文对应高亮/划线/批注标记消失**（不残留孤儿高亮）；再次打开面板该条不再出现
  - Given 删除不存在的 id When 调用 Then 返回可读错误或幂等成功（架构定），不崩溃
- **US-13 面板内多选批量删除（NOTE-05，P0，[widget 测试]，线框 07）**
  - Given 面板中 N 条笔记 When 进入多选、勾选 M 条 → 点"删除选中" Then 弹二次确认，确认后
    `notes_list` 减少 M 条，未选中的保持不变，原文对应标记同步清理
  - Given 未勾选任何条目 When 点"删除选中" Then 按钮禁用或提示"请选择"（可断言），不误删
  - Given 底部"全部删除" When 点击 Then 二次确认后清空该书全部笔记（`notes_list` 为空），
    阅读器原文无任何残留标记
- **US-14 书签当前页 + 书签列表跳转（NOTE-06，P1，[集成测试][单测]，线框 02-menus/07）**
  - Given 阅读到某章某位置 When 点底栏 🔖 书签 Then 落库一条 `kind=bookmark`、`locator_json` 为当前
    Locator；图标变为已收藏态；再次点击取消（幂等切换，删除对应记录）
  - Given 已有书签 When 打开书签列表（与笔记面板并列或并入，架构定）Then 列出该书书签（位置/时间）；
    点击某条 Then 跳转到该位置（同 US-8 定位语义）
  - Given 重启应用 When 重新打开该书 Then 已落库书签仍在、图标状态正确
- **US-15 删书级联清笔记 / 保留笔记选项（NOTE-05，P1，[单测]）**
  - Given 书 A 有笔记 When `library_remove(A)` Then 因 `annotations.book_id` 外键 `ON DELETE CASCADE`
    且主连接 `PRAGMA foreign_keys=ON`（`store/mod.rs:54`），该书笔记与书签全部删除；`fts_books` 中该书行删除
  - Given 未来"保留笔记"选项（LIB-04）When 选择保留 Then 须先导出再删（本 REQ 只需保证默认级联语义可测）

### 故事 4：导出 —— 作为老周，我想要把笔记导出到其他工具

- **US-16 导出 Markdown/JSON 字段完整（NOTE-07，P1，[单测][集成测试]，线框 07）**
  - Given 书含笔记 When 调用 `notes_export(book_id, Markdown, out)` Then 产出文件内容包含：书名、
    每个笔记的章节名、锚点信息、原文片段、批注（若有）、时间；Markdown 可解析、特殊字符/换行被转义
  - When 调用 `notes_export(book_id, Json, out)` Then 产出合法 JSON，可反序列化，字段与 Markdown
    内容一致（书/章/锚点/snippet/note_text/时间）
  - Given 导出过程 When 运行 Then UI 不阻塞（导出经 async 桥接；可断言导出期间页面仍可交互/显示进度态）
- **US-17 空笔记提示 + 导出路径（桌面保存框 / 移动端）（NOTE-07，P1，[widget 测试][真机]，线框 07）**
  - Given 该书无笔记 When 点"导出" Then 给出空笔记提示（可断言文案含"暂无笔记"），不产生文件、不崩溃
  - Given 有笔记 When 桌面端点"导出" Then 弹出保存对话框；用户取消则**不写文件**且无错误提示
  - Given 移动端 When 导出 Then 写入应用文档目录（`path_provider`）并可观察/分享导出路径；
    路径策略由架构在 02-design 定义（保存框 vs 应用目录/分享）

### 故事 5：全文搜索 —— 作为老周，我想要在书里快速定位内容

- **US-18 搜索返回结果列表（关键词高亮 + 章节名 + 上下文）（READ-06，P1，[单测][集成测试]，线框 04）**
  - Given 已索引书 B，正文含"看不见的城市，卡尔维诺写道" When `search("卡尔维诺", scope=全部书籍)`
    Then 返回 ≥1 条 `SearchHit`，每条含 `book_id`、书名、章节名、上下文片段、命中区间；
    结果行按线框 04 渲染：书名（粗）+ "第 N 章 · 章节名" + 上下文，且关键词以**不同样式**
    （蓝色加粗，可断言 span 颜色/字重）标出；显示命中数与耗时
  - Given 搜索 2 字中文词（如"城市"）且原文包含该词 When 搜索 Then 返回 ≥1 条命中
    （**强制项**：`tokenize='unicode61'` 默认对 CJK 整段成 token，2 字词查不到，见 §5 风险1；
    架构必须给出满足此断言的索引/分词方案）
  - Given 搜索无命中 When 搜索 Then 显示空态（"未找到…"，可断言），不崩溃
  - Given 输入为空/纯空白 When 搜索 Then 不发起查询或提示"请输入关键词"，不崩溃
- **US-19 点击定位跳转 + 原文关键词高亮（READ-06，P1，[集成测试]，线框 04）**
  - Given 搜索结果列表 When 点击某条"定位" Then 阅读器打开/定位到该命中的书、章节与位置
    （滚动偏移落在该章区间；`reading_progress` 更新为命中位置）
  - Given 定位完成 Then 原文命中关键词出现**临时高亮**（可断言命中文本被高亮 span 覆盖）；
    与持久化笔记高亮可区分
  - Given 跨书命中（scope=全部书籍）When 定位 Then 正确打开对应书并定位（不误开当前书）
- **US-20 范围筛选（全部书籍/当前书籍）+ 按格式筛选（READ-06，P1，[单测][widget 测试][集成测试]，线框 04）**
  - Given 书库有 2 本书、关键词在两本书中都出现 When scope=当前书籍 Then 结果只含当前书；
    scope=全部书籍 Then 含两本书
  - Given scope=全部书籍 When 在筛选面板勾选格式（EPUB/MOBI 等，线框 04 复选）Then 结果只含所选格式的书；
    取消勾选恢复；筛选状态在本次搜索会话内保持
  - Given 结果数/耗时 When 展示 Then 文案含命中条数与耗时（线框 04 "结果 42 条 · 0.08s"）
- **US-21 搜索性能 / CJK / 特殊字符（READ-06，P1，[单测][真机]，线框 04）**
  - Given 已建索引的语料 When 执行常见关键词查询 Then 查询耗时 < 100ms（docs/02 §6 / docs/05 §4；
    CI 宽松门槛由架构在 02-adr 定义并写入验收）
  - Given 含 `%`、`_`、引号、`*`、`NEAR`、空串等特殊输入 When 搜索 Then 不抛异常/不崩溃
    （转义为 FTS 查询语法安全形式），返回结果或空态
  - Given 索引构建 When 导入一本新书 Then 该书章节被写入 `fts_books`，立即可被搜索到（US-23 回填）
- **US-22 真实集成测试：搜索→结果→跳转（READ-06，P1，[集成测试]）**
  - Given 新增集成用例（可与 US-10 同文件）：真实 `SearchPage` + 真实 `ReaderPage` + 真实点击/导航，
    注入 fake 搜索 backend（生产为 Rust）；**不构造**合成页
  - When 在真实搜索页输入关键词 → 点"全文搜索" → 结果列表出现 → 点"定位"
  - Then 跳转到真实 `ReaderPage` 命中位置并出现关键词临时高亮；`tester.takeException() == null`；
    运行 `flutter test integration_test -d linux`（xvfb）通过；覆盖 US-18/US-19/US-20

### 故事 6：数据与交付 —— 作为发布者，我想要迁移安全、真机可验收

- **US-23 v4 迁移（annotations + fts_books）幂等/向前兼容/旧书回填（NOTE/READ，P0，[单测]）**
  - Given 一个 `user_version=3` 的既有库（含 books/reading_progress/translation_cache/settings）
    When 打开 Then 迁移到 `user_version=4`，创建 `annotations`（列与 docs/04 §5:155-167 一致）+
    `idx_annot_book` + `fts_books`（`fts5(book_id UNINDEXED, chapter, text, tokenize=...)`）；
    既有数据零丢失；重复打开幂等（再次迁移为 no-op）
  - Given 迁移后既有书籍 When 首次搜索 Then 旧书内容已回填索引可被搜到（回填时机/触发由架构定）
  - Given `Store` 主连接与 `TranslationRepo` 第二连接共享 `migrate_conn`（`store/mod.rs:56`、
    `store/translation.rs:34`）When 任一先打开 Then 迁移行为一致、不重复建表报错
- **US-24 Android 真机验收清单（P0，[真机]）**
  - Given `bash scripts/build-android-local.sh` 产出的 APK 安装于 Android 真机
  - Then 人工逐项通过：① 长按选中 → 高亮（换 4 色）/划线/批注各创建成功并重开仍在；
    ② 笔记面板按章节列出、点条目跳回原文并临时高亮；③ 编辑/改色/单条删除/多选批量删除（含二次确认）
    后原文标记同步消失；④ 书签当前页、重开仍在、列表跳转；⑤ 导出 Markdown/JSON（移动端路径可观察）；
    ⑥ 全文搜索出结果、关键词高亮、定位跳转正确；⑦ 换字号/主题后高亮不丢；
    ⑧ 既有选词翻译/查词/复制、听书跟读高亮、连续滚动、进度恢复零回退

---

## 3. 影响面分析（必须非空）

### 3.1 既有功能（Flutter / interface 层）

- **`app/lib/pages/reader_page.dart`（核心，必改）**：
  - `_onSelectionAction`（`:623-636`）：`highlight`/`note` 由占位改为真实创建流程（高亮选色、划线、
    批注输入），保留 `translate`/`lookup`/`copy` 分支语义不变（`:625-630`）。
  - `_onSelectedText`/`_sliceSelection`（`:522-540`）：当前仅取 `SelectedContent.plainText`；需扩展为
    携带章节 `href` + 选中文本 + 当前 `progression`，交由锚点解析生成 `Locator`（R12）。
  - `build` 的正文 Stack（`:655-731`）：需渲染**持久化高亮/划线 span** 与**临时高亮**（US-8/US-19）；
    工具条与结果卡片层（`:690-705`）复用，增加选色器/批注输入。
  - `_openMore`（`:455-473`）：`笔记`/`导出` 两个 `ListTile`（`:467-468`）由占位改为打开笔记面板/导出；
    可增加搜索入口（线框 05 顶栏 ⌕ 搜索）。
  - 书签：`_bookmarked`（`:113`）与 `onBookmark`（`:724`）由会话内改为持久化 + 书签列表（US-14）。
  - 当前位置取值：`_chapterIndex`/`_chapterProgress`（`:102-114`）+ `_hrefForIndex`（`:909-910`）
    作为书签/笔记跳转的 Locator 来源；跳转复用 `_changeChapter`/`_scrollToChapter`（`:272-340`），
    保证 `reading_progress` 一致性（US-8/US-19）。
- **`app/lib/widgets/selection_toolbar.dart`（必改）**：`:26-31` 增补"划线"入口与四色选色交互
  （线框 06）；现有"划重点/笔记/翻译/查词/复制"文案/顺序若调整，须同步 `reader_selection_test.dart:40-44`
  的断言（US-1/2/3）。
- **`app/lib/pages/notes_page.dart`（14 行骨架 → 真实面板）**：实现线框 07 的章节分组列表、搜索框、
  底部导出/全部删除、编辑批注卡片、空态（US-6/7/9/11/13）。
- **`app/lib/pages/search_page.dart`（14 行骨架 → 真实搜索页）**：搜索框 + 结果列表 + 筛选面板 +
  空态 + 定位（US-18/19/20）。
- **`app/lib/pages/continuous_scroll_policy.dart`（必改）**：`ChapterSection`（`:188-228`）正文由
  单个 `Text` 改为 `Text.rich`/`RichText`，按锚点区间分段着色（R11；US-1/2/4）。
- **`app/lib/widgets/reader_chrome.dart`（预期小改）**：底栏书签入口复用（`02-menus.svg:31-32`）；
  顶栏是否新增搜索图标由架构定，不得改版布局。
- **`app/lib/services/`（新增）**：按 `library_backend.dart` 模式新增 `notes_backend.dart` /
  `search_backend.dart`（DTO + 抽象）+ Rust 实现（如 `rust_notes_backend.dart`/`rust_search_backend.dart`）；
  `library_backend.dart` 的 `ChapterData`（`:25-30`）需补 `href`（R13）。页面禁止直接 import
  `package:reader_app/src/rust/`（ddd-rules.toml `interface.forbid_imports`）。
- **`app/lib/pages/library_page.dart`（小改）**：打开 `ReaderPage` 时注入笔记/搜索后端（`:131-143`）；
  可选：书架搜索入口。

### 3.2 数据模型 / 迁移（v4：`annotations` + `fts_books`）

- **`core/src/store/mod.rs` `migrate_conn`（`:252-319`，必改）**：新增 `if version < 4`，建
  `annotations`（id/book_id/kind/color/locator_json/snippet/note_text/created_at/updated_at/sync_status
  + `idx_annot_book`，逐列对齐 docs/04 §5:155-167）与 `fts_books`
  （`fts5(book_id UNINDEXED, chapter, text, tokenize='unicode61')`，docs/04 §5:198-202），
  `PRAGMA user_version = 4`。Store 主连接（`:56`）与 TranslationRepo 第二连接（`translation.rs:34`）
  共享该迁移，必须幂等（US-23）。
- **外键级联**：`annotations.book_id REFERENCES books(id) ON DELETE CASCADE`；主连接已
  `PRAGMA foreign_keys=ON`（`store/mod.rs:54`），删书级联清笔记（US-15）。注意
  `TranslationRepo::open` 只设 WAL+busy_timeout（`translation.rs:32`），若笔记走独立第二连接，
  需在架构中明确级联/事务边界。
- **新增仓储（infrastructure，遵循 `store/translation.rs` 模式）**：`store/annotations.rs`
  实现 `AnnotationRepository` 契约、`store/search_index.rs` 实现 `SearchIndexRepository` 契约
  （契约放 `core/src/types.rs`）。原因：ddd-rules.toml 规定 domain 层（`core/src/notes`、
  `core/src/search`）**禁依赖 `crate::store`**（`forbid_internal`），必须经 trait 注入
  （与 REQ-003 `TranslationCacheRepository` 同法，`types.rs:162-168`）。
- **`fts_books` DDL 的 href 缺口**：DDL 只有 `book_id/chapter/text`，无 `href`；而搜索定位需要
  `Locator.href`。架构必须定义映射（如 `chapter` 列存 `href`、或建立 href↔章节映射、或结果经
  书库章节列表按名解析），并在 02-design 写明；US-18/US-19 以"可定位到命中位置"为硬断言。
- **旧书回填**：v4 迁移前已入库的书没有 FTS 行（`library/mod.rs:32-60` 导入不索引，R14）。
  架构需定义回填时机（迁移时/首次搜索/打开书时）并有界；US-23 验收。

### 3.3 领域 / 桥接接口

- **`core/src/types.rs`（共享内核，必改）**：新增 `TextSelection`（章 + 片段 + 偏移）、
  `NoteKind{highlight,underline,note,bookmark}`、`Annotation`、`NotePatch`、`ExportFormat`、
  `ExportSummary`、`NoteGroup`/`GroupBy`、`SearchHit`、`SearchScope`（范围 + 格式集合）及
  `AnnotationRepository`/`SearchIndexRepository` 契约（`types.rs:179-180` 的 TODO）。
- **`core/src/locator/mod.rs`（必改）**：实现 `from_selection`（生成文本锚，含偏移消歧）与
  `text_at`（导出/面板取原文）；`resolve` 的降级链至少覆盖文本锚→progression（docs/04 §3）。
- **`core/src/notes/mod.rs`（必改）**：实现 `create/update/delete/list/resolve/export`
  （docs/04 §7:248-255），含级联清理、LWW 更新、导出编排。
- **`core/src/search/mod.rs`（必改）**：实现 `index_book`（导入/打开时调用）与 `query`（范围过滤
  + 结果片段），docs/04 §7:280-284。
- **`core/src/api.rs`（必改）**：新增桥接 DTO（`TextSelectionView`/`NoteView`/`NoteGroupView`/
  `SearchHitView` 等）与 async 函数 `notes_create/notes_update/notes_delete/notes_list/notes_resolve/
  notes_export`、`search`（契约 docs/03 §4:122-145）；`library_open` 装配笔记/搜索仓储单例
  （沿用 DICT/TRANSLATION 双单例模式，`api.rs:155-183`）。
- **FRB 再生成**：`flutter_rust_bridge_codegen generate --rust-input crate::api --rust-root core/
  --dart-output app/lib/src/rust/`（`bridge/README.md:17-19`）→ 更新 `core/src/frb_generated.rs` +
  `app/lib/src/rust/**`；**禁止手改生成物**。
- **导入侧索引**：`LibraryService::import_file`（`library/mod.rs:32-60`）或 `api.rs` 在入库后调用
  `SearchService::index_book`（R14/US-21）。

### 3.4 听读进度 / Locator 不变式（不得破坏）

- **`reading_progress` 仍是阅读/听读进度的唯一事实源**（`store/mod.rs:73-104`、
  `library/mod.rs:101-109`、`api.rs:242-255`）：笔记的 `locator_json` 存在 `annotations` 表，
  **创建/编辑/删除笔记不得写入 `reading_progress`**。
- **`Locator.progression` 恒为章内 `0.0..=1.0`**，`href` 恒为章资源路径（`types.rs:18-34`、
  docs/04 §3）。笔记锚点遵循同一模型：文本锚（`snippet/start/end`）优先，`progression` 兜底。
- **从面板/搜索跳转**应复用既有定位路径并更新 `reading_progress`（US-8/US-19），保持听读同进度；
  跳转不得把全书比例写入 `progression`。
- **听书不变式**：听书仍写 `reading_progress`（`listen_page.dart:171-230`），本 REQ 不改其逻辑；
  `locator/mod.rs` 从 stub 变为实现时，`tts::*` 的句↔Locator 语义不得改变（`api.rs:417-471`）。

### 3.5 笔记高亮 vs TTS 跟读高亮的边界

- `listen_follow_highlight.dart`（`:1-9`、`:186-190`）是听书运行态**临时**单色高亮，由
  `SentenceChunk.charStart/charEnd` 切片渲染，不入库、不参与 `annotations`；本 REQ 的笔记高亮是
  **持久化多色**记录（`annotations` 表 + Locator 锚点）。两者在渲染层可共存但数据源隔离；
  US-8/US-19 的"临时高亮"是第三种（跳转反馈），与二者均不同，需在架构中区分命名/组件。

### 3.6 回归面（非空）

- **Flutter 单测/widget**：`app/test/reader_page_test.dart`、`reader_selection_test.dart`
  （工具条文案断言 `:40-44`）、`reader_page_interaction_coverage_test.dart`、
  `reader_continuous_scroll_test.dart`、`listen_page_test.dart`、`listen_follow_highlight_test.dart`、
  `translate_reader_test.dart`、`screenshot_golden_test.dart`、`no_synthetic_chrome_test.dart`、
  `rust_bridge_test.dart`。
- **集成**：`app/integration_test/reader_continuous_scroll_test.dart`、`reader_interaction_test.dart`、
  `screenshots_test.dart`；新增 `notes_search_integration_test.dart`（US-10/US-22）。
- **core**：`cargo test --release -p reader_core`；`core/tests/integration.rs`（当前 TODO，应补
  "导入→打开→建笔记→搜索→导出"全链路，docs/05 §2.3）；`store` 迁移测试（v1→v4）。
- **静态/构建**：`flutter analyze` 0 issues；`scripts/ddd-lint`（notes/search 走 trait，勿违
  `forbid_internal`）；`bash scripts/build-android-local.sh` 出
  `dist/reader-android-arm64-vX.Y.Z.apk`；`bash scripts/ui-screenshots.sh REQ-009`；US-24 真机清单。
- **数据兼容**：既有 v3 库升级不丢数据；既有书库可被搜索（回填）；删书级联不残留孤儿笔记/索引。

---

## 4. 依赖与优先级

| 项 | 内容 | 依赖/前置 | 优先级 |
|---|---|---|---|
| v4 迁移 | `annotations` + `fts_books` + 索引 | `migrate_conn`；FK 级联 | **P0** |
| 锚点解析 | `LocatorResolver::from_selection/text_at` + 偏移获取 | R12 选区偏移策略（架构前置） | **P0** |
| 笔记领域 | `AnnotationService` CRUD/列表/导出 | `AnnotationRepository` 契约 + store 实现 | **P0** |
| 高亮/划线/批注 UI | 工具条四色/划线/批注 + 正文 span 渲染 | `ChapterSection` 改造 | **P0** |
| 笔记面板 | 章节分组 + 搜索 + 跳回临时高亮 + 编辑卡片 | 线框 07；笔记领域 | **P0** |
| 整理 | 编辑/改色/删除/多选批量删除/二次确认/锚点清理 | 笔记面板 | **P0** |
| 书签 | 当前页落库 + 列表跳转 | `kind=bookmark` + Locator | **P1** |
| 导出 | Markdown/JSON + 保存路径 + 空笔记提示 | `notes_export` + 路径策略 | **P1** |
| 搜索索引 | 导入/打开建索引 + 旧书回填 | `SearchService::index_book` | **P1** |
| 搜索查询/UI | 结果列表/关键词高亮/定位/范围+格式筛选 | 线框 04；`SearchHit` | **P1** |
| CJK/分词 | 2 字中文词可搜（US-18 强制项） | **架构决策**（见风险1） | **P1（架构前置）** |
| FRB 桥接 | notes_*/search + DTO + codegen | `bridge/README.md:17-19` | **P0** |
| 真实集成测试 | 选词→高亮→面板→跳回；搜索→结果→跳转 | `integration_test/` + fake backend | **P0** |
| 真机验收 | Android 清单（US-24） | `build-android-local.sh` | **P0** |

- **与既有 REQ 关系（复用不重做）**：REQ-003 提供选词工具条与翻译/查词入口（复用，动作正交）；
  REQ-005/006 提供听书跟读临时高亮（回归，不合并数据）；REQ-008 提供连续滚动章节渲染与
  `_changeChapter/_scrollToChapter` 定位（复用，扩展 span 渲染）；REQ-001 提供 `reading_progress`
  契约（复用，零变更）。
- **优先级说明**：笔记全套（NOTE-01~07）为 P0（产品"能记笔记"）；全文搜索 READ-06 为 P1 但
  用户列为第一优先级，**本期必做**；书签（NOTE-06）与导出（NOTE-07）按 docs/01 为 P1，本期同样交付。

---

## 5. 风险

1. **CJK 分词 / FTS5 查询（高）**：`fts_books` DDL 用 `tokenize='unicode61'`；实测（SQLite 3.53.1）
   对"看不见的城市，卡尔维诺写道：城市是记忆的。"，`unicode61` 查 `城市`/`卡尔维诺`/`记忆` **均无命中**，
   仅整段连续汉字 `看不见的城市` 命中；`trigram` 分词器对 <3 字查询（`城市`/`城`）也无命中。
   → 2 字中文词搜索是本 REQ 硬需求（US-18 强制项）。缓解：架构在 02-adr 明确分词/索引策略
   （如 CJK 逐字/二元组预处理后再入 FTS、自定义 tokenizer、或 trigram+短查询回退），
   必要时调整 docs/04 §5 的 FTS DDL（需 architect 裁定并同步文档）；US-18/US-21 以可测断言锁定。
   *（FTS5 本身已在 bundled SQLite 编译：`libsqlite3-sys-0.38.2/build.rs:159` `-DSQLITE_ENABLE_FTS5`，
   `core/Cargo.toml:18` `bundled`；rusqlite 的 `fts5` cargo feature 仅用于自定义 tokenizer API，
   若架构选自定义 tokenizer 需加该 feature。）*
2. **选区字符偏移获取（高）**：滚动模式 `SelectionArea.onSelectionChanged` 只给 `SelectedContent.plainText`
   （`reader_page.dart:540`；Flutter `selection.dart:200-214`），无 start/end；`TextAnchor` 需要偏移。
   缓解：架构定义锚点生成策略——推荐由 `LocatorResolver::from_selection` 用选中文本在章文本内匹配
   （结合当前 `progression` 消歧）得到 `start/end`；或接入 `SelectionHandler.getSelection` 取
   `SelectedContentRange`（`selection.dart:125-194`）。US-4 用重排后仍命中同段锁定正确性。
3. **多色高亮与重排锚定（高）**：正文当前是单个 `Text`（`continuous_scroll_policy.dart:216-224`），
   内联多色/重叠/划线需改 `RichText` 分段；换字号/主题/分页重排后偏移变化。缓解：以**文本锚**
   为唯一权威（docs/04 §3），渲染时按解析出的偏移分段；US-4/US-5 断言不丢/不漂移/重叠不崩溃；
   架构定义 span 合成与锚点解析公式。
4. **FRB codegen（中-高）**：仓库根无 `flutter_rust_bridge.yaml`，codegen 命令见
   `bridge/README.md:17-19`；新增多组 DTO（含 Option/嵌套结构）易出现字段错位或生成 diff。
   缓解：沿用 REQ-003/005 流程，桥接 DTO 字段与 Dart 一一对应；codegen 后检查 diff 干净并加
   FFI 往返测试（`rust_bridge_test.dart` 模式）；**勿手改生成物**。
5. **`fts_books` 无 href 列 + 旧书未索引（中-高）**：DDL 只有 `book_id/chapter/text`，搜索定位需要
   `Locator.href`；导入路径不建索引（R14）。缓解：架构定义 href↔章节映射与回填策略；US-19 以
   "定位到命中位置"、US-23 以"旧书可搜"锁定。
6. **导出路径桌面/移动差异（中）**：桌面用 `file_picker` 保存框（取消不写文件），移动端无原生保存框，
   需 `path_provider` 应用目录/分享。缓解：架构定义可注入的路径选择接口；US-17 分别以
   widget 测试（取消/空笔记）与真机清单（移动端路径可观察）覆盖。
7. **删除级联与锚点清理（中）**：`ON DELETE CASCADE` 依赖 `PRAGMA foreign_keys=ON`（主连接已设，
   `store/mod.rs:54`；第二连接未设，`translation.rs:32`）；删除笔记还须同步移除界面标记。
   缓解：US-12/US-15 断言行删除 + 无残留标记；US-23 断言迁移/连接一致性。
8. **既有测试/golden 失配（中）**：工具条文案变化（`reader_selection_test.dart:40-44`）、正文渲染
   结构变化（`screenshot_golden_test.dart`、`screenshots_test.dart`）可能失败。缓解：测试阶段显式
   更新并记录；回归全量 + 截图脚本重跑。
9. **性能与索引开销（中）**：搜索 <100ms（US-21）、导入建索引/回填不阻塞打开（US-21/23）。
   缓解：异步桥接 + 后台索引；架构定义索引批量与上限。
10. **范围蔓延（中）**：易顺手做同步（NOTE-08）、桌面快捷键（SET-02）、PDF 文本层锚定。
    缓解：§1.2 明确不做；这些仅作接口预留/回归。

---

## 6. 闸门1 自评

- [x] **验收标准全部可测（无"体验好/流畅"类不可测词）**：US-1~US-24 每条均为可断言观察项 ——
  - `[集成测试]`：真实 `longPress` 选词→工具条→高亮/划线/批注落库断言（US-1/2/3）；换字号/主题后
    带色 span 文本 == `snippet`（US-4）；重叠 span 计数（US-5）；面板条目→跳转位置 + 临时高亮组件
    （US-8）；选词→高亮→面板→跳回全流程（US-10）；书签落库/跳转（US-14）；导出内容字段（US-16）；
    搜索命中字段/关键词样式/定位临时高亮（US-18/19/20）；搜索→结果→跳转全流程（US-22）。
  - `[widget 测试]`：面板章节分组/色标/时间/空态（US-6）、面板搜索过滤（US-7）、打开/点外部关闭（US-9）、
    编辑/改色（US-11）、多选批量删除/二次确认/按钮禁用（US-13）、空笔记提示/保存取消（US-17）、
    筛选面板（US-20）。
  - `[单测]`：锚点消歧与降级（US-4）、重叠区间（US-5）、删除幂等/级联（US-12/15）、导出 Markdown/JSON
    字段与转义（US-16）、搜索范围/格式过滤/CJK/特殊字符（US-18/20/21）、v4 迁移幂等/回填（US-23）。
  - `[真机]`：搜索性能与移动端路径（US-21/17）、Android 八项清单（US-24）。
  无"体验好""流畅"等措辞；每类均给出可执行断言；每条映射到线框 06/07/04（或明确复用既有底栏/
  入口，零布局改版）。
- [x] **与既有 REQ 无重复**：§1.4 逐条给出 file:line —— REQ-003 的选词工具条只做翻译/查词/复制
  （`reader_page.dart:625-630`），高亮/笔记分支是占位（`:631-634`），且 REQ-003 明确把完整选区/笔记
  归本 REQ（`REQ-003 02-design.md:393-395`）；REQ-005/006 的跟读高亮是临时单色、不入库
  （`listen_follow_highlight.dart:186-190`、`REQ-005 01-req.md:202-207`），本 REQ 是持久化多色笔记；
  REQ-008 明确把笔记/搜索划出（`REQ-008 01-req.md:37-40`）；翻译缓存与本 REQ 无关。
- [x] **影响面清单非空**：§3 覆盖 6 类必答项 —— 既有功能（§3.1，reader_page/工具条/两个骨架页/
  连续流正文/服务层/书库页，逐 file:line）、数据模型与迁移 v4（§3.2，annotations/fts_books/外键/
  href 缺口/旧书回填）、领域与桥接（§3.3，types/locator/notes/search/api/FRB/导入索引）、
  听读进度与 Locator 不变式（§3.4，`reading_progress` 唯一事实源、章内 progression、听书不改）、
  笔记高亮 vs TTS 跟读边界（§3.5）、回归面（§3.6，Flutter/core/集成/静态/构建/数据兼容）。
  每条附具体文件、行号、表/接口与约束。
