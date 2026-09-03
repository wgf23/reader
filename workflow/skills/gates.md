# Skill · gates（闸门 1-5 执行）

> orchestrator 逐条执行并**独立复验**（不采信子代理自评）。

## 前置
```bash
source /home/heiwa/workspace/.toolchain/env.sh
```

## 闸门1（需求）
- `01-req.md` 存在 + wf-meta 头合法（`skills/wf-meta-check`）。
- 验收标准全部可断言（无"体验好"类词）；与既有 REQ 无重复；影响面非空。

## 闸门2（架构）
- `02-adr/02-design/02-plan.md` 存在 + 头合法。
- ADR 每决策点 ≥2 备选 + 理由；plan 每任务 ≤1 天 + 验收；冲突清单为空或已含处置。

## 闸门3（开发）
```bash
cd core && CARGO_BUILD_JOBS=2 cargo test --release   # 全绿
cd app  && flutter test                               # 全绿
cd app  && flutter analyze                            # 0 issues
scripts/ddd-lint/... check <root> --rules workflow/rules/ddd-rules.toml  # 违规=0
# CRAP：core 若零改动则 N/A，以 flutter analyze 替代；有改动则按 skills/crap
# 原型一致性：skills/prototype-conformance（deviation=0）
```

## 闸门4（测试）
- 变异分数 ≥80%（`skills/mutants`）；新代码覆盖率 ≥85%（`skills/coverage`）；存活体 100% 有结论。

## 闸门5（交付）
- `05-delivery.md` 追溯矩阵全闭合；全量回归绿；发布产物齐全。
