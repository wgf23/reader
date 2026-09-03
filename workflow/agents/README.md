# Agents — 多智能体工作流的角色定义

> 每个 Agent = 一个角色 + 阶段 + 职责 + 读/写产物 + 闸门。Orchestrator 派单时按本目录定义下发。
> 命名：`<role>.md`。

| Agent | 阶段 | 责任 | 产物 |
|---|---|---|---|
| [orchestrator](orchestrator.md) | 全程 | 状态机、派单、执行闸门、rework 调度、STATE 唯一写者 | STATE.md |
| [req-analyst](req-analyst.md) | 1 需求 | 需求规格 + 验收标准(可测) | 01-req.md |
| [architect](architect.md) | 2 架构 | 设计 + ADR + 计划拆分 + 冲突检查 | 02-adr/02-design/02-plan.md |
| [developer](developer.md) | 3 开发 | 前置审查 + 按原型实现 + 自检 | 代码 + 03-review.md |
| [test-engineer](test-engineer.md) | 4 测试 | 测试补强 + 变异 + 覆盖分析 | 04-mutation/04-coverage.md |
| [release-manager](release-manager.md) | 5 交付 | 回归 + 发布 + 追溯矩阵 | 05-delivery.md |

## 通用 agent 契约
- **只写本阶段产物**；读 `docs/`、`workflow/` 不受限；不改其他阶段文件。
- 产物第一段必须带 wf-meta 头（见 `../schemas/wf-meta.schema.json`）。
- 完成后汇报：产物路径 + 闸门自评（pass/fail + 依据）。
