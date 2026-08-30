# Reader —— 跨平台电子书阅读器

> PC 优先（Windows / macOS / Linux → 后续 Android / iOS）的**离线优先**阅读器。
> 核心卖点：**笔记**（高亮/划线/批注）、**翻译**（离线词典 + 在线翻译）与**听书**（番茄小说式：系统 TTS 离线朗读、听读同进度、定时关闭、后台播放）；约束：**性能**与**体积**。
> 本期范围不含 Kindle、KFX、DRM。

## 目录结构

| 目录 | 内容 |
|---|---|
| [`docs/`](docs/00-README.md) | 设计文档集 v1.0（用户故事 / 技术 / 架构 / 模块设计 / 测试 / 低保真线框） |
| [`app/`](app/README.md) | Flutter 应用壳（UI + 渲染层 + 服务层） |
| [`core/`](core/README.md) | Rust 核心库 `reader_core`（解析 / 规范化 / 定位器 / 笔记 / 词典 / 搜索 / 存储） |
| [`bridge/`](bridge/README.md) | flutter_rust_bridge 桥接（生成物目录 + 说明） |
| [`assets/`](assets/README.md) | 图标 / 默认字体 / 内置小词典 |
| [`scripts/`](scripts/README.md) | 构建与发布脚本 |

## 当前状态

- **设计**：v1.2（含听书），见 `docs/`。
- **代码**：**P0 垂直切片已完成并测试通过**：
  - `core/`：EPUB/TXT 解析、规范 EPUB 转换、SQLite 书库（导入/列表/打开/去重）；`cargo test` 19 单测 + 5 真实语料集成测试全绿；
  - 桥接：flutter_rust_bridge 绑定已生成（`app/lib/src/rust/`），FFI 端到端测试（真实中文 EPUB 导入）通过；
  - `app/`：书架页（真实书库 + 导入入口 + 错误处理）与阅读器页（滚动模式 + 章节切换），`flutter analyze` 0 问题、widget 测试通过。
- 下一步（P1）：PDF/MOBI/AZW3、笔记、翻译词典、WebView 分页渲染、听书。

## 快速开始（骨架验证）

```bash
# 0) 开发环境（首次，一次性）：国内镜像一键搭建（rustup/gcc/Flutter 装到 <workspace>/.toolchain）
bash scripts/setup-dev.sh
source /home/heiwa/workspace/.toolchain/env.sh      # 之后每个新 shell 都先执行这句

# 1) Rust 核心（首次会拉取依赖；版本为骨架占位，P0 首个 cargo check 后按需 pin）
cd core && cargo check && cargo test

# 2) Flutter 应用
cd app
flutter create . --platforms=windows,macos,linux,android,ios   # 生成平台壳
flutter pub get
flutter test                                              # 骨架冒烟测试
flutter run -d windows                                    # 运行（桌面需 GTK/clang 等系统库）
```

> 说明：本容器无 sudo 且 HOME 只读，工具链统一装在 `<workspace>/.toolchain/`，走国内镜像
> （Rust: rsproxy.cn；Flutter/Pub: flutter-io.cn），crates 源替换见 `$CARGO_HOME/config.toml`。
> `flutter create .` 可能覆盖 `pubspec.yaml`，若被覆盖按 `docs/02-technical.md` §8 依赖清单恢复。

## 工程约定

1. **设计先行**：功能实现前先在 `docs/` 更新/补充对应设计。
2. **核心进 Rust**：所有格式与业务逻辑放 `core/`；UI 只经 `app/lib/services/` 调桥接，禁止直接碰 FFI。
3. **失败不崩溃**：核心层任何输入都走 `Result`，坏文件给明确错误。
4. **离线优先**：除用户主动配置的在线翻译外，无任何网络依赖。
