//! 全文搜索：FTS5 索引与查询。
//!
//! 设计：docs/04-module-design.md §5（fts_books 虚拟表）、docs/02 §6（<100ms）。

pub struct SearchService;

impl SearchService {
    // TODO(P0):
    //   index_book(book) -> Result<()>    // 入库时构建
    //   query(q, scope) -> Vec<SearchHit>
}
