# 07 · Multi-Agent 开发工作流设计（v1.0 草案）

> 目标：把"需求 → 架构 → 开发 → 测试 → 交付"做成**可审计、可复现、带质量闸门**的
> 多 Agent 流水线；每个阶段都有产物落盘（长期上下文持久化）；质量护栏包括
> **变异测试**、**自研 CRAP 评分**、**DDD/分层合规检测**；开发前置审查触发 **rework 环**。
>
> 本文是工作流本身的设计（先评审，后实现）。实现物（脚本/工具/目录骨架）见 §10 实现计划。

---

## 1. 设计目标与原则

| # | 原则 | 含义 |
|---|---|---|
| 1 | **产物即记忆** | Agent 之间不靠对话传递上下文，一切写入工作区文件；任何 Agent 可随时从头读取重建上下文 |
| 2 | **质量闸门前置** | 每个阶段有可自动执行的出口标准，不达标不进下一阶段 |
| 3 | **严格但不教条** | 变异测试、CRAP、DDD 合规都以"可配置阈值 + 机器可读报告"落地，阈值可评审调整 |
| 4 | **rework 是流程的一部分** | 开发前置审查发现问题不是失败，而是标准回退路径（带记录） |
| 5 | **可追溯** | 需求 ↔ 设计 ↔ 任务 ↔ 代码 ↔ 测试 ↔ 发布，全程可追踪（追溯矩阵） |

---

## 2. 总体流水线

```
   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
   │ 需求分析   │──▶│ 架构设计   │──▶│ 开发      │──▶│ 测试      │──▶│ 交付      │
   │(1)        │    │(2)        │    │(3)        │    │(4)        │    │(5)        │
   └──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
        │               │  ▲            │  ▲                           │
        │ 闸门1         │ 闸门2         │ 闸门3(CRAP+DDD+测试)         │ 闸门4(变异+覆盖)
        ▼               ▼  │            ▼  │                           ▼
   REQ 产物          ADR/设计/计划  代码+报告+测试                   变异报告      发布+追溯矩阵
                         │            │
                         └── rework 环 ┘
        rework-A: 计划问题(任务拆分/依赖) ──▶ 回 架构设计
        rework-B: 设计与既有业务冲突      ──▶ 回 架构设计(改 ADR)
        rework-C: 需求歧义/验收不可测     ──▶ 回 需求分析
```

- **粒度**：流水线以"需求项（REQ-XXX）"为单位推进；一个 REQ 走完五阶段即闭合。
- **编排者**：主 Agent 担任 Orchestrator，维护 `workflow/STATE.md`，逐个阶段派出执行 Agent、
  执行闸门；每阶段结束更新 STATE 并进入下一阶段（或触发 rework）。
- **并行**：多 REQ 可并行（互不依赖时）；REQ 内部的批量扫描/变异分析可用 workflow 工具 fan-out。

---

## 3. 长期上下文持久化（workflow/ 目录契约）

```
reader/workflow/                     # 工作流工作区（.gitignore 之外的提交物）
├── STATE.md                         # 唯一状态源：当前阶段/活跃 REQ/闸门结果/rework 记录
├── rules/                           # 流水线自身配置（评审后冻结）
│   ├── ddd-rules.toml               # 分层依赖规则（§6）
│   └── crap-config.toml             # CRAP 公式与阈值（§5）
├── backlog/                         # 需求池
│   └── REQ-001-xxx/                 # 每需求一个目录，含全部阶段产物
│       ├── 01-req.md                # 需求分析产物（闸门1）
│       ├── 02-adr.md                # 架构决策记录
│       ├── 02-design.md             # 模块/接口/数据模型设计
│       ├── 02-plan.md               # 计划拆分（任务分解 + 依赖 + 估算）
│       ├── 03-review.md             # 开发前置审查记录（通过/问题→rework）
│       ├── 03-crap-report.md        # CRAP 评分报告
│       ├── 03-ddd-report.md         # DDD/分层合规报告
│       ├── 04-mutation-report.md    # 变异测试报告
│       ├── 04-coverage-report.md    # 覆盖率报告
│       └── 05-delivery.md           # 交付/发布说明 + 追溯矩阵
└── rework/                          # rework 记录（跨 REQ 可查）
    └── REWORK-REQ-001-B.md          # 类型-B 冲突记录
```

**产物文件头契约**（每个产物第一段固定格式，机器可读）：

```markdown
<!-- wf-meta: req=REQ-001 | phase=architecture | agent=architect | date=2025-xx-xx | gate=passed|failed -->
```

**读写约定**：Agent 只允许写自己阶段的文件；读不受限（docs/、workflow/ 全部可读）；
Orchestrator 是唯一允许写 STATE.md 的角色。此约定保证"长期上下文"不被污染。

---

## 4. 各阶段详设

### 4.1 阶段 1 · 需求分析（Requirements）

| 项 | 内容 |
|---|---|
| Agent | `req-analyst`（需求分析师） |
| 输入 | 用户原始诉求（backlog）、既有 docs/（用户故事/验收标准风格） |
| 活动 | 澄清拆分；写需求规格；验收标准（Given/When/Then）；影响分析（对既有功能/数据模型/听读进度的冲突面） |
| 产物 | `01-req.md`：背景/目标/用户故事/验收标准(可测)/优先级/依赖/风险/影响面 |
| 闸门1 | ① 验收标准全部可测（无"体验好"这类不可测词）；② 与既有 REQ 无重复；③ 影响面清单非空 |

> 用户要求"每完成一个需求分析都需要有产物" → `01-req.md` 是强制产物，无它闸门1 不通过。

### 4.2 阶段 2 · 架构设计（Architecture，含计划拆分）

| 项 | 内容 |
|---|---|
| Agent | `architect`（架构师） |
| 输入 | `01-req.md`、docs/（03 架构、04 领域设计、既有 ADR） |
| 活动 | ① 方案设计：模块/接口签名/数据模型/时序；② **计划拆分**：任务分解（Task-001…n，依赖图，估算，验收）；③ **冲突检查**：与既有业务（Locator 不变式、限界上下文、听读同进度、docs/ 约定）比对，输出冲突清单 |
| 产物 | `02-adr.md`（决策记录：方案/备选/理由/影响）；`02-design.md`（接口与数据设计）；`02-plan.md`（任务拆分） |
| 闸门2 | ① ADR 有 ≥2 个备选并给出选择理由；② plan 任务粒度可执行（每任务 ≤1 天、有验收）；③ 冲突清单为空或已含处置方案 |

### 4.3 阶段 3 · 开发（Development，含前置审查 + 质量自检）

**第一步：前置审查（Pre-Implementation Review）→ rework 触发点**

开发 Agent 拿到 `02-*.md` 后，先产出 `03-review.md`，逐项核对：

| 检查项 | 判定 | 问题 → |
|---|---|---|
| 设计与 docs/03、docs/04 既有约定冲突？（层、Locator、进度模型） | 冲突清单 | rework-B → 回架构设计 |
| 计划拆分是否有问题（任务缺失/依赖环/估算离谱）？ | 问题清单 | rework-A → 回架构设计 |
| 需求验收标准是否可实现/可测？ | 歧义清单 | rework-C → 回需求分析 |
| 是否影响既有功能（回归面）？ | 回归清单 | 并入开发任务 |
| **实现是否与交互原型图一致？**（`docs/wireframes/**` 是 UI 交互的**权威规范**；涉及 UI 的 REQ 必须指定对应原型图并逐屏对照，禁止对布局/交互自由发挥） | 偏差清单（逐屏：少做/做错/发明新交互） | rework-B → 回架构/UI 设计；偏差须在 03-review 记录并被修复 |

> **教训固化**：凡是涉及页面的 REQ，`02-adr/02-design` 必须引用具体原型图（如
> `docs/wireframes/reader-ui-v2/*`）；`developer` 严格逐屏实现原型，**不得自创布局**
> （此前 REQ-001 曾违反自己产出的线框 [REQ-001 教训]）。

**第二步：实现 + 自检循环**

```
实现(按 plan 任务) → 单元/集成测试 → CRAP 评分 → DDD 合规 → 不达标 → 重写/重构 → 复评
                    └─ 逐屏对照原型图（开发自检 + 人工复核）
```

| 项 | 内容 |
|---|---|
| Agent | `developer`（开发者） |
| 产物 | 代码（提交）+ `03-crap-report.md` + `03-ddd-report.md` + `03-review.md` |
| 闸门3 | ① CRAP FAIL=0（§5）；② DDD 违规=0（§6）；③ `cargo test` + Flutter 测试全绿；④ 无未处理 rework；⑤ **原型一致性通过**（orchestrator 逐屏对照 `docs/wireframes/**` 指定的原型图核对实现，deviation=0） |

### 4.4 阶段 4 · 测试（Testing）

| 项 | 内容 |
|---|---|
| Agent | `test-engineer`（测试工程师） |
| 活动 | ① 补充单元/集成测试（边界、异常）；② **变异测试**（§7）；③ 覆盖率采集；④ 对"存活变异体"逐一分析（真缺陷→补测试/修代码；等价变异→列入豁免清单并注明理由） |
| 产物 | `04-mutation-report.md`（变异分数/存活清单/分析结论）；`04-coverage-report.md` |
| 闸门4 | ① 变异分数 ≥ 阈值（默认 80%，§7）；② 新代码覆盖率 ≥ 阈值（默认行 85%）；③ 存活变异体 100% 有结论（修复或豁免） |
| 缺陷处置 | 测试发现缺陷 → 写 `REWORK-REQ-xxx-D.md` → 回开发修复 → 重跑测试与闸门4（§8） |

### 4.5 阶段 5 · 交付（Delivery）

| 项 | 内容 |
|---|---|
| Agent | `release-manager`（发布经理） |
| 活动 | 全量回归（cargo test + flutter test + FFI 端到端 + 变异抽查）；变更说明；版本号（语义化）；发布产物清单；**追溯矩阵闭合** |
| 产物 | `05-delivery.md`：验证结果汇总 / 发布说明 / 已知问题 / 追溯矩阵表 |
| 闸门5 | ① 追溯矩阵全闭合（每条验收标准 → 测试证据）；② 全量回归绿；③ 发布产物齐全 |

---

## 5. 自研 CRAP 评分脚本设计（scripts/crap/）

**背景**：CRAP（Change Risk Anti-Patterns）经典公式为
`CRAP = CC² × (1 − cov)³ + CC`（CC=圈复杂度，cov=行覆盖率）。我们按 Rust 项目定制：

**输入**：`src/**/*.rs`（或指定变更集）+ `cargo llvm-cov export --format=json`（函数级覆盖）。

**工具实现**（Rust 小工具，`scripts/crap/`，依赖 syn/walkdir/serde_json）：
1. **圈复杂度 CC(f)**：用 `syn` 解析函数体统计分支点——
   `if/else if +1`、`match 每 arm +1`、`loop/while/for +1`、`&&/|| +1`、`? 运算符 +0.5`、`嵌套闭包 +0.5`；
2. **覆盖率 cov(f)**：llvm-cov JSON 的 functions 数组按符号名（demangle 后）匹配函数；
3. **重复惩罚 D(f)**：函数体 token 化后取 5-gram，任意两函数 Jaccard 相似度 > 0.6 且体长 > 30 行 → `D=15`；

**公式（自研，配置可调）**：

```
CRAP(f) = CC(f)² × (1 − cov(f))³ + CC(f) + D(f)
```

**阈值**（crap-config.toml）：

| 区间 | 判定 |
|---|---|
| CRAP ≥ 25 | **FAIL**：必须重写/重构（拆函数、消重复） |
| 15 ≤ CRAP < 25 | WARN：补测试 或 拆分 |
| CRAP < 15 | PASS |

**报告**：`03-crap-report.md`（函数表格：CC/cov/CRAP/判定/优化建议）+ `crap.json`（CI 机器门槛）。
**CI**：`FAIL=0` 且 `WARN` 数量 ≤ 新增行数的 1% 才通过。

---

## 6. DDD / 分层合规检测设计（scripts/ddd-lint/）

**背景**：Rust 无 ArchUnit；自研静态检查工具（syn 解析 `use` 语句 + 规则表声明）。

**规则声明**（`ddd-rules.toml`，按本工程真实架构声明，评审后冻结）：

| 层 | 覆盖路径 | 允许依赖（内部） | 禁止（外部/内部） |
|---|---|---|---|
| interface | `core/src/api.rs`、`app/lib/pages/**`、`app/lib/engines/**` | 全部内部 | `app/pages` 禁止 `import src/rust/**`（只能经 services） |
| application | `core/src/library/**`、`app/lib/services/**` | domain | 禁止 `use rusqlite/zip/quick-xml` 等基础设施 crate |
| domain | `core/src/format|convert|locator|notes|dict|search|tts|types|error` | 仅 domain 内部 | 禁止 `crate::store`、`crate::api` |
| infrastructure | `core/src/store/**`、`app/lib/src/rust/**`（生成） | error/types | 禁止依赖 domain 业务模块 |

**检查逻辑**（逐 .rs/.dart 文件）：
1. 解析 `use reader_core::xxx::…` / `import '…src/rust/…'`；
2. 按文件所属层查规则表 → 违规则记录 `文件:行:规则:说明`；
3. 输出 `03-ddd-report.md` + `ddd.json`；CI 门槛：违规=0。

**可扩展**：规则表支持追加自定义规则（如"领域层禁止 `unwrap()`"、"api 层函数必须返回 Result"），
lint 只做机械校验，规则本身由架构评审维护。

---

## 7. 变异测试设计（Testing 阶段核心）

**工具**：Rust 生态标准 `cargo-mutants`（支持超时、白名单、JSON 输出）。

| 项 | 设计 |
|---|---|
| 范围 | 默认全量；增量模式（`--since` 或只变异变更相关模块）用于日常，合入前全量 |
| 门槛 | **变异分数 ≥ 80%**（killed / (killed+survived)）；未覆盖变异体（timeout）单独列示 |
| 存活分析 | 每个存活变异体必须给出结论：① 真缺陷 → 补测试或修代码；② 等价变异 → 加入 `mutants-allowlist` 并注明理由（评审过） |
| 报告 | `04-mutation-report.md`：总分/存活清单（文件:行:变异类型:结论）/豁免清单 |
| 超时 | 单变异体超时 60s；防"测试太慢拖死全量" |
| 备注 | cargo-mutants 全量较慢（分钟级），CI 放 nightly 或 PR 合入前 gate |

---

## 8. Rework 机制详设

> **总原则：任何阶段发现的问题（含测试阶段）都必须走 rework 流程，且必须有记录文件。**
> 记录统一存放 `workflow/rework/REWORK-REQ-xxx-<类型>.md`，含：问题清单、双方论证、处置、
> 回退后的闸门复跑结果。

| 类型 | 触发 | 回退目标 | 典型来源 |
|---|---|---|---|
| rework-A | 计划问题：任务缺失/依赖环/估算离谱 | 架构设计（重出 plan） | 开发前置审查（03-review） |
| rework-B | 设计冲突：与既有业务/ADR/docs 约定冲突 | 架构设计（改 ADR/design） | 开发前置审查（03-review） |
| rework-C | 需求歧义：验收不可测/自相矛盾 | 需求分析（改 01-req.md） | 开发前置审查 / 测试阶段 |
| **rework-D** | **测试发现的缺陷**：单元/集成/变异测试失败、功能不符验收标准 | **开发阶段**（修代码 + 补/改测试） | 测试阶段（闸门4 前） |
| **rework-E** | 测试暴露需求理解偏差（验收标准与用户意图不符） | **需求分析**（改 01-req.md 后重走） | 测试阶段 |

- rework-D 是测试阶段的标准闭环：变异测试存活体判定为"真缺陷"、集成测试失败、行为与验收标准不符，
  一律先写 `REWORK-REQ-xxx-D.md` 再回开发修复；修复后回到测试阶段重跑对应测试与闸门4。
- rework 必须**带记录**（问题清单 + 双方论证 + 处置），不静默重做；
- 同一 REQ rework 次数计入 STATE.md，>3 次触发 Orchestrator 人工介入；
- rework 后重新走对应闸门，不跳级。

---

## 9. 编排与 Agent 设计

### 9.1 角色表

| 角色 | 阶段 | 职责 | 输出 |
|---|---|---|---|
| orchestrator（主 Agent） | 全程 | 状态机、派单、执行闸门、rework 调度 | STATE.md |
| req-analyst | 1 | 需求规格与验收 | 01-req.md |
| architect | 2 | 设计 + 计划拆分 + 冲突检查 | 02-*.md |
| developer | 3 | 前置审查 + 实现 + 自检 | 代码 + 03-*.md |
| test-engineer | 4 | 测试补强 + 变异 + 覆盖分析 | 04-*.md |
| release-manager | 5 | 回归 + 发布 + 追溯矩阵 | 05-delivery.md |

### 9.2 Agent prompt 模板（每个执行 Agent 固定前缀）

```
你是 <role>，处理 REQ-XXX 的 <phase> 阶段。
先读：workflow/STATE.md、workflow/backlog/REQ-XXX/（上游产物）、reader/docs/（设计约定）、reader/workflow/rules/（阈值）
规则：只写本阶段产物文件；产物必须带 wf-meta 头；不修改其他阶段文件。
产出：<files>。完成后汇报：产物路径 + 闸门自评结果。
```

### 9.3 闸门执行

- 自动闸门（可脚本化）：文件存在性 + `cargo test`/`flutter test` + crap/ddd/变异命令的退出码；
- 评审闸门：Orchestrator（或抽查子 Agent）对产物做人工式评审（如 ADR 备选充分性、存活变异体结论合理性）。

### 9.4 workflow 工具映射

- 单 REQ 流水线：Orchestrator 逐阶段派 subagent（每阶段一个后台 subagent），靠文件交接；
- 批量 fan-out：多文件 CRAP 扫描、变异体存活分析、多 REQ 并行 → 用 `workflow` 工具脚本
  （pipeline/parallel + schema 校验产物结构）。

---

## 10. 实现计划（评审通过后执行）

| # | 实现物 | 位置 |
|---|---|---|
| 1 | workflow/ 目录骨架 + STATE.md 模板 + wf-meta 校验脚本 | `reader/workflow/`、`reader/scripts/wf-meta-check.py` |
| 2 | CRAP 工具（Rust，syn + llvm-cov json + n-gram 重复检测） | `reader/scripts/crap/`（cargo 子工具） |
| 3 | DDD lint 工具（Rust，syn + ddd-rules.toml） | `reader/scripts/ddd-lint/` |
| 4 | 变异测试封装脚本（cargo-mutants 包装 + 报告模板 + 豁免清单） | `reader/scripts/mutants.sh` |
| 5 | 阶段产物模板（01-req/02-adr/02-design/02-plan/03-review/04-mutation/05-delivery 的 markdown 模板） | `reader/workflow/templates/` |
| 6 | 试点：拿一个真实需求（建议 P1 的"WebView 分页渲染"或"笔记高亮"）跑通全流水线 | workflow/backlog/REQ-001 |

## 11. 与既有工程的关系

- 流水线**不改变** docs/ 设计文档的权威性：ADR 是对 docs/ 的增量决策，冲突以 docs/ + ADR 为准；
- 既有测试资产（19 单测 + 5 语料 + FFI 端到端）作为阶段 4 的基线回归集；
- 质量门槛不降低既有标准（语料测试、FFI 测试照常必须全绿）。

## 12. 决策确认记录（评审结论）

| 决策点 | 结论 | 状态 |
|---|---|---|
| CRAP 公式与阈值 | `CC²(1−cov)³ + CC + D`，FAIL≥25 / WARN≥15 | ✅ 接受现状 |
| 变异分数门槛 | 80%（变更模块增量跑 + 合入前全量） | ✅ 接受现状 |
| DDD 规则表 | 按 §6 表声明（interface/application/domain/infrastructure） | ✅ 接受现状 |
| 试点需求 | **REQ-001：WebView 分页渲染** | ✅ 已定 |
| 工具实现语言 | **Rust 小工具**（CRAP / DDD lint） | ✅ 已定 |
| 测试缺陷 rework | 新增 rework-D / rework-E，全部带记录（§8） | ✅ 已定 |
| Git 分支策略 | 见 §13 | ✅ 已定 |

## 13. Git 分支与提交策略

```
main                          # 主干：只收已过全部闸门的合并
└── wf/REQ-XXX                # 每个需求一条工作流分支（§2 流水线在此分支上跑）
    ├── 阶段产物随分支提交（workflow/backlog/REQ-XXX/**）
    ├── rework 记录随分支提交（workflow/rework/**）
    └── 闸门全过后 --no-ff 合并回 main，合并信息引用 REQ 与交付产物
```

- **每次跑工作流新建分支**：`git checkout -b wf/REQ-XXX`（基于最新 main）。
- 一个 REQ 一次流水线 = 一个分支；rework 在同一分支上继续，不另开分支。
- 产物与代码同分支提交，保证"需求→代码→测试→交付"在提交历史上可追溯。
- 合并条件：闸门 1–5 全过 + `05-delivery.md` 追溯矩阵闭合。
- `git remote` 后续再加（当前仅本地仓库）。

---

## 待评审决策点（请确认）

~~1. CRAP 公式与阈值~~ ✅ 已确认（接受现状）
~~2. 变异分数门槛 80%~~ ✅ 已确认
~~3. DDD 规则表~~ ✅ 已确认
~~4. 试点需求（WebView 分页渲染）~~ ✅ 已确认
~~5. 工具实现语言（Rust 小工具）~~ ✅ 已确认
