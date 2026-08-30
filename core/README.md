# core/ —— Rust 核心库 `reader_core`

解析 / 规范化 / 定位器 / 书库 / 笔记 / 词典翻译 / 搜索 / 存储 / 听书。
设计依据：`docs/03-architecture.md`（架构）、`docs/04-module-design.md`（领域模型与接口）。

## 模块（✅=P0 已实现，⏳=P1）

```
src/
├── lib.rs        # crate 根（模块声明 + 版本常量）
├── api.rs        # flutter_rust_bridge 桥接 API（docs/03 §4）
├── error.rs      # 统一错误类型（不 panic 原则）
├── types.rs      # 共享类型：BookId / Locator / TextAnchor / BookMeta（docs/04 §2–§3）
├── format/       # 格式解析 → ParsedBook
│   ├── epub.rs   # ✅ P0：容器/OPF/spine/导航(nav+NCX 取多者)/章节纯文本/资源收集
│   ├── txt.rs    # ✅ P0：编码探测(UTF-8→GB18030) + 章节切分（第X章/Chapter N）
│   └── mobi/azw3/pdf/fb2/cbz  # ⏳ P1
├── convert/      # ✅ P0：规范化 → 规范 EPUB（mimetype/container/opf/nav/扁平资源重写）
├── locator/      # ⏳ P1：Locator 锚定（类型已就位）
├── library/      # ✅ P0：导入（解析→规范化→入库，SHA-256 去重）/ 列表 / 打开（章节）
├── notes/        # ⏳ P1
├── dict/         # ⏳ P1（含翻译）
├── search/       # ⏳ P1
├── tts/          # ⏳ P1（听书：句切分 + 句↔Locator，docs/04 §9）
└── store/        # ✅ P0：SQLite（WAL / user_version 迁移 v1 / books + book_files）
```

## 测试

- `cargo test`：19 单元测试 + 5 真实语料集成测试（`tests/p0_corpus.rs`）。
- 语料：`tests/corpus/src/`（红楼梦中文 EPUB、傲慢与偏见 EPUB3/TXT，公有领域，来源见
  `tests/corpus/README.md`）。
- FFI 端到端：`../app/test/rust_bridge_test.dart`（见 `../bridge/README.md`）。

## 命令

```bash
cargo check        # 快速校验
cargo test         # 单元 + 语料集成测试
cargo build --release   # 产出 cdylib：target/release/libreader_core.so（桥接用）
cargo bench        # 基准（P1 起，见 docs/05 §4）
```

> `Cargo.toml` 依赖仍为宽松版本约束，P1 首个 `cargo check` 后按需 pin（docs/05 §4 基准门槛）。
