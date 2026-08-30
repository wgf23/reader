import 'dart:typed_data';

import 'package:reader_app/services/library_backend.dart';

/// 测试用书库后端（注入 LibraryPage/ReaderPage，避免依赖 Rust 动态库与系统 WebView）
class FakeBackend implements LibraryBackend {
  final List<BookSummaryData> books = const [
    BookSummaryData(
      id: 'b1',
      title: '测试书',
      authors: ['张三'],
      language: 'zh',
      format: 'epub',
    ),
  ];

  ProgressData? saved;

  @override
  Future<void> open() async {}

  @override
  Future<List<BookSummaryData>> list() async => books;

  @override
  Future<BookSummaryData> import(String path) async => books.first;

  @override
  Future<BookViewData> openBook(String id) async => const BookViewData(
        id: 'b1',
        title: '测试书',
        chapters: [
          ChapterData(title: '第一章', text: '很久以前，有一座山。'),
          ChapterData(title: '第二章', text: '故事结束了。'),
        ],
      );

  @override
  Future<void> remove(String id) async {}

  @override
  Future<String> chapterHtml(String bookId, String href) async =>
      '<html><body><h1>第一章</h1><p>很久以前，有一座山。</p></body></html>';

  @override
  Future<Uint8List> resource(String bookId, String path) async =>
      Uint8List.fromList([1, 2, 3]);

  @override
  Future<void> saveProgress(String bookId, String href, double progression) async {
    saved = ProgressData(href: href, progression: progression);
  }

  @override
  Future<ProgressData?> loadProgress(String bookId) async => saved;
}
