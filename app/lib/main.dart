import 'package:flutter/material.dart';

import 'pages/library_page.dart';

/// 应用根。骨架期先落到书架页；路由 / 状态管理 P0 接入（docs/03 §3.1）。
class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reader',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const LibraryPage(),
    );
  }
}

void main() {
  runApp(const ReaderApp());
}
