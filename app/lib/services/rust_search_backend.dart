/// Rust 核心搜索后端：经 flutter_rust_bridge 调用 `reader_core`，生成类型 → DTO。
/// 设计：docs/03-architecture.md §4、docs/07 §6。
library;

import '../src/rust/api.dart' as rust;
import 'search_backend.dart';

/// flutter_rust_bridge 实现的搜索后端
class RustSearchBackend implements SearchBackend {
  @override
  Future<List<SearchHitData>> search(
    String query,
    SearchScopeData scope,
  ) async {
    final hits = await rust.search(
      query: query,
      scope: rust.SearchScopeView(
        allBooks: scope.allBooks,
        bookId: scope.bookId,
        formats: scope.formats,
      ),
    );
    return [
      for (final h in hits)
        SearchHitData(
          bookId: h.bookId,
          bookTitle: h.bookTitle,
          href: h.href,
          chapterTitle: h.chapterTitle,
          chapterIndex: h.chapterIndex,
          snippet: h.snippet,
          ranges: [
            for (final r in h.ranges)
              TextRangeData(start: r.start, end: r.end),
          ],
          score: h.score,
        ),
    ];
  }
}
