import 'package:reader_app/services/search_backend.dart';

/// 测试用搜索后端：记录 query/scope，按 snippet 过滤 [hits]。
class FakeSearchBackend implements SearchBackend {
  FakeSearchBackend({List<SearchHitData> hits = const <SearchHitData>[]})
      : hits = List<SearchHitData>.from(hits);

  final List<SearchHitData> hits;
  final List<String> queries = <String>[];
  final List<SearchScopeData> scopes = <SearchScopeData>[];

  @override
  Future<List<SearchHitData>> search(
    String query,
    SearchScopeData scope,
  ) async {
    queries.add(query);
    scopes.add(scope);
    if (query.trim().isEmpty) return const <SearchHitData>[];
    final matched = hits
        .where((h) =>
            h.snippet.contains(query) ||
            h.bookTitle.contains(query) ||
            h.chapterTitle.contains(query))
        .toList();
    return matched.isEmpty ? hits : matched;
  }
}
