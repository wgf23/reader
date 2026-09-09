<!-- wf-meta: req=REQ-007-reader-interaction-fixes | phase=testing | agent=test-engineer | date=2026-09-09 | gate=passed -->
# REQ-007 · 覆盖率报告（闸门4②）

> 输入：`03-review.md`（gate=passed）、代码 `d20f789`（diff base `4f3f55b`）、`workflow/skills/coverage.md`。
> 工具：`flutter test --coverage`（Flutter/Dart，生成 `app/coverage/lcov.info`）。
> 口径：**新代码 = `git diff 4f3f55b..HEAD` 新增行 ∩ lcov 可执行行（DA）**；逐文件与合计均统计。排除 `lib/engines/paged_web_view.dart`（真实系统 WebView，固有不可测，单列）与 `lib/src/rust/**`（FRB 生成物）。

---

## 1. 结论摘要

| 口径 | 覆盖 | 门槛 | 判定 |
|---|---|---|---|
| **新增/改动 Dart 代码（6 个可测文件，新代码口径）** | **142 / 142 = 100%** | ≥85% | ✅ |
| 新增/改动 Dart 代码（whole-file 口径，6 个可测文件） | 477 / 515 = 92.6% | 参考 | ✅ |
| `paged_web_view.dart`（真实 WebView，排除） | 0 / 37 新行（2/97 whole-file） | — | 单列不可测 |
| Dart 全仓 | 1268 / 2418 = 52.4% | 参考 | — |
| Rust 全量测试 | 222 passed / 0 failed | 绿 | ✅ |

---

## 2. 采集命令

```bash
export PATH=/root/flutter/bin:$HOME/.cargo/bin:$PATH
cd /root/reader/app && flutter test --coverage     # → app/coverage/lcov.info（152 passed / 4 skipped）
cd /root/reader/core && CARGO_BUILD_JOBS=2 cargo test --release   # 222 passed / 0 failed
```

> 注：`scripts/cov-summary.py` 面向 `cargo llvm-cov` 的 JSON（`data[0].files`），**不能解析 lcov**；本报告用内联 lcov 解析器按文件统计（等价口径），并对 `git diff` 新增行取交集。

---

## 3. 新增/改动 Dart 文件覆盖率表（新代码口径）

| # | 文件 | 新增可执行行 | 已覆盖 | 新代码行覆盖 | whole-file |
|---|---|---|---|---|---|
| 1 | `lib/pages/body_tap_policy.dart` | 47 | 47 | **100%** | 47/47 = 100% |
| 2 | `lib/engines/paged_document_reloader.dart` | 16 | 16 | **100%** | 16/16 = 100% |
| 3 | `lib/engines/paged_js_result.dart` | 15 | 15 | **100%** | 15/15 = 100% |
| 4 | `lib/engines/paged_view_controls.dart` | 4 | 4 | **100%** | 4/4 = 100% |
| 5 | `lib/pages/reader_page.dart` | 47 | 47 | **100%** | 312/350 = 89.1% |
| 6 | `lib/widgets/translation_popup.dart` | 13 | 13 | **100%** | 83/83 = 100% |
| — | **合计（可测）** | **142** | **142** | **100% ✅** | 477/515 = 92.6% |
| — | `lib/engines/paged_web_view.dart`（排除） | 37 | 0 | 0%（固有不可测） | 2/97 = 2.1% |

> `reader_page.dart` 新代码 47/47 全绿；whole-file 未覆盖的 38 行均为**既有**（非本 REQ 新增）代码（错误/边界路径，如 `_onProgressSeek` 分页分支、默认 `PagedWebView` 构建器、`_toolbarTop` 的 clamp 分支等），不影响新代码门槛。

---

## 4. 新增/改动文件的未覆盖热点与补测（本阶段）

首轮采集发现 `reader_page.dart` 新代码仅 **37/47 = 78.7%**（低于 85%），未覆盖新增行：`202–206, 209`（`_applyTap` 的 `dismiss` 分支）、`248`（`_jumpToProgress` 分页 `relayoutAfterLoad` 接线）、`502–504`（`Listener.onPointerMove`）。本阶段**新增测试文件** `app/test/reader_page_interaction_coverage_test.dart`（3 例，纯测试、不改生产代码）：

| 新增用例 | 覆盖的新增行 |
|---|---|
| `REQ-007 D1 dismiss 分支：非中部点击隐藏 Chrome 并清空选中` | `202–206, 209`（`hasSelection` + `chromeVisible` 双分支） |
| `REQ-007 D1 onPointerMove 分支：拖动正文（超 slop）不 toggle Chrome` | `502–504`（`Listener.onPointerMove`） |
| `REQ-007 D2/D4 分页目录切章 → relayoutAfterLoad 经 PagedLoadGate 接线` | `248`（`_jumpToProgress` 分页重排接线） |

复采后 `reader_page.dart` 新代码 **47/47 = 100%**，合计 142/142 = 100%。

其他新增文件的边界分支已由开发阶段单测穷举覆盖（`body_tap_policy_test.dart` 分区表/四条件、`paged_document_reloader_test.dart` 重载/样式/幂等/gate、`paged_js_result_test.dart` bool/num/字符串/null、`page_turn_coordinator_test.dart` 章内/章末对称、`translate_reader_test.dart` 去设置/查词无按钮/来源标签）。

---

## 5. 不可测项说明

| 项 | 说明 | 兜底 |
|---|---|---|
| `lib/engines/paged_web_view.dart`（新行 37，覆盖 0%） | 真实 `InAppWebView` 平台视图，`flutter_inappwebview` 无 Linux 实现，widget 测试无法实例化，属**固有不可测**（`workflow/skills/coverage.md` 先例）。本 REQ 已把其新增逻辑抽为可测出口：`paged_document_reloader.dart` / `paged_js_result.dart` / `paged_view_controls.dart` **均 100%**；文件内剩余为薄委托（`didUpdateWidget`→reloader、`_js`→executor、`_loadGate`）。 | US-17 Android 真机清单（`03-review.md §4`）+ 集成测试仅滚动模式 |
| `lib/src/rust/**`（FRB 生成物） | 代码生成，不计入口径 | codegen 幂等（`git status app/lib/src/rust/` 为空） |
| FFI 4 例（无 `.so` 时 skip） | 普通 `flutter test` 无 `libreader_core.so` → `markTestSkipped`（本次 152 passed / 4 skipped）。 | 带 `READER_CORE_SO` 环境时可跑（REQ-006 已端到端覆盖） |
| US-17 真机项 | 分页呼出/翻页/切章/去设置的人工验收 | 见 `03-review.md §4` |

---

## 6. 回归与门禁自检

| 检查 | 命令 | 结果 |
|---|---|---|
| core 全量单测 | `cd core && CARGO_BUILD_JOBS=2 cargo test --release` | **185 + 21 + 5 + 8 + 3 = 222 passed / 0 failed** |
| Flutter 全量 + 覆盖 | `cd app && flutter test --coverage` | **152 passed / 4 skipped / 0 failed** |
| 新增/改动 Dart 新代码行覆盖 | 本报告 §3 | **142/142 = 100% ≥ 85%** |
| 关键分支（错误路径/边界） | `body_tap_policy` 四条件/分区、reloader 三分支+gate、`parseJsBool` 全类型、coordinator 对称、`OverlayError` 有无按钮、翻译未配置谓词 | 已覆盖 |
| 变异测试 | `04-mutation.md` | REQ-007 无新可变点；定向 83.3%；存活体 100% 有结论 |

---

## 7. 本阶段新增/修改的测试文件

| 文件 | 变更 |
|---|---|
| `app/test/reader_page_interaction_coverage_test.dart` | **新增**（3 例）：`dismiss` 分支、`onPointerMove` 分支、分页目录切章 `relayoutAfterLoad` 接线（补 `reader_page.dart` 新代码 78.7% → 100%） |

> 生产代码零改动（本阶段仅新增测试文件 + 产出本报告与 `04-mutation.md`）；无 rework 文件。

---

## 8. 闸门4 自评

- [x] **新代码行覆盖率 ≥ 85%**：可测新增/改动 Dart 文件 **142/142 = 100%**（首轮 78.7% 已补测至 100%）
- [x] **关键分支（错误路径/边界）已覆盖**：手势四条件与命中区、重载/样式/幂等、JS 返回值全类型、章内/章末翻页、未配置翻译"去设置"与查词不串扰
- [x] 不可测项（真实 WebView / FRB / FFI 环境 / 真机）逐条说明并给出兜底
- [x] 全量回归绿（222 Rust + 152 Dart，`flutter test` 0 failed）

**闸门4②结论：通过（passed）。**
