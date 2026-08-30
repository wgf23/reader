//! 笔记：高亮 / 划线 / 批注 / 书签 + 导出（Markdown / JSON）。
//!
//! 设计：docs/04-module-design.md §4–§7（annotations 表、领域规则 §8）。
//! 锚定：本模块只消费 `Locator`，不关心具体格式。

pub struct AnnotationService;

impl AnnotationService {
    // TODO(P0):
    //   create(book, selection, kind, color, note_text) -> NoteId
    //   update(id, patch) / delete(id)
    //   list(book_id) -> Vec<Annotation>
    //   resolve(note_id) -> Locator
    //   export(book_id, fmt, out_path) -> ExportSummary
}
