import 'package:flutter/material.dart';

/// 笔记面板页（线框 07）。骨架占位，P0 接入 AnnotationService。
class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('笔记')),
      body: const Center(child: Text('笔记面板骨架占位 —— 笔记 CRUD P0 接入')),
    );
  }
}
