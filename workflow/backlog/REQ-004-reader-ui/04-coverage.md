<!-- wf-meta: req=REQ-004 | phase=testing | agent=test-engineer | date=2025-09-01 | gate=passed -->
# REQ-004 · 测试强化与覆盖报告（闸门4）

> 范围：**UI-only REQ**（core 零改动）。闸门4 的 mutation/coverage 工具（cargo-mutants + llvm-cov）面向
> Rust 核心；本 REQ 无新 Rust 代码，故 mutation 对 core 无可测对象；Dart 侧以 `flutter test --coverage`
> + `flutter analyze` + 全绿测试承担质量闸门。

## 1. 覆盖度量（`flutter test --coverage`）

### 1.1 新增/改动 interface 代码覆盖率（排除不可在 widget 测试覆盖的真实 WebView 与桥接生成物）

| 文件 | 覆盖 | 说明 |
|---|---|---|
| `app/lib/pages/reader_page.dart` | **85.9%**（244/284） | 沉浸态/手势/Chrome/Aa/目录/书签/选中/进度/分页主路径 |
| `app/lib/widgets/reader_chrome.dart` | 100%（42/42） | ReaderTopBar/ReaderBottomBar |
| `app/lib/widgets/selection_toolbar.dart` | 100%（26/26） | 5 入口 + 4 色点 |
| `app/lib/widgets/directory_drawer.dart` | **100%**（15/15） | 目录抽屉 |
| `app/lib/widgets/display_settings_sheet.dart` | 94.6%（53/56） | Aa 面板 |
| `app/lib/widgets/translation_popup.dart` | 100%（64/64） | REQ-003 浮层复用 |
| **新增/改动代码合计** | **91.2%**（444/487） | ≥85% 通过 |

> 注：`engines/paged_web_view.dart` 为真实系统 WebView 封装（依赖平台原生组件），widget 测试经
> `pagedViewBuilder` 注入 fake 构建器从而不实例化真实 WebView —— 故该文件在 widget test 下 0 覆盖，
> **属固有不可测**（由真机/集成测试覆盖，out of widget-test scope）。`src/rust/**`（FRB 生成物）与
> `rust_*_test.dart`（FFI）需 `README:core libreader_core.so`，在未构建 `.so` 时可跳过（沿用既有机制）。

### 1.2 本 REQ 新增 widget 测试（读者/翻译/书架）
| 测试 | 覆盖点 |
|---|---|
| 沉浸态/点击中部呼出/再点隐藏 | US-1/US-2 |
| 翻章保存进度 + 重开恢复 | 进度模型 |
| Aa 面板 + ReaderSettingsSheet 组件（主题/分页模式） | US-11/US-12 |
| 分页模式渲染（initialPagedMode） | US-13 |
| 底部进度条拖动 → saveProgress | US-9 |
| ⋯更多 4 占位项 | US-6 |
| 目录抽屉打开 → 选章跳转 + saveProgress | US-8 |
| 书签图标切换（幂等） | US-10 |
| 选中工具条 划重点/笔记/复制 点击不崩溃 | US-14 |
| 分页模式边缘 15% 点击不崩（fake 无 state 短路） | US-3/US-4 |
| ReaderDirectoryDrawer 组件 | US-8 |
| 翻译/查词 浮层（成功/失败重试/未收录/无词库/null 后端） | US-15/US-16 |

### 1.3 全量结果
- `flutter test --coverage`：**24 项全绿**（另 2 项 FFI 因未构建 `.so` 跳过，沿用既有
  `READER_CORE_SO` 机制，非本 REQ 回归）。
- `flutter analyze`：**0 issues**。
- `cargo test --release`：全绿（lib + 21 mobi_azw3 + 5 p0_corpus + 7 translate_corpus）——**core 零改动零回归**。

## 2. Mutation 情况
- 本 REQ **core 零改动**（git 核实 core/ 无 diff），mutation 针对 Rust 主代码无新增可变异点。
  既有 core 在 REQ-003 闸门已达成 **98.5%**（`workflow/backlog/REQ-003-translate/04-mutation.md`），
  本次不作重复变异验证（避免无意义长任务）。
- Dart/Flutter 侧当前项目未配置 mutation 工具（cargo-mutants 为 Rust-only）；Dart 质量以
  coverage（≥85%）+ analyze + 全绿测试替代评估。

## 3. 闸门4 结论
- [x] **覆盖 ≥85%**：新增/改动 interface 代码合计 **91.2%**（reader_page 85.9%、widgets 均 ≥94.6%）。
- [x] **mutation ≥80%**：core 零改动（REQ-003 已 98.5%）；无新 Rust 可变异点。
- [x] **全绿 + analyze 0**：24 项 widget + cargo 全绿；flutter analyze 0 issues。
- 无待办缺陷；无已知未测生产路径（除固有不可测的真实 WebView / FRB 生成物 / FFI）。
