/// 正文高亮分段纯逻辑（ADR REQ-009 D6）。
///
/// 分层：`app/lib/pages` = interface；只 import Flutter SDK + `widgets/note_colors`。
/// 三类高亮彻底分离：持久化（`NoteSpanData`）、跳转临时（`TempHighlightData`）、
/// TTS 跟读（`listen_follow_highlight.dart`，不在本文件）。
library;

import 'package:flutter/material.dart';

import '../widgets/note_colors.dart';

/// 持久化笔记区间（来自 `annotations`；UTF-16 半开区间）。
class NoteSpanData {
  const NoteSpanData({
    required this.start,
    required this.end,
    required this.kind,
    this.color,
    required this.order,
  });

  final int start;
  final int end;
  final String kind; // highlight | underline | note
  final String? color;
  final int order;
}

/// 跳转临时高亮区间（不落库）。
class TempHighlightData {
  const TempHighlightData({required this.start, required this.end});

  final int start;
  final int end;
}

/// 分段结果（`Text.rich` 的原子区间）。
class NoteSpan {
  const NoteSpan({
    required this.start,
    required this.end,
    this.style,
    this.isTemporary = false,
  });

  final int start;
  final int end;
  final TextStyle? style;
  final bool isTemporary;
}

/// 合并所有端点后逐原子区间取样式：
/// - 背景色取覆盖区间的**最后一条**高亮颜色（`order` 最大）；
/// - 划线/批注取并集（批注加虚线下划线）；
/// - 临时高亮覆盖时以临时色呈现并置 `isTemporary`。
List<NoteSpan> composeSpans({
  required String text,
  required List<NoteSpanData> annotations,
  TempHighlightData? temp,
}) {
  final len = text.length;
  if (len == 0) return const <NoteSpan>[];

  final bounds = <int>{0, len};
  for (final a in annotations) {
    if (a.start >= 0 && a.start <= len) bounds.add(a.start);
    if (a.end >= 0 && a.end <= len) bounds.add(a.end);
  }
  if (temp != null) {
    if (temp.start >= 0 && temp.start <= len) bounds.add(temp.start);
    if (temp.end >= 0 && temp.end <= len) bounds.add(temp.end);
  }
  final sorted = bounds.toList()..sort();

  final spans = <NoteSpan>[];
  for (var i = 0; i + 1 < sorted.length; i++) {
    final s = sorted[i];
    final e = sorted[i + 1];
    if (e <= s) continue;

    final covering = annotations
        .where((a) => a.start <= s && a.end >= e)
        .toList(growable: false);
    NoteSpanData? highlight;
    NoteSpanData? underline;
    var hasNote = false;
    for (final a in covering) {
      switch (a.kind) {
        case 'highlight':
          if (highlight == null || a.order >= highlight.order) highlight = a;
        case 'underline':
          if (underline == null || a.order >= underline.order) underline = a;
        case 'note':
          hasNote = true;
      }
    }
    final tempCovering =
        temp != null && temp.start <= s && temp.end >= e;

    final Color? bg = tempCovering
        ? NoteColors.tempHighlight
        : (highlight != null ? NoteColors.colorFor(highlight.color) : null);
    final bool hasUnderline = underline != null;
    final bool hasLine = hasUnderline || hasNote;
    final TextStyle? style = (bg == null && !hasLine)
        ? null
        : TextStyle(
            backgroundColor: bg,
            decoration: hasLine ? TextDecoration.underline : null,
            decorationStyle: (hasNote && !hasUnderline)
                ? TextDecorationStyle.dotted
                : null,
            decorationColor: hasUnderline
                ? NoteColors.colorFor(underline.color)
                : (hasNote ? Colors.grey : null),
          );

    if (spans.isNotEmpty &&
        spans.last.end == s &&
        spans.last.isTemporary == tempCovering &&
        spans.last.style == style) {
      final prev = spans.removeLast();
      spans.add(NoteSpan(
        start: prev.start,
        end: e,
        style: style,
        isTemporary: tempCovering,
      ));
    } else {
      spans.add(NoteSpan(
        start: s,
        end: e,
        style: style,
        isTemporary: tempCovering,
      ));
    }
  }
  return spans;
}
