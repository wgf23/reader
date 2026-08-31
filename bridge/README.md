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
- 开发期：Flutter 侧用 `--dart-define=READER_CORE_SO=<绝对路径>` 指定 .so；否则按平台默认名
  （Windows: `reader_core.dll` / macOS: `libreader_core.dylib` / Linux·Android: `libreader_core.so`；
  Android 走 frb 默认 loader，.so 由 build-android.sh 打进 jniLibs）。
- 发布期：
  - **Android**：`bash scripts/build-android.sh`（交叉编译 3 ABI → jniLibs → APK，含第三方插件补丁）；
  - **Windows**：在 Windows 上执行 `scripts/build-windows.ps1`（产出 zip 免安装包，.so 随包分发）。

```bash
# FFI 端到端测试（需先 cargo build --release）
cd app
READER_CORE_SO=../core/target/release/libreader_core.so flutter test test/rust_bridge_test.dart
```
