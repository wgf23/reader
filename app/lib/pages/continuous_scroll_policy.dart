/// 滚动模式连续滚动阅读的纯逻辑 + 可测出口（REQ-008 · ADR D1/D2/D3/D5）。
///
/// 分层：`app/lib/pages` = interface；只 import Flutter SDK + `services` DTO，
/// 不 import `package:reader_app/src/rust/`（ddd-rules.toml）。
///
/// 本文件承载：
/// - `ChapterContentProvider` / `ChapterResolution` / `ChapterContentCache`（D5，US-10）
/// - `ChapterGeometry` / `resolveVisibleChapter`（D2，US-5/6/7）
/// - `chapterProgression`（D3，US-3/5）
/// - `proportionalChapterOffset`（D4，US-4）
/// - `ChapterSection`（D1，US-11 以 `find.byType` 计数）
library;

import 'package:flutter/widgets.dart';

import '../services/library_backend.dart' show ChapterData;

/// 章节内容出口（D5）：生产 = `(i) => view.chapters[i]`；测试可对某章抛异常。
typedef ChapterContentProvider = ChapterData Function(int index);

/// 单章解析结果（成功 / 失败 + provider 调用次数）。
class ChapterResolution {
  const ChapterResolution._({this.chapter, this.error, required this.attempts});

  factory ChapterResolution.success(ChapterData chapter, int attempts) =>
      ChapterResolution._(chapter: chapter, attempts: attempts);

  factory ChapterResolution.failure(Object error, int attempts) =>
      ChapterResolution._(error: error, attempts: attempts);

  final ChapterData? chapter;
  final Object? error;

  /// 本章 provider 已被调用次数（≤ `maxAttempts`，显式 `retry` 除外）。
  final int attempts;

  bool get isFailure => chapter == null;
}

/// 记忆化章节缓存（D5 / US-10）。
///
/// 同一章 provider 最多调用 [maxAttempts] 次；失败被记忆，**不自动重试**；
/// [retry] 仅供用户显式重试（有界、显式）。
class ChapterContentCache {
  ChapterContentCache({required this.provider, this.maxAttempts = 1});

  final ChapterContentProvider provider;
  final int maxAttempts;

  final Map<int, ChapterResolution> _results = <int, ChapterResolution>{};
  final Map<int, int> _attempts = <int, int>{};

  /// 解析第 [index] 章：首次调用 provider；成功/失败均记忆化。
  ChapterResolution resolve(int index) {
    final cached = _results[index];
    if (cached != null) return cached;
    final attempts = _attempts[index] ?? 0;
    if (attempts >= maxAttempts) {
      // 防御：失败已被记忆化，正常不可达；保持有界（不无限调用 provider）。
      final r = ChapterResolution.failure(
        StateError('第 ${index + 1} 章重试次数已达上限（$maxAttempts）'),
        attempts,
      );
      _results[index] = r;
      return r;
    }
    final n = attempts + 1;
    _attempts[index] = n;
    try {
      final chapter = provider(index);
      final r = ChapterResolution.success(chapter, n);
      _results[index] = r;
      return r;
    } catch (e) {
      final r = ChapterResolution.failure(e, n);
      _results[index] = r;
      return r;
    }
  }

  /// 清失败记忆（用户点"重试"时调用）；下次 [resolve] 重新调用 provider。
  void retry(int index) {
    _results.remove(index);
    _attempts.remove(index);
  }

  /// 第 [index] 章 provider 已调用次数（未解析过为 0）。
  int attemptsOf(int index) => _attempts[index] ?? 0;
}

/// 已构建章在视口中的几何（D2）。
class ChapterGeometry {
  const ChapterGeometry({
    required this.index,
    required this.top,
    required this.height,
  });

  final int index;

  /// 章顶相对视口顶的 px（章顶在视口上方为负）。
  final double top;

  /// 章渲染高度（px）。
  final double height;

  /// 章在视口中可见高度占比（夹取到 [0,1]）。
  double visibleFraction(double viewportHeight) {
    if (height <= 0 || viewportHeight <= 0) return 0.0;
    final visibleTop = top < 0 ? 0.0 : top;
    final visibleBottom =
        (top + height) > viewportHeight ? viewportHeight : (top + height);
    final visible = visibleBottom - visibleTop;
    if (visible <= 0) return 0.0;
    return (visible / viewportHeight).clamp(0.0, 1.0);
  }
}

/// 可见章判定（D2：顶部锚点 + 迟滞 + 触底；纯函数，US-6 单测）。
///
/// [built] 按 index 升序，仅需包含已构建（视口 + cacheExtent）的章。
/// 规则：
/// - 触底 [atEnd] → 强制末章 [lastIndex]（处理短末章无法顶到视口顶）；
/// - [built] 为空 → 保持 [current]；
/// - `candidate` = 最后一个 `top <= hysteresis` 的已构建章（其起点已到达/越过视口顶部）；
///   若无（说明在所有已构建章之上），取 `built.first`；
/// - 向前切换（`candidate > current`）：要求 `candidate.top <= -hysteresis`；
/// - 向后切换（`candidate < current`）：要求 `current.top >= +hysteresis`。
int resolveVisibleChapter({
  required List<ChapterGeometry> built,
  required double viewportHeight,
  required int current,
  required int lastIndex,
  double hysteresis = 8.0,
  bool atEnd = false,
}) {
  if (atEnd) return lastIndex;
  if (built.isEmpty) return current;
  if (viewportHeight <= 0) return current;

  ChapterGeometry? candidate;
  for (final g in built) {
    if (g.top <= hysteresis) candidate = g;
  }
  candidate ??= built.first;

  if (candidate.index == current) return current;

  if (candidate.index > current) {
    // 向前：章顶越过 -hysteresis 才切换。
    return candidate.top <= -hysteresis ? candidate.index : current;
  }

  // 向后：当前章顶回落到 +hysteresis 以下（视口下方）才切换。
  final currentGeo = _geometryOf(built, current);
  if (currentGeo == null) return candidate.index;
  return currentGeo.top >= hysteresis ? candidate.index : current;
}

ChapterGeometry? _geometryOf(List<ChapterGeometry> built, int index) {
  for (final g in built) {
    if (g.index == index) return g;
  }
  return null;
}

/// 章内 progression（D3，纯函数，US-3/US-5 单测）：`(-top) / height` 夹取 [0,1]。
double chapterProgression({required double top, required double height}) {
  if (height <= 0) return 0.0;
  return ((-top) / height).clamp(0.0, 1.0);
}

/// 远跳/恢复的起点估算（D4，纯函数）：按章序比例映射到估算总高。
double proportionalChapterOffset({
  required int index,
  required int chapterCount,
  required double maxScrollExtent,
}) {
  if (chapterCount <= 1 || maxScrollExtent <= 0) return 0.0;
  final clamped = index.clamp(0, chapterCount - 1);
  return (maxScrollExtent * clamped / (chapterCount - 1))
      .clamp(0.0, maxScrollExtent);
}

/// 每章一个 item 的正文段落（公开 widget，供 US-11 以 `find.byType` 计数）。
///
/// 结构与既有单章渲染逐字一致：`Text(title, bold 18)` + `SizedBox(16)` + `Text(body)`。
class ChapterSection extends StatelessWidget {
  const ChapterSection({
    super.key,
    required this.index,
    required this.chapter,
    required this.fontSize,
    required this.lineHeight,
    required this.fontFamily,
    required this.foreground,
  });

  final int index;
  final ChapterData chapter;
  final int fontSize;
  final double lineHeight;
  final String? fontFamily;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          chapter.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 16),
        Text(
          chapter.text,
          style: TextStyle(
            color: foreground,
            fontSize: fontSize.toDouble(),
            height: lineHeight,
            fontFamily: fontFamily,
          ),
        ),
      ],
    );
  }
}
