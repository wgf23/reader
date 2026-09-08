/// 听书设置面板（线框 `docs/wireframes/10-listen-settings.svg`；REQ-005 · T-009）。
///
/// - 音色：系统男声/系统女声可选；AI 音色/Piper/声音克隆 **禁用灰置**（P2，线框文案）；
/// - 语速：0.5x–3.0x 滑块，实时生效并持久化（`listen.speed`）；
/// - 定时关闭分组与后台播放 **全部禁用灰置**（明确不做，01-req §1.2）。
///
/// 实现为 `StatefulWidget`（局部态保证滑块/单选即时反馈；每次变更回调父页做引擎+持久化）。
library;

import 'package:flutter/material.dart';

import '../services/tts_backend.dart';

/// 线框 10 听书设置面板
class ListenSettingsSheet extends StatefulWidget {
  const ListenSettingsSheet({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    required this.onClose,
    this.voiceFallback = false,
  });

  final ListenSettingsData settings;
  final ValueChanged<ListenSettingsData> onSettingsChanged;
  final VoidCallback onClose;

  /// 无匹配系统音色已回退默认 → 显示"系统默认音色"提示（REQ-006 US-21）。
  final bool voiceFallback;

  @override
  State<ListenSettingsSheet> createState() => _ListenSettingsSheetState();
}

class _ListenSettingsSheetState extends State<ListenSettingsSheet> {
  late ListenSettingsData _settings = widget.settings;

  static const _timerOptions = ['关闭', '15 分钟', '30 分钟', '60 分钟', '本章结束'];

  void _update(ListenSettingsData next) {
    setState(() => _settings = next);
    widget.onSettingsChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '听书设置',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // ---------- 音色 ----------
            const Text('音色', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            if (widget.voiceFallback)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '当前：系统默认音色（未找到所选音色）',
                  style: TextStyle(fontSize: 12, color: Color(0xFFB71C1C)),
                ),
              ),
            RadioGroup<String>(
              groupValue: _settings.voiceId,
              onChanged: (v) {
                if (v != null) _update(_settings.copyWith(voiceId: v));
              },
              child: const Column(
                children: [
                  RadioListTile<String>(
                    value: 'system_male',
                    title: Text('系统男声'),
                    secondary: Text('离线'),
                    dense: true,
                  ),
                  RadioListTile<String>(
                    value: 'system_female',
                    title: Text('系统女声'),
                    secondary: Text('离线'),
                    dense: true,
                  ),
                  RadioListTile<String>(
                    value: 'ai',
                    enabled: false,
                    title: Text('AI 音色 · 在线'),
                    secondary: Text('需网络（P2）'),
                    dense: true,
                  ),
                  RadioListTile<String>(
                    value: 'piper',
                    enabled: false,
                    title: Text('本地神经音色 Piper'),
                    secondary: Text('下载 52MB（P2）'),
                    dense: true,
                  ),
                  ListTile(
                    enabled: false,
                    dense: true,
                    title: Text('声音克隆 · 评估中'),
                  ),
                ],
              ),
            ),
            const Divider(),
            // ---------- 语速 ----------
            const Text('语速', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    min: 0.5,
                    max: 3.0,
                    divisions: 25,
                    value: _settings.speed.clamp(0.5, 3.0),
                    onChanged: (v) {
                      final rounded = (v * 10).round() / 10;
                      _update(_settings.copyWith(speed: rounded));
                    },
                  ),
                ),
                Text(
                  '${_settings.speed.toStringAsFixed(1)}x',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A73E8),
                  ),
                ),
              ],
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0.5x', style: TextStyle(fontSize: 12, color: Color(0xFF5F6368))),
                Text('3.0x', style: TextStyle(fontSize: 12, color: Color(0xFF5F6368))),
              ],
            ),
            const Divider(),
            // ---------- 定时关闭（P2 全禁用） ----------
            const Text('定时关闭', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            RadioGroup<String>(
              groupValue: '30 分钟',
              onChanged: (_) {},
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final label in _timerOptions)
                    SizedBox(
                      width: 148,
                      child: RadioListTile<String>(
                        value: label,
                        enabled: false,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(label, style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            // ---------- 后台播放（P2 禁用） ----------
            const SwitchListTile(
              value: true,
              onChanged: null,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('后台播放', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF9AA0A6)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '在线 AI 音色需网络与费用，会把正文文本发送至 TTS 服务商；离线音色不联网、隐私无忧',
                style: TextStyle(fontSize: 11, color: Color(0xFF5F6368)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
