/// 阅读器顶栏 + 底栏（原型 reader-ui-v2/02-menus.svg）。
library;

import 'package:flutter/material.dart';

/// 顶栏：‹ 返回 ｜ 书名·章节名 ｜ ⋯ 更多
class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    super.key,
    required this.title,
    required this.chapter,
    required this.onBack,
    required this.onMore,
  });

  final String title;
  final String chapter;
  final VoidCallback onBack;
  final void Function() onMore;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFECEEF1),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              IconButton(tooltip: '返回书架', onPressed: onBack, icon: const Icon(Icons.arrow_back)),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(chapter, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              IconButton(tooltip: '更多', onPressed: onMore, icon: const Icon(Icons.more_horiz)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底栏：上一章 ｜ ☰目录 ｜ 进度条+% ｜ 🔖 ｜ Aa ｜ 下一章
class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({
    super.key,
    required this.chapterIndex,
    required this.chapterCount,
    required this.progress,
    required this.bookmarked,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onDirectory,
    required this.onBookmark,
    required this.onSettings,
    required this.onProgressChanged,
    required this.onProgressSeek,
  });

  final int chapterIndex;
  final int chapterCount;
  final double progress;
  final bool bookmarked;
  final VoidCallback onPrevChapter;
  final VoidCallback onNextChapter;
  final VoidCallback onDirectory;
  final VoidCallback onBookmark;
  final VoidCallback onSettings;

  /// 拖动中（预览，不跳转）
  final ValueChanged<double> onProgressChanged;

  /// 松手（跳转 + saveProgress）
  final ValueChanged<double> onProgressSeek;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFECEEF1),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              TextButton(
                onPressed: chapterIndex > 0 ? onPrevChapter : null,
                child: const Text('上一章'),
              ),
              IconButton(tooltip: '目录', onPressed: onDirectory, icon: const Icon(Icons.menu_book)),
              // 进度条 + 百分比（可拖，松手跳转）
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
                  child: Slider(
                    value: progress.clamp(0.0, 1.0),
                    onChanged: onProgressChanged,
                    onChangeEnd: onProgressSeek,
                  ),
                ),
              ),
              SizedBox(width: 36, child: Text('${(progress * 100).round()}%', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12))),
              IconButton(
                tooltip: bookmarked ? '取消书签' : '加书签',
                onPressed: onBookmark,
                icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border,
                    color: bookmarked ? Colors.redAccent : null),
              ),
              TextButton(
                style: TextButton.styleFrom(backgroundColor: const Color(0xFFE1E4E8), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 12)),
                onPressed: onSettings,
                child: const Text('Aa', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: chapterIndex < chapterCount - 1 ? onNextChapter : null,
                child: const Text('下一章'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
