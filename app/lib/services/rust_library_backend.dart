/// Rust 核心后端：经 flutter_rust_bridge 调用 `reader_core`。
/// 设计：docs/03-architecture.md §4、docs/04 §7。
library;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:path_provider/path_provider.dart';

import '../src/rust/api.dart' as rust;
import '../src/rust/frb_generated.dart' as rustlib;
import 'library_backend.dart';

/// flutter_rust_bridge 实现的书库后端
class RustLibraryBackend implements LibraryBackend {
  static bool _initialized = false;

  /// 加载 Rust 动态库（只做一次）。
  /// 开发期：`--dart-define=READER_CORE_SO=<path>` 指定；默认取可执行目录旁的
  /// `libreader_core.so`（发布期由构建脚本拷贝，见 bridge/README.md）。
  Future<void> _ensureInit() async {
    if (_initialized) return;
    const env = String.fromEnvironment('READER_CORE_SO');
    final soPath = env.isNotEmpty ? env : 'libreader_core.so';
    await rustlib.RustLib.init(
      externalLibrary: frb.ExternalLibrary.open(soPath),
    );
    _initialized = true;
  }

  @override
  Future<void> open() async {
    await _ensureInit();
    final dir = await getApplicationSupportDirectory();
    await rust.libraryOpen(dataDir: '${dir.path}/data');
  }

  @override
  Future<List<rust.BookSummary>> list() => rust.libraryList();

  @override
  Future<rust.BookSummary> import(String path) => rust.libraryImport(path: path);

  @override
  Future<rust.BookView> openBook(String id) => rust.bookOpen(id: id);

  @override
  Future<void> remove(String id) => rust.libraryRemove(id: id);
}
