/// 翻译浮层与词典卡片（REQ-003 最小 UI 方案，02-design §5.2）。
/// 可 widget 测试：loading（CircularProgressIndicator）/ 结果（Provider 名 + 缓存标记）/
/// 错误（文案 + 重试按钮）/ 词典卡片字段渲染 / "未找到"（US-2）与导入引导（US-3）。
library;

import 'package:flutter/material.dart';

import '../services/translate_backend.dart';

/// 译文结果卡片：译文 + Provider 名 + "缓存"徽标（US-13/15 可断言）
class TranslationResultCard extends StatelessWidget {
  const TranslationResultCard({super.key, required this.translation});

  final TranslationData translation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('译文', style: theme.textTheme.labelMedium),
                const Spacer(),
                if (translation.fromCache)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '缓存',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  )
                else
                  Text('在线', style: theme.textTheme.labelSmall),
                const SizedBox(width: 6),
                Text(
                  translation.provider,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(translation.text, style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

/// 词典卡片：词条/音标/词性/释义/例句（US-16）；entry==null → "未找到"（US-2）
class DictResultCard extends StatelessWidget {
  const DictResultCard({super.key, required this.entry});

  final DictEntryData? entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = entry;
    if (e == null) {
      return Card(
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text('未找到该词', style: theme.textTheme.bodyMedium),
        ),
      );
    }
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(e.word, style: theme.textTheme.titleMedium),
                if (e.pos != null) ...[
                  const SizedBox(width: 6),
                  Text(e.pos!, style: theme.textTheme.labelMedium),
                ],
                if (e.phonetic != null) ...[
                  const SizedBox(width: 6),
                  Text(e.phonetic!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(_stripHtml(e.definition), style: theme.textTheme.bodyMedium),
            if (e.example != null) ...[
              const SizedBox(height: 6),
              Text(
                '例句：${e.example}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 释义含 HTML（g 字段原样保留）→ 展示前极简剥标签（02-design §8 取舍6）
  static String _stripHtml(String s) => s.replaceAll(RegExp(r'<[^>]*>'), '');
}

/// 错误浮层：文案 + 重试按钮（US-12/15 可断言）
class OverlayError extends StatelessWidget {
  const OverlayError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 3,
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
