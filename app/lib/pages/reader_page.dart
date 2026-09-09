import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, RenderBox, ScrollCacheExtent, SelectedContent;
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
import 'continuous_scroll_policy.dart';
import 'listen_page.dart';
import 'progress_saver.dart';
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
    this.chapterProvider,
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

  /// REQ-008 D5：章节内容出口（测试注入失败/空章；null → `view.chapters[i]`）。
  final ChapterContentProvider? chapterProvider;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final GlobalKey<PagedWebViewState> _pagedKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  /// REQ-008 D1：连续流滚动视图 + 每章 GlobalKey（几何/定位）。
  final GlobalKey _scrollViewKey = GlobalKey();
  List<GlobalKey> _chapterKeys = <GlobalKey>[];

  /// REQ-008 D5：章节内容记忆化缓存（失败路径可注入）。
  ChapterContentCache? _chapterCache;

  /// REQ-008 D6：尾沿防抖落盘器。
  late final ProgressSaver _progressSaver;

  /// REQ-008 D2：程序化定位后锁定可见章判定，直到用户真实拖动。
  bool _chapterLocked = false;

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
    _progressSaver = ProgressSaver(
      save: (href, progression) =>
          widget.backend.saveProgress(widget.bookId, href, progression),
    );
    _load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    // REQ-008 D6 降级线：退出前强刷最后一次滚动位置（不阻断返回）。
    if (_view != null && !_pagedMode) {
      unawaited(_progressSaver.flush(
        _hrefForIndex(_chapterIndex),
        _chapterProgress,
      ));
    }
    _progressSaver.dispose();
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
      if (!mounted) return;
      setState(() {
        _view = view;
        _chapterIndex = start;
        _chapterKeys = List<GlobalKey>.generate(
          view.chapters.length,
          (_) => GlobalKey(),
        );
        _chapterCache = ChapterContentCache(
          provider: widget.chapterProvider ?? (i) => view.chapters[i],
        );
      });
      if (!_pagedMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToChapter(start, _chapterProgress);
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
    final view = _view;
    if (view == null || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final atEnd = position.pixels >= position.maxScrollExtent - 1.0;
    // 程序化定位后锁定可见章；触底时强制末章（短末章兜底）。
    if (_chapterLocked && !atEnd) return;
    final built = _collectBuiltGeometry();
    if (built.isEmpty) return;
    final idx = resolveVisibleChapter(
      built: built,
      viewportHeight: position.viewportDimension,
      current: _chapterIndex,
      lastIndex: view.chapters.length - 1,
      atEnd: atEnd,
    );
    final geo = _geometryFor(built, idx) ?? built.first;
    final p = chapterProgression(top: geo.top, height: geo.height);
    final changed = idx != _chapterIndex;
    final pChanged = (p - _chapterProgress).abs() > 1e-9;
    if (changed || (_chromeVisible && pChanged)) {
      setState(() {
        _chapterIndex = idx;
        _chapterProgress = p;
      });
    } else {
      _chapterIndex = idx;
      _chapterProgress = p;
    }
    _progressSaver.schedule(_hrefForIndex(idx), p);
  }

  /// 收集已构建章的视口几何（`top` = 章顶相对视口顶的 px）。
  List<ChapterGeometry> _collectBuiltGeometry() {
    final result = <ChapterGeometry>[];
    for (var i = 0; i < _chapterKeys.length; i++) {
      final ctx = _chapterKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) continue;
      final reveal = viewport.getOffsetToReveal(box, 0.0).offset;
      result.add(ChapterGeometry(
        index: i,
        top: reveal - _scrollController.offset,
        height: box.size.height,
      ));
    }
    return result;
  }

  ChapterGeometry? _geometryFor(List<ChapterGeometry> built, int index) {
    for (final g in built) {
      if (g.index == index) return g;
    }
    return null;
  }

  /// REQ-008 D4：底栏上一章/下一章 → 连续流滚动定位到目标章 + 立即落盘。
  Future<void> _goChapter(int delta) async {
    final view = _view;
    if (view == null) return;
    final target = (_chapterIndex + delta).clamp(0, view.chapters.length - 1);
    if (target == _chapterIndex) return;
    await _changeChapter(target, 0.0);
  }

  /// 切章统一入口：更新可见章/进度 → 落盘 → 定位（分页 relayout / 滚动 ensureVisible）。
  Future<void> _changeChapter(int target, double progression) async {
    final view = _view;
    if (view == null) return;
    final t = target.clamp(0, view.chapters.length - 1);
    final p = progression.clamp(0.0, 1.0);
    setState(() {
      _chapterIndex = t;
      _chapterProgress = p;
      _selectedText = null;
      _resetPopups();
    });
    await _progressSaver.flush(_hrefForIndex(t), p);
    if (_pagedMode) {
      _pagedControls?.relayoutAfterLoad();
    } else {
      await _scrollToChapter(t, p);
    }
  }

  /// REQ-008 D4：目标章 `ensureVisible(alignment:0)` + `progression×章高`；
  /// 未构建章先按章序比例估算 + 有界步进把目标带进构建范围。
  Future<void> _scrollToChapter(int index, double progression) async {
    final view = _view;
    if (view == null || !_scrollController.hasClients) return;
    final target = index.clamp(0, view.chapters.length - 1);
    final p = progression.clamp(0.0, 1.0);
    if (await _revealAndOffset(target, p)) return;

    // 目标章未构建：先按章序比例估算，再逐帧步进（有界，防惰性列表死循环）。
    final limit = view.chapters.length < 50 ? view.chapters.length : 50;
    _scrollController.jumpTo(proportionalChapterOffset(
      index: target,
      chapterCount: view.chapters.length,
      maxScrollExtent: _scrollController.position.maxScrollExtent,
    ));
    for (var i = 0; i < limit; i++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scrollController.hasClients) return;
      if (await _revealAndOffset(target, p)) return;
      final position = _scrollController.position;
      final next = (position.pixels + position.viewportDimension * 0.8)
          .clamp(0.0, position.maxScrollExtent);
      if (next == position.pixels) break;
      _scrollController.jumpTo(next);
    }
    // 兜底：仍定位不到时至少同步状态（不崩溃）。
    _chapterIndex = target;
    _chapterProgress = p;
    _chapterLocked = true;
  }

  /// 若目标章已构建：对齐章顶 + 章内偏移；返回是否成功。
  Future<bool> _revealAndOffset(int target, double progression) async {
    final ctx = _chapterKeys[target].currentContext;
    if (ctx == null) return false;
    await Scrollable.ensureVisible(ctx, alignment: 0.0, duration: Duration.zero);
    if (!mounted || !_scrollController.hasClients) return false;
    final box = _chapterKeys[target].currentContext?.findRenderObject();
    final height = box is RenderBox && box.hasSize ? box.size.height : 0.0;
    // 第一章保留正文顶部留白：章顶锚点取内容起点 0（而非 padding 之后），
    // 保证单章初始态（progression=0）与既有 golden 视觉一致。
    final base = target == 0 ? 0.0 : _scrollController.offset;
    final max = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo((base + progression * height).clamp(0.0, max));
    _chapterIndex = target;
    _chapterProgress = progression;
    _chapterLocked = true;
    return true;
  }

  /// 分页模式进度回调（页切换频率低 → 立即落盘）。
  Future<void> _saveProgress(double progression) async {
    final view = _view;
    if (view == null) return;
    await _progressSaver.flush(
      _hrefForIndex(_chapterIndex),
      progression.clamp(0.0, 1.0),
    );
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
    final p = v.clamp(0.0, 1.0);
    setState(() => _chapterProgress = p);
    if (_pagedMode) {
      // 分页：按 progression 精确跳页
      final state = _pagedKey.currentState;
      if (state != null) {
        final n = await state.pageCount();
        if (n > 0) {
          final target = (p * (n - 1)).round().clamp(0, n - 1);
          await state.gotoPage(target);
        }
      }
    } else {
      // 滚动：连续流按"当前可见章 + 章内比例"定位
      await _scrollToChapter(_chapterIndex, p);
    }
    await _progressSaver.flush(_hrefForIndex(_chapterIndex), p);
  }

  Future<void> _onChapterSelect(int i) async {
    await _changeChapter(i, 0.0);
    if (mounted) Navigator.pop(context); // 关目录抽屉
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
        onChanged: (s) {
          setState(() {
            _settings = s;
            _pagedMode = s.pagedMode;
          });
          // REQ-008 D4/§4.6：字号/字体/主题/行距重排或切回滚动后，以
          // "章序号 + 章内比例"重新锚定（不跳变）。
          if (!s.pagedMode) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _scrollToChapter(_chapterIndex, _chapterProgress);
            });
          }
        },
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

  /// 返回阅读页后重读进度并跳转（听读写同一 `reading_progress`，US-15/US-8）。
  Future<void> _reloadProgress() async {
    final view = _view;
    if (view == null) return;
    try {
      final progress = await widget.backend.loadProgress(widget.bookId);
      if (progress == null || !mounted) return;
      final idx = _chapterIndexForHref(view, progress.href);
      final target = idx >= 0 ? idx : _chapterIndex;
      final p = progress.progression.clamp(0.0, 1.0);
      setState(() {
        _chapterIndex = target;
        _chapterProgress = p;
      });
      if (_pagedMode) {
        _pagedControls?.relayoutAfterLoad();
      } else {
        await _scrollToChapter(target, p);
      }
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
                    child: _buildArticleBody(view, fg),
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

  Widget _buildArticleBody(BookViewData view, Color fg) {
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
    // REQ-008 D1：连续流 = SelectionArea + CustomScrollView + SliverList.builder 按章懒构建。
    return SelectionArea(
      onSelectionChanged: (content) => _onSelectedText(_sliceSelection(content)),
      // 禁用 Android 原生「复制」等上下文菜单，避免与自定义工具条（划重点/笔记/翻译/查词/复制）重叠；
      // 仍保留选区两端手柄供拖动调整。
      contextMenuBuilder: (context, selectableRegionState) => const SizedBox.shrink(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // 用户真实拖动 → 解锁可见章判定（D2 程序化锁）。
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _chapterLocked = false;
          }
          return false;
        },
        child: CustomScrollView(
          key: _scrollViewKey,
          controller: _scrollController,
          // US-11 有界构建：视口 + 250px（Flutter 3.41+ 用 scrollCacheExtent）
          scrollCacheExtent: const ScrollCacheExtent.pixels(250.0),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 64), // 与现状等价
              sliver: SliverList.builder(
                itemCount: view.chapters.length,
                itemBuilder: (context, i) => _buildChapterItem(view, i, fg),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 每章一个 sliver item（D1）；失败章内联 `OverlayError` 且显式重试有界（D5）。
  Widget _buildChapterItem(BookViewData view, int i, Color fg) {
    final isLast = i == view.chapters.length - 1;
    final gap = isLast ? 0.0 : 32.0; // 章间距（唯一行为性增量，非新控件）
    final resolution = _chapterCache?.resolve(i);
    if (resolution == null) return const SizedBox.shrink();
    if (resolution.isFailure) {
      return Padding(
        padding: EdgeInsets.only(bottom: gap),
        child: OverlayError(
          message: '第 ${i + 1} 章加载失败，请稍后重试',
          onRetry: () => setState(() => _chapterCache?.retry(i)),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: ChapterSection(
        key: _chapterKeys[i],
        index: i,
        chapter: resolution.chapter!,
        fontSize: _settings.fontSize,
        lineHeight: _lineHeightFor(_settings.lineHeight),
        fontFamily: _fontFamilyFor(_settings.fontFamily),
        foreground: fg,
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

  String _hrefFor(BookViewData view) => _hrefForIndex(_chapterIndex);

  String _hrefForIndex(int index) =>
      'chapter_${(index + 1).toString().padLeft(4, '0')}.xhtml';
}
