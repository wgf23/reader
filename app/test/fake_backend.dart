import 'package:reader_app/services/library_backend.dart';

/// 测试用书库后端（注入 LibraryPage/ReaderPage，避免依赖 Rust 动态库）
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
}
