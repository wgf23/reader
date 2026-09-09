import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../engines/paged_view_controls.dart';
import '../engines/paged_web_view.dart';
import '../engines/system_tts_engine.dart';
import '../engines/tts_engine.dart';
import '../services/library_backend.dart';
import '../services/rust_tts_backend.dart';
import '../services/translate_backend.dart';
import '../services/tts_backend.dart';
import '../widgets/directory_drawer.dart';
import '../widgets/display_settings_sheet.dart';
import '../widgets/reader_chrome.dart';
import '../widgets/selection_toolbar.dart';
import '../widgets/translation_popup.dart';
import 'body_tap_policy.dart';
import 'listen_page.dart';
import 'settings_page.dart';

/// 分页视图构建器（测试注入 fake，避免依赖系统 WebView）。
typedef PagedViewBuilder = Widget Function(
  BuildContext context, {
  required String bookId,
  required String href,
  required String html,
  required LibraryBackend backend,
  required int fontSize,
  required ValueChanged<double> onProgress,
  ValueChanged<String>? onSelectedText,
});

/// 阅读器页（重构版 · 原型 docs/wireframes/reader-ui-v2/*）。
///
/// - 沉浸态：默认无 Chrome；点击正文中部 1/3 呼出/隐藏 顶栏+底栏（Kindle 式）。
/// - 左右边缘 15% 点击翻页（仅分页模式）；滚动模式靠滑动。
/// - 顶栏：返回/书名·章节/⋯更多；底栏：上一章/☰目录/可拖进度条/书签/Aa/下一章。
/// - Aa 面板（底部弹层）：字号/字体/主题/行距/**翻页模式切换**（从右上角移入）。
/// - 选中文本 → 统一浮动工具条（划重点/笔记/翻译/查词/复制）。
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.bookId,
    required this.bookTitle,
    required this.backend,
    this.translateBackend,
    this.pagedViewBuilder,
    this.pagedControls,
    this.initialPagedMode = false,
    this.ttsBackend,
    this.ttsEngine,
  });

  final String bookId;
  final String bookTitle;
  final LibraryBackend backend;
  final TranslateBackend? translateBackend;
  final PagedViewBuilder? pagedViewBuilder;

  /// REQ-007 D4：测试注入 fake 分页控件（生产为 `PagedWebViewState`）。
  final PagedViewControls? pagedControls;

  /// 初始分页模式（测试注入用，默认滚动）
  final bool initialPagedMode;

  /// 听书后端/引擎（测试注入；null → 点击"听书"时懒创建 Rust/系统实现）
  final TtsBackend? ttsBackend;
  final TtsEngine? ttsEngine;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final GlobalKey<PagedWebViewState> _pagedKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  BookViewData? _view;
  int _chapterIndex = 0;
  bool _chromeVisible = false;
  bool _pagedMode = false;
  ReaderSettings _settings = (
    fontSize: 18,
    fontFamily: '系统默认',
    theme: '浅色',
    lineHeight: '标准',
    pagedMode: false,
  );

  bool _bookmarked = false;
  double _chapterProgress = 0.0;
  String? _error;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  // REQ-003 选中/翻译/查词状态
  String? _selectedText;
  bool _translating = false;
  TranslationData? _translation;
  String? _translationError;
  bool _lookingUp = false;
  DictEntryData? _dictEntry;
  String? _lookupError;
  bool _lookupAttempted = false;

  /// 最近一次正文手势位置（选中时用于把工具条放到选词附近，而非固定顶部）。
  Offset? _lastDataPointer;

  /// REQ-007 D1：不参与手势竞技场的手动 tap 判定。
  final BodyTapTracker _tapTracker = BodyTapTracker();

  @override
  void initState() {
    super.initState();
    _pagedMode = widget.initialPagedMode;
    _load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _tapTracker.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final view = await widget.backend.openBook(widget.bookId);
      var start = 0;
      final progress = await widget.backend.loadProgress(widget.bookId);
      if (progress != null) {
        final idx = _chapterIndexForHref(view, progress.href);
        if (idx >= 0) start = idx;
        _chapterProgress = progress.progression.clamp(0.0, 1.0);
      }
      if (mounted) {
        setState(() {
          _view = view;
          _chapterIndex = start;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  int _chapterIndexForHref(BookViewData view, String href) {
    final m = RegExp(r'chapter_(\d+)\.xhtml').firstMatch(href);
    if (m != null) {
      final idx = int.tryParse(m.group(1) ?? '') ?? 0;
      final zero = idx - 1;
      if (zero >= 0 && zero < view.chapters.length) return zero;
    }
    return -1;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max > 0) {
      _chapterProgress = (_scrollController.offset / max).clamp(0.0, 1.0);
    }
  }

  void _goChapter(int delta) {
    final view = _view;
    if (view == null) return;
    final next = (_chapterIndex + delta).clamp(0, view.chapters.length - 1);
    if (next == _chapterIndex) return;
    setState(() {
      _chapterIndex = next;
      _chapterProgress = 0.0;
      _selectedText = null;
      _resetPopups();
    });
    _saveProgress(0.0);
    _jumpToProgress(0.0);
  }

  void _saveProgress(double progression) {
    final view = _view;
    if (view == null) return;
    final now = DateTime.now();
    if (now.difference(_lastSave).inMilliseconds < 300) return;
    _lastSave = now;
    final href = 'chapter_${(_chapterIndex + 1).toString().padLeft(4, '0')}.xhtml';
    widget.backend.saveProgress(widget.bookId, href, progression);
  }

  // ---------- 手势命中区（5 层 Stack + 不进竞技场的 Listener） ----------
  /// REQ-007 D1：命中区解析委托纯函数 [resolveBodyTap]，动作语义与既有
  /// `_onBodyTapUp` 逐字一致。
  void _applyTap(BodyTapAction action) {
    switch (action) {
      case BodyTapAction.prevPage:
        _page(-1);
      case BodyTapAction.nextPage:
        _page(1);
      case BodyTapAction.toggleChrome:
        setState(() => _chromeVisible = !_chromeVisible);
      case BodyTapAction.dismiss:
        if (_selectedText != null) {
          setState(() {
            _selectedText = null;
            _resetPopups();
          });
        }
        if (_chromeVisible) setState(() => _chromeVisible = false);
    }
  }

  /// 分页控件来源：测试注入优先，否则取真实 WebView state。
  PagedViewControls? get _pagedControls =>
      widget.pagedControls ?? _pagedKey.currentState;

  /// REQ-007 D4：章内翻页成功不跳章；章首/章末才续章。
  Future<void> _page(int delta) async {
    final controls = _pagedControls;
    if (controls == null) return;
    await PageTurnCoordinator(controls: controls, goChapter: _goChapter).page(delta);
  }

  /// 进度条松手 → 跳转 + 保存（原型 reader-ui-v2 底栏：拖动实时预览、松手跳转）。
  Future<void> _onProgressSeek(double v) async {
    setState(() => _chapterProgress = v);
    // 分页：按 progression 精确跳页；滚动：jumpTo 比例偏移
    if (_pagedMode) {
      final state = _pagedKey.currentState;
      if (state != null) {
        final n = await state.pageCount();
        if (n > 0) {
          final target = (v * (n - 1)).round().clamp(0, n - 1);
          await state.gotoPage(target);
        }
      }
    } else if (_scrollController.hasClients) {
      final max = _scrollController.position.maxScrollExtent;
      if (max > 0) _scrollController.jumpTo(max * v);
    }
    _saveProgress(v);
  }

  void _jumpToProgress(double v) {
    if (_pagedMode) {
      // REQ-007 D2：切章重载进行中时，等新文档载入完成再重排（PagedLoadGate）。
      final controls = _pagedControls;
      if (controls != null) controls.relayoutAfterLoad();
    } else if (_scrollController.hasClients) {
      final max = _scrollController.position.maxScrollExtent;
      if (max > 0) _scrollController.jumpTo(max * v);
    }
  }

  void _onChapterSelect(int i) {
    setState(() => _chapterIndex = i);
    _saveProgress(0.0);
    _jumpToProgress(0.0);
    Navigator.pop(context); // 关目录抽屉
  }

  void _openDirectory() {
    final view = _view;
    if (view == null) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => ReaderDirectoryDrawer(
        chapters: view.chapters.map((c) => c.title).toList(),
        currentIndex: _chapterIndex,
        onSelect: _onChapterSelect,
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      builder: (_) => ReaderSettingsSheet(
        settings: _settings,
        onChanged: (s) => setState(() {
          _settings = s;
          _pagedMode = s.pagedMode;
        }),
      ),
    );
  }

  /// REQ-007 D5 / R3-3：翻译未配置 → 直接 push 设置页，并透传同一 translateBackend。
  void _openTranslateSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(translateBackend: widget.translateBackend),
      ),
    );
  }

  void _openMore() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.insights), title: const Text('阅读统计'), onTap: () => Navigator.pop(context)),
            ListTile(leading: const Icon(Icons.headphones), title: const Text('听书'), onTap: () {
              Navigator.pop(context); // 先关闭底部弹层（US-1）
              _openListen();
            }),
            ListTile(leading: const Icon(Icons.sticky_note_2), title: const Text('笔记'), onTap: () => Navigator.pop(context)),
            ListTile(leading: const Icon(Icons.ios_share), title: const Text('导出'), onTap: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }

  /// 进入听书页并传入当前阅读位置；返回后重读进度（US-1/US-2/US-15）。
  Future<void> _openListen() async {
    final view = _view;
    if (view == null) return;
    final ttsBackend = widget.ttsBackend ?? RustTtsBackend();
    final ttsEngine = widget.ttsEngine ?? SystemTtsEngine();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ListenPage(
          bookId: widget.bookId,
          bookTitle: widget.bookTitle,
          href: _hrefFor(view),
          progression: _chapterProgress,
          backend: widget.backend,
          ttsBackend: ttsBackend,
          ttsEngine: ttsEngine,
        ),
      ),
    );
    await _reloadProgress();
  }

  /// 返回阅读页后重读进度并跳转（听读写同一 `reading_progress`，US-15）。
  Future<void> _reloadProgress() async {
    final view = _view;
    if (view == null) return;
    try {
      final progress = await widget.backend.loadProgress(widget.bookId);
      if (progress == null || !mounted) return;
      final idx = _chapterIndexForHref(view, progress.href);
      setState(() {
        if (idx >= 0) _chapterIndex = idx;
        _chapterProgress = progress.progression.clamp(0.0, 1.0);
      });
      _jumpToProgress(_chapterProgress);
    } catch (_) {
      // 重读失败不阻断返回（保持当前页）
    }
  }

  // ---------- 选中/翻译/查词（REQ-003，统一工具条） ----------
  void _onSelectedText(String text) {
    final trimmed = text.trim();
    setState(() {
      _selectedText = trimmed.isEmpty ? null : trimmed;
      _resetPopups();
    });
  }

  void _resetPopups() {
    _translating = false;
    _translation = null;
    _translationError = null;
    _lookingUp = false;
    _dictEntry = null;
    _lookupError = null;
    _lookupAttempted = false;
  }

  String _sliceSelection(SelectedContent? content) => content?.plainText ?? '';

  Future<void> _doTranslate() async {
    final backend = widget.translateBackend;
    final text = _selectedText;
    if (text == null) return;
    if (backend == null) {
      setState(() {
        _translating = false;
        _translation = null;
        _translationError = '未配置翻译后端（请检查设置）';
      });
      return;
    }
    setState(() {
      _translating = true;
      _translationError = null;
      _translation = null;
    });
    try {
      final t = await backend.translate(text);
      if (!mounted) return;
      setState(() {
        _translating = false;
        _translation = t;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _translating = false;
        _translationError = '$e';
      });
    }
  }

  Future<void> _doLookup() async {
    final backend = widget.translateBackend;
    final text = _selectedText;
    if (text == null) return;
    if (backend == null) {
      setState(() {
        _lookingUp = false;
        _dictEntry = null;
        _lookupError = '未配置查词后端（请导入词典）';
        _lookupAttempted = true;
      });
      return;
    }
    setState(() {
      _lookingUp = true;
      _dictEntry = null;
      _lookupAttempted = false;
      _lookupError = null;
    });
    try {
      final e = await backend.lookup(text);
      if (!mounted) return;
      setState(() {
        _lookingUp = false;
        _dictEntry = e;
        _lookupAttempted = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lookingUp = false;
        _lookupError = '$e';
        _lookupAttempted = true;
      });
    }
  }

  /// 复制选中文本到系统剪贴板（US-22 P1；失败不崩溃）。
  Future<void> _copySelection() async {
    final text = _selectedText;
    if (text == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      // 测试/无剪贴板平台：静默失败，保留选中态
    }
  }

  void _onSelectionAction(SelectionAction action) {
    switch (action) {
      case SelectionAction.translate:
        _doTranslate();
      case SelectionAction.lookup:
        _doLookup();
      case SelectionAction.copy:
        _copySelection();
      case SelectionAction.highlight:
      case SelectionAction.note:
        // 占位：划重点/笔记 为后续 REQ
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    if (_error != null) {
      return Scaffold(body: Center(child: Text('打开失败：$_error')));
    }
    if (view == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final chapter = view.chapters[_chapterIndex];
    final theme = _settings.theme;
    final bg = theme == '深色' ? const Color(0xFF121212) : (theme == '护眼' ? const Color(0xFFF5ECD9) : Colors.white);
    final fg = theme == '深色' ? const Color(0xFFE0E0E0) : const Color(0xFF202124);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // 手势层 + 正文（相骨）；REQ-007 D1：Listener 不进手势竞技场，
              // 故点在 SelectionArea 文字上也能收到 pointer 事件并手动判定 tap。
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (e) {
                    _lastDataPointer = e.localPosition;
                    _tapTracker.onPointerDown(e);
                  },
                  onPointerMove: (e) {
                    _lastDataPointer = e.localPosition;
                    _tapTracker.onPointerMove(e);
                  },
                  onPointerUp: (e) {
                    _lastDataPointer = e.localPosition;
                    if (_tapTracker.onPointerUp(e)) {
                      _applyTap(resolveBodyTap(
                        local: e.localPosition,
                        size: constraints.biggest,
                        pagedMode: _pagedMode,
                        chromeVisible: _chromeVisible,
                        hasSelection: _selectedText != null,
                      ));
                    }
                  },
                  onPointerCancel: _tapTracker.onPointerCancel,
                  child: Container(
                    color: bg,
                    child: _buildArticleBody(view, chapter, fg),
                  ),
                ),
              ),
              // 选中浮动工具条（原型 04-selection.svg），放在选词附近
              if (_selectedText != null)
                Positioned(
                  top: _toolbarTop(constraints.biggest.height),
                  left: 0,
                  right: 0,
                  child: Center(child: ReaderSelectionToolbar(
                    onAction: _onSelectionAction,
                  )),
                ),
              if (_selectedText != null)
                Positioned(
                  top: _toolbarTop(constraints.biggest.height) + 56,
                  left: 0,
                  right: 0,
                  child: _buildSelectionResultCards(),
                ),
              // 顶栏/底栏（呼出时，原型 02-menus.svg）
              if (_chromeVisible) ...[
                Positioned(top: 0, left: 0, right: 0,
                  child: ReaderTopBar(
                    title: widget.bookTitle,
                    chapter: chapter.title,
                    onBack: () => Navigator.pop(context),
                    onMore: _openMore,
                  )),
                Positioned(bottom: 0, left: 0, right: 0,
                  child: ReaderBottomBar(
                    chapterIndex: _chapterIndex,
                    chapterCount: view.chapters.length,
                    progress: _chapterProgress,
                    bookmarked: _bookmarked,
                    onPrevChapter: () => _goChapter(-1),
                    onNextChapter: () => _goChapter(1),
                    onDirectory: _openDirectory,
                    onBookmark: () => setState(() => _bookmarked = !_bookmarked),
                    onSettings: _openSettings,
                    onProgressChanged: (v) => setState(() => _chapterProgress = v),
                    onProgressSeek: _onProgressSeek,
                  )),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSelectionResultCards() {
    return Column(
      children: [
        if (_translating) const Card(child: Padding(padding: EdgeInsets.all(10), child: Text('翻译中…'))),
        if (!_translating && _translationError != null)
          OverlayError(
            message: _translationError!,
            onRetry: _doTranslate,
            // REQ-007 D5：仅"未配置"类翻译错误出现"去设置"；网络失败/查词错误不传。
            onOpenSettings: isTranslationNotConfiguredError(_translationError!)
                ? _openTranslateSettings
                : null,
          ),
        if (!_translating && _translation != null)
          TranslationResultCard(translation: _translation!),
        if (_lookingUp) const Card(child: Padding(padding: EdgeInsets.all(10), child: Text('查词中…'))),
        if (!_lookingUp && _lookupError != null)
          OverlayError(message: _lookupError!, onRetry: _doLookup),
        if (!_lookingUp && _lookupError == null && _lookupAttempted)
          DictResultCard(entry: _dictEntry),
      ],
    );
  }

  Widget _buildArticleBody(BookViewData view, ChapterData chapter, Color fg) {
    if (_pagedMode) {
      final builder = widget.pagedViewBuilder ??
          (context, {required bookId, required href, required html,
              required backend, required fontSize, required onProgress,
              onSelectedText}) {
            return PagedWebView(
              key: _pagedKey,
              bookId: bookId,
              href: href,
              html: html,
              backend: backend,
              fontSize: fontSize,
              theme: _themeForPaged(),
              onProgress: onProgress,
              onSelectedText: onSelectedText,
            );
          };
      return FutureBuilder<String>(
        future: widget.backend.chapterHtml(widget.bookId, _hrefFor(view)),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('章节加载失败：${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          return builder(
            context,
            bookId: widget.bookId,
            href: _hrefFor(view),
            html: snapshot.data!,
            backend: widget.backend,
            fontSize: _settings.fontSize,
            onProgress: _saveProgress,
            onSelectedText: _onSelectedText,
          );
        },
      );
    }
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 64),
      child: SelectionArea(
        onSelectionChanged: (content) => _onSelectedText(_sliceSelection(content)),
        // 禁用 Android 原生「复制」等上下文菜单，避免与自定义工具条（划重点/笔记/翻译/查词/复制）重叠；
        // 仍保留选区两端手柄供拖动调整。
        contextMenuBuilder: (context, selectableRegionState) => const SizedBox.shrink(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(chapter.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),
            Text(
              chapter.text,
              style: TextStyle(
                color: fg,
                fontSize: _settings.fontSize.toDouble(),
                height: _lineHeightFor(_settings.lineHeight),
                fontFamily: _fontFamilyFor(_settings.fontFamily),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 选中工具条定位（贴近所选文字） ----------
  double _toolbarTop(double screenH) {
    final p = _lastDataPointer;
    if (p == null) return 8;
    const toolH = 56.0;
    const margin = 12.0;
    // 优先放所选文字上方；若上方空间不足则放其下方
    final above = p.dy - toolH - margin;
    if (above >= 8) return above;
    final below = p.dy + margin;
    return below.clamp(8.0, screenH - toolH - 8);
  }

  // ---------- 显示设置 → 渲染样式映射（Aa 面板 03-settings.svg） ----------
  double _lineHeightFor(String lineHeight) {
    switch (lineHeight) {
      case '紧凑':
        return 1.4;
      case '宽松':
        return 2.2;
      default:
        return 1.8;
    }
  }

  String? _fontFamilyFor(String font) {
    switch (font) {
      case '衬线':
        return 'serif';
      case '无衬线':
        return 'sans-serif';
      default:
        return null; // 系统默认
    }
  }

  String _themeForPaged() {
    switch (_settings.theme) {
      case '深色':
        return 'dark';
      case '护眼':
        return 'sepia';
      default:
        return 'light';
    }
  }

  String _hrefFor(BookViewData view) {
    final pad = (_chapterIndex + 1).toString().padLeft(4, '0');
    return 'chapter_$pad.xhtml';
  }
}
