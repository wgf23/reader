# app/ —— Flutter 应用壳

UI（页面/组件）+ 渲染层（WebView 分页、PDF）+ 服务层（桥接薄封装）。

## 目录

```
lib/
├── main.dart            # 应用根（MaterialApp，落到书架页）
├── pages/               # 书架✅ / 阅读器✅(滚动模式) / 导入 / 搜索 / 笔记 / 听书（占位）
├── widgets/             # 复用组件（骨架期空）
├── services/            # LibraryBackend 抽象 + RustLibraryBackend（flutter_rust_bridge）
├── engines/             # ReflowEngine/TtsEngine 接口（P1 实现 WebView 版）
├── src/rust/            # flutter_rust_bridge 生成绑定（勿手改；重新生成见 bridge/README.md）
└── i18n/                # 文案资源（骨架期空）
```

## P0 状态

- 书架页真实接入 Rust 书库（`LibraryBackend` 抽象，测试注入 Fake）。
- 阅读器页滚动模式渲染章节纯文本 + 章节切换；WebView 分页为 P1。
- `flutter analyze` 0 问题；widget 测试通过；FFI 端到端测试见 `test/rust_bridge_test.dart`。

## 首次搭建 / 运行

```bash
# 生成平台壳（已生成过可跳过；会覆盖 pubspec 则先备份，见项目根 README）
flutter create . --platforms=windows,macos,linux,android,ios --project-name reader_app --org com.reader
flutter pub get
# Rust 核心
cd ../core && cargo build --release
# 桌面运行（需要系统 GTK 等桌面库；无显示环境用测试验证）
cd ../app && flutter test
READER_CORE_SO=../core/target/release/libreader_core.so flutter test test/rust_bridge_test.dart
```
