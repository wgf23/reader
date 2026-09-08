// REQ-006 T-001（US-1/US-2，[配置断言]）：Android 主清单平台配置静态断言。
//
// 纯文本解析，不依赖真机/构建：Android 11(API30)+ 包可见性需声明 TTS_SERVICE，
// release 在线翻译需主清单 INTERNET。`flutter test` 的工作目录为 `app/`。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Android 主清单（US-1/US-2）', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');

    test('US-1 声明 TTS_SERVICE 包可见性且保留 PROCESS_TEXT', () {
      expect(
        manifest,
        contains('android.intent.action.TTS_SERVICE'),
        reason: 'Android 11+ 需声明 TTS_SERVICE 才能解析默认 TTS 引擎',
      );
      expect(
        manifest,
        contains('android.intent.action.PROCESS_TEXT'),
        reason: 'REQ-004 的原生选择菜单 PROCESS_TEXT query 必须保留',
      );
    });

    test('US-2 主清单声明 INTERNET 权限（release 在线翻译必需）', () {
      expect(
        manifest,
        contains('android.permission.INTERNET'),
        reason: 'INTERNET 只在 debug/profile 时 release APK 无法联网翻译',
      );
    });

    test('debug/profile 清单保留 INTERNET（merger 去重不冲突）', () {
      for (final p in [
        'android/app/src/debug/AndroidManifest.xml',
        'android/app/src/profile/AndroidManifest.xml',
      ]) {
        expect(_read(p), contains('android.permission.INTERNET'), reason: p);
      }
    });

    test('US-1 build.gradle.kts targetSdk 取自 flutter.targetSdkVersion（≥30）', () {
      final gradle = _read('android/app/build.gradle.kts');
      expect(
        gradle,
        contains('targetSdk = flutter.targetSdkVersion'),
        reason: '本机 Flutter 3.47.2 默认 targetSdk=36（≥30）',
      );
      expect(gradle, contains('compileSdk = 36'));
    });
  });
}
