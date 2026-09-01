<!-- wf-meta: req=REQ-004 | phase=architecture | agent=architect | date=2025-09-01 | gate=passed -->
# REQ-004 · 模块/接口设计（阅读器页交互重构：沉浸态 + 工具 Chrome + 选中统一）

> 原型权威规范：`docs/wireframes/reader-ui-v2/README.md` + `01-immersive.svg`（沉浸态/热区）+
> `02-menus.svg`（呼出态顶/底栏） + `03-settings.svg`（Aa 面板） + `04-selection.svg`（选中工具条）。
> 本设计所有 widget 布局/交互均以上述图为唯一依据；deviation 目标 = 0（docs/07 §4.3）。

## 1. 模块与职责变化

| 模块 | 变化 | 层 | 说明 |
|---|---|---|---|
| `app/lib/pages/reader_page.dart` | **重构**：删除常驻 AppBar 与右上角三按钮（模式切换/字号/目录）、底部两按钮行、内嵌行式选中工具条；改为**沉浸态容器**（5 层 Stack + 手势层 + 状态机 + 浮层编排） | interface | UI 态全部局部 setState（ADR 决策点4）；只经 services/engines，不 import 桥接生成物 |
| `app/lib/engines/paged_web_view.dart` | **增强**（向后兼容）：新增 `pageCount()`、`onSelectionRect` 可选回调、`fontFamily/lineHeight` 可选样式参数；JS `selectionchange` 回传增强（文本+矩形） | interface | `nextPage/prevPage/gotoPage/relayout/fontSize/theme/onProgress/onSelectedText` 既有行为零改动（ADR 决策点1/3） |
| `app/lib/engines/progress_mapper.dart` | **新增**：进度换算纯函数（分页页↔progression、滚动 offset↔progression、百分比文本） | interface | 纯 Dart、无 Flutter 依赖、可单测（ADR 决策点3） |
| `app/lib/widgets/reader_chrome.dart` | **新增**：`ReaderChromeOverlay` + `ReaderTopBar` + `ReaderBottomBar`（02-menus.svg 顶/底栏浮层） | interface（widgets/**，见 §9 复核） | 顶栏：←返回/书名·章节名/⋯更多（四占位菜单）；底栏：上一章/☰目录/进度条/🔖书签/Aa/下一章（顺序与原型一致） |
| `app/lib/widgets/progress_slider.dart` | **新增**：`ProgressSlider`（可拖 Slider + 百分比/位置文本 + 拖动预览） | interface | 02-menus.svg 进度条区；拖动 onChange 实时预览、onChangeEnd 松手跳转（换算在 ReaderPage 经 progress_mapper） |
| `app/lib/widgets/settings_sheet.dart` | **新增**：`SettingsSheet`（Aa 面板，5 行：字号/字体/主题/行距/翻页模式）+ `ReaderStyle` 值对象 + 主题/字体/行距枚举 | interface | 03-settings.svg 逐行实现；面板外点击/✕ 关闭；`ReaderStyle` 供 ArticleBody 与面板共用 |
| `app/lib/widgets/directory_drawer.dart` | **新增**：`DirectoryDrawer`（侧拉目录抽屉：章节列表 + 当前章高亮 + 遮罩/关闭） | interface | README §3.3 + 02-menus.svg"☰ 目录"；按 `view.chapters` 扁平列表，不折叠 |
| `app/lib/widgets/selection_toolbar.dart` | **新增**：`SelectionToolbar`（浮动工具条：划重点/笔记/翻译/查词/复制 + 笔记 4 色圆点） | interface | 04-selection.svg；两模式**同一组件实例约定**（ADR 决策点1）；翻译/查词在 `translateBackend==null` 时隐藏 |
| `app/lib/widgets/translation_popup.dart` | **零改动复用**：`TranslationResultCard`/`DictResultCard`/`OverlayError` | interface | REQ-003 产物，本 REQ 只复用不修改（或仅微调定位包装） |
| `app/lib/widgets/reader/article_body.dart` | **新增**：`ArticleBody`（渲染引擎容器：滚动模式 `SingleChildScrollView+SelectionArea` / 分页模式 `PagedWebView` FutureBuilder + fake 注入点） | interface | 渲染引擎可不同、交互统一；暴露统一 `onProgress`/`onSelectedText`/`onSelectionRect` 回调 |
| `app/lib/services/library_backend.dart` | **零改动** | application | `openBook/chapterHtml/resource/saveProgress/loadProgress` 全部复用 |
| `app/lib/services/translate_backend.dart` | **零改动** | application | REQ-003 复用 |
| `app/test/reader_page_test.dart` | **重写** | — | 断言 AppBar/底部两按钮/`auto_stories` 图标的结构用例全部替换为沉浸态断言（见 §10） |
| `app/test/translate_reader_test.dart` | **更新** | — | 行式工具条断言（翻译/查词/取消 ActionChip）→ 浮动工具条 5 入口断言 |
| `app/test/fake_backend.dart` | **微改**（可选） | — | 如需更充分滚动进度测试可加长文本；既有用例零改动 |
| `core/**` | **零改动** | — | 进度=章内 progression，纯 UI 映射（ADR 决策点3） |

## 2. 接口签名（Dart）

### 2.1 `ReaderPage`（重构后，构造参数向后兼容）
```dart
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.bookId,
    required this.bookTitle,
    required this.backend,
    this.translateBackend,      // REQ-003：null → 隐藏翻译/查词（既有）
    this.pagedViewBuilder,      // 测试注入 fake（既有 typedef 不变）
  });
  // 状态字段（局部 setState，ADR 决策点4）：
  //   _uiVisible (bool, 默认 false=沉浸)  _settingsOpen  _drawerOpen
  //   _bookmarked  _dragPreview (double?)  _progression (double 0..1)
  //   _pendingProgression (double?, 互切恢复)  _style (ReaderStyle)
}
```

### 2.2 `ReaderChromeOverlay` / `ReaderTopBar` / `ReaderBottomBar`（widgets/reader_chrome.dart）
```dart
/// 顶栏+底栏浮层容器（02-menus.svg 呼出态；visible=false 时 IgnorePointer + 透明）
class ReaderChromeOverlay extends StatelessWidget {
  const ReaderChromeOverlay({
    super.key,
    required this.visible,
    required this.bookTitle,
    required this.chapterTitle,
    required this.chapterIndex,
    required this.chapterCount,
    required this.progress,           // 0..1 章内进度（Slider 值 + 百分比）
    required this.percentText,        // "42%"（含位置计数文本可并入）
    required this.bookmarked,
    required this.onBack,             // ← 返回（Navigator.pop）
    required this.onMoreSelected,     // ValueChanged<String> ⋯ 菜单项（阅读统计/听书/笔记/导出）
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onToggleDirectory,
    required this.onToggleBookmark,
    required this.onOpenSettings,     // → 打开 Aa 面板
    required this.onProgressPreview,  // ValueChanged<double>? 拖动中实时预览
    required this.onProgressSeek,     // ValueChanged<double> 松手跳转
  });
}
// ReaderTopBar：← 返回（左）/ 书名(大字)·章节名(小字)（中）/ ⋯ 更多（右，PopupMenuButton，
//   恰好 4 项顺序：阅读统计/听书/笔记/导出；点击占位项上抛 onMoreSelected，页面 Toast"即将上线"）
// ReaderBottomBar：自左至右 上一章 ▶◀ / ☰ 目录 / ProgressSlider+百分比 / 🔖 书签 / Aa 按钮 / 下一章
//   边界：第一章禁用上一章、末章禁用下一章（US-7）
```

### 2.3 `ProgressSlider`（widgets/progress_slider.dart）
```dart
class ProgressSlider extends StatelessWidget {
  const ProgressSlider({
    super.key,
    required this.value,              // 0..1
    required this.percentText,        // 如 "42% · 第 3/8 页"
    required this.onChanged,          // 拖动中（预览；不跳转）
    required this.onChangeEnd,        // 松手（跳转 + saveProgress）
  });
}
```

### 2.4 `SettingsSheet` + `ReaderStyle`（widgets/settings_sheet.dart）
```dart
enum ReaderTheme { light, dark, sepia }        // 浅色/深色/护眼（03-settings.svg 色样）
enum ReaderFont { system, serif, sans }        // 系统默认/衬线/无衬线
enum ReaderLineHeight { compact, normal, loose } // 紧凑(1.4)/标准(1.8)/宽松(2.2)

class ReaderStyle {
  const ReaderStyle({this.fontSize = 18, this.font = ReaderFont.system,
    this.theme = ReaderTheme.light,
    this.lineHeight = ReaderLineHeight.normal, this.pagedMode = false});
  final int fontSize;                 // [14,16,18,20,24]（既有字号范围沿用）
  final ReaderFont font;
  final ReaderTheme theme;
  final ReaderLineHeight lineHeight;
  final bool pagedMode;               // 默认滚动模式（ADR 关联裁定3）
  ReaderStyle copyWith({...});
  static ReaderStyle get defaults => const ReaderStyle();
}

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key,
    required this.style,              // 当前值
    required this.onStyleChanged,     // ValueChanged<ReaderStyle> 任一控件变更即时生效
    required this.onClose,            // ✕ / 面板外点击
  });
  // 面板自带全屏半透明遮罩（正文淡化，03-settings.svg）；面板覆盖下半屏；
  // 恰好 5 行选项 + 标题"显示设置" + ✕（US-11 逐项断言）
}
```

### 2.5 `DirectoryDrawer`（widgets/directory_drawer.dart）
```dart
class DirectoryDrawer extends StatelessWidget {
  const DirectoryDrawer({super.key,
    required this.chapters,           // List<String> 章节标题（view.chapters 顺序）
    required this.currentIndex,
    required this.onSelect,           // ValueChanged<int>（j≠当前 → 跳转+saveProgress；当前 → 仅关闭）
    required this.onClose,            // 遮罩点击 / 关闭按钮
  });
  // 右侧 scrim + 抽屉；当前章条目高亮（主题色 + 选中标记，US-8 可断言）
}
```

### 2.6 `SelectionToolbar`（widgets/selection_toolbar.dart）
```dart
class SelectionToolbar extends StatelessWidget {
  const SelectionToolbar({super.key,
    required this.hasTranslateBackend,  // false → 隐藏 翻译/查词（REQ-003 零注入行为不变）
    required this.onHighlight,          // 划重点（占位：Toast"即将上线"，不崩溃）
    required this.onNote,               // 笔记（占位，带 4 色圆点装饰，04-selection.svg）
    required this.onTranslate,
    required this.onLookup,
    required this.onCopy,               // 写入系统剪贴板（Clipboard.setData）
    required this.onDismiss,            // 工具条外点击取消选中
  });
}
// 两模式渲染同一组件（相同 runtimeType / 相同 ValueKey('selection-toolbar')，US-15 断言点）
```

### 2.7 `ArticleBody`（widgets/reader/article_body.dart）
```dart
class ArticleBody extends StatefulWidget {
  const ArticleBody({super.key,
    required this.bookId,
    required this.href,
    required this.chapter,            // ChapterData（滚动模式 Text 数据源）
    required this.backend,
    required this.style,              // ReaderStyle（字号/字体/主题/行距/模式）
    required this.scrollController,   // 滚动模式 ScrollController（ReaderPage 持有，进度条 jumpTo 用）
    required this.onProgress,         // ValueChanged<double> 章内 0..1（分页 JS / 滚动 offset 归一）
    required this.onSelectedText,     // ValueChanged<String> 统一选中入口（两引擎收敛）
    required this.onSelectionRect,    // ValueChanged<Rect?> 分页 JS 矩形（滚动 null）
    this.pagedViewBuilder,            // 既有测试注入 typedef
    this.pagedKey,                    // GlobalKey<PagedWebViewState>（翻页/跳页/样式重载）
  });
}
// 职责：仅"渲染 + 上报"，无 UI 态；滚动模式内部：SingleChildScrollView + SelectionArea +
//   ScrollController 监听 → onProgress(offset/maxScrollExtent)（节流）；分页模式内部：
//   FutureBuilder(chapterHtml) → builder → PagedWebView(fontSize/theme/fontFamily/lineHeight/
//   onProgress/onSelectedText/onSelectionRect)
```

### 2.8 `PagedWebView` 增强（engines/paged_web_view.dart，全部向后兼容）
```dart
// 新增（本 REQ）
Future<int> pageCount();                      // JS readerPager.pageCount()（relayout 后准确）
final ValueChanged<Rect?>? onSelectionRect;   // 可选；选区视口矩形（尽力定位工具条）
final String? fontFamily;                     // 可选，默认 null=系统默认
final double? lineHeight;                     // 可选，默认 null=现状
// JS applyStyle(fontSize, theme, fontFamily, lineHeight) 扩展（缺省参数=现状，既有注入零改动）
// JS selectionchange 增强：callHandler('selectedText', text, r.x, r.y, r.w, r.h)
//   Dart handler 向后兼容解析：args.length>=5 → onSelectedText(text) + onSelectionRect(Rect)；
//   args.length==1 → 仅 onSelectedText(text)（旧 JS/旧测试路径）

// 既有（复用零改动）
Future<bool> nextPage(); Future<bool> prevPage();   // 越界返回 false（US-3 边界）
Future<bool> gotoPage(int index);
Future<void> relayout();
int fontSize; String theme; ValueChanged<double>? onProgress; ValueChanged<String>? onSelectedText;
```

### 2.9 `progress_mapper.dart`（engines/progress_mapper.dart，纯函数可单测）
```dart
/// 分页：拖动值 v∈[0,1] → 目标页（末页=1.0）
int progressionToPage(double v, int pageCount) =>
    (v * (pageCount - 1)).round().clamp(0, pageCount - 1);
/// 滚动：offset ↔ progression
double offsetToProgression(double offset, double max) =>
    max <= 0 ? 0.0 : (offset / max).clamp(0.0, 1.0);
double progressionToOffset(double v, double max) => (v * max).clamp(0.0, max);
/// 百分比文本："42%"（round(v*100)）
String percentText(double v) => '${(v * 100).round()}%';
/// 位置计数文本（分页："第 x/y 页"；滚动：滚动模式用比例）
String pagePositionText(int page, int pageCount) => '第 ${page + 1}/$pageCount 页';
```

## 3. 数据模型变化

- **core/表/迁移零改动**（ADR 决策点3）：进度保存仍为 `saveProgress(bookId, href, progression)`
  （章内 0..1，REQ-001 通路）；`ProgressData{href, progression}` 不变。
- **UI 层新增值对象**（非持久化）：
  - `ReaderStyle`（settings_sheet.dart）：字号/字体/主题/行距/翻页模式（会话级内存；
    持久化归 READ 系列后续 REQ，本期不落库）；
  - `_bookmarked`（reader_page 私有 bool）：当前页书签图标态（内存；NOTE-06 P1 落库）；
  - `_progression`/`_pendingProgression`/`_dragPreview`（reader_page 私有）。
- 无 DDL、无新桥接函数、无 FRB 再生成。

## 4. 关键时序

### 4.1 打开书 → 沉浸态（US-1）
```
LibraryPage 点书 → ReaderPage(bookId, backend, translateBackend)
 → initState._load()：openBook → loadProgress → 定位章节（_chapterIndexForHref 既有）
 → build：_error/_view null → 无 AppBar 骨架（居中内容 + SafeArea 返回）
 → _view 就绪 → 5 层 Stack：ArticleBody 渲染正文；_uiVisible=false → chrome 不可见
 → 断言：find.byType(AppBar) == 0；正文占满（第一章文本可见，顶部即正文起始）
```

### 4.2 中部点击呼出/隐藏（US-2）
```
手势层 onTapUp(p)：
  若 _settingsOpen||_drawerOpen → 遮罩消费（关闭面板/抽屉）
  否则按命中区：
    分页且 x<0.15w → prevPage()；分页且 x>0.85w → nextPage()
    滚动模式边缘 → 忽略
    0.33w≤x≤0.66w 且 0.1h≤y≤0.9h → _toggleChrome()（AnimatedOpacity 300ms 淡入/淡出；
       呼出→沉浸时连带关闭 _settingsOpen/_drawerOpen，ADR 关联裁定2）
    其余 → 忽略
```

### 4.3 边缘翻页（分页，US-3）与滑动（滚动，US-4）
```
分页：手势层 → PagedWebView.nextPage()/prevPage()（JS 平移视口）→ JS report() →
     onProgress(progression) → _progression 更新 → 节流 saveProgress(href, prog)
     （第 1 页 prev / 末页 next 由 JS 返回 false，不越界）
滚动：滑动由 SingleChildScrollView 原生处理（手势层 tap-only 不参与）→ controller 监听 →
     onProgress(offset/max) → 节流 saveProgress
```

### 4.4 进度条拖动（US-9）
```
呼出态底栏 ProgressSlider：
  onChanged(v) → _dragPreview=v → percentText 实时更新（预览，不跳转）
  onChangeEnd(v) → 分页：target=progressionToPage(v, pageCount) → pagedKey.gotoPage(target)
                   → 滚动：scrollController.jumpTo(progressionToOffset(v, max))
                   → saveProgress(href, progression)（复用 500ms 节流）
  Slider 在 chrome 层之上 → 拖动期间手势层不可达（与翻页互斥，US-9 风险1）
```

### 4.5 模式切换（Aa 面板，US-12/16 互切不跳变）
```
Aa 面板"翻页"单选切模式 → _style.pagedMode 翻转 → ArticleBody 重建为另一引擎
 → 目标引擎就绪前记录 _pendingProgression = _progression
 → 分页：首次 onProgress（页数就绪）后 gotoPage(progressionToPage(prog, n))
 → 滚动：maxScrollExtent>0 后 jumpTo(progressionToOffset(prog, max))
 → 清除 pending；保存不跳变（US-16 断言）
```

### 4.6 长按选中 → 浮动工具条（US-14/15，两模式统一）
```
滚动：SelectionArea.onSelectionChanged → plainText → _onSelectedText(text)（无几何）
分页：JS selectionchange → callHandler('selectedText', text, x,y,w,h) →
      _onSelectedText(text) + _selectionRect（视口矩形）
 → _selectedText 非空 → 顶层渲染 SelectionToolbar（key='selection-toolbar'，两模式同类型）
 → 定位：分页 = rect 上方（clamp 视口）；滚动 = 视口顶部基准位（ADR 决策点1 降级线）
 → 翻译/查词 → _doTranslate/_doLookup（REQ-003 浮层复用）；复制 → Clipboard.setData(text)
 → 划重点/笔记 → Toast"即将上线"（不崩溃）；工具条外点击 → _cancelSelection
```

### 4.7 目录抽屉 / 书签（US-8/US-10）
```
☰ → _drawerOpen=true → DirectoryDrawer（当前章高亮）→ onSelect(j)：
     j≠当前 → 关抽屉 + _chapterIndex=j + saveProgress(0.0)
     j==当前 → 仅关抽屉；遮罩/关闭 → 仅关抽屉
🔖 → _bookmarked=!_bookmarked（图标态切换，幂等；切章/翻页后重置）
```

## 5. ReaderPage 状态机（沉浸 ⇄ 呼出）

```
                         中部点击 (守卫: 无面板/抽屉)
        ┌──────────────────────────────────────────────┐
        ▼                                              │
  ┌───────────┐   中部点击    ┌───────────┐
  │ immersive │ ───────────▶ │ revealed  │
  │ (默认)     │ ◀─────────── │ (呼出)     │
  └───────────┘              └───────────┘
  chrome 不可见               顶栏+底栏淡入可见
  边缘点击→翻页(分页)          边缘点击→翻页(分页)
  滑动/长按→引擎处理           中部点击→回 immersive
                              Aa/抽屉/进度条/书签/章切换可用
```
- **守卫（guard）**：`_settingsOpen || _drawerOpen` 时不响应中部切换（遮罩消费）；边缘 15% 永不触发
  切换（命中区分支互斥）；滚动模式边缘无动作。
- **副作用（side effects）**：immersive → revealed：无；revealed → immersive：关闭 Aa 面板与目录
  抽屉（ADR 关联裁定2）；选中工具条/翻译浮层不受 chrome 可见性影响。
- **实现**：`_uiVisible` + `AnimatedOpacity(duration: 300ms)` + `IgnorePointer(!_uiVisible)`
  （隐藏时浮层不拦截点击）；状态迁移集中在 `_toggleChrome()` 一个方法（可测）。

## 6. 手势命中区实现（ADR 决策点2 落地）

```
Stack（reader_page.build 返回，自下而上）:
  0. ArticleBody                        —— 引擎原生手势（滑动/长按/缩放）
  1. ReaderGestureLayer (Positioned.fill) —— GestureDetector(behavior: translucent,
        onTapUp: _onTapUp)；只注册 tap，不注册 drag/scale
  2. ReaderChromeOverlay (visible? 顶栏+底栏) —— 控件自身消费其区域点击
  3. SettingsSheet / DirectoryDrawer      —— 全屏遮罩 + 面板/抽屉（打开时消费全部点击）
  4. SelectionToolbar + 翻译/查词浮层     —— 最高层（选中操作，独立于 chrome）
```
命中区常量（`widgets/reader/gesture_zones.dart` 或 reader_page 顶层，测试共用）：
```dart
const double kEdgeZone = 0.15;            // 左/右 15%
const double kCenterLeft = 1 / 3;         // 中部 1/3 左边界
const double kCenterRight = 2 / 3;
const double kCenterTop = 0.1, kCenterBottom = 0.9;  // 正文中部垂直区域（避开系统区）
```
`_onTapUp(TapUpDetails d)`：
```dart
final w = context.size!.width, h = context.size!.height;
final x = d.localPosition.dx, y = d.localPosition.dy;
if (_settingsOpen || _drawerOpen) { /* 遮罩已消费，理论上不到达 */ return; }
if (_style.pagedMode) {
  if (x < w * kEdgeZone) { _prevPage(); return; }        // 分页左边缘
  if (x > w * (1 - kEdgeZone)) { _nextPage(); return; }  // 分页右边缘
} else if (x < w * kEdgeZone || x > w * (1 - kEdgeZone)) {
  return;                                                // 滚动模式边缘不拦截（US-4）
}
if (x >= w * kCenterLeft && x <= w * kCenterRight &&
    y >= h * kCenterTop && y <= h * kCenterBottom) {
  _toggleChrome();                                       // 呼出/隐藏（US-2）
}
```
优先级与互斥（测试断言点）：
| 竞争对 | 裁决 | 测试 |
|---|---|---|
| 边缘点击 vs 中部呼出 | 边缘分支先判，互斥 | US-2 末句：边缘点击不切换可见性 |
| 滑动 vs tap | 手势层无 drag，竞技场 tap 失败 | US-4：滚动偏移变化正常 |
| 长按选中 vs tap | 长按超时取消 tap | US-14：选中仍出工具条 |
| 进度条拖动 vs 翻页 | Slider 在 chrome 层之上 | US-9 风险1：拖动不触发翻页 |
| 面板/抽屉 vs 其他 | 遮罩消费全部点击 | US-11/US-8：面板外点击关闭 |

## 7. 进度换算（ADR 决策点3 落地）

| 模式 | 显示值（Slider/百分比） | 拖动松手目标 | 保存 |
|---|---|---|---|
| 分页 | `progression = current/columns`（JS `report()` 既有语义，不动） | `gotoPage(progressionToPage(v, pageCount))` | `saveProgress(href, progression)` |
| 滚动 | `progression = offset/maxScrollExtent`（controller 监听，节流） | `jumpTo(progressionToOffset(v, max))` | 同上 |
- 百分比文本：`percentText = round(progression×100)%`；位置计数分页 = "第 x/y 页"（02-menus.svg
  "42% · 位置 …"布局语义，百分比为必断言语义，计数格式可断言）。
- **互切不跳变**：`_pendingProgression` 机制（时序 §4.5）；分页↔滚动互切回归用例（US-16）断言
  切换后重新保存的 `progression` 与切换前一致（fake 数据短时允许 max==0 分支返回 0 不抛错）。
- 与既有模型兼容性：保存语义（href+progression 章内）与 REQ-001 完全一致；docs/04 §3
  `Locator.progression`（章内）一致；听读同进度不变式（docs/04 §9.1：`reading_progress` 唯一事实源）
  不破坏——进度条只是该模型的 UI 换算，不新增事实源。

## 8. 与 services/engines 的接口

| 接口 | 变化 | 说明 |
|---|---|---|
| `LibraryBackend` | **零改动** | openBook/chapterHtml/resource/saveProgress/loadProgress 全部复用（REQ-001） |
| `TranslateBackend` | **零改动** | translate/lookup 复用（REQ-003）；null 注入 → 工具条隐藏翻译/查词 |
| `PagedWebView` | **增强（向后兼容）** | 新增 `pageCount()`、`onSelectionRect`、`fontFamily/lineHeight`；`next/prev/gotoPage/relayout` 既有复用；JS 选区回传增强（文本+矩形），handler 解析向后兼容（1 参=旧、≥5 参=新） |
| `ReflowEngine`（reflow_engine.dart） | **零改动** | `selectText` TODO 本期不兜底（分页坐标由 JS 矩形提供；滚动定位用降级线）——记录 NOTEs 升级路径（ADR 决策点1） |
| `translation_popup.dart` | **零改动复用** | TranslationResultCard/DictResultCard/OverlayError 浮层复用；定位由 ReaderPage 顶层 Stack 编排 |
| `progress_mapper.dart` | **新增** | 纯函数（§2.9），ReaderPage 与测试共用 |

## 9. ddd-rules 层归属复核（与 docs/07 §6 + workflow/rules/ddd-rules.toml 比对）

- `ddd-rules.toml` interface 层 paths = `["core/src/api.rs", "app/lib/pages", "app/lib/engines"]`
  —— **`app/lib/widgets/**` 不在任何已声明层内**（"未声明层不检查"）。01-req §3 称
  "pages/** 与 widgets/** 均已声明属 interface 层"与规则表不符（**需求措辞偏差，见 02-plan 冲突检查**）。
- 处置（本 REQ）：
  1. **不修改冻结的规则表**（docs/07 §6"评审后冻结，勿单方面修改"）；
  2. 新增 5 个 widget 文件 + article_body.dart 在**架构纪律层面**与 pages 同级约束：只 import
     Flutter / services（DTO）/ engines（组件），**禁止 `package:reader_app/src/rust/` 与
     `src/rust/`**（widgets 不直接触碰桥接生成物，与 forbid_imports 同义）；03-review 阶段 developer
     人工核对 import 面（widgets 漏检风险已登记）；
  3. 建议（不执行，需规则评审链）：后续把 `app/lib/widgets` 加入 interface paths——作为已知取舍记录。
- `app/lib/pages/reader_page.dart` 与 `app/lib/engines/*` 改造后仍满足既有规则（不 import
  桥接生成物，经 services）。
- 依赖方向合规：widgets → services（application）→ FFI；无反向依赖。

## 10. 既有 widget 测试的改造点

| 测试文件 | 现状断言（失效点） | 改造 |
|---|---|---|
| `reader_page_test.dart` | ① `find.byIcon(Icons.skip_next)` 底部翻章按钮；② `find.byIcon(Icons.auto_stories)` 右上模式切换按钮；③ `find.text('第一章')` 顶部章节标题（改为正文首行）；④ AppBar 结构 | **重写**：沉浸态断言（`find.byType(AppBar)==0`）；中部点击呼出 → 底栏 ☰/上一章/下一章等控件可见；再点隐藏；边缘 15% 点击翻页（分页模式，fake 构建器回调断言）/滚动模式不翻页；进度保存/恢复断言保留（`backend.saved`） |
| `translate_reader_test.dart` | 行式工具条断言 `find.text('翻译'/'查词'/'取消')`（ActionChip 行） | **更新**：浮动 `SelectionToolbar` 5 入口断言（划重点/笔记/翻译/查词/复制 + 顺序）；SelectionArea 注入方式不变；分页 fake builder 捕获 `onSelectedText` 不变（新捕获 `onSelectionRect` 可选）；"translateBackend null 无入口"断言改为"翻译/查词隐藏、划重点/笔记/复制仍在" |
| `library_page_test.dart` | 打开书后断言 ReaderPage 文本（无结构断言，基本兼容） | 回归确认：沉浸态下 `find.text('第一章')`/正文文本仍成立 |
| `fake_backend.dart` | — | 可选：加长章节文本使滚动 `maxScrollExtent>0`（互切测试用）；`saved` 断言复用 |
| `widget_test.dart`/`settings_page_test.dart`/`rust_*_test.dart` | — | **零改动**（回归面确认，T-009） |
| **新增用例（US-17 十项）** | — | ① 沉浸态（无 AppBar/无 chrome）；② 中部呼出/隐藏；③ 分页边缘 15% 翻页 + 滚动边缘不翻页；④ ⋯更多四占位项；⑤ 底栏六控件顺序；⑥ 目录抽屉打开/高亮/跳转/遮罩关闭；⑦ 进度条拖动预览与松手跳转 + 百分比；⑧ Aa 面板 5 行 + 字号/主题/模式切换生效；⑨ 选中工具条 5 入口 + 查词卡片/译文浮层；⑩ 右上角三按钮 findsNothing |

## 11. 与既有约定的兼容性核对

- [x] **不破坏 Locator/进度模型**：进度条=章内 progression 换算，保存语义（href+progression）不变；
      core/api.rs/表零改动（ADR 决策点3）。
- [x] **听读同进度不变式保持**（docs/04 §9.1）：`reading_progress` 仍是唯一事实源，进度条/书签
      不新增事实源（书签为内存图标态，NOTE-06 落库时再设计）。
- [x] **不跨越限界上下文**（docs/04 §1）：全部改动在 Reading/UI 界面层；不触碰 library/notes/tts
      领域；翻译/查词经既有 Translation 上下文（REQ-003 复用）。
- [x] **ddd-rules**：规则表零改动；pages/engines 合规；widgets 按架构纪律约束（§9 处置 2）。
- [x] **REQ-001/003 能力复用不重做**：PagedWebView 增强全部向后兼容；翻译/查词/选区回调既有路径
      保留；`pagedViewBuilder` typedef 不变（fake 零改动）。
- [x] **原型一致性**：01/02/03/04.svg + README 逐屏映射（§1 表格 + 各 widget 注释）；已拍板决策
      纳入（滚动无边缘翻页、⋯更多四占位、书架不动）；右上角三按钮移除后入口唯一性（US-13）由
      设计保证（模式切换/字号仅 Aa 面板、目录仅底栏 ☰）。
- [x] **FRB/桥接**：无新桥接、无再生成（core 零改动）。

## 12. 已知取舍（非冲突，均含处置）
1. **滚动模式工具条固定基准位**（04-selection.svg"选中文本上方"仅分页精确）→ ADR 决策点1 降级线
   （01-req §5 风险2 授权）；NOTE 系列引入 TextSelection 锚定时补滚动几何。
2. **widgets/** 未列入 ddd-rules.toml（01-req 措辞偏差）→ §9 处置 2/3（架构纪律 + 建议后续评审）。
3. **进度条为章内语义**（README §3.3"42%"可读作章内）→ 全书进度条（README"位置 1304/3120"的
   全书语义）归 READ-07 P1（ADR 决策点3）。
4. **Aa 设置会话级不持久化**（重开书恢复默认）→ 显示设置持久化归 READ 系列后续 REQ（ADR 关联裁定3
   配套说明）；本期 US-12 只要求即时生效。
5. **书签内存态**（重开书书签清空）→ NOTE-06 P1 落库（US-10 只要求图标态 + 幂等）。
