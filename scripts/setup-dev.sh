#!/usr/bin/env bash
# reader 开发环境一键搭建（免 sudo、免改系统目录；外网可达时用官方源，不可达自动/手动换国内镜像）
#
# 适用：无 sudo、HOME 只读的容器/沙箱环境（如本项目的开发容器）。
# 工具链全部安装到 <workspace>/.toolchain/ ：
#   rustup + stable Rust
#   gcc-15（apt 免安装提取：apt-get download + dpkg -x）
#   Flutter SDK stable
# 用法：bash reader/scripts/setup-dev.sh
# 之后每个新 shell：source <workspace>/.toolchain/env.sh
set -euo pipefail

WS="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"   # 默认 = 项目根的上两级（workspace）
TC="$WS/.toolchain"
BIN="$TC/bin"
FLUTTER_VERSION="3.47.2"

# ---- 源选择：外网可达用官方；不可达取消注释镜像行 ----
RUSTUP_BASE="https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init"
RUSTUP_DIST="https://static.rust-lang.org"; RUSTUP_UPDATE="https://static.rust-lang.org/rustup"
FLUTTER_BASE="https://storage.googleapis.com/flutter_infra_release"
PUB_BASE="https://pub.dev"
# 国内镜像（备用）：
# RUSTUP_BASE="https://rsproxy.cn/rustup/dist/x86_64-unknown-linux-gnu/rustup-init"
# RUSTUP_DIST="https://rsproxy.cn"; RUSTUP_UPDATE="https://rsproxy.cn/rustup"
# FLUTTER_BASE="https://storage.flutter-io.cn/flutter_infra_release"
# PUB_BASE="https://pub.flutter-io.cn"

mkdir -p "$TC/rustup" "$TC/cargo" "$BIN" "$TC/apt-gcc" "$TC/home" \
         "$TC/xdg-config" "$TC/xdg-cache" "$TC/xdg-data"

cat > "$TC/env.sh" <<ENVEOF
# reader 开发环境。用法：source $TC/env.sh
export TOOLCHAIN_ROOT=$TC
export RUSTUP_HOME=$TC/rustup
export CARGO_HOME=$TC/cargo
export FLUTTER_ROOT=$TC/flutter
export PATH=$BIN:\$CARGO_HOME/bin:\$FLUTTER_ROOT/bin:\$PATH
export HOME=$TC/home
export XDG_CONFIG_HOME=$TC/xdg-config
export XDG_CACHE_HOME=$TC/xdg-cache
export XDG_DATA_HOME=$TC/xdg-data
export RUSTUP_DIST_SERVER=$RUSTUP_DIST
export RUSTUP_UPDATE_ROOT=$RUSTUP_UPDATE
export PUB_HOSTED_URL=$PUB_BASE
export FLUTTER_STORAGE_BASE_URL=$FLUTTER_BASE
export LD_LIBRARY_PATH=$TC/apt-gcc/usr/lib/x86_64-linux-gnu:\$LD_LIBRARY_PATH
ENVEOF

echo "[1/4] Rust（rustup）"
if [ ! -x "$TC/rustup-init" ]; then
  curl -sL --max-time 300 -o "$TC/rustup-init" "$RUSTUP_BASE"
  chmod +x "$TC/rustup-init"
fi
RUSTUP_HOME="$TC/rustup" CARGO_HOME="$TC/cargo" \
RUSTUP_DIST_SERVER="$RUSTUP_DIST" RUSTUP_UPDATE_ROOT="$RUSTUP_UPDATE" \
  "$TC/rustup-init" -y --default-toolchain stable --profile default --no-modify-path

cat > "$TC/cargo/config.toml" <<'CARGOEOF'
[source.crates-io]
replace-with = "rsproxy-sparse"
[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"
[net]
git-fetch-with-cli = true
CARGOEOF

echo "[2/4] C 工具链（gcc-15 免安装提取）"
if [ ! -x "$BIN/gcc" ]; then
  ( cd "$TC/apt-gcc"
    apt-get download gcc-15 gcc-15-x86-64-linux-gnu cpp-15 cpp-15-x86-64-linux-gnu \
      libc6-dev linux-libc-dev libgcc-15-dev libisl23 libmpc3 libmpfr6 libgmp10 >/dev/null
    for f in *.deb; do dpkg -x "$f" .; done )
  REAL=$(find "$TC/apt-gcc" -type f -name 'x86_64-linux-gnu-gcc-15' | head -1)
  cat > "$BIN/gcc" <<GCCEOF
#!/usr/bin/env bash
exec "$REAL" -I"$TC/apt-gcc/usr/include" -I"$TC/apt-gcc/usr/include/x86_64-linux-gnu" -I"$TC/apt-gcc/usr/lib/gcc/x86_64-linux-gnu/15/include" -L"$TC/apt-gcc/usr/lib/x86_64-linux-gnu" "\$@"
GCCEOF
  cat > "$BIN/cc" <<'CCEOF'
#!/usr/bin/env bash
exec /home/heiwa/workspace/.toolchain/bin/gcc "$@"
CCEOF
  chmod +x "$BIN/gcc" "$BIN/cc"
  # libc 链接脚本：运行时 .so 用系统路径，静态 .a 用提取目录
  cat > "$TC/apt-gcc/usr/lib/x86_64-linux-gnu/libc.so" <<LIBCEOF
/* GNU ld script */
OUTPUT_FORMAT(elf64-x86-64)
GROUP ( /lib/x86_64-linux-gnu/libc.so.6 $TC/apt-gcc/usr/lib/x86_64-linux-gnu/libc_nonshared.a AS_NEEDED ( /lib64/ld-linux-x86-64.so.2 ) )
LIBCEOF
fi

echo "[3/4] Flutter SDK（$FLUTTER_VERSION）"
if [ ! -d "$TC/flutter" ]; then
  ARCHIVE="flutter_linux_$FLUTTER_VERSION-stable.tar.xz"
  [ -f "$TC/flutter.tar.xz" ] || curl -sL --max-time 3000 -o "$TC/flutter.tar.xz" \
    "$FLUTTER_BASE/releases/stable/linux/$ARCHIVE"
  tar xJf "$TC/flutter.tar.xz" -C "$TC" && rm "$TC/flutter.tar.xz"
fi

echo "[4/4] 验证"
source "$TC/env.sh"
rustc --version && cargo --version
"$FLUTTER_ROOT/bin/flutter" --version | head -2
"$BIN/cc" --version | head -1
echo "完成。新 shell 使用前请先：source $TC/env.sh"
