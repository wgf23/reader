# fuzz —— 解析器健壮性模糊测试（cargo-fuzz）

设计：docs/05-test-design.md §5。
目标：format::parse（epub/mobi/azw3/txt）喂随机字节 + 变异语料，断言不 panic。

```bash
cargo +nightly install cargo-fuzz
cargo +nightly fuzz run epub_parse      # 种子取自 tests/corpus
```
