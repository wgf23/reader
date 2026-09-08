/// 跟读高亮（线框 09：正文区当前朗读句蓝色半透明高亮；REQ-005 · US-17）。
///
/// 高亮区间为 **UTF-16 code unit 半开区间 `[highlightStart, highlightEnd)`**，与
/// `SentenceChunk.charStart/charEnd` 同尺度，可直接 `text.substring` 切片。
library;

import 'package:flutter/material.dart';

/// 正文 + 当前句高亮
class ListenFollowHighlight extends StatelessWidget {
  const ListenFollowHighlight({
    super.key,
    required this.text,
    required this.highlightStart,
    required this.highlightEnd,
  });

  final String text;
  final int highlightStart;
  final int highlightEnd;

  @override
  Widget build(BuildContext context) {
    final start =
        highlightStart < 0 ? 0 : (highlightStart > text.length ? text.length : highlightStart);
    final end = highlightEnd < start
        ? start
        : (highlightEnd > text.length ? text.length : highlightEnd);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: RichText(
        key: const Key('listen-follow-text'),
        text: TextSpan(
          style: const TextStyle(
            color: Color(0xFF202124),
            fontSize: 17,
            height: 1.8,
          ),
          children: [
            TextSpan(text: text.substring(0, start)),
            TextSpan(
              text: text.substring(start, end),
              style: const TextStyle(backgroundColor: Color(0x401A73E8)),
            ),
            TextSpan(text: text.substring(end)),
          ],
        ),
      ),
    );
  }
}
