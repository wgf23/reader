/// Rust 核心笔记后端：经 flutter_rust_bridge 调用 `reader_core`，生成类型 → DTO。
/// 设计：docs/03-architecture.md §4、docs/07 §6（页面只经 services）。
library;

import '../src/rust/api.dart' as rust;
import 'library_backend.dart' show ProgressData;
import 'notes_backend.dart';

/// flutter_rust_bridge 实现的笔记后端
class RustNotesBackend implements NotesBackend {
  @override
  Future<AnnotationData> create({
    required String bookId,
    required String href,
    required String text,
    required double progression,
    required String kind,
    String? color,
    String? noteText,
  }) async {
    final a = await rust.notesCreate(
      bookId: bookId,
      href: href,
      text: text,
      progression: progression,
      kind: kind,
      color: color,
      noteText: noteText,
    );
    return _toData(a);
  }

  @override
  Future<void> update(String noteId, NotePatchData patch) =>
      rust.notesUpdate(
        noteId: noteId,
        patch: rust.NotePatchView(
          noteText: patch.noteText,
          color: patch.color,
          kind: patch.kind,
        ),
      );

  @override
  Future<void> delete(String noteId) => rust.notesDelete(noteId: noteId);

  @override
  Future<int> deleteMany(List<String> noteIds) =>
      rust.notesDeleteMany(noteIds: noteIds);

  @override
  Future<int> deleteAll(String bookId) => rust.notesDeleteAll(bookId: bookId);

  @override
  Future<List<NoteGroupData>> list(String bookId) async {
    final groups = await rust.notesList(bookId: bookId);
    return [
      for (final g in groups)
        NoteGroupData(
          chapterTitle: g.chapterTitle,
          href: g.href,
          notes: [for (final n in g.notes) _toData(n)],
        ),
    ];
  }

  @override
  Future<ProgressData> resolve(String noteId) async {
    final loc = await rust.notesResolve(noteId: noteId);
    return ProgressData(href: loc.href, progression: loc.progression);
  }

  @override
  Future<ExportSummaryData> export(
    String bookId,
    String fmt,
    String outPath,
  ) async {
    final s = await rust.notesExport(
      bookId: bookId,
      fmt: fmt,
      outPath: outPath,
    );
    return ExportSummaryData(
      path: s.path,
      noteCount: s.noteCount,
      format: s.format,
    );
  }

  @override
  Future<BookmarkToggleData> toggleBookmark({
    required String bookId,
    required String href,
    required double progression,
    String? snippet,
  }) async {
    final r = await rust.notesToggleBookmark(
      bookId: bookId,
      href: href,
      progression: progression,
      snippet: snippet,
    );
    return BookmarkToggleData(bookmarked: r.bookmarked, noteId: r.noteId);
  }

  AnnotationData _toData(rust.AnnotationView a) => AnnotationData(
        id: a.id,
        bookId: a.bookId,
        kind: a.kind,
        color: a.color,
        href: a.href,
        progression: a.progression,
        snippet: a.snippet,
        noteText: a.noteText,
        start: a.start,
        end: a.end,
        createdAt: a.createdAt.toInt(),
        updatedAt: a.updatedAt.toInt(),
        syncStatus: a.syncStatus,
      );
}
