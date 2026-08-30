/// 书库后端抽象：UI 只面向此接口编程，测试注入 Fake。
/// 设计：docs/03-architecture.md §4（桥接 API 面）。
library;

import '../src/rust/api.dart' as rust;

abstract class LibraryBackend {
  /// 打开书库（数据目录由后端自行解析，如应用支持目录）
  Future<void> open();
  Future<List<rust.BookSummary>> list();
  Future<rust.BookSummary> import(String path);
  Future<rust.BookView> openBook(String id);
  Future<void> remove(String id);
}
