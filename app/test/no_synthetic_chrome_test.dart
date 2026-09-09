import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// US-3/US-14 静态守卫：集成测试不得直接构造 ReaderTopBar/ReaderBottomBar 合成页，
/// 必须由真实 ReaderPage + 真实点击产生。
void main() {
  test('integration_test/*.dart 禁止出现合成 ReaderTopBar(/ReaderBottomBar(', () {
    final dir = Directory('integration_test');
    expect(dir.existsSync(), isTrue, reason: '应在 app 包根目录运行 flutter test');

    // 拼接构造，避免本文件自身命中扫描（本文件不在 integration_test/ 下）。
    final forbidden = <String>['Reader' 'TopBar(', 'Reader' 'BottomBar('];
    final offenders = <String>[];

    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final needle in forbidden) {
        if (source.contains(needle)) {
          offenders.add('${entity.path} 含 "$needle"');
        }
      }
    }

    expect(offenders, isEmpty, reason: '禁止合成 Chrome 页绕过真实交互：$offenders');
  });
}
