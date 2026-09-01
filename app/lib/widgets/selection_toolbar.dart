/// 选中文本浮动工具条（原型 reader-ui-v2/04-selection.svg）。
/// 动作由 reader_page 处理：翻译/查词 接 translate_backend，其余为占位（TODO）。
library;

import 'package:flutter/material.dart';

enum SelectionAction { highlight, note, translate, lookup, copy }

class ReaderSelectionToolbar extends StatelessWidget {
  const ReaderSelectionToolbar({
    super.key,
    required this.onAction,
    this.hasTranslateBackend = true,
  });

  final ValueChanged<SelectionAction> onAction;

  /// translateBackend==null 时隐藏 翻译/查词（REQ-003 零注入行为不变；划重点/笔记/复制仍在）
  final bool hasTranslateBackend;

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
          if (hasTranslateBackend) ...[
            _btn('翻译', Icons.translate, SelectionAction.translate),
            _btn('查词', Icons.abc, SelectionAction.lookup),
          ],
          _btn('复制', Icons.copy, SelectionAction.copy),
        ],
      ),
    );
  }

  Widget _btn(String label, IconData icon, SelectionAction action, {bool withColorDots = false}) {
    return InkWell(
      onTap: () => onAction(action),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 2),
            if (withColorDots)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(fontSize: 11)),
                  const SizedBox(width: 3),
                  for (final c in const [Color(0xFFFBC02D), Color(0xFF1A73E8), Color(0xFF43A047), Color(0xFFE91E63)])
                    Container(width: 4, height: 4, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                ],
              )
            else
              Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
