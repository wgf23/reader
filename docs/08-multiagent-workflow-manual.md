# 08 · Multi-Agent 工作流运行手册（Operational Manual）

> 定位：与 `07-dev-workflow.md`（**设计**）互补，本文是**怎么实际跑起来**的运行手册 ——
> 每阶段的产物/闸门/工具命令/子代理派单模板，全部可复制执行。
> 作为长期上下文持久化的「操作说明书」，任何 Agent 或人按本文即可复用这套多智能体流水线。

---

## 1. 流水线一览（一图速览）

```
REQ-XXX ─▶ (1)需求分析 ─▶ (2)架构设计 ─▶ (3)开发 ─▶ (4)测试 ─▶ (5)交付 ─▶ 合并 main
             agent=req-analyst   architect        developer   test-engineer  release-manager
             产物=01-req.md      02-adr/design/   03-review+   04-mutation/   05-delivery.md
                                 plan.md          代码+报告     coverage.md     (含追溯矩阵)
             闸门1               闸门2             闸门3        闸门4           闸门5
```

- 编排者 = 主 Agent（orchestrator），唯一写 `workflow/STATE.md`。
- 每个阶段派一个独立 subagent（后台），仅写本阶段产物文件；靠**文件交接**上下文。
- 分支策略：`git checkout -b wf/REQ-XXX`，闸门全过 `--no-ff` 合入 `main`。

---

## 2. 产物契约与模板

**产物文件头（每份产物第一段，机器可读）**：

```markdown
<!-- wf-meta: req=REQ-XXX | phase=<phase> | agent=<agent> | date=YYYY-MM-DD | gate=passed|failed -->
```

`phase` 必须取自下表（`scripts/wf-meta-check.py` 校验）：

| phase | 产物文件 |
|---|---|
| requirements | `01-req.md` |
| architecture | `02-adr.md` `02-design.md` `02-plan.md` |
| development | `03-review.md`（含 gate3 自评） |
| testing | `04-mutation.md` `04-coverage.md` |
| delivery | `05-delivery.md` |

**模板**：`workflow/templates/`（每阶段一份，直接拷贝再填）。
**校验**：`python3 scripts/wf-meta-check.py workflow`（应输出 `✓ 全部产物头合法`）。

---

## 3. 工具链：构建与闸门命令

> 工具为 Rust 小工具（`scripts/crap/`、`scripts/ddd-lint/`）；先构建一次，之后直接跑。

### 3.1 工具构建
```bash
source /home/heiwa/workspace/.toolchain/env.sh
CARGO_BUILD_JOBS=2 cargo build --release --manifest-path scripts/crap/Cargo.toml
CARGO_BUILD_JOBS=2 cargo build --release --manifest-path scripts/ddd-lint/Cargo.toml
```

### 3.2 校验产物头（wf-meta）
```bash
python3 scripts/wf-meta-check.py workflow            # strict=False（非严格）
python3 scripts/wf-meta-check.py workflow --strict   # 缺产物也报错
```

### 3.3 闸门3 的 CRAP（自研评分）
```bash
# 先出 llvm-cov JSON，再算 CRAP（阈值：FAIL≥25 / WARN≥15，见 workflow/rules/crap-config.toml）
scripts/crap/target/release/crap analyze core/...   # 按工具实际 CLI 调用
```
> 注：门楣= FAIL=0；本工程 core 若零改动（纯 UI REQ），CRAP 无可测新对象，以 `flutter analyze` 替代评估。

### 3.4 闸门3 的 DDD / 分层合规
```bash
scripts/ddd-lint/target/release/ddd-lint check <repo-root> \
  --rules workflow/rules/ddd-rules.toml --out workflow/reports/ddd-<req>.md
# 期望：违规=0
```

### 3.5 闸门4 的变异测试（cargo-mutants）
```bash
source /home/heiwa/workspace/.toolchain/env.sh
cargo install cargo-mutants --version 27.1   # 一次性
bash scripts/mutants.sh                      # 封装：超时/白名单/JSON 报告
# 门槛：变异分数 ≥ 80%；存活体须逐条结论（真缺陷→fix / 等价→豁免清单）
```

### 3.6 闸门4 覆盖率
```bash
cd app && flutter test --coverage            # 生成 coverage/lcov.info
# 用 scripts/cov-summary.py 汇总；新增/改动界面代码行覆盖率 ≥ 85%
```

### 3.7 回归
```bash
cd core && cargo test --release             # Rust 核心全量
cd app  && flutter test                      # Flutter widget + 既有 FFI
cd app  && flutter analyze                   # 0 issues
```

---

## 4. 子代理派单模板（orchestrator 用）

```text
你是 <role>，处理 REQ-XXX 的 <phase> 阶段。
先读：workflow/STATE.md、workflow/backlog/REQ-XXX/（上游产物）、reader/docs/**（设计约定）、
     reader/workflow/rules/**（阈值）、reader/workflow/templates/<file>（产物模板）。
规则：
- 只写本阶段产物文件（<files>）；产物必须带 wf-meta 头；不写/不改其他阶段文件。
- 严格按文档/原型图（prototype 是 UI 权威规范，逐屏对照，禁自创布局）。
- 完成后汇报：产物路径 + 闸门自评（pass/fail + 依据）。
```

> 注意：子代理须用 `run_in_background`（后台）避免阻塞；orchestrator 逐一收结果并执行闸门。
> 若子代理长时间无输出，由 orchestrator 接管（本仓库多次出现子代理停滞，接管策略已固化）。

---

## 5. 闸门清单（orchestrator 逐条复核）

| 闸门 | 验收 |
|---|---|
| 1 | ①验收全可测 ②与既有 REQ 无重复 ③影响面非空 |
| 2 | ①ADR ≥2 备选+理由 ②plan 任务可执行 ③冲突清单为空或已含处置 |
| 3 | ①CRAP FAIL=0 ②DDD 违规=0 ③cargo/flutter 全绿 ④无未处理 rework ⑤原型一致性 deviation=0 |
| 4 | ①变异≥80% ②新代码覆盖≥85% ③存活体 100% 有结论 |
| 5 | ①追溯矩阵全闭合 ②全量回归绿 ③发布产物齐全 |

---

## 6. Rework 类型（带记录，不静默）

| 类型 | 触发 | 回退 |
|---|---|---|
| rework-A | 计划问题 | 架构设计（重出 plan） |
| rework-B | 设计/原型冲突 | 架构/UI 设计（改 ADR/design） |
| rework-C | 需求歧义不可测 | 需求分析 |
| rework-D | 测试发现缺陷 | 开发（修代码+补测试） |
| rework-E | 需求理解偏差 | 需求分析 |

记录：`workflow/rework/REWORK-REQ-XXX-<类型>.md`（问题清单+论证+处置+闸门复跑）。

---

## 7. 当前执行状态（截至本手册）

| 字段 | 值 |
|---|---|
| 已完成 REQ | REQ-001（骨架/分页）、REQ-002（mobi/azw3）、REQ-003（翻译/查词）、REQ-004（阅读器 UI 重构，含内置词典+离线翻译） |
| 分支 | `main`（`wf/REQ-XXX` 已合并） |
| 状态源 | `workflow/STATE.md`（orchestrator 唯一可写） |
| 实测闸门 | 各 REQ 闸门 1-5 通过；ddd-lint 违规=0；flutter analyze 0；cargo 全绿 |

> 更新方式：每完成一个 REQ，orchestrator 更新 `workflow/STATE.md` 并在 `main` 提交；本文 §7 表格同步刷新。
