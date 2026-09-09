/// 选中文本浮动工具条（原型 docs/wireframes/06-selection-toolbar.svg）。
///
/// 动作：复制 / 高亮（4 色）/ 划线 / 批注 / 翻译 / 查词（查词为 REQ-003 保留入口）。
/// 颜色统一取自 `NoteColors`（单一色源，ADR C15）。
library;

import 'package:flutter/material.dart';

import 'note_colors.dart';

enum SelectionAction {
  copy,
  highlight,
  underline,
  note,
  translate,
  lookup,
}

class ReaderSelectionToolbar extends StatefulWidget {
  const ReaderSelectionToolbar({
    super.key,
    required this.onAction,
    this.onHighlightColor,
  });

  final ValueChanged<SelectionAction> onAction;

  /// 选定高亮颜色时回调（`#RRGGBB`）；为 null 时「高亮」直接走 [onAction]。
  final ValueChanged<String>? onHighlightColor;

  @override
  State<ReaderSelectionToolbar> createState() =>
      _ReaderSelectionToolbarState();
}

class _ReaderSelectionToolbarState extends State<ReaderSelectionToolbar> {
  bool _paletteOpen = false;

  void _onHighlightTap() {
    if (widget.onHighlightColor == null) {
      widget.onAction(SelectionAction.highlight);
      return;
    }
    setState(() => _paletteOpen = !_paletteOpen);
  }

  void _pickColor(String hex) {
    setState(() => _paletteOpen = false);
    widget.onHighlightColor?.call(hex);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _btn('复制', Icons.copy, SelectionAction.copy),
              _btn('高亮', Icons.border_color, SelectionAction.highlight,
                  onTap: _onHighlightTap),
              _btn('划线', Icons.format_underlined, SelectionAction.underline),
              _btn('批注', Icons.edit_note, SelectionAction.note),
              _btn('翻译', Icons.translate, SelectionAction.translate),
              _btn('查词', Icons.abc, SelectionAction.lookup),
            ],
          ),
          if (_paletteOpen)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final hex in NoteColors.palette)
                    GestureDetector(
                      key: Key('note-color-$hex'),
                      onTap: () => _pickColor(hex),
                      child: Container(
                        width: 26,
                        height: 26,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: NoteColors.colorFor(hex),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _btn(
    String label,
    IconData icon,
    SelectionAction action, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap ?? () => widget.onAction(action),
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
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
