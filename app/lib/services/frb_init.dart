/// flutter_rust_bridge 加载初始化（RustLibraryBackend / RustTranslateBackend 共用）。
/// 静态标志保证整进程只 init 一次（RustLib.init 幂等性由调用方保证）。
library;

import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:path_provider/path_provider.dart';

import '../src/rust/frb_generated.dart' as rustlib;

bool _initialized = false;

/// 加载 Rust 动态库（只做一次）。
/// - `--dart-define=READER_CORE_SO=<path>`：显式指定（开发期/桌面）；
/// - Android：走 frb 默认 loader（.so 打包进 jniLibs，按 libreader_core.so 加载）；
/// - 其他平台：按平台默认名（reader_core.dll / libreader_core.dylib / libreader_core.so）。
Future<void> ensureRustLib() async {
  if (_initialized) return;
  const env = String.fromEnvironment('READER_CORE_SO');
  if (env.isNotEmpty) {
    await rustlib.RustLib.init(externalLibrary: frb.ExternalLibrary.open(env));
  } else if (Platform.isAndroid) {
    await rustlib.RustLib.init();
  } else {
    await rustlib.RustLib.init(
      externalLibrary: frb.ExternalLibrary.open(_defaultSoName()),
    );
  }
  _initialized = true;
}

String _defaultSoName() {
  if (Platform.isWindows) return 'reader_core.dll';
  if (Platform.isMacOS) return 'libreader_core.dylib';
  return 'libreader_core.so';
}

/// 应用支持目录（数据目录 <dir>/data 由 Rust 侧 library_open 使用）
Future<Directory> appSupportDir() async {
  final dir = await getApplicationSupportDirectory();
  return dir;
}
