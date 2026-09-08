/// 听书控制条（线框 `docs/wireframes/09-listen-player.svg`；REQ-005 · T-006）。
///
/// 自上而下：章节名 → 上一句 / 播放暂停 / 下一句 → 句级进度条 + 语速文本；
/// 右侧「定时」「音色」为 P2 禁用占位（`onPressed == null`）。
///
/// 句级进度条：拖动中本地预览，**松手**才回调 [onSeek]（避免拖动期间反复起播）。
library;

import 'package:flutter/material.dart';

/// 线框 09 控制条
class ListenControlBar extends StatefulWidget {
  const ListenControlBar({
    super.key,
    required this.chapterTitle,
    required this.playing,
    required this.speedText,
    required this.progress,
    required this.onPrevSentence,
    required this.onTogglePlay,
    required this.onNextSentence,
    required this.onSeek,
    this.onTimer,
    this.onVoice,
    this.timerLabel = '⏱ 30 分钟',
    this.voiceLabel = '🎙 系统男声',
    this.voiceFallback = false,
  });

  final String chapterTitle;
  final bool playing;
  final String speedText;

  /// 句级进度 0..1
  final double progress;

  final VoidCallback? onPrevSentence;
  final VoidCallback? onTogglePlay;
  final VoidCallback? onNextSentence;

  /// 拖动松手回调
  final ValueChanged<double>? onSeek;

  /// P2 占位（传 null → 禁用灰置）
  final VoidCallback? onTimer;
  final VoidCallback? onVoice;

  final String timerLabel;
  final String voiceLabel;

  /// 无匹配系统音色已回退默认 → 显示"系统默认音色"（REQ-006 US-21）。
  final bool voiceFallback;

  @override
  State<ListenControlBar> createState() => _ListenControlBarState();
}

class _ListenControlBarState extends State<ListenControlBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final value = (_dragValue ?? widget.progress).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF9AA0A6), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.chapterTitle,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: '上一句',
                      onPressed: widget.onPrevSentence,
                      icon: const Icon(Icons.skip_previous),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filled(
                      tooltip: widget.playing ? '暂停' : '播放',
                      iconSize: 34,
                      onPressed: widget.onTogglePlay,
                      icon: Icon(widget.playing ? Icons.pause : Icons.play_arrow),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: '下一句',
                      onPressed: widget.onNextSentence,
                      icon: const Icon(Icons.skip_next),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 116,
                    height: 32,
                    child: OutlinedButton(
                      onPressed: widget.onTimer,
                      child: Text(widget.timerLabel,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 116,
                    height: 32,
                    child: OutlinedButton(
                      onPressed: widget.onVoice,
                      child: Text(
                        widget.voiceFallback ? '🎙 系统默认音色' : widget.voiceLabel,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: value,
                  onChanged: widget.onSeek == null
                      ? null
                      : (v) => setState(() => _dragValue = v),
                  onChangeEnd: widget.onSeek == null
                      ? null
                      : (v) {
                          setState(() => _dragValue = null);
                          widget.onSeek!(v);
                        },
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.speedText,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A73E8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
