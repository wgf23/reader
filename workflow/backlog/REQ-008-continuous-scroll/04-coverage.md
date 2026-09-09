<!-- wf-meta: req=REQ-008-continuous-scroll | phase=testing | agent=test-engineer | date=2026-09-09 | gate=passed -->
# REQ-008 · 覆盖率报告（闸门4②）

> 输入：`03-review.md`（gate=passed，commit `7e5d97a`）、代码、`workflow/skills/coverage.md`、`workflow/skills/gates.md`。
> 工具：`flutter test --coverage`（Flutter 3.47.2 / Dart，生成 `app/coverage/lcov.info`）。
> 口径：**新代码 = `git diff main` 新增行 ∩ lcov 可执行行（DA）**；同时给出三文件 whole-file 口径。
> 范围：本 REQ 新增/改动的三个 Dart 文件 `continuous_scroll_policy.dart`、`progress_saver.dart`、`reader_page.dart`
> （`reader_interaction_test.dart`/`screenshots_test.dart` 为测试文件，不计入生产代码覆盖）。
> 原始数据：`workflow/reports/coverage-req008.lcov`；摘要：`workflow/reports/coverage-req008-summary.txt`。

---

## 1. 结论摘要

| 口径 | 覆盖 | 门槛 | 判定 |
|---|---|---|---|
| **新增/改动 Dart 代码（新代码口径，3 文件）** | **256 / 260 = 98.46%** | ≥85% | ✅ |
| 新增/改动 Dart 代码（whole-file 口径，3 文件） | 519 / 546 = 95.05% | 参考 | ✅ |
| `continuous_scroll_policy.dart`（新代码） | 69 / 69 = **100%** | — | ✅ |
| `progress_saver.dart`（新代码） | 23 / 23 = **100%** | — | ✅ |
| `reader_page.dart`（新代码） | 164 / 168 = **97.62%** | — | ✅ |
| Dart 全仓（whole-file） | 1460 / 2614 = 55.9% | 参考 | — |
| Rust 全量测试 | 222 passed / 0 failed | 绿 | ✅ |
| 真实集成测试（未削弱） | 5 passed / 0 failed | 绿 | ✅ |

> **首轮采集**（补测前）：新代码 242/260 = 93.08%，已 ≥85%。本阶段仍补齐 4 个边界/回归分支（见 §4），
> 提升至 **256/260 = 98.46%**。剩余 4 行均有结论（§4），无未知未测路径。

---

## 2. 采集命令与工具口径说明

```bash
export PATH="/root/flutter/bin:$HOME/.cargo/bin:$PATH"
cd /root/reader/app && flutter test --coverage        # → app/coverage/lcov.info
# 逐文件/新代码统计（lcov 解析；见下）
cd /root/reader && git diff --stat main -- core/       # 空（core 零改动，另见 04-mutation.md）
```

- `scripts/cov-summary.py` 面向 `cargo llvm-cov` 的 JSON（`data[0].files`），**不能解析 lcov**（实测抛
  `json.decoder.JSONDecodeError`）。本报告改用等价的 lcov 解析（`LF/LH/DA` 按文件汇总）+ `git diff` 新增行取交集，
  口径与 REQ-007 `04-coverage.md` 一致，并如实登记该工具差异。
- 新代码口径：新增行中仅统计 lcov 有 `DA` 记录的可执行行（注释/空行/`const` 声明等不计入分母）。
- 不可测项按 `skills/coverage.md` 排除（§5）。

---

## 3. 新增/改动 Dart 文件覆盖率表

### 3.1 新代码口径（主口径）

| # | 文件 | diff 新增行 | 新增可执行行 | 已覆盖 | 新代码行覆盖 |
|---|---|---|---|---|---|
| 1 | `lib/pages/continuous_scroll_policy.dart` | 228 | 69 | 69 | **100.00%** |
| 2 | `lib/pages/progress_saver.dart` | 65 | 23 | 23 | **100.00%** |
| 3 | `lib/pages/reader_page.dart` | 279 | 168 | 164 | **97.62%** |
| — | **合计** | 572 | **260** | **256** | **98.46% ✅** |

### 3.2 whole-file 口径（参考）

| # | 文件 | 行覆盖 | 覆盖率 |
|---|---|---|---|
| 1 | `lib/pages/continuous_scroll_policy.dart` | 69 / 69 | 100.00% |
| 2 | `lib/pages/progress_saver.dart` | 23 / 23 | 100.00% |
| 3 | `lib/pages/reader_page.dart` | 427 / 454 | 94.05% |
| — | **合计** | **519 / 546** | **95.05%** |

> `reader_page.dart` whole-file 未覆盖 27 行中，仅 4 行为本 REQ 新增（318–320、395，见 §4）；
> 其余 23 行为**既有**代码（如 `_onProgressSeek` 分页分支 391/393/394/396、默认 `PagedWebView` 构建器
> 764/767/768/774、翻译/查词错误分支 580–584、`_themeForPaged` 896–900 等），不属本 REQ 新代码口径。

---

## 4. 未覆盖热点逐一分析与本阶段补测

### 4.1 剩余新增未覆盖行（4 行，100% 有结论）

| 文件:行 | 代码 | 结论 |
|---|---|---|
| `reader_page.dart:318-320` | `_scrollToChapter` 兜底：`_chapterIndex=target; _chapterProgress=p; _chapterLocked=true;` | **防御兜底分支，widget 测试不构造**：仅当"目标章未构建 → 按章序比例估算 → 最多 `min(章数,50)` 次 0.8 视口步进"仍无法 `ensureVisible` 到目标章时执行（保证不崩溃/状态一致）。构造该场景需病态不均匀书 + 依赖 SliverList 惰性估算，且会引入脆弱断言；本阶段已覆盖其**可达主路径**（311–315 有界步进，见 §4.2 #3）。兜底本身为 no-crash 保险，由集成 US-4/真机 US-13 覆盖。 |
| `reader_page.dart:395` | `_onProgressSeek` 分页分支 `state.gotoPage(target)` | **固有不可测**：分页分支取 `_pagedKey.currentState`（真实 `PagedWebViewState`），`flutter_inappwebview` 无 Linux 实现，widget 测试经 `pagedViewBuilder` 注入 fake 构建器，无法挂载真实 state。由真机 US-13⑤（分页进度条拖动）覆盖。滚动分支同一函数已覆盖。 |

### 4.2 本阶段补测（新增 `app/test/reader_continuous_scroll_coverage_test.dart`，5 例，未改生产代码）

| 新增用例 | 覆盖/守住的点 |
|---|---|
| `ChapterContentCache maxAttempts=0：provider 零调用且返回有界失败` | `continuous_scroll_policy.dart:60-65`（`attempts >= maxAttempts` 防御分支；provider 调用有界，US-10） |
| `向后回滚且 current 不在已构建集合 → 取最靠上的已构建章` | `continuous_scroll_policy.dart:156`（`_geometryOf` 为 null 的向后回滚分支，US-6） |
| `恢复定位到未构建的远章：有界步进最终落到目标章` | `reader_page.dart:311-315`（`_scrollToChapter` 惰性列表有界步进；首章极短使估算偏小，强制走步进） |
| `分页模式 onProgress 回调 → _saveProgress 立即落盘` | `reader_page.dart:343-348`（分页进度回调接线，US-9 回归） |
| `分页模式听书返回 → _reloadProgress 分页重排接线` | `reader_page.dart:512`（分页 `relayoutAfterLoad` 接线，US-8/US-9 回归） |

> 补测**仅新增**文件与断言；既有 `reader_continuous_scroll_test.dart`（8 例）、`continuous_scroll_policy_test.dart`
> （29 例）、`progress_saver_test.dart`（5 例）、`reader_page_test.dart`（18 例）等断言**零改动、未削弱**。

### 4.3 关键边界/异常覆盖核对（US 维度）

| US | 关键分支 | 覆盖证据 |
|---|---|---|
| US-3 | 尾沿防抖 300ms、flush 取消挂起、dispose 释放、debounce 可注入、flush 无挂起值 | `progress_saver_test.dart` 5 例；`ProgressSaver` 23/23 |
| US-4 | 章起点 + 章内比例恢复、远章有界步进 | 集成 US-4 + 本阶段远章恢复用例 |
| US-6 | 顶部锚点/±8px 迟滞/触底/空 built/current 未构建 | `continuous_scroll_policy_test.dart` + 本阶段 #2 |
| US-7 | 上一章/目录跳转定位 + 立即落盘 | widget US-7；集成 US-1/2 |
| US-10 | 失败记忆化、provider ≤1 次/章、显式 retry 有界、maxAttempts 边界 | widget US-10 + 本阶段 #1 |
| US-11 | 50 章仅构建 ≤3 | widget US-11 |
| US-9 | 书签幂等、分页↔滚动互切、分页 onProgress/重排接线 | widget US-9 + 本阶段 #4/#5 |

---

## 5. 不可测项说明

| 项 | 说明 | 兜底 |
|---|---|---|
| `lib/engines/paged_web_view.dart`（whole-file 2/97） | 真实 `InAppWebView` 平台视图，`flutter_inappwebview` 无 Linux 实现，widget 测试经 `pagedViewBuilder` 注入 fake，不实例化真实 WebView，属**固有不可测**。 | 真机 US-13⑤；分页可测出口（`paged_document_reloader`/`paged_js_result`/`paged_view_controls`）均 100%（REQ-007 已交付）。 |
| `reader_page.dart:395`（分页 `_onProgressSeek`） | 同上，需真实 `PagedWebViewState`。 | 真机 US-13⑤。 |
| `lib/src/rust/**`（FRB 生成物） | 代码生成，不计入口径。 | codegen 幂等（`git status app/lib/src/rust/` 为空）。 |
| FFI 4 例（无 `.so` 时 skip） | 普通 `flutter test` 无 `libreader_core.so` → `markTestSkipped`（本次 198 passed / 4 skipped）。 | 带 `READER_CORE_SO` 环境可跑；REQ-006 已端到端覆盖。 |
| `integration_test/*.dart` | `flutter test --coverage` 不含集成测试，不计入 lcov。 | 单独 `xvfb-run -a flutter test integration_test/reader_continuous_scroll_test.dart -d linux`：**5 passed / 0 failed**（本阶段复核）。 |
| US-13 真机项 | 滚动到底自动衔接/末章停止/重开恢复/听读一致/书签分页 | `03-review.md §5` 人工清单；阶段 5b 执行。 |

---

## 6. 回归与门禁自检

| 检查 | 命令 | 结果 |
|---|---|---|
| Flutter 全量 + 覆盖 | `cd app && flutter test --coverage` | **198 passed / 4 skipped / 0 failed**（补测前 193，+5） |
| 新增/改动 Dart 新代码行覆盖 | 本报告 §3.1 | **256/260 = 98.46% ≥ 85%** ✅ |
| Flutter 静态分析 | `cd app && flutter analyze` | **No issues found!**（0 issues） |
| Rust 全量单测 | `cd core && CARGO_BUILD_JOBS=2 cargo test --release` | **222 passed / 0 failed** |
| 真实集成（US-1/2/3/4/8） | `xvfb-run -a flutter test integration_test/reader_continuous_scroll_test.dart -d linux` | **5 passed / 0 failed** |
| 静态守卫（未削弱） | `cd app && flutter test test/no_synthetic_chrome_test.dart` | **1 passed**（`integration_test/*.dart` 禁合成 Chrome） |
| 变异测试 | `04-mutation.md` | core 零改动 → 无新可变点；沿用基线 REQ-003 98.5% / REQ-006 99.17%（保守 98.33%） |

---

## 7. 本阶段新增/修改的测试文件

| 文件 | 变更 |
|---|---|
| `app/test/reader_continuous_scroll_coverage_test.dart` | **新增**（5 例）：`ChapterContentCache` 边界、`resolveVisibleChapter` 回滚未构建、远章恢复有界步进、分页 `onProgress` 落盘、分页听书返回重排 |

> 生产代码零改动（`git diff main -- app/lib/` 与 `03-review.md` 一致，本阶段未新增改动）；无 rework 文件。
> 未改动 `app/integration_test/**`、`app/test/no_synthetic_chrome_test.dart`（守卫保持原样）。

---

## 8. 闸门4 自评

- [x] **新代码行覆盖率 ≥ 85%**：**256/260 = 98.46%**（三文件：100% / 100% / 97.62%）；补测前 93.08% 已达标，本阶段补至 98.46%
- [x] **关键分支（错误路径/边界）已覆盖**：尾沿防抖/flush/dispose、可见章迟滞/触底/回滚/未构建、失败记忆化与有界重试、maxAttempts 边界、远章有界步进、分页进度落盘与重排接线
- [x] 不可测项（真实 WebView、FRB 生成物、FFI 环境、集成测试口径、真机）逐条说明并给出兜底
- [x] 全量回归绿（222 Rust + 198 Dart + 5 集成 + analyze 0），既有断言/守卫零削弱

**闸门4②结论：通过（passed）。**
