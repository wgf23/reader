// REQ-009 · NoteColors 单一色源边界测试（线框 06 四色）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/widgets/note_colors.dart';

void main() {
  group('NoteColors.colorFor', () {
    test('四色色板与默认色常量', () {
      expect(NoteColors.palette.length, 4);
      expect(NoteColors.defaultColor, '#FBC02D');
      expect(NoteColors.palette, contains(NoteColors.defaultColor));
    });

    test('null / 空串 → 默认黄', () {
      expect(NoteColors.colorFor(null), const Color(0xFFFBC02D));
      expect(NoteColors.colorFor(''), const Color(0xFFFBC02D));
    });

    test('带 # / 不带 # 的合法 6 位 hex 均解析', () {
      expect(NoteColors.colorFor('#FBC02D'), const Color(0xFFFBC02D));
      expect(NoteColors.colorFor('1A73E8'), const Color(0xFF1A73E8));
      expect(NoteColors.colorFor('43a047'), const Color(0xFF43A047));
    });

    test('非法长度 / 非法字符 → 默认黄（不抛异常）', () {
      expect(NoteColors.colorFor('#12345'), const Color(0xFFFBC02D));
      expect(NoteColors.colorFor('#1234567'), const Color(0xFFFBC02D));
      expect(NoteColors.colorFor('#GGGGGG'), const Color(0xFFFBC02D));
      expect(NoteColors.colorFor('#ZZZZZZ'), const Color(0xFFFBC02D));
    });

    test('hexOf 与 colorFor 往返一致', () {
      for (final hex in NoteColors.palette) {
        expect(NoteColors.hexOf(NoteColors.colorFor(hex)), hex);
      }
    });

    test('hexOf 输出大写 6 位并保留前导零', () {
      expect(NoteColors.hexOf(const Color(0xFF000000)), '#000000');
      expect(NoteColors.hexOf(const Color(0xFF0A0B0C)), '#0A0B0C');
      expect(NoteColors.hexOf(const Color(0xFFFFFFFF)), '#FFFFFF');
    });
  });
}
