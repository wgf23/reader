#!/usr/bin/env bash
# build-android.sh —— 在 Linux/WSL 上构建 Android APK（含第三方插件补丁）
#
# 前置（一次性，见 .toolchain 说明）：
#   - JDK 21（.toolchain/jdk）、Android SDK + NDK r27（.toolchain/android-sdk）
#   - rustup android targets（aarch64-linux-android 等）
#   - Gradle 发行版：wrapper 默认走官方源；网络受限时手动下载 gradle-9.3.1-all.zip
#     并改 app/android/gradle/wrapper/gradle-wrapper.properties 的 distributionUrl 为
#     file:///…/gradle.zip（构建完成后建议改回官方 URL 再提交）
# 用法：bash scripts/build-android.sh [--all-abi]
#   --all-abi：Flutter AOT 编 3 个 ABI（慢）；默认只编 arm64（Rust 库仍全 ABI 打包）
set -euo pipefail

TC=/home/heiwa/workspace/.toolchain
source "$TC/env.sh"
export JAVA_HOME=$TC/jdk PATH=$JAVA_HOME/bin:$PATH
export ANDROID_SDK_ROOT=$TC/android-sdk ANDROID_HOME=$ANDROID_SDK_ROOT
export GRADLE_USER_HOME=$TC/gradle-home
export CARGO_BUILD_JOBS=2

ROOT=$(cd "$(dirname "$0")/.." && pwd)
NDK=$ANDROID_SDK_ROOT/android-ndk-r27
TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/linux-x86_64
export PATH=$TOOLCHAIN/bin:$PATH

# 1) 第三方插件补丁（pub-cache；flutter pub get 重新拉依赖后需重打）
PATCHED=0
patch_file() { # $1=file $2=from $3=to
  if grep -qF "$2" "$1"; then sed -i "s|$2|$3|" "$1" && PATCHED=1; fi
}
PUB=$HOME/.pub-cache/hosted/pub.dev
patch_file "$PUB/flutter_inappwebview_android-1.1.3/android/build.gradle" \
  "getDefaultProguardFile('proguard-android.txt')" \
  "getDefaultProguardFile('proguard-android-optimize.txt')"
patch_file "$PUB/jni-1.0.3/android/build.gradle" \
  "ndkVersion flutter.ndkVersion" 'ndkVersion "27.0.12077973"'
patch_file "$PUB/file_picker-8.3.7/android/build.gradle" \
  "compileSdk 34" "compileSdk 36"
[ $PATCHED -eq 1 ] && echo "[patch] 已应用插件构建补丁" || echo "[patch] 补丁已就位（或插件版本变化，请检查）"

# 2) Rust 交叉编译（3 ABI）
cd "$ROOT/core"
declare -A CCS=( [aarch64-linux-android]=aarch64-linux-android21-clang \
                 [armv7-linux-androideabi]=armv7a-linux-androideabi21-clang \
                 [x86_64-linux-android]=x86_64-linux-android21-clang )
for t in aarch64-linux-android armv7-linux-androideabi x86_64-linux-android; do
  t_u=${t//-/_}; cc=${CCS[$t]}
  export CC_$t_u=$TOOLCHAIN/bin/$cc AR_$t_u=$TOOLCHAIN/bin/llvm-ar
  export CARGO_TARGET_${t_u^^}_LINKER=$TOOLCHAIN/bin/$cc
  echo "[cargo] $t …"
  cargo build --release --target $t
done

# 3) 拷贝 .so 到 jniLibs
JNI="$ROOT/app/android/app/src/main/jniLibs"
mkdir -p "$JNI/arm64-v8a" "$JNI/armeabi-v7a" "$JNI/x86_64"
cp "$ROOT/core/target/aarch64-linux-android/release/libreader_core.so" "$JNI/arm64-v8a/"
cp "$ROOT/core/target/armv7-linux-androideabi/release/libreader_core.so" "$JNI/armeabi-v7a/"
cp "$ROOT/core/target/x86_64-linux-android/release/libreader_core.so" "$JNI/x86_64/"

# 4) Flutter APK
cd "$ROOT/app"
if [ "${1:-}" = "--all-abi" ]; then
  flutter build apk --release --split-per-abi
else
  flutter build apk --release --target-platform android-arm64
fi

# 5) 归档
mkdir -p "$ROOT/dist"
VER=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)
cp build/app/outputs/flutter-apk/app-release.apk "$ROOT/dist/reader-android-arm64-v${VER}.apk"
echo "✅ 产物：$ROOT/dist/reader-android-arm64-v${VER}.apk"
