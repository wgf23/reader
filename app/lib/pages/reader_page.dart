import 'package:flutter/material.dart';

import '../engines/paged_web_view.dart';
import '../services/library_backend.dart';

/// 分页视图构建器（测试注入 fake，避免依赖系统 WebView）
typedef PagedViewBuilder = Widget Function(
  BuildContext context, {
  required String bookId,
  required String href,
  required String html,
  required LibraryBackend backend,
  required int fontSize,
  required ValueChanged<double> onProgress,
});

/// 阅读器页（线框 05）。
/// - 滚动模式：Flutter Text 渲染纯文本（P0 占位）
/// - 分页模式：PagedWebView（REQ-001，WebView + CSS 分页）
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.bookId,
    required this.bookTitle,
    required this.backend,
    this.pagedViewBuilder,
  });

  final String bookId;
  final String bookTitle;
  final LibraryBackend backend;

  /// 测试注入用；默认构建 PagedWebView
  final PagedViewBuilder? pagedViewBuilder;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  static const _fontSizes = [14, 16, 18, 20, 24];

  final GlobalKey<PagedWebViewState> _pagedKey = GlobalKey();

  BookViewData? _view;
  int _chapterIndex = 0;
  bool _pagedMode = false; // 默认滚动模式（可测）
  int _fontSize = 18;
  String? _error;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final view = await widget.backend.openBook(widget.bookId);
      var start = 0;
      final progress = await widget.backend.loadProgress(widget.bookId);
      if (progress != null) {
        final idx = _chapterIndexForHref(view, progress.href);
        if (idx >= 0) start = idx;
      }
      if (mounted) {
        setState(() {
          _view = view;
          _chapterIndex = start;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// 规范 EPUB 章节 href 形如 chapter_0001.xhtml → 章节索引
  int _chapterIndexForHref(BookViewData view, String href) {
    final m = RegExp(r'chapter_(\d+)\.xhtml').firstMatch(href);
    if (m != null) {
      final idx = int.tryParse(m.group(1) ?? '') ?? 0;
      final zero = idx - 1;
      if (zero >= 0 && zero < view.chapters.length) return zero;
    }
    return -1;
  }

  void _goChapter(int delta) {
    final view = _view;
    if (view == null) return;
    final next = (_chapterIndex + delta).clamp(0, view.chapters.length - 1);
    setState(() => _chapterIndex = next);
    _saveProgress(0.0);
  }

  void _saveProgress(double progression) {
    final view = _view;
    if (view == null) return;
    final now = DateTime.now();
    if (now.difference(_lastSave).inMilliseconds < 500) return;
    _lastSave = now;
    final href = 'chapter_${(_chapterIndex + 1).toString().padLeft(4, '0')}.xhtml';
    widget.backend.saveProgress(widget.bookId, href, progression);
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
          IconButton(
            tooltip: _pagedMode ? '切换到滚动模式' : '切换到分页模式',
            icon: Icon(_pagedMode ? Icons.article_outlined : Icons.auto_stories),
            onPressed: () => setState(() => _pagedMode = !_pagedMode),
          ),
          PopupMenuButton<int>(
            tooltip: '字号',
            initialValue: _fontSize,
            onSelected: (v) => setState(() => _fontSize = v),
            itemBuilder: (_) => [
              for (final s in _fontSizes)
                PopupMenuItem(value: s, child: Text('$s pt')),
            ],
          ),
          PopupMenuButton<int>(
            tooltip: '目录',
            onSelected: (i) {
              setState(() => _chapterIndex = i);
              _saveProgress(0.0);
            },
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
          Expanded(child: _buildChapterBody(view, chapter)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: _chapterIndex > 0 ? () => _goChapter(-1) : null,
                    icon: const Icon(Icons.skip_previous),
                    tooltip: '上一章',
                  ),
                  Text(
                    '${_chapterIndex + 1} / ${view.chapters.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  IconButton(
                    onPressed:
                        _chapterIndex < view.chapters.length - 1 ? () => _goChapter(1) : null,
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

  Widget _buildChapterBody(BookViewData view, ChapterData chapter) {
    if (_pagedMode) {
      final builder = widget.pagedViewBuilder ??
          (context, {required bookId, required href, required html, required backend,
              required fontSize, required onProgress}) {
            return PagedWebView(
              key: _pagedKey,
              bookId: bookId,
              href: href,
              html: html,
              backend: backend,
              fontSize: fontSize,
              onProgress: onProgress,
            );
          };
      return FutureBuilder<String>(
        future: widget.backend.chapterHtml(widget.bookId, _hrefFor(view)),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('章节 HTML 加载失败：${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return builder(
            context,
            bookId: widget.bookId,
            href: _hrefFor(view),
            html: snapshot.data!,
            backend: widget.backend,
            fontSize: _fontSize,
            onProgress: _saveProgress,
          );
        },
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
      child: Text(
        chapter.text,
        style: TextStyle(fontSize: _fontSize.toDouble(), height: 1.8),
      ),
    );
  }

  String _hrefFor(BookViewData view) {
    final pad = (_chapterIndex + 1).toString().padLeft(4, '0');
    final href = 'chapter_$pad.xhtml';
    return href;
  }
}
