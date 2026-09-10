/// 全文搜索页（原型 docs/wireframes/04-search.svg）。
///
/// 顶部搜索框 + 「全文搜索」按钮；结果行（书名/章节/上下文关键词高亮/定位）；
/// 右侧筛选（范围 + 格式 + 结果数/耗时）；点击「定位」返回命中给 ReaderPage。
library;

import 'package:flutter/material.dart';

import '../services/search_backend.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.searchBackend,
    this.initialBookId,
    this.initialBookTitle,
  });

  final SearchBackend searchBackend;
  final String? initialBookId;
  final String? initialBookTitle;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  List<SearchHitData> _hits = const <SearchHitData>[];
  bool _searched = false;
  bool _searching = false;
  double _elapsed = 0;
  String? _error;
  bool _allBooks = true;
  final Set<String> _formats = <String>{'EPUB', 'MOBI'};

  static const List<String> _formatOptions = <String>['EPUB', 'PDF', 'MOBI'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final q = _controller.text.trim();
    if (q.isEmpty) {
      setState(() {
        _searched = true;
        _hits = const <SearchHitData>[];
        _elapsed = 0;
        _error = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    final sw = Stopwatch()..start();
    try {
      final hits = await widget.searchBackend.search(
        q,
        SearchScopeData(
          allBooks: _allBooks,
          bookId: widget.initialBookId,
          formats: _formats.toList(),
        ),
      );
      sw.stop();
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searched = true;
        _hits = hits;
        _elapsed = sw.elapsedMicroseconds / 1e6;
      });
    } catch (e) {
      sw.stop();
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searched = true;
        _error = '$e';
      });
    }
  }

  void _locate(SearchHitData hit) {
    Navigator.pop(context, hit);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('全文搜索')),
      body: Column(
        children: [
          _searchBar(),
          const Divider(height: 1),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _results()),
                _filterPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const Key('search-field'),
              controller: _controller,
              onSubmitted: (_) => _doSearch(),
              decoration: const InputDecoration(
                hintText: '输入关键词',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('search-submit'),
            onPressed: _searching ? null : _doSearch,
            child: const Text('全文搜索'),
          ),
        ],
      ),
    );
  }

  Widget _results() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('搜索失败：$_error'));
    }
    if (!_searched) {
      return const Center(
        child: Text('输入关键词后点击「全文搜索」',
            style: TextStyle(color: Colors.grey)),
      );
    }
    if (_controller.text.trim().isEmpty) {
      return const Center(
        child: Text('请输入关键词', style: TextStyle(color: Colors.grey)),
      );
    }
    if (_hits.isEmpty) {
      return const Center(
        child: Text('未找到相关结果', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      itemCount: _hits.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) => _resultRow(i, _hits[i]),
    );
  }

  Widget _resultRow(int index, SearchHitData hit) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hit.bookTitle,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              OutlinedButton(
                key: Key('search-locate-$index'),
                onPressed: () => _locate(hit),
                child: const Text('定位'),
              ),
            ],
          ),
          Text(
            '第 ${hit.chapterIndex + 1} 章 · ${hit.chapterTitle}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 4),
          _snippetRich(hit),
        ],
      ),
    );
  }

  Widget _snippetRich(SearchHitData hit) {
    final ranges = [...hit.ranges]..sort((a, b) => a.start.compareTo(b.start));
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final r in ranges) {
      final s = r.start.clamp(0, hit.snippet.length);
      final e = r.end.clamp(s, hit.snippet.length);
      if (s > cursor) {
        spans.add(TextSpan(text: hit.snippet.substring(cursor, s)));
      }
      spans.add(TextSpan(
        text: hit.snippet.substring(s, e),
        style: const TextStyle(
          color: Color(0xFF1A73E8),
          fontWeight: FontWeight.bold,
        ),
      ));
      cursor = e;
    }
    if (cursor < hit.snippet.length) {
      spans.add(TextSpan(text: hit.snippet.substring(cursor)));
    }
    return Text.rich(
      TextSpan(
        children: spans,
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _filterPanel() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 172,
        child: Material(
          color: const Color(0xFFECEEF1),
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('筛选',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          const Text('按范围', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ListTile(
            key: const Key('scope-all'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              _allBooks
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: _allBooks ? const Color(0xFF1A73E8) : Colors.grey,
            ),
            title: const Text('全部书籍', style: TextStyle(fontSize: 12)),
            onTap: () => setState(() => _allBooks = true),
          ),
          ListTile(
            key: const Key('scope-current'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              !_allBooks
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: !_allBooks ? const Color(0xFF1A73E8) : Colors.grey,
            ),
            title: const Text('当前书籍', style: TextStyle(fontSize: 12)),
            onTap: () => setState(() => _allBooks = false),
          ),
          const SizedBox(height: 4),
          const Text('按格式', style: TextStyle(color: Colors.grey, fontSize: 12)),
          for (final f in _formatOptions)
            CheckboxListTile(
              key: Key('format-$f'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(f, style: const TextStyle(fontSize: 12)),
              value: _formats.contains(f),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _formats.add(f);
                } else {
                  _formats.remove(f);
                }
              }),
            ),
          const Spacer(),
          const Divider(),
          Text(
            '结果 ${_hits.length} 条 · ${_elapsed.toStringAsFixed(2)}s',
            key: const Key('search-stats'),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
