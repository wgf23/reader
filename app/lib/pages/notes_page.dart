/// 笔记面板页（线框 07）：薄壳，内容由 `widgets/notes_panel.dart` 提供。
/// ReaderPage 内以右侧覆盖层直接嵌入 `NotesPanel`；本页保留独立路由可达性。
library;

import 'package:flutter/material.dart';

import '../services/export_path_picker.dart';
import '../services/notes_backend.dart';
import '../services/rust_notes_backend.dart';
import '../widgets/notes_panel.dart';

class NotesPage extends StatelessWidget {
  const NotesPage({
    super.key,
    required this.bookId,
    required this.bookTitle,
    this.notesBackend,
    this.picker,
  });

  final String bookId;
  final String bookTitle;
  final NotesBackend? notesBackend;
  final ExportPathPicker? picker;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('笔记')),
      body: NotesPanel(
        bookId: bookId,
        bookTitle: bookTitle,
        notesBackend: notesBackend ?? RustNotesBackend(),
        picker: picker ?? defaultExportPathPicker(),
      ),
    );
  }
}
