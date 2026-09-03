/// 选中文本浮动工具条（原型 reader-ui-v2/04-selection.svg）。
/// 动作由 reader_page 处理：翻译/查词 接 translate_backend，其余为占位（TODO）。
library;

import 'package:flutter/material.dart';

enum SelectionAction { highlight, note, translate, lookup, copy }

class ReaderSelectionToolbar extends StatelessWidget {
  const ReaderSelectionToolbar({
    super.key,
    required this.onAction,
  });

  final ValueChanged<SelectionAction> onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn('划重点', Icons.border_color, SelectionAction.highlight),
          _btn('笔记', Icons.edit_note, SelectionAction.note, withColorDots: true),
          _btn('翻译', Icons.translate, SelectionAction.translate),
          _btn('查词', Icons.abc, SelectionAction.lookup),
          _btn('复制', Icons.copy, SelectionAction.copy),
        ],
      ),
    );
  }

  Widget _btn(String label, IconData icon, SelectionAction action, {bool withColorDots = false}) {
    return InkWell(
      onTap: () => onAction(action),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 4),
              if (withColorDots)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                    for (final c in const [Color(0xFFFBC02D), Color(0xFF1A73E8), Color(0xFF43A047), Color(0xFFE91E63)])
                      Container(width: 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 1.5), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                  ],
                )
              else
                Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
