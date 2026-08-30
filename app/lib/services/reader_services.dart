/// UI 与 Rust 核心之间的服务层（薄封装，UI 不直接触碰 FFI）。
///
/// 设计：docs/03-architecture.md §4（桥接 API 面）。
/// 骨架期仅声明接口；P0 经 flutter_rust_bridge 实现（生成物见 ../bridge）。
abstract class LibraryService {
  Future<List<String>> listBooks();
  Future<String> importFiles(List<String> paths);
  // TODO(P0): importFolder / remove / updateMeta / importStatus
}

abstract class NoteService {
  Future<void> createHighlight(String bookId, String snippet);
  Future<List<String>> listByChapter(String bookId);
  // TODO(P0): createNote / update / delete / resolve / export
}

// TODO(P0): TranslateService / SearchService / SettingsService
//           签名对齐 docs/03 §4。
