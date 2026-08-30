import 'package:flutter/material.dart';

/// 搜索页（线框 04）。骨架占位，P0 接入 SearchService。
class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: const Center(child: Text('搜索骨架占位 —— FTS 搜索 P0 接入')),
    );
  }
}
