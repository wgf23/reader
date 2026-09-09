/// 编辑批注卡片（线框 07：输入框 + 删除 + 保存）。
library;

import 'package:flutter/material.dart';

class NoteEditorCard extends StatefulWidget {
  const NoteEditorCard({
    super.key,
    this.initialText = '',
    required this.onSave,
    required this.onDelete,
    this.onClose,
  });

  final String initialText;
  final ValueChanged<String> onSave;
  final VoidCallback onDelete;
  final VoidCallback? onClose;

  @override
  State<NoteEditorCard> createState() => _NoteEditorCardState();
}

class _NoteEditorCardState extends State<NoteEditorCard> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('编辑批注',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            TextField(
              key: const Key('note-editor-field'),
              controller: _controller,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '输入批注内容…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: widget.onDelete,
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('删除'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: widget.onClose,
                  child: const Text('取消'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  key: const Key('note-editor-save'),
                  onPressed: () => widget.onSave(_controller.text),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
