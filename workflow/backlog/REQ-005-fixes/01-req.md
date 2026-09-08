<!-- wf-meta: req=REQ-005-fixes | phase=requirements | agent=req-analyst | date=2026-09-08 | gate=passed -->
# REQ-005-fixes · 听书功能不可用 + 安卓原生选择菜单覆盖自定义工具条 —— 需求分析

## 1. 背景与目标

### 1.1 问题现象（用户原始诉求）

- **问题1 · 听书功能无法使用**：阅读器"⋯ 更多 → 听书"点击后无任何反应；即便进入听书页也朗读不出声。
- **问题2 · 选中文本弹出安卓原生选择菜单**：长按选中正文时，系统原生 `ActionMode`（复制/全选…）浮在
  Flutter 画面之上，覆盖 app 内的自定义选中工具条（划重点/笔记/翻译/查词/复制），形成"双菜单"。

### 1.2 成功标准与范围划界

**成功标准一句话**：在阅读器"⋯ 更多 → 听书"可进入听书页，系统 TTS（离线）从**当前阅读位置**逐句朗读
当前章节，播放/暂停/停止与语速调节可用，听读共用同一 `reading_progress`（进入/退出不改变阅读位置），
且分页模式长按不再弹出 Android 原生选择菜单、滚动模式仍只有自定义工具条。

**本期范围（orchestrator 划定，本 REQ 遵循）**：

- **P0（必须）**：
  1. 阅读器"⋯ 更多 → 听书"真正进入听书并朗读（问题1 根因 R1-1/R1-2）。
  2. 系统 TTS（`flutter_tts`，离线）朗读当前章节、从当前阅读位置起播、可播放/暂停/停止、语速可调
     （R1-3/R1-4）。
  3. Rust 句级切分 + 句↔Locator 映射实现并经 FFI 暴露（R1-5/R1-6/R1-7）。
  4. 听读同一进度（复用 `reading_progress`/`Locator`，不新增表）。
  5. 分页模式禁用 WebView 原生选择菜单、滚动模式回归守住"只有自定义工具条"（R2-1/R2-2）。
- **P1（本期尽量，可测）**：跟读当前句高亮（线框 09 基本形态）、章末自动连播开关。
- **明确不做（另立 REQ）**：多音色/在线 AI/Piper、定时关闭、后台播放与系统媒体键、点读（点句开读）、
  在线音色授权、笔记/划重点。这些在听书设置面板中按线框 10 呈现为**禁用/灰置占位**，不实现行为。

**相邻缺陷（列为影响面/风险，非本期强制验收）**：自定义工具条"复制"在
`app/lib/pages/reader_page.dart:383-386` 为空实现（注释"此处占位"）；`selection_toolbar.dart` 无显式
关闭/取消入口。建议顺手修复"复制"，但不阻塞本 REQ 交付（见 §4 说明与 US-22 标注）。

### 1.3 根因分析 · 问题1（听书无法使用）—— 全链路均未实现

| 编号 | 根因 | 证据（file:line，已逐条核对） |
|---|---|---|
| **R1-1** | **入口空转**：`_openMore` 弹层"听书"项 `onTap` 只 `Navigator.pop`，从不 push `ListenPage`；全仓库 `ListenPage` 无任何引用/路由（`main.dart` 仅 `home: LibraryPage()`，无 routes）。 | `app/lib/pages/reader_page.dart:269-284`（听书项在 `:277`）；`app/lib/pages/listen_page.dart:5-6` 定义；`app/lib/main.dart:19` 无路由 |
| **R1-2** | **听书页是静态占位**：`ListenPage` 为 `StatelessWidget`，body 仅一行占位文本，无播放器/引擎/控制条/跟读/设置。 | `app/lib/pages/listen_page.dart:5-15`（`:12` 占位文本） |
| **R1-3** | **无 TTS 引擎实现**：`tts_engine.dart` 只有 `abstract class TtsEngine` 与数据类型；注释提到的 `SystemTtsEngine` 不存在，无任何 `flutter_tts` 调用。 | `app/lib/engines/tts_engine.dart:4`（注释）、`:9-22`（抽象接口） |
| **R1-4** | **依赖未启用**：`flutter_tts` / `just_audio` / `audio_service` 全部被注释，`pubspec.lock` 无这些包。 | `app/pubspec.yaml:26-29` |
| **R1-5** | **Rust 切句/映射未实现**：`segment` / `locator_for_sentence` / `sentence_index_at` 均 `Err(TtsError::NotImplemented)`；单测仍断言 `is_err()`。 | `core/src/tts/mod.rs:62-65`、`:68-75`、`:78-85`、`:99-103` |
| **R1-6** | **无 FFI 桥接**：`api.rs` 无 `tts_segment`/`tts_locator_for_sentence`/`tts_sentence_index_at`（docs/03 §13.3 已定义契约）；`app/lib/src/rust/` 生成物中无 tts 绑定。 | `core/src/api.rs` 全文无 `tts_`；`app/lib/src/rust/api.dart` / `frb_generated.dart` 无 tts |
| **R1-7** | **契约不一致（实现时必须对齐）**：Dart `SentenceChunk` 字段 `text/charStart/charEnd/totalProgression`；Rust `SentenceChunk` 字段 `text/char_range/locator`，且 `locator` 为 `Locator`（含 `Rect`/`TextAnchor`，当前未作为 FRB 桥接类型出现）。 | Dart：`app/lib/engines/tts_engine.dart:25-37`；Rust：`core/src/tts/mod.rs:10-17`；`core/src/types.rs:18-34` |

补充核对：docs/03 §13.2 的 `TtsEngine` 接口与 `tts_engine.dart:9-22` 一致（configure/speak/pause/resume/
stop/events）；但 `TtsEvent`（`tts_engine.dart:40-51`）只有 `TtsSentenceDone`/`TtsFailed`，缺
`Interrupted`（移动端音频焦点丢失属 P2，本期可不补，见 §3/§5）。

### 1.4 根因分析 · 问题2（原生选择菜单覆盖自定义工具条）

| 编号 | 根因 | 证据（file:line，已逐条核对） |
|---|---|---|
| **R2-1** | **滚动模式已抑制（回归守住，非当前缺陷）**：`SelectionArea(contextMenuBuilder: ... => const SizedBox.shrink())` 已禁用 Flutter/Android 原生上下文菜单。 | `app/lib/pages/reader_page.dart:533-537`；orchestrator Android 平台 widget 探针实测长按后 `AdaptiveTextSelectionToolbar` 数量 = 0、`ReaderSelectionToolbar` = 1 |
| **R2-2** | **分页模式未抑制（真正剩余根因）**：`InAppWebView.initialSettings` 未设 `disableContextMenu: true`，也无 `onContextMenu` 处理 → Android WebView 长按选文弹出系统 `ActionMode`；而 JS `selectionchange` 仍回传选区，令自定义工具条照常出现，形成"双菜单"。 | `app/lib/engines/paged_web_view.dart:149-152`（`initialSettings` 仅 `useShouldInterceptRequest`/`transparentBackground`）、`:215-223`（`selectionchange` 回传）。插件默认 `false`：`flutter_inappwebview_platform_interface-1.3.0+1/.../in_app_webview_settings.dart:1684`、`:1997`；Android 实现 `flutter_inappwebview_android-1.1.3/.../InAppWebView.java:1608`（`disableContextMenu` 为真时直接 `return actionMode`，不展示浮动菜单） |
| **R2-3** | **相邻缺陷（非本期强制）**：工具条"复制"动作空实现，点击不写剪贴板。 | `app/lib/pages/reader_page.dart:377-392`（复制分支 `:383-386`） |

### 1.5 原型权威性

`docs/wireframes/09-listen-player.svg`（听书跟读）、`docs/wireframes/10-listen-settings.svg`（听书设置）、
`docs/wireframes/reader-ui-v2/04-selection.svg`（选中浮动工具条）+ `docs/wireframes/README.md` 为本 REQ
UI 的**权威规范**；§2 每条 UI 验收均标注原型图映射，实现阶段禁止对布局/交互自由发挥（闸门3 由
orchestrator 逐屏核对，deviation=0）。线框 09/10 中的 P2 项（AI 音色/Piper/声音克隆/定时关闭/后台播放）
按 §1.2 以**禁用占位**呈现，不实现行为。

---

## 2. 用户故事与验收标准（Given/When/Then，必须可测；每条标注根因/原型图映射）

### 故事 1：听书入口与听书页 —— 作为王叔，我想要在阅读页一键切到听书并继续听，以便通勤时"听"书

- **US-1 听书入口真正进入听书页（R1-1，P0）**
  - Given `ReaderPage(bookId:'b1', backend: FakeBackend())` 已加载，工具栏已呼出
  - When 点击"更多"（`find.byTooltip('更多')`）→ 在弹层点击"听书"（`find.text('听书')`）
  - Then `Navigator` push 出 `ListenPage`：`find.byType(ListenPage)` 为 1（`findsOneWidget`）；原"更多"
    底部弹层已关闭（`find.text('导出')` 为 `findsNothing`）；**不得**只 pop 回沉浸态。
  - Given `ListenPage` 需要依赖（`bookId`/`href`/`progression`/`backend`/`ttsEngine`）When 由阅读页构造
    Then 测试可注入 fake `TtsEngine`（构造参数存在，`ListenPage` 不是无参 `const ListenPage()` 占位）。

- **US-2 从当前阅读位置起播、进入听书不改变阅读位置（R1-1/R1-5/R1-6，LISTEN-01/02，P0）**
  - Given 阅读页当前章节 `chapter_0002.xhtml`、`_chapterProgress = 0.42`（fake `loadProgress` 返回同值）
  - When 进入 `ListenPage`
  - Then 首句 `ttsEngine.speak` 收到的 `SentenceChunk` 对应"包含 `progression≈0.42` 的句子"（fake 引擎
    记录调用，断言索引等于 `sentence_index_at(href, locator)` 的结果）；进入过程**未调用**
    `backend.saveProgress`（阅读位置不变）。
  - Given 从听书页返回阅读页 When 阅读页重新读取进度 Then 章节与 `progression` 与进入前一致（fake
    `loadProgress` 返回值不变）。

- **US-3 听书页布局符合线框 09（R1-2，线框 `09-listen-player.svg`，P0）**
  - Given `ListenPage` 已进入
  - Then 页面自上而下含：正文区（当前朗读句带高亮，US-17）、底部听书控制条，控制条内**恰好含**：
    章节名文本（如"第三章 · 起风了"）、上一句（`⏮`）、播放/暂停（`⏸`/`▶`）、下一句（`⏭`）、
    句级进度条（`Slider`）、语速文本（如"1.0x"）、定时按钮（占位，禁用）、音色按钮（占位，禁用）
    （按线框 09 用 `find.byType`/`find.text` 断言各控件存在；`ReaderSelectionToolbar` 不在听书页出现）。

### 故事 2：Rust 核心句级切分与句↔Locator 映射 —— 作为架构，我想要"脑子"在 Rust，以便听读位置统一

- **US-4 `tts::segment` 中文切句（R1-5，P0）**
  - Given 章文本（含中文标点 `。！？；…`、引号/书名号、段落换行、英文句点、连续省略号）
  - When 调用 `segment(book_id, href)`（或架构确定的等价签名，见 §5 风险7）
  - Then 返回 `Ok(Vec<SentenceChunk>)`：句子数 > 0；每句 `text` 非空且已 trim；相邻 `char_range` 在章
    文本中**连续覆盖且不重叠**（`prev.1 == next.0`）；引号/书名号成对保留在句内（断言具体切句结果）；
    空文本返回 `Ok(vec![])`（不返回 `NotImplemented`、不 panic）。
  - Given 段落边界 When 切分 Then 不跨段落合并（段落结尾句与下一段首句分为两块）。

- **US-5 `tts::locator_for_sentence` 句 → Locator（R1-5，P0）**
  - Given 已 `segment` 得到 N 句 When `locator_for_sentence(book_id, href, i)`（`0 ≤ i < N`）
  - Then 返回 `Ok(Locator)`：`locator.book_id == book_id`、`locator.href == href`、
    `locator.progression` 在 `[0.0, 1.0]` 且随 `i` 单调不减、`locator.text`（文本锚）的 snippet 与
    第 `i` 句 `text` 前缀一致。
  - Given `i ≥ N` 或 `href` 不存在 When 调用 Then 返回 `Err`（明确错误，不 panic）。

- **US-6 `tts::sentence_index_at` Locator → 句索引（R1-5，P0）**
  - Given 对每句 `i` 先取 `locator_for_sentence` When 再调 `sentence_index_at(book_id, href, locator)`
    Then 对全部 `i` 满足 `sentence_index_at(locator_for_sentence(i)) == i`（双向映射往返一致）。
  - Given 章首位置 When 查询 Then 返回 `0`；Given 章末位置 When 查询 Then 返回 `N-1`（或按架构定义
    的明确边界值，测试断言该定义）。
  - Given `href` 不匹配或 locator 越界 When 查询 Then 返回 `Err`（不 panic）。

- **US-7 FFI 桥接三函数 + 契约对齐（R1-6/R1-7，P0）**
  - Given 运行 FRB codegen 后 When 检查桥接面
  - Then `core/src/api.rs` 存在 `tts_segment`/`tts_locator_for_sentence`/`tts_sentence_index_at` 三个函数
    （命名与 docs/03 §13.3 对齐，`Result<…, String>` 错误映射）；`app/lib/src/rust/` 生成物含对应 Dart
    函数（如 `ttsSegment(...)`），代码生成后无未解决 diff。
  - Given 桥接 DTO When 对齐字段 Then Dart `SentenceChunk` 与 Rust/桥接 DTO 字段**一一对应**
    （`text`、`charStart`/`charEnd`（或 `charRange`）、`locator`/`progression`；具体命名由架构阶段
    在 02-adr 落定，测试断言字段名与类型与 ADR 一致）；`Locator` 经桥接 DTO 传递（不直接暴露含
    `Rect` 的领域类型，见 §5 风险2）。
  - Given 测试语料书（含两章）When 经 FFI 调 `tts_segment(bookId, 'chapter_0001.xhtml')`
    Then 返回非空句列表；`tts_locator_for_sentence` 与 `tts_sentence_index_at` 往返一致
    （`rust_bridge_test`/新增 `tts_ffi_test` 可断言）。

- **US-8 切句性能预算（R1-5，P0，可测基准）**
  - Given 10 万字中文章文本 When `segment` 单次调用 Then 耗时 **< 50ms**（docs/02 §11.4；CI 用宽松上限
    ≤ 200ms 防回归，以基准/计时测试记录为准）。

### 故事 3：系统 TTS 引擎与播放控制 —— 作为王叔，我想要离线朗读与基础控制，以便没网也能听

- **US-9 `SystemTtsEngine` 实现 + `flutter_tts` 依赖启用（R1-3/R1-4，P0）**
  - Given 查看 `app/lib/engines/tts_engine.dart` When 检查实现 Then 存在 `class SystemTtsEngine implements
    TtsEngine`（或架构确定的等价具体类），内部封装 `flutter_tts`。
  - Given `app/pubspec.yaml` When 检查依赖 Then `flutter_tts` 在 `dependencies` 中**未被注释**且
    `pubspec.lock` 含该包；`flutter pub get` 成功。
  - Given 注入平台通道 mock（或 fake `FlutterTts`）When 调 `configure(voiceId, speed)`
    Then 触发 `setSpeechRate`/`setVoice`（断言调用与参数）；When `speak(chunk)` Then 触发
    `flutterTts.speak(chunk.text)`（断言朗读文本 == chunk.text）。

- **US-10 播放/暂停/停止（R1-3，LISTEN-04，P0）**
  - Given `ListenPage` 已开始朗读（状态 Playing）When 点击暂停按钮 Then 调 `ttsEngine.pause()`，UI 图标
    切为播放态（可断言 `find.byIcon`/语义），状态 `Paused`。
  - Given Paused When 点击播放 Then 调 `ttsEngine.resume()`，状态回 `Playing`。
  - Given Playing/Paused When 点击停止 Then 调 `ttsEngine.stop()`，状态 `Stopped`，句级进度停止推进
    （fake 引擎记录调用序列，断言 `pause/resume/stop` 各被调用）。

- **US-11 语速可调（0.5–3.0x）实时生效 + 记忆（R1-3，LISTEN-05，线框 10，P0）**
  - Given 听书设置面板打开、语速滑块当前 1.0x When 拖动/点击调整语速 Then 调
    `ttsEngine.configure(speed: 新值)`，滑块旁文本更新为新值（如"1.5x"），范围限制在 `[0.5, 3.0]`。
  - Given 调整语速为 X When 退出并重新进入听书 Then 语速读回 X（写入 `settings` 键 `listen.speed`，
    断言持久化通路被调用/读回）。

- **US-12 完全离线朗读（R1-3/R1-4，LISTEN-09，P0）**
  - Given 本期仅接入系统 TTS（无在线 Provider/Piper）When 检查依赖与代码 Then 未新增任何网络依赖/
    网络调用（无 HTTP 客户端 import，`just_audio`/`audio_service` 保持注释，见 §4）。
  - Given 设备无网络（或测试断言无网络调用）When 播放 Then 朗读链路仍走系统 TTS 并出声（集成/真机
    验收项；widget 层以"无网络调用"结构性断言兜底）。
  - Given 系统缺目标语言语音 When 朗读失败 Then 捕获 `TtsFailed` 事件并在听书页给出可读提示
    （不崩溃），提示文案含"语音/安装"语义。

- **US-13 听书设置面板符合线框 10（R1-3，线框 `10-listen-settings.svg`，P0 语速 / P1 连播）**
  - Given 听书页点击"听书设置"入口 When 面板打开 Then 面板含：音色分组（系统男声/系统女声可选；
    AI 音色/Piper/声音克隆**禁用灰置**并显示线框文案"需网络（P2）"/"下载 52MB（P2）"/"评估中"）、
    语速滑块（0.5x–3.0x，US-11）、章末连播开关（US-18，P1）、定时关闭分组与后台播放开关
    **禁用灰置**（明确不做）。
  - Given 面板中任一 P2 控件 When 尝试点击 Then 无状态变更、不崩溃（断言控件 `onChanged == null`/
    `enabled == false` 或等价禁用态）。

### 故事 4：听读同一进度 —— 作为王叔，我想要听读到哪读到哪、无缝切换

- **US-14 句完成写入 `reading_progress`（R1-5，LISTEN-02，P0）**
  - Given 听书播放中，fake 引擎在句 `i` 完成时发出 `TtsSentenceDone(i)`
  - When `ListenPage` 处理该事件
  - Then 调用 `backend.saveProgress(bookId, href, progression)`，其中 `href` 为章资源路径
    （`chapter_%04d.xhtml` 约定，与 `reader_page.dart:164`/`:605-608` 一致）、`progression` 等于该句
    Locator 的章内进度；断言 fake `backend.saved` 的 `href`/`progression` 与句 `i` 的映射一致。
  - Given 连续多句完成 When 事件推进 Then 每次句完成都更新进度（300ms 防抖语义沿用既有
    `_saveProgress` 节流；退出听书时强制刷一次）。

- **US-15 退出听书/重开位置一致（R1-1/R1-5，LISTEN-01/02，P0）**
  - Given 听到第 `k` 句后退出听书 When 返回阅读页 Then 阅读页定位到同一章同一 `progression`
    （`loadProgress` 返回听书写入的值，断言章节索引与 `_chapterProgress`）。
  - Given 应用重启 When 打开同一本书 Then 从上次听读位置继续（`loadProgress` 通路不变，断言恢复
    到该章）。

- **US-16 听书进度条拖动 = 移动阅读进度（R1-5，LISTEN-02，P0）**
  - Given 听书页句级进度条 When 拖动到句 `j` 位置并松手 Then `ttsEngine` 从句 `j` 开始朗读
    （`speak` 收到第 `j` 句）、并调用 `backend.saveProgress` 写入句 `j` 的 Locator。
  - Given 拖动过程 When 松手前 Then 不触发越界句索引（`0 ≤ j < N`），不崩溃。

### 故事 5：P1 跟读与连播 —— 作为王叔，我想要看到读到哪句并自动接下一章

- **US-17 跟读当前句高亮（R1-3/R1-5，LISTEN-08，线框 09，P1）**
  - Given 听书页播放中，当前句为 `chunk.text` When 渲染正文
  - Then 正文中 `chunk.text` 对应的字符区间以高亮样式呈现（可断言：暴露 `ListenFollowHighlight`
    组件或 `RichText` span 的背景色/键，断言高亮子串 == `chunk.text`）。
  - Given fake 引擎发出 `TtsSentenceDone(i)` When 推进到句 `i+1` Then 高亮区间同步切换到句 `i+1`
    （断言旧句不再高亮、新句高亮）。

- **US-18 章末自动连播开关（R1-3，LISTEN-03，P1）**
  - Given 连播开关默认开启 When 当前章最后一句完成（fake 引擎发 `TtsSentenceDone(N-1)`）
    Then 自动加载下一章（`backend.openBook`/`chapterHtml` 或等价），并从下一章句 `0` 开始 `speak`
    （断言 `href` 变为下一章、`speak` 首句为新章第 0 句）。
  - Given 连播开关关闭 When 当前章最后一句完成 Then **不**加载下一章、状态转 `Stopped`。
  - Given 最后一章 When 播完 Then 停止（不越界、不崩溃）。

### 故事 6：问题2 · 原生选择菜单 —— 作为所有用户，我想要只有自定义工具条，以便操作不被覆盖

- **US-19 分页模式禁用 WebView 原生选择菜单（R2-2，P0）**
  - Given `PagedWebView` 构建 When 检查传给 `InAppWebView` 的 `initialSettings`
    Then `InAppWebViewSettings.disableContextMenu == true`（配置断言；为此需提供可测出口——如把
    `initialSettings` 提取为可测工厂/常量，或允许测试注入 settings；见 §3）。
  - Given Android 真机/集成环境 When 长按选中 WebView 内文本 Then **不出现**系统原生 `ActionMode`
    浮动菜单；`ReaderSelectionToolbar` 正常出现（`find.byType(ReaderSelectionToolbar)` 为 1）。
  - Given 分页模式禁用菜单 When 用户长按 Then 文本仍可被选中（选柄可用，见 US-20），禁用的是"菜单"
    而非"选区"。

- **US-20 禁用菜单后选区回传仍可用（R2-2，P0）**
  - Given `disableContextMenu == true`、JS `selectionchange` 监听（`paged_web_view.dart:215-223`）保留
  - When 选区非空触发 `callHandler('selectedText', txt)`（测试直接调用 `onSelectedText` 回调或经
    fake 分页构建器触发）
  - Then `ReaderPage` 的 `_selectedText` 更新、`ReaderSelectionToolbar` 出现（`findsOneWidget`），
    五入口"划重点/笔记/翻译/查词/复制"齐全；翻译/查词入口行为与 REQ-003 一致（回归，见 US-25）。
  - Given 分页模式长按选区 When 自定义工具条出现 Then 不出现第二套菜单（无 `AdaptiveTextSelectionToolbar`/
    原生 ActionMode；集成/真机断言）。

- **US-21 滚动模式回归守住"只有自定义工具条"（R2-1，P0）**
  - Given 滚动模式、正文含可选中文本 When 长按选中 Then
    `find.byType(AdaptiveTextSelectionToolbar)` 为 `findsNothing`（Android 平台 widget 探针）、
    `find.byType(ReaderSelectionToolbar)` 为 `findsOneWidget`。
  - Given 源码 When 检查 `SelectionArea.contextMenuBuilder` Then 仍返回 `const SizedBox.shrink()`
    （`reader_page.dart:533-537` 不被本 REQ 回退）。

- **US-22 工具条"复制"写系统剪贴板（R2-3，P1 · 可选，见 §4 说明）**
  - Given 选中文本"很久以前" When 点击工具条"复制" Then 系统剪贴板内容等于选中文本
    （`Clipboard.getData(Clipboard.kTextPlain)` 返回"很久以前"）。
  - 说明：此为相邻缺陷，orchestrator 未强制本期修；本 REQ 将其列为 **P1 可选**，若不实现则保持现状且
    不影响其余 P0 验收（§4 记录）。

### 故事 7：测试与回归 —— 作为发布者，我想要新能力可测、旧能力不破

- **US-23 widget 测试覆盖关键交互（P0）**
  - Given 测试注入 fake `LibraryBackend`、fake `TtsEngine`、fake `pagedViewBuilder`（既有注入点）
  - Then 新增/更新测试覆盖并断言：① 更多→听书进入 `ListenPage`（US-1）；② 播放/暂停/停止调用引擎
    （US-10）；③ 语速调节调用 `configure`（US-11）；④ 句完成写 `saveProgress`（US-14）；⑤ 退出/重开
    位置一致（US-15）；⑥ 跟读高亮推进（US-17）；⑦ 连播开关（US-18）；⑧ 分页 `disableContextMenu ==
    true` 配置断言（US-19）；⑨ 滚动模式只有自定义工具条（US-21）。
  - Given 测试运行 When 执行 `flutter test` Then 全部通过。

- **US-24 core 测试更新（R1-5，P0）**
  - Given `core/src/tts/mod.rs:99-103` 的 `not_implemented_yet` 断言 `segment(...).is_err()` When 本 REQ
    实现后 Then 该测试必须被删除/改写为断言成功路径（否则与实现冲突）；新增 US-4/5/6/8 用例。
  - Given `cargo test -p reader_core` When 运行 Then 全绿；`core/tests/` 集成测试（若有 tts 用例）同步
    更新。

- **US-25 既有功能零回归（P0）**
  - Given REQ-001 阅读进度/分页、REQ-003 翻译查词、REQ-004 阅读器交互既有测试
  - When 执行全量测试 Then `reader_page_test.dart`（其中"更多弹层 4 占位项"用例需更新为"听书可跳转"）、
    `reader_selection_test.dart`、`translate_reader_test.dart`、`library_page_test.dart` 等均通过；
    阅读进度 `saveProgress`/`loadProgress` 语义不变；分页模式翻译/查词入口行为不变。
  - Given 滚动模式 `SelectionArea` 选区行为 When 回归 Then 与 REQ-004 一致（US-21）。

---

## 3. 影响面分析（必须非空）

- **问题1 · R1-1 入口（`app/lib/pages/reader_page.dart:269-284`）**：`_openMore` 的"听书"项由"仅 pop"
  改为"pop 后 push `ListenPage`"，并传入 `bookId`/`bookTitle`/当前 `href`/`progression`/`backend`/
  `translateBackend`（可选）/`ttsEngine`；需处理弹层关闭与路由 push 的时序（先 `Navigator.pop` 再
  `Navigator.push`）。
- **问题1 · R1-2 听书页（`app/lib/pages/listen_page.dart:5-15`）**：`StatelessWidget` → `StatefulWidget`；
  接入引擎编排、播放控制条（线框 09）、跟读高亮、听书设置入口/面板（线框 10）、句级进度条；状态机按
  docs/04 §9.3（Idle/Playing/Paused/Stopped）。
- **问题1 · R1-3 TTS 引擎（`app/lib/engines/tts_engine.dart:9-52`）**：新增 `SystemTtsEngine`（封装
  `flutter_tts`）；`SentenceChunk` 与桥接 DTO 对齐（R1-7）；`TtsEvent` 建议补 `Interrupted`（P2，本期
  可留）；`TtsEngine` 接口本身保持 docs/03 §13.2 契约。**分层约束**：`app/lib/engines` 属 interface 层
  （`ddd-rules.toml:12`），`forbid_imports` 禁止直接 import `package:reader_app/src/rust/`（`:16`）→
  引擎/页面只能经 `services/` 拿 DTO；需新增 `services/tts_backend.dart`（薄封装转发 FFI）。
- **问题1 · R1-4 依赖（`app/pubspec.yaml:26-29`）**：启用 `flutter_tts: ^4`（P0）；`just_audio`/
  `audio_service` 对应后台播放/系统媒体键（明确不做）→ **保持注释**，避免无谓体积与权限；`pubspec.lock`
  更新。
- **问题1 · R1-5 Rust 核心（`core/src/tts/mod.rs:62-85`）**：实现 `segment`/`locator_for_sentence`/
  `sentence_index_at`；改写 `:99-103` 测试；docs/04 §9.1 `SentenceChunk` 类型沿用。
  **DDD 关键约束**：`core/src/tts` 属 **domain 层**（`ddd-rules.toml:26-35`），`forbid_internal` 禁止
  `crate::store`/`crate::api`/`crate::library` → 现有 `segment(book_id, href)` 签名无法直接读章节文本；
  需架构阶段二选一：(a) domain 内定义 `ChapterTextSource` trait，由 infrastructure 实现并在装配层注入
  （对齐 REQ-003 `TranslationCacheRepository` 先例）；(b) 改签名传入章文本，桥接层由 `api.rs` 从
  `LibraryService` 取文本后调用。决策需同步 docs/03 §13.3 契约与测试。
- **问题1 · R1-6 FFI 桥接（`core/src/api.rs` + `app/lib/src/rust/*`）**：新增 `tts_segment`/
  `tts_locator_for_sentence`/`tts_sentence_index_at`（docs/03 §13.3）；FRB 2.13 codegen 再生成
  `app/lib/src/rust/api.dart`/`frb_generated*.dart`；同步 docs/03 §4/§13 契约说明。同步/异步由架构定
  （切句 <50ms，可同步；若取文本走 IO 则建议 async）。
- **问题1 · R1-7 契约不一致**：Dart `SentenceChunk`（`tts_engine.dart:25-37`）与 Rust `SentenceChunk`
  （`core/src/tts/mod.rs:10-17`）字段不同；`Locator`（`core/src/types.rs:18-34`，含 `Rect`/`TextAnchor`）
  当前未作为 FRB 桥接类型暴露 → 需定义桥接 DTO（如 `SentenceChunkView` + `LocatorView`），保证
  `progression`/`href` 可回传；架构阶段在 02-adr 落定命名并让两侧字段一一对应。
- **问题1 · 听读进度 / Locator（数据模型，预期零表结构变更）**：复用 `reading_progress`
  （`core/src/store/mod.rs:73-95`、`api.rs:191-205` 的 `progress_save`/`progress_get`），不新增表；
  `settings` 新增键 `listen.voice_id`/`listen.speed`/`listen.auto_next`（docs/04 §9.2；`listen.timer`
  因定时关闭不做而本期不建）。
- **问题1 · `LibraryBackend` / services（`app/lib/services/library_backend.dart`）**：听书需要"按句
  Locator 存进度"（已有 `saveProgress(bookId, href, progression)` 可复用）与"取章文本/章 HTML"（已有
  `openBook`/`chapterHtml`）；是否需要新增 `TtsBackend` 抽象（segment/locator 转发）由架构定；测试需
  新增 `fake_tts_engine.dart` 与 `fake_tts_backend.dart`（若新增接口）。
- **问题2 · R2-2 分页模式（`app/lib/engines/paged_web_view.dart:149-152`）**：`initialSettings` 增加
  `disableContextMenu: true`；保留 `:215-223` 的 `selectionchange` 回传；为满足可测性，建议把
  `initialSettings` 提取为可测工厂/常量或允许注入（widget 测试断言 `disableContextMenu == true`）。
  回归面：Android 插件行为（`flutter_inappwebview_android-1.1.3/.../InAppWebView.java:1608`）确认
  禁用菜单不影响选区/选柄；若禁用后选区失效，需降级为自定义 JS 菜单（记 ADR，见 §5 风险5）。
- **问题2 · R2-1 滚动模式（`app/lib/pages/reader_page.dart:533-537`）**：本 REQ **不改**该实现，但需以
  测试守住（US-21），防止后续改动回退。
- **问题2 · R2-3 相邻缺陷（`app/lib/pages/reader_page.dart:383-386`）**：复制空实现（P1 可选）；
  `selection_toolbar.dart` 无显式关闭入口（沿用点击正文外部关闭，REQ-004 已有行为，非本 REQ）。
- **测试面**：新增 `app/test/listen_page_test.dart`、`app/test/tts_engine_test.dart`、
  `app/test/fake_tts_engine.dart`；更新 `app/test/reader_page_test.dart`（"更多"用例）；
  `reader_selection_test.dart`/`translate_reader_test.dart` 回归；core `tts/mod.rs` 单测 +
  `app/test/rust_bridge_test.dart` 或新增 `tts_ffi_test.dart`；`integration_test/screenshots_test.dart`
  可增听书页/设置页截图（可选）。
- **回归面（非空）**：core 全量测试（library/进度/locator/dict/search 零行为变化确认）；Flutter 既有
  widget 测试（reader_page/reader_selection/translate_reader/library/settings）；FFI 端到端（打开书/
  进度/新 tts 三函数）；分页 WebView 渲染与选区回传；workflow 闸门（CRAP/DDD/变异）；`ddd-rules.toml`
  无需修改但新增文件须过 ddd-lint（interface 层禁 import 生成物）。

---

## 4. 依赖与优先级

| 项 | 内容 | 依赖/前置 | 优先级 |
|---|---|---|---|
| 入口跳转 | `_openMore` → `ListenPage` | REQ-004 既有"⋯更多"弹层（`reader_page.dart:269-284`） | P0 |
| Rust 切句/映射 | `tts/mod.rs` 三函数实现 | docs/04 §9、章文本获取方案（§3 DDD 约束） | P0 |
| FFI 桥接 | `api.rs` 三函数 + FRB codegen | `flutter_rust_bridge: 2.13.0`（`pubspec.yaml:14`）、codegen 工具 | P0 |
| 系统 TTS | `SystemTtsEngine` + `flutter_tts` | `flutter_tts` 包、平台系统语音 | P0 |
| 播放控制 | 播放/暂停/停止/语速 | `TtsEngine` 接口（docs/03 §13.2） | P0 |
| 听读同进度 | 复用 `reading_progress`/`Locator` | REQ-001 进度通路（`progress_save/get`、`chapter_%04d.xhtml` 约定） | P0 |
| 听书页/设置 UI | 线框 09/10 | REQ-004 阅读器页与工具条、REQ-003 选中/翻译/查词（复用不重做） | P0 |
| 分页禁原生菜单 | `disableContextMenu: true` | `flutter_inappwebview ^6.1.5`（`pubspec.yaml:18`） | P0 |
| 跟读高亮 | 线框 09 当前句高亮 | Rust `char_range` + 句完成事件 | P1 |
| 章末连播 | `listen.auto_next` 开关 | 多章 `segment`/加载下一章 | P1 |
| 复制修复 | `Clipboard.setData` | 无 | P1（可选；orchestrator 未强制，见 §3 R2-3） |
| 多音色/在线 AI/Piper | — | — | 不做（另立 REQ，线框 10 禁用占位） |
| 定时关闭/后台播放/媒体键 | — | — | 不做（另立 REQ，线框 10 禁用占位；`just_audio`/`audio_service` 保持注释） |
| 点读（点句开读） | — | — | 不做（LISTEN-08 后半，另立 REQ） |
| 笔记/划重点 | — | — | 不做（NOTE 系列，另立 REQ） |

- **与既有 REQ 关系**：REQ-001 提供进度/分页渲染/`chapterHtml`；REQ-003 提供选中→工具条→翻译/查词
  通路（本 REQ 只消费，分页选区回传机制不改）；REQ-004 提供"⋯更多"入口与沉浸态工具条（本 REQ 把听书
  项从占位改为真跳转，并在"更多弹层 4 项"既有测试上更新预期）。三者能力均**复用不重做**。
- **优先级说明**：本 REQ 为 **P0 修复**（用户明确反馈两个功能不可用）；P1（跟读高亮/连播）在 P0 全绿
  后实现；US-22 复制为 P1 可选，若排期紧张可不做且不影响 P0 交付。

---

## 5. 风险

1. **平台 TTS 可用性差异（高）**：Windows 中文依赖系统语音包、Linux speech-dispatcher 音质/可用性
   差异、Android 部分机型缺中文 TTS 引擎 → 可能"接了引擎仍不出声"。缓解：US-12 捕获失败并给出
   "语音/安装"引导提示；听书设置面板按线框 10 呈现系统音色与可用性标注；架构阶段明确各平台检测与
   降级（对齐 LISTEN-09、docs/02 §11.5）。
2. **FFI 再生成与契约不一致（高）**：`SentenceChunk`/`Locator` 两侧字段不一致，`Locator` 含 `Rect`
   /`TextAnchor` 不适合直接桥接 → codegen 失败或运行时字段错位。缓解：02-adr 定义桥接 DTO（`LocatorView`/
   `SentenceChunkView`）并让 Dart/Rust 字段一一对应；codegen 后检查 diff 干净；US-7 加 FFI 往返测试。
3. **切句边界（中-高）**：中文标点/引号书名号/省略号/中英混排/换行可能导致切句错误或 `char_range`
   与高亮错位。缓解：US-4 用明确语料断言句数、边界、引号完整与区间连续；`char_range` 与 Locator
   `progression` 一致性纳入测试；架构阶段落定切句规则（docs/04 领域规则2）。
4. **听读进度一致性（中）**：句完成写盘节流（300ms）可能导致退出瞬间丢最后一句进度；分页/滚动
   progression 语义差异可能使听读互切跳变。缓解：退出听书强制刷进度（US-14）；统一以 Locator 的
   `href + progression` 为唯一事实源（docs/04 §9.4 规则1）；US-15 断言退出/重开位置一致。
5. **禁用 WebView 菜单后选区回传是否仍可用（中-高）**：`disableContextMenu: true` 在 Android 侧
   直接 `return actionMode`（`InAppWebView.java:1608`），理论上只隐藏菜单、保留选区，但不同 WebView
   版本行为可能有差异，极端情况下长按选柄/ActionMode 生命周期受影响 → 选区回传（`selectionchange`）
   失效。缓解：US-19/US-20 同时断言"菜单不出现"与"选区回传仍生效"；Android 真机/集成测试验证；若
   确证选区失效，降级为自定义 JS 长按菜单并记 ADR（不退回原生菜单）。
6. **真机验证缺失（中）**：widget 测试无法覆盖真实系统 TTS 出声、Android 原生 ActionMode、WebView
   选区。缓解：widget 层用 fake 引擎 + 配置断言兜底；交付前提供 Android 真机手工验收清单（长按分页
   无原生菜单、听书出声、语速生效、退出续读）；CI 若无法跑 Android 真机则在 04-coverage/05-delivery
   明确记录未覆盖项。
7. **DDD 分层约束（中）**：`core/src/tts` 属 domain，禁 `crate::store`/`crate::library`，现有
   `segment(book_id, href)` 无文本来源 → 直接实现会违反 ddd-lint。缓解：架构阶段在 §3 方案 (a)/(b)
   中择一并出 ADR（trait 注入或文本入参）；新增文件过 ddd-lint（违规=0）。
8. **测试基础设施（中）**：`flutter_tts` 依赖平台通道，widget 测试无法真实调用。缓解：`ListenPage`
   构造注入 `TtsEngine`（US-1 明确要求可注入），测试用 `FakeTtsEngine` 记录调用；`SystemTtsEngine`
   用平台通道 mock 单测。
9. **范围蔓延（中）**：线框 09/10 含定时/后台/多音色/Piper/克隆等 P2 项，易被顺手实现。缓解：§1
   划界 + US-13 断言 P2 控件禁用；`just_audio`/`audio_service` 保持注释；点读/笔记/划重点显式排除。
10. **依赖体积与兼容（低-中）**：新增 `flutter_tts` 影响包体积/平台配置（Android 需 TTS intent
    query）。缓解：仅启用 `flutter_tts`（系统 TTS 零体积）；回归桌面/Android 构建脚本
    （`scripts/build-android.sh` 等）确保通过。

---

## 6. 闸门1 自评

- [x] **验收标准全部可测（无"体验好"类不可测词）**：US-1~US-25 每条均为可断言观察项——
  - 控件存在性/数量/类型：`find.byType(ListenPage)`、`find.byType(ReaderSelectionToolbar)`、
    `find.byType(AdaptiveTextSelectionToolbar) == findsNothing`、线框 09/10 各控件；
  - 回调触发与调用记录：fake `TtsEngine` 的 `configure/speak/pause/resume/stop` 调用序列、
    `backend.saveProgress` 参数、`Clipboard.getData`；
  - 配置断言：`InAppWebViewSettings.disableContextMenu == true`、`SelectionArea.contextMenuBuilder`
    返回 `SizedBox.shrink`、P2 控件禁用态；
  - Rust 返回值：`Ok(Vec<SentenceChunk>)`、句↔Locator 往返 `i == index_at(locator_for_sentence(i))`、
    `Err` 边界、切句性能 `<50ms`（CI ≤200ms）；
  - 真机/集成项：Android 长按无原生 ActionMode、离线出声、退出/重开续读。
  每条 UI 项标注原型图映射（09/10/04-selection），无不可测措辞。
- [x] **与既有 REQ 无重复**：REQ-001（分页渲染/进度/`chapterHtml`）、REQ-003（选中→翻译/查词）、
  REQ-004（阅读器沉浸态/工具条/⋯更多入口）均**复用不重做**（US-2/US-20/US-25 明确为消费既有能力）；
  LISTEN-03/04/05/08/09 属产品层用户故事，本 REQ 只实现其 P0/P1 子集（入口/离线系统 TTS/播放控制/
  语速/听读同进度/跟读/连播），LISTEN-06/07/10/11（定时/后台/多音色/AI/克隆/点读）显式划出（§1.2/§4）；
  "复制"修复为相邻缺陷（P1 可选，§4）。
- [x] **影响面清单非空**：§3 逐层列出问题1 的 7 个根因（R1-1..R1-7）对应文件与问题2 的分页/滚动/
  相邻三个面（R2-1..R2-3），覆盖 Rust core（domain 约束与 DDD 决策）、FFI 桥接再生成、Flutter
  引擎/页面/widget/services、`pubspec` 依赖、测试面（新增/更新/回归）、回归面（core/Flutter/FFI/
  分页选区/闸门），并含听读进度数据模型（复用 `reading_progress`，零新表）与 `settings` 键，共
  10+ 类，均列具体 file:line 与约束。
