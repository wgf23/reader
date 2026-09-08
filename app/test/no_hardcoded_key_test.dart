// REQ-006 T-011（US-14，[配置断言]）：全仓库源码/配置无硬编码 DeepL key。
//
// 扫描范围：app/lib、app/android/app/src、app/test、core/src、docs（源码+配置+文档）。
// 跳过：构建产物（build/target/.dart_tool）、变异测试输出（mutants*）、本测试自身。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 真实 DeepL key 形态（Free 层后缀 :fx）。
final _realKey = RegExp(
  r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:fx',
);

/// 硬编码 `DeepL-Auth-Key <字面量>`（占位符 `{key}`/`$key`/`<key>` 不算）。
final _hardcodedAuth = RegExp(
  r'DeepL-Auth-Key\s+(?!\{|\$|<)[A-Za-z0-9:_-]+',
);

const _scanRoots = [
  'lib',
  'android/app/src',
  'test',
  '../core/src',
  '../docs',
];

const _skipDirs = {'.dart_tool', 'build', 'target', 'node_modules', '.git'};

bool _isScannable(File f) {
  final p = f.path;
  if (p.endsWith('no_hardcoded_key_test.dart')) return false;
  const exts = [
    '.dart', '.rs', '.xml', '.kts', '.gradle', '.yaml', '.yml',
    '.md', '.toml', '.json', '.properties', '.txt',
  ];
  return exts.any(p.endsWith);
}

List<File> _collect(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  final out = <File>[];
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    if (_skipDirs.any((d) => e.path.contains('/$d/'))) continue;
    if (e.path.contains('/mutants')) continue;
    if (_isScannable(e)) out.add(e);
  }
  return out;
}

void main() {
  test('US-14 仓库无硬编码 DeepL key / 硬编码 Authorization 字面量', () {
    final files = <File>[for (final r in _scanRoots) ..._collect(r)];
    expect(files, isNotEmpty, reason: '扫描范围不应为空（工作目录应为 app/）');

    final realKeyHits = <String>[];
    final authHits = <String>[];
    for (final f in files) {
      final src = f.readAsStringSync();
      if (_realKey.hasMatch(src)) realKeyHits.add(f.path);
      if (_hardcodedAuth.hasMatch(src)) authHits.add(f.path);
    }
    expect(realKeyHits, isEmpty, reason: '发现疑似真实 DeepL key: $realKeyHits');
    expect(authHits, isEmpty, reason: '发现硬编码 DeepL-Auth-Key 字面量: $authHits');
  });
}
