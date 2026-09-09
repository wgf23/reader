<!-- wf-meta: req=REQ-008-continuous-scroll | phase=testing | agent=test-engineer | date=2026-09-09 | gate=passed -->
# REQ-008 · 变异测试报告（闸门4①③）

> 输入：`03-review.md`（gate=passed，commit `7e5d97a`）、代码、`workflow/skills/mutants.md`、`workflow/skills/gates.md`。
> 工具：cargo-mutants 27.1.0 / rustc（与 REQ-006/007 同环境）。
> 范围：REQ-008 是**纯 Flutter/UI 连续滚动 REQ**，生产改动全部在 `app/lib/pages/**`；`core/**` **零改动**。

---

## 1. 结果摘要

| 指标 | 数值 | 门槛 | 判定 |
|---|---|---|---|
| **本 REQ 新增 Rust 可变异点** | **0 个**（`core/**` 对 `main` 零 diff） | — | ✅ 无可变异点 |
| 沿用基线①（REQ-003 全 scope） | **132 / 134 = 98.5%**（保守口径；报告值） | ≥80% | ✅ |
| 沿用基线②（REQ-006 全 scope） | **119 / 120 = 99.17%**（保守 98.33%） | ≥80% | ✅ |
| 沿用基线③（REQ-007 定向重跑 `translate_auto`） | **5 / 6 = 83.3%**；基线 98.33% | ≥80% | ✅ |
| 本 REQ 存活变异体 | **0 个**（N/A：本 REQ 无新增 Rust 变异点） | 100% 有结论 | ✅（空集） |
| timeout / unviable | N/A（未新增运行） | — | — |

> **关键结论**：REQ-008 未改 `core/**` 任何字节，cargo-mutants 面向 Rust 主代码**无新增可变异点**；
> 按 `skills/mutants.md`「core 零改动（纯 UI REQ）→ 无可变异点 → 沿用既有分数，不重复跑全量」执行。
> Dart/Flutter 侧本项目**未配置 Dart mutation 工具**（`scripts/mutants.sh` 封装 cargo-mutants，Rust-only），
> Dart 质量由覆盖率（`04-coverage.md`，新代码 98.46%）+ `flutter analyze`（0 issues）+ 全绿测试承担。

---

## 2. 证据：`core/**` 对 `main` 零改动

```bash
cd /root/reader
git diff --stat main -- core/      # → 无输出（空）
git status --short core/           # → 无输出（空）
```

真实输出（本阶段执行）：

```
=== core diff vs main (expect empty) ===
=== core status ===
```

即 `core/**` 与 `main`（`edfd10f`，REQ-007 已合并）**逐字节一致**，因此 cargo-mutants 的变异体集合与
`main` 完全一致，本 REQ 未引入任何新变异点。

### 2.1 `cargo mutants --list` 佐证（不跑测试，秒级）

```bash
cd /root/reader/core && cargo mutants --list | wc -l   # → 1345
```

- 全 core 枚举 **1345** 个变异体，均为**既有**（`core` 与 `main` 一致，无新增）。
- 与 REQ-006/007 基线逐文件计数比对（证明相关文件变异体集合未变）：

| 范围 | 本阶段 `--list` | REQ-006 基线 | 结论 |
|---|---|---|---|
| `src/dict/translation.rs` | 102 | 102 | 一致 |
| `src/dict/provider.rs` + `src/dict/mod.rs` | 31 | 31 | 一致 |
| `src/store/translation.rs`（regex `DEFAULT_PROVIDER\|default_provider\|set_default_provider`） | 3 | 3 | 一致 |
| `src/api.rs`（regex `translate_get_config\|translate_set_strategy\|translate\b`） | 3 | 3 | 一致 |

> `--list` 输出落 `/tmp/opencode/mut-list-req008.txt`（1345 行）；计数与 REQ-006 基线一致，佐证 core 未变。

---

## 3. 沿用基线分数明细（引用既有可审计报告）

| 基线 | 报告 | 分数 | killed / survived / timeout | 说明 |
|---|---|---|---|---|
| REQ-003 | `workflow/backlog/REQ-003-translate/04-mutation.md` | **98.5%** | 132 / 4 / 2（A 片 2 个 missed 保守计存活未复跑） | 全 scope；豁免 2 个等价变异（`translation.rs:121` 日志-only、`:336` `>=` no-op） |
| REQ-006 | `workflow/backlog/REQ-006-tts-online-translate/04-mutation.md` | **99.17%**（保守 98.33%） | 119 / 1 / 2（unviable 17） | 全 scope；存活 1 个等价豁免 + 2 timeout 死循环有结论 |
| REQ-007 | `workflow/backlog/REQ-007-reader-interaction-fixes/04-mutation.md` | 定向 **83.3%** / 基线 98.33% | 5 / 1 / 0（+1 unviable） | 仅字符串字面量改动，无新可变点；定向重跑佐证 |

> 三条基线均 ≥80%。REQ-008 沿用其中最新的 core 全 scope 基线（REQ-006 99.17% / 保守 98.33%），
> 并以 REQ-003 98.5% 交叉印证；未变更的 core 不重复跑全量（`skills/mutants.md` 明确规定）。

---

## 4. 存活变异体分析

**N/A —— 本 REQ 无新增 Rust 变异点，故无本 REQ 的存活变异体。**

| # | 文件:行 | 变异类型 | 结论 |
|---|---|---|---|
| — | — | — | 本 REQ 无新增 Rust 变异点；既有存活/超时变异体见 §3 引用的 REQ-003/006/007 报告（均已 100% 给出结论） |

> 存活体结论覆盖率：**0 / 0 = 100%（空集）**。若把沿用基线的既有存活体计入，其结论见对应报告，
> 全部为「等价豁免」或「死循环 timeout」并有理由，无"0 结论"存活体。

---

## 5. 豁免清单

**N/A（本 REQ 无新增变异体，故无新增豁免）。**

既有豁免（沿用，不属本 REQ）：

| 文件:行 | 变异 | 豁免理由 | 出处 |
|---|---|---|---|
| `core/src/dict/translation.rs:351:16` | `> with >=` | `len==64` 时 `truncate(64)` 为 no-op，行为等价 | REQ-006 §6 |
| `core/src/dict/translation.rs:121` | `!= with ==` | 仅控制 advisory 日志，API 可观察状态不变 | REQ-003 §4 |

---

## 6. Dart/Flutter 侧说明（与闸门4①③的关系）

- 本 REQ 生产代码全在 Dart：新增 `continuous_scroll_policy.dart`（228 行）、`progress_saver.dart`（65 行）、
  改 `reader_page.dart`（+279 行）。
- 当前仓库无 Dart mutation 工具；cargo-mutants 仅覆盖 Rust。按 REQ-004（纯 UI REQ）先例，
  Dart 侧以 `flutter test --coverage`（新代码 **98.46%**）+ `flutter analyze`（0 issues）+ 全量/集成测试全绿
  替代评估（详见 `04-coverage.md`）。
- 本阶段补测 5 例（`app/test/reader_continuous_scroll_coverage_test.dart`），覆盖 `maxAttempts` 边界、
  可见章回滚未构建、远章有界步进、分页进度落盘/重排接线；未改生产代码。

---

## 7. 缺陷触发的 rework

- [x] 无（本 REQ 无新增 Rust 变异点；测试阶段未发现生产缺陷）
- [ ] 有 → REWORK-REQ-008-D.md

> **无 rework-D**。测试补强为覆盖边界（新增测试文件），非缺陷修复。

---

## 8. 闸门4 自评

- [x] **变异分数 ≥ 80%**：本 REQ 无新增 Rust 变异点（`git diff --stat main -- core/` 为空）；
  沿用基线 REQ-003 **98.5%**、REQ-006 **99.17%**（保守 98.33%）、REQ-007 定向 **83.3%**，均 ≥80%
- [x] **存活变异体 100% 有结论**：本 REQ 存活体 **0 个（空集，N/A）**；沿用基线既有存活/超时体结论见引用报告，无遗漏
- [x] 证据可审计：core 零 diff 命令输出 + `cargo mutants --list` 1345 与逐文件基线计数比对
- [x] 范围限定清晰：纯 Dart REQ，Dart mutation 工具缺失以覆盖率/analyze/全绿测试替代，先例一致

**闸门4①③结论：通过（passed）。**
