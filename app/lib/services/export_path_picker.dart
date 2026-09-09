/// 导出路径选择（可注入；ADR REQ-009 D8）。
///
/// - 桌面：`FilePicker.platform.saveFile`（用户取消 → null，不写文件）；
/// - 移动：`path_provider` 应用文档目录 `reader_notes/`。
library;

import 'dart:io' show Platform, Directory;

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

abstract class ExportPathPicker {
  /// 返回目标绝对路径；用户取消返回 null。
  Future<String?> pick({
    required String suggestedName,
    required String extension,
  });
}

/// 桌面：系统保存对话框。
class DesktopExportPathPicker implements ExportPathPicker {
  const DesktopExportPathPicker();

  @override
  Future<String?> pick({
    required String suggestedName,
    required String extension,
  }) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出笔记',
      fileName: '$suggestedName.$extension',
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    return path; // 取消 → null
  }
}

/// 移动端：应用文档目录（路径可观察/分享）。
class MobileExportPathPicker implements ExportPathPicker {
  const MobileExportPathPicker();

  @override
  Future<String?> pick({
    required String suggestedName,
    required String extension,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/reader_notes');
    if (!exportDir.existsSync()) {
      exportDir.createSync(recursive: true);
    }
    final safe = suggestedName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${exportDir.path}/${safe}_$ts.$extension';
  }
}

/// 按平台选择默认实现（测试注入 fake 时不会被调用）。
ExportPathPicker defaultExportPathPicker() =>
    (Platform.isAndroid || Platform.isIOS)
        ? const MobileExportPathPicker()
        : const DesktopExportPathPicker();
