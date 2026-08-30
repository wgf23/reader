# 工作流状态（唯一状态源 —— 仅 orchestrator 可写，Agent 只读）

| 字段 | 值 |
|---|---|
| 当前阶段 | architecture（闸门1、闸门2 已过，等待开发） |
| 活跃 REQ | REQ-001-webview |
| 分支 | wf/REQ-001-webview |
| 闸门状态 | 闸门1 ✅ 闸门2 ✅（ADR/design/plan 齐备） |
| rework 计数 | 0 |
| 最近事件 | REQ-001 阶段1/2 产物落盘并提交；下一步：阶段3 开发（T-001 → T-004） |

> 说明：本文件由 orchestrator 维护；各阶段 Agent 只读写自己阶段的产物文件。
