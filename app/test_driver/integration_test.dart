import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// flutter drive 的驱动脚本：接收集成测试里 takeScreenshot 的字节，落盘到 screenshots/。
Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('screenshots/$name.png');
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
      // ignore: avoid_print
      print('SAVED_SCREENSHOT $name -> ${file.path} (${bytes.length} bytes)');
      return true;
    },
  );
}
