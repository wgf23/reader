/// 翻译浮层与词典卡片（REQ-003 最小 UI 方案，02-design §5.2）。
/// 可 widget 测试：loading（CircularProgressIndicator）/ 结果（Provider 名 + 缓存标记）/
/// 错误（文案 + 重试按钮）/ 词典卡片字段渲染 / "未找到"（US-2）与导入引导（US-3）。
library;

import 'package:flutter/material.dart';

import '../services/translate_backend.dart';

/// 译文结果卡片：译文 + Provider 名 + 来源标签（REQ-006 US-18 可断言）
///
/// 标签映射：`fromCache → 缓存`；`provider=="offline" → 离线`；否则 `在线`；
/// 始终显示 provider 名；`fallbackReason != null` 追加回退提示行。
class TranslationResultCard extends StatelessWidget {
  const TranslationResultCard({super.key, required this.translation});

  final TranslationData translation;

  String get _sourceLabel {
    if (translation.fromCache) return '缓存';
    if (translation.provider == 'offline') return '离线';
    return '在线';
  }

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
                      _sourceLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  )
                else
                  Text(_sourceLabel, style: theme.textTheme.labelSmall),
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
            if (translation.fallbackReason != null) ...[
              const SizedBox(height: 6),
              Text(
                translation.fallbackReason!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
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

/// "翻译未配置"识别谓词（REQ-007 D5）：仅翻译未配置返回 true（查词错误不得命中）。
///
/// 锚定 core 文案契约 `未配置在线翻译 API Key` 与 ReaderPage 无后端时的
/// `未配置翻译后端`；集中一处，避免散落。
bool isTranslationNotConfiguredError(String message) =>
    message.contains('未配置在线翻译 API Key') ||
    message.contains('未配置翻译后端');

/// 错误浮层：文案 + 重试按钮（US-12/15 可断言）。
///
/// REQ-007 D5：可选 [onOpenSettings]（非 null 才渲染"去设置"），不传时行为与
/// 现状逐字一致（网络失败 / 查词错误不受影响）。
class OverlayError extends StatelessWidget {
  const OverlayError({
    super.key,
    required this.message,
    required this.onRetry,
    this.onOpenSettings,
    this.openSettingsLabel = '去设置',
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onOpenSettings;
  final String openSettingsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final openSettings = onOpenSettings;
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
            if (openSettings == null)
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('重试'),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.tonal(
                    onPressed: onRetry,
                    child: const Text('重试'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: openSettings,
                    child: Text(openSettingsLabel),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
