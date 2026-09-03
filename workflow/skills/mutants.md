# Skill · mutants（变异测试，cargo-mutants 27.1）

## 目的
对 Rust 主代码注入变异体，验证测试能否"杀死"它们，衡量测试质量。

## 前置 + 运行
```bash
source /home/heiwa/workspace/.toolchain/env.sh
cargo install cargo-mutants --version 27.1          # 一次性
CARGO_BUILD_JOBS=2 bash scripts/mutants.sh          # 封装：超时/白名单/JSON 报告
```

## 门槛
- **变异分数 ≥ 80%**：`killed / (killed + survived)`。
- 未覆盖（timeout）变异体单独列示。
- 每个存活体必须给结论：① 真缺陷 → 补测试/修代码；② 等价变异 → 加入豁免清单 + 理由（评审过）。

## 报告
`04-mutation.md`：总分 / 存活清单（文件:行:变异类型:结论）/ 豁免清单。
> 注意：`pkill -f 'cargo-mutants'` 会自匹配其命令行（曾致误杀）；用精确 job 管理。

## 平台注意
- 变体耗时：全量分钟级，放 CI nightly 或合入前 gate。
- **core 零改动（纯 UI REQ）** → 无可变异点 → 沿用既有分数（如 REQ-003 已 98.5%），不重复跑。
