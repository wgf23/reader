/// Aa 显示设置面板（原型 reader-ui-v2/03-settings.svg）：字号/字体/主题/行距/翻页模式。
library;

import 'package:flutter/material.dart';

/// 显示设置回调集合
typedef ReaderSettings = ({
  int fontSize,
  String fontFamily,
  String theme,
  String lineHeight,
  bool pagedMode,
});

/// 底部弹出显示设置面板
class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;

  static const _fontSizes = [14, 16, 18, 20, 24];
  static const _fonts = ['系统默认', '衬线', '无衬线'];
  static const _themes = ['浅色', '深色', '护眼'];
  static const _lineHeights = ['紧凑', '标准', '宽松'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('显示设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(tooltip: '关闭', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 12),
          // 字号
          _label('字号'),
          Row(
            children: [
              const Text('A-'),
              Expanded(
                child: Slider(
                  value: settings.fontSize.toDouble(),
                  min: _fontSizes.first.toDouble(),
                  max: _fontSizes.last.toDouble(),
                  divisions: _fontSizes.length - 1,
                  label: '${settings.fontSize} pt',
                  onChanged: (v) => onChanged(settings.copyWith(fontSize: v.round())),
                ),
              ),
              const Text('A+'),
              SizedBox(width: 40, child: Text('${settings.fontSize} pt', textAlign: TextAlign.end)),
            ],
          ),
          // 字体
          _label('字体'),
          _choiceRow(_fonts, settings.fontFamily,
              (v) => onChanged(settings.copyWith(fontFamily: v))),
          // 主题
          _label('主题'),
          _choiceRow(_themes, settings.theme, (v) => onChanged(settings.copyWith(theme: v))),
          // 行距
          _label('行距'),
          _choiceRow(_lineHeights, settings.lineHeight,
              (v) => onChanged(settings.copyWith(lineHeight: v))),
          // 翻页模式切换（从右上角移到这里）
          _label('翻页'),
          Row(
            children: [
              _radio(context, '分页模式', settings.pagedMode, () => onChanged(settings.copyWith(pagedMode: true))),
              const SizedBox(width: 16),
              _radio(context, '滚动模式', !settings.pagedMode, () => onChanged(settings.copyWith(pagedMode: false))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(String text) =>
      Padding(padding: const EdgeInsets.only(top: 12, bottom: 6), child: Text(text, style: const TextStyle(fontSize: 13)));

  Widget _choiceRow(List<String> options, String current, ValueChanged<String> onSelect) {
    return Row(
      children: [
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(o),
              selected: current == o,
              onSelected: (_) => onSelect(o),
            ),
          ),
      ],
    );
  }

  Widget _radio(BuildContext context, String label, bool selected, VoidCallback onSelect) {
    final color = selected ? Theme.of(context).colorScheme.primary : Colors.grey;
    return InkWell(
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(width: 2, color: color),
              ),
              child: selected
                  ? Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)))
                  : null,
            ),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }
}

// 让 ReaderSettings 支持 copyWith
extension _ReaderSettingsX on ReaderSettings {
  ReaderSettings copyWith({int? fontSize, String? fontFamily, String? theme, String? lineHeight, bool? pagedMode}) => (
        fontSize: fontSize ?? this.fontSize,
        fontFamily: fontFamily ?? this.fontFamily,
        theme: theme ?? this.theme,
        lineHeight: lineHeight ?? this.lineHeight,
        pagedMode: pagedMode ?? this.pagedMode,
      );
}
