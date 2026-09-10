/// 笔记颜色单一来源（线框 06 的四色点；禁止各页面自造色板）。
library;

import 'package:flutter/material.dart';

class NoteColors {
  const NoteColors._();

  /// 高亮四色（与线框 06 色点一致；复用工具栏既有色值，ADR C15）。
  static const List<String> palette = <String>[
    '#FBC02D', // 黄
    '#1A73E8', // 蓝
    '#43A047', // 绿
    '#E91E63', // 粉
  ];

  static const String defaultColor = '#FBC02D';

  /// 跳转临时高亮（区别于持久化高亮；线框 07 的蓝色）。
  static const Color tempHighlight = Color(0x331A73E8);

  /// `#RRGGBB` → Color；非法/空 → 默认黄色。
  static Color colorFor(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFFFBC02D);
    final v = hex.startsWith('#') ? hex.substring(1) : hex;
    final parsed = int.tryParse(v, radix: 16);
    if (parsed == null || v.length != 6) return const Color(0xFFFBC02D);
    return Color(0xFF000000 | parsed);
  }

  /// Color → `#RRGGBB`（供选择器回传）。
  static String hexOf(Color c) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }
}
