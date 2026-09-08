<!-- wf-meta: req=REQ-006 | phase=architecture | agent=architect | date=2026-09-09 | gate=passed -->
# REQ-006 · 架构决策记录（ADR：在线翻译策略/读配置桥接 / TTS 事件与自动滚动 / Android 平台配置 / 音色回退 / 来源标签）

## 决策（一句话）

在线翻译在 **core `TranslationService` 层**新增虚拟策略 `provider="auto"`（默认值，在线优先 deepl → 失败/无 key 回退 offline，缓存按真实 provider 分行），并新增只读桥接 `translate_get_config` + 写策略桥接 `translate_set_strategy`（**key 只回填固定掩码，绝不回传明文**）；TTS 侧新增 `TtsSentenceStarted`/`TtsVoiceFallback` 事件并**以事件驱动推进（`speak` Future 不参与推进）**，`ListenFollowHighlight` 改 `StatefulWidget` 用 `TextPainter` 计算当前句偏移后 `animateTo`；Android 主清单补 `TTS_SERVICE` query + `INTERNET`；译文卡片按 `provider/fromCache/fallbackReason` 显示"在线/离线/缓存"。

---

## 决策点 1：在线翻译策略与回退（R2-1/R2-3，US-10~US-13/US-16/US-17/US-20）

**现状（已核实）**：`core/src/dict/translation.rs:394-439` 的 `translate_cached` 取 `config.default_provider()`（`store/translation.rs:19-20` 默认 `"offline"`），按名字找唯一 Provider；需 key 且 `provider_key().is_none()` → 直接 `Error::NotConfigured("翻译服务未配置：{name} 未配置 API Key…")`（`:413-417`），**不**回退；`OfflineProvider` 未命中 → `Error::NotConfigured("离线翻译未命中（请先安装内置词库）")`（`provider.rs:127-131`）。`api.rs:160-168` 注册顺序 `[offline, deepl, echo]`。`translate_set_config`（`api.rs:339-347`）语义 = 保存 key + `set_default_provider(provider)`（REQ-003 ADR 关联裁定2）。

### 备选
- **A1（选）：新增虚拟策略 `provider="auto"`，在 `TranslationService` 层编排"在线优先→回退 offline"；`default_provider` 默认值由 `"offline"` 改为 `"auto"`**
  - 做法：`translate_cached` 解析 `strategy = config.default_provider()`；`"auto"` 时按"在线候选（`needs_key()==true`，按注册顺序）→ offline 候选（`needs_key()==false`）"逐候选：先查该候选缓存（命中直返）→ 校验 key → `translate`；首个成功者写缓存并返回，且带回 `fallback_reason`。显式 provider 走"该 provider → offline 兜底"（同样带回 `fallback_reason`）。
  - 优点：策略显式、可测（返回的 `provider` 始终是真实 provider）；缓存键仍是真实 provider（offline/deepl 天然分行，`translation_cache` 零 schema 变更）；隐私面不变（`TranslationProvider::translate` 仍只收 `text/from/to`）；`translate_set_config` 语义零改动（向后兼容）。
  - 缺点：`default_provider()` 的默认返回值从 `"offline"` 变 `"auto"`，**存量断言 1 处需更新**（`store/translation.rs:263` `provider_config_roundtrip`）；需新增 `translate_routed` 返回 `fallback_reason`（不改 `translate_cached` 的 2 元组签名）。
- **A2：修改 `translate_cached` 内部按 provider 逐个尝试（不引入 `auto` 名称）**
  - 做法：保留默认 `"offline"`；`translate_cached` 先试默认 provider，失败/无 key 再试其余在线 provider，最后 offline。
  - 缺点：默认策略不是"在线优先"（默认 offline 时即便配了 key 也先离线，US-13"已配置 key → 在线"需靠 `set_config` 切默认值才成立，语义隐式）；"逐个尝试"的顺序与"谁是默认"耦合，回归面大；US-13 标题的"默认策略"无显式载体。
- **A3：Dart services 层做两段调用（先在线后离线）**
  - 缺点：Provider 计数/参数断言、缓存"失败不写"原子性、隐私断言（US-20）的测试锚点全在 Rust Provider 层（REQ-003 ADR 决策点4 已拒绝 C3）；跨进程两次调用无法保证"失败不写缓存"。**拒绝**。

### 选择与理由
选 **A1**。与 docs/03 §6.3"缓存优先 → 调 Provider → 写缓存"一致；与 REQ-003 的 `TranslationProvider` 同步签名、缓存键 `(原文,from,to,provider)`、隐私约束全部一致；`auto` 只作为"策略名"存在于 `settings` 值域，不注册为 Provider，因此 `find(|p| p.name()==name)` 对显式 provider 行为零变化。唯一代价是默认值字符串变化，用 1 处测试断言更新消解（US-23 已授权"测试预期更新"）。

### 契约细则
- **默认策略解析**：`let strategy = self.config.default_provider()?;`。`strategy == AUTO_PROVIDER("auto")` → auto 路由；否则按 `strategy` 找 Provider 并附加 offline 兜底。未注册/未知 → `Error::NotConfigured("未知翻译 Provider: {name}")`（保留既有文案）。
- **key 语义**：新增 `TranslationProvider::key_is_missing(Option<&str>) -> bool`，默认 `key.is_none()`（Echo 等空串仍视为"已配置"以免破坏 `translate_echo_*`）；`DeepLProvider` 覆写为"`None` 或空白串均视为未配置"（修复 `setConfig('deepl','')` 会带空 key 发请求的问题）。
- **auto 候选顺序**：在线候选 = 注册顺序中 `needs_key()==true` 的 Provider（实际即 `deepl`、`echo`）；离线候选 = `needs_key()==false`（`offline`）。在线候选无 key → 跳过并记录原因；在线候选 `translate` 返回 `NotConfigured/Network` → 记录原因后继续；全部在线候选失败 → 试 offline。
- **缓存顺序（关键）**：先对在线候选逐个 `cache_get`，**任一命中即返回（在线优先）**；在线候选全部未命中后，再对离线候选 `cache_get` → `translate`。避免"offline 先缓存导致配了 deepl 后永远走缓存"。
- **`fallback_reason`**：`Some("在线失败，已回退离线")`（在线被实际尝试且失败）；`Some("未配置在线翻译 API Key，已回退离线")`（无可用 key）；离线作为唯一可用候选（无在线候选/无 key 且未尝试）时仍带后者，便于 US-16 提示。该字段**不进** `Translation` 值对象、**不写缓存**（缓存 JSON 零变化）。
- **`translate_set_config` 向后兼容**：签名与语义（保存 key + 切默认 provider）**完全不变**；策略回切由新增的 `translate_set_strategy` 完成（设置页保存 key 后调用 `setStrategy('auto')`，见决策点2）。
- **错误文案契约**（精确，供断言）：
  - auto 无 key + 离线未命中：`翻译服务未配置：未配置在线翻译 API Key（deepl），且离线翻译未命中（请先安装内置词库）`（含子串"未配置在线翻译 API Key"与"离线翻译未命中"）。
  - auto 在线失败 + 离线未命中：`网络请求失败：在线翻译失败：{detail}；离线翻译未命中（请先安装内置词库）（原文：{text}）`（含子串"在线翻译失败"、"离线翻译未命中"、原文）。
  - 显式 provider 无 key 且无 offline 兜底：`翻译服务未配置：{provider} 未配置 API Key，请先在设置中配置`（保留 REQ-003）。
  - 显式 provider 网络失败且无 offline 兜底：`网络请求失败：{detail}（原文：{text}）`（保留 REQ-003）。
  - 空文本：`待翻译文本为空`（保留）。
- **缓存键 provider 语义**：`CacheKey.provider` 恒为**真实 provider 名**（`offline`/`deepl`/`echo`），同文会生成 offline 与 deepl 两行；`translation_cache` 表与唯一索引零改动。
- **隐私**：`TranslationProvider::translate(text, from, to)` 入参不变；auto 编排不向 Provider/HTTP 追加任何字段；`deepl_body`（`provider.rs:145-154`）零改动，仅 `text/target_lang[/source_lang]`。

### 影响
- `core/src/dict/translation.rs`：新增 `AUTO_PROVIDER`/两个 `FALLBACK_REASON_*` 常量、`RoutedTranslation`、`translate_routed`/`config_view`/`set_strategy`；`translate_cached` 改为委托 `translate_routed`（签名不变）。
- `core/src/dict/mod.rs`：`TranslationProvider` 增默认方法 `key_is_missing`（默认实现，既有 impl 无需改）。
- `core/src/dict/provider.rs`：`DeepLProvider` 覆写 `key_is_missing`。
- `core/src/store/translation.rs`：`DEFAULT_PROVIDER` 由 `"offline"` 改 `"auto"`；对应 1 处单测断言更新。
- 回归面：`core/tests/translate_corpus.rs:210-214`（默认 offline 结果）仍成立（auto→offline）；`:216-254` 显式 echo 路径不变；`api_bridge_*` 缓存行数仍为 2。

### 降级线（授权）
若"`default_provider` 值域扩展"被判定为破坏性（下游有字符串枚举校验）：降级为**独立设置键 `translate.strategy`**（`ProviderConfig` 加带默认实现的 `strategy()/set_strategy()`，默认 `"auto"`），`default_provider` 默认值保持 `"offline"`；`translate_cached` 先读 strategy，`"auto"` 走 auto 路由，其余按 strategy 找 Provider。**缓存键、错误文案、隐私契约、US 断言全部不变**，仅策略载体改变，由 developer 在 T-006 记录 diff。

---

## 决策点 2：读取当前翻译配置的桥接（R2-2，US-15）

**现状（已核实）**：`api.rs` 只有 `translate_set_config`（写），无读通道（`api.rs:339-347`）；`TranslateBackend`（`translate_backend.dart:55-67`）只有 `setConfig`；`rust_translate_backend.dart:72-74` 仅转发写；设置页 `_load`（`settings_page.dart:37-45`）只读词库，key 输入框无回填。

### 备选
- **B1（选）：新增只读桥接 `translate_get_config() -> TranslateConfigView` + 写策略 `translate_set_strategy(strategy)`；`TranslateBackend` 增 `getConfig/setStrategy`；`FakeTranslateBackend` 同步；key 只回填固定掩码 `••••••••` + `has_deepl_key` 标记**
  - 优点：类型化、一次往返；US-15 可断言字段；**不把明文 key 带回 Dart/UI/日志**（安全）；策略与 key 分离，兼容 REQ-003 `setConfig`。
  - 缺点：新增 2 个 FFI（FRB 再生成 + docs 同步）；设置页需 `_keyDirty` 逻辑避免把掩码写回。
- **B2：复用 `translate_set_config` 双向（传入空/哨兵读取）或让 `translate` 附带 config**
  - 缺点：语义污染、`translate` 每次多带配置；无法表达"只读不写"；测试断言困难。**拒绝**。
- **B3：Dart 侧经通用 `settings_get` 读 settings**
  - 缺点：通用 settings 通道在 REQ-005 ADR 决策点6 已确认**未实现**（`api.rs` 无 `settings_get`）；且会把 `translate.key.deepl` 明文带到 Dart 层，违背"key 不离开 Rust/最小暴露"。**拒绝**。

### 选择与理由
选 **B1**。US-15 要求"回填已保存 key（掩码显示）并显示当前 provider/策略"，唯一可同时满足"可读 + 安全 + 不新增通用设置面"的方案；与 REQ-005 `tts_listen_settings_get/set` 的类型化专用通道先例一致。

### 接口契约
```rust
// core/src/api.rs（interface；async，FRB 池线程）
#[derive(Debug)]
pub struct TranslateConfigView {
    pub provider: String,                 // "auto"|"offline"|"deepl"|"echo"（= default_provider）
    pub has_deepl_key: bool,              // key_is_missing 语义（空串=false）
    pub deepl_key_masked: Option<String>, // 固定 "••••••••"；无 key 为 None；绝不返回明文
}
pub async fn translate_get_config() -> Result<TranslateConfigView, String>;
pub async fn translate_set_strategy(strategy: String) -> Result<(), String>;
// set_strategy 校验：strategy ∈ {"auto","offline","deepl","echo"}（且非 auto 须已注册）；未知 → Err("未知翻译策略: {s}")
```
```dart
// app/lib/services/translate_backend.dart（application）
class TranslateConfigData {
  const TranslateConfigData({required this.provider, required this.hasDeeplKey, this.deeplKeyMasked});
  final String provider;
  final bool hasDeeplKey;
  final String? deeplKeyMasked;
}
abstract class TranslateBackend {
  // …既有…
  Future<TranslateConfigData> getConfig();
  Future<void> setStrategy(String strategy);
}
```
- **明文回填 vs 已配置标记**：**只回填固定掩码 + `hasDeeplKey` 标记，不回填明文**。理由：key 是凭据，UI 只需表达"已配置"；`obscureText: true` 下明文也无可见价值；避免 key 进入 widget 状态/崩溃日志/内存转储。设置页用 `_keyDirty` 标记（`onChanged` 置真）保证未编辑时**不写 key**，避免把掩码写回 settings。
- **空 key 保存语义**：用户把输入框清空并保存 = **清除 key**（`setConfig('deepl','')`）+ 提示"已清除 DeepL API Key（当前未配置在线翻译）"；非静默（有明确提示）。同时写策略（默认 `auto`），auto 自动回退离线。

### 影响
- `core/src/api.rs`：新增 DTO + 2 个 async 函数；`TranslationService` 增 `config_view()`/`set_strategy()`；FRB codegen。
- `app/lib/services/translate_backend.dart`/`rust_translate_backend.dart`/`app/test/fake_translate_backend.dart`：同步新方法；`FakeTranslateBackend` 记录 `lastStrategy` 并可配置 `hasDeeplKey`。
- `app/lib/pages/settings_page.dart`：`_load` 调 `getConfig`；新增策略下拉；key 掩码回填 + `_keyDirty`。
- `docs/03 §4`（dict/translate 桥接面）需在开发/交付阶段同步（本阶段不改 docs）。

### 降级线（授权）
若 FRB 对 `Option<String>` 生成障碍：降级 `deepl_key_masked: String`（空串=无 key）；若连"掩码"也判定为敏感：降级为仅 `has_deepl_key: bool`，输入框留空 + hintText"已配置（留空不修改）"。**US-15 的"回填/显示已配置"语义与断言不变**，仅展示形态改变。

---

## 决策点 3：TTS 事件契约扩展与推进语义（R1-6/R1-7，US-4/US-5/US-6）

**现状（已核实）**：`tts_engine.dart:68-80` 的 `sealed class TtsEvent` 只有 `TtsSentenceDone`/`TtsFailed`；`system_tts_engine.dart:15-19` 只注册 completion/cancel/error，**无** `setStartHandler`；`speak`（`:71-75`）`await _tts.speak(chunk.text)` 忽略返回值且未传 `focus`；`ListenPage._onTtsEvent`（`listen_page.dart:138-144`）用 `if/else` 处理两事件。flutter_tts 4.2.5 已核实：`setStartHandler(VoidCallback)`（`flutter_tts.dart:572-574`）由平台 `speak.onStart` 触发（`:603-607`）；`speak(String,{bool focus=false})`（`:354-363`，仅 Android 透传 focus）；`awaitSpeakCompletion(bool)`（`:345-346`）；Android 插件 `speak()` 在 `focus=true` 时 `requestAudioFocus()`（`FlutterTtsPlugin.kt:664-687`），`awaitSpeakCompletion=true` 时 `speak` Future 挂起到 `onDone` 才 `success(1)`（`:320-325`,`:120-123`），出错/停止时**不一定** resolve（`:177-181`,`:136-138`）。

### 备选
- **C1（选）：新增 `TtsSentenceStarted(index)`（onStart）+ `TtsVoiceFallback(requestedVoiceId)`（无匹配音色，US-21 第三句）；`setStartHandler` 接线；`speak` 立即返回、事件驱动推进**
  - 优点：US-5 有明确事件；US-21"系统默认音色"提示有数据来源；避免 `awaitSpeakCompletion(true)` 的 Future 挂起/递归/双推进（风险5）。
  - 缺点：`TtsEvent` 增 2 个子类，`FakeTtsEngine` 与 `_onTtsEvent` 必须同步（穷尽 switch）。
- **C2：只加 `TtsSentenceStarted`，音色可用性复用 `TtsFailed`/不提示**
  - 缺点：US-21 第三句"无匹配时显示系统默认音色"不可达（`TtsFailed` 会被当成朗读失败并触发错误态）。**不满足验收**。
- **C3：不加事件，用 `speak` Future 完成驱动推进（`awaitSpeakCompletion(true)`）**
  - 缺点：R1-7 的 onStart 缺失（US-5 不可达）；Future 与 completion handler 双触发 → 双推进/递归（风险5 明确点名的失败模式）；出错/停止时 Future 可能不 resolve → 卡死。**拒绝**。

### 选择与理由
选 **C1**。事件驱动是唯一与"完成事件恰好一次（US-4）+ 不重复推进（US-6）"同时自洽的模型；`speak` Future 只用于**失败检测**（返回 `0/false` 或抛异常 → `TtsFailed`），不用于推进。

### 契约细则
```dart
// app/lib/engines/tts_engine.dart
sealed class TtsEvent {}
class TtsSentenceStarted extends TtsEvent { TtsSentenceStarted(this.sentenceIndex); final int sentenceIndex; } // 新
class TtsSentenceDone   extends TtsEvent { TtsSentenceDone(this.sentenceIndex);   final int sentenceIndex; }
class TtsVoiceFallback  extends TtsEvent { TtsVoiceFallback(this.requestedVoiceId); final String requestedVoiceId; } // 新
class TtsFailed         extends TtsEvent { TtsFailed(this.message);              final String message; }
```
- **推进语义**：`SystemTtsEngine.speak(chunk)` 设 `_current=chunk` 后 `unawaited(_tts.speak(chunk.text, focus:true).then(_onSpeakResult).catchError(...))` 并**立即返回**；`_onSpeakResult(r)` 仅当 `r==0 || r==false` 时 `_emit(TtsFailed('朗读未开始（引擎忙或不可用）'))`。`TtsSentenceDone` 只由 completion handler 派发（`_onComplete`），`TtsSentenceStarted` 只由 start handler 派发（`_onStart`），互不重复。
- **ListenPage 穷尽处理**（`switch (event)` + `sealed`）：
  - `TtsSentenceStarted(i)`：`i` 合法则 `setState(_index=i)`（确认高亮/滚动锚点），**不** `saveProgress`（听读同进度不变式）。
  - `TtsSentenceDone(i)`：`_saveProgressDebounced(chunks[i].locator)` + 推进 `speak(i+1)`（沿用既有逻辑）。
  - `TtsVoiceFallback`：置 `_voiceFallback=true`（控制条/设置面板显示"系统默认音色"）。
  - `TtsFailed`：既有容错（连续 >5 次停止）。
- **乐观推进**：Done 时仍先 `_index=i+1`（保证 onStart 缺失的平台也推进，US-6 不依赖 Started）；Started 只做确认。
- **`resume`**：走同一 `speak(_current)` 路径（`focus:true`、失败可见），不直接调 `_tts.speak`。

### 影响
- `tts_engine.dart`（interface）：2 个新事件子类。
- `system_tts_engine.dart`（interface）：`setStartHandler`、`_onStart`、`_onSpeakResult`、`resume` 路径统一；只 import `flutter_tts` + `tts_engine.dart`（ddd-rules 不触生成物）。
- `listen_page.dart`（interface）：`_onTtsEvent` 改穷尽 `switch`；新增 `_voiceFallback`。
- `fake_tts_engine.dart`：`emitStarted(i)`/`emitVoiceFallback(id)`。
- 回归：`tts_engine_test.dart` 既有断言（如完成恰好一次、stop 后不派发）继续成立；新增 onStart/失败返回/focus 断言。

### 降级线（授权）
若 `setStartHandler` 在目标平台不触发：`TtsSentenceStarted` 缺失时 `ListenPage` 仍以 Done 的乐观 `_index` 推进（现有行为），Started 仅作增强，US-6/US-8 不因此失败；`TtsVoiceFallback` 若无法可靠判定，则控制条恒显示逻辑音色名（不误导为"已选男/女声"的替代文案由 UI 文案兜底）。

---

## 决策点 4：自动滚动实现（R1-3，US-7/US-8/US-9）

**现状（已核实）**：`listen_follow_highlight.dart:10,29-31` 为 `StatelessWidget` + `SingleChildScrollView` + 单个 `RichText`；无 `ScrollController`/`ensureVisible`；`ListenPage` 使用处 `listen_page.dart:435-441` 只传 `text/highlightStart/highlightEnd`。`RichText` 的 span 无 `RenderObject` 可直接 `ensureVisible`。

### 备选
- **A1（选）：`ListenFollowHighlight` 改 `StatefulWidget`，持（或注入）`ScrollController`，在 `didUpdateWidget` 检测 `highlightStart` 变化 → 用 `TextPainter`（与正文同 `TextStyle`/`textDirection`/`maxWidth`/`textScaler`）对完整 `TextSpan` 布局，取 `getOffsetForCaret`/`getBoxesForSelection` 得到当前句的 y 偏移 → `controller.animateTo`；导出纯函数 `offsetForHighlight(...)` 供单测**
  - 优点：直接解决"span 无法 ensureVisible"；偏移随字符位置单调（US-7 代理①）；`LayoutBuilder` 提供 `maxWidth`，`TextPainter` 与真实排版同参数，精度可控；纯函数可无 widget 单测。
  - 缺点：`TextPainter` 需与 `RichText` 的样式/宽度/`textScaler` 严格一致，否则偏差；换行/超长文本下计算有成本（每句一次布局，句级频率可接受）。
- **A2：父页 `ListenPage` 持 controller 传入，按句序号比例估算 offset**
  - 缺点：`RichText` 自动换行使"比例×maxScrollExtent"与真实句位置偏差大，US-7 单调性在换行不均时可能不成立；父子耦合。
- **A3：把每句拆成独立 `Text.rich`/`WidgetSpan`，用 `GlobalKey` + `Scrollable.ensureVisible` 定位**
  - 优点：`ensureVisible` 语义直接。
  - 缺点：数千句 → 数千 RenderObject，长章性能/内存风险；改变现有渲染结构（`Key('listen-follow-text')` 与既有高亮测试假设被破坏）；与 REQ-005 最小改动冲突。**拒绝**。

### 选择与理由
选 **A1**。US-7 允许"offset 单调"或"锚点可见"两种代理；A1 以"同一 `TextPainter` 布局 → 当前句 y 偏移"提供确定、单调、可纯函数断言的代理，同时不改变 RichText 结构（既有 `Key`/高亮测试零回归）。`controller` 设为**可选注入**（默认内部创建），`listen_page_test.dart:567-579` 的裸构造继续编译。

### 契约与可测代理
```dart
// app/lib/widgets/listen_follow_highlight.dart（interface/widget；ddd-rules 未声明该路径，按 pages 同级纪律）
class ListenFollowHighlight extends StatefulWidget {
  const ListenFollowHighlight({
    super.key, required this.text, required this.highlightStart, required this.highlightEnd,
    this.controller,            // ScrollController?：注入/测试用；null 内部创建
    this.autoScroll = true,     // 关闭可做"不滚动"对照
    this.onScrolled,            // void Function(double offset)?：测试 spy（可选）
  });
  @visibleForTesting
  static double offsetForHighlight({
    required String text, required int highlightStart, required TextStyle style,
    required double maxWidth, required double textScaler, required double viewportHeight,
    required double maxScrollExtent,
  });
}
```
- **可测代理**（US-7）：① `offsetForHighlight` 对递增 `highlightStart` 返回**单调不减**的偏移（纯函数单测）；② widget 测试注入 `ScrollController`，把 `highlightStart` 从句 0 改到句 k（长文本，`maxScrollExtent>0`）后 `pumpAndSettle`，断言 `controller.offset` 增大；回退到更早句时减小（双向）；③ 可选断言 `onScrolled` 被调。
- **US-8/US-9**：`ListenPage` 推进/`_onSeek`/上下句改变 `_index` → `highlightStart/End` 变化 → A1 的 `didUpdateWidget` 触发滚动；widget 测试断言 `ListenFollowHighlight.highlightStart` 与 `controller.offset` 同步变化。

### 影响
- `listen_follow_highlight.dart`：`StatelessWidget` → `StatefulWidget`；新增 `controller/autoScroll/onScrolled` 可选参数与纯函数；`Key('listen-follow-text')` 保留。
- `listen_page.dart`：无需传 controller（默认内部创建）；US-8/9 通过 `_index` 变化自然驱动。
- 回归：既有"越界 clamp 不抛异常"用例仍成立。

### 降级线（授权）
若 `TextPainter` 计算在极端 CJK/emoji/混排下与真实排版偏差导致 offset 抖动：降级为"按当前句 `charStart` 对应的 `TextPainter` 行号 × 行高估算 + 对当前句调用 `RenderObject.showOnScreen` 语义兜底"；**US-7 只要求"offset 单调"或"锚点可见"其一**，降级不改变验收内容。

---

## 决策点 5：Android 平台配置（R1-1/R1-2，US-1/US-2）

**现状（已核实）**：`app/android/app/src/main/AndroidManifest.xml:39-44` 的 `<queries>` 只有 `PROCESS_TEXT`，无 `TTS_SERVICE`；主清单**无** `uses-permission`；`INTERNET` 仅在 `debug/AndroidManifest.xml:6`、`profile/AndroidManifest.xml:6`。`build.gradle.kts:9` `compileSdk=36`、`:23` `targetSdk = flutter.targetSdkVersion`（Flutter 3.47.2 默认 36）。flutter_tts 4.2.5 README:81-91 明示 Android 11+ 需在 `queries` 声明 `android.intent.action.TTS_SERVICE`。

### 备选
- **E1（选）：主清单 `<queries>` 增 `TTS_SERVICE` intent（保留 `PROCESS_TEXT`），并在主清单增 `INTERNET` 权限；debug/profile 清单保留（merger 合并去重）**
  - 优点：release 与 debug/profile 行为一致；最小改动；官方推荐声明方式。
  - 缺点：`INTERNET` 为普通权限，扩大权限面（但本 App 已用 DeepL 在线翻译，功能必需）。
- **E2：只在 debug/profile 声明 / 用 flavor 分清单**
  - 缺点：release APK 在线翻译仍必失败（R1-2 未修）；flavor 引入构建复杂度。**不满足 US-2**。
- **E3：不声明 `TTS_SERVICE`，改用 `getDefaultEngine`/`setEngine` 规避包可见性**
  - 缺点：Android 11+ 包可见性限制下仍可能查不到引擎；非官方路径，行为因 ROM 而异；US-1 的静态断言不成立。**拒绝**。

### 选择与理由
选 **E1**。与 flutter_tts 官方 README 一致，与 `targetSdk=36`（≥30）匹配；`INTERNET` 是本 App 在线翻译的既有功能依赖（REQ-003 已引入 DeepL），补到主清单是修复 release 缺失，不是新增能力。

### 隐私/影响
- `TTS_SERVICE` 是**包可见性声明**（`<queries>`），不授予任何权限、不涉及数据访问；无隐私面。
- `INTERNET` 扩大权限面，但仅被 `DeepLProvider`（`core/src/dict/provider.rs`）使用；无广告/统计 SDK；无后台服务。需在交付文档记录"权限用途"。
- manifest merger：主/debug/profile 三份 `INTERNET` 重复声明由 merger 去重，无冲突；不新增 `TTS_SERVICE` 到 debug/profile（主清单即覆盖全部构建类型）。
- 静态断言（US-1/US-2）：`app/test/android_manifest_test.dart` 纯文本解析主清单，断言含 `android.intent.action.TTS_SERVICE`、`android.permission.INTERNET`，且 `PROCESS_TEXT` 仍在；`build.gradle.kts` 断言 `targetSdk` 使用 `flutter.targetSdkVersion`（或注释记录 ≥30）。

### 降级线（授权）
若某 ROM 声明 `TTS_SERVICE` 后仍找不到引擎：US-4 保证"失败可见（`TtsFailed`）"而非静默；真机清单记录该 ROM 型号与引擎安装引导。若 manifest merger 出现冲突（罕见）：把 `TTS_SERVICE` 同时补到 debug/profile 清单，主清单保留。

---

## 决策点 6：音色回退与语言/焦点（R1-4/R1-5/R1-8，US-3/US-4/US-21）

**现状（已核实）**：`system_tts_engine.dart:32-38` `configure` 只 `setSpeechRate`+`setVoice`，无 `setLanguage`/`awaitSpeakCompletion`；`:41-55` `_pickVoice` 返回 null 时 `voice ??= {'name': voiceId, 'locale':'zh-CN'}` 把逻辑名当真实音色名；`:72-75` `speak` 未传 `focus` 且忽略返回值。插件已核实：`setLanguage` 不可用返回 `0`（不抛错，`FlutterTtsPlugin.kt:504-512`）；`setVoice` 找不到返回 `0`（静默，`:514-526`）；`clearVoice()` 恢复默认音色返回 `1`（`:528-531`）；`speak` 在 `focus=true` 时请求音频焦点（`:664-687`）。

### 备选
- **F1（选）：语言固定常量 `'zh-CN'`；`configure` 顺序 `awaitSpeakCompletion(true)` → `setLanguage('zh-CN')` → `setSpeechRate(speed)` → `_applyVoice`；`_applyVoice` 匹配则 `setVoice`（返回 0 也 `clearVoice` 兜底），无匹配/异常 → `clearVoice()` + `TtsVoiceFallback`；`speak(focus:true)`，返回 `0/false` 或异常 → `TtsFailed`**
  - 优点：直接修 R1-4/R1-5/R1-6/R1-8；US-3 的调用序列/顺序可断言；US-21 的 `clearVoice` 与"系统默认音色"提示可达；不新增设置项。
  - 缺点：语言固定 `zh-CN`，英文书朗读语言不随书（记入 tradeoff，后续 REQ）。
- **F2：语言取设置项（新增 `listen.language`）**
  - 缺点：超出 US 范围（无验收要求）；新增设置键/UI；与 REQ-005 `ListenSettingsData` 契约冲突（字段扩展）。**本期不做**。
- **F3：保留"逻辑名当真实音色名"回退**
  - 缺点：R1-5 已知缺陷（男女声切换失效）；US-21 直接失败。**拒绝**。

### 选择与理由
选 **F1**。US-3 明确允许"固定值，测试断言具体值"；`setLanguage` 返回 0 不抛错，故用 try/catch + 返回值双重兜底，保证"平台不支持时不阻断 `speak`"（US-3 第二句）。`clearVoice()` 是插件提供的"恢复默认音色"正解（非传无效逻辑名）。

### 契约细则
- `setLanguage('zh-CN')`：常量 `SystemTtsEngine.language = 'zh-CN'`；`await` 后若返回 `0`，不抛错（可记 warning），继续后续步骤。
- `awaitSpeakCompletion(true)`：作为平台设置调用（满足 US-3）；**不**用它来推进（见决策点3）。
- `speak(focus: true)`：Android 透传；桌面/iOS 由插件忽略（无副作用）。
- 返回值/异常：`r==0 || r==false` → `TtsFailed('朗读未开始（引擎忙或不可用）')`；`catchError` → `TtsFailed('$e')`；`onError` 回调 → `TtsFailed('$message')`（既有）。
- 音色：`_pickVoice` 命中 → `setVoice({name, locale})`；返回 0 → `clearVoice()` + `TtsVoiceFallback(voiceId)`；无命中/`getVoices` 抛错/非 List → `clearVoice()` + `TtsVoiceFallback(voiceId)`；`setVoice` 抛错 → `clearVoice()` + `TtsVoiceFallback(voiceId)`。

### 影响
- `system_tts_engine.dart`：上述调用序列与返回值处理；新增 `setStartHandler`。
- `listen_control_bar.dart`/`listen_settings_sheet.dart`：新增可选 `voiceFallback` 参数（默认 false），为真时显示"系统默认音色"；既有测试零回归。
- `tts_engine_test.dart`：`tts_engine_test.dart:187-214` 现断言回退音色名为 `system_female`/`system_male`，需按 US-21 更新为"调用 `clearVoice`/不传逻辑名且仍能 `speak`"（US-23 已明确此属**测试预期更新**，不改 REQ-005 对外行为契约）。

### 降级线（授权）
若某平台 `clearVoice()` 不可用/抛错：降级为"不调用任何 `setVoice`，保持系统默认音色"，并仍发 `TtsVoiceFallback`；US-21 断言"不调用 `setVoice(逻辑名)` 且 `speak` 仍被调用"不受影响。

---

## 决策点 7：译文来源标签（R2-4，US-18）

**现状（已核实）**：`translation_popup.dart:31-46` 对 `fromCache` 显示"缓存"，否则一律"在线"，offline 结果被误标"在线"；provider 名另起一栏显示。线框 08（`08-translation.svg:31`）示例为"DeepL · 命中缓存"。

### 备选
- **G1（选）：`TranslationResultCard` 按 `fromCache` / `provider` / `fallbackReason` 映射文案：`fromCache → "缓存"`；`provider=="offline" → "离线"`；其余 → "在线"；始终显示 provider 名；`fallbackReason != null` 时追加回退提示行**
  - 优点：US-18 三条断言全部可达；与线框 08 的"DeepL · 命中缓存"语义一致（徽标+provider）；不改布局。
  - 缺点：golden/截图测试可能需同步（US-18 已预警）。
- **G2：只修"缓存"分支，provider 仍不参与标签**
  - 缺点：offline 仍被标"在线"，US-18 失败。
- **G3：用颜色/图标区分在线/离线/缓存**
  - 缺点：线框 08 是文字标签；颜色对可访问性不友好；US-18 断言"显示'在线'/'离线'/'缓存'"文字不成立。**拒绝**。

### 选择与理由
选 **G1**。线框 08 的标签是文字（"命中缓存"），US-18 明确要求显示"在线/离线/缓存"文字 + provider 名；最小改动即可满足，不触碰布局。

### 契约
- 标签映射：`fromCache==true` → `缓存`；否则 `provider=="offline"` → `离线`；否则 → `在线`。
- provider 名始终显示（`deepl`/`offline`/`echo`）。
- `fallbackReason != null` → 卡片底部显示该原因（"在线失败，已回退离线" / "未配置在线翻译 API Key，已回退离线"）。
- 数据来源：`TranslationData.fallbackReason`（由决策点1的 `RoutedTranslation.fallback_reason` 经 `TranslationView` 桥接）。

### 影响
- `translation_popup.dart`：标签逻辑 + 回退提示；`TranslationResultCard` 构造不变（`TranslationData` 新增可选字段）。
- `translate_backend.dart`：`TranslationData` 增 `String? fallbackReason`（可选，默认 null → 既有构造零回归）。
- `rust_translate_backend.dart`：从 `TranslationView.fallbackReason` 映射。
- golden/截图测试：若标签变更触发差异，按 US-18 更新并复核线框 08。

### 降级线（授权）
若 golden 对比成本过高：仅保留"缓存/离线/在线"三态文字标签，回退提示改用 `OverlayError` 之外的次要文本；**US-18 的标签断言不变**。

---

## 关联裁定（次要决策，供 02-design/02-plan 引用）

1. **P1 范围**：US-5（onStart）、US-18（标签）、US-21（音色回退）为 P1，P0 全绿后补；任务拆分中已标注。
2. **`translate_set_config` 兼容**：语义（保存 key + 切默认 provider）不变；策略回切由 `translate_set_strategy` 完成（设置页保存 key 后调用 `setStrategy('auto')`，若用户在 UI 选了显式 provider 则写该值）。
3. **默认策略**：`translate.default_provider` 默认值 `"offline"` → `"auto"`；键名不变，值域扩展。存量单测 `provider_config_roundtrip` 的 1 处断言更新。
4. **长文本**：DeepL 单请求约 128 KiB；本期**不自动分段**，超限由 Provider 返回网络/HTTP 错误 → auto 回退离线，离线未命中则明确错误 + 可重试（US-11 允许）。
5. **key 安全**：仅掩码回填；明文永不出 Rust；settings 表仍明文存储（本期不做钥匙串，沿用 REQ-003 已知限制，记入交付文档）。
6. **语言**：`setLanguage('zh-CN')` 固定；多语言朗读留后续 REQ。
7. **TTS 事件**：`TtsSentenceStarted`/`TtsVoiceFallback` 均**不**写盘；`reading_progress` 仍是唯一进度事实源。
8. **`TtsEvent` 穷尽性**：`sealed` + `switch` 编译期检查；新增事件时 `_onTtsEvent` 不补分支会编译失败（防止遗漏）。
9. **文档同步**：`docs/03 §4/§13`、`docs/04 §7/§9.5` 需同步新增 FFI/DTO/事件/默认策略；本阶段按纪律**只写 3 份产物，不改 docs**，标记为开发/交付阶段风险。
10. **范围划界**：AI 音色/Piper/克隆/定时/后台/媒体键/点读/TRANS-03/04/05 不做（沿用 REQ-005 禁用占位）。

## 影响汇总
- **Rust**：`core/src/dict/translation.rs`（auto 路由/回退/错误文案/config_view/set_strategy）、`core/src/dict/mod.rs`（`key_is_missing` 默认方法）、`core/src/dict/provider.rs`（DeepL 覆写）、`core/src/store/translation.rs`（默认值 auto）、`core/src/api.rs`（`TranslateConfigView`、`TranslationView.fallback_reason`、2 个新 async FFI、`translate` 内部改 `translate_routed`）；`translation_cache`/`settings` 表结构零改动；`user_version` 保持 3。
- **Dart**：`engines/tts_engine.dart`（2 事件）、`engines/system_tts_engine.dart`（初始化/失败/焦点/音色/onStart）、`widgets/listen_follow_highlight.dart`（Stateful + 滚动）、`pages/listen_page.dart`（事件穷尽 + 音色标签）、`widgets/listen_control_bar.dart`/`listen_settings_sheet.dart`（voiceFallback 可选参数）、`services/translate_backend.dart`+`rust_translate_backend.dart`（getConfig/setStrategy/fallbackReason）、`pages/settings_page.dart`（策略下拉 + key 掩码回填）、`widgets/translation_popup.dart`（标签）；`test/fake_tts_engine.dart`/`fake_translate_backend.dart` 同步。
- **Android**：`app/android/app/src/main/AndroidManifest.xml`（TTS_SERVICE query + INTERNET）。
- **回归面**：core 全量（含 `translate_corpus.rs`/`tts_api.rs`）、Flutter widget/FFI/goldens、Android manifest 静态断言、CRAP/DDD 闸门。

## flutter_tts 4.2.5 真实 API（已核实，供实现/测试引用）
- `Future<dynamic> speak(String text, {bool focus = false})`：仅 Android 透传 `focus`（`flutter_tts.dart:354-363`）；Android 插件 `speak` 返回 `tts.speak(...) == 0` 的布尔（`FlutterTtsPlugin.kt:680`），服务不可用时重建引擎并返回 `false`（`:682-686`）；`awaitSpeakCompletion(true)` 且 `QUEUE_FLUSH` 时 Dart Future 挂起到 `onDone` 才 `success(1)`（`:320-325`,`:120-123`），`onError`/`onStop` 路径不保证 resolve（`:136-138`,`:177-181`）。
- `Future<dynamic> setLanguage(String language)`：Android 用 `Locale.forLanguageTag`，不可用返回 `0`（不抛错，`FlutterTtsPlugin.kt:504-512`）。
- `Future<dynamic> awaitSpeakCompletion(bool awaitCompletion)`（`flutter_tts.dart:345-346`）。
- `Future<dynamic> setSpeechRate(double rate)`（`:390-391`）；`Future<dynamic> setVoice(Map<String,String> voice)`（`:477-478`）找不到返回 `0`（静默，`FlutterTtsPlugin.kt:514-526`）；`Future<dynamic> clearVoice()`（`:481-482`）恢复默认音色返回 `1`（`FlutterTtsPlugin.kt:528-531`）。
- `void setStartHandler(VoidCallback callback)`（`:572-574`），平台 `speak.onStart` 触发（`:603-607`）；`setCompletionHandler`/`setErrorHandler`/`setCancelHandler` 既有。
- `Future<dynamic> get getVoices`（`:523-526`，返回 `List<Map>`，元素含 `name`/`locale`，iOS 另有 quality/gender/identifier）。
- `requestAudioFocus()` 仅在 `focus=true` 时调用（`FlutterTtsPlugin.kt:668-670`）。

## 闸门2 自评（ADR 部分）
- [x] **备选 ≥2 且给出理由**：7 个决策点均含 ≥2 备选（1: A1/A2/A3；2: B1/B2/B3；3: C1/C2/C3；4: A1/A2/A3；5: E1/E2/E3；6: F1/F2/F3；7: G1/G2/G3），每个给出选择理由与拒绝论证，且每点含降级线授权。
- [x] **与既有约定一致**：docs/03 §4/§6.3/§13、docs/04 §1/§5/§7/§9、REQ-003 ADR（同步 Provider/缓存键/隐私/`translate_set_config`）、REQ-005 ADR（TtsEngine 分层/听读同进度/线框 09-10）全部对齐；唯一存量断言更新（`provider_config_roundtrip` 默认值）已列处置。
- [x] **原型权威**：决策点 3/4/5/6/7 与线框 09/10/08/03 及 `reader-ui-v2/04-selection.svg` 逐项对应（详见 02-design §6）；未自创布局。
- [ ] **待同步项（非本阶段闸门项）**：`docs/03`/`docs/04` 文档同步在开发/交付阶段完成，本阶段只产出 3 份产物。
