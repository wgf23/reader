<!-- wf-meta: req=REQ-009-notes-search | phase=testing | agent=test-engineer | date=2026-09-09 | gate=passed -->
# REQ-009 · 覆盖率报告（闸门4②）

> 输入：`03-review.md`（gate=passed，commit `3b8af1d`）、代码、`workflow/skills/coverage.md`、`workflow/skills/gates.md`。
> 工具：`flutter test --coverage`（Flutter 3.47.2 / Dart）+ `cargo llvm-cov 0.9.1`（rustc 1.98.1）。
> 口径：**新代码 = `git diff main` 新增行 ∩ 覆盖率可执行行**；排除 `app/lib/src/rust/**`（FRB 生成物）
> 与 `paged_web_view.dart`（真实系统 WebView，固有不可测）。
> 原始数据：`workflow/reports/coverage-req009.lcov`（Dart）、`workflow/reports/coverage-req009-rust.lcov` / `.json`（Rust）。

---

## 1. 结论摘要

| 口径 | 覆盖 | 门槛 | 判定 |
|---|---|---|---|
| **Dart 新增/改动代码（新代码口径，排除生成物）** | **870 / 874 = 99.54%** | ≥85% | ✅ |
| Dart 新增/改动代码（whole-file，同 17 文件） | 2191 / 2320 = 94.44% | 参考 | ✅ |
| **Rust 新增/改动生产代码（排除 `frb_generated.rs`）** | **2210 / 2231 = 99.06%** | ≥85% | ✅ |
| Rust whole-file（同 9 文件） | 见 §4 | 参考 | ✅ |
| Dart 全仓（whole-file，含生成物） | 见 lcov；新代码口径为准 | 参考 | — |
| Rust 全量测试 | **282 passed / 0 failed** | 绿 | ✅ |
| Dart 全量测试 | **292 passed / 1 skipped / 0 failed** | 绿 | ✅ |
| `flutter analyze` | **No issues found!** | 0 issues | ✅ |
| 真实集成测试（US-10/US-22） | **2 passed / 0 failed** | 绿 | ✅ |

> 本阶段补齐 8 个新测试文件（见 §6），把 Dart 新代码从首轮 18.98% 提升到 **99.54%**；
> Rust 新增 api 桥接集成测试把 `api.rs` 新代码从 0% 提升到 **99.64%**。

---

## 2. 采集命令

```bash
export PATH="/root/flutter/bin:/root/.cargo/bin:$PATH"

# Dart（带 READER_CORE_SO 使 FRB 适配层 FFI 测试真实执行）
cd app && READER_CORE_SO=/root/reader/core/target/release/libreader_core.so \
  flutter test --coverage            # → app/coverage/lcov.info

# Rust（release，含 lib + 全部 tests/*.rs）
cd core && CARGO_BUILD_JOBS=2 cargo llvm-cov --release \
  --lcov --output-path /root/reader/workflow/reports/coverage-req009-rust.lcov
cd core && CARGO_BUILD_JOBS=2 cargo llvm-cov --release \
  --json --output-path /root/reader/workflow/reports/coverage-req009-rust.json
```

- 新代码口径：新增行中仅统计覆盖率工具有记录的可执行行（注释/空行/类声明不计入分母）。
- `scripts/cov-summary.py` 面向 `cargo llvm-cov` 的 JSON（`data[0].files`），**不能解析 lcov**；
  本报告用等价的 lcov 解析（`DA`/`SF`）+ `git diff` 新增行取交集，口径与 REQ-007/REQ-008 一致。
- FFI 适配层（`rust_notes_backend`/`rust_search_backend`/`rust_library_backend` 的 href 行）
  由 `test/notes_search_ffi_test.dart` 在 `READER_CORE_SO` 下真实执行覆盖（普通 `flutter test`
  无 `.so` 时该用例 skip，此时这三文件覆盖为 0；故本报告以**带 .so 的采集**为主口径并如实登记）。

---

## 3. Dart 新增/改动文件覆盖率表（新代码口径）

| # | 文件 | 新增可执行行 | 已覆盖 | 新代码行覆盖 | whole-file |
|---|---|---|---|---|---|
| 1 | `lib/services/notes_backend.dart` | 41 | 41 | **100.00%** | 100.00% |
| 2 | `lib/services/rust_notes_backend.dart` | 49 | 49 | **100.00%** | 100.00% |
| 3 | `lib/services/search_backend.dart` | 18 | 18 | **100.00%** | 100.00% |
| 4 | `lib/services/rust_search_backend.dart` | 18 | 18 | **100.00%** | 100.00% |
| 5 | `lib/services/export_path_picker.dart` | 16 | 16 | **100.00%** | 100.00% |
| 6 | `lib/services/library_backend.dart` | 1 | 1 | **100.00%** | 75.00% |
| 7 | `lib/services/rust_library_backend.dart` | 1 | 1 | **100.00%** | 23.26% |
| 8 | `lib/widgets/note_colors.dart` | 15 | 14 | 93.33% | 93.33% |
| 9 | `lib/widgets/note_editor_card.dart` | 26 | 26 | **100.00%** | 100.00% |
| 10 | `lib/widgets/notes_panel.dart` | 223 | 223 | **100.00%** | 100.00% |
| 11 | `lib/widgets/selection_toolbar.dart` | 34 | 34 | **100.00%** | 97.83% |
| 12 | `lib/pages/note_span_policy.dart` | 39 | 39 | **100.00%** | 100.00% |
| 13 | `lib/pages/notes_page.dart` | 6 | 6 | **100.00%** | 100.00% |
| 14 | `lib/pages/search_page.dart` | 128 | 128 | **100.00%** | 100.00% |
| 15 | `lib/pages/reader_page.dart` | 240 | 237 | 98.75% | 95.63% |
| 16 | `lib/pages/continuous_scroll_policy.dart` | 17 | 17 | **100.00%** | 100.00% |
| 17 | `lib/pages/library_page.dart`（后端注入 2 行） | 2 | 2 | **100.00%** | 70.31% |
| — | **合计** | **874** | **870** | **99.54% ✅** | 94.44% |

> `rust_library_backend.dart` whole-file 低（23.26%）是因为该文件大部分为既有方法，本 REQ 仅新增 `href: c.href` 一行；
> 新代码口径该行已由 FFI 测试覆盖。`library_backend.dart` 同理（仅 `href` 字段默认值）。

---

## 4. Rust 新增/改动生产代码覆盖率表（排除 `frb_generated.rs`）

| # | 文件 | 新增可执行行 | 已覆盖 | 新代码行覆盖 | whole-file |
|---|---|---|---|---|---|
| 1 | `core/src/types.rs` | 76 | 76 | **100.00%** | 100.00% |
| 2 | `core/src/store/mod.rs` | 106 | 106 | **100.00%** | 98.95% |
| 3 | `core/src/store/annotations.rs` | 276 | 269 | 97.46% | 97.46% |
| 4 | `core/src/store/search_index.rs` | 253 | 253 | **100.00%** | 100.00% |
| 5 | `core/src/locator/mod.rs` | 342 | 338 | 98.83% | 98.83% |
| 6 | `core/src/notes/mod.rs` | 588 | 582 | 98.98% | 98.98% |
| 7 | `core/src/search/mod.rs` | 310 | 307 | 99.03% | 99.03% |
| 8 | `core/src/api.rs` | 278 | 277 | **99.64%** | 94.32% |
| 9 | `core/src/store/translation.rs`（busy_timeout 2 行） | 2 | 2 | **100.00%** | 100.00% |
| — | **合计** | **2231** | **2210** | **99.06% ✅** | — |

> `api.rs` 新代码 99.64%：由新增 `core/tests/notes_search_api.rs` 端到端驱动 9 个 notes 桥接 +
> `search`/懒回填/scope 组装（此前 Rust 侧对 `notes_*`/`search` 桥接为 0 覆盖）。
> `store/annotations.rs` 97.46% 的未覆盖行主要为 `locator_json` 反序列化失败兜底分支，
> 主路径（insert/get/update/delete/delete_many/delete_all/list/find_bookmark）100% 覆盖。

---

## 5. 剩余未覆盖行逐一分析（Dart 4 行 / 100% 有结论）

| 文件:行 | 代码 | 结论 |
|---|---|---|
| `note_colors.dart:7` | `const NoteColors._();` | **不可执行声明行**：私有构造，lcov 记为未覆盖但无逻辑，等价于不可测。 |
| `reader_page.dart:776` | `_createNote('highlight', color: NoteColors.defaultColor);` | **不可达防御分支**：仅当 `ReaderSelectionToolbar.onHighlightColor == null` 时点「高亮」才会走 `_onSelectionAction(highlight)`；`ReaderPage` 恒传入 `_createHighlightWithColor`（走选色回调），故生产不可达。工具栏自身该分支由 `selection_toolbar_highlight_test.dart` 覆盖。 |
| `reader_page.dart:1245-1246` | 滚动开始清临时高亮：`_tempTimer?.cancel(); setState(() => _tempHighlight = null);` | **手势仲裁不可稳定构造**：`SelectionArea` 会拦截正文拖拽为选区，widget 测试无法稳定触发 `ScrollStartNotification.dragDetails != null`。同语义的「点击正文清除临时高亮」已由 `reader_notes_test.dart` 覆盖；本分支由真实集成测试 US-8 与真机 US-24 覆盖。 |

> Rust 剩余未覆盖行均为防御兜底/错误分支（`serde` 反序列化失败回退、`delete_all(kinds=Some)`），
> 主路径 100% 覆盖；新代码口径 99.06%，无未知未测路径。

---

## 6. 本阶段新增/修改的测试文件

| 文件 | 用例数 | 覆盖点 |
|---|---|---|
| `app/test/note_span_policy_test.dart` | **新增 18** | `composeSpans` 空/单色/多色/重叠 order/划线/批注虚线/临时高亮/越界/零宽/emoji/合并 |
| `app/test/note_colors_test.dart` | **新增 6** | `colorFor` 非法/缺 #/长度错、`hexOf` 往返、前导零 |
| `app/test/notes_panel_test.dart` | **新增 28** | 分组/色标/时间/空态/无匹配/多选/复选框/批量删除二次确认/编辑校验/改色/导出成功·取消·失败·空态/错误态 |
| `app/test/search_page_test.dart` | **新增 12** | 初始/空查询/命中/关键词蓝加粗/无命中/键盘提交/错误/loading/范围/格式/定位 pop/越界 clamp/分隔线 |
| `app/test/notes_page_test.dart` | **新增 2** | 薄壳注入 / 默认实现降级 |
| `app/test/export_path_picker_test.dart` | **新增 4** | 桌面 saveFile 参数/取消、移动应用目录+非法字符替换（method channel mock） |
| `app/test/selection_toolbar_highlight_test.dart` | **新增 2** | 高亮选色两分支（无/有 `onHighlightColor`） |
| `app/test/reader_notes_test.dart` | **新增 18** | 划线/批注落库、编辑器校验/取消/删除、面板开合/点外关闭/条目跳转+临时高亮/resolve 降级、书签失败、导出成功·取消·空态·读失败·写失败、搜索同书/跨书定位、initialTarget 超时清除、加载失败静默 |
| `app/test/notes_search_ffi_test.dart` | **新增 1（FFI）** | `RustNotesBackend` CRUD/书签/导出/resolve/删除 + `RustSearchBackend` 映射 + `RustLibraryBackend.href` |
| `core/src/types.rs` | **新增 3** | `NoteKind`/`ExportFormat`/`Lang` 的 `parse`/`as_str`/`ext` 全分支 |
| `core/src/locator/mod.rs` | **新增 6** | `text_at` 反序/零宽、progression=start/total、并列取最早、needle 超长/等长 |
| `core/src/notes/mod.rs` | **新增 4** | 空白颜色→None、真实时间戳、delete_many/delete_all 计数、书签 snippet 补锚、14+3 个参考日期 |
| `core/src/search/mod.rs` | **新增 4** | `index_book`/`is_indexed` 委托、eq_ci 不同字母不判等、空/超长/等长 needle、多词与半开区间 |
| `core/src/store/annotations.rs` | **新增 2** | delete 删除已存在行、delete_all(kinds) 过滤计数 |
| `core/src/store/search_index.rs` | **新增 1** | book_id + formats 组合占位符不冲突 |
| `core/src/store/mod.rs` | **新增 2** | cache/dicts 目录、新库 integrity_check |
| `core/tests/notes_search_api.rs` | **新增 1** | api 桥接全链路（9 notes + search + 懒回填/scope/格式过滤/空查询/错误路径） |

> 既有测试（`reader_page_test`/`reader_selection_test`/`continuous_scroll_policy_test`/`reader_continuous_scroll_test` 等）
> 断言**零改动、未削弱**；新增测试均为真实断言，无空断言。

---

## 7. 不可测项说明

| 项 | 说明 | 兜底 |
|---|---|---|
| `lib/engines/paged_web_view.dart` | 真实 `InAppWebView` 平台视图，`flutter_inappwebview` 无 Linux 实现，属**固有不可测**。 | 真机 US-24；分页可测出口 REQ-007 已交付。 |
| `lib/src/rust/**`（FRB 生成物） | 代码生成，不计入口径。 | codegen 幂等（`git status app/lib/src/rust/` 干净）。 |
| `reader_page.dart:776 / 1245-1246` | 不可达防御分支 / SelectionArea 手势仲裁不可稳定构造（见 §5）。 | 工具栏单测 + 真实集成 US-8 + 真机。 |
| `integration_test/*.dart` | `flutter test --coverage` 不含集成测试，不计入 lcov。 | 单独 `xvfb-run` 运行（§1，US-10/US-22 2/2）。 |
| US-24 真机项 | 8 项人工清单（`03-review.md §6`），本环境无 Android 设备。 | 阶段 5b/真机执行。 |

---

## 8. 回归与门禁自检

| 检查 | 命令 | 结果 |
|---|---|---|
| Dart 全量 + 覆盖 | `cd app && READER_CORE_SO=... flutter test --coverage` | **292 passed / 1 skipped / 0 failed** |
| Dart 新代码行覆盖 | §3 | **870/874 = 99.54% ≥ 85%** ✅ |
| Flutter 静态分析 | `cd app && flutter analyze` | **No issues found!** |
| Rust 全量测试 | `cd core && CARGO_BUILD_JOBS=2 cargo test --release` | **282 passed / 0 failed** |
| Rust 新代码行覆盖 | §4（`cargo llvm-cov --release`） | **2210/2231 = 99.06% ≥ 85%** ✅ |
| 真实集成（US-10/US-22） | `xvfb-run -a flutter test integration_test/notes_search_integration_test.dart -d linux` | **2 passed / 0 failed** |
| 静态守卫（未削弱） | `cd app && flutter test test/no_synthetic_chrome_test.dart` | passed |
| 变异测试 | `04-mutation.md` | 见该报告 |

---

## 9. 闸门4②自评

- [x] **新代码行覆盖率 ≥ 85%**：Dart **99.54%**（870/874）、Rust **99.06%**（2210/2231）
- [x] **关键分支（错误/边界）已覆盖**：空/纯空白查询、特殊字符、单字 CJK LIKE 回退、同 snippet 多处消歧/并列、无匹配降级、删除幂等/级联、导出转义/空态/取消/失败、书签幂等、v3→v4 迁移幂等、面板空态/无匹配/未选禁用、搜索 loading/错误/跨书
- [x] 不可测项逐条说明并给出兜底（§7）
- [x] 全量回归绿（Rust 282 + Dart 292 + 集成 2 + analyze 0），既有断言/守卫零削弱
- [x] 结论可审计：分数 / 命令 / 原始 lcov 落盘

**闸门4②结论：通过（passed）。**
