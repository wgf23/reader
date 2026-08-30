# bridge/ —— flutter_rust_bridge 桥接

`core/`（Rust）与 `app/`（Flutter）之间的 FFI 绑定。

## 现状（P0 已打通）

- 绑定已生成：`app/lib/src/rust/`（Dart）+ `core/src/frb_generated.rs`（Rust）。
- 桥接 API 面见 `core/src/api.rs`（书架/导入/打开章节），契约以 `docs/03-architecture.md` §4 为准。
- **FFI 端到端已验证**：`app/test/rust_bridge_test.dart` 加载 `libreader_core.so`，
  真实导入《紅樓夢》EPUB 并打开章节（`cargo test` 之外的第二道验收线）。

## 重新生成（API 变更后）

```bash
source /home/heiwa/workspace/.toolchain/env.sh
cd reader
flutter_rust_bridge_codegen generate \
  --rust-input crate::api --rust-root core/ --dart-output app/lib/src/rust/
```

## 构建与运行约定

- Rust 动态库：`cd core && cargo build --release` → `target/release/libreader_core.so`。
- 开发期：Flutter 侧用 `--dart-define=READER_CORE_SO=<绝对路径>` 指定 .so；否则默认找
  可执行目录旁的 `libreader_core.so`。
- 发布期：构建脚本把 `.so` 拷贝到各平台可执行目录旁（Windows 为 `.dll`、macOS 为 `.dylib`）。

```bash
# FFI 端到端测试（需先 cargo build --release）
cd app
READER_CORE_SO=../core/target/release/libreader_core.so flutter test test/rust_bridge_test.dart
```
