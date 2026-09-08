/// Rust 核心听书后端：经 flutter_rust_bridge 调用 `reader_core`，生成类型转 DTO。
/// 设计：REQ-005 02-design §2.4；仿 `rust_library_backend.dart`。
///
/// 分层：application 层（ddd-rules 允许 import `src/rust/`）；engines/pages/widgets 不碰生成物。
library;

import '../engines/tts_engine.dart';
import '../src/rust/api.dart' as rust;
import 'frb_init.dart';
import 'tts_backend.dart';

/// flutter_rust_bridge 实现的听书后端
class RustTtsBackend implements TtsBackend {
  @override
  Future<List<SentenceChunk>> segment(String bookId, String href) async {
    final list = await rust.ttsSegment(bookId: bookId, href: href);
    return [
      for (final c in list)
        SentenceChunk(
          index: c.index,
          text: c.text,
          charStart: c.charStart,
          charEnd: c.charEnd,
          locator: _toLocator(c.locator),
        ),
    ];
  }

  @override
  Future<SentenceLocator> locatorForSentence(
      String bookId, String href, int index) async {
    final loc =
        await rust.ttsLocatorForSentence(bookId: bookId, href: href, idx: index);
    return _toLocator(loc);
  }

  @override
  Future<int> sentenceIndexAt(
      String bookId, String href, SentenceLocator locator) async {
    final view = rust.LocatorView(
      bookId: locator.bookId,
      href: locator.href,
      progression: locator.progression,
      totalProgression: locator.totalProgression,
      snippet: locator.snippet,
    );
    return rust.ttsSentenceIndexAt(bookId: bookId, href: href, locator: view);
  }

  @override
  Future<ListenSettingsData> loadListenSettings() async {
    final s = await rust.ttsListenSettingsGet();
    return ListenSettingsData(
      voiceId: s.voiceId,
      speed: s.speed,
      autoNext: s.autoNext,
    );
  }

  @override
  Future<void> saveListenSettings(ListenSettingsData settings) async {
    await rust.ttsListenSettingsSet(
      settings: rust.ListenSettingsView(
        voiceId: settings.voiceId,
        speed: settings.speed,
        autoNext: settings.autoNext,
      ),
    );
  }

  SentenceLocator _toLocator(rust.LocatorView v) => SentenceLocator(
        bookId: v.bookId,
        href: v.href,
        progression: v.progression,
        totalProgression: v.totalProgression,
        snippet: v.snippet,
      );
}

/// 确保 Rust 库已加载（与 RustLibraryBackend 共用幂等 init）。
Future<void> ensureTtsBackendInit() => ensureRustLib();
