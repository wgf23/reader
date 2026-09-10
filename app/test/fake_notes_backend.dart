import 'package:reader_app/services/library_backend.dart';
import 'package:reader_app/services/notes_backend.dart';

/// 测试用笔记后端（widget/集成共用）：内存 store + 记录调用参数。
///
/// `create` 会按 [chapterTexts] 计算 UTF-16 区间，模拟 Rust `from_selection`。
class FakeNotesBackend implements NotesBackend {
  FakeNotesBackend({
    this.chapterTexts = const <String, String>{},
    this.chapterTitles = const <String, String>{},
  });

  final Map<String, String> chapterTexts;
  final Map<String, String> chapterTitles;
  final List<AnnotationData> store = <AnnotationData>[];
  final List<String> createCalls = <String>[];
  final List<String> deleteCalls = <String>[];
  int _seq = 0;
  int _now = 1700000000;

  String _id() => 'an_fake_${_seq++}';

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
    final trimmed = noteText?.trim();
    if (kind == 'note' && (trimmed == null || trimmed.isEmpty)) {
      throw Exception('批注内容不能为空');
    }
    final chapter = chapterTexts[href] ?? '';
    final start = chapter.indexOf(text);
    final end = start >= 0 ? start + text.length : null;
    final a = AnnotationData(
      id: _id(),
      bookId: bookId,
      kind: kind,
      color: color,
      href: href,
      progression: progression,
      snippet: text,
      noteText: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      start: start >= 0 ? start : null,
      end: end,
      createdAt: _now++,
      updatedAt: _now++,
      syncStatus: 'local',
    );
    store.add(a);
    createCalls.add('$kind:$color:$text');
    return a;
  }

  @override
  Future<void> update(String noteId, NotePatchData patch) async {
    final i = store.indexWhere((a) => a.id == noteId);
    if (i < 0) throw Exception('笔记不存在: $noteId');
    final old = store[i];
    store[i] = AnnotationData(
      id: old.id,
      bookId: old.bookId,
      kind: patch.kind ?? old.kind,
      color: patch.color ?? old.color,
      href: old.href,
      progression: old.progression,
      snippet: old.snippet,
      noteText: patch.noteText ?? old.noteText,
      start: old.start,
      end: old.end,
      createdAt: old.createdAt,
      updatedAt: _now++,
      syncStatus: old.syncStatus,
    );
  }

  @override
  Future<void> delete(String noteId) async {
    deleteCalls.add(noteId);
    store.removeWhere((a) => a.id == noteId);
  }

  @override
  Future<int> deleteMany(List<String> noteIds) async {
    final n = store.where((a) => noteIds.contains(a.id)).length;
    store.removeWhere((a) => noteIds.contains(a.id));
    return n;
  }

  @override
  Future<int> deleteAll(String bookId) async {
    final n = store.where((a) => a.bookId == bookId).length;
    store.removeWhere((a) => a.bookId == bookId);
    return n;
  }

  @override
  Future<List<NoteGroupData>> list(String bookId) async {
    final notes = store.where((a) => a.bookId == bookId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final groups = <NoteGroupData>[];
    for (final n in notes) {
      final i = groups.indexWhere((g) => g.href == n.href);
      if (i >= 0) {
        groups[i].notes.add(n);
      } else {
        groups.add(NoteGroupData(
          chapterTitle: chapterTitles[n.href] ?? n.href,
          href: n.href,
          notes: <AnnotationData>[n],
        ));
      }
    }
    return groups;
  }

  @override
  Future<ProgressData> resolve(String noteId) async {
    final a = store.firstWhere((a) => a.id == noteId);
    return ProgressData(href: a.href, progression: a.progression);
  }

  @override
  Future<ExportSummaryData> export(
    String bookId,
    String fmt,
    String outPath,
  ) async {
    final n = store.where((a) => a.bookId == bookId).length;
    if (n == 0) throw Exception('暂无笔记');
    return ExportSummaryData(path: outPath, noteCount: n, format: fmt);
  }

  @override
  Future<BookmarkToggleData> toggleBookmark({
    required String bookId,
    required String href,
    required double progression,
    String? snippet,
  }) async {
    final target = (progression * 1000).round() / 1000;
    final i = store.indexWhere((a) =>
        a.kind == 'bookmark' &&
        a.href == href &&
        ((a.progression * 1000).round() / 1000 - target).abs() < 1e-6);
    if (i >= 0) {
      final id = store[i].id;
      store.removeAt(i);
      return BookmarkToggleData(bookmarked: false, noteId: id);
    }
    final a = await create(
      bookId: bookId,
      href: href,
      text: snippet ?? '',
      progression: progression,
      kind: 'bookmark',
    );
    return BookmarkToggleData(bookmarked: true, noteId: a.id);
  }
}
