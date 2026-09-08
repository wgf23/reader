/// 跟读高亮（线框 09：正文区当前朗读句蓝色半透明高亮；REQ-005 · US-17）。
///
/// 高亮区间为 **UTF-16 code unit 半开区间 `[highlightStart, highlightEnd)`**，与
/// `SentenceChunk.charStart/charEnd` 同尺度，可直接 `text.substring` 切片。
///
/// REQ-006 · US-7：当前句变化时自动滚动进视口。`RichText` 的 span 无 `RenderObject`
/// 可直接 `ensureVisible`，故用与渲染同参数的 `TextPainter` 布局整段文本、取当前句
/// 字符位置的 y 偏移，再 `animateTo`（ADR 决策点4 A1）。`offsetForHighlight` 为纯函数，
/// 可无 widget 单测（偏移随 `highlightStart` 单调不减）。
library;

import 'package:flutter/material.dart';

/// 正文 + 当前句高亮 + 自动滚动
class ListenFollowHighlight extends StatefulWidget {
  const ListenFollowHighlight({
    super.key,
    required this.text,
    required this.highlightStart,
    required this.highlightEnd,
    this.controller,
    this.autoScroll = true,
    this.onScrolled,
  });

  final String text;
  final int highlightStart;
  final int highlightEnd;

  /// 注入/测试用；`null` 时内部创建并负责 dispose。
  final ScrollController? controller;

  /// `false` 可做"不滚动"对照（测试/降级）。
  final bool autoScroll;

  /// 滚动目标偏移回调（测试 spy；可选）。
  final void Function(double offset)? onScrolled;

  /// 与渲染同参数：计算当前句进入视口所需滚动偏移（纯函数）。
  ///
  /// 返回 `[0, maxScrollExtent]` 内的目标偏移；对递增的 [highlightStart] 单调不减。
  @visibleForTesting
  static double offsetForHighlight({
    required String text,
    required int highlightStart,
    required TextStyle style,
    required double maxWidth,
    required double textScaler,
    required double viewportHeight,
    required double maxScrollExtent,
  }) {
    final start = highlightStart < 0
        ? 0
        : (highlightStart > text.length ? text.length : highlightStart);
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(textScaler),
    )..layout(maxWidth: maxWidth <= 0 ? double.infinity : maxWidth);
    final caret = painter.getOffsetForCaret(
      TextPosition(offset: start),
      Rect.zero,
    );
    // 让当前句略低于视口顶部（保留 20% 视口高度的引导区），便于阅读上下文。
    final target = caret.dy - viewportHeight * 0.2;
    if (target <= 0) return 0;
    if (target >= maxScrollExtent) return maxScrollExtent;
    return target;
  }

  @override
  State<ListenFollowHighlight> createState() => _ListenFollowHighlightState();
}

class _ListenFollowHighlightState extends State<ListenFollowHighlight> {
  static const TextStyle _bodyStyle = TextStyle(
    color: Color(0xFF202124),
    fontSize: 17,
    height: 1.8,
  );

  static const double _horizontalPadding = 24;

  ScrollController? _controller;
  bool _ownsController = false;

  double _maxWidth = 0;
  double _viewportHeight = 0;

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
    // 初始句可能来自阅读位置（resume），首帧后滚动到它。
    if (widget.autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToHighlight());
    }
  }

  @override
  void didUpdateWidget(covariant ListenFollowHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController();
      _attachController(widget.controller);
    }
    if (oldWidget.highlightStart != widget.highlightStart && widget.autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToHighlight());
    }
  }

  @override
  void dispose() {
    _detachController();
    super.dispose();
  }

  void _attachController(ScrollController? injected) {
    if (injected != null) {
      _controller = injected;
      _ownsController = false;
    } else {
      _controller = ScrollController();
      _ownsController = true;
    }
  }

  void _detachController() {
    if (_ownsController) {
      _controller?.dispose();
    }
    _controller = null;
  }

  void _scrollToHighlight() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null || !controller.hasClients) return;
    if (_maxWidth <= 0) return;
    final offset = ListenFollowHighlight.offsetForHighlight(
      text: widget.text,
      highlightStart: widget.highlightStart,
      style: _bodyStyle,
      maxWidth: _maxWidth - _horizontalPadding * 2,
      textScaler: 1.0,
      viewportHeight: _viewportHeight,
      maxScrollExtent: controller.position.maxScrollExtent,
    );
    controller.animateTo(
      offset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
    widget.onScrolled?.call(offset);
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.highlightStart < 0
        ? 0
        : (widget.highlightStart > widget.text.length
            ? widget.text.length
            : widget.highlightStart);
    final end = widget.highlightEnd < start
        ? start
        : (widget.highlightEnd > widget.text.length
            ? widget.text.length
            : widget.highlightEnd);
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxWidth = constraints.maxWidth;
        _viewportHeight = constraints.maxHeight;
        return SingleChildScrollView(
          controller: _controller,
          padding: const EdgeInsets.fromLTRB(
            _horizontalPadding,
            16,
            _horizontalPadding,
            16,
          ),
          child: RichText(
            key: const Key('listen-follow-text'),
            text: TextSpan(
              style: _bodyStyle,
              children: [
                TextSpan(text: widget.text.substring(0, start)),
                TextSpan(
                  text: widget.text.substring(start, end),
                  style: const TextStyle(backgroundColor: Color(0x401A73E8)),
                ),
                TextSpan(text: widget.text.substring(end)),
              ],
            ),
          ),
        );
      },
    );
  }
}
