/// 书库后端抽象：UI 只面向此接口编程，测试注入 Fake。
/// 设计：docs/03-architecture.md §4（桥接 API 面）；docs/07 §6（分层合规：页面禁止
/// 直接 import 桥接生成物，只能经 services 拿 DTO）。
library;

import 'dart:typed_data';

/// 页面/服务层共享的 DTO（不暴露生成桥接类型给 UI）
class BookSummaryData {
  const BookSummaryData({
    required this.id,
    required this.title,
    required this.authors,
    this.language,
    required this.format,
  });

  final String id;
  final String title;
  final List<String> authors;
  final String? language;
  final String format;
}

class ChapterData {
  const ChapterData({required this.title, required this.text});

  final String title;
  final String text;
}

class BookViewData {
  const BookViewData({
    required this.id,
    required this.title,
    required this.chapters,
  });

  final String id;
  final String title;
  final List<ChapterData> chapters;
}

class ProgressData {
  const ProgressData({required this.href, required this.progression});

  final String href;
  final double progression;
}

abstract class LibraryBackend {
  /// 打开书库（数据目录由后端自行解析，如应用支持目录）
  Future<void> open();
  Future<List<BookSummaryData>> list();
  Future<BookSummaryData> import(String path);
  Future<BookViewData> openBook(String id);
  Future<void> remove(String id);

  // ---- REQ-001：WebView 分页渲染所需 ----
  /// 章节原始 HTML（规范 EPUB 缓存）
  Future<String> chapterHtml(String bookId, String href);
  /// 资源字节（图片/CSS/字体）
  Future<Uint8List> resource(String bookId, String path);
  /// 保存阅读进度（href + 章内进度 0..1）
  Future<void> saveProgress(String bookId, String href, double progression);
  /// 读取阅读进度
  Future<ProgressData?> loadProgress(String bookId);
}
