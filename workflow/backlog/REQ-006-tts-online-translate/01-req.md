<!-- wf-meta: req=REQ-006 | phase=requirements | agent=req-analyst | date=2026-09-09 | gate=passed -->
# REQ-006 · 听书真正发声/自动滚动 + 新增在线翻译 —— 需求分析

## 1. 背景与目标

### 1.1 问题现象（用户原始诉求，不可偏离）

- **问题1 · 听书（P0）**：点击"听书"后当前句高亮出现，但**没有声音**（TTS 不发声），且**不会自动滚动**到当前朗读句。
- **问题2 · 在线翻译（P0）**：选中一段话翻译，当前只走离线词典，未命中就提示"离线翻译未命中……"。
  需要新增**在线翻译**（翻译任意句子/段落），优先复用 core 已有的在线翻译 Provider 接口
  （REQ-003：ureq + DeepL）。若需 API key：做成设置项可配置，未配置时回退离线并给明确提示；
  **禁止硬编码 key**。

### 1.2 成功标准与范围划界

**成功标准一句话**：在 Android 真机（targetSdk 36）上点击"听书"能听到系统 TTS 朗读、当前句自动滚动进
视口并高亮；选中任意句子/段落翻译时，已配置 DeepL key 则走在线返回非空译文（provider=deepl），未配置
key 或网络失败则回退离线/给出明确可重试提示，且全仓库无硬编码 key、在线请求只发送选中文本。

**本期范围**：

- **P0（必须）**：
  1. Android 主清单声明 TTS 包可见性（`TTS_SERVICE` queries）+ release 网络权限（`INTERNET`）。
  2. `SystemTtsEngine` 初始化正确（语言、完成等待、音色回退不传无效逻辑名、失败可见、音频焦点）。
  3. 听书页当前朗读句**自动滚动进视口**并高亮。
  4. 在线翻译可用（DeepL），任意句子/段落；key 设置页可配置并回填。
  5. 未配置 key / 网络失败的回退与明确提示，不丢原文、可重试。
  6. 隐私：在线只发送选中文本；仓库无硬编码 key。
- **P1（本期尽量）**：`onStart` 事件接线用于高亮/滚动时序；音色枚举差异的可用性提示；译文来源标签
  （在线/离线/缓存）修正。
- **明确不做（另立 REQ）**：AI 在线音色、Piper 本地神经音色、声音克隆、定时关闭、后台播放/系统媒体键、
  点读（点句开读）——沿用 REQ-005 划界，线框 10 中仍为禁用灰置；TRANS-03/04/05（Provider 启停进阶
  管理、生词本、对照阅读）；key 的加密/系统钥匙串存储（见 §5 风险8，本期仅"不硬编码 + settings 存储"）。

### 1.3 根因核实（逐条 Read 源码，含与 orchestrator 初查的对照）

> 下表每条均给出 file:line 证据；"初查一致"表示与 orchestrator 初查结论一致，"修正"表示初查需细化。

| 编号 | 结论 | 证据（已逐条核对） | 对照初查 |
|---|---|---|---|
| **R1-1** | **Android 主清单缺 TTS 包可见性**：只有 `PROCESS_TEXT` 的 `<queries>`，无 `android.intent.action.TTS_SERVICE`。Android 11(API30)+ 包可见性下 `TextToSpeech` 无法解析默认引擎 → 初始化失败/无声。targetSdk=36（Flutter 3.47.2 `FlutterExtension.kt:34`）、minSdk=24（`:26`）。 | `app/android/app/src/main/AndroidManifest.xml:39-44`；`/root/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt:26,34`；flutter_tts 4.2.5 README 明示需声明（`.../flutter_tts-4.2.5/README.md:81-91`），且插件自身 manifest 不含该 query（`.../flutter_tts-4.2.5/android/src/main/AndroidManifest.xml` 仅 `package`） | **一致** |
| **R1-2** | **release 无 INTERNET 权限**：`INTERNET` 只在 debug/profile 清单，main 清单没有 → release APK 的 DeepL 在线翻译必失败。 | `app/android/app/src/main/AndroidManifest.xml` 无 `uses-permission`；`app/android/app/src/debug/AndroidManifest.xml:6`、`app/android/app/src/profile/AndroidManifest.xml:6` 有 | **一致** |
| **R1-3** | **自动滚动缺失**：`ListenFollowHighlight` 是 `StatelessWidget`，仅 `SingleChildScrollView` + `RichText`，无 `ScrollController`/`ensureVisible`；句变化时不会滚动。 | `app/lib/widgets/listen_follow_highlight.dart:10,29-31`；使用处 `app/lib/pages/listen_page.dart:435-441` | **一致** |
| **R1-4** | **引擎未 `setLanguage` / 未 `awaitSpeakCompletion`**：`configure` 只调 `setSpeechRate`+`setVoice`；`SystemTtsEngine` 全文无 `setLanguage`/`awaitSpeakCompletion`。中文文本在默认 locale 非中文的机型上可能无声或读错语言。 | `app/lib/engines/system_tts_engine.dart:32-38`（configure）、`:72-75`（speak） | **一致** |
| **R1-5** | **音色回退传无效逻辑名（细化）**：`_pickVoice` 返回 null 时 `voice ??= {'name': voiceId, 'locale':'zh-CN'}`，即把逻辑 id `system_male`/`system_female` 当作真实系统音色名。Android 插件 `setVoice` 找不到时**静默 `result.success(0)` 返回、不抛错**（`FlutterTtsPlugin.kt:514-526`），故不会"使引擎异常"，但会导致音色选择恒为默认（男/女声切换失效），且现有测试还断言了这一行为。 | `app/lib/engines/system_tts_engine.dart:41-55`（回退 `:49`）；`FlutterTtsPlugin.kt:514-526`；测试 `app/test/tts_engine_test.dart:187-214` | **修正**（危害等级下调；仍需修） |
| **R1-6** | **speak 失败被静默**：`speak` 忽略 `_tts.speak` 的返回值（Android 侧服务不可用时插件会重建引擎并返回 `false`，`FlutterTtsPlugin.kt:664-686`），`ListenPage` 只显示"朗读中"却无 `TtsFailed`，用户无任何反馈。 | `app/lib/engines/system_tts_engine.dart:72-75`；`FlutterTtsPlugin.kt:664-686` | 初查未列（**新增**） |
| **R1-7** | **未注册 start handler / 无 onStart 事件**：引擎只注册 completion/cancel/error，`TtsEvent` 只有 Done/Failed；用户诉求点名的"onStart/onComplete 接线"缺 onStart。 | `app/lib/engines/system_tts_engine.dart:15-19,94-101`；`app/lib/engines/tts_engine.dart:67-80` | 初查提及接线（**细化**） |
| **R1-8** | **未请求音频焦点**：`speak(chunk.text)` 未传 `focus: true`（Android 插件仅在 `focus=true` 时 `requestAudioFocus()`）。 | `system_tts_engine.dart:74`；`FlutterTtsPlugin.kt:668-670` | 初查提及音频焦点（**一致**） |
| **R2-1** | **翻译默认 Provider=offline**：`TranslationRepo::default_provider()` 初值 `"offline"`；`api.rs` 按 `[offline, deepl, echo]` 装配。用户未保存 key 时 `translate()` 走 offline，整句未命中 → `Error::NotConfigured("离线翻译未命中（请先安装内置词库）")`。 | `core/src/store/translation.rs:19-20,128-139`；`core/src/api.rs:160-168`；`core/src/dict/translation.rs:404-417`；`core/src/dict/provider.rs:127-131` | **一致** |
| **R2-2** | **设置页只写不读、无回填**：`_saveKey` 调 `setConfig('deepl', key)`（同时切默认 provider=deepl），但没有读取已存 key/当前 provider 的通道；`TranslateBackend` 只有 `setConfig`，无 getter；FFI 只有 `translate_set_config`。 | `app/lib/pages/settings_page.dart:88-96,150-168`；`app/lib/services/translate_backend.dart:55-67`；`app/lib/services/rust_translate_backend.dart:72-74`；`core/src/api.rs:339-347` | **一致** |
| **R2-3** | **无自动回退**：`translate_cached` 选默认 provider 后若需 key 且无 key → 直接 `NotConfigured`，**不**回退 offline；offline 未命中亦不回退在线。 | `core/src/dict/translation.rs:404-417` | **一致** |
| **R2-4** | **译文来源标签错误**：`TranslationResultCard` 对非缓存结果一律显示"在线"，offline 结果会被标成"在线"。 | `app/lib/widgets/translation_popup.dart:31-46` | 初查未列（**新增**） |

**根因结论（供架构阶段参考，不作为本阶段实现决定）**：问题1 的"无声"主因是 R1-1（包可见性）叠加
R1-4/R1-6/R1-8；"不滚动"是 R1-3。问题2 的"只走离线"是 R2-1 叠加 R2-3；"无法配置/无回填"是 R2-2；
提示与标签问题为 R2-4。**R1-5 与 orchestrator 初查有细化**：插件对无效音色名是静默忽略而非异常，
危害从"引擎异常"下调为"音色切换失效"，但修复方向一致（不把逻辑名当真实音色名）。

### 1.4 原型权威性与 UI 映射（docs/wireframes/** 为 UI 权威规范）

| 屏 | 原型图 | 本 REQ 涉及 | 是否改变布局 |
|---|---|---|---|
| 听书跟读 | `docs/wireframes/09-listen-player.svg` | 当前句高亮 + **自动滚动进视口**；控制条不变 | 仅滚动行为，不改布局 |
| 听书设置 | `docs/wireframes/10-listen-settings.svg` | 音色可用性提示（P1）；P2 项保持禁用灰置 | 不改布局 |
| 翻译浮层 | `docs/wireframes/08-translation.svg` | 译文卡片来源标签（在线/离线/缓存）、错误+重试 | 不改布局 |
| 选中工具条 | `docs/wireframes/reader-ui-v2/04-selection.svg` | "翻译"入口复用，不新增入口 | 不改布局 |
| 设置页 | `docs/wireframes/03-settings.svg`（+ 现有"词典与翻译"区块） | 新增在线翻译 Provider 选择 + key 回填 | 仅该区块增加控件，非全局改版 |

> 本 REQ **预期不新增/大改 UI 布局**：听书页仅增加滚动行为；设置页"词典与翻译"区块增加在线翻译配置；
> 译文卡片修正标签。实现阶段禁止对上述线框的布局自由发挥（闸门3 逐屏核对）。

---

## 2. 用户故事与验收标准（Given/When/Then，必须可测；标注根因/原型图/自动化层级）

> **自动化层级标注**：`[单测]` = 可在 CI 自动断言；`[配置断言]` = 静态/manifest 解析断言；
> `[真机]` = 需 Android 真机/集成人工验收（CI 不可自动化，交付阶段提供手工清单）。

### 故事 1：TTS 真正发声（平台配置 + 引擎初始化 + 失败可见）—— 作为王叔，我想要点了听书就出声，以便通勤时"听"书

- **US-1 Android 主清单声明 TTS 包可见性（R1-1，P0，[配置断言]）**
  - Given 仓库文件 `app/android/app/src/main/AndroidManifest.xml`
  - When 以 XML/文本解析其 `<queries>` 节点
  - Then 存在 `<intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>`；
    原 `PROCESS_TEXT` intent 保留；测试以纯文本断言执行，不依赖真机/构建。
  - Given 解析 `app/android/app/build.gradle.kts` 的 `targetSdk`
  - Then 其值 ≥ 30（本机 Flutter 3.47.2 默认 36；测试可断言该配置或注释记录来源）。
  - 依据：flutter_tts 4.2.5 README:81-91 明示 Android 11+ 必须声明；插件 manifest 不含该 query。

- **US-2 主清单声明 INTERNET 权限（R1-2，P0，[配置断言]）**
  - Given `app/android/app/src/main/AndroidManifest.xml`
  - When 检查 `uses-permission`
  - Then 含 `android.permission.INTERNET`（release 在线翻译必需）；debug/profile 清单可保留、不冲突。
  - Given 执行 release 构建（或 manifest-merger 产物检查）When 检查合并清单 Then 含 INTERNET；
    若无法在 CI 跑 Android 构建，则以主清单静态断言 + 交付阶段 release APK 手工验收记录兜底。

- **US-3 引擎初始化调用序列：语言 + 完成等待 + 语速/音色（R1-4，P0，[单测]）**
  - Given `FakeFlutterTts`（记录 `calls`/`args`，既有 `app/test/tts_engine_test.dart:11-68`）
  - When `SystemTtsEngine.configure(voiceId:'system_male', speed:1.0)` 后 `speak(chunk)`
  - Then 断言调用序列包含 `setLanguage('zh-CN')`（或按设置/目标语言，测试断言具体值）与
    `awaitSpeakCompletion(true)`，且二者在 `speak` 之前发生；`setSpeechRate(1.0)`、`setVoice(...)`
    仍被调用（顺序可断言）。
  - Given 平台不支持 `setLanguage`/`awaitSpeakCompletion`（fake 抛错）When `configure`
  - Then 不抛错、不阻断后续 `speak`（catch 后可上报警告），断言 `speak` 仍被调用。

- **US-4 speak 失败可见 + 完成事件恰好一次 + 音频焦点（R1-6/R1-8，P0，[单测]）**
  - Given `FakeFlutterTts.speak` 返回 `false`（模拟服务不可用）或抛错 When `SystemTtsEngine.speak(chunk)`
  - Then 引擎经 `events` 派发 `TtsFailed`（含可读原因），`ListenPage` 进入错误提示；
    **不得**只停留在"朗读中"且无任何事件。
  - Given `speak` 成功、完成回调触发一次 When 断言 Then 恰好派发一次 `TtsSentenceDone(index)`
    （不重复、不丢；index 为该句章内序号）。
  - Given Android 路径 When `speak` Then 传给 `flutter_tts.speak` 的 `focus == true`
    （断言 fake 收到的 `focus` 参数；Android 插件仅在 true 时请求音频焦点）。

- **US-5 onStart 事件接线（R1-7，P1，[单测]）**
  - Given 构造 `SystemTtsEngine` When 检查 Then 已注册 `setStartHandler`（调用记录可见）。
  - Given fake 触发 start 回调 When 开始朗读某句 Then 引擎派发 `TtsSentenceStarted(index)`（新增事件，
    或架构确定的等价事件）；`ListenPage` 收到后更新当前句高亮/滚动锚点。
  - Given 新增事件类型 When 编译 Then `ListenPage._onTtsEvent` 对事件做穷尽处理（无 `switch` 遗漏告警）。

- **US-6 完成回调推进下一句（REQ-005 US-14/US-17 回归加固，P0，[单测]）**
  - Given `ListenPage` 播放中、fake 引擎发 `TtsSentenceDone(i)` When 处理
  - Then 调用 `saveProgress`（沿用 300ms 防抖）并 `speak(_chunks[i+1])`；句 `i` 不再高亮、句 `i+1` 高亮。
  - 说明：此为 REQ-005 已交付契约，本 REQ 因引擎新增 `awaitSpeakCompletion`/`onStart` 需**回归验证**
    不产生重复推进或双 `speak`（见 §5 风险5）。

### 故事 2：自动滚动/高亮到当前朗读句 —— 作为王叔，我想要看到读到哪句，以便跟上

- **US-7 句变化时滚动到当前句（R1-3，P0，[单测]，线框 09）**
  - Given `ListenFollowHighlight`（或架构确定的等价组件）可注入 `ScrollController`，文本长到
    `maxScrollExtent > 0`
  - When 将高亮区间从句 0 改为靠后的句 k
  - Then 满足以下任一可观察代理：① `controller.offset` 随句序号增大而**单调增大**；
    ② 对当前句锚点调用了 `Scrollable.ensureVisible`/`RenderObject.showOnScreen`（可经注入回调或
    spy 断言）；滚动稳定后当前句的 `RenderBox` 落在视口 `[0, viewportHeight]` 内。
  - Given 句序号由 k 回退到更早句 When 变化 Then offset 相应减小（单调性双向可断言）。

- **US-8 听书页句推进时滚动同步（R1-3，P0，[单测]，线框 09）**
  - Given `ListenPage` 已播放、正文可滚动，fake 引擎连续 `emitDone(i)` When 推进到句 `i+1`
  - Then 高亮子串切换为句 `i+1` 且滚动位置随之前移（widget 测试断言 `ListenFollowHighlight` 的
    `highlightStart/End` 变化 + `controller.offset` 变化）；旧句不再高亮。

- **US-9 手动跳句/拖动后滚动同步（R1-3，P0，[单测]，线框 09）**
  - Given 用户点击上一句/下一句或拖动句级进度条到句 j（`_onSeek`）When 松手
  - Then `_index == j`，高亮与滚动锚点同步到句 j（断言高亮区间与 offset 对应句 j）；
    不触发越界句索引、不崩溃。

### 故事 3：在线翻译任意句子/段落 —— 作为陈老师，我想要整句/整段在线翻译，以便理解原文

- **US-10 已配置 key 时在线翻译句子（R2-1/R2-3，P0，[单测]）**
  - Given 已配置 DeepL key 且翻译策略为在线/自动（架构定命名）
  - When 调用 `translate(text, from, to)`（如一句中文/英文）
  - Then 返回 `provider == "deepl"`、`text` 非空且不等于输入、首次 `fromCache == false`；
    **不**返回"离线翻译未命中"类错误。
  - Given 测试注入 DeepL stub/mock Provider When 断言 Then 路由到 deepl（计数 +1）；
    真实网络端到端作为交付阶段手工验收项（需用户 key）。

- **US-11 在线翻译段落/长文本（R2-1，P0，[单测]）**
  - Given 选中跨行段落（含 `\n`/多空白）When 翻译
  - Then Provider 收到**空白规范化后**的整段（连续空白折叠、trim，复用 REQ-003 `normalize_text`）；
    `provider == "deepl"`；译文非空。
  - Given 段落长度超过单次请求上限（如 > 10000 字符）When 翻译
  - Then 不崩溃：给出明确错误（携带原文可重试）或按架构决定分段合并；断言无 panic/无静默空结果。

- **US-12 在线命中缓存不重复请求（REQ-003 US-10/US-11 回归，P0，[单测]）**
  - Given 同一 `(text, from, to, deepl)` 已缓存 When 再次翻译
  - Then Provider 调用计数不增、`fromCache == true`、译文一致。

- **US-13 默认策略：在线优先、未配置回退离线（R2-3，P0，[单测]）**
  - Given 未配置任何在线 key When 翻译 Then 走 offline（命中则返回离线译文）；
    **不得**因默认 provider=deepl 而无条件 `NotConfigured`。
  - Given 已配置 key When 翻译 Then 走在线（US-10）。
  - 说明：新增 `provider="auto"` 策略还是修改 `translate_cached` 回退逻辑由架构阶段定，
    验收只断言可观察行为（provider 取值 + 是否报错）。

### 故事 4：API key 可配置且未硬编码 —— 作为用户，我想要填自己的 key，以便安全地使用在线翻译

- **US-14 仓库无硬编码 key（P0，[配置断言]）**
  - Given 全仓库源码与配置 When 扫描 Then 不存在真实 DeepL key（形如 `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx:fx`）、
    不存在硬编码 `DeepL-Auth-Key <字面量>`；示例/文档只用占位符（如 `YOUR_DEEPL_KEY`）。
  - Given 测试 When 运行 Then 断言 key 仅来自 settings（用户输入）；CI 用 fake key 或不发真实请求。

- **US-15 设置页保存并回填 key / 当前策略（R2-2，P0，[单测]）**
  - Given 设置页 When 输入 key 并保存 Then 调 `setConfig('deepl', key)`（或等价），提示已保存。
  - Given 已保存 key 后重新进入设置页 Then 输入框回填已保存 key（掩码显示），并显示当前
    provider/策略（如"自动（在线优先）"）；为此新增读取通道（FFI `translate_get_config` 或等价 +
    `TranslateBackend` getter + fake），架构阶段落定签名。
  - Given 空 key 保存 When 保存 Then 语义明确（清空并提示"未配置"或拒绝覆盖），不静默写入空值
    覆盖既有 key；测试断言所选语义。

- **US-16 未配置 key 时不静默走在线、给明确提示（R2-1/R2-3，P0，[单测]）**
  - Given 未配置 key 且离线未命中 When 翻译
  - Then 错误文案同时含"未配置在线翻译 API Key"与"离线未命中"语义，提供重试；错误携带原文；不写缓存。
  - Given 未配置 key 且离线命中 When 翻译 Then 返回 offline 译文，UI 标注"离线"（见 US-19）。

### 故事 5：回退与错误提示 —— 作为用户，我想要失败时能看懂、能重试、不丢原文

- **US-17 在线失败回退离线（R2-3，P0，[单测]）**
  - Given 已配置 key、在线 Provider 返回网络/HTTP 错误 When 翻译
  - Then 若离线词典命中 → 返回 offline 结果且 UI 提示"在线失败，已回退离线"；
    若离线也未命中 → 返回可重试错误（含原文与原因），失败不写缓存。
  - Given 失败后网络恢复 When 重试同一原文 Then 可再次尝试在线（可重试闭环）。

- **US-18 译文卡片来源标签正确（R2-4，P1，[单测]，线框 08）**
  - Given 结果 `provider=="deepl"` 且 `fromCache==false` Then 显示"在线"；
    `provider=="offline"` Then 显示"离线"（或"离线词典"）；`fromCache==true` Then 显示"缓存"；
    同时显示 provider 名。
  - 依据：现状对非缓存一律显示"在线"（`translation_popup.dart:31-46`），需修正。

- **US-19 错误不丢原文 + 可重试（REQ-003 US-12/US-15 回归，P0，[单测]）**
  - Given 翻译失败 Then `OverlayError` 文案含原文或可据此重试；点击"重试"以同一原文再次调用
    （断言 fake 的 `lastTranslatedText` 不变、调用计数 +1）。

### 故事 6：隐私 —— 作为用户，我想要在线翻译只发送我选中的文字

- **US-20 在线请求只含选中文本（REQ-003 US-9/US-13 回归，P0，[单测]）**
  - Given 在线翻译请求 When 检查 Provider 入参与 HTTP body Then 只含 `text`/`source_lang`
    （非 auto 时）/`target_lang`，**无** book_id/href/书名/路径/设备信息（对 Provider 入参与
    `deepl_body` 双重断言，复用既有 `deepl_body` 测试）。
  - Given 缓存写入 Then 仅含 REQ-003 规定列（source_text/from_lang/to_lang/provider/result/
    created_at/hit_count），无书信息。

### 故事 7：音色枚举差异鲁棒性 —— 作为王叔，我想要没有男女声时也能正常朗读

- **US-21 无匹配系统音色时不传无效逻辑名（R1-5，P1，[单测]，线框 10）**
  - Given `getVoices` 返回列表不含 name 含 `male`/`female` 的音色（如 `zh-cn-x-ccc-local`），
    或 `getVoices` 抛错 When `configure(voiceId:'system_male')`
  - Then **不**调用 `setVoice({'name':'system_male', ...})`；改为调用 `clearVoice()` 或保持默认音色；
    随后 `speak` 仍被调用（断言成功路径）。
  - Given 找到匹配音色 When configure Then `setVoice` 传入真实 `name`/`locale`（保持 REQ-005 US-13）。
  - Given 无匹配音色 When 听书设置/控制条展示 Then 显示"系统默认音色"或等价提示（不误导为已选男/女声）。

### 故事 8：测试与回归 —— 作为发布者，我想要新能力可测、旧能力不破

- **US-22 新增/更新测试全绿（P0，[单测]）**
  - Given 新增测试覆盖：manifest 静态断言（US-1/US-2）、`SystemTtsEngine` 调用序列/失败/焦点/onStart
    （US-3~US-5）、`ListenFollowHighlight` 滚动代理（US-7）、`ListenPage` 滚动同步（US-8/US-9）、
    翻译策略在线/回退（US-10~US-13/US-17）、设置页回填（US-15）、卡片标签（US-18）、隐私（US-20）
  - When 运行 `flutter test` 与 `cargo test -p reader_core` Then 全部通过。

- **US-23 既有功能零回归（P0，[单测]）**
  - Given REQ-003（翻译/词典/FFI/设置页）、REQ-005（TTS 引擎/听书页/FFI）、REQ-004（阅读器 UI/选中）
    既有测试 When 全量运行 Then 通过；`translate` 缓存键/错误语义保持兼容；`reading_progress` 语义不变；
    `ListenSettingsData`/`listen.*` 键兼容。
  - 特别：REQ-005 `tts_engine_test.dart:187-214` 现断言回退音色名为 `system_female`/`system_male`，
    因 US-21 修正需同步更新为"调用 `clearVoice`/不传逻辑名且仍能 speak"；属**测试预期更新**，
    不改变 REQ-005 的对外行为契约。

---

## 3. 影响面分析（必须非空）

### 3.1 既有功能

- **Android 构建配置**：`app/android/app/src/main/AndroidManifest.xml` 增加 `TTS_SERVICE` intent query
  与 `INTERNET` 权限；`app/android/app/src/debug/AndroidManifest.xml`、`.../profile/...` 的 INTERNET
  保持（重复声明由 manifest merger 合并，无冲突）；`build.gradle.kts` 的 `targetSdk`（当前经
  `flutter.targetSdkVersion`=36）不改，但 US-1 需断言 ≥30。
- **TTS 引擎层（interface）**：`app/lib/engines/system_tts_engine.dart` 增加 `setLanguage`、
  `awaitSpeakCompletion(true)`、`setStartHandler`、`speak(focus:true)`、`speak` 返回值/异常处理、
  音色回退改为 `clearVoice()`/默认音色；`app/lib/engines/tts_engine.dart` 增加 `TtsSentenceStarted`
  事件（契约扩展）→ 需同步 `FakeTtsEngine`（`app/test/fake_tts_engine.dart`）与 `ListenPage._onTtsEvent`。
- **听书页/跟读组件**：`app/lib/widgets/listen_follow_highlight.dart` 由 `StatelessWidget` 改
  `StatefulWidget`（或新增滚动协调器），持有/注入 `ScrollController`，在 `didUpdateWidget` 响应句变化；
  `app/lib/pages/listen_page.dart` 接线 onStart、滚动锚点，保持 REQ-005 的句完成写进度/连播/seek 行为。
- **翻译编排（domain）**：`core/src/dict/translation.rs` `translate_cached` 增加"在线优先/回退离线"
  策略或新增 auto 路由；`core/src/dict/provider.rs` `OfflineProvider` 未命中错误文案需兼容扩展
  （保留"离线翻译未命中"子串以免破坏 REQ-003 断言，或由策略层包装提示）。
- **桥接/服务层**：`core/src/api.rs` 新增 `translate_get_config`（读取当前 provider/策略 + 掩码 key）
  或等价；`app/lib/services/translate_backend.dart`、`rust_translate_backend.dart` 增加 getter 并同步
  `app/test/fake_translate_backend.dart`；`app/lib/pages/reader_page.dart` `_doTranslate` 可能需传策略。
- **设置页/译文卡片（UI）**：`app/lib/pages/settings_page.dart` 增加 Provider 选择/策略 + key 回填
  （`_load` 读取配置）；`app/lib/widgets/translation_popup.dart` 修正来源标签。

### 3.2 数据模型 / 接口

- **`settings` 表（key/value，无迁移）**：新增翻译策略键（如 `translate.default_provider` 支持
  `auto`，或独立 `translate.mode`）；沿用 `translate.key.deepl`。**无 schema 变更**，`user_version`
  保持 3（REQ-003 迁移不变）。
- **`translation_cache` 表**：无 schema 变更；缓存键 `(source_text, from_lang, to_lang, provider)`
  天然区分在线/离线（同文会生成 offline 与 deepl 两行），符合 REQ-003 语义。
- **桥接契约**：`translate` 现有签名 `(text, from, to)` 保持不变（策略在 core 内解析）或按架构新增
  可选 provider 参数；新增 `translate_get_config`（读）；`translate_set_config` 语义扩展需保持
  "保存 key + 切默认 provider" 的向后兼容（REQ-003 ADR 关联裁定2）。
- **`ListenSettingsData`**：字段不变（`voiceId`/`speed`/`autoNext`）；`listen.*` 键不变。
- **Android manifest**：作为构建期接口，`TTS_SERVICE` query 与 `INTERNET` 权限需与 targetSdk 36 匹配。

### 3.3 听读进度 / Locator

- **零模型变更**：自动滚动是纯 UI 行为，不改变 `reading_progress`/`Locator`/句↔Locator 映射；
  `TtsSentenceStarted` 只用于高亮/滚动时序，**不得**触发额外 `saveProgress`（写盘仍只在句完成）。
- 回归确认：进入/退出听书位置不变、句完成写盘节流（300ms）与退出强刷、连播/seek 行为与 REQ-005 一致。

### 3.4 回归面（非空）

- **core**：`dict`/`translation`/`store::translation`/`tts` 既有单测与 `core/tests/translate_corpus.rs`；
  缓存键/错误语义/隐私参数断言不变；无迁移测试变化。
- **Flutter**：`tts_engine_test.dart`（US-3/US-4/US-21 会更新既有断言）、`listen_page_test.dart`、
  `translate_reader_test.dart`、`settings_page_test.dart`、`reader_page_test.dart`、
  `reader_selection_test.dart`、`rust_dict_ffi_test.dart`、`tts_ffi_test.dart`、goldens/截图测试
  （译文卡片标签变更可能影响 golden，需同步）。
- **构建**：Android debug/release 构建与 manifest 合并；`scripts/build-android.sh` 回归。
- **闸门**：DDD 分层（`app/lib/engines` 属 interface，禁 import `src/rust/`；`core/src/dict`/`tts`
  属 domain，禁 `crate::store|api|library`）、CRAP、变异分数。

---

## 4. 依赖与优先级

| 项 | 内容 | 依赖/前置 | 优先级 |
|---|---|---|---|
| TTS 包可见性 | main manifest `TTS_SERVICE` query | flutter_tts 4.2.5、targetSdk 36 | P0 |
| release 联网 | main manifest `INTERNET` | Android manifest merger | P0 |
| 引擎初始化 | `setLanguage`/`awaitSpeakCompletion`/焦点/失败上报 | REQ-005 `SystemTtsEngine`/`TtsEngine` 契约 | P0 |
| onStart 事件 | `TtsSentenceStarted` + start handler | 同上（契约扩展，需同步 fake/页面） | P1 |
| 自动滚动 | `ListenFollowHighlight` 滚动控制 | REQ-005 跟读高亮、Flutter `ScrollController` | P0 |
| 在线翻译 | DeepL Provider（ureq + rustls） | REQ-003 `DeepLProvider`/`TranslationService`/缓存 | P0 |
| 翻译策略/回退 | 在线优先、未配置/失败回退离线 | `ProviderConfig`/`translate_cached` | P0 |
| key 配置与回填 | `translate_set_config` + 新增读通道 | REQ-003 settings 键、FRB 再生成 | P0 |
| 来源标签 | 译文卡片"在线/离线/缓存" | 线框 08 | P1 |
| 音色回退修正 | 不传逻辑名、`clearVoice`/默认 | REQ-005 音色枚举 | P1 |
| AI 音色/Piper/克隆/定时/后台 | — | — | 不做（沿用 REQ-005 禁用占位） |
| TRANS-03/04/05 | — | — | 不做（另立 REQ） |

- **与既有 REQ 关系**：REQ-003 提供 DeepL Provider/缓存/`translate_set_config`/隐私约束（本 REQ
  复用不重做，仅补"在线可达 + 回退 + 读配置"）；REQ-005 提供 `SystemTtsEngine`/听书页/跟读高亮/
  句↔Locator（本 REQ 修平台配置与引擎细节、加滚动，不重做切句/进度）；REQ-004 提供选中工具条
  "翻译"入口（复用）。三者能力**复用不重做**。
- **优先级说明**：两个问题均为用户反馈的 **P0**；US-5/US-18/US-21 为 P1，可在 P0 全绿后补，
  但不影响 P0 交付验收。
- **验收层级**：`[单测]`/`[配置断言]` 进 CI；`[真机]`（真正出声、音频焦点、release 联网、真实
  DeepL 请求）由交付阶段按手工清单验收（需用户提供 key）。

---

## 5. 风险

1. **真机验证不可自动化（高）**：TTS 是否真出声、音频焦点行为、manifest 合并后 release 权限、
   真实 DeepL 请求，CI（Linux，无 Android 设备/无 key）无法覆盖。缓解：US-1/US-2 静态断言 +
   US-3~US-5 fake 平台通道断言 + US-7 滚动代理断言兜底；交付阶段提供 Android 真机手工验收清单
   （听书出声、中文语言、焦点、release 联网、真实翻译），并在 04-coverage/05-delivery 记录未覆盖项。
2. **DeepL key/网络（高）**：CI 无 key、真实请求计费/限流；Free 层额度与文本长度上限（单请求约
   128 KiB）可能导致长段落失败。缓解：单测用 stub/mock；真实端到端列为手工项；US-11 覆盖超长文本
   的明确错误/分段；不硬编码 key（US-14）。
3. **Android 权限/包可见性（中-高）**：`INTERNET` 为普通权限但会扩大权限面（隐私权衡）；`TTS_SERVICE`
   query 在部分 ROM 上仍可能找不到引擎；manifest merger 与 flavor 差异。缓解：主清单统一声明；
   US-1/US-2 静态断言 + release 手工验收；US-4 保证找不到引擎时失败可见而非静默。
4. **音色枚举差异（中）**：各设备系统音色名不统一，逻辑 `system_male`/`system_female` 无法直接映射；
   修正为"匹配不到则默认音色"后，男女声切换可能名存实亡。缓解：US-21 断言不传无效名且仍能朗读；
   UI 提示"系统默认音色"；真机清单核对至少一台设备的中文音色可用性。
5. **`awaitSpeakCompletion` 与完成回调的并发/重复推进（中）**：开启完成等待后，`speak` 的 Future
   与 completion handler 可能同时触发，`ListenPage._handleSentenceDone` 内再 `speak` 可能造成双读或
   递归。缓解：US-4 断言"完成事件恰好一次"，US-6 回归验证不重复推进/双 `speak`；架构阶段明确
   以事件驱动为准、`speak` Future 不参与推进。
6. **自动滚动精度/稳定性（中）**：`RichText` 按字符区间高亮，无法直接对 span 定位；按比例估算
   offset 与实际换行可能偏差，测试可能抖动。缓解：US-7 允许"offset 单调"或"`ensureVisible`/锚点
   可见"两种代理；优先用 `GlobalKey` + `ensureVisible` 或按行高估算；测试用足够长文本与
   `pumpAndSettle` 降低抖动。
7. **错误文案兼容性（中）**：REQ-003 测试/实现存在"离线翻译未命中"文案，US-16 要求补充"未配置在线
   API Key"。缓解：保留原有子串并追加，或在策略层包装提示；回归跑 `core/tests/translate_corpus.rs`
   与 `translate_reader_test.dart` 确认不破坏。
8. **key 存储安全（中）**：key 存于 SQLite `settings` 明文（非硬编码但未加密）。缓解：本期满足
   "可配置 + 不硬编码 + 掩码回填"；加密/系统钥匙串列为后续 REQ（§1.2 明确不做），在 §5 与交付文档
   记录已知限制。
9. **范围蔓延（中）**：听书线框 10 含 P2 项（AI 音色/Piper/克隆/定时/后台），易被顺手实现。缓解：
   §1.2 划界 + 沿用 REQ-005 禁用占位；`just_audio`/`audio_service` 保持注释。
10. **UI 标签/ golden 回归（低-中）**：译文卡片标签从"在线/缓存"改为"在线/离线/缓存"可能影响
    golden/截图测试。缓解：US-18 明确标签映射，更新相关 golden 并复核线框 08。

---

## 6. 闸门1 自评

- [x] **验收标准全部可测（无"体验好"类不可测词）**：US-1~US-23 每条均为可断言观察项——
  - `[配置断言]`：manifest 含 `TTS_SERVICE` intent query（US-1）、含 `INTERNET`（US-2）、targetSdk ≥30、
    仓库无真实 key 正则匹配（US-14）；
  - `[单测]`：`FakeFlutterTts` 调用序列（`setLanguage`/`awaitSpeakCompletion`/`setSpeechRate`/`setVoice`/
    `speak` 的 `focus` 参数，US-3/US-4）、`TtsFailed`/`TtsSentenceDone` 恰好一次（US-4）、
    `setStartHandler`/`TtsSentenceStarted`（US-5）、`ScrollController.offset` 单调或 `ensureVisible` 被调
    （US-7~US-9）、`provider` 取值与 `fromCache`（US-10~US-13/US-17/US-18）、设置页 getter 回填
    （US-15）、隐私参数断言（US-20）、`clearVoice` 与 `speak` 成功（US-21）、全量测试（US-22/US-23）；
  - `[真机]`：真正出声、中文语言、音频焦点、release 联网、真实 DeepL——明确标注为人工验收并配清单。
    每条 UI 项标注线框 09/10/08/04-selection 映射；无"体验好/流畅/友好"等不可测措辞。
- [x] **与既有 REQ 无重复**：REQ-003（DeepL Provider/缓存/`translate_set_config`/隐私）与 REQ-005
  （`SystemTtsEngine`/听书页/跟读高亮/句↔Locator/进度）均**复用不重做**；本 REQ 的新增点严格限定为
  平台配置（R1-1/R1-2）、引擎初始化/失败可见/焦点/onStart（R1-4~R1-8）、自动滚动（R1-3）、在线可达与
  回退/读配置（R2-1~R2-3）、标签修正（R2-4）；US-6/US-12/US-19/US-20 明确标注为 REQ-005/REQ-003 的
  **回归验证**而非重复需求；P2（AI 音色/Piper/定时/后台）与 TRANS-03/04/05 显式划出（§1.2/§4）。
- [x] **影响面清单非空**：§3 按"既有功能 / 数据模型·接口 / 听读进度·Locator / 回归面"四类展开，
  覆盖 Android manifest 与构建、TTS 引擎与事件契约、听书页/跟读组件、翻译编排与 Provider、
  API/FFI 与 services/fake、设置页/译文卡片 UI、`settings` 键（无迁移）与 `translation_cache`、
  `translate_get_config` 新桥接、听读进度零模型变更、以及 core/Flutter/FFI/构建/闸门回归面，
  均列具体文件与约束。
