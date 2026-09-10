/// 笔记后端抽象：UI 只面向此接口编程，测试注入 Fake。
/// 设计：docs/03-architecture.md §4；ADR REQ-009 D10（DTO 与 Dart 一一对应）。
library;

import 'library_backend.dart' show ProgressData;

/// 笔记视图（与 Rust `AnnotationView` 一一对应）。
class AnnotationData {
  const AnnotationData({
    required this.id,
    required this.bookId,
    required this.kind,
    this.color,
    required this.href,
    required this.progression,
    this.snippet,
    this.noteText,
    this.start,
    this.end,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
  });

  final String id;
  final String bookId;

  /// highlight | underline | note | bookmark
  final String kind;
  final String? color;
  final String href;
  final double progression;
  final String? snippet;
  final String? noteText;

  /// UTF-16 半开区间（文本锚）；无锚为 null。
  final int? start;
  final int? end;
  final int createdAt;
  final int updatedAt;
  final String syncStatus;
}

/// 按章节分组的笔记。
class NoteGroupData {
  const NoteGroupData({
    required this.chapterTitle,
    required this.href,
    required this.notes,
  });

  final String chapterTitle;
  final String href;
  final List<AnnotationData> notes;
}

/// 笔记局部更新（null = 不改）。
class NotePatchData {
  const NotePatchData({this.noteText, this.color, this.kind});

  final String? noteText;
  final String? color;
  final String? kind;
}

/// 书签切换结果。
class BookmarkToggleData {
  const BookmarkToggleData({required this.bookmarked, this.noteId});

  final bool bookmarked;
  final String? noteId;
}

/// 导出结果摘要。
class ExportSummaryData {
  const ExportSummaryData({
    required this.path,
    required this.noteCount,
    required this.format,
  });

  final String path;
  final int noteCount;
  final String format;
}

abstract class NotesBackend {
  Future<AnnotationData> create({
    required String bookId,
    required String href,
    required String text,
    required double progression,
    required String kind,
    String? color,
    String? noteText,
  });
  Future<void> update(String noteId, NotePatchData patch);
  Future<void> delete(String noteId);
  Future<int> deleteMany(List<String> noteIds);
  Future<int> deleteAll(String bookId);
  Future<List<NoteGroupData>> list(String bookId);

  /// 笔记 id → 位置（href + progression）。
  Future<ProgressData> resolve(String noteId);
  Future<ExportSummaryData> export(String bookId, String fmt, String outPath);
  Future<BookmarkToggleData> toggleBookmark({
    required String bookId,
    required String href,
    required double progression,
    String? snippet,
  });
}
