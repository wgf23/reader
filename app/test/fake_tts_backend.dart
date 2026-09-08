import 'dart:typed_data';

import 'package:reader_app/engines/tts_engine.dart';
import 'package:reader_app/services/library_backend.dart';
import 'package:reader_app/services/tts_backend.dart';

/// 默认测试句表（与 [FakeListenBackend] 的章节文本一致）
const Map<String, List<String>> kDefaultSentences = {
  'chapter_0001.xhtml': ['第一句。', '第二句。', '第三句。'],
  'chapter_0002.xhtml': ['第四章句一。', '第四章句二。'],
};

/// 测试用听书后端：由"句表"派生 chunk / 映射，确定性可断言。
class FakeTtsBackend implements TtsBackend {
  FakeTtsBackend({
    this.sentences = kDefaultSentences,
    this.settings = const ListenSettingsData(
      voiceId: 'system_male',
      speed: 1.0,
      autoNext: true,
    ),
    this.bookId = 'b1',
  });

  final Map<String, List<String>> sentences;
  ListenSettingsData settings;
  final String bookId;

  final List<String> segmentCalls = [];
  final List<SentenceLocator> indexAtLocators = [];
  final List<ListenSettingsData> savedSettings = [];

  String chapterText(String href) => (sentences[href] ?? const <String>[]).join('');

  List<SentenceChunk> chunksFor(String href) {
    final list = sentences[href] ?? const <String>[];
    final total = list.fold<int>(0, (a, b) => a + b.length);
    final out = <SentenceChunk>[];
    var start = 0;
    for (var i = 0; i < list.length; i++) {
      final text = list[i];
      final end = start + text.length;
      final progression = total == 0 ? 0.0 : start / total;
      out.add(SentenceChunk(
        index: i,
        text: text,
        charStart: start,
        charEnd: end,
        locator: SentenceLocator(
          bookId: bookId,
          href: href,
          progression: progression,
          totalProgression: progression,
          snippet: text,
        ),
      ));
      start = end;
    }
    return out;
  }

  @override
  Future<List<SentenceChunk>> segment(String bookId, String href) async {
    segmentCalls.add(href);
    return chunksFor(href);
  }

  @override
  Future<SentenceLocator> locatorForSentence(
      String bookId, String href, int index) async {
    final chunks = chunksFor(href);
    if (index < 0 || index >= chunks.length) {
      throw ArgumentError('句子索引越界: $index');
    }
    return chunks[index].locator;
  }

  @override
  Future<int> sentenceIndexAt(
      String bookId, String href, SentenceLocator locator) async {
    indexAtLocators.add(locator);
    final chunks = chunksFor(href);
    var best = -1;
    for (var i = 0; i < chunks.length; i++) {
      if (chunks[i].locator.progression <= locator.progression + 1e-6) {
        best = i;
      } else {
        break;
      }
    }
    if (best < 0) throw StateError('进度落在首句之前');
    return best;
  }

  @override
  Future<ListenSettingsData> loadListenSettings() async => settings;

  @override
  Future<void> saveListenSettings(ListenSettingsData value) async {
    settings = value;
    savedSettings.add(value);
  }
}

/// 测试用书库后端：章节文本与 [FakeTtsBackend.sentences] 一致。
class FakeListenBackend implements LibraryBackend {
  FakeListenBackend({
    this.sentences = kDefaultSentences,
    this.progress,
    this.bookId = 'b1',
    this.bookTitle = '测试书',
  });

  final Map<String, List<String>> sentences;
  ProgressData? progress;
  final String bookId;
  final String bookTitle;

  final List<ProgressData> saved = [];

  @override
  Future<void> open() async {}

  @override
  Future<List<BookSummaryData>> list() async => [
        BookSummaryData(
          id: bookId,
          title: bookTitle,
          authors: const ['张三'],
          language: 'zh',
          format: 'epub',
        ),
      ];

  @override
  Future<BookSummaryData> import(String path) async => (await list()).first;

  @override
  Future<BookViewData> openBook(String id) async => BookViewData(
        id: id,
        title: bookTitle,
        chapters: [
          for (final entry in sentences.entries)
            ChapterData(
              title: _chapterTitle(entry.key),
              text: entry.value.join(''),
            ),
        ],
      );

  @override
  Future<void> remove(String id) async {}

  @override
  Future<String> chapterHtml(String bookId, String href) async =>
      '<html><body>${chapterText(href)}</body></html>';

  String chapterText(String href) => (sentences[href] ?? const <String>[]).join('');

  @override
  Future<Uint8List> resource(String bookId, String path) async =>
      Uint8List.fromList(const [1, 2, 3]);

  @override
  Future<void> saveProgress(
      String bookId, String href, double progression) async {
    final p = ProgressData(href: href, progression: progression);
    progress = p;
    saved.add(p);
  }

  @override
  Future<ProgressData?> loadProgress(String bookId) async => progress;

  String _chapterTitle(String href) {
    final m = RegExp(r'chapter_(\d+)\.xhtml').firstMatch(href);
    final n = int.tryParse(m?.group(1) ?? '') ?? 1;
    const numerals = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
    final label = n >= 1 && n <= numerals.length ? numerals[n - 1] : '$n';
    return '第$label章';
  }
}
