<!-- wf-meta: req=REQ-005-fixes | phase=architecture | agent=architect | date=2026-09-08 | gate=passed -->
# REQ-005-fixes · 模块/接口设计（听书链路贯通 + 分页禁原生菜单）

> 原型权威规范：`docs/wireframes/09-listen-player.svg`（听书跟读/控制条）、
> `docs/wireframes/10-listen-settings.svg`（听书设置）、`docs/wireframes/reader-ui-v2/04-selection.svg`
> （选中浮动工具条，本 REQ 仅回归守护）+ `docs/wireframes/README.md`。所有布局/交互以上述图为唯一依据；
> 本 REQ **不新增/不修改** 04-selection 的布局（REQ-004 产物），deviation 目标 = 0。

## 1. 模块与职责变化

| 模块 | 变化 | 层 | 说明（对应 ADR） |
|---|---|---|---|
| `core/src/tts/mod.rs` | **实现**：`segment`/`locator_for_sentence`/`sentence_index_at` 改**文本入参**并实现切句与映射；删 `not_implemented_yet` | domain | 仅 `use crate::types`；决策点1(a) |
| `core/src/api.rs` | **新增**：`LocatorView`/`SentenceChunkView`/`ListenSettingsView` + `chapter_text` helper + 5 个 async 桥接（`tts_segment`/`tts_locator_for_sentence`/`tts_sentence_index_at`/`tts_listen_settings_get`/`tts_listen_settings_set`） | interface | 决策点1(b)/3/6；interface 可用 `crate::library` |
| `core/src/store/mod.rs` | **新增**：`get_setting`/`set_setting`（公开） | infrastructure | 决策点6；复用既有 `settings` 表 |
| `core/src/library/mod.rs` | **新增**：`get_setting`/`set_setting` 转发（薄） | application | 决策点6 |
| `app/lib/engines/tts_engine.dart` | **修改**：`SentenceChunk{index,text,charStart,charEnd,locator}` + 新增 `SentenceLocator`；`TtsEngine`/`TtsEvent` 契约不变 | interface | 决策点1(b)/3 |
| `app/lib/engines/system_tts_engine.dart` | **新增**：`SystemTtsEngine implements TtsEngine`（封装 `flutter_tts`） | interface | 决策点3；只 import flutter_tts + tts_engine |
| `app/lib/engines/paged_web_view.dart` | **修改**：`initialSettings` 提取为 `buildPagedWebViewSettings({disableContextMenu=true})` 工厂并设 `disableContextMenu: true`；`selectionchange` 回传零改动 | interface | 决策点2 |
| `app/lib/services/tts_backend.dart` | **新增**：`TtsBackend` 抽象 + `ListenSettingsData` | application | 决策点3/6 |
| `app/lib/services/rust_tts_backend.dart` | **新增**：`RustTtsBackend`（import 生成物转 DTO） | application | 决策点3/6；先例 `rust_library_backend.dart` |
| `app/lib/pages/listen_page.dart` | **重写**：`StatelessWidget` → `StatefulWidget`（状态机 + 引擎编排 + 控制条 + 跟读高亮 + 设置入口/面板 + 句级进度条） | interface | 决策点3/4 |
| `app/lib/pages/reader_page.dart` | **修改**：`_openMore` 听书项跳转 `ListenPage`；返回 `_reloadProgress`；新增可选 `ttsBackend`/`ttsEngine`；复制修复（US-22） | interface | 决策点5 |
| `app/lib/widgets/listen_control_bar.dart` | **新增**：`ListenControlBar`（线框 09 控制条） | interface（widgets，见 §6 纪律） | 原型 09 |
| `app/lib/widgets/listen_settings_sheet.dart` | **新增**：`ListenSettingsSheet`（线框 10 面板） | interface（widgets 纪律） | 原型 10 |
| `app/lib/widgets/listen_follow_highlight.dart` | **新增**：`ListenFollowHighlight`（当前句高亮正文） | interface（widgets 纪律） | 原型 09；US-17 |
| `app/lib/pages/library_page.dart` | **零改动** | interface | ReaderPage 默认懒创建 tts 实现 |
| `app/lib/services/library_backend.dart` | **零改动** | application | `openBook/chapterHtml/saveProgress/loadProgress` 全复用 |
| `app/pubspec.yaml` | **修改**：启用 `flutter_tts: ^4`；`just_audio`/`audio_service` 保持注释 | — | 决策点3；US-9/US-12 |
| `core/src/types.rs` | **零改动**（`Locator`/`TextAnchor`/`Rect` 不动） | domain | 不破坏 Locator 模型 |
| `core/src/store/**` 表/迁移 | **零改动** | infrastructure | 零新表；`settings` 复用 |

## 2. 接口签名（Rust / Dart）

### 2.1 Rust domain（`core/src/tts/mod.rs`，仅 `use crate::types`）
```rust
pub struct SentenceChunk { pub text: String, pub char_range: (u32, u32), pub locator: Locator } // 结构不变
pub fn segment(text: &str, book_id: &BookId, href: &str) -> Result<Vec<SentenceChunk>, TtsError>;
pub fn locator_for_sentence(text: &str, book_id: &BookId, href: &str, idx: usize) -> Result<Locator, TtsError>;
pub fn sentence_index_at(text: &str, book_id: &BookId, href: &str, loc: &Locator) -> Result<usize, TtsError>;
```
- `char_range`/`TextAnchor.start/end` 计量单位 = **UTF-16 code unit 半开区间**（ADR 决策点1(b)）。
- `progression_i = char_start_i / utf16_len(text)`，clamp `[0,1]`，单调递增；`sentence_index_at` = 满足 `progression_i <= loc.progression` 的最大 i；`loc.progression==1.0 → N-1`，`==0.0 → 0`，NaN/<0/>1/href 不匹配/空文本 → `Err`。

### 2.2 Rust bridge（`core/src/api.rs`）
```rust
pub struct LocatorView {
    pub book_id: String,
    pub href: String,
    pub progression: f32,        // 章内 0..=1
    pub total_progression: f32,  // 全书（本期=章内近似，仅展示）
    pub snippet: Option<String>, // TextAnchor.snippet
}
pub struct SentenceChunkView {
    pub index: u32,              // 章内句序号（0 起）
    pub text: String,
    pub char_start: u32,         // UTF-16 code unit，[start,end)
    pub char_end: u32,
    pub locator: LocatorView,
}
pub struct ListenSettingsView { pub voice_id: String, pub speed: f32, pub auto_next: bool }

fn chapter_text(id: &str, href: &str) -> std::result::Result<String, String>; // 经 LibraryService::open_book 按 href 取 Chapter.text
pub async fn tts_segment(book_id: String, href: String) -> std::result::Result<Vec<SentenceChunkView>, String>;
pub async fn tts_locator_for_sentence(book_id: String, href: String, idx: u32) -> std::result::Result<LocatorView, String>;
pub async fn tts_sentence_index_at(book_id: String, href: String, locator: LocatorView) -> std::result::Result<u32, String>;
pub async fn tts_listen_settings_get() -> std::result::Result<ListenSettingsView, String>;
pub async fn tts_listen_settings_set(settings: ListenSettingsView) -> std::result::Result<(), String>;
```
- FFI 函数名与 `docs/03 §13.3` 一致；async（取文本有 IO）；`idx: u32`、`locator: LocatorView` 为桥接适配（docs 待同步）。
- `tts_sentence_index_at` 在 api 层把 `LocatorView` 重建为 domain `Locator`（`text` 由 `snippet` 还原、`cfi/page/rect=None`）后调 domain 函数。

### 2.3 Dart 引擎契约（`app/lib/engines/tts_engine.dart`）
```dart
class SentenceLocator {
  const SentenceLocator({required this.bookId, required this.href,
    required this.progression, required this.totalProgression, this.snippet});
  final String bookId; final String href;
  final double progression;       // 章内 0..1
  final double totalProgression;  // 全书（本期近似）
  final String? snippet;
}
class SentenceChunk {
  const SentenceChunk({required this.index, required this.text,
    required this.charStart, required this.charEnd, required this.locator});
  final int index;                // 章内句序号（TtsSentenceDone 依据）
  final String text;
  final int charStart;            // UTF-16 code unit，[start,end)
  final int charEnd;
  final SentenceLocator locator;
}
abstract class TtsEngine { // 契约不变（docs/03 §13.2）
  Future<void> configure({required String voiceId, required double speed});
  Future<void> speak(SentenceChunk chunk);
  Future<void> pause(); Future<void> resume(); Future<void> stop();
  Stream<TtsEvent> get events;
}
sealed class TtsEvent {}
class TtsSentenceDone extends TtsEvent { TtsSentenceDone(this.sentenceIndex); final int sentenceIndex; }
class TtsFailed extends TtsEvent { TtsFailed(this.message); final String message; }
```

### 2.4 Dart 服务（`app/lib/services/tts_backend.dart` + `rust_tts_backend.dart`）
```dart
class ListenSettingsData {
  const ListenSettingsData({required this.voiceId, required this.speed, required this.autoNext});
  final String voiceId; final double speed; final bool autoNext; // speed clamp [0.5,3.0]
  ListenSettingsData copyWith({String? voiceId, double? speed, bool? autoNext});
}
abstract class TtsBackend {
  Future<List<SentenceChunk>> segment(String bookId, String href);
  Future<SentenceLocator> locatorForSentence(String bookId, String href, int index);
  Future<int> sentenceIndexAt(String bookId, String href, SentenceLocator locator);
  Future<ListenSettingsData> loadListenSettings();
  Future<void> saveListenSettings(ListenSettingsData settings);
}
class RustTtsBackend implements TtsBackend { /* 生成物 -> SentenceChunk/SentenceLocator/ListenSettingsData */ }
```

### 2.5 Dart 引擎实现与 WebView 工厂
```dart
// app/lib/engines/system_tts_engine.dart
class SystemTtsEngine implements TtsEngine {
  SystemTtsEngine({FlutterTts? tts});
  // configure: setSpeechRate(speed) + setVoice(voiceId 解析为系统 voice)
  // speak(chunk): _last=chunk; flutterTts.speak(chunk.text); 完成回调 -> TtsSentenceDone(chunk.index)
  // pause/resume/stop 转发；异常 -> TtsFailed(message)
}
// app/lib/engines/paged_web_view.dart（顶层工厂，build() 与测试共用）
InAppWebViewSettings buildPagedWebViewSettings({bool disableContextMenu = true}) =>
    InAppWebViewSettings(useShouldInterceptRequest: true, transparentBackground: false,
        disableContextMenu: disableContextMenu);
// build(): initialSettings: buildPagedWebViewSettings()
```

### 2.6 Dart 页面/widget
```dart
// app/lib/pages/listen_page.dart
class ListenPage extends StatefulWidget {
  const ListenPage({super.key, required this.bookId, required this.bookTitle,
    required this.href, required this.progression, required this.backend,
    required this.ttsBackend, required this.ttsEngine});
}
// app/lib/pages/reader_page.dart（新增可选参数，向后兼容）
const ReaderPage({..., this.ttsBackend, this.ttsEngine});

// app/lib/widgets/listen_control_bar.dart（线框 09）
class ListenControlBar extends StatelessWidget {
  const ListenControlBar({super.key, required this.chapterTitle,
    required this.playing, required this.speedText, required this.progress,
    required this.onPrevSentence, required this.onTogglePlay, required this.onNextSentence,
    required this.onSeek, required this.onTimer, required this.onVoice});
  // 章节名 / ⏮ / ⏸▶ / ⏭ / Slider / "1.0x" / 定时(禁用) / 音色(禁用)
}
// app/lib/widgets/listen_settings_sheet.dart（线框 10）
class ListenSettingsSheet extends StatelessWidget {
  const ListenSettingsSheet({super.key, required this.settings,
    required this.onSettingsChanged, required this.onClose});
}
// app/lib/widgets/listen_follow_highlight.dart（线框 09 当前句高亮；US-17）
class ListenFollowHighlight extends StatelessWidget {
  const ListenFollowHighlight({super.key, required this.text,
    required this.highlightStart, required this.highlightEnd});
}
```

## 3. 数据模型变化

- **零新表、零迁移**：不新建听书进度表（听读同进度不变式，`docs/04 §9.4` 规则1）。
- **`reading_progress` 复用**：仍由 `LibraryService::save_progress/load_progress`（`core/src/library/mod.rs:101-109`）与 `api.rs progress_save/progress_get` 承载；`Locator` 结构零改动。
- **`settings` 新增键**（复用既有 `settings(key,value)` 表，`core/src/store/mod.rs:286`）：
  | 键 | 值 | 默认 | 读回规则 |
  |---|---|---|---|
  | `listen.voice_id` | 字符串（`system_male`/`system_female`） | `system_male` | 空/未知 → 默认 |
  | `listen.speed` | f32 字符串 | `1.0` | 解析失败 → 1.0；clamp `[0.5,3.0]` |
  | `listen.auto_next` | `"1"`/`"0"` | `"1"`（开启） | 非 `"1"` → false |
  - `listen.timer` **不建**（定时关闭明确不做，01-req §1.2）。
- **桥接 DTO（非持久化）**：`LocatorView`/`SentenceChunkView`/`ListenSettingsView`（§2.2）；Dart `SentenceLocator`/`SentenceChunk`/`ListenSettingsData`（§2.3/2.4）。
- **UI 运行态**：`ListenPage` 私有 `_chunks/_index/_state/_settings/_chapterText/_dirty/_debounceTimer`（内存，不入库）。

## 4. 关键时序

### 4.1 听书启动（US-1/US-2/US-3/US-9）
```
ReaderPage._openMore 点"听书"
  → Navigator.pop(context)                       // 关闭底部弹层（find.text('导出') findsNothing）
  → Navigator.push(MaterialPageRoute(→ ListenPage(
        bookId, bookTitle, href:_hrefFor(view), progression:_chapterProgress,
        backend: widget.backend, ttsBackend:_ttsBackend, ttsEngine:_ttsEngine)))
ListenPage.initState
  → _settings = await ttsBackend.loadListenSettings()           // settings 三键
  → view = await backend.openBook(bookId)
  → _chapterIndex = href 解析（chapter_%04d.xhtml）；_chapterText = view.chapters[_chapterIndex].text
  → _chunks = await ttsBackend.segment(bookId, href)
  → idx = await ttsBackend.sentenceIndexAt(bookId, href, locatorFor(progression))  // 从当前阅读位置起播
  → await ttsEngine.configure(voiceId:_settings.voiceId, speed:_settings.speed)
  → _state = Playing; await ttsEngine.speak(_chunks[idx])       // **不调用 saveProgress**（US-2）
  → 控制条渲染（章节名/⏮/⏸/⏭/Slider/1.0x/定时禁用/音色禁用）
```

### 4.2 句完成 → 进度落库 + 高亮推进（US-14/US-17）
```
ttsEngine.events: TtsSentenceDone(i)
  → chunk = _chunks[i]
  → _dirty = true; _saveProgressDebounced(chunk.locator)   // 300ms 合并；退出强刷
      → backend.saveProgress(bookId, chunk.locator.href, chunk.locator.progression)
  → 若 i+1 < N：_index=i+1; 高亮切到 _chunks[i+1] 的 [charStart,charEnd); ttsEngine.speak(_chunks[i+1])
  → 若 i == N-1：auto_next ? _loadNextChapter() : _stop()   // US-18
```

### 4.3 播放/暂停/停止与语速（US-10/US-11）
```
暂停: _state=Paused; ttsEngine.pause()；图标切 ▶
播放: _state=Playing; ttsEngine.resume()
停止: _state=Stopped; ttsEngine.stop()（句级进度停止推进）
设置面板拖动语速 v∈[0.5,3.0] → _settings=copyWith(speed:v); ttsEngine.configure(speed:v);
    await ttsBackend.saveListenSettings(_settings)  // listen.speed 持久化；文本更新为 "v.x"
```

### 4.4 句级进度条拖动（US-16）
```
ListenControlBar.onSeek(v) 松手
  → j = (v * (N-1)).round().clamp(0, N-1)
  → ttsEngine.stop(); _index=j; 高亮切句 j; ttsEngine.speak(_chunks[j])
  → _dirty=true; backend.saveProgress(bookId, _chunks[j].locator.href, _chunks[j].locator.progression)
```

### 4.5 退出 / 返回阅读页（US-15）
```
返回（AppBar 返回 / 系统返回）
  → if (_dirty) await _flushProgress()          // 强制刷一次（300ms 防抖窗口内不丢）
  → Navigator.pop(context)
ReaderPage: await Navigator.push(...) 之后 → _reloadProgress()
  → p = await backend.loadProgress(bookId); _chapterIndex = _chapterIndexForHref(p.href);
    _chapterProgress = p.progression; _jumpToProgress(...)
  → 断言：章节与 progression 与听书写入一致
```

### 4.6 章末连播（US-18）
```
TtsSentenceDone(N-1) 且 _settings.autoNext
  → nextHref = chapter_(idx+1).xhtml；若超出 chapters.length-1 → _stop()（不越界）
  → _chapterIndex++; _chapterText = view.chapters[_chapterIndex].text
  → _chunks = await ttsBackend.segment(bookId, nextHref); _index=0
  → backend.saveProgress(bookId, nextHref, 0.0); ttsEngine.speak(_chunks[0])
关闭连播：TtsSentenceDone(N-1) → _state=Stopped（不加载下一章）
```

### 4.7 分页模式禁原生菜单 + 选区回传（US-19/US-20/US-21）
```
PagedWebView.build → initialSettings: buildPagedWebViewSettings(disableContextMenu: true)
  → Android: 长按不出现系统 ActionMode 浮动菜单（插件 return actionMode）
  → JS selectionchange 保留：选区非空 → callHandler('selectedText', txt)
      → PagedWebView.onSelectedText → ReaderPage._onSelectedText → ReaderSelectionToolbar
滚动模式（不改）：SelectionArea(contextMenuBuilder: (...) => const SizedBox.shrink())（reader_page.dart:533-537）
  → 无 AdaptiveTextSelectionToolbar；仅 ReaderSelectionToolbar（US-21 回归）
```

## 5. 逐屏原型映射（deviation=0 目标）

### 5.1 `docs/wireframes/09-listen-player.svg`（听书跟读）
| 线框元素（坐标/文案） | 实现 | 可测断言 |
|---|---|---|
| 顶部标题"听书模式 · 跟读" | `ListenPage` AppBar（title '听书' + 返回 + 设置图标 tooltip '听书设置'） | `find.text('听书')`；`find.byTooltip('听书设置')` |
| 正文区灰色短横线（y=90..430） | `ListenFollowHighlight`（正文文本 + 当前句高亮 span） | `find.byType(ListenFollowHighlight)` |
| 当前朗读句蓝色半透明矩形（y≈191）+ "朗读中"徽标 | 高亮区间 `[charStart,charEnd)` 背景色 + 徽标 | US-17：高亮子串 == `chunk.text`；推进后旧句不高亮 |
| 控制条第 1 行：章节名"第三章 · 起风了" | `ListenControlBar.chapterTitle` | `find.text(章节名)` |
| 控制条第 2 行：`⏮` / `⏸`（播放中）/ `⏭` | `IconButton(Icons.skip_previous/skip_next)` + 播放/暂停 `Icons.pause/play_arrow` | US-3/US-10：`find.byIcon` |
| 控制条第 3 行：句级进度条 + `1.0x` | `Slider`（句级）+ `Text('${speed}x')` | US-3/US-16：`find.byType(Slider)` + 速度文本 |
| 右侧 `⏱ 30 分钟`（定时） | 按钮**禁用占位**（`onPressed: null`） | US-3：按钮存在且禁用 |
| 右侧 `🎙 男声·AI`（音色） | 按钮**禁用占位**（显示当前系统音色，如"🎙 系统男声"；线框"AI"属 P2 示意） | US-3：按钮存在且禁用 |
| 底部说明"迷你播放条/空格暂停/←→跳句" | **P2 不做**（后台播放/跨页常驻，01-req §1.2） | 不实现；范围划界 |

### 5.2 `docs/wireframes/10-listen-settings.svg`（听书设置）
| 线框元素 | 实现 | 可测断言 |
|---|---|---|
| 标题"听书设置" | `ListenSettingsSheet` 标题 | `find.text('听书设置')` |
| 音色行1"系统男声"（选中）/"离线" | `RadioListTile` 可选 | US-13：可选、选中态 |
| 音色行2"系统女声"/"离线" | `RadioListTile` 可选 | US-13：可选 |
| 音色行3"AI 音色 · 在线"/"需网络（P2）" | `RadioListTile(onChanged: null)` 灰置 + 文案 | US-13：`onChanged == null` |
| 音色行4"本地神经音色 Piper"/"下载 52MB（P2）" | 禁用灰置 + 文案 | US-13 |
| 音色行5"声音克隆 · 评估中" | 禁用灰置 | US-13 |
| 语速分组：0.5x—3.0x 滑块 + "1.0x" | `Slider(min:0.5,max:3.0)` + 文本 | US-11：拖动 → `configure(speed)` + 文本更新 |
| 定时关闭分组（关闭/15/30/60/本章结束） | 全部禁用灰置 | US-13：`onChanged == null` |
| 后台播放开关（开） | `SwitchListTile(onChanged: null)` 灰置 | US-13：`onChanged == null` |
| 面板外隐私说明 | 静态文案（"离线音色不联网…"） | `find.textContaining('离线音色不联网')` |

### 5.3 `docs/wireframes/reader-ui-v2/04-selection.svg`（选中浮动工具条，回归守护，不改布局）
| 线框元素 | 本 REQ 关系 | 可测断言 |
|---|---|---|
| 浮动工具条 5 入口：划重点/笔记/翻译/查词/复制 + 笔记 4 色圆点 | REQ-004 产物，**零改动**；本 REQ 只保证分页模式不被原生菜单覆盖 | US-20：分页选区回传后 `ReaderSelectionToolbar` 出现、五入口齐全 |
| 选中文本上方定位、两端选柄、词典卡片 | REQ-004/003 产物，零改动 | US-20/US-21 回归 |
| 滚动模式"只有自定义工具条" | `reader_page.dart:533-537` 不改 | US-21：`AdaptiveTextSelectionToolbar` findsNothing |

## 6. 与既有约定的兼容性

- [x] **不破坏 Locator 模型**：`core/src/types.rs` 零改动；只新增 `LocatorView` 桥接 DTO；`char_range`/`TextAnchor.start/end` 统一 UTF-16 半开区间（无存量实现依赖其他单位）。
- [x] **不跨越限界上下文**（`docs/04 §1`）：听书复用 Reading/Locator/reading_progress，不新建领域表；tts 是 Reading 的支撑模块，不反向依赖 library/store（domain 文本入参）。
- [x] **听读同进度不变式保持**（`docs/04 §9.4` 规则1）：`reading_progress` 仍是唯一事实源；进入听书不写盘，句完成/拖动/退出写盘，返回阅读页重读。
- [x] **ddd-rules 零改动**：domain `core/src/tts` 只 `use crate::types`；interface `core/src/api.rs`/`app/lib/pages`/`app/lib/engines` 不 import `src/rust/`（`system_tts_engine.dart` 只 import flutter_tts；`listen_page.dart` 经 `TtsBackend`）；application `app/lib/services` 负责生成物→DTO 转换（先例 `rust_library_backend.dart`）。`app/lib/widgets/listen_*.dart` 未在 ddd-rules 声明 → 按 pages 同级纪律（只经 services/engines，禁 `package:reader_app/src/rust/`、`src/rust/`），03-review 人工核对 import 面。
- [x] **REQ-001/003/004 复用不重做**：`openBook/chapterHtml/saveProgress/loadProgress` 零改动；`ReaderSelectionToolbar`/`translation_popup.dart`/`SelectionArea` 零改动；`PagedWebView` 仅加 settings 工厂（`next/prev/gotoPage/relayout/onProgress/onSelectedText` 及 fake 构建器契约不变）；`_openMore` 听书项由占位改跳转（更新既有测试预期）。
- [x] **原型一致性**：09/10/04-selection 逐屏映射见 §5；`deviation=0` 由 T-013 自检。
- [x] **范围划界**：定时关闭/后台播放/媒体键/多音色/AI/Piper/克隆/点读/笔记/划重点均不实现（P2 禁用灰置，§8）；`just_audio`/`audio_service` 保持注释。
- [x] **零新表/零迁移**：`settings` 复用，仅新增三个键。

## 7. US ↔ 设计对应关系

| US | 设计落点 | 关键断言 |
|---|---|---|
| US-1 | §2.6 `ListenPage` 构造注入；§4.1 入口 push | `find.byType(ListenPage)`；弹层关闭；fake 注入 |
| US-2 | §4.1 起播定位 + "不写盘" | `speak` 收到句索引 == `sentenceIndexAt(progression)`；`saveProgress` 未调用 |
| US-3 | §2.6/§5.1 控制条 | 章节名/⏮/⏸▶/⏭/Slider/速度文本/定时禁用/音色禁用 |
| US-4 | §2.1 切句规则（ADR 1b） | 句数>0、trim、`prev.charEnd==next.charStart`、引号成对、空文本 `Ok(vec![])` |
| US-5 | §2.1/2.2 | `book_id/href/progression∈[0,1]` 单调、`snippet` 为句前缀、越界 Err |
| US-6 | §2.1/2.2 边界语义 | 往返 `i == indexAt(locatorFor(i))`；章首 0/章末 N-1；不匹配 Err |
| US-7 | §2.2/2.3/2.4 | 生成物三函数 + 字段一一对应 + FFI 往返 |
| US-8 | §2.1 domain 计时 | 10 万字 <50ms（CI ≤200ms） |
| US-9 | §2.5 `SystemTtsEngine`；pubspec | `configure→setSpeechRate/setVoice`；`speak→speak(text)` |
| US-10 | §4.3 状态机 | `pause/resume/stop` 调用序列 + 图标态 |
| US-11 | §4.3/§5.2/决策点6 | `configure(speed)` + 文本更新 + `listen.speed` 往返 |
| US-12 | §2.5/§4.1 失败事件 | 无网络依赖；`TtsFailed` → 可读提示含"语音/安装" |
| US-13 | §5.2/§8 | 系统男/女可选；AI/Piper/克隆/定时/后台禁用灰置 |
| US-14 | §4.2 | `saveProgress(href, progression)` 参数 == 句 locator；300ms 防抖 + 退出强刷 |
| US-15 | §4.5 | 退出→返回阅读页同章同 progression；重开恢复 |
| US-16 | §4.4 | 拖动松手 → `speak(句 j)` + `saveProgress(句 j)` |
| US-17 | §2.6/§5.1 | 高亮子串 == `chunk.text`；推进切换 |
| US-18 | §4.6 | 连播开→下一章句 0；关→Stopped；末章停止 |
| US-19 | §2.5/§4.7 | `buildPagedWebViewSettings().disableContextMenu == true` |
| US-20 | §4.7 | 选区回传 → 工具条出现、五入口齐全 |
| US-21 | §4.7/§6 | 滚动模式无原生工具条；`contextMenuBuilder` 仍 `SizedBox.shrink` |
| US-22 | §2.6 `_onSelectionAction.copy` | `Clipboard.getData == 选中文本`（P1 可选） |
| US-23 | §7 + 02-plan T-013 | 九项 widget 用例 + `flutter test` 全绿 |
| US-24 | §2.1 删旧测试 + 新用例 | `cargo test -p reader_core` 全绿 |
| US-25 | §6 兼容性 | 既有测试全绿（reader_page_test 更多弹层用例更新） |

## 8. P2 控件"禁用灰置"实现（可断言）

- **统一实现**：P2 控件一律传 `onChanged: null` / `onPressed: null`（Flutter 原生禁用态自动灰置），**不**使用 `enabled: false` 以外的自定义变灰。
- 具体：
  | 控件 | 实现 | 断言 |
  |---|---|---|
  | AI 音色/Piper/声音克隆 `RadioListTile` | `onChanged: null` | `tester.widget<RadioListTile>(...).onChanged == null` |
  | 定时关闭选项（关闭/15/30/60/本章结束） | `RadioListTile(onChanged: null)` | 同上 |
  | 后台播放 `SwitchListTile` | `onChanged: null` | `.onChanged == null` |
  | 控制条定时按钮 | `IconButton(onPressed: null)` | `.onPressed == null` |
  | 控制条音色按钮 | `IconButton(onPressed: null)` | `.onPressed == null` |
- 点击 P2 控件无状态变更、不崩溃（US-13 断言）。

## 9. 已知取舍（非冲突，均含处置）
1. **US-3 与 US-13 的入口措辞冲突**：控制条"音色按钮禁用"（US-3）与"听书设置入口"（US-13）→ 关联裁定1：设置入口移到 AppBar 设置图标，控制条两按钮保持禁用占位。
2. **`char_range`/`TextAnchor` 单位由字节改为 UTF-16**：与 Dart 索引对齐（ADR 决策点1(b)）；未来 `LocatorResolver` 需做 UTF-16↔字节映射（已登记）。
3. **`tts_segment` 含 `open_book` I/O**：US-8 只对 domain `segment(text,…)` 计时；FFI I/O 成本单列（决策点1(a)）。
4. **`total_progression` 本期近似**：无全书权重，取章内值，仅展示（关联裁定6）。
5. **`tts_sentence_index_at` 每次重建 domain `Locator` 且重切句**：章内句数有限、调用稀疏（起播/拖动），性能可接受；若后续高频调用再引入章文本缓存（记录）。
6. **widgets 未列入 ddd-rules**：与 REQ-004 相同处置（§6），规则表冻结零改动，建议后续评审纳入 interface paths（不执行）。

## 闸门2 自评（设计部分）
- [x] **逐屏对照原型**：09（控制条逐元素）、10（音色/语速/定时/后台逐项）、04-selection（回归守护）映射表齐备；无自创布局。
- [x] **模块/接口/数据模型/时序齐备**：§1 模块与层、§2 Rust/Dart 签名（含 DTO 字段）、§3 零新表 + settings 键、§4 七条关键时序、§6 兼容性清单。
- [x] **US 对应关系**：§7 覆盖 US-1..US-25；P2 禁用灰置实现可断言（§8）。
- [ ] **未完全落定项**：`docs/03 §13.3`/`docs/04 §9.5` 文档同步（async/`LocatorView`/`u32`/domain 文本入参）待开发/交付阶段执行；本阶段按纪律不改 docs，**标记为待同步风险**。
