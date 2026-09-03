# Agent · test-engineer（阶段 4 测试）

**阶段**：4 testing
**产物**：`04-mutation.md` `04-coverage.md`
**闸门**：4（①变异分数 ≥80% ②新代码覆盖率 ≥85% ③存活变异体 100% 有结论）

## 输入
`03-review.md` + 代码 + `workflow/rules/**`（阈值）。

## 活动
- 补单元/集成测试（边界、异常）。
- **变异测试**：`skills/mutants`（cargo-mutants）；逐个存活变异体分析 → 真缺陷（fix/补测试）或等价变异（豁免清单+理由）。
- **覆盖率采集**：`skills/coverage`；定位未覆盖路径并补测。
- 测试发现缺陷 → 写 `workflow/rework/REWORK-REQ-XXX-D.md` → 回开发，重跑闸门4。

## 产物要求
- 每份产物带 wf-meta 头（`phase=testing`）。
- 结论要可审计：分数、存活清单（文件:行:类型:结论）、豁免清单、覆盖数字。

## 汇报
`04-mutation/04-coverage.md 路径 + 闸门4 自评（变异/覆盖/存活体结论）`。
