# Skill · build-android（Android APK，Linux/WSL）

## 命令
```bash
bash scripts/build-android.sh           # 默认 arm64 APK（Rust 3 ABI 全打包）
bash scripts/build-android.sh --all-abi # Flutter AOT 编 3 ABI（慢）
```
输出归档到 `dist/reader-android-arm64-v<version>.apk`。

## 前置（`scripts/build-android.sh` 头部注释）
- JDK 21（`.toolchain/jdk`）、Android SDK + NDK r27、rustup android targets（3 ABI）、Gradle（wrapper）。
- 插件补丁（flutter_inappwebview / jni / file_picker）由脚本自动打。

## 已知坑
- `set -euo pipefail` 下 `export A=... PATH=$A...` 同句引用未赋值变量会崩 → 已拆成多行。
- gradle `distributionUrl` 行尾不得带注释；官方源在此环境仅 ~2KB/s → 用腾讯镜像
  `https://mirrors.cloud.tencent.com/gradle/gradle-9.3.1-all.zip`（约 58MB/s）。
- `app/android/app/src/main/jniLibs/*/*.so` 是跟踪文件，构建会重生成（core 零改动时内容等价，回退避免噪声）。

## 验证
`aapt dump badging <apk> | grep versionCode`；确认含 `libreader_core.so`（3 ABI）与所需资产。
