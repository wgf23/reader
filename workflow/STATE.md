# 工作流状态（唯一状态源 —— 仅 orchestrator 可写，Agent 只读）

| 字段 | 值 |
|---|---|
| 当前阶段 | idle（等待 REQ） |
| 活跃 REQ | — |
| 分支 | main |
| 闸门状态 | — |
| rework 计数 | — |
| 最近事件 | 工作流初始化 |

> 说明：本文件由 orchestrator 维护；各阶段 Agent 只读写自己阶段的产物文件。
