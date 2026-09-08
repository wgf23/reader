#!/usr/bin/env bash
# ui-screenshots.sh —— 产真实 UI 截图 + 生成产品预览对照报告（供 opencode / CI / 人工一键调用）
#
# 用法：
#   bash scripts/ui-screenshots.sh [REQ-XXX]
# 产物：
#   app/screenshots/*.png                                 真实引擎渲染截图（非 widget golden 占位）
#   workflow/backlog/<REQ>/product-preview-<REQ>.html     设计稿↔实现 对照报告（浏览器打开）
#
# 说明：脚本自包含工具链 PATH（本机安装路径），不依赖调用方 shell 环境，opencode/CI 可直接跑。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ---- 工具链（本机安装路径；可用同名环境变量覆盖）----
export FLUTTER_ROOT="${FLUTTER_ROOT:-/root/flutter}"
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export PATH="$FLUTTER_ROOT/bin:$CARGO_HOME/bin:/usr/local/bin:$PATH"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"

REQ="${1:-REQ-004}"
# 定位 backlog 目录：支持传 REQ-004 或完整目录名 REQ-004-reader-ui
BDIR="$(ls -d workflow/backlog/${REQ}* 2>/dev/null | head -1 || true)"
[ -z "$BDIR" ] && BDIR="workflow/backlog/$REQ"
MANIFEST="$BDIR/product-preview.manifest.json"
OUT="$BDIR/product-preview-$(basename "$BDIR").html"

echo "[1/4] 构建 Rust core（libreader_core.so）"
( cd core && cargo build )

echo "[2/4] 集成测试截图（Linux desktop + xvfb 无头）"
( cd app && xvfb-run -a flutter test integration_test/screenshots_test.dart -d linux )

echo "[3/4] 生成产品预览对照报告"
if [ ! -f "$MANIFEST" ]; then
  echo "!! 缺少清单 $MANIFEST —— 跳过报告生成（请先按 skills/product-preview.md 编写清单）" >&2
  exit 2
fi
python3 scripts/product-preview.py "$MANIFEST" -o "$OUT"

echo "[4/4] 完成 ✅"
echo "  截图：$ROOT/app/screenshots/"
echo "  报告：$ROOT/$OUT"
