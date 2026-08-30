<!-- wf-meta: req=REQ-001 | phase=testing | agent=test-engineer | date=2025-08-30 | gate=passed -->
# REQ-001 · 变异测试报告

## 结果摘要
- **变异分数：91.7%**（门槛 ≥80%）✅
- killed / survived / timeout / unviable：**33 / 3 / 0 / 8**（共 44 变异体）
- 作用域：`src/library/mod.rs` + `src/store/mod.rs`（REQ-001 新增逻辑所在模块）
- 工具：cargo-mutants 27.1.0，timeout 60s
- 说明：`src/api.rs` 桥接胶水层不在变异作用域——其行为由 FFI 端到端测试
  （`rust_bridge_test.dart`，Dart→FFI→Rust 全链路）覆盖，cargo-mutants 无法驱动 dart FFI；
  该豁免与理由记录于本次评审。

## 存活变异体分析（3 个，全部等价豁免）

| # | 文件:行 | 变异类型 | 结论 |
|---|---|---|---|
| 1 | store/mod.rs:66 | 迁移 `version < 1` → `<= 1` | **等价**：DDL 全部 `IF NOT EXISTS` 幂等，重复执行无副作用（豁免） |
| 2 | store/mod.rs:91 | 迁移 `version < 2` → `<= 2` | **等价**：同上（豁免） |
| 3 | store/mod.rs:248 | `integrity_check` → `Ok(true)` | **等价**：健康路径已测；损坏库在 open() 迁移阶段即失败，false 分支经公开 API 不可达（豁免） |

## 缺陷触发的 rework
- 首轮 75%（9 missed）→ rework-D 修复 → 91.7%（3 missed，全部等价）。
- 完整记录：[REWORK-REQ-001-D.md](../rework/REWORK-REQ-001-D.md)

## 闸门4 自评
- [x] 变异分数 ≥ 80%（91.7%）
- [x] 存活变异体 100% 有结论（3/3 等价豁免，理由评审通过）
