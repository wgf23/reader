#!/usr/bin/env bash
# 变异测试封装（docs/07 §7）：cargo-mutants 运行 + 报告生成。
#
# 用法：
#   bash scripts/mutants.sh core [--output-dir <dir>] [--timeout <sec>]
# 说明：
#   - 全量变异较慢（分钟级），日常用 --since 或模块过滤（增量）；合入前跑全量。
#   - 报告：<output-dir>/mutation-report.md + summary（killed/survived/timeout）。
#   - 门槛由测试阶段（闸门4）依据报告判定：score >= 80%。
set -euo pipefail

# 工具链与仓库根可配置/自动推导（便于迁移到其它 workspace）
TC="${TOOLCHAIN_ROOT:-/home/heiwa/workspace/.toolchain}"
source "$TC/env.sh"

TARGET="${1:-core}"
shift || true
OUT_DIR="${OUT_DIR:-workflow/reports}"
TIMEOUT="${TIMEOUT:-60}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/$TARGET"

mkdir -p "$OUT_DIR"
echo "[mutants] 开始变异测试（timeout=${TIMEOUT}s）…"
cargo mutants --timeout "$TIMEOUT" "$@" 2>&1 | tee "$OUT_DIR/mutants.log"

# 汇总（cargo-mutants 摘要形如 "Mutations: X killed, Y survived, Z timeout"）
SUMMARY=$(grep -E 'killed|survived|timeout' "$OUT_DIR/mutants.log" | tail -5 || true)
{
  echo "# 变异测试报告"
  echo
  echo "> 时间: $(date '+%Y-%m-%d %H:%M:%S') ｜ 目标: $TARGET"
  echo
  echo '```'
  echo "$SUMMARY"
  echo '```'
  echo
  echo "## 存活/超时变异体分析"
  echo
  echo "> 由 test-engineer 逐个给出结论（真缺陷 → 修复；等价 → 豁免并注明理由），"
  echo "> 结论追加在 REWORK-REQ-xxx-D.md 或 04-mutation-report.md。"
} > "$OUT_DIR/mutation-report.md"

echo "[mutants] 报告: $OUT_DIR/mutation-report.md"
