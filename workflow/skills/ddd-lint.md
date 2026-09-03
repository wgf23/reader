# Skill · ddd-lint（DDD / 分层合规）

## 目的
静态检查 `.rs`/.dart 的 `use`/`import` 依赖是否违反 `workflow/rules/ddd-rules.toml` 的层规则。

## 构建 + 运行
```bash
source /home/heiwa/workspace/.toolchain/env.sh
CARGO_BUILD_JOBS=2 cargo build --release --manifest-path scripts/ddd-lint/Cargo.toml
scripts/ddd-lint/target/release/ddd-lint check <repo-root> \
  --rules workflow/rules/ddd-rules.toml --out workflow/reports/ddd-<req>.md
```

## 期望
```text
[ddd-lint] 报告已写入 ...（违规=0）
```
**违规=0** 才过闸门3。

## 规则表（`workflow/rules/ddd-rules.toml`，评审后冻结）
- interface：`core/src/api.rs`、`app/lib/pages`、`app/lib/engines`；禁止 `import src/rust/**`（只能经 services）。
- application：`core/src/library`、`app/lib/services`；禁 `rusqlite/zip/quick-xml`。
- domain：`core/src/format|convert|locator|notes|dict|search|tts|types|error`；禁 `crate::store|api|library`。
- infrastructure：`core/src/store`、`app/lib/src/rust`；禁依赖 domain 业务模块。

> `app/lib/widgets/**` 未声明属任何层（设计取舍，见 02-design §9），按「架构纪律」人工核对 import 面。
