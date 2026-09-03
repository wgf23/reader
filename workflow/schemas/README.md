# Schemas — 阶段产物与 wf-meta 的结构契约（JSON Schema）

> 描述每份产物应满足的结构（机器可读、可校验）。产物正文是 Markdown；schema 定义的是
> **wf-meta 头参数**与**各阶段产物的必备要素**，作生成约束 / 校验参考。

| Schema | 定契约 |
|---|---|
| [wf-meta.schema.json](wf-meta.schema.json) | 产物头 `wf-meta` 参数（req/phase/agent/date/gate） |
| [phase-artifacts.schema.json](phase-artifacts.schema.json) | 各 phase 必备产物文件 + 必备内容要素 |
| [traceability.schema.json](traceability.schema.json) | 05-delivery 追溯矩阵行（US→原型→设计→测试→状态） |
