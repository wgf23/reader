import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/library_backend.dart';
import '../services/rust_library_backend.dart';
import 'reader_page.dart';

/// 书架页（线框 01）。P0：真实接入 Rust 书库（导入/列表/打开）。
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, this.backend});

  /// 测试注入用；默认 Rust 核心后端
  final LibraryBackend? backend;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late final LibraryBackend _backend = widget.backend ?? RustLibraryBackend();
  List<BookSummaryData>? _books;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _error = null);
    try {
      await _backend.open();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _load() async {
    final books = await _backend.list();
    if (mounted) setState(() => _books = books);
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['epub', 'pdf', 'mobi', 'azw3', 'txt', 'fb2', 'cbz'],
      dialogTitle: '选择书籍文件',
    );
    if (result == null) return;
    setState(() => _busy = true);
    try {
      for (final f in result.files) {
        final path = f.path;
        if (path != null) {
          await _backend.import(path);
        }
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('书库')),
      floatingActionButton: FloatingActionButton(
        onPressed: _busy ? null : _import,
        tooltip: '导入书籍',
        child: _busy ? const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ) : const Icon(Icons.add),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.grey),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '书库未就绪（Rust 核心未加载）：\n$_error',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _init, child: const Text('重试')),
          ],
        ),
      );
    }
    final books = _books;
    if (books == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (books.isEmpty) {
      return const Center(child: Text('书库为空 —— 点击右下角 ＋ 导入书籍'));
    }
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (context, i) {
        final b = books[i];
        return ListTile(
          leading: const Icon(Icons.menu_book),
          title: Text(b.title),
          subtitle: Text(
            '${b.authors.isNotEmpty ? '${b.authors.join('、')} · ' : ''}'
            '${b.format}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReaderPage(
                  bookId: b.id,
                  bookTitle: b.title,
                  backend: _backend,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
