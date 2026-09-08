import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/rust_translate_backend.dart';
import '../services/translate_backend.dart';

/// 设置页（线框 03）。REQ-003：新增"词典与翻译"最小区块（TRANS-01 验收"可安装/移除词库
/// （设置页）"+ TRANS-02 Provider key 最小配置通道 + 隐私"清空翻译缓存"；docs/02 §10）。
/// REQ-006：该区块内新增「翻译策略」下拉 + key 掩码回填（不回填明文，`_keyDirty` 控制写回）。
/// TRANS-03 进阶管理 UI（Provider 启停/离线开关）不在本 REQ。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.translateBackend, this.filePicker});

  /// 测试注入用；默认 Rust 后端
  final TranslateBackend? translateBackend;

  /// 测试注入用（widget 测试环境无 file_picker 平台实现）；默认走 FilePicker
  final Future<String?> Function()? filePicker;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TranslateBackend _backend =
      widget.translateBackend ?? RustTranslateBackend();
  final TextEditingController _keyController = TextEditingController();

  List<DictInfoData>? _dicts;
  String? _message;
  bool _busy = false;

  /// 当前翻译策略（"auto"/"offline"/"deepl"/"echo"；REQ-006 US-15）
  String _strategy = 'auto';

  /// 是否已配置 DeepL key（用于回填掩码）
  bool _hasKey = false;

  /// 用户是否编辑过 key 输入框（未编辑时保存**不写** key，避免掩码写回）
  bool _keyDirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _backend.listDicts();
      final config = await _backend.getConfig();
      if (mounted) {
        setState(() {
          _dicts = list;
          _strategy = config.provider;
          _hasKey = config.hasDeeplKey;
          _keyDirty = false;
          _keyController.text =
              config.hasDeeplKey ? (config.deeplKeyMasked ?? '••••••••') : '';
        });
      }
    } catch (_) {
      // 后端未初始化等：列表留空，不阻塞设置页
      if (mounted) setState(() => _dicts = const []);
    }
  }

  Future<void> _importDict() async {
    final picker = widget.filePicker ??
        () async {
          final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['ifo'],
            dialogTitle: '选择 StarDict 词库（.ifo）',
          );
          return result?.files.first.path;
        };
    final path = await picker();
    if (path == null) return;
    setState(() => _busy = true);
    try {
      final info = await _backend.installDict(path);
      if (mounted) {
        setState(() {
          _message = '已安装词库：${info.name}（${info.wordCount} 词条）';
          _busy = false;
        });
      }
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = '导入失败：$e';
          _busy = false;
        });
      }
    }
  }

  Future<void> _removeDict(DictInfoData d) async {
    try {
      await _backend.removeDict(d.id);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _message = '移除失败：$e');
    }
  }

  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    try {
      if (_keyDirty) {
        if (key.isEmpty) {
          // 空 key 保存 = 清除（明确提示，不静默覆盖）
          await _backend.setConfig('deepl', '');
          if (mounted) {
            setState(() => _message = '已清除 DeepL API Key（当前未配置在线翻译）');
          }
        } else {
          await _backend.setConfig('deepl', key);
          if (mounted) setState(() => _message = '已保存 DeepL API Key');
        }
      } else if (mounted) {
        setState(() => _message = '已保存翻译策略');
      }
      // 保存 key 后回到默认在线优先策略（用户所选策略为准）。
      await _backend.setStrategy(_strategy);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _message = '保存失败：$e');
    }
  }

  Future<void> _clearCache() async {
    try {
      await _backend.clearCache();
      if (mounted) setState(() => _message = '翻译缓存已清空');
    } catch (e) {
      if (mounted) setState(() => _message = '清空失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dicts = _dicts;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('词典与翻译', style: Theme.of(context).textTheme.titleMedium),
          const Divider(),
          // 词库导入
          Row(
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _importDict,
                icon: const Icon(Icons.add),
                label: const Text('导入词库（.ifo）'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (dicts == null)
            const Center(child: CircularProgressIndicator())
          else if (dicts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('未安装词库 —— 查词不可用，请先导入（离线查词需词库）'),
            )
          else
            for (final d in dicts)
              ListTile(
                dense: true,
                leading: const Icon(Icons.menu_book),
                title: Text(d.name),
                subtitle: Text('${d.wordCount} 词条'),
                trailing: IconButton(
                  tooltip: '移除词库',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeDict(d),
                ),
              ),
          const SizedBox(height: 12),
          // 翻译策略（REQ-006 US-15）
          DropdownButtonFormField<String>(
            key: ValueKey<String>('translate-strategy-$_strategy'),
            initialValue: _strategy,
            decoration: const InputDecoration(
              labelText: '翻译策略',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'auto', child: Text('自动（在线优先）')),
              DropdownMenuItem(value: 'offline', child: Text('离线词典')),
              DropdownMenuItem(value: 'deepl', child: Text('DeepL 在线')),
              DropdownMenuItem(value: 'echo', child: Text('Echo（演示）')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _strategy = v);
            },
          ),
          const SizedBox(height: 12),
          // Provider key
          Text('在线翻译 Provider（DeepL）', style: Theme.of(context).textTheme.titleSmall),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keyController,
                  decoration: InputDecoration(
                    labelText: 'DeepL API Key',
                    hintText: _hasKey
                        ? '已配置（留空不修改；清空并保存可清除）'
                        : '留空 = 未配置（翻译不可用，可切 echo 演示）',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  obscureText: true,
                  onChanged: (v) => _keyDirty = true,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _saveKey, child: const Text('保存')),
            ],
          ),
          const SizedBox(height: 12),
          // 隐私：清空翻译缓存
          OutlinedButton.icon(
            onPressed: _clearCache,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('清空翻译缓存'),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_message!, style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
