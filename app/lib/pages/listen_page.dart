/// 听书页（线框 09：跟读 + 控制条；线框 10：听书设置；REQ-005）。
///
/// 状态机 `Idle/Playing/Paused/Stopped`（docs/04 §9.3）；句完成写 `reading_progress`
/// （听读同进度，进入不写盘）；章末按 `auto_next` 连播。引擎/后端均构造注入，测试可 fake。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../engines/tts_engine.dart';
import '../services/library_backend.dart';
import '../services/tts_backend.dart';
import '../widgets/listen_control_bar.dart';
import '../widgets/listen_follow_highlight.dart';
import '../widgets/listen_settings_sheet.dart';

/// 听书运行态（docs/04 §9.3）
enum ListenState { idle, playing, paused, stopped }

/// 听书页
class ListenPage extends StatefulWidget {
  const ListenPage({
    super.key,
    required this.bookId,
    required this.bookTitle,
    required this.href,
    required this.progression,
    required this.backend,
    required this.ttsBackend,
    required this.ttsEngine,
  });

  final String bookId;
  final String bookTitle;

  /// 当前章节资源路径（`chapter_%04d.xhtml`）
  final String href;

  /// 当前阅读位置（章内进度 0..1）
  final double progression;

  final LibraryBackend backend;
  final TtsBackend ttsBackend;
  final TtsEngine ttsEngine;

  @override
  State<ListenPage> createState() => _ListenPageState();
}

class _ListenPageState extends State<ListenPage> {
  BookViewData? _view;
  int _chapterIndex = 0;
  String _chapterTitle = '';
  String _chapterText = '';
  List<SentenceChunk> _chunks = const [];
  int _index = 0;
  ListenState _state = ListenState.idle;
  ListenSettingsData _settings = const ListenSettingsData(
    voiceId: 'system_male',
    speed: 1.0,
    autoNext: true,
  );
  String? _error;

  /// 无匹配系统音色已回退默认（REQ-006 US-21；驱动"系统默认音色"提示）。
  bool _voiceFallback = false;

  int _failureCount = 0;
  bool _dirty = false;
  SentenceLocator? _pending;
  Timer? _debounce;
  StreamSubscription<TtsEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.ttsEngine.events.listen(_onTtsEvent);
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    widget.ttsEngine.stop();
    _flushProgress();
    super.dispose();
  }

  // ---------- 初始化（进入不写盘，US-2） ----------
  Future<void> _init() async {
    try {
      final settings = await widget.ttsBackend.loadListenSettings();
      final view = await widget.backend.openBook(widget.bookId);
      final idx = _chapterIndexForHref(view, widget.href);
      if (idx < 0) throw StateError('章节不存在: ${widget.href}');
      final chunks = await widget.ttsBackend.segment(widget.bookId, widget.href);
      var start = 0;
      if (chunks.isNotEmpty) {
        final at = await widget.ttsBackend.sentenceIndexAt(
          widget.bookId,
          widget.href,
          SentenceLocator(
            bookId: widget.bookId,
            href: widget.href,
            progression: widget.progression.clamp(0.0, 1.0),
            totalProgression: widget.progression.clamp(0.0, 1.0),
          ),
        );
        start = at < 0 ? 0 : (at >= chunks.length ? chunks.length - 1 : at);
      }
      await widget.ttsEngine.configure(
        voiceId: settings.voiceId,
        speed: settings.speed,
      );
      if (!mounted) return;
      setState(() {
        _view = view;
        _chapterIndex = idx;
        _chapterTitle = view.chapters[idx].title;
        _chapterText = view.chapters[idx].text;
        _chunks = chunks;
        _index = start;
        _settings = settings;
        _state = chunks.isEmpty ? ListenState.stopped : ListenState.playing;
      });
      if (chunks.isNotEmpty) {
        await widget.ttsEngine.speak(chunks[start]);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '打开听书失败：$e';
        _state = ListenState.stopped;
      });
    }
  }

  // ---------- 引擎事件（sealed → 穷尽 switch，新增事件编译期强制补分支） ----------
  void _onTtsEvent(TtsEvent event) {
    switch (event) {
      case TtsSentenceStarted():
        // 只确认高亮/滚动锚点，不写盘（听读同进度不变式，US-5）。
        final i = event.sentenceIndex;
        if (mounted && i >= 0 && i < _chunks.length) {
          setState(() => _index = i);
        }
      case TtsSentenceDone():
        // 唯一推进源（US-6）：写进度 + 下一句。
        _handleSentenceDone(event.sentenceIndex);
      case TtsVoiceFallback():
        if (mounted) setState(() => _voiceFallback = true);
      case TtsFailed():
        _handleFailed(event.message);
    }
  }

  Future<void> _handleSentenceDone(int i) async {
    if (!mounted || i < 0 || i >= _chunks.length) return;
    _failureCount = 0;
    _saveProgressDebounced(_chunks[i].locator);
    if (i + 1 < _chunks.length) {
      setState(() {
        _index = i + 1;
        _state = ListenState.playing;
      });
      await widget.ttsEngine.speak(_chunks[i + 1]);
      return;
    }
    if (_settings.autoNext) {
      await _loadNextChapter();
    } else {
      setState(() => _state = ListenState.stopped);
    }
  }

  Future<void> _handleFailed(String message) async {
    if (!mounted) return;
    _failureCount++;
    setState(() {
      _error = '朗读失败：$message（请检查系统语音是否已安装）';
    });
    if (_failureCount > 5) {
      await _stopInternal();
      return;
    }
    if (_index + 1 < _chunks.length) {
      setState(() => _index += 1);
      await widget.ttsEngine.speak(_chunks[_index]);
    } else {
      await _stopInternal();
    }
  }

  Future<void> _loadNextChapter() async {
    final view = _view;
    if (view == null) return;
    final nextIndex = _chapterIndex + 1;
    if (nextIndex >= view.chapters.length) {
      await _stopInternal();
      return;
    }
    final nextHref = _hrefForIndex(nextIndex);
    try {
      final chunks = await widget.ttsBackend.segment(widget.bookId, nextHref);
      if (!mounted) return;
      setState(() {
        _chapterIndex = nextIndex;
        _chapterTitle = view.chapters[nextIndex].title;
        _chapterText = view.chapters[nextIndex].text;
        _chunks = chunks;
        _index = 0;
        _state = chunks.isEmpty ? ListenState.stopped : ListenState.playing;
      });
      // 清掉上一章末句的待写进度，避免覆盖新章进度
      _debounce?.cancel();
      _pending = null;
      await widget.backend.saveProgress(widget.bookId, nextHref, 0.0);
      if (chunks.isNotEmpty) {
        await widget.ttsEngine.speak(chunks.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载下一章失败：$e';
        _state = ListenState.stopped;
      });
    }
  }

  // ---------- 播放控制（US-10） ----------
  Future<void> _togglePlay() async {
    switch (_state) {
      case ListenState.playing:
        await widget.ttsEngine.pause();
        if (mounted) setState(() => _state = ListenState.paused);
      case ListenState.paused:
        await widget.ttsEngine.resume();
        if (mounted) setState(() => _state = ListenState.playing);
      case ListenState.idle:
      case ListenState.stopped:
        if (_chunks.isNotEmpty) {
          setState(() => _state = ListenState.playing);
          await widget.ttsEngine.speak(_chunks[_index]);
        }
    }
  }

  Future<void> _prevSentence() async {
    if (_chunks.isEmpty) return;
    final j = _index <= 0 ? 0 : _index - 1;
    await widget.ttsEngine.stop();
    if (!mounted) return;
    setState(() {
      _index = j;
      _state = ListenState.playing;
    });
    await widget.ttsEngine.speak(_chunks[j]);
  }

  Future<void> _nextSentence() async {
    if (_chunks.isEmpty) return;
    final j = _index + 1 >= _chunks.length ? _chunks.length - 1 : _index + 1;
    await widget.ttsEngine.stop();
    if (!mounted) return;
    setState(() {
      _index = j;
      _state = ListenState.playing;
    });
    await widget.ttsEngine.speak(_chunks[j]);
  }

  Future<void> _stopInternal() async {
    await widget.ttsEngine.stop();
    if (mounted) setState(() => _state = ListenState.stopped);
  }

  // ---------- 句级进度条拖动（US-16） ----------
  Future<void> _onSeek(double v) async {
    if (_chunks.isEmpty) return;
    final raw = (v * (_chunks.length - 1)).round();
    final j = raw.clamp(0, _chunks.length - 1).toInt();
    await widget.ttsEngine.stop();
    if (!mounted) return;
    setState(() {
      _index = j;
      _state = ListenState.playing;
    });
    await widget.ttsEngine.speak(_chunks[j]);
    _debounce?.cancel();
    _pending = null;
    _dirty = false;
    await widget.backend.saveProgress(
      widget.bookId,
      _chunks[j].locator.href,
      _chunks[j].locator.progression,
    );
  }

  // ---------- 进度持久化（US-14/US-15） ----------
  void _saveProgressDebounced(SentenceLocator locator) {
    _pending = locator;
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _flushProgress);
  }

  Future<void> _flushProgress() async {
    _debounce?.cancel();
    _debounce = null;
    final p = _pending;
    if (p == null || !_dirty) return;
    _pending = null;
    _dirty = false;
    try {
      await widget.backend.saveProgress(widget.bookId, p.href, p.progression);
    } catch (_) {
      // 退出强刷失败不阻塞返回（阅读页重开仍可重读）
    }
  }

  Future<void> _exit() async {
    await _flushProgress();
    await widget.ttsEngine.stop();
    if (mounted) Navigator.of(context).pop();
  }

  // ---------- 设置（US-11/US-13） ----------
  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => ListenSettingsSheet(
        settings: _settings,
        voiceFallback: _voiceFallback,
        onSettingsChanged: _onSettingsChanged,
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    );
  }

  Future<void> _onSettingsChanged(ListenSettingsData next) async {
    if (!mounted) return;
    // 换音色后重新判定回退状态（匹配到则清除"系统默认音色"提示）。
    setState(() {
      _settings = next;
      _voiceFallback = false;
    });
    await widget.ttsEngine.configure(
      voiceId: next.voiceId,
      speed: next.speed,
    );
    await widget.ttsBackend.saveListenSettings(next);
  }

  // ---------- 渲染 ----------
  @override
  Widget build(BuildContext context) {
    final chunk =
        _chunks.isNotEmpty && _index >= 0 && _index < _chunks.length
            ? _chunks[_index]
            : null;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          onPressed: _exit,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('听书'),
        actions: [
          // 线框 09 正文控制条无"停止"位；按 ADR 关联裁定1 将次要控制放顶部栏。
          IconButton(
            tooltip: '停止',
            onPressed: _chunks.isEmpty ? null : _stopInternal,
            icon: const Icon(Icons.stop),
          ),
          IconButton(
            tooltip: '听书设置',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFEBEE),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFB71C1C), fontSize: 13),
              ),
            ),
          Expanded(child: _buildBody(chunk)),
          ListenControlBar(
            chapterTitle: _chapterTitle,
            playing: _state == ListenState.playing,
            speedText: '${_settings.speed.toStringAsFixed(1)}x',
            progress: _progress(),
            onPrevSentence: _chunks.isEmpty ? null : _prevSentence,
            onTogglePlay: _chunks.isEmpty ? null : _togglePlay,
            onNextSentence: _chunks.isEmpty ? null : _nextSentence,
            onSeek: _chunks.isEmpty ? null : _onSeek,
            onTimer: null,
            onVoice: null,
            voiceFallback: _voiceFallback,
            voiceLabel:
                _settings.voiceId.contains('female') ? '🎙 系统女声' : '🎙 系统男声',
          ),
        ],
      ),
    );
  }

  double _progress() {
    if (_chunks.length <= 1) return 0.0;
    return (_index / (_chunks.length - 1)).clamp(0.0, 1.0);
  }

  Widget _buildBody(SentenceChunk? chunk) {
    if (_view == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (chunk == null) {
      return const Center(child: Text('本章暂无可朗读内容'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Row(
            children: [
              if (_state == ListenState.playing)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A73E8),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Text(
                    '朗读中',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListenFollowHighlight(
            text: _chapterText,
            highlightStart: chunk.charStart,
            highlightEnd: chunk.charEnd,
          ),
        ),
      ],
    );
  }

  // ---------- 工具 ----------
  int _chapterIndexForHref(BookViewData view, String href) {
    final m = RegExp(r'chapter_(\d+)\.xhtml').firstMatch(href);
    if (m == null) return -1;
    final zero = (int.tryParse(m.group(1) ?? '') ?? 0) - 1;
    return (zero >= 0 && zero < view.chapters.length) ? zero : -1;
  }

  String _hrefForIndex(int index) =>
      'chapter_${(index + 1).toString().padLeft(4, '0')}.xhtml';
}
