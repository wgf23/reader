/// 内置词典自动安装：把随包打包的英汉词典（langdao-ec）落到应用数据目录的
/// `<data>/dicts/langdao-ec/`，使「查词/离线翻译」开箱即用，无需手动导入。
/// 需在 `library_open`（Rust 扫描 dicts 目录）之前调用。
library;

import 'dart:io';

import 'package:flutter/services.dart';

/// 内置词典资源根（与 pubspec assets 一致）
const String kBuiltinDictAssetRoot = 'assets/dict/langdao-ec';
const String kBuiltinDictId = 'langdao-ec';
const List<String> _builtinDictFiles = [
  'langdao-ec-gb.ifo',
  'langdao-ec-gb.idx',
  'langdao-ec-gb.dict.dz',
];

Future<void> ensureBuiltinDict(String dataDir) async {
  final target = Directory('$dataDir/dicts/$kBuiltinDictId');
  // 已安装（幂等）则跳过
  if (await target.exists()) return;
  await target.create(recursive: true);
  for (final f in _builtinDictFiles) {
    final data = await rootBundle.load('$kBuiltinDictAssetRoot/$f');
    await File('${target.path}/$f').writeAsBytes(data.buffer.asUint8List(), flush: true);
  }
}
