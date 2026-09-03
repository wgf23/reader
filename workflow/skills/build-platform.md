# Skill · build-platform（macOS / Windows）

## macOS（Linux 可交叉；zip）
```bash
source /home/heiwa/workspace/.toolchain/env.sh
bash scripts/build.sh       # 产出 dist/ 下的 macOS zip
```

## Windows 安装器
```bash
# 需 Windows 宿主（WSL 无法交叉编译 MSVC）
powershell -File scripts/build-windows.ps1
```
> 说明：WSL 无法交叉编译 MSVC，Windows 包须在 Windows 上跑 `build-windows.ps1`；
> macOS zip 可由 build.sh 在 Linux/WSL 交叉产出。

## 验收
- 产物存在 + 版本号正确 + 包含 Rust 核心 `.so/.dll/.dylib`。
- 安装后可启动、导入书、打开阅读、查词/翻译。
