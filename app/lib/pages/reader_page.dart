import 'package:flutter/material.dart';

import '../services/library_backend.dart';

/// 阅读器页（线框 05）。P0：滚动模式渲染章节纯文本 + 章节切换。
/// WebView 分页（ReflowEngine）为 REQ-001（docs/07，workflow/backlog/REQ-001-webview）。
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.bookId,
    required this.bookTitle,
    required this.backend,
  });

  final String bookId;
  final String bookTitle;
  final LibraryBackend backend;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  BookViewData? _view;
  int _chapterIndex = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final view = await widget.backend.openBook(widget.bookId);
      if (mounted) {
        setState(() {
          _view = view;
          _chapterIndex = 0;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _goChapter(int delta) {
    final view = _view;
    if (view == null) return;
    final next = (_chapterIndex + delta).clamp(0, view.chapters.length - 1);
    setState(() => _chapterIndex = next);
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.bookTitle)),
        body: Center(child: Text('打开失败：$_error')),
      );
    }
    if (view == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.bookTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final chapter = view.chapters[_chapterIndex];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookTitle),
        actions: [
          PopupMenuButton<int>(
            tooltip: '目录',
            onSelected: (i) => setState(() => _chapterIndex = i),
            itemBuilder: (_) => [
              for (var i = 0; i < view.chapters.length; i++)
                PopupMenuItem(
                  value: i,
                  child: Text(
                    '${i + 1}. ${view.chapters[i].title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              chapter.title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 8),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
              child: Text(
                chapter.text,
                style: const TextStyle(fontSize: 18, height: 1.8),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: _chapterIndex > 0
                        ? () => _goChapter(-1)
                        : null,
                    icon: const Icon(Icons.skip_previous),
                    tooltip: '上一章',
                  ),
                  Text(
                    '${_chapterIndex + 1} / ${view.chapters.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  IconButton(
                    onPressed: _chapterIndex < view.chapters.length - 1
                        ? () => _goChapter(1)
                        : null,
                    icon: const Icon(Icons.skip_next),
                    tooltip: '下一章',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
