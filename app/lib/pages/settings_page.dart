import 'package:flutter/material.dart';

/// 设置页（线框 03）。骨架占位，P0 接入设置存储。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: const Center(child: Text('设置骨架占位 —— 外观/翻译/词典 P0 接入')),
    );
  }
}
