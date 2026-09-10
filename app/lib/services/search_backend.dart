/// 全文搜索后端抽象：UI 只面向此接口编程，测试注入 Fake。
/// 设计：docs/03-architecture.md §4；ADR REQ-009 D10。
library;

/// UTF-16 半开区间（关键词在 snippet 内的位置）。
class TextRangeData {
  const TextRangeData({required this.start, required this.end});

  final int start;
  final int end;
}

/// 搜索命中。
class SearchHitData {
  const SearchHitData({
    required this.bookId,
    required this.bookTitle,
    required this.href,
    required this.chapterTitle,
    required this.chapterIndex,
    required this.snippet,
    required this.ranges,
    this.score,
  });

  final String bookId;
  final String bookTitle;
  final String href;
  final String chapterTitle;

  /// 该命中所属书籍的**真实章节序号**（0 基，按书库章节顺序；rework-B D1）。
  /// UI 渲染「第 N 章」时使用 `chapterIndex + 1`，不使用结果列表序号。
  final int chapterIndex;
  final String snippet;
  final List<TextRangeData> ranges;
  final double? score;
}

/// 搜索范围（`allBooks=true` 时忽略 `bookId`；`formats` 空 = 全部格式）。
class SearchScopeData {
  const SearchScopeData({
    this.allBooks = true,
    this.bookId,
    this.formats = const [],
  });

  final bool allBooks;
  final String? bookId;
  final List<String> formats;
}

abstract class SearchBackend {
  Future<List<SearchHitData>> search(String query, SearchScopeData scope);
}
