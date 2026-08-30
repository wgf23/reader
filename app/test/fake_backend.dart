import 'package:reader_app/services/library_backend.dart';
import 'package:reader_app/src/rust/api.dart' as rust;

/// 测试用书库后端（注入 LibraryPage/ReaderPage，避免依赖 Rust 动态库）
class FakeBackend implements LibraryBackend {
  final List<rust.BookSummary> books = const [
    rust.BookSummary(
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
  Future<List<rust.BookSummary>> list() async => books;

  @override
  Future<rust.BookSummary> import(String path) async => books.first;

  @override
  Future<rust.BookView> openBook(String id) async => const rust.BookView(
        id: 'b1',
        title: '测试书',
        chapters: [
          rust.ChapterView(title: '第一章', text: '很久以前，有一座山。'),
          rust.ChapterView(title: '第二章', text: '故事结束了。'),
        ],
      );

  @override
  Future<void> remove(String id) async {}
}
