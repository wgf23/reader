# Skill · wf-meta-check（产物头校验）

## 目的
校验每份阶段产物第一段的 `wf-meta` 头（req / phase / agent / date / gate）与阶段对应、格式合法。

## 命令
```bash
python3 scripts/wf-meta-check.py workflow            # 非严格：只查头一致性
python3 scripts/wf-meta-check.py workflow --strict   # 严格：缺产物文件也报错
```

## 期望
`wf-meta ✓ 全部产物头合法`。`phase` 取值必须为：
`requirements | architecture | development | testing | delivery`。

## 产物文件映射（由 PHASES 定义）
```
requirements → 01-req.md
architecture → 02-adr.md, 02-design.md, 02-plan.md
development  → 03-review.md
testing      → 04-mutation.md, 04-coverage.md
delivery     → 05-delivery.md
```
