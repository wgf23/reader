# Skill · crap（CRAP 评分）

## 公式（自研，配置在 `workflow/rules/crap-config.toml`）
```
CRAP(f) = CC(f)² × (1 − cov(f))³ + CC(f) + D(f)
```
- `CC` 圈复杂度：`if/else if +1`、`match 每臂 +1`、`loop/while/for +1`、`&&/|| +1`、`? +0.5`、嵌套闭包 +0.5。
- `cov`：函数级行覆盖率（`cargo llvm-cov export --format=json`）。
- `D` 重复惩罚：token 化后 5-gram Jaccard > 0.6 且体长 >30 行 → +15。

## 阈值
| 区间 | 判定 |
|---|---|
| CRAP ≥ 25 | FAIL（必须重写/重构） |
| 15 ≤ CRAP < 25 | WARN（补测试或拆分） |
| CRAP < 15 | PASS |

## 构建 + 运行
```bash
source /home/heiwa/workspace/.toolchain/env.sh
CARGO_BUILD_JOBS=2 cargo build --release --manifest-path scripts/crap/Cargo.toml
# 先出 llvm-cov JSON，再跑：
scripts/crap/target/release/crap <repo-root> [--out workflow/reports/crap-<req>.md]
```
（具体 CLI 以工具 `--help` 为准。）

## 闸门
`FAIL=0`；WARN 数 ≤ 新增行数 1%。**core 零改动（纯 UI REQ）时无可测对象 → 以 `flutter analyze`（0 issues）替代评估。**
