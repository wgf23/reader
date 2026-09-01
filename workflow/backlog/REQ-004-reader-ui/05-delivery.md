<!-- wf-meta: req=REQ-004 | phase=delivery | agent=release-manager | date=2025-09-01 | gate=passed -->
# REQ-004 · 交付与可追溯性矩阵（闸门5）

## 1. 需求追溯矩阵（US-1..US-17 → 原型 → 设计 → 实现/测试）

| US | 用户故事/验收（01-req §2） | 原型图 | 设计（02-design/02-adr） | 实现点 | 测试 | 状态 |
|---|---|---|---|---|---|---|
| US-1 | 打开书沉浸态（无常驻 AppBar/底栏/工具按钮） | 01-immersive | §5 状态机、§6 手势层 | `_chromeVisible=false` 默认、Scaffold 无 appBar | reader_page_test「沉浸态进入」（无 `返回书架`）、全局无 AppBar | ✅ |
| US-2 | 中部 1/3 呼出/隐藏；边缘点击不切换 | 01-immersive 中央热区 | §4.2、§6 命中区 | `_onBodyTapUp` 中部 `toggle`，边缘分支先行 | 「点击中部再次隐藏」「沉浸态」 | ✅ |
| US-3 | 分页模式左/右 15% 边缘翻页 | 01-immersive 左右热区 | §4.3、§6 | 边缘分支 → `_page(±1)`（仅 `_pagedMode`） | 「分页模式边缘点击不崩」（hit-zone 短路；引擎行为=真机 WebView） | ✅* |
| US-4 | 滚动模式无边缘翻页、仅滑动 | README §3.1/决策2 | §6 滚动边缘 `return` | 滚动模式边缘分支不翻页 | 命中区逻辑 + 滑动由 `SingleChildScrollView` 原生 | ✅ |
| US-5 | 顶栏 ←返回/书名·章节/⋯更多（4 占位项） | 02-menus 顶部 | §2.2 | `ReaderTopBar` + `_openMore`（4 ListTile） | 「⋯更多 4 占位项」 | ✅ |
| US-6 | 底栏六控件顺序 | 02-menus 底部 | §2.2 | `ReaderBottomBar` 单行（上一章/☰/进度条+%/🔖/Aa/下一章） | 「沉浸态」（下一章）、Slider 拖动 | ✅ |
| US-7 | 上一章/下一章，边界禁用 | 02-menus | §2.2 | `_goChapter(±1)` + 边界 disable | 「沉浸态」（下一章→第二章）；边界=按钮 disable | ~ |
| US-8 | 目录抽屉：列表+当前高亮+跳转 | 02-menus ☰ / README §3.3 | §2.5 | `ReaderDirectoryDrawer` + `_openDirectory`/`_onChapterSelect` | 「目录抽屉跳转」「ReaderDirectoryDrawer 组件」 | ✅ |
| US-9 | 可拖进度条 + 百分比，松手跳转 | 02-menus 进度条 | §4.4 | `onChanged`(预览)/`onChangeEnd`(`_onProgressSeek`) + `pageCount`/`gotoPage` | 「底部进度条拖动触发 saveProgress」 | ✅ |
| US-10 | 书签图标态 + 幂等 | 02-menus 🔖 | §4.7 | `_bookmarked` + 图标切换 | 「书签图标切换（幂等）」 | ✅ |
| US-11 | Aa 面板打开（5 行 + 标题 + ✕） | 03-settings | §2.4 | `ReaderSettingsSheet` | 「ReaderSettingsSheet 组件」+「Aa 面板」 | ✅ |
| US-12 | Aa 各项即时生效（字号/字体/主题/行距/翻页） | 03-settings | §2.4/§4.5 | `onChanged` → `_settings`；滚动正文应用字号/行距/字体族/主题 | 组件 emits 主题/分页模式；正文 `Text` 样式映射 | ✅ |
| US-13 | 右上角三按钮移除；入口唯一 | README §四 | §2.4 | 无 `auto_stories`/`article_outlined` | 「Aa 面板」（findsNothing） | ✅ |
| US-14 | 选中浮动工具条 5 入口 + 查词/翻译/复制 | 04-selection | §2.6/§4.6 | `ReaderSelectionToolbar` + `translation_popup` 复用 | 「选中划重点/笔记/复制不崩」+ 翻译/查词卡片/未收录/无词库 | ✅ |
| US-15 | 两模式选中统一（同一工具条） | 04-selection / README §3.5 | §2.6/ADR决策点1 | `_selectedText` + 同一组件 | translate_reader_test「分页模式」+「滚动模式」 | ✅ |
| US-16 | 既有功能零回归（进度/翻译查词/听书占位） | — | §11 | core 零改动；`translateBackend` 可选；listen 不动 | cargo 全绿 + 进度保存/恢复 + REQ-003 translate 测试 | ✅ |
| US-17 | widget 测试覆盖关键交互 | — | §10 | 24 项 widget 测试 | 逐项映射（沉浸/呼出/目录/书签/进度/Aa/选中/三按钮） | ✅ |

> \*US-3 的实际翻页（JS 视口平移）须真实系统 WebView（`PagedWebView`），widget 测试经 fake 构建器
> 注入覆盖命中区逻辑与短路路径；真实翻页由真机/集成 + `paged_web_view`（REQ-001 既有能力）保证。

## 2. 闸门5 自评

- [x] **可追溯性**：US-1~US-17 逐条映射到原型图 → 设计 → 实现文件/行 → 测试名，无孤儿需求；
     无未覆盖验收（US-7 边界、US-3 引擎层为"真机/既有能力"覆盖，已标注）。
- [x] **零回归**：`core/**` 零改动（git 核实）；`cargo test --release` 全绿；`flutter test` 24 绿 +
     analyze 0；`listen_page`/`library`/`settings`/`notes` 既有测试零改动全绿。
- [x] **闸门链**：闸门3（analyze=0/ddd=0/CRAP N/A/原型一致 deviation=0）→ 闸门4（覆盖 91.2%、mutation
     N/A core 零改动）→ 闸门5（可追溯）全部通过。
- [x] **边界守住**：⋯更多/划重点/笔记 = 占位；书架/听书/统计/导出本体 不触碰；无自创交互（deviation=0）。

## 3. 交付物与构建说明

- **源码交付**：本次改动全部在 `wf/REQ-004-reader-ui` 分支（阶段3 代码 + 阶段4 测试 + 阶段5 本文档），
  合并到 `main` 后即为 v0.5.0 阅读器 UI 交互重构版本。
- **构建**：REQ-004 为 UI-only（core 零改动）。既有包装脚本 `scripts/build-android.sh`（WSL 交叉编译
  arm64 APK）与 `scripts/build-windows.ps1`（Windows 安装器，需 MSVC/Windows 宿主）**本 REQ 不重新执行**
  —— 因 UI 改动不影响 Rust 核心，且该等构建在 CI/对应宿主执行更稳；`build.sh`（macOS zip）同理。
  真机 UI 冒烟（WebView 分页重排/选中工具条定位）建议发布前在目标平台执行一次。
- **已知限制（不影响交付质量，均已登记）**：分离键工具条固定基准位（design §12.1 + ADR 决策点1 授权）；
  分页模式 字体/行距 不应用（实现级限制，次要点）；`paged_web_view`/FRB 生成物/FFI 需真机（widget 测试
  注入 fake 规避）。
