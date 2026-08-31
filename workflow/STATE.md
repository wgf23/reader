# 工作流状态（唯一状态源 —— 仅 orchestrator 可写，Agent 只读）

| 字段 | 值 |
|---|---|
| 当前阶段 | REQ-002 阶段5 交付（闸门1-4 ✅） |
| 活跃 REQ | REQ-002-mobi-azw3 |
| 分支 | wf/REQ-002-mobi-azw3 |
| 闸门状态 | 闸门1-4 ✅（真 agent：req-analyst/architect/developer/test-engineer，orchestrator 逐一独立复验）｜ 闸门5 待跑 |
| rework 计数 | 1（REWORK-REQ-002-D：变异 77.7%→94.8%，16 测试缺口闭环，5 等价豁免） |
| 最近事件 | 阶段4 test-engineer 完成（降载模式，多次 WSL 中断后幂等重跑成功）：覆盖率 97.7%、变异 94.8%；派阶段5 release-manager |
