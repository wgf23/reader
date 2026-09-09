// REQ-009 · note_span_policy.composeSpans 纯函数边界测试（US-1/2/3/4/5/8）。
//
// 覆盖：空文本、无标注、单/多色高亮、重叠 order 取最大、划线、批注虚线下划线、
// 临时高亮覆盖/越界、非法区间忽略、相邻同款式合并、emoji（UTF-16 尺度）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/pages/note_span_policy.dart';
import 'package:reader_app/widgets/note_colors.dart';

NoteSpanData hl(int s, int e, {String? color, int order = 0}) => NoteSpanData(
      start: s,
      end: e,
      kind: 'highlight',
      color: color,
      order: order,
    );

NoteSpanData ul(int s, int e, {String? color, int order = 0}) => NoteSpanData(
      start: s,
      end: e,
      kind: 'underline',
      color: color,
      order: order,
    );

NoteSpanData nt(int s, int e, {int order = 0}) =>
    NoteSpanData(start: s, end: e, kind: 'note', order: order);

void main() {
  group('composeSpans 基础', () {
    test('空文本 → 空列表', () {
      expect(composeSpans(text: '', annotations: const []), isEmpty);
    });

    test('无标注 → 单个无样式 span 覆盖全文', () {
      final spans = composeSpans(text: 'abc', annotations: const []);
      expect(spans.length, 1);
      expect(spans.single.start, 0);
      expect(spans.single.end, 3);
      expect(spans.single.style, isNull);
      expect(spans.single.isTemporary, isFalse);
    });

    test('单条高亮 → backgroundColor 为色板色', () {
      final spans = composeSpans(
        text: 'abcdef',
        annotations: [hl(1, 4, color: '#1A73E8')],
      );
      expect(spans.length, 3);
      expect(spans[1].start, 1);
      expect(spans[1].end, 4);
      expect(spans[1].style?.backgroundColor,
          NoteColors.colorFor('#1A73E8'));
      expect(spans[0].style, isNull);
      expect(spans[2].style, isNull);
    });

    test('color 为 null → 回退默认黄', () {
      final spans = composeSpans(text: 'abc', annotations: [hl(0, 1)]);
      expect(spans.length, 2);
      expect(spans.first.style?.backgroundColor, NoteColors.colorFor(null));
    });

    test('未知 kind 不产生样式', () {
      final spans = composeSpans(
        text: 'abc',
        annotations: [
          const NoteSpanData(start: 0, end: 2, kind: 'unknown', order: 0)
        ],
      );
      expect(spans.single.style, isNull);
    });
  });

  group('高亮重叠/多色', () {
    test('同区间多条高亮 → order 最大者胜出', () {
      final spans = composeSpans(
        text: 'abcd',
        annotations: [
          hl(0, 4, color: '#FBC02D', order: 0),
          hl(0, 4, color: '#E91E63', order: 5),
        ],
      );
      expect(spans.single.style?.backgroundColor,
          NoteColors.colorFor('#E91E63'));
    });

    test('部分重叠 → 按端点切分原子区间', () {
      final spans = composeSpans(
        text: 'abcdef',
        annotations: [
          hl(0, 3, color: '#FBC02D', order: 0),
          hl(2, 6, color: '#43A047', order: 1),
        ],
      );
      // [0,2) 黄；[2,3) 起被 order 更大的绿色覆盖，[3,6) 同绿色 → 合并为 [2,6)
      expect(spans.length, 2);
      expect(spans[0].style?.backgroundColor,
          NoteColors.colorFor('#FBC02D'));
      expect(spans[1].start, 2);
      expect(spans[1].end, 6);
      expect(spans[1].style?.backgroundColor,
          NoteColors.colorFor('#43A047'));
    });

    test('相邻同款式高亮合并为一个 span', () {
      final spans = composeSpans(
        text: 'abcd',
        annotations: [
          hl(0, 2, color: '#FBC02D', order: 0),
          hl(2, 4, color: '#FBC02D', order: 1),
        ],
      );
      expect(spans.length, 1);
      expect(spans.single.start, 0);
      expect(spans.single.end, 4);
    });
  });

  group('划线 / 批注', () {
    test('划线 → underline + decorationColor', () {
      final spans = composeSpans(
        text: 'abcd',
        annotations: [ul(1, 3, color: '#E91E63')],
      );
      expect(spans.length, 3);
      final s = spans[1].style!;
      expect(s.decoration, TextDecoration.underline);
      expect(s.decorationColor, NoteColors.colorFor('#E91E63'));
      expect(s.decorationStyle, isNull);
    });

    test('批注 → 虚线下划线 + 灰色', () {
      final spans = composeSpans(text: 'abcd', annotations: [nt(0, 2)]);
      final s = spans.first.style!;
      expect(s.decoration, TextDecoration.underline);
      expect(s.decorationStyle, TextDecorationStyle.dotted);
      expect(s.decorationColor, Colors.grey);
    });

    test('批注 + 划线并存 → 实线且取划线色', () {
      final spans = composeSpans(
        text: 'abcd',
        annotations: [nt(0, 3), ul(0, 3, color: '#1A73E8')],
      );
      final s = spans.first.style!;
      expect(s.decoration, TextDecoration.underline);
      expect(s.decorationStyle, isNull, reason: '有划线时不用虚线');
      expect(s.decorationColor, NoteColors.colorFor('#1A73E8'));
    });

    test('高亮 + 划线叠加：背景 + 下划线同时生效', () {
      final spans = composeSpans(
        text: 'abcd',
        annotations: [
          hl(0, 4, color: '#FBC02D'),
          ul(0, 4, color: '#43A047'),
        ],
      );
      final s = spans.single.style!;
      expect(s.backgroundColor, NoteColors.colorFor('#FBC02D'));
      expect(s.decoration, TextDecoration.underline);
      expect(s.decorationColor, NoteColors.colorFor('#43A047'));
    });

    test('两条重叠划线 → order 最大者决定 decorationColor', () {
      final spans = composeSpans(
        text: 'abcd',
        annotations: [
          ul(0, 4, color: '#1A73E8', order: 1),
          ul(0, 4, color: '#E91E63', order: 2),
        ],
      );
      expect(spans.single.style?.decorationColor,
          NoteColors.colorFor('#E91E63'));
    });
  });

  group('临时高亮', () {
    test('临时高亮覆盖持久高亮 → 临时色 + isTemporary', () {
      final spans = composeSpans(
        text: 'abcdef',
        annotations: [hl(0, 6, color: '#FBC02D')],
        temp: const TempHighlightData(start: 2, end: 4),
      );
      expect(spans.length, 3);
      expect(spans[1].isTemporary, isTrue);
      expect(spans[1].style?.backgroundColor, NoteColors.tempHighlight);
      expect(spans[0].isTemporary, isFalse);
      expect(spans[0].style?.backgroundColor,
          NoteColors.colorFor('#FBC02D'));
    });

    test('临时高亮与持久高亮同区间不合并（isTemporary 不同）', () {
      final spans = composeSpans(
        text: 'abc',
        annotations: [hl(0, 3, color: '#FBC02D')],
        temp: const TempHighlightData(start: 0, end: 3),
      );
      expect(spans.single.isTemporary, isTrue);
      expect(spans.single.style?.backgroundColor, NoteColors.tempHighlight);
    });
  });

  group('非法/越界区间', () {
    test('负 start / 超长 end 的端点被忽略，不越界', () {
      final spans = composeSpans(
        text: 'abc',
        annotations: [hl(-5, 99, color: '#FBC02D')],
      );
      // 端点越界 → 不加入 bounds，仅 [0,3] 一个原子区间；covering 判断
      // start(-5)<=0 && end(99)>=3 仍成立 → 仍着色，但不越界。
      expect(spans.length, 1);
      expect(spans.single.start, 0);
      expect(spans.single.end, 3);
      expect(spans.single.style?.backgroundColor,
          NoteColors.colorFor('#FBC02D'));
    });

    test('start == end 的零宽标注不产生额外 span', () {
      final spans = composeSpans(
        text: 'abc',
        annotations: [hl(1, 1, color: '#FBC02D')],
      );
      expect(spans.length, 1);
      expect(spans.single.style, isNull);
    });

    test('emoji（代理对）按 UTF-16 索引正确切分', () {
      // '😀' 占 2 个 UTF-16 code unit：0..2，'ab' 在 2..4
      const text = '😀ab';
      final spans = composeSpans(
        text: text,
        annotations: [hl(2, 4, color: '#43A047')],
      );
      final covered =
          spans.where((s) => s.style?.backgroundColor != null).toList();
      expect(covered.single.start, 2);
      expect(covered.single.end, 4);
      // 用 UTF-16 substring 取回覆盖文本，语义与 Dart String 一致
      expect(text.substring(covered.single.start, covered.single.end), 'ab');
    });
  });
}
