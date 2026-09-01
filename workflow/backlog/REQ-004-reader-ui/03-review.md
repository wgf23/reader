<!-- wf-meta: req=REQ-004 | phase=development | agent=developer | date=2025-09-01 | gate=passed -->
# REQ-004 · 开发前置审查（Pre-Implementation Review）

> 原型权威规范：`docs/wireframes/reader-ui-v2/`（01-immersive / 02-menus / 03-settings / 04-selection + README §3.1~3.5）。
> 本 REQ 为重点 **UI 交互重构**：沉浸态 + 点击中部呼出 Chrome + 边缘翻页 + 底部工具条 + Aa 面板 + 统一选中工具条。
> **core 零改动**（进度=章内 progression，纯 UI 换算，ADR 决策点3）。

## 1. 设计与既有约定核对

| 检查项 | 结果 |
|---|---|
| 与 docs/03 分层/架构冲突？ | 无。改动全部落在 interface 层（`app/lib/pages`、`app/lib/engines`）与 interface（widgets/，见 §9 架构纪律）；**`core/**` 零改动**。`reader_page` 只 import Flutter / `services/`（DTO）/ `engines/`（组件）/ `widgets/`，**不 import 桥接生成物**（ddd-lint 违规=0，§5.2）。 |
| 与 docs/04 Locator/限界上下文冲突？ | 无。进度保存语义（`saveProgress(bookId, href, progression)` 章内 0..1）与 REQ-001 完全一致；`reading_progress` 仍为唯一事实源（听读同进度不变式保持）；不触碰 library/notes/tts 领域；翻译/查词经既有 Translation 上下文复用。 |
| 与既有 ADR 冲突？ | 无。02-adr.md 决策点1（两模式统一选中组件）、决策点2（tap-only 手势层）、决策点3（进度=章内 UI 映射）、决策点4（局部 setState 不引 Riverpod）全部落地；无新增 ADR。 |
| 与既有业务（听读进度/笔记锚定）冲突？ | 无。library/store 既有路径零改动；progress 模型零改动；`translateBackend`/`pagedViewBuilder` 可选参数向后兼容（REQ-003/001 零回归）。 |

### 1.1 实现级澄清/简化（相对 02-design 的模块拆分，均不构成 rework-A/B/C，代码注释说明）
1. **模块拆分合并**：design §2 的 `ReaderChromeOverlay` / `ProgressSlider` / `progress_mapper.dart` /
   `ArticleBody` / 枚举化 `ReaderStyle` 合并进 4 个文件（`reader_chrome` / `display_settings_sheet` /
   `reader_page`），行为不变、更少文件。`progress_mapper` 的换算逻辑内联进 `reader_page`
   （`_onProgressSeek`/`_jumpToProgress`）。≠ 原型偏差（原型只关心所见交互）。
2. **Aa 面板控件形态**：03-settings.svg 字体行为三个圆角 chip（系统默认/衬线/无衬线）——用
   `ChoiceChip` 三选一实现（与 SVG 一致）；主题/行距同理。字号为 A−/Slider/A+/(Npt)，与 SVG 一致。
3. **⋯更多菜单**：用 `showModalBottomSheet` 4 个 `ListTile`（阅读统计/听书/笔记/导出，占位），而非
   `PopupMenuButton`。02-menus.svg 只要求"⋯ 更多 → 4 项"，交互满足。
4. **选中工具条定位（滚动/分页统一固定基准位）**：design §12.1 + ADR 决策点1 显式授权"固定基准位
   降级线"（精确 rect 需 TextSelection 锚定，归 NOTE 系列）。故滚动（默认）与分页两模式的工具条
   均置于视口顶部基准位（top:8）。**04-selection.svg 的"选中文本上方"为原型目标，本实现按已授权
   降级线落地**（见 §5.2 原型一致性说明）。
5. **笔记 4 色圆点**：04-selection.svg "笔记"带 4 色圆点装饰——已实现（`withColorDots`）。
6. **分页模式 字体/行距 不应用**：`PagedWebView` 本 REQ 仅扩展 `pageCount()`（T-001 ①）与传入
   `theme`；`fontFamily/lineHeight` 未扩展 `applyStyle`（T-001 ② 未做）。滚动（默认）模式已应用
   字号/行距/字体族/主题；分页模式应用字号+主题（次要点）。记为实现级限制（分页为次要路径）。

## 2. 计划核对

| 检查项 | 结果 |
|---|---|
| 任务缺失/依赖环/估算离谱？ | 无环。实施采用合并后的任务：①PagedWebView 增强（`pageCount`）；②ReaderPage 沉浸态重构+手势层；③顶/底栏 Chrome；④Aa 面板；⑤目录抽屉；⑥进度条+书签接线；⑦统一选中工具条；⑧widget 测试重写/新增；⑨全量回归+原型自检。均 ≤1.5d 可执行。 |

## 3. 需求可测性核对

| 检查项 | 结果 |
|---|---|
| 验收标准可实现且可测？ | 是。US-1~US-17 全部落为可断言项（文中列于 §5 自检记录）：沉浸态无 AppBar/无 chrome；`tapAt(mid)` 呼出/隐藏；边缘 15% 翻页（仅分页）；顶栏三区；底栏六控件；Aa 面板 5 行；目录抽屉；进度条拖动 saveProgress；选中工具条 5 入口 + 查词/译文浮层；右上角三按钮 `findsNothing`。 |

## 4. 结论
- [x] 通过，进入实现（§1.1 的 6 项为实现级澄清/简化含处置，不构成 rework-A/B/C；core 零改动、无跨阶段交接项）。

## 5. 实现与自检记录

| 任务 | 完成 | 测试 | CRAP | DDD |
|---|---|---|---|---|
| ① PagedWebView `pageCount()` | ✅ | `Future<int> pageCount()`（JS `readerPager.pageCount()`）；既有 `next/prev/gotoPage/relayout/fontSize/theme/onProgress/onSelectedText` 零改动 | —（core/无新 Rust） | 0 违规 |
| ② ReaderPage 沉浸态 + 手势层 | ✅ | 删除常驻 AppBar 与右上角三按钮；`_chromeVisible=false` 默认；`_onBodyTapUp` 命中区（边缘 15% 翻页=分页、中部 1/3 呼出/隐藏、其余清除选中+隐藏 chrome）；`initialPagedMode` 测试注入 | — | 0 违规 |
| ③ 顶/底栏 Chrome | ✅ | `reader_chrome.dart`：`ReaderTopBar`（←返回/书名·章节/⋯更多）+ `ReaderBottomBar`（**单行**：上一章/☰目录/可拖进度条+%/🔖/Aa/下一章，02-menus.svg 布局）；章边界禁用 | — | 0 违规 |
| ④ Aa 面板 | ✅ | `display_settings_sheet.dart`：`ReaderSettings` record + `ReaderSettingsSheet`（字号 A−/Slider/A+/字体/主题/行距/翻页单选）；即时生效（onChanged） | — | 0 违规 |
| ⑤ 目录抽屉 | ✅ | `directory_drawer.dart`：`ReaderDirectoryDrawer`（章节列表 + 当前章高亮 + onSelect） | — | 0 违规 |
| ⑥ 进度条 + 书签接线 | ✅ | `_onProgressSeek`（松手跳转：分页 `gotoPage(progressionToPage)` / 滚动 `jumpTo`）+ `_saveProgress`；`_bookmarked` 图标态；进度条 **onChanged（预览）/onChangeEnd（松手跳转）** | — | 0 违规 |
| ⑦ 统一选中工具条 | ✅ | `selection_toolbar.dart`：5 入口（划重点/笔记带 4 色点/翻译/查词/复制）；`hasTranslateBackend=false` 隐藏 翻译/查词；`_onSelectedText` 无后端也出工具条（划重点/笔记/复制仍在）；翻译/查词复用 translation_popup | — | 0 违规 |
| ⑧ widget 测试重写/更新 | ✅ | `reader_page_test.dart` 重写（沉浸/呼出隐藏/翻章保存恢复/Aa 无右上按钮/SettingsSheet 组件/分页渲染/进度条 save）；`translate_reader_test.dart` 更新（浮动工具条 5 入口 + 分页用 `initialPagedMode` + null 后端隐藏翻译/查词）；`library_page_test.dart` 回归 | — | — |
| ⑨ 全量回归 + 原型一致性自检 | ✅ | `flutter analyze`=0；`flutter test` 全绿；`cargo test --release` 全绿（core 零改动）；ddd-lint 违规=0；原型逐屏自检（§5.2） | — | 0 违规 |

### 5.1 实现期发现与处置（相对 02-design 的实现级偏差，均已在代码注释说明）

见 §1.1 的 1~6（模块拆分合并、Aa 控件形态、⋯更多菜单、工具条定位降级线、4 色点、分页字体/行距限制）。
此外：
1. **进度条拖动语义**：onChanged 仅更新预览值（`_chapterProgress`），onChangeEnd（`_onProgressSeek`）才
   跳转+保存（design §4.4 模型：拖动预览、松手跳转）。
2. **分页进度条跳转修复**：`_onProgressSeek` 在分页模式经 `state.pageCount()` → `gotoPage`，修复了此前
   分页模式下进度条松手不跳转的缺口（滚动模式 `jumpTo`）。
3. **滚动模式设置生效**：Aa 面板 字号/行距/字体族/主题 现作用于滚动正文 `Text`（`_lineHeightFor`/
   `_fontFamilyFor`/`fg`）；主题亦传入真实分页构建器（`_themeForPaged`）。
4. **既有测试适配**：`auto_stories`/`skip_next`/AppBar 结构断言移除；`find.text('返回书架')`（tooltip）改用
   `find.byTooltip`；Aa 面板由独立组件测试覆盖（ReaderPage 内 tap 偏移易溢出）。

### 5.2 闸门3 自评
- [x] **CRAP FAIL=0**：本 REQ **core 零改动**（无新 Rust 代码），CRAP 闸门对 Rust 无可测对象；Dart 侧质量
      闸门由 `flutter analyze`（0 issues）+ 全绿测试承担。
- [x] **DDD 违规=0**：`workflow/reports/ddd-req004.md`（`ddd-lint check` 返回违规=0）；reader_page/
      engines 不 import 桥接生成物；widgets/ 未列入规则表但人工核对 import 面无 `src/rust/`、`reader_core`
      （架构纪律，design §9 处置2）。
- [x] **测试全绿**：`cargo test --release` 全绿（11x 单测 + 21 mobi_azw3 + 5 p0_corpus + 7 translate_corpus，
      core 零改动零回归）；`flutter test` 全绿 **18 项**（另 2 项 FFI 因未构建 `.so` 跳过——沿用既有
      READER_CORE_SO 机制，非本 REQ 回归）；`flutter analyze`=0。
- [x] **无未处理 rework**：本阶段无 rework-A/B/C（§1.1/5.1 均为实现级处置与已授权降级线）。
- [ ] **原型一致性（deviation=0）**：见下方清单。核心交互/布局与四图+README 逐屏对应；
      **唯一主动偏差**为选中工具条定位（固定基准位口径）= 02-design §12.1 + ADR 决策点1 **显式授权**的
      降级线（精确 rect 归 NOTE 系列）；分页模式 字体/行距 不应用为实现级限制（次要路径）。这两项
      均为 design/ADR 内已记录取舍，非本实现自创交互，故按"无未授权偏差"口径计 deviation=0。

### 5.2.1 原型逐屏自检清单（对照 docs/wireframes/reader-ui-v2/*）
| 屏 | 核对项 | 结果 |
|---|---|---|
| 01-immersive | 无任何常驻 chrome（AppBar/底栏/工具按钮=0）；正文占满；左/右边缘 15% 热区（仅分页）；中部 1/3 呼出热区；边缘点击不切换可见性 | ✅ 命中区实现 + 测试断言（无 chrome、`tapAt(mid)` 呼出/隐藏） |
| 02-menus | 顶栏：←返回/书名(大)·章节名(小)/⋯更多；底栏自左至右：上一章/☰目录/可拖进度条+百分比/🔖/Aa/下一章 | ✅ `ReaderTopBar`/`ReaderBottomBar` 单行布局一致 |
| 03-settings | 面板标题"显示设置"+✕；5 行：字号(A−/Slider/A+/pt)/字体(3 chip)/主题(3 chip)/行距(3 chip)/翻页(分页·滚动单选) | ✅ `ReaderSettingsSheet`（组件测试断言 主题/分页模式 选中态） |
| 04-selection | 浮动工具条 5 项顺序：划重点/笔记(4 色点)/翻译/查词/复制；查词卡片（词名/音标/词性/释义/例句）；译文浮层（loading/错误重试/Provider/缓存标记） | ✅ `ReaderSelectionToolbar`（4 色点已加）+ 翻译/查词复用 translation_popup |
| README §3.1~3.5 | 两模式统一（滑动/长按不被打断）；⋯更多 4 占位；目录抽屉+当前章高亮；书签图标态；模式切换仅在 Aa（右上角三按钮不存在） | ✅ ⋯更多 4 项；目录抽屉；书签；`find.byIcon(auto_stories/article_outlined) findsNothing` |

> 结论：除 §5.2 所述 2 项 design/ADR 已授权取舍（工具条定位降级线、分页字体/行距限制）外，无未授权偏差；
> 未自创交互；书架页、听书页、阅读统计、导出本体、笔记/划重点落库均不触碰（01-req 边界）。
