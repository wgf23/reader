// REQ-009 · 导出路径选择（桌面保存框取消 / 移动应用目录）测试（US-16/17）。
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/services/export_path_picker.dart';

/// 记录 saveFile 参数并返回预设路径的 FilePicker fake。
class _FakeFilePicker extends FilePicker {
  _FakeFilePicker({this.result});
  final String? result;
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    calls.add({
      'dialogTitle': dialogTitle,
      'fileName': fileName,
      'type': type,
      'allowedExtensions': allowedExtensions,
    });
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaultExportPathPicker 在桌面返回 Desktop 实现', () {
    expect(defaultExportPathPicker(), isA<DesktopExportPathPicker>());
  });

  test('桌面：saveFile 参数正确，返回所选路径', () async {
    final fake = _FakeFilePicker(result: '/tmp/我的书.md');
    FilePicker.platform = fake;
    final out = await const DesktopExportPathPicker()
        .pick(suggestedName: '我的书', extension: 'md');
    expect(out, '/tmp/我的书.md');
    expect(fake.calls.single['dialogTitle'], '导出笔记');
    expect(fake.calls.single['fileName'], '我的书.md');
    expect(fake.calls.single['type'], FileType.custom);
    expect(fake.calls.single['allowedExtensions'], ['md']);
  });

  test('桌面：用户取消（null）→ 返回 null，不写文件', () async {
    FilePicker.platform = _FakeFilePicker(result: null);
    final out = await const DesktopExportPathPicker()
        .pick(suggestedName: 'x', extension: 'json');
    expect(out, isNull);
  });

  test('移动：应用文档目录 + reader_notes + 非法字符替换 + 时间戳', () async {
    final tmp = Directory.systemTemp.createTempSync('req009_picker');
    addTearDown(() => tmp.deleteSync(recursive: true));

    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tmp.path;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final out = await const MobileExportPathPicker()
        .pick(suggestedName: 'a/b:c*d?e"f<g>h|i', extension: 'md');
    expect(out, isNotNull);
    expect(out, startsWith('${tmp.path}/reader_notes/'));
    expect(out, endsWith('.md'));
    final base = out!.split('/').last;
    // 非法字符全部替换为 _，且包含时间戳
    expect(base, startsWith('a_b_c_d_e_f_g_h_i_'));
    expect(base, isNot(contains(RegExp(r'[\\/:*?"<>|]'))));
    expect(Directory('${tmp.path}/reader_notes').existsSync(), isTrue);
  });
}
