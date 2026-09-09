<!-- wf-meta: req=REQ-008-continuous-scroll | phase=architecture | agent=architect | date=2026-09-09 | gate=passed -->
# REQ-008 · 模块/接口设计（连续滚动：渲染编排 / 可见章判定 / 章内进度 / 跨章恢复 / 失败路径 / 节流可测）

> 依据：`01-req.md`（US-1..US-13 + R1..R11 + 风险 §5）、`02-adr.md`（D1..D8）。
> DDD 分层标注：**interface** = `core/src/api.rs`、`app/lib/pages`、`app/lib/engines`（禁 import
> `package:reader_app/src/rust/`、`src/rust/`）；**application** = `core/src/library`、`app/lib/services`；
> **domain** = `core/src/format|convert|locator|notes|dict|search|tts` 等（禁依赖 `crate::store/api/library`）；
> **infrastructure** = `core/src/store`、`app/lib/src/rust`。
> 硬约束：零 schema 变更、零 FFI、零新增依赖、零布局自创。

---

## 1. 模块与职责变化

| 模块 | 层 | 变化 | 对应决策 |
|---|---|---|---|
| `app/lib/pages/continuous_scroll_policy.dart` | interface（新） | 连续滚动纯逻辑：`ChapterContentProvider`/`ChapterContentCache`/`ChapterResolution`、`ChapterGeometry`/`resolveVisibleChapter`、`chapterProgression`、`proportionalChapterOffset` | D1/D2/D3/D4/D5 |
| `app/lib/pages/progress_saver.dart` | interface（新） | `ProgressSaver`：尾沿 300ms 防抖 + `flush()`；可注入 `save`/`debounce` | D6 |
| `app/lib/pages/reader_page.dart` | interface（改） | 滚动分支由 `SingleChildScrollView` 单章改为 `SelectionArea` + `CustomScrollView` + `SliverList.builder` 多章懒构建；`ChapterSection` 公开 widget；`_onScroll`/`_goChapter`/`_jumpToProgress`/`_onProgressSeek`/`_onChapterSelect`/`_load`/`_reloadProgress` 改为连续流语义；新增可选 `chapterProvider`；`ProgressSaver` 接线 | D1..D8 |
| `app/lib/widgets/reader_chrome.dart` | interface（零改动） | 入参语义不变，仅由页面传入"可见章"值 | D2/D3 |
| `app/lib/services/library_backend.dart` | application（零改动） | `BookViewData`/`ChapterData`/`ProgressData`/`saveProgress`/`loadProgress` 全不变 | D3/D4 |
| `app/lib/engines/reflow_engine.dart` | interface（零改动） | 本 REQ 不扩（ADR D7） | D7 |
| `app/lib/pages/listen_page.dart` | interface（零改动） | 听书跨章/写进度语义不变，仅作回归面 | — |
| `app/lib/pages/body_tap_policy.dart` | interface（零改动） | 拖动判非 tap，连续滚动拖拽不误触 Chrome | — |
| `app/lib/engines/paged_view_controls.dart` / `paged_web_view.dart` | interface（零改动） | 分页路径保留；切回滚动时页面重新定位 | — |
| `core/**` | domain/infrastructure（零改动） | 无签名/DTO/schema/迁移/FFI 变更 | — |

---

## 2. 接口签名（Dart）

### 2.1 连续滚动纯逻辑（interface，新）

```dart
// app/lib/pages/continuous_scroll_policy.dart
import 'package:flutter/rendering.dart' show RenderBox, RenderAbstractViewport;
import 'package:flutter/widgets.dart';

import '../services/library_backend.dart' show ChapterData;

/// 章节内容出口（D5）：生产 = (i) => view.chapters[i]；测试可对某章抛异常。
typedef ChapterContentProvider = ChapterData Function(int index);

/// 单章解析结果。
class ChapterResolution {
  const ChapterResolution._({this.chapter, this.error, required this.attempts});
  factory ChapterResolution.success(ChapterData chapter, int attempts) =>
      ChapterResolution._(chapter: chapter, attempts: attempts);
  factory ChapterResolution.failure(Object error, int attempts) =>
      ChapterResolution._(error: error, attempts: attempts);

  final ChapterData? chapter;
  final Object? error;
  final int attempts;         // 本章 provider 已被调用次数（≤ maxAttempts，除显式 retry）
  bool get isFailure => chapter == null;
}

/// 记忆化章节缓存（D5/US-10）：同一章 provider 最多调用 maxAttempts 次；
/// 失败被记忆，不自动重试；retry(i) 仅供用户显式重试。
class ChapterContentCache {
  ChapterContentCache({required this.provider, this.maxAttempts = 1});
  final ChapterContentProvider provider;
  final int maxAttempts;

  ChapterResolution resolve(int index);
  void retry(int index);
  int attemptsOf(int index);
}

/// 已构建章在视口中的几何（D2）。
class ChapterGeometry {
  const ChapterGeometry({required this.index, required this.top, required this.height});
  final int index;
  final double top;      // 章顶相对视口顶的 px（章顶在视口上方为负）
  final double height;   // 章渲染高度（px）

  double visibleFraction(double viewportHeight); // 夹取到 [0,1]
}

/// 可见章判定（D2，顶部锚点 + 迟滞 + 触底；纯函数，US-6 单测）。
/// [built] 按 index 升序，仅需包含已构建（视口 + cacheExtent）的章。
int resolveVisibleChapter({
  required List<ChapterGeometry> built,
  required double viewportHeight,
  required int current,
  required int lastIndex,
  double hysteresis = 8.0,   // px
  bool atEnd = false,        // pixels >= maxScrollExtent - 1.0
});

/// 章内 progression（D3，纯函数，US-3/US-5 单测）：`(-top)/height` 夹取 [0,1]。
double chapterProgression({required double top, required double height});

/// 远跳/恢复的起点估算（D4，纯函数）：按章序比例映射到估算总高。
double proportionalChapterOffset({
  required int index,
  required int chapterCount,
  required double maxScrollExtent,
});
```

### 2.2 进度落盘（interface，新）

```dart
// app/lib/pages/progress_saver.dart
import 'dart:async';

typedef ProgressSave = Future<void> Function(String href, double progression);

/// 尾沿防抖（D6/US-3）：滚动过程 schedule（300ms 内合并）；显式动作 flush。
class ProgressSaver {
  ProgressSaver({
    required ProgressSave save,
    this.debounce = const Duration(milliseconds: 300),
  });

  final Duration debounce;

  /// 记录最新位置并重置 300ms 尾沿计时器；到期以"最后一次"值落盘。
  void schedule(String href, double progression);

  /// 立即落盘并取消计时器（切章/进度条松手/目录/听书返回/切模式/dispose）。
  Future<void> flush(String href, double progression);

  /// 释放计时器（dispose）。
  void dispose();
}
```

### 2.3 页面接线（interface，改）

```dart
// app/lib/pages/reader_page.dart
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.bookId,
    required this.bookTitle,
    required this.backend,
    this.translateBackend,
    this.pagedViewBuilder,
    this.pagedControls,
    this.initialPagedMode = false,
    this.ttsBackend,
    this.ttsEngine,
    this.chapterProvider,   // 新增（D5）：测试注入失败/空章出口；null → view.chapters[i]
  });
  final ChapterContentProvider? chapterProvider;
  // 其余字段不变
}

/// 每章一个 item 的正文段落（公开 widget，供 US-11 以 find.byType 计数）。
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
  Widget build(BuildContext context);
  // 结构：Text(chapter.title, bold 18) + SizedBox(16) + Text(chapter.text, 既有样式)
}
```

**内部状态/方法（`_ReaderPageState`，关键）**：

```dart
final GlobalKey _scrollViewKey = GlobalKey();
final List<GlobalKey> _chapterKeys = <GlobalKey>[]; // 与 view.chapters 等长
ChapterContentCache? _chapterCache;
late ProgressSaver _progressSaver;
bool _chapterLocked = false;        // 程序化定位后锁定可见章，直到用户真实拖动

void _onScroll();                   // 计算几何 → 可见章/章内进度 → 按需 setState → schedule 落盘
Future<void> _scrollToChapter(int index, double progression); // ensureVisible + progression×章高
void _goChapter(int delta);         // 目标章定位 + flush
void _onChapterSelect(int i);       // 目录跳转
Future<void> _onProgressSeek(double v); // 当前章内定位 + flush
Future<void> _reloadProgress();     // 听书返回：读进度 → _scrollToChapter
String _hrefForIndex(int index);    // chapter_%04d.xhtml（沿用 _hrefFor 语义）
```

### 2.4 滚动分支结构（D1）

```dart
// _buildArticleBody(...) 滚动分支（分页分支不变）
return SelectionArea(
  onSelectionChanged: (content) => _onSelectedText(_sliceSelection(content)),
  contextMenuBuilder: (context, state) => const SizedBox.shrink(),
  child: NotificationListener<ScrollNotification>(
    onNotification: (n) {
      if (n is ScrollStartNotification && n.dragDetails != null) {
        _chapterLocked = false; // 用户真实拖动 → 解锁可见章判定（D2）
      }
      return false;
    },
    child: CustomScrollView(
      key: _scrollViewKey,
      controller: _scrollController,
      cacheExtent: 250.0, // US-11 有界构建：视口 + 250px
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 64), // 与现状等价
          sliver: SliverList.builder(
            itemCount: view.chapters.length,
            itemBuilder: (context, i) => _buildChapterItem(context, view, i),
          ),
        ),
      ],
    ),
  ),
);
```

`_buildChapterItem`：`final r = _chapterCache!.resolve(i);`
- `r.chapter != null` → `Padding(padding: EdgeInsets.only(bottom: i < last ? 32 : 0), child: ChapterSection(key: _chapterKeys[i], ...))`
  （章间距 32 = 行为性增量，见 §5）；
- `r.isFailure` → `Padding(bottom: 32, child: OverlayError(message: '第 ${i+1} 章加载失败，请稍后重试', onRetry: () => setState(() => _chapterCache!.retry(i))))`。

---

## 3. 数据模型变化

**零变更（预期）**。逐项确认：

| 项 | 结论 |
|---|---|
| `reading_progress` 表 `(book_id PK, href, progression, updated_at)`（`core/src/store/mod.rs:283-289`） | 零变更；`href=chapter_%04d.xhtml`、`progression∈[0,1]` 章内值 |
| `ProgressData{href, progression}`（`library_backend.dart:44-49`） | 零变更 |
| `BookViewData` / `ChapterData`（`library_backend.dart:25-42`） | 零变更（连续流所需数据已在内存，R11） |
| `Locator` / `TextAnchor` / `Rect`（`core/src/types.rs`） | 零变更；`LocatorResolver` 仍 stub，本 REQ 不扩 |
| `saveProgress` / `loadProgress` 签名（`:65`/`:67`） | 零变更 |
| `user_version` / 迁移 / FRB 生成物 | 零变更（无新 FFI/DTO） |
| `settings` / `translation_cache` / `annotations` | 零变更 |

> 新增的 `ChapterContentProvider`/`ChapterContentCache`/`ProgressSaver`/`ChapterSection` 均为
> **UI 运行时对象**，不落库、不过桥。

---

## 4. 关键时序

### 4.1 打开/恢复（US-4，跨章）

```
ReaderPage.initState → _load()
  → backend.openBook(bookId) → BookViewData（全部章在内存）
  → backend.loadProgress(bookId) → ProgressData{href, progression}
  → _chapterIndexForHref(href) → start（沿用 :148-156）
  → _chapterProgress = progression.clamp(0,1)
  → 建 _chapterKeys（等长）+ _chapterCache（provider 默认取 view.chapters[i]）
  → setState(_view=view, _chapterIndex=start)
  → build：CustomScrollView 首帧从章 0 开始（sliver 懒构建）
  → addPostFrameCallback → _scrollToChapter(start, _chapterProgress)
        ├─ 目标章已构建 → Scrollable.ensureVisible(alignment:0) → jumpTo(offset + p×章高)
        └─ 未构建 → jumpTo(proportionalChapterOffset) → 逐帧（≤min(count,50)）步进至目标构建 → 同上
  → _chapterLocked = true（直到用户真实拖动）
```

### 4.2 滚动（US-1/2/3/5/6）

```
用户 drag/fling → Scrollable 滚动（SliverList 按视口 + cacheExtent 懒构建下一章）
  → ScrollController.addListener(_onScroll)
      → 收集已构建章几何：
            box = key.currentContext.findRenderObject() as RenderBox
            top = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset - position.pixels
            height = box.size.height
      → atEnd = position.pixels >= position.maxScrollExtent - 1.0
      → 若 !_chapterLocked：
            idx = resolveVisibleChapter(built, viewportHeight, _chapterIndex, last, atEnd: atEnd)
            p   = chapterProgression(top: 章[idx].top, height: 章[idx].height)
            chapterChanged = idx != _chapterIndex
            _chapterProgress = p
            if (chapterChanged || (_chromeVisible && p 变化)) setState(更新 _chapterIndex/_chapterProgress)
            _progressSaver.schedule(_hrefForIndex(idx), p)     // 300ms 尾沿
  → 滚到末章继续 drag：SliverList 无更多 item，pixels 停在 maxScrollExtent，无异常（US-2）
```

### 4.3 章切换/目录/进度条（US-5/7）

```
底栏"下一章" → _goChapter(+1)
  → target = clamp(_chapterIndex+delta, 0, count-1)
  → setState(_chapterIndex=target, _chapterProgress=0, _selectedText=null, _resetPopups())
  → _progressSaver.flush(href(target), 0.0)     // 立即落盘（保持既有断言）
  → _scrollToChapter(target, 0.0) → _chapterLocked = true
  → 顶栏章节名/底栏进度/章节序号随 setState 更新（reader_chrome 零改动）

目录选第 i 章 → _onChapterSelect(i)（同上 + Navigator.pop）
进度条松手 → _onProgressSeek(v)：_chapterProgress=v → jumpTo(章顶 + v×章高) → flush(href, v)
```

### 4.4 听书往返（US-8，听读同进度）

```
点"听书" → _openListen 传 href=_hrefForIndex(_chapterIndex)、progression=_chapterProgress（可见章值）
ListenPage 内部跨章朗读并写 reading_progress(href2, p2)（listen_page.dart:196-230，零改动）
返回 → _reloadProgress() → loadProgress → _chapterIndexForHref → _scrollToChapter(idx, p2)
  → 连续滚动仍可自动接续；backend.saved.href 仍为听书写入值
```

### 4.5 失败路径（US-10）

```
_chapterCache.resolve(i) 首次调用 provider(i)
  ├─ 成功 → 缓存，渲染 ChapterSection
  └─ 抛异常/返回不可用 → 缓存失败 + attempts=1
        → 该章位置渲染 OverlayError('第 i+1 章加载失败，请稍后重试', onRetry: retry(i))
        → 相邻已渲染章保留；takeException()==null
  → 后续 rebuild：命中失败记忆，provider 不再被调用（attempts 仍 =1，重试有界）
  → 用户点"重试" → retry(i) 清失败记忆 → 下一帧重新 resolve（显式、有界）
```

### 4.6 模式切换与重排（US-9/REQ-004 回归）

```
Aa 面板切分页模式（pagedMode=true）→ 分页分支渲染 view.chapters[_chapterIndex]（现状不变）
Aa 面板切回滚动（pagedMode=false）→ build 重建 sliver → post-frame _scrollToChapter(_chapterIndex, _chapterProgress)
  → 连续滚动仍工作；进度语义不变
Aa 面板改字号/字体/主题/行距 → setState 重建 sliver（章高变化）→ post-frame
  _scrollToChapter(_chapterIndex, _chapterProgress) 以"章序号 + 章内比例"重新锚定，不跳变
```

---

## 5. 逐屏映射原型图（`docs/wireframes/**` 为 UI 权威；禁止自创布局）

| 原型图 | 涉及交互 | 本设计落点 | 布局变化 |
|---|---|---|---|
| `reader-ui-v2/01-immersive.svg` | 沉浸态正文全屏；中部 1/3 点击呼出/隐藏；左右 15% 仅分页翻页；长按选词 | 连续流沿用同一正文排版；每章 `ChapterSection` = 既有"章标题 + 16px + 正文"结构；下一章标题随滚动进入视口（US-1）。中部点击/长按/边缘热区由 `body_tap_policy.dart` 保持不变 | **零新增控件/颜色/字号**；唯一行为性增量 = 章与章之间 `32px` 间距（复用正文留白节奏，非新元素） |
| `reader-ui-v2/02-menus.svg` | 顶栏 返回/书名·章节/更多；底栏 上一章·☰目录·可拖进度条·书签·Aa·下一章 | 顶栏 `chapter` = 可见章标题（`_chapterIndex`）；底栏 `progress` = 可见章内比例（`_chapterProgress`）；上一章/下一章/目录 = `_scrollToChapter`；`reader_chrome.dart` 零改动 | **无**（控件集合/位置/尺寸不变，仅数据随可见章刷新） |
| 失败提示（无新增原型） | 下一章不可用 | 复用既有 `OverlayError` 样式（`translation_popup.dart:147-181`）内联在失败章位置，文案含"加载失败" | **无新增布局体系**（复用现有错误卡片样式） |
| `reader-ui-v2/04-selection.svg` | 选中浮动工具条 + 结果卡片 | 外层 `SelectionArea` 继续承载选中/工具条；跨章选中为自然结果 | **无**（零改动回归） |
| `reader-ui-v2/03-settings.svg`（Aa） | 字号/字体/主题/行距/翻页模式 | 滚动样式映射不变；切回滚动重新定位 | **无** |

> **偏差目标 = 0**。章间距（32px）是连续多章的排版必然结果，不是新增 UI 元素；产品验收时按
> "无新增控件/颜色/字号、控件集合与 02-menus 一致"判定。若产品认为章间距需调整，属参数调整，
> 不改结构。

---

## 6. 测试分层与可测出口映射（供 02-plan 引用）

| 层 | 文件 | 覆盖 US | 可测出口 |
|---|---|---|---|
| [单测] | `app/test/continuous_scroll_policy_test.dart` | US-6/US-10 | `resolveVisibleChapter`（顶部锚点/迟滞/触底/程序化锁定语义）、`chapterProgression`（0/0.5/1/越界夹取）、`proportionalChapterOffset`、`ChapterContentCache`（≤1 次/章、失败记忆化、retry） |
| [单测] | `app/test/progress_saver_test.dart` | US-3 | `ProgressSaver`：`schedule` 300ms 内合并为 1 次尾沿、`flush` 立即且取消计时器、dispose 释放（`testWidgets` + `tester.pump`） |
| [widget] | `app/test/reader_continuous_scroll_test.dart` | US-5/US-6/US-7/US-9/US-10/US-11 | 顶栏章节名/底栏 `Slider.value` 跨章切换；抖动去重（`find.text` findsOneWidget）；上一章/目录跳转 + `saved.href`；书签/分页切换回归；注入失败 provider（保留内容 + 文案 + attempts）；50 章有界（`find.byType(ChapterSection)` ≤3） |
| [widget] | `app/test/reader_page_test.dart`（既有，兼容） | 回归 | 既有 18 个用例保持通过（见 §7 兼容性） |
| [集成测试] | `app/integration_test/reader_continuous_scroll_test.dart` | US-1/US-2/US-3/US-4/US-8 | 真实 `ReaderPage` + 真实 `drag`/`fling`；滚动到底 → 下一章正文/标题出现且 `ReaderBottomBar` findsNothing；末章停止不越界；滚动中 `backend.saved.href/progression`；重建恢复跨章；听书写入后返回定位 |
| [集成测试] | `app/integration_test/reader_interaction_test.dart`（既有，1 处 finder 调整） | 回归 US-2 拖拽 | `find.byType(CustomScrollView)` |
| [单测] | `app/test/no_synthetic_chrome_test.dart`（既有，自动覆盖新文件） | US-12 | 扫描 `integration_test/*.dart` 无 `ReaderTopBar(`/`ReaderBottomBar(` |
| [真机] | 交付清单 | US-13 | 连续滚动/末章停止/重开恢复/听书返回/书签+分页切换 |

**平台约束**：`flutter_inappwebview` 无 Linux 实现 → `flutter test integration_test -d linux`（xvfb）
只跑滚动模式；分页走 [widget 测试] + 真机。

---

## 7. 与既有约定的兼容性

- [x] **不破坏 Locator 模型**：`progression` 恒为可见章内 `[0,1]`；`href` 恒为 `chapter_%04d.xhtml`；
  `Locator`/`reading_progress` 零变更（D3）。
- [x] **不跨越限界上下文**：改动全部在 `app/lib/pages`（interface）；`services`（application）与
  `core`（domain/infrastructure）零改动；无新表/新上下文（docs/04 §1）。
- [x] **听读同进度不变式保持**：`reading_progress` 仍是唯一事实源；`_openListen` 传可见章
  `href/_chapterProgress`；`_reloadProgress` 跨章恢复；`listen_page.dart` 零改动（US-8）。
- [x] **ddd-rules 合规**：新增 `pages/*.dart` 属 interface（`ddd-rules.toml:12`），只 import Flutter SDK +
  `../services/library_backend.dart`（DTO）；**不** import `package:reader_app/src/rust/`、`src/rust/`；
  `core/**` 零改动。
- [x] **REQ-001/004/005/006/007 复用不重做**：分页渲染/进度（001）、沉浸态/顶底栏/热区（004）、听书跨章
  与听读同进度（005/006）、中部点击手动判定与真实集成范式（007）全部复用；本 REQ 只把"手动下一章"变
  "自动接续"，不改其修复语义。
- [x] **无新增依赖**：仅 Flutter SDK 既有 API。
- [x] **既有测试兼容性（逐项处置，详见 02-plan 冲突清单）**：
  - `reader_page_test.dart` 18 个用例**断言零改动**：`_goChapter`/`_onChapterSelect`/`_onProgressSeek`/
    `_reloadProgress` 走 `flush` 立即落盘（保持 `backend.saved` 即时断言）；`SelectionArea` 仍唯一；
    `find.text(_ch1)/find.text(_ch2)` 仍 findsOneWidget（sliver 每章一个 item，不重复）。
  - `reader_interaction_test.dart:139-140` 的 `find.byType(SingleChildScrollView)` 必须改为
    `find.byType(CustomScrollView)`（唯一硬调整）。
  - `screenshot_golden_test.dart`：单章视觉目标不变（`SliverPadding` 等价原 `padding`）；若像素有
    差异则显式更新 golden 并在 03-review 记录。
  - `no_synthetic_chrome_test.dart`：自动扫描新集成测试文件，无需改扫描逻辑。
- [x] **零布局自创**：顶栏/底栏/工具条/Aa 面板/设置页布局零改动；唯一行为性增量 = 章间距 32px（§5）。
- [x] **截图/产品预览前置**：REQ-008 `product-preview.manifest.json` 缺失（`ui-screenshots.sh` 第 3 步
  会退出 2）→ 已列入 02-plan T-008 创建，并给 `screenshots_test.dart` 增一张"连续滚动到第二章"真实截图。

---

## 8. 设计取舍与风险登记

1. **sliver 懒构建 vs 远跳定位**（D1/D4）：懒构建换来 US-11 有界与 US-6 去重；远跳用
   `ensureVisible` + 估算 + 有界步进补偿，降级线为 `TextPainter` 精确估算。
2. **顶部锚点 vs 占比最大**（D2）：顶部锚点稳定、短末章靠触底锁正确；降级线为占比最大，断言不变。
3. **章内 progression 几何来源**（D3）：`getOffsetToReveal` 与 `ensureVisible` 同源；降级为
   `localToGlobal` 等价算法。
4. **最后一次滚动落盘**（D6）：尾沿防抖修复；widget 用 `pump(300ms)` 断言，集成用真实延时 ≥350ms。
5. **失败路径人工注入**（D5）：`ChapterContentProvider` 是唯一测试缝；生产 provider 永不失败，
   零行为变化。
6. **短末章判定**（D2）：触底锁 `atEnd` + 程序化锁；US-2/US-7 均覆盖。
7. **首帧定位闪烁**（D4）：post-frame 定位，US-4 只断言最终位置；若产品认为闪烁明显，降级 `TextPainter`。
8. **golden/截图**（D8）：单章目标不变；如有差异显式更新并记录。
