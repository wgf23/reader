import 'package:flutter/material.dart';

/// 导入页（线框 02）。骨架占位，P0 接入拖拽与后台导入任务。
class ImportPage extends StatelessWidget {
  const ImportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入书籍')),
      body: const Center(child: Text('导入骨架占位 —— 拖拽/选择文件 P0 接入')),
    );
  }
}
