# Porting Guide — 把本工作流搬到其它 workspace

> 分两种目标：**A. 换到同栈项目**（Rust core + Flutter app，保留结构）与 **B. 只搬方法论**（不同栈/只拿 workflow/）。

---

## A. 同栈项目（Rust core + Flutter app）：复制 + 改 3 处

### 1. 要复制的内容
```
<new-ws>/
├── workflow/      ← 本目录（agents/skills/schemas/rules/templates/STATE）
├── scripts/       ← 工具（wf-meta-check.py、crap/、ddd-lint/、mutants.sh、cov-summary.py、build-*.sh）
├── docs/          ← docs/07、docs/08（工作流文档）与 docs/wireframes/**（UI 权威）
├── core/          ← Rust 核心（cargo test 目标）
└── app/           ← Flutter 应用（flutter test / analyze / build 目标）
```
> 注意：`workflow/skills/*` 用**相对路径**引用 `workflow/rules`、`scripts/`、`docs/`，因此只要这几者
> 位于同一 workspace 根下即无需改路径。

### 2. 必改的 3 处硬编码
| 文件 | 现状 | 改法 |
|---|---|---|
| `scripts/mutants.sh` | `source /home/heiwa/workspace/.toolchain/env.sh`、`cd /home/heiwa/workspace/reader/$TARGET` | 换成本环境的工具链 source 与 `$(dirname $0)/..` 仓库根 |
| `scripts/build-android.sh` | `TC=/home/heiwa/workspace/.toolchain` | 换成新 toolchain 路径（或用 `$TOOLCHAIN_ROOT` 环境变量） |
| `scripts/setup-dev.sh` | 硬编码 `.toolchain`、`reader/` | 换成新路径/项目名 |

### 3. 需按新项目调整
- `workflow/rules/ddd-rules.toml`：把 `core/src/api.rs`、`app/lib/pages`、`app/lib/services`…改为新项目的真实模块路径（若层结构一致可不变）。
- `workflow/schemas/phase-artifacts.schema.json`、`traceability.schema.json`：字段/名称如与项目用语不同则调整。
- `app/pubspec.yaml` 版本、`assets/` 等由项目决定。

### 4. 工具构建（新 workspace 一次性）
```bash
source <new-toolchain>/env.sh
CARGO_BUILD_JOBS=2 cargo build --release --manifest-path scripts/crap/Cargo.toml
CARGO_BUILD_JOBS=2 cargo build --release --manifest-path scripts/ddd-lint/Cargo.toml
```
（若想摆脱此 Rust 小工具，可改成其它语言/工具的等价命令，见 B。）

---

## B. 只搬方法论（不同栈 / 只拿 `workflow/`）

此时**保留 agents/skills/schemas/templates/rules**，但 `skills/*` 里的**具体命令**需按你栈改写：

| Skill | 原命令 | 适用新栈时 |
|---|---|---|
| gates | `cargo test` / `flutter test` / `flutter analyze` | 换成你的测试/静态检查命令 |
| crap | `scripts/crap`（Rust CC/覆盖） | 换成你语言的复杂度/覆盖工具，或仅作为"复杂度+低覆盖→风险"的**概念**沿用 |
| ddd-lint | `scripts/ddd-lint`（Rust syn 解析 use） | 换成你语言的等价依赖检查，或按你的层规则人工核对 |
| mutants | `cargo-mutants` | 换成你栈的变异测试；无则跳过（此闸门非硬性） |
| coverage | `flutter test --coverage` | 换成你栈的覆盖工具 |
| wf-meta-check | `scripts/wf-meta-check.py` | 保留（纯 python，无栈依赖）——它是**跨栈可用**的 |
| prototype-conformance | `docs/wireframes/**` 逐屏 | 换成你项目的 UI 权威规范位置 |
| build-* | Flutter/Rust | 换成你栈的构建 |

> 关键：**方法（阶段/闸门/产物契约/rework/可追溯）是栈无关的**，可复用的正是它。
> 只有"执行工具的命令"是栈特定的，需替换。

---

## 建议
想**跨栈复用最快**：把 `wf-meta-check.py`（纯 python）+ `workflow/schemas/*.json`（JSON Schema）+ 
`workflow/templates/*.md` + `workflow/agents/*.md` 搬走，它们几乎零依赖；再把 `skills/gates.md` 的
"命令"列改成你栈的命令即可。这样新 workspace 立刻有一套**可执行的研发工作流**。
