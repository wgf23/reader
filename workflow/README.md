# Multi-Agent R&D Workflow（本目录）

> 这是**研发工作流的元系统**：多智能体流水线（需求→架构→开发→测试→交付）+ 质量闸门 +
> 可复用的 agents / skills / schemas。它把自己描述为可复用的组件，**可搬到其它 workspace**。

## 目录说明
```
workflow/
├── README.md              ← 本文件：是什么 + 怎么复用
├── porting.md             ← 移植到其它 workspace 的 checklist
├── STATE.md               ← 唯一状态源（orchestrator 写）
├── agents/                ← 角色定义（5 阶段 agent + orchestrator）
├── skills/                ← 可复用能力（每 skill = 命令可执行）
├── schemas/               ← 产物结构契约（wf-meta 头 / 各阶段要素 / 追溯矩阵行）
├── rules/                 ← 阈值（crap-config.toml / ddd-rules.toml，评审后冻结）
├── templates/             ← 各阶段 Markdown 产物模板
├── backlog/               ← 每 REQ 的 5 阶段产物（长期上下文）
├── reports/               ← 闸门执行报告
└── rework/                ← rework 记录
```

## 这套工作流 = 方法论（可复用）+ 工具（可移植，需同技术栈）

**① 方法论部分（在 `workflow/` 内，跨 workspace 通用）**
- 五阶段流水线 + 每阶段 agent 职责 + 闸门 + rework 类型。
- agents/skills/schemas/templates/rules 的定义与契约。
- `.md` 产物模板 + `wf-meta` 头契约 + 追溯矩阵。
- UI 原型一致性（`docs/wireframes/**` 作为 UI 权威规范）的原则。

**② 可执行闸门（依赖 workflow/ 之外）**
- `skills/*` 里的命令指向：`scripts/`（wf-meta-check.py、CRAP、ddd-lint、mutants.sh、cov-summary.py、build-*.sh/ps1）。
- 测试/构建指向项目自身：Rust `core/`（`cargo test`）、Flutter `app/`（`flutter test` / `flutter analyze` / `flutter build`）。
- 原型权威与设计约定：`docs/`（docs/07、docs/08、docs/wireframes/**）。

## 结论（能否搬到别处用）
- 只要新 workspace **保留相同结构**（`workflow/` + `scripts/` + `docs/`，且是 Rust+Flutter 项目），
  复制这四者即可跑通，`workflow/` 是驱动、`scripts/` 是工具、`docs/` 是权威。
- 若**只搬 `workflow/`**：可用它的**方法论**（phase/agent/skill/schema/gate 概念、模板、契约）；
  但 **`scripts/`（工具）与项目栈（`core/`+`app/`）缺失，** 执行闸门的命令会找不到。
  → 需按 `porting.md` 补齐/改写。
- 若新 workspace 是**不同技术栈**：方法（阶段/闸门/产物契约/rework）可复用；`skills` 的
  具体命令（cargo/flutter、ddd-rules 路径、CRAP/ddd-lint、build）需**改写**成你栈的命令。
