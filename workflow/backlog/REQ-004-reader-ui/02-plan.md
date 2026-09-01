<!-- wf-meta: req=REQ-004 | phase=architecture | agent=architect | date=2025-09-01 | gate=passed -->
# REQ-004 · 计划拆分（Task 分解：阅读器页交互重构）

## 任务清单

| Task | 内容 | 依赖 | 估算 | 验收 |
|---|---|---|---|---|
| **T-001** | **PagedWebView 引擎增强（向后兼容）**（design §2.8）：① 新增 `Future<int> pageCount()`（JS `readerPager.pageCount()`）；② JS `applyStyle` 扩展 `fontFamily`/`lineHeight` 可选参数（默认=现状）；③ JS `selectionchange` 回传增强为 `callHandler('selectedText', text, x, y, w, h)`（`getBoundingClientRect` 视口矩形），Dart handler 向后兼容解析（1 参=仅文本、≥5 参=文本+矩形 → 新可选 `onSelectionRect`）；④ 既有 `next/prev/gotoPage/relayout/fontSize/theme/onProgress/onSelectedText` 零改动；⑤ `progress_mapper.dart` 纯函数（`progressionToPage`/`offsetToProgression`/`progressionToOffset`/`percentText`/`pagePositionText`）落盘 | — | 1d | 既有 paged_web_view 相关测试与 fake 构建器**零改动通过**；新增单测：`pageCount()` 返回值、handler 1 参与 ≥5 参解析分支、矩形 clamp、progress_mapper 纯函数边界（v=0/1、pageCount=1、max=0 不除零不抛错）；`pagedViewBuilder` typedef 不变 |
| **T-002** | **ReaderPage 沉浸态重构 + 手势层**（design §5/§6，ADR 决策点2/4）：① 删除常驻 AppBar、右上角三按钮（模式切换/字号/目录）、底部两按钮行、内嵌行式选中工具条；② build 改为 5 层 Stack（ArticleBody / ReaderGestureLayer / chrome / 面板 / 浮层）；③ 命中区常量 + `_onTapUp` 裁决（边缘 15% 翻页=分页、中部 1/3 呼出、滚动边缘不拦截、其余忽略）；④ `_uiVisible` 状态机 + `AnimatedOpacity` 300ms + `IgnorePointer`；⑤ error/loading 态无 AppBar（居中内容 + SafeArea 返回，ADR 关联裁定6）；⑥ `_progression`/`_pendingProgression` 互切机制 | T-001 | 1.5d | US-1/US-2/US-4/US-13 widget 测试绿：打开书 `find.byType(AppBar)==0`、无 chrome；`tapAt(0.5w, 0.5h)` 呼出→再点隐藏（淡入淡出可断言 visible）；`tapAt(0.05w, 0.5h)` 不切换可见性；滚动模式边缘 `tapAt` 不触发翻页回调；`find.byIcon(Icons.auto_stories)`/原字号/目录按钮 `findsNothing`；加载/错误态无 AppBar |
| **T-003** | **ReaderChromeOverlay 顶/底栏**（design §2.2，02-menus.svg）：`reader_chrome.dart`：`ReaderTopBar`（← 返回 / 书名(大)·章节名(小) / ⋯ 更多 PopupMenuButton 恰好 4 项：阅读统计/听书/笔记/导出，点击占位项 Toast"即将上线"不打开新页）+ `ReaderBottomBar`（自左至右：上一章 / ☰ 目录 / ProgressSlider+百分比 / 🔖 书签 / Aa / 下一章，顺序断言）；`ProgressSlider`（`progress_slider.dart`：Slider + 百分比/位置文本 + onChanged 预览/onChangeEnd 松手）；章切换边界（第一章禁上一章、末章禁下一章） | T-002 | 1d | US-5/US-6/US-7 绿：顶栏三区（返回/书名+章节/⋯更多）可见；⋯更多展开恰好 4 项且顺序正确，点任一占位项不崩溃（无新路由 push）；底栏控件类型顺序断言（IconButton ☰ → Slider → 🔖 → Aa → 下一章，02-menus.svg 顺序）；← 返回 `Navigator.pop`；上一章/下一章跳转 ±1 章且 `saveProgress` 调用、边界禁用 |
| **T-004** | **SettingsSheet Aa 面板**（design §2.4，03-settings.svg，ADR 关联裁定1/3）：`settings_sheet.dart` + `ReaderStyle`（字号 [14,16,18,20,24] / 字体 系统默认·衬线·无衬线 / 主题 浅色·深色·护眼 / 行距 紧凑·标准·宽松 / 翻页 分页模式·滚动模式单选，默认滚动）；面板恰好 5 行 + 标题"显示设置" + ✕ + 半透明遮罩（正文淡化）；各控件即时生效：滚动 `Text` 字号/字体族/行距/主题色，分页 `PagedWebView.fontSize/fontFamily/lineHeight/theme` 重载（fake 构建器断言参数）；**翻页模式切换迁移**（右上角入口移除后 Aa 面板为唯一入口）+ `_pendingProgression` 互切不丢位 | T-003 | 1.5d | US-11/US-12 绿：面板打开覆盖下半屏、5 行逐项断言（每行标签 + 控件 + 当前值）；✕ 与面板外点击关闭且**回到呼出态**（ADR 关联裁定1 断言）；字号拖动/点 A+/A− 正文即时变化 + pt 值文本更新；字体/主题/行距选择断言对应渲染属性（滚动 TextStyle / 分页 fake 捕获参数）；模式切换 → ArticleBody 渲染组件切换（滚动 `SelectionArea` ↔ 分页 fake 构建器）；分页↔滚动互切后 `_progression` 不变（US-16 回归断言） |
| **T-005** | **DirectoryDrawer 目录抽屉**（design §2.5，README §3.3）：`directory_drawer.dart`：右侧 scrim + 抽屉，按 `view.chapters` 扁平列表，当前章高亮（主题色+选中标记）；onSelect(j≠当前) → 关抽屉 + `_chapterIndex=j` + `saveProgress(0.0)`；onSelect(当前) → 仅关；遮罩/关闭按钮 → 仅关 | T-003 | 0.5d | US-8 绿：☰ 打开抽屉列出全部章节标题且顺序一致；当前章条目高亮（样式断言）；点击 j≠当前 → 抽屉关闭 + 章节跳转（正文文本变化）+ `backend.saved.href` 更新；点击当前章 → 关闭不变更；遮罩点击/关闭按钮 → 关闭不变更、`saveProgress` 未被调用 |
| **T-006** | **可拖进度条 + 书签接线**（design §4.4/§4.7，ADR 决策点3）：ReaderPage 接线 `ProgressSlider`：`_dragPreview` 实时百分比预览（不跳转）；onChangeEnd → 分页 `progressionToPage` + `gotoPage` / 滚动 `progressionToOffset` + `jumpTo` → `saveProgress`；`_progression` 显示值（分页 JS `onProgress` / 滚动 controller 监听，节流复用）；书签：`_bookmarked` 图标态（🔖 已书签/未书签着色与语义断言、幂等、切章/翻页重置） | T-003 | 1d | US-9/US-10 绿：拖动 Slider 过程中百分比文本实时变化（预览值）且未触发跳转回调；松手 → 分页模式目标页换算正确（fake 构建器捕获 goto 回调/或 `backend.saved.progression` 断言）、滚动模式 `jumpTo` 后 offset 变化 + `saveProgress` 调用；拖动进度条期间不触发边缘翻页（互斥，US-9 风险1）；书签点击图标态切换、重复点击幂等、切章后重置；百分比格式"42%"与位置文本断言 |
| **T-007** | **统一选中工具条 SelectionToolbar**（design §2.6/§4.6，ADR 决策点1）：`selection_toolbar.dart`（5 入口顺序：划重点/笔记/翻译/查词/复制 + 笔记 4 色圆点装饰；`hasTranslateBackend=false` → 隐藏翻译/查词）；两模式收敛：滚动 `SelectionArea` 回调 / 分页 JS 回传（T-001 矩形）→ 同一 `_selectedText` 状态 + 同一组件实例（固定 `ValueKey('selection-toolbar')`）；定位：分页 rect 上方（clamp 视口）/ 滚动视口顶部基准位（降级线）；复制 → `Clipboard.setData`；划重点/笔记 → Toast"即将上线"；工具条外点击 → 取消选中；翻译/查词复用 `translation_popup.dart`（零改动） | T-001, T-002 | 1d | US-14/US-15 绿：滚动模式注入 `SelectionArea.onSelectionChanged` → 工具条出现且恰好 5 入口顺序正确（"笔记"带 4 色圆点）；分页模式经 fake 构建器回调（文本+矩形）→ **同一组件类型/同一 key**（断言 `find.byKey('selection-toolbar')` 两模式均命中）；点击查词 → `DictResultCard`（词条/音标/词性/释义）；点击翻译 → `TranslationResultCard`（loading/结果/缓存标记/错误重试，REQ-003 行为一致）；复制 → `Clipboard.getData` 返回选中文本；划重点/笔记点击不崩溃；`translateBackend=null` → 仅隐藏翻译/查词（划重点/笔记/复制仍在）；工具条外点击关闭 |
| **T-008** | **widget 测试更新与新增（US-1..US-17 全覆盖）**（design §10）：重写 `reader_page_test.dart`（沉浸态/呼出隐藏/边缘翻页/章切换/进度保存恢复，删除 AppBar 与底部按钮断言）；更新 `translate_reader_test.dart`（浮动工具条 5 入口替换行式三按钮，SelectionArea/fake 捕获注入不变）；`library_page_test.dart` 回归确认；新增 US-17 十项用例（①沉浸 ②呼出/隐藏 ③边缘翻页两模式 ④⋯更多四占位 ⑤底栏六控件顺序 ⑥目录抽屉 ⑦进度条拖动 ⑧Aa 面板 ⑨选中工具条+查词/译文 ⑩三按钮消失）；fake_backend 可选加长文本（滚动 maxScrollExtent>0） | T-002..T-007 | 1.5d | 全部 widget 测试绿（`flutter test`）；US-17 十项断言逐项存在且可定位到测试；除本 REQ 明确重写/更新的文件外，其余测试文件零改动且全绿 |
| **T-009** | **全量回归 + 原型一致性自检（deviation=0）**：`cargo test`（core 零改动确认）+ `flutter test` + FFI 端到端（打开书/翻页/进度/翻译查词）；CRAP/DDD 报告（FAIL=0、违规=0）；**逐屏对照 `docs/wireframes/reader-ui-v2/`**：01-immersive（无 chrome/边缘 15%/中部热区）→ 02-menus（顶栏三区/底栏六控件/42% 文本）→ 03-settings（5 行布局/色样/模式单选）→ 04-selection（工具条 5 入口/笔记 4 色点/卡片）→ README §3.1~3.5 交互逐条核对，输出偏差清单（少做/做错/发明新交互 = 0） | T-008 | 1d | 全量回归绿；自检清单 4 图 + README 逐屏打勾、deviation=0（orchestrator 复核前置材料）；`03-crap-report.md`/`03-ddd-report.md` 就绪 |

## 依赖图
```
T-001 ─→ T-002 ─→ T-003 ─┬→ T-004
                          ├→ T-005
                          └→ T-006
T-001 ────────────────→ T-007 ─┐
T-002 ────────────────→ T-007 ─┤
                               ├→ T-008 ─→ T-009
T-002..T-007 ──────────────────┘
（无环；T-004/T-005/T-006 在 T-003 后并行；T-007 在 T-001+T-002 后；关键路径
 T-001→T-002→T-003→T-006→T-008→T-009 ≈ 8d；T-004/T-005 不占关键路径）
```

## 原型一致性自检清单（T-009 执行，deviation=0）
| 屏 | 核对项（对照 svg 逐项） |
|---|---|
| 01-immersive | 无任何常驻 chrome（AppBar/底栏/工具按钮 = 0）；正文占满；左/右边缘 15% 热区（仅分页模式生效）；中部 1/3 呼出热区（x∈[1/3,2/3]×正文中部垂直）；边缘点击不切换工具栏可见性 |
| 02-menus | 顶栏：←返回 / 书名(大)·章节名(小) / ⋯更多；底栏自左至右：上一章 / ☰目录 / 可拖进度条+百分比（"42%"样式）/ 🔖书签 / Aa / 下一章；进度条可拖、百分比文本存在 |
| 03-settings | 面板覆盖下半屏 + 正文淡化 + 标题"显示设置" + ✕；恰好 5 行：字号（A−/滑块/A+/pt 值）/ 字体（系统默认·衬线·无衬线）/ 主题（浅色·深色·护眼，色样对齐）/ 行距（紧凑·标准·宽松）/ 翻页（分页模式/滚动模式单选） |
| 04-selection | 浮动工具条恰好 5 项且顺序：划重点/笔记/翻译/查词/复制；"笔记"带 4 色圆点装饰；选中文本上方（分页精确/滚动基准位，ADR 决策点1 降级线）；查词卡片（词名/音标/词性/释义/例句）；翻译浮层（loading/错误重试/Provider/缓存标记） |
| README §3.1~3.5 | 全局两模式统一：滑动/长按不被打断；⋯更多菜单 4 占位项；目录抽屉（章节列表+当前章高亮）；书签图标态；模式切换仅在 Aa 面板（右上角三按钮不存在，US-13） |

## 冲突检查结果

- **与 ddd-rules 无冲突（1 项措辞偏差已处置）**：
  1. `ddd-rules.toml` interface paths 为 `core/src/api.rs | app/lib/pages | app/lib/engines`，
     **`app/lib/widgets/**` 未声明**（01-req §3"widgets 已声明属 interface 层"与规则表不符）。
     处置：规则表冻结零改动（docs/07 §6）；新增 widget 文件按架构纪律与 pages 同级约束（只经
     services、禁 import 桥接生成物，03-review 人工核对 import 面）；建议后续评审把 widgets 纳入
     interface paths（记录不执行）。
  2. pages/engines 改造后合规：reader_page 与 paged_web_view 均不 import `src/rust/**`
     （经 services/engines 组件，ddd-lint 违规=0 可达成）。
- **与进度模型/听读同进度无冲突**：进度条 = 章内 progression（`saveProgress(href, progression)`
  语义不变）；core/api.rs/表/迁移零改动；`reading_progress` 仍为唯一事实源（docs/04 §9.1 不变式
  保持）；docs/04 §3 `Locator.progression`（章内）一致。
- **与原型一致性无冲突**：四图 + README 逐屏映射入自检清单（T-009 deviation=0）；已拍板决策
  （滚动无边缘翻页、⋯更多四占位、书架不动）已纳入；无自创交互（ADR/design 全部以原型为据）。
- **与 REQ-001/003 零回归**：PagedWebView 增强全部向后兼容（fake 构建器/既有测试零改动）；
  翻译/查词/选区回传既有路径保留；`translateBackend` 可选参数不变。
- **与状态管理现状无冲突**：不引入 Riverpod（ADR 决策点4），全部局部 setState。
- **范围划界**：⋯更多四项 / 划重点 / 笔记 / 复制（系统剪贴板）/ 书签图标态 均为占位（01-req §1
  边界）；书架页、听书页、阅读统计、导出本体均不触碰。

## 闸门2 自评（计划部分）
- [x] ADR 备选 ≥2 且给出理由（4 决策点各 ≥2 备选 + 拒绝论证 + 降级线授权引用）
- [x] 任务粒度可执行（T-001..T-009 每项 ≤1.5d、验收可断言且映射 US 编号；依赖图无环）
- [x] 冲突清单为空或已含处置方案（ddd-rules 措辞偏差、进度模型、原型一致性、REQ-001/003 回归、
      状态管理现状共 5 类，全部无冲突或已列处置；已知取舍 5 项均在 02-design §12 记录）
- [x] 原型引用：ADR/design 均显式引用 `docs/wireframes/reader-ui-v2/*`（docs/07 §4.3 教训固化）
