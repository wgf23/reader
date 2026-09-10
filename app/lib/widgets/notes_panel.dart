/// 笔记面板（原型 docs/wireframes/07-annotation-panel.svg）。
///
/// 右侧 360px 覆盖层由 `ReaderPage` 提供；本 widget 负责：标题/搜索/章节分组/
/// 色标/片段/批注/时间/底部导出·全部删除/多选批量删除/编辑卡片/改色。
library;

import 'package:flutter/material.dart';

import '../services/export_path_picker.dart';
import '../services/notes_backend.dart';
import 'note_colors.dart';
import 'note_editor_card.dart';

/// 面板内搜索过滤（大小写不敏感；命中片段/批注/章节名）。
List<NoteGroupData> filterNoteGroups(
  List<NoteGroupData> groups,
  String keyword,
) {
  final k = keyword.trim().toLowerCase();
  if (k.isEmpty) return groups;
  final out = <NoteGroupData>[];
  for (final g in groups) {
    final notes = g.notes
        .where((n) =>
            (n.snippet ?? '').toLowerCase().contains(k) ||
            (n.noteText ?? '').toLowerCase().contains(k) ||
            g.chapterTitle.toLowerCase().contains(k))
        .toList(growable: false);
    if (notes.isNotEmpty) {
      out.add(NoteGroupData(
        chapterTitle: g.chapterTitle,
        href: g.href,
        notes: notes,
      ));
    }
  }
  return out;
}

class NotesPanel extends StatefulWidget {
  const NotesPanel({
    super.key,
    required this.bookId,
    required this.bookTitle,
    required this.notesBackend,
    required this.picker,
    this.onChanged,
    this.onTapNote,
    this.onClose,
  });

  final String bookId;
  final String bookTitle;
  final NotesBackend notesBackend;
  final ExportPathPicker picker;

  /// 笔记变更后通知 ReaderPage 重载 span 渲染。
  final VoidCallback? onChanged;
  final ValueChanged<AnnotationData>? onTapNote;
  final VoidCallback? onClose;

  @override
  State<NotesPanel> createState() => _NotesPanelState();
}

class _NotesPanelState extends State<NotesPanel> {
  List<NoteGroupData> _groups = const <NoteGroupData>[];
  String _filter = '';
  bool _loading = true;
  String? _error;
  bool _multiSelect = false;
  final Set<String> _selected = <String>{};
  AnnotationData? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final groups = await widget.notesBackend.list(widget.bookId);
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
        _error = null;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  int get _total => _groups.fold(0, (n, g) => n + g.notes.length);

  String _timeLabel(int secs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    return '$mm-$dd';
  }

  Future<bool> _confirm(String title, String content) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm-delete'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _deleteOne(AnnotationData note) async {
    final ok = await _confirm('删除笔记', '确认删除这条笔记？删除后原文标记将一并清除。');
    if (!ok) return;
    await widget.notesBackend.delete(note.id);
    setState(() => _editing = null);
    await _load();
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final ok = await _confirm('删除选中', '确认删除选中的 ${_selected.length} 条笔记？');
    if (!ok) return;
    await widget.notesBackend.deleteMany(_selected.toList());
    setState(() {
      _selected.clear();
      _multiSelect = false;
    });
    await _load();
  }

  Future<void> _deleteAll() async {
    if (_total == 0) return;
    final ok = await _confirm('全部删除', '确认删除该书全部笔记？此操作不可撤销。');
    if (!ok) return;
    await widget.notesBackend.deleteAll(widget.bookId);
    await _load();
  }

  Future<void> _export() async {
    if (_total == 0) {
      _snack('暂无笔记');
      return;
    }
    final fmt = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('导出格式'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'markdown'),
            child: const Text('Markdown (.md)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'json'),
            child: const Text('JSON (.json)'),
          ),
        ],
      ),
    );
    if (fmt == null) return;
    final ext = fmt == 'json' ? 'json' : 'md';
    final path = await widget.picker
        .pick(suggestedName: widget.bookTitle, extension: ext);
    if (path == null) return; // 用户取消 → 不写文件
    try {
      final s = await widget.notesBackend.export(widget.bookId, fmt, path);
      _snack('已导出 ${s.noteCount} 条到 ${s.path}');
    } catch (e) {
      _snack('导出失败：$e');
    }
  }

  Future<void> _saveEdit(AnnotationData note, String text) async {
    if (note.kind == 'note' && text.trim().isEmpty) {
      _snack('批注内容不能为空');
      return;
    }
    await widget.notesBackend.update(
      note.id,
      NotePatchData(noteText: text.trim()),
    );
    setState(() => _editing = null);
    await _load();
  }

  Future<void> _changeColor(AnnotationData note, String hex) async {
    await widget.notesBackend.update(note.id, NotePatchData(color: hex));
    await _load();
  }

  void _openColorPicker(AnnotationData note) {
    showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择颜色'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final hex in NoteColors.palette)
                  GestureDetector(
                    key: Key('panel-color-$hex'),
                    onTap: () => Navigator.pop(ctx, hex),
                    child: Container(
                      width: 28,
                      height: 28,
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
    ).then((hex) {
      if (hex != null) _changeColor(note, hex);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Stack(
        children: [
          Column(
            children: [
              _header(),
              _searchField(),
              Expanded(child: _body()),
              _bottomBar(),
            ],
          ),
          if (_editing != null)
            Positioned(
              left: 16,
              right: 16,
              top: 96,
              child: NoteEditorCard(
                initialText: _editing!.noteText ?? '',
                onSave: (t) => _saveEdit(_editing!, t),
                onDelete: () => _deleteOne(_editing!),
                onClose: () => setState(() => _editing = null),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          const Text('笔记',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Spacer(),
          if (_multiSelect)
            TextButton(
              key: const Key('notes-cancel-multi'),
              onPressed: () => setState(() {
                _multiSelect = false;
                _selected.clear();
              }),
              child: const Text('取消多选'),
            ),
          IconButton(
            key: const Key('notes-close'),
            tooltip: '关闭',
            icon: const Icon(Icons.close),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        key: const Key('notes-search'),
        onChanged: (v) => setState(() => _filter = v),
        decoration: const InputDecoration(
          hintText: '搜索笔记',
          prefixIcon: Icon(Icons.search, size: 18),
          isDense: true,
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('加载失败：$_error'));
    }
    final groups = filterNoteGroups(_groups, _filter);
    if (_groups.isEmpty) {
      return const Center(child: Text('暂无笔记'));
    }
    if (groups.isEmpty) {
      return const Center(child: Text('无匹配'));
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
            child: Text(g.chapterTitle,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          for (final n in g.notes) _noteRow(n),
        ],
      ],
    );
  }

  Widget _noteRow(AnnotationData note) {
    final isBookmark = note.kind == 'bookmark';
    return InkWell(
      key: Key('note-row-${note.id}'),
      onTap: () {
        if (_multiSelect) {
          setState(() {
            if (!_selected.remove(note.id)) _selected.add(note.id);
          });
        } else {
          widget.onTapNote?.call(note);
        }
      },
      onLongPress: () => setState(() {
        _multiSelect = true;
        _selected.add(note.id);
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_multiSelect)
              Checkbox(
                value: _selected.contains(note.id),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(note.id);
                  } else {
                    _selected.remove(note.id);
                  }
                }),
              ),
            if (isBookmark)
              const Padding(
                padding: EdgeInsets.only(right: 8, top: 2),
                child: Icon(Icons.bookmark, size: 16, color: Color(0xFFFBC02D)),
              )
            else
              GestureDetector(
                key: Key('note-color-strip-${note.id}'),
                onTap: () => _openColorPicker(note),
                child: Container(
                  width: 4,
                  height: 44,
                  color: NoteColors.colorFor(note.color),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.snippet ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (note.noteText != null && note.noteText!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        note.noteText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(_timeLabel(note.updatedAt),
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (!_multiSelect)
              IconButton(
                key: Key('note-edit-${note.id}'),
                tooltip: '编辑',
                icon: const Icon(Icons.edit, size: 16),
                onPressed: () => setState(() => _editing = note),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE1E4E8))),
        ),
        child: Row(
          children: [
            FilledButton(
              key: const Key('notes-export'),
              onPressed: _export,
              child: const Text('导出'),
            ),
            const SizedBox(width: 8),
            if (_multiSelect)
              FilledButton(
                key: const Key('notes-delete-selected'),
                onPressed: _selected.isEmpty ? null : _deleteSelected,
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('删除选中'),
              ),
            const Spacer(),
            TextButton(
              key: const Key('notes-delete-all'),
              onPressed: _total == 0 ? null : _deleteAll,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('全部删除'),
            ),
          ],
        ),
      ),
    );
  }
}
