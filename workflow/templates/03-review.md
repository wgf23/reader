<!-- wf-meta: req=REQ-XXX | phase=development | agent=developer | date=YYYY-MM-DD | gate=failed -->
# REQ-XXX · 开发前置审查（Pre-Implementation Review）

## 1. 设计与既有约定核对
| 检查项 | 结果 |
|---|---|
| 与 docs/03 分层/架构冲突？ | 无 / 见下 |
| 与 docs/04 Locator/限界上下文冲突？ | 无 / 见下 |
| 与既有 ADR 冲突？ | 无 / 见下 |
| 与既有业务（听读进度/笔记锚定）冲突？ | 无 / 见下 |

## 2. 计划核对
| 检查项 | 结果 |
|---|---|
| 任务缺失 / 依赖环 / 估算离谱？ | 无 / 见下 |

## 3. 需求可测性核对
| 检查项 | 结果 |
|---|---|
| 验收标准可实现且可测？ | 是 / 见下 |

## 4. 结论
- [ ] 通过，进入实现
- [ ] 发现问题 → 触发 rework：类型（A/B/C）见 `workflow/rework/REWORK-REQ-XXX-?.md`

## 5. 实现与自检记录
| Task | 完成 | 测试 | CRAP | DDD |
|---|---|---|---|---|
| T-001 | ✅ | … | PASS | 0 违规 |
