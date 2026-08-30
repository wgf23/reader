import 'package:flutter/material.dart';

/// 听书页（线框 09：跟读 + 控制条；线框 10：听书设置）。
/// 骨架占位，P1 接入 TtsEngine 与听读进度同步。
class ListenPage extends StatelessWidget {
  const ListenPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('听书')),
      body: const Center(child: Text('听书骨架占位 —— 系统 TTS 朗读 P1 接入')),
    );
  }
}
