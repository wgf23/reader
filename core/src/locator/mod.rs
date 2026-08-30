//! Locator 锚定：文本锚生成 / 重定位 / 降级链。
//!
//! 设计：docs/04-module-design.md §3。
//! 定位优先级：文本片段锚（重排不失效）→ progression → CFI；PDF：page + rect。

pub struct LocatorResolver;

impl LocatorResolver {
    // TODO(P0):
    //   from_selection(book, selection) -> Result<Locator>
    //   resolve(book, loc) -> Result<ResolvedPosition>
    //   text_at(book, loc) -> Result<String>
}
