<!-- wf-meta: req=REQ-005-fixes | phase=architecture | agent=architect | date=2026-09-08 | gate=passed -->
# REQ-005-fixes · 架构决策记录（ADR：Rust 切句桥接契约 / 分页禁原生菜单 / TTS 分层 / 听书状态与进度 / 入口接线 / 设置持久化）

## 决策
把"听书不可用"这条断链按 **domain 纯函数（文本入参）→ interface 取文本 → FRB 桥接 DTO（`SentenceChunkView`/`LocatorView`，UTF-16 半开区间）→ services 转 DTO → `SystemTtsEngine` → `ListenPage` 状态机** 串通，听读共用既有 `reading_progress`（零新表）；分页原生菜单在 `PagedWebView` 内以**可测的 settings 工厂**关闭（`disableContextMenu: true`），保留既有 `selectionchange` 选区回传，与滚动模式既有的 `contextMenuBuilder → SizedBox.shrink()` 形成"两模式都只有自定义工具条"。UI 严格对齐 `docs/wireframes/09-listen-player.svg`、`10-listen-settings.svg`、`reader-ui-v2/04-selection.svg`，deviation 目标 = 0。

---

## 决策点 1：Rust 切句 / 句↔Locator 的桥接契约（R1-5/R1-6/R1-7）

### 1(a) DDD 取文本方案（`core/src/tts` 属 domain，禁 `crate::store`/`crate::library`/`crate::api`）

**现状（已核实）**：`core/src/tts/mod.rs:62-85` 三个 free function 签名为 `segment(book_id, href)`、`locator_for_sentence(book_id, href, idx)`、`sentence_index_at(book_id, href, loc)`，均 `Err(NotImplemented)`；domain 层无法读章节文本（`docs/04 §9.5` 的同名签名没有文本来源）。

#### 备选
- **A：domain 定义 `ChapterTextSource` trait，infrastructure 实现、装配层注入（对齐 REQ-003 `TranslationCacheRepository` 先例）**
  - 做法：在 `core/src/types.rs`（共享内核）定义 `trait ChapterTextSource { fn chapter_text(&self, book_id:&str, href:&str) -> Result<String>; }`；`core/src/library`（application）实现；`core/src/api.rs` 装配并注入。`core/src/tts` 需从 free function 升级为持有 `Box<dyn ChapterTextSource>` 的服务结构（或全局注入），签名变成 `segment(&self, book_id, href)`。
  - 优点：domain 侧签名与 `docs/04 §9.5` 逐字一致；文本来源可 fake（domain 单测不碰 IO）。
  - 缺点：① free function → 有状态服务的结构性重构，`tts/mod.rs` 现有 3 个函数与单测全部改写；② 需新增 trait + 实现 + 装配 + 进程内单例，改动面从"实现 3 个函数"扩到"新增一条依赖注入链"；③ trait 返回 `Result<String>` 把 I/O 语义带进 domain 契约；④ 与"最小修复（01-req 约束）"冲突。
- **B（选）：domain 函数改**文本入参**，`core/src/api.rs`（interface）经 `LibraryService::open_book` 按 href 取 `Chapter.text` 后调用；FFI 函数名保持 `tts_segment(book_id, href)`**
  - 做法：
    ```rust
    // core/src/tts/mod.rs（domain；仅 use crate::types）
    pub fn segment(text: &str, book_id: &BookId, href: &str) -> Result<Vec<SentenceChunk>, TtsError>;
    pub fn locator_for_sentence(text: &str, book_id: &BookId, href: &str, idx: usize) -> Result<Locator, TtsError>;
    pub fn sentence_index_at(text: &str, book_id: &BookId, href: &str, loc: &Locator) -> Result<usize, TtsError>;
    ```
    ```rust
    // core/src/api.rs（interface；新增内部 helper，不新增桥接面）
    fn chapter_text(id: &str, href: &str) -> std::result::Result<String, String>;
    // 经 service()?.open_book(id)（LibraryService::open_book -> OpenedBook.chapters[i].href == href）
    // 取 Chapter.text；FFI 对外仍是 tts_segment(book_id, href)
    ```
  - 优点：① domain 变成**纯文本处理**，单测无需 IO/装配，US-4/5/6/8 直接喂字符串；② 改动最小（不新增 trait/单例/装配），保留 free function 结构；③ domain 仍只 `use crate::types`，ddd-lint 违规=0；④ FFI 对外签名（docs/03 §13.3 的函数名与入参）不变，只新增内部 helper；⑤ `Chapter.href` 已存在（`core/src/format/mod.rs:49-59`），规范 EPUB 章节扁平命名 `chapter_%04d.xhtml`（`core/src/convert/mod.rs:61-69`），按 href 精确匹配可靠。
  - 缺点：① `tts` domain 的入参比 `docs/04 §9.5` 多一个 `text`（文档需同步一句注释）；② 每次 FFI 调用都 `open_book`（解析规范 EPUB）取文本，`tts_segment` 单次有 IO 成本（切句本身仍 <50ms；见下）。

#### 选择与理由
选 **B**。01-req 明确"最小修复"，A 把问题从"实现切句"扩大到"引入依赖注入架构"，收益（签名与文档逐字一致）抵不上重构面；B 让 domain 保持纯函数、可被 US-4/5/6/8 直接断言，且 ddd-lint 天然合规。REQ-003 的 `TranslationCacheRepository` 先例解决的是"domain 需要持久化能力"，而这里 domain 只需要一段字符串——字符串入参就是最合适的"依赖倒置"。

#### 影响
- `core/src/tts/mod.rs`：3 个函数签名加 `text: &str`；`SentenceChunk` 结构不变；删除 `:99-103` 的 `not_implemented_yet`（`is_err()` 与实现冲突），改由 US-4/5/6/8 用例覆盖。
- `core/src/api.rs`：新增 `chapter_text` helper（interface 可用 `crate::library`）；FFI 三函数签名见决策点 1(b)。
- `docs/04 §9.5`/`docs/03 §13.3`：需同步一行"domain 签名文本入参；FFI 签名不变/异步/`LocatorView`"（文档改动归开发/交付阶段，本阶段只落 ADR/design/plan）。
- 性能：US-8 的 `<50ms` 以 **domain `segment(text, …)` 直接计时**为准（文本已在手）；FFI `tts_segment` 的 `open_book` I/O 成本单列，不纳入 US-8 断言。

### 1(b) 桥接 DTO 契约（R1-7：Dart `SentenceChunk` 与 Rust `SentenceChunk` 字段不一致；`Locator` 含 `Rect/TextAnchor` 不宜直接桥接）

**现状（已核实）**：Dart `SentenceChunk{text,charStart,charEnd,totalProgression}`（`app/lib/engines/tts_engine.dart:25-37`）；Rust `SentenceChunk{text,char_range:(u32,u32),locator:Locator}`（`core/src/tts/mod.rs:10-17`）；`Locator` 含 `Rect/TextAnchor/cfi/page`（`core/src/types.rs:17-54`），FRB 生成面从未出现。

#### 备选
- **A（选）：新增桥接 DTO `SentenceChunkView` + `LocatorView`，字段与 Dart `SentenceChunk` 一一对应**
  ```rust
  // core/src/api.rs（桥接面；*View 命名沿用 DictInfoView 等既有约定）
  pub struct LocatorView {
      pub book_id: String,
      pub href: String,
      pub progression: f32,        // 章内 0.0..=1.0
      pub total_progression: f32,  // 全书 0.0..=1.0（本期=章内近似，见关联裁定6）
      pub snippet: Option<String>, // TextAnchor.snippet；无文本锚为 None
  }
  pub struct SentenceChunkView {
      pub index: u32,              // 章内句序号（0 起，供 TtsSentenceDone 回传）
      pub text: String,
      pub char_start: u32,         // UTF-16 code unit，半开区间 [start, end)
      pub char_end: u32,
      pub locator: LocatorView,
  }
  pub struct ListenSettingsView {
      pub voice_id: String,
      pub speed: f32,              // 0.5..=3.0
      pub auto_next: bool,
  }
  ```
  ```dart
  // app/lib/engines/tts_engine.dart（与桥接 DTO 一一对应）
  class SentenceLocator {
    final String bookId;
    final String href;
    final double progression;       // 章内
    final double totalProgression;  // 全书（本期近似）
    final String? snippet;
  }
  class SentenceChunk {
    final int index;                // 章内句序号
    final String text;
    final int charStart;            // UTF-16 code unit，[start,end)
    final int charEnd;
    final SentenceLocator locator;
  }
  ```
  - 优点：字段严格一一对应（US-7 可断言字段名/类型）；不暴露 `Rect/cfi/page`；`snippet` 满足 US-5 的"文本锚前缀一致"；`index` 让 `TtsSentenceDone(index)` 在 seek/暂停后仍正确。
  - 缺点：Dart `SentenceChunk` 由旧的 `totalProgression` 平铺字段改为 `locator` 嵌套（实现时需同步改；当前无生产调用方，仅接口声明）。
- **B：直接把 domain `Locator` 桥接给 Dart（FRB 暴露 `Locator`）**
  - 优点：类型不新增。
  - 缺点：`Locator` 含 `Rect`/`TextAnchor`/`cfi`/`page`，FRB 需为这些类型全部生成桥接（`Rect` 目前不是桥接类型），契约面膨胀；Dart 侧拿到一堆无意义字段；与 `*View` 命名约定不符。**拒绝**。
- **C：把 `char_range` 直接以 `(u32,u32)` 元组桥接**
  - 缺点：FRB 对元组的 Dart 表示不直观，Dart `SentenceChunk.charStart/charEnd` 需解包，US-7 字段名断言困难。**拒绝**（改为 `char_start/char_end` 两个标量）。

#### 选择与理由
选 **A**。桥接面最小、字段一一对应、`Locator` 领域字段不外泄；`index` 是 `TtsSentenceDone` 正确性的关键（否则 seek 后引擎内部计数器错位），且不改 `docs/03 §13.2` 的 `speak(SentenceChunk)` 签名（index 随 chunk 走）。

#### char 偏移计量单位（契约核心）
**决策：UTF-16 code unit，半开区间 `[start, end)`。**
- 与 Dart 索引一致：Dart `String` 的索引/`substring`/`TextSpan` 均以 UTF-16 code unit 为单位，US-17 跟读高亮可直接 `chapterText.substring(chunk.charStart, chunk.charEnd)`，无需换算。
- Rust 侧换算：`text.encode_utf16().count()` 得总长；字符边界用 `char_indices()` 遍历 + 逐字符 `len_utf16()` 累加，**禁止**直接用字节偏移做 Dart 切片。
- 与 `TextAnchor.start/end` 一致：`locator_for_sentence` 产出的 `TextAnchor.start/end` 同样使用 UTF-16 半开区间（与 `char_range` 同值），保证"文本锚"与"高亮区间"同尺度。
- 风险登记：未来 `LocatorResolver` 若用 Rust `&str` 字节切片做 snippet 模糊匹配，需先把 UTF-16 偏移映射回字节偏移（`char_indices` + `len_utf16` 前缀和）；本期 `LocatorResolver` 未实现，无存量冲突。

#### `progression` 构造规则（单调不减）
**决策：`progression_i = char_start_i / total_utf16_len(text)`，clamp `[0.0, 1.0]`。**
- 因每句 `text` 非空、`char_start` 严格递增，`progression_i` 严格递增（满足 US-5"单调不减"）。
- 首句 `char_start=0` → `progression_0 = 0.0`；末句 `char_start < total_len` → `progression_{N-1} < 1.0`。
- 空文本：`segment` 返回 `Ok(vec![])`；`total_len=0` 时不存在句子，不产生除零（映射函数在 N=0 时返回 `Err`）。
- 阅读页的 `progression`（页/列粒度）与句子的字符粒度是同一"章内进度"语义（`docs/04 §3`），互转是近似（`docs/04 §3` 定位算法已授权容错），US-2 的"≈0.42"按此近似断言。

#### `sentence_index_at` 边界语义
**决策：返回满足 `progression_i <= loc.progression` 的最大 `i`（即"包含该进度的句子"）。**
- 章首：`loc.progression == 0.0` → `0`。
- 章末：`loc.progression == 1.0` → `N-1`（因所有 `progression_i < 1.0`）。
- 往返：`sentence_index_at(locator_for_sentence(i))` 中 `locator.progression == progression_i`，最大满足者即 `i` → US-6 往返一致。
- 错误：`href` 与 `book_id` 不匹配 → `Err`；`progression` 为 NaN 或 `<0.0` 或 `>1.0` → `Err`；空文本/N=0 → `Err`；均不 panic。
- `locator_for_sentence(i)`：`0 <= i < N` 返回 `Ok`，否则 `Err`。

#### `locator_for_sentence` 的文本锚填充
**决策：`text = Some(TextAnchor { snippet, start, end })`。**
- `snippet` = 该句 `text` 的前 `min(40, text_utf16_len)` 个 UTF-16 code unit（不足则整句），非空。
- `start/end` = 该句 `char_range`（UTF-16 半开区间）。
- `book_id/href/progression/total_progression` 按上述规则填充；`cfi/page/rect = None`（非 PDF）。
- 桥接 `LocatorView.snippet` 取 `text.snippet`（`None` 仅出现在非 tts 来源的 Locator，本期 `locator_for_sentence` 恒为 `Some`）。

#### 切句规则（`docs/04 §9.4` 规则2，US-4 断言依据）
1. **句末定界**：`。！？；…` 及 ASCII `.!?;`（半角句点见第 4 条）+ 段落边界 `\n`/`\r\n`。
2. **成对保留**：定界符后紧跟的收尾引号/括号（`」』”’）)】》〉`）并入本句；`“”‘’《》「」『』（）【】` 成对保留在句内，不在引号内部切。
3. **`……` 整体**：连续两个及以上 `…`（或 `...`）视为一个定界整体，在整体末尾切，不在两个 `…` 之间切。
4. **英文句点/缩写不误切**：`.` 仅当前一非空白字符是字母且后一字符是空白/串尾、且不构成缩写（`e.g.`/`i.e.`/`Mr.`/`Mrs.`/`Dr.`/`No.` 等小写缩写表 + 单大写字母缩写）且不在数字之间（`3.14`）时，才作句末。
5. **区间连续不重叠**：`char_range_i = [start_i, start_{i+1})`（末句 `end = total_len`），其中 `start_i` 是第 i 句首个非空白字符的 UTF-16 下标（跳过句间空白/换行）→ 恒有 `prev.char_end == next.char_start`（US-4 直接断言）；`text_i = text[start_i..start_{i+1}].trim()`（已 trim、非空）。
6. **不跨段合并**：段落边界（`\n`）强制断句，段落结尾无标点时也在边界处切。
7. **空/纯空白文本**：`Ok(vec![])`（不 `NotImplemented`、不 panic）。
8. **超长无标点**：整段作为一句返回（不丢弃）。

#### 影响（1b）
- `app/lib/engines/tts_engine.dart`：`SentenceChunk` 改为 `{index,text,charStart,charEnd,locator}` + 新增 `SentenceLocator`；`TtsEvent` 保持 `TtsSentenceDone/TtsFailed`（`Interrupted` P2 不做，01-req §1.3 已授权）。
- `core/src/api.rs`：`to_locator_view`/`to_chunk_view` 转换 + `sentence_index_at` 入参由 `Locator` 变 `LocatorView`（在 api 层重建 domain `Locator` 后调用 domain 函数，domain 签名仍 `&Locator`）。
- `docs/03 §13.3`/`docs/04 §9.1`：DTO/异步/`u32` 序号需同步说明。
- 测试：US-7 断言生成物函数名（`ttsSegment`/`ttsLocatorForSentence`/`ttsSentenceIndexAt`）与字段名/类型；US-4/5/6 断言切句与往返。

#### 降级线（授权）
若 FRB 对 `Option<String>`/嵌套 struct 的生成出现障碍：降级为**扁平 DTO**（`SentenceChunkView{index,text,char_start,char_end,book_id,href,progression,total_progression,snippet}`），Dart `SentenceChunk` 同步扁平化；**契约字段语义（UTF-16 半开区间、progression 规则、边界语义）不变**。此降级不改变 US-4/5/6/7 的断言内容，只改字段嵌套形态，由 developer 在 T-002 记录 diff。

---

## 决策点 2：分页模式禁用 WebView 原生选择菜单的实现位置（R2-2）

**现状（已核实）**：`app/lib/engines/paged_web_view.dart:149-152` 的 `initialSettings` 只有 `useShouldInterceptRequest`/`transparentBackground`，未设 `disableContextMenu`；`:215-223` 的 `selectionchange` 监听保留选区回传；插件默认 `false`，Android 实现在 `disableContextMenu` 为真时直接 `return actionMode`（不展示浮动菜单、不影响选区）。widget 测试无法实例化真实 `InAppWebView`。

### 备选
- **A（选）：把 settings 提取为可测工厂 `buildPagedWebViewSettings({bool disableContextMenu = true, ...})`（顶层函数），`build()` 使用它；测试直接断言工厂返回值**
  - 优点：US-19 的"配置断言"可在纯 Dart 单测/widget 测试中直接执行（不依赖 WebView）；`build()` 与测试共用同一工厂，避免"测的常量和用的常量漂移"；可选参数为将来平台差异化留口。
  - 缺点：`PagedWebView.build` 需改成调用工厂（一行），无行为风险。
- **B：仅在 `build()` 内联加 `disableContextMenu: true`**
  - 优点：改动最小。
  - 缺点：widget 测试无法实例化真实 WebView → US-19 无任何可断言出口（01-req 已明确否决）。
- **C：保留 settings 默认，改用 `onContextMenu` 回调 + JS `preventDefault` 拦截**
  - 优点：不改 settings。
  - 缺点：`onContextMenu` 的平台触发时机/选区生命周期差异更大，且原生菜单可能先于回调出现；作为 A 失效时的**降级路径**更合适，不作为主方案。

### 选择与理由
选 **A**。US-19 要求"检查传给 `InAppWebView` 的 `initialSettings` 且 `disableContextMenu == true`"，可测工厂是唯一能同时满足"配置可断言 + 不依赖真机"的实现；插件 Android 源码已确认"只隐藏菜单、保留选区"，与 US-20 不冲突。

### 平台范围
- **Android：必须开启**（R2-2 的目标平台，US-19/US-20 验收平台）。
- **桌面/iOS：同一工厂默认同开**（app 自带自定义工具条，统一"只有一套菜单"的交互；`disableContextMenu` 在未实现的平台为无害 no-op）。若桌面实测出现选区/复制回归，可在 `build()` 传 `disableContextMenu: !isDesktop` 覆盖——**工厂参数已预留**，不改契约。

### 如何同时满足 US-19 与 US-20
- `disableContextMenu: true` 只抑制系统 `ActionMode` 浮动菜单（Android 插件 `return actionMode`），**不禁用文本选择**；选柄与 `selectionchange` 仍在。
- `:215-223` 的 JS 监听保留：选区非空 → `callHandler('selectedText', txt)` → `PagedWebView.onSelectedText` → `ReaderPage._onSelectedText` → `ReaderSelectionToolbar`（US-20）。
- 测试组合：US-19 = 工厂单测 `buildPagedWebViewSettings().disableContextMenu == true`；US-20 = 既有 fake 分页构建器触发 `onSelectedText` → 工具条 `findsOneWidget` + 五入口齐全；真机/集成 = 长按无 ActionMode 且工具条出现（US-23 记录真机项）。

### 降级线（授权）
若真机确证"禁用菜单导致选区回传失效"（`selectionchange` 不再触发或选柄消失）：**降级为自定义 JS 长按菜单**——保留 `disableContextMenu: true`，在 `paginationJs` 增加 `contextmenu` 事件 `preventDefault` + 基于现有 `selectionchange` 的选区捕获，必要时在页内注入轻量自绘菜单；**绝不退回原生菜单**。降级只改 `paged_web_view.dart` 的 JS/回调，不改 `ReaderPage`/`ReaderSelectionToolbar` 契约。

---

## 决策点 3：TTS 引擎与服务的分层 / 注入

**现状（已核实）**：`TtsEngine` 只有抽象（`app/lib/engines/tts_engine.dart:9-22`），无 `SystemTtsEngine`；`flutter_tts` 被注释（`app/pubspec.yaml:26-29`）；`app/lib/engines` 属 interface 层，`ddd-rules.toml:16` 禁 import `package:reader_app/src/rust/`、`src/rust/`；`app/lib/services` 属 application 层，可 import 生成物（先例 `rust_library_backend.dart`/`rust_translate_backend.dart`）。

### 备选
- **A（选）：`SystemTtsEngine implements TtsEngine` 放 `app/lib/engines/system_tts_engine.dart`（interface，只 import `flutter_tts` + `tts_engine.dart`）；新增 `app/lib/services/tts_backend.dart`（抽象 `TtsBackend` + 返回引擎 DTO）+ `app/lib/services/rust_tts_backend.dart`（import 生成物并转 DTO）；`ListenPage` 构造注入 `TtsEngine`/`TtsBackend`/`LibraryBackend`**
  - 优点：US-1 可注入 fake；US-9 可注入 `FlutterTts`/mock 平台通道；分层合规（engines 不碰生成物、services 负责 FFI 转换）；与 REQ-003 服务模式完全同构。
  - 缺点：多两个文件。
- **B：`ListenPage` 内直接 `new SystemTtsEngine()` / `new FlutterTts()`**
  - 缺点：不可注入 fake，US-1/US-10/US-11 无法在 widget 测试断言调用序列；US-8 测试基础设施风险。**拒绝**。
- **C：`SystemTtsEngine`/`ListenPage` 直接 import `app/lib/src/rust/api.dart`**
  - 缺点：违反 `ddd-rules.toml:16` 的 `forbid_imports`（interface 层禁生成物）。**拒绝**。

### 选择与理由
选 **A**。与既有 `LibraryBackend`/`TranslateBackend` 模式一致；`TtsEngine` 只做"合成编排"，`TtsBackend` 只做"切句/映射/设置转发"，职责不混；`SentenceChunk`/`SentenceLocator` 作为引擎契约值对象定义在 `engines/tts_engine.dart`（interface），`services/tts_backend.dart` 引用它（application→interface 的值对象引用，无循环：`tts_engine.dart` 不 import services）。

### 接口签名
```dart
// app/lib/engines/system_tts_engine.dart（interface）
class SystemTtsEngine implements TtsEngine {
  SystemTtsEngine({FlutterTts? tts});                 // 测试注入（mock 平台通道）
  // configure -> setSpeechRate(speed)/setVoice(voice)；speak -> speak(chunk.text)；
  // 完成回调 -> events.add(TtsSentenceDone(chunk.index))；异常 -> TtsFailed(message)
}
```
```dart
// app/lib/services/tts_backend.dart（application）
abstract class TtsBackend {
  Future<List<SentenceChunk>> segment(String bookId, String href);
  Future<SentenceLocator> locatorForSentence(String bookId, String href, int index);
  Future<int> sentenceIndexAt(String bookId, String href, SentenceLocator locator);
  Future<ListenSettingsData> loadListenSettings();
  Future<void> saveListenSettings(ListenSettingsData settings);
}
class ListenSettingsData { final String voiceId; final double speed; final bool autoNext; ... }
```
```dart
// app/lib/pages/listen_page.dart（interface）
class ListenPage extends StatefulWidget {
  const ListenPage({
    super.key,
    required this.bookId, required this.bookTitle,
    required this.href, required this.progression,
    required this.backend,        // LibraryBackend（进度/取文本）
    required this.ttsBackend,     // TtsBackend（segment/locator/settings）
    required this.ttsEngine,      // TtsEngine（SystemTtsEngine / fake）
  });
}
```
```rust
// core/src/api.rs（interface）
pub async fn tts_segment(book_id: String, href: String) -> std::result::Result<Vec<SentenceChunkView>, String>;
pub async fn tts_locator_for_sentence(book_id: String, href: String, idx: u32) -> std::result::Result<LocatorView, String>;
pub async fn tts_sentence_index_at(book_id: String, href: String, locator: LocatorView) -> std::result::Result<u32, String>;
```

### 影响
- `app/pubspec.yaml`：`flutter_tts: ^4` 取消注释；`just_audio`/`audio_service` 保持注释（后台播放 P2）。
- `app/lib/pages/library_page.dart`：构造 `ReaderPage` 时无需传 tts（ReaderPage 懒创建默认实现）。
- 测试：新增 `app/test/fake_tts_engine.dart`、`app/test/fake_tts_backend.dart`、`app/test/tts_engine_test.dart`。

### 降级线（授权）
若 `FlutterTts` 无法在测试环境子类化/mock：`SystemTtsEngine` 内部再抽一层 `TtsPlatform`（`setRate/setVoice/speak/stop/…` 四方法）接口，生产实现包 `FlutterTts`、测试注入 `FakeTtsPlatform`；`TtsEngine` 契约不变。

---

## 决策点 4：听书页状态机与进度持久化

**现状（已核实）**：`ListenPage` 是 `StatelessWidget` 占位（`app/lib/pages/listen_page.dart:5-15`）；`reading_progress` 由 `LibraryService::save_progress/load_progress`（`core/src/library/mod.rs:101-109`）承载，`api.rs progress_save/get` 与 `LibraryBackend.saveProgress/loadProgress` 已通；`reader_page.dart:158-166` 的 300ms 节流是既有写盘节流语义。

### 备选
- **A（选）：`ListenPage` 改 `StatefulWidget`，状态机 `Idle/Playing/Paused/Stopped`（`Interrupted` P2 不做，docs/04 §9.3）；句完成 → `LibraryBackend.saveProgress(bookId, locator.href, locator.progression)`，300ms 防抖 + 退出/`dispose` 强制刷；进入不写盘**
  - 优点：复用既有 `reading_progress`（听读同进度不变式），零新表；`saveProgress` 语义与阅读页完全一致（US-14/15/16）。
  - 缺点：防抖窗口内退出需强制刷（用 `_dirty` 标记解决）。
- **B：听书自建进度表（如 `listen_progress`）**
  - 缺点：制造第二个进度事实源，违反 `docs/04 §9.4` 规则1"`reading_progress` 是唯一事实源"，且与 US-15"返回阅读页同位置"直接冲突。**拒绝**。
- **C：仅会话内存，不持久化**
  - 缺点：US-15"应用重启从上次听读位置继续"、US-11"语速记忆"不可达。**拒绝**。

### 选择与理由
选 **A**。唯一同时满足"听读同进度 + 退出强刷 + 零新表"的方案；`saveProgress(href, progression)` 与 `reader_page.dart:164`/`:605-608` 的 `chapter_%04d.xhtml` 约定一致，US-14 可直接断言 `backend.saved`。

### 状态机
```
Idle ──(进入/首句 speak)──▶ Playing
Playing ⇄ Paused（pause/resume）
Playing ──(TtsSentenceDone i, i+1<N)──▶ Playing(i+1)
Playing ──(TtsSentenceDone N-1, auto_next=true)──▶ Playing(下一章,0)
Playing ──(TtsSentenceDone N-1, auto_next=false | 最后一章)──▶ Stopped
Playing/Paused ──(用户停止)──▶ Stopped
Playing ──(TtsFailed)──▶ 提示 + 保持/停止（容错：单句失败跳过，连续 >5 次停止并提示，docs/04 §9.4 规则3）
```
- 进度：`_dirty` 在每次句完成置真；`_saveProgressDebounced(locator)` 300ms 合并；`dispose`/返回手势/系统返回 → `_flushProgress()` 后 `Navigator.pop`。
- 进入：`initState` 只读设置/切句/定位，不调用 `saveProgress`（US-2）。
- 设置键：`listen.voice_id`/`listen.speed`/`listen.auto_next`；`listen.timer` 不建（定时关闭不做，01-req §1.2）。

### 影响
- `ListenPage` 状态字段：`_chunks/_index/_state/_settings/_chapterText/_error/_dirty/_debounceTimer`。
- 测试：fake `TtsEngine` 记录 `configure/speak/pause/resume/stop` 序列并可控发 `TtsSentenceDone(i)`；fake `LibraryBackend.saved` 断言 href/progression。

### 降级线（授权）
若 300ms 防抖导致退出瞬间丢最后一句（真机验证发现）：降级为**句完成即写**（去掉防抖，仅保留"退出强刷"），写盘频率上升但语义不变；US-14 的断言不依赖防抖窗口。

---

## 决策点 5：阅读页 → 听书页的入口接线与参数传递（R1-1）

**现状（已核实）**：`reader_page.dart:269-284` 的 `_openMore` 中"听书"项 `onTap` 只 `Navigator.pop`（`:277`）；`main.dart:19` 无 routes；`ReaderPage` 现有 `bookId/bookTitle/backend/translateBackend/pagedViewBuilder/initialPagedMode`。

### 备选
- **A（选）：`_openMore` 的听书项先 `Navigator.pop` 关闭弹层，再 `Navigator.push(MaterialPageRoute(→ ListenPage(...)))`，传 `bookId/bookTitle/当前 href/当前 progression/backend/ttsBackend/ttsEngine`；返回后 `_reloadProgress()` 重读进度**
  - 优点：与现有页面跳转方式一致（无全局路由）；参数显式、可注入 fake（US-1）；返回刷新保证 US-15。
  - 缺点：需在 `ReaderPage` 增加可选 `ttsBackend`/`ttsEngine` 构造参数（默认懒创建）。
- **B：全局路由/全局单例播放器（如 `go_router` + 常驻 `ListenController`）**
  - 缺点：`main.dart` 无 routes、工程未引入 go_router（`pubspec.yaml:22` 注释）；跨页常驻播放器属 P2 后台播放，超出本期范围。**拒绝**。
- **C：命名路由 `Navigator.pushNamed('/listen')`**
  - 缺点：需在 `main.dart` 注册 routes + 全局传参（`arguments` 弱类型，注入 fake 困难），为单页跳转引入全局路由面。**拒绝**。

### 选择与理由
选 **A**。最小改动、显式注入、返回刷新三点同时满足 US-1/US-2/US-15；跨页常驻/后台播放按 01-req 明确留待 P2 另立 REQ。

### 接口签名
```dart
// app/lib/pages/reader_page.dart（新增可选参数，向后兼容）
const ReaderPage({
  ...,
  this.ttsBackend,   // TtsBackend?；null → 点击听书时懒创建 RustTtsBackend()
  this.ttsEngine,    // TtsEngine?；null → 点击听书时懒创建 SystemTtsEngine()
});
// _openMore 听书项：
// Navigator.pop(context);                       // 关闭底部弹层
// Navigator.push(context, MaterialPageRoute(builder: (_) => ListenPage(
//   bookId, bookTitle, href: _hrefFor(view), progression: _chapterProgress,
//   backend: widget.backend, ttsBackend: _ttsBackend, ttsEngine: _ttsEngine)));
// await 返回后：_reloadProgress()（loadProgress → 章节索引 + _chapterProgress + _jumpToProgress）
```

### 影响
- `reader_page.dart`：`_openMore` 听书分支改为跳转；新增 `_openListen`/`_reloadProgress`；新增可选 tts 参数；顺手修 `:383-386` 复制（US-22，P1 可选）。
- `app/test/reader_page_test.dart:170-182`：既有"⋯更多 4 个占位项"用例更新为"听书项可跳转 `ListenPage`、其余三项仍占位"（US-1/US-25）。
- `app/lib/pages/library_page.dart`：无需改动（ReaderPage 默认懒创建）。

### 降级线（授权）
若返回后 `loadProgress` 读到旧值（写盘未落）：`_openListen` 的 `await Navigator.push(...)` 后先 `await Future<void>.delayed(Duration.zero)` 再 `_reloadProgress()`；仍不行为则由 ListenPage 在 pop 前 `await` 一次强刷（`_flushProgress` 返回 Future）。不改变"返回重读进度"的契约。

---

## 决策点 6：听书设置持久化（US-11 语速记忆；`listen.voice_id/speed/auto_next`）

**现状（已核实）**：`settings` 表存在（`core/src/store/mod.rs:286`），但**无通用读写桥接**：`api.rs` 无 `settings_get/settings_set`；`store/translation.rs` 的 `upsert_setting` 为私有、仅服务 Provider 配置；`Store` 无公开 `get_setting/set_setting`。`docs/04 §9.2` 规定听书设置入 `settings` 表。

### 备选
- **A（选）：新增**听书专用**类型化桥接 `tts_listen_settings_get() -> ListenSettingsView` / `tts_listen_settings_set(view)`；`Store` 增公开 `get_setting/set_setting`（infrastructure），`LibraryService` 转发（application），`TtsBackend.loadListenSettings/saveListenSettings` 调用**
  - 优点：一次往返、类型化、与 `docs/04 §9.2` 的三个键一一对应；US-11 可直接断言 `ListenSettingsData` 往返；不新增表/迁移。
  - 缺点：新增一对 FFI（需 FRB 再生成 + docs 同步）；不是通用设置通道。
- **B：实现 `docs/03 §4` 的通用 `settings_get/settings_set`（key-value 字符串）**
  - 优点：与架构文档 §4 的预留面一致、可复用。
  - 缺点：字符串化 API，`speed` 需在 Dart 解析、`auto_next` 需约定 `"1"/"0"`，US-11 的字段级断言更弱；且要定义"整包 Settings"与"单键"的取舍（`docs/03 §4` 原签名为 `settings_get()->Settings`/`settings_set(patch)`，实现整包超出本期）。**不作为主方案**（可作为后续 REQ 的通用化）。
- **C：`shared_preferences` 存听书设置**
  - 缺点：与 `docs/04 §9.2`（settings 表）不符；`shared_preferences` 当前被注释（`pubspec.yaml:24`），新增依赖；跨设备/备份语义弱。**拒绝**。
- **D：仅内存（重进听书恢复默认）**
  - 缺点：US-11"退出重进读回 X"不可达。**拒绝**。

### 选择与理由
选 **A**。范围最小、类型安全、与线框 10 的设置项一一对应；通用 `settings_get/set` 留作后续设置 REQ 的统一通道（本 ADR 记录，不实现）。

### 接口签名
```rust
// core/src/store/mod.rs（infrastructure）
impl Store {
    pub fn get_setting(&self, key: &str) -> Result<Option<String>>;
    pub fn set_setting(&mut self, key: &str, value: &str) -> Result<()>;
}
// core/src/api.rs（interface）
pub async fn tts_listen_settings_get() -> std::result::Result<ListenSettingsView, String>;
pub async fn tts_listen_settings_set(settings: ListenSettingsView) -> std::result::Result<(), String>;
// 键：listen.voice_id（字符串）、listen.speed（f32 字符串）、listen.auto_next（"1"/"0"）
// 缺省：voice_id="system_male"、speed=1.0、auto_next=true；speed 读回时 clamp [0.5,3.0]
```

### 影响
- `core/src/store/mod.rs`（infrastructure）新增两个方法；`core/src/library/mod.rs`（application）转发；`core/src/api.rs` 新增桥接；`app/lib/services/tts_backend.dart`/`rust_tts_backend.dart` 暴露 `loadListenSettings/saveListenSettings`；FRB 再生成。
- `docs/03 §4/§13`：需补 `tts_listen_settings_get/set`（文档同步归开发/交付阶段）。
- 测试：`tts_listen_settings_get` 往返（默认值 + 写后读回 + 非法 speed clamp）。

### 降级线（授权）
若 `Store` 直连 SQL 与 `TranslationRepo` 的私有 `upsert_setting` 重复引发 CRAP 告警：把 `upsert_setting` 上移为 `Store` 的 `set_setting` 并让 `TranslationRepo` 复用（同语义重构），由 developer 在 03 阶段按 CRAP 阈值处置。

---

## 关联裁定（次要决策，供 02-design/02-plan 引用）
1. **听书设置入口位置（解 US-3 与 US-13 的措辞冲突）**：US-3 要求控制条内"定时按钮/音色按钮"均为**占位禁用**，而 US-13 要求听书页存在"听书设置"入口。裁定：控制条按线框 09 保留 `⏱ 定时`（禁用）与 `🎙 音色`（禁用，显示当前系统音色）两个占位按钮；**听书设置入口 = ListenPage 顶部栏右侧设置图标（tooltip "听书设置"）**，点击打开线框 10 面板。两者互不冲突，US-3/US-13 均可断言。
2. **默认音色/语速**：默认 `system_male`、`1.0x`（线框 10 选中态）；系统缺男/女声时 `SystemTtsEngine` 回退默认系统音色，并在面板标注可用性（US-12 失败提示 + docs/02 §11.5）。
3. **`SentenceChunk.index`**：桥接新增字段，作为 `TtsSentenceDone(index)` 的唯一依据，使 seek/暂停后事件索引仍正确；不改 `docs/03 §13.2` 的 `speak(SentenceChunk)` 签名。
4. **桥接异步与参数适配**：`tts_segment`/`tts_locator_for_sentence`/`tts_sentence_index_at` 采用 **async**（取章文本有 IO，对齐 REQ-003 桥接先例）；函数名与 docs/03 §13.3 一致，`idx: usize → u32`、`loc: &Locator → LocatorView` 为桥接适配，docs 需同步一行。
5. **进入不写盘**：`ListenPage` 进入/初始化不调用 `saveProgress`（US-2）；仅在句完成/拖动松手/退出强刷时写（US-14/16/15）。
6. **`total_progression` 本期近似**：无全书权重，tts 的 `total_progression` 取章内 `progression`，仅展示用，不落库（`reading_progress` 只存 href+progression）。
7. **依赖边界**：仅启用 `flutter_tts`；`just_audio`/`audio_service` 保持注释（后台播放/媒体键 P2，01-req §1.2/§4）。
8. **复制修复**：`reader_page.dart:383-386` 空实现改为 `Clipboard.setData`（US-22，P1 可选，不阻塞 P0）。

## 影响汇总
- **Rust**：`core/src/tts/mod.rs`（文本入参实现）、`core/src/api.rs`（DTO + 5 async 桥接 + `chapter_text`）、`core/src/store/mod.rs`（setting 读写）、`core/src/library/mod.rs`（转发）；`Locator`/表/迁移零改动。
- **Dart**：`engines/tts_engine.dart`（DTO 对齐）、`engines/system_tts_engine.dart`（新）、`engines/paged_web_view.dart`（settings 工厂）、`services/tts_backend.dart`+`rust_tts_backend.dart`（新）、`pages/listen_page.dart`（重写）、`pages/reader_page.dart`（入口/返回刷新/复制）、`widgets/listen_*.dart`（新）；`pubspec.yaml` 启用 `flutter_tts`。
- **数据模型**：零新表、零迁移；`settings` 新增 `listen.voice_id/speed/auto_next`；`reading_progress` 复用。
- **回归面**：core 全量、Flutter widget（reader_page/reader_selection/translate_reader/library）、FFI 端到端、分页选区回传、CRAP/DDD 闸门。

## 闸门2 自评（ADR 部分）
- [x] **备选 ≥2 且给出理由**：6 个决策点均 ≥2 备选并给出选择理由与拒绝论证；1(a) 分析了两方案对 free function/测试/ddd-lint/docs §13.3 的影响；1(b) 含 DTO 字段、char 单位（UTF-16 半开区间）、progression 规则、`sentence_index_at` 边界、文本锚与 8 条切句规则；每点均有降级线。
- [x] **与既有约定一致**：Locator 结构零改动（只加 `LocatorView` DTO）；听读同进度（`reading_progress` 唯一事实源）；限界上下文（tts 仍属 Reading 的支撑模块，不新建领域表）；ddd-rules 零改动（domain 文本入参、interface 不碰生成物、services 转换）。
- [x] **原型权威**：决策点 2/3/4/5 与线框 09/10、`reader-ui-v2/04-selection.svg` 逐项对应（详见 02-design §5）；未自创布局（US-3/US-13 的入口冲突以关联裁定1 处置）。
- [ ] **未完全落定项**：`docs/03 §13.3`/`docs/04 §9.5` 的同步（async/`LocatorView`/`u32`/domain 文本入参）需在开发/交付阶段改文档，本阶段按纪律只产出 3 份产物，**标记为待同步风险**（非本阶段闸门项）。
