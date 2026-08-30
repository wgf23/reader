#!/usr/bin/env bash
# 构建占位脚本：P0 起逐步填充（见 docs/03-architecture.md §11 与 app/README.md）。
set -euo pipefail

echo "[骨架期] 当前仅验证目录与配置；请按 docs/03 §11 的构建说明操作："
echo "  cd core && cargo check"
echo "  cd app  && flutter create . --platforms=windows,macos,linux,android,ios && flutter pub get"
