<!-- wf-meta: req=REQ-006 | phase=architecture | agent=architect | date=2026-09-09 | gate=passed -->
# REQ-006 · 模块/接口设计（听书发声+自动滚动 / 在线翻译策略+回退+读配置）

> 依据：`01-req.md`（US-1..US-23、R1-1..R1-8、R2-1..R2-4）、`02-adr.md`（7 个决策点）、`docs/03`（§4/§6.3/§13）、`docs/04`（§1/§5/§7/§9）、REQ-003/REQ-005 ADR。
> 本阶段只写文档，不改任何代码/配置/线框。

---

## 1. 模块与职责变化

| 模块/文件 | 层级（ddd-rules） | 变化 | 对应 US |
|---|---|---|---|
| `core/src/dict/translation.rs` | domain | `TranslationService` 增 `translate_routed`（auto 路由/回退）、`config_view`、`set_strategy`；`translate_cached` 委托且签名不变；新增 `AUTO_PROVIDER`/`FALLBACK_REASON_*` 常量与 `RoutedTranslation` | US-10~US-13/US-16/US-17 |
| `core/src/dict/mod.rs` | domain | `TranslationProvider` 增默认方法 `key_is_missing(Option<&str>) -> bool`（既有 impl 零改动） | US-13/US-16 |
| `core/src/dict/provider.rs` | domain | `DeepLProvider` 覆写 `key_is_missing`（空白 key 视为未配置）；`OfflineProvider`/`deepl_body` 零改动 | US-13/US-16/US-20 |
| `core/src/store/translation.rs` | infrastructure | `DEFAULT_PROVIDER` 由 `"offline"` 改 `"auto"`（键名不变，值域扩展）；1 处单测断言更新 | US-13 |
| `core/src/api.rs` | interface | `translate` 内部改调 `translate_routed` 并回填 `TranslationView.fallback_reason`；新增 `TranslateConfigView` + `translate_get_config`/`translate_set_strategy`（async） | US-10/US-15/US-17 |
| `app/lib/engines/tts_engine.dart` | interface | `TtsEvent` 增 `TtsSentenceStarted`/`TtsVoiceFallback`（sealed） | US-5/US-21 |
| `app/lib/engines/system_tts_engine.dart` | interface | `configure` 增 `awaitSpeakCompletion(true)`/`setLanguage('zh-CN')`；`setStartHandler` 接线；`speak(focus:true)` + 返回值/异常→`TtsFailed`；音色无匹配→`clearVoice()`+`TtsVoiceFallback`；`speak` 立即返回（事件驱动） | US-3/US-4/US-5/US-21 |
| `app/lib/widgets/listen_follow_highlight.dart` | 未声明层（按 pages 同级纪律） | `StatelessWidget`→`StatefulWidget`，注入/内部持 `ScrollController`，`didUpdateWidget` 用 `TextPainter` 计算偏移并 `animateTo`；导出纯函数 `offsetForHighlight` | US-7 |
| `app/lib/pages/listen_page.dart` | interface | `_onTtsEvent` 改穷尽 `switch`（4 类事件）；`TtsSentenceStarted` 只更新高亮/滚动锚点（不写盘）；`_voiceFallback` 驱动音色标签 | US-5/US-8/US-9/US-21 |
| `app/lib/widgets/listen_control_bar.dart` / `listen_settings_sheet.dart` | 未声明层（同上） | 新增可选 `voiceFallback`（默认 false），为真显示"系统默认音色" | US-21 |
| `app/lib/services/translate_backend.dart` | application | 增 `TranslateConfigData`、`getConfig()`、`setStrategy()`；`TranslationData` 增可选 `fallbackReason` | US-15/US-17/US-18 |
| `app/lib/services/rust_translate_backend.dart` | application | 转发 `getConfig`/`setStrategy`；映射 `fallbackReason` | US-15/US-17 |
| `app/lib/pages/settings_page.dart` | interface | "词典与翻译"区块增策略下拉 + key 掩码回填（`_keyDirty`）+ 空 key 清除语义 | US-15 |
| `app/lib/widgets/translation_popup.dart` | 未声明层（同上） | `TranslationResultCard` 按 `fromCache/provider/fallbackReason` 显示"在线/离线/缓存" + 回退提示 | US-18 |
| `app/android/app/src/main/AndroidManifest.xml` | 构建期接口 | `<queries>` 增 `TTS_SERVICE`；增 `INTERNET` 权限 | US-1/US-2 |
| `app/test/fake_tts_engine.dart` / `fake_translate_backend.dart` | 测试 | 同步新事件/新后端方法 | US-22 |

**分层合规**（ddd-rules.toml 冻结，零改动）：
- `core/src/dict/**`（domain）新增代码只 `use crate::types`/`crate::error`/`crate::dict`，**不**触 `crate::store|api|library`；auto 路由经既有 `ProviderConfig`/`TranslationCacheRepository` 契约。
- `core/src/api.rs`（interface）可 `use crate::dict`/`crate::library`（interface 无 `forbid_internal`）。
- `app/lib/engines/**`（interface）新增/修改只 import `flutter_tts` + `tts_engine.dart`，**不** import `package:reader_app/src/rust/`/`src/rust/`。
- `app/lib/pages/**`（interface）经 `services` 取 DTO，**不**直接触生成物。
- `app/lib/services/**`（application）负责生成物→DTO；不 import `rusqlite/zip/quick-xml`。
- `app/lib/widgets/**` 未被 ddd-rules 声明（同 REQ-005）：处置 = 规则表零改动，按 pages 同级纪律（只经 services/engines、禁 `src/rust/`），03-review 人工核对 import 面。

---

## 2. 接口签名（Rust / Dart）

### 2.1 Rust · domain（`core/src/dict`）

```rust
// core/src/dict/mod.rs
pub trait TranslationProvider: Send {
    fn name(&self) -> &str;
    fn translate(&self, text: &str, from: Lang, to: Lang) -> Result<Translation>;
    fn configure(&mut self, _key: Option<&str>) {}
    fn needs_key(&self) -> bool { true }
    /// 新增（REQ-006）：空/空白 key 是否视为未配置。
    /// 默认仅 None 视为未配置（Echo 的 `Some("")` 演示语义不变）；
    /// DeepLProvider 覆写为 None 或空白串均视为未配置。
    fn key_is_missing(&self, key: Option<&str>) -> bool { key.is_none() }
}
```

```rust
// core/src/dict/provider.rs
impl TranslationProvider for DeepLProvider {
    fn key_is_missing(&self, key: Option<&str>) -> bool {
        key.map(|k| k.trim().is_empty()).unwrap_or(true)
    }
}
// OfflineProvider::needs_key() == false（既有）；EchoProvider 用默认 key_is_missing（既有行为不变）
```

```rust
// core/src/dict/translation.rs
pub const AUTO_PROVIDER: &str = "auto";
pub const FALLBACK_REASON_ONLINE_FAILED: &str = "在线失败，已回退离线";
pub const FALLBACK_REASON_ONLINE_UNCONFIGURED: &str = "未配置在线翻译 API Key，已回退离线";

/// 路由结果（fallback_reason 不进 Translation 值对象、不写缓存）
pub struct RoutedTranslation {
    pub translation: Translation,
    pub from_cache: bool,
    pub fallback_reason: Option<String>,
}

pub struct TranslateConfig {
    pub provider: String,      // "auto"|"offline"|"deepl"|"echo"
    pub has_deepl_key: bool,
}

impl TranslationService {
    pub fn new(cache: Box<dyn TranslationCacheRepository + Send>,
               config: Box<dyn ProviderConfig + Send>,
               providers: Vec<Box<dyn TranslationProvider>>) -> Self;      // 不变

    /// 新增：策略路由（auto 在线优先→回退；显式 provider→offline 兜底）
    pub fn translate_routed(&mut self, text: &str, from: Lang, to: Lang)
        -> Result<RoutedTranslation>;

    /// 保留：REQ-003 签名/语义不变（丢弃 fallback_reason）
    pub fn translate_cached(&mut self, text: &str, from: Lang, to: Lang)
        -> Result<(Translation, bool)>;

    pub fn translate(&mut self, text: &str, from: Lang, to: Lang) -> Result<Translation>; // 不变
    pub fn clear_cache(&mut self) -> Result<()>;                                          // 不变
    pub fn set_config(&mut self, provider: &str, key: &str) -> Result<()>;                // 不变

    /// 新增：读配置视图（供 translate_get_config）
    pub fn config_view(&self) -> Result<TranslateConfig>;
    /// 新增：设置策略（auto/已注册 provider），未知 → Err(Other("未知翻译策略: {s}"))
    pub fn set_strategy(&mut self, strategy: &str) -> Result<()>;
}
```

**`translate_routed` 伪代码（策略解析核心）**
```
norm = normalize_text(text);  norm 为空 → Err(Other("待翻译文本为空"))
strategy = config.default_provider()?
if strategy == AUTO_PROVIDER:
    online  = providers.filter(needs_key)            // 注册顺序：deepl, echo
    offline = providers.filter(!needs_key)           // offline
else:
    p = providers.find(name==strategy) or Err(NotConfigured("未知翻译 Provider: {strategy}"))
    online  = [p]
    offline = providers.filter(!needs_key)           // 显式 provider 亦有 offline 兜底

// 1) 在线优先：逐个候选先查缓存
for c in online:
    key = CacheKey{norm, from, to, provider:c.name()}
    if let Some(e)=cache.cache_get(&key)?: cache.cache_incr_hit(&key)?; return Ok(e.result, true, None)
// 2) 在线未命中：逐个候选尝试翻译
online_attempted=false; online_error=None; online_unconfigured=false
for c in online:
    if c.needs_key() && c.key_is_missing(config.provider_key(c.name())?.as_deref()):
        online_unconfigured=true; continue
    online_attempted=true
    match c.translate(&norm, from, to):
        Ok(t) => cache.cache_put(...provider:c.name()...); return Ok(t, false, None)
        Err(e) => online_error=Some(e)          // 继续下一个在线候选
// 3) 回退 offline（先缓存后翻译）
for c in offline:
    key = CacheKey{...provider:c.name()}
    if let Some(e)=cache.cache_get(&key)?: cache.cache_incr_hit(&key)?;
        return Ok(e.result, true, fallback_reason(online_error, online_unconfigured))
    match c.translate(&norm, from, to):
        Ok(t) => cache.cache_put(...); return Ok(t, false, fallback_reason(...))
        Err(e) => offline_error=Some(e)
// 4) 全部失败 → 组合错误（见 §8 文案契约）
if let Some(ne)=online_error:
    Err(Network{ detail: format!("在线翻译失败：{ne}；离线翻译未命中（请先安装内置词库）"), source_text:text })
else if online_unconfigured:
    Err(NotConfigured("翻译服务未配置：未配置在线翻译 API Key（deepl），且离线翻译未命中（请先安装内置词库）"))
else:
    Err(offline_error.unwrap_or(NotConfigured("离线翻译未命中（请先安装内置词库）")))
```
> 说明：`fallback_reason(...)` = 有 `online_error` → `FALLBACK_REASON_ONLINE_FAILED`；否则若 `online_unconfigured` → `FALLBACK_REASON_ONLINE_UNCONFIGURED`；否则 `None`。

### 2.2 Rust · interface（`core/src/api.rs`）

```rust
#[derive(Debug)]
pub struct TranslationView {
    pub text: String,
    pub from: String,
    pub to: String,
    pub provider: String,
    pub from_cache: bool,
    pub fallback_reason: Option<String>,   // 新增
}

#[derive(Debug)]
pub struct TranslateConfigView {
    pub provider: String,                  // "auto"|"offline"|"deepl"|"echo"
    pub has_deepl_key: bool,               // key_is_missing 语义
    pub deepl_key_masked: Option<String>,  // 固定 "••••••••"；无 key 为 None；绝不返回明文
}

pub async fn translate(text: String, from: String, to: String)
    -> std::result::Result<TranslationView, String>;   // 签名不变，内部 translate_routed
pub async fn translate_get_config()
    -> std::result::Result<TranslateConfigView, String>;   // 新增
pub async fn translate_set_strategy(strategy: String)
    -> std::result::Result<(), String>;                    // 新增
// translate_set_config(provider, key) 签名/语义不变（REQ-003 关联裁定2）
```

### 2.3 Dart · interface / application

```dart
// app/lib/engines/tts_engine.dart（interface）
sealed class TtsEvent {}
class TtsSentenceStarted extends TtsEvent { TtsSentenceStarted(this.sentenceIndex); final int sentenceIndex; }
class TtsSentenceDone    extends TtsEvent { TtsSentenceDone(this.sentenceIndex);    final int sentenceIndex; }
class TtsVoiceFallback   extends TtsEvent { TtsVoiceFallback(this.requestedVoiceId); final String requestedVoiceId; }
class TtsFailed          extends TtsEvent { TtsFailed(this.message);               final String message; }
```

```dart
// app/lib/engines/system_tts_engine.dart（interface）
class SystemTtsEngine implements TtsEngine {
  SystemTtsEngine({FlutterTts? tts});
  static const String language = 'zh-CN';
  // configure(voiceId, speed):
  //   awaitSpeakCompletion(true)   [try/catch，返回值忽略]
  //   setLanguage(language)        [try/catch；返回 0 不抛错、不阻断]
  //   setSpeechRate(speed)
  //   _applyVoice(voiceId)         [匹配→setVoice(name,locale)；否则/返回0/异常→clearVoice()+TtsVoiceFallback]
  // speak(chunk):
  //   _current = chunk;
  //   unawaited(_tts.speak(chunk.text, focus: true)
  //       .then((r) { if (r == 0 || r == false) _emit(TtsFailed('朗读未开始（引擎忙或不可用）')); })
  //       .catchError((e) => _emit(TtsFailed('$e'))));
  //   // 立即返回；推进只由 TtsSentenceDone 事件驱动
  // resume(): 走 speak(_current)（focus:true，失败可见）
  // 新 handler: setStartHandler(_onStart) → _emit(TtsSentenceStarted(_current!.index))
}
```

```dart
// app/lib/widgets/listen_follow_highlight.dart（widget）
class ListenFollowHighlight extends StatefulWidget {
  const ListenFollowHighlight({
    super.key,
    required this.text,
    required this.highlightStart,
    required this.highlightEnd,
    this.controller,        // ScrollController?（注入/测试；null 内部创建）
    this.autoScroll = true,
    this.onScrolled,        // void Function(double offset)?
  });
  @visibleForTesting
  static double offsetForHighlight({
    required String text, required int highlightStart, required TextStyle style,
    required double maxWidth, required double textScaler, required double viewportHeight,
    required double maxScrollExtent,
  });
}
// didUpdateWidget: oldWidget.highlightStart != widget.highlightStart && autoScroll
//   → offset = offsetForHighlight(...)（TextPainter 布局整段 TextSpan，取当前句 y）
//   → controller.animateTo(offset.clamp(0, maxScrollExtent), duration: 200ms, curve: easeOut)
```

```dart
// app/lib/services/translate_backend.dart（application）
class TranslateConfigData {
  const TranslateConfigData({required this.provider, required this.hasDeeplKey, this.deeplKeyMasked});
  final String provider;
  final bool hasDeeplKey;
  final String? deeplKeyMasked;
}
class TranslationData {
  const TranslationData({required this.text, required this.from, required this.to,
    required this.provider, required this.fromCache, this.fallbackReason});
  final String text, from, to, provider;
  final bool fromCache;
  final String? fallbackReason;   // 新增（可选，默认 null → 既有构造零回归）
}
abstract class TranslateBackend {
  // …既有 installDict/removeDict/listDicts/lookup/translate/clearCache/setConfig…
  Future<TranslateConfigData> getConfig();
  Future<void> setStrategy(String strategy);
}
```

```dart
// app/lib/pages/settings_page.dart（interface，线框 03"翻译与词典"区块内）
// _load(): listDicts() + getConfig() → _strategy/provider、_hasKey、deepl_key_masked 回填
// 新增控件：DropdownButtonFormField<String>「翻译策略」：auto（自动·在线优先）/ offline / deepl / echo
// key 输入：obscureText:true；已配置时 controller.text='••••••••'，_keyDirty=false
//   onChanged → _keyDirty=true
// _saveKey():
//   if (_keyDirty) { trimmed.isEmpty ? setConfig('deepl','')（清除+提示） : setConfig('deepl', trimmed) }
//   await setStrategy(_strategy);   // 默认 'auto'
//   await _load();                  // 回填最新配置
```

```dart
// app/lib/widgets/translation_popup.dart（widget）
// TranslationResultCard: 标签 = fromCache?'缓存' : provider=='offline'?'离线' : '在线'
//   始终显示 provider 名；fallbackReason!=null → 底部追加提示行
```

---

## 3. 数据模型变化

| 项 | 变化 | 说明 |
|---|---|---|
| `settings` 表 | **无 schema 变更**；复用键 `translate.default_provider`，值域扩展 `"auto"`（默认值由 `"offline"` 改 `"auto"`）；`translate.key.deepl` 不变 | 无新键、无新表 |
| `translation_cache` 表 | **无变更** | 缓存键 `(source_text, from_lang, to_lang, provider)` 天然区分 offline/deepl 分行 |
| `user_version` | **不变，保持 3** | 无迁移 |
| `reading_progress` / `listen.*` | **不变** | 听读同进度；`ListenSettingsData` 字段不变 |
| 领域值对象 `Translation` | **不变** | 不新增 `fallback_reason`（该字段属请求结果，不进缓存 JSON，避免旧缓存行反序列化问题） |
| 桥接 DTO | 新增 `TranslateConfigView`；`TranslationView` 增 `fallback_reason: Option<String>` | FRB 再生成 |
| Dart DTO | 新增 `TranslateConfigData`；`TranslationData` 增可选 `fallbackReason` | 可选参数，既有构造零回归 |
| Android manifest | 新增 `TTS_SERVICE` query + `INTERNET` | 构建期接口 |

---

## 4. 关键时序

### 4.1 TTS：configure → speak → onStart → 高亮/滚动 → onComplete → 下一句 → 写进度

```
ListenPage.initState
  → 订阅 engine.events（broadcast，先订阅后 configure/speak）
  → _init(): loadListenSettings → openBook → segment → sentenceIndexAt → engine.configure(voiceId, speed)
        └─ SystemTtsEngine.configure: awaitSpeakCompletion(true) → setLanguage('zh-CN')
             → setSpeechRate(speed) → _applyVoice（匹配→setVoice；否则→clearVoice+TtsVoiceFallback）
  → engine.speak(chunks[start], focus:true)          [立即返回；不 await 完成]
  ┌─ 平台 speak.onStart ──▶ _onStart → _emit(TtsSentenceStarted(start))
  │     → ListenPage._onTtsEvent: setState(_index=start)（确认高亮/滚动锚点，不写盘）
  │     → ListenFollowHighlight.didUpdateWidget → offsetForHighlight → controller.animateTo
  └─ 平台 speak.onComplete ─▶ _onComplete → _emit(TtsSentenceDone(start))
        → ListenPage._handleSentenceDone(start):
             _saveProgressDebounced(chunks[start].locator)   [300ms 防抖，不额外写盘]
             i+1<N → setState(_index=i+1) → engine.speak(chunks[i+1])
             i+1==N && autoNext → _loadNextChapter()（segment 下一章 + speak 首句 + saveProgress(nextHref,0)）
             i+1==N && !autoNext → Stopped
  失败：_onSpeakResult(0/false)/catchError/onError → TtsFailed → ListenPage 提示 + 连续 >5 次停止
```
- **唯一推进源 = `TtsSentenceDone`**；`TtsSentenceStarted` 只做高亮/滚动确认；`speak` Future 只做失败检测。
- **写盘只在句完成/拖动松手/退出强刷**；`TtsSentenceStarted`/`TtsVoiceFallback` 不写盘（Locator 不变式）。

### 4.2 翻译：选择 → 策略路由 → 缓存 → Provider → 回退 → UI 标签

```
ReaderPage 选中文本 → TranslateBackend.translate(text, from:'auto', to:'zh')
  → rust.translate(text, from, to)   [async，FRB 池线程]
      → TranslationService.translate_routed(norm, from, to)
          strategy = config.default_provider()        // 默认 "auto"
          ┌ strategy=="auto"
          │   在线候选（deepl, echo）逐个 cache_get → 命中即返回（provider=真实名, from_cache=true）
          │   未命中 → 逐个校验 key（key_is_missing）→ provider.translate
          │      成功 → cache_put(provider=真实名) → 返回（from_cache=false, fallback=None）
          │      失败/无 key → 记录原因
          │   在线全败 → offline 候选 cache_get → 命中返回（fallback=原因）
          │            → offline.translate → 成功 cache_put → 返回（fallback=原因）
          │            → 失败 → 组合错误（§8）
          └ strategy!="auto" → 该 provider + offline 兜底（同上，fallback 语义一致）
      → TranslationView{text, from, to, provider, from_cache, fallback_reason}
  → TranslationData{...}
  → TranslationResultCard 标签：fromCache→"缓存"；provider=="offline"→"离线"；否则"在线"；显示 provider 名 + fallbackReason 提示
失败 → OverlayError（保留原文，可重试；UI 以同一原文再次调用）
```

---

## 5. 与既有约定的兼容性

- [x] **不破坏 Locator 模型**：`core/src/types.rs` 的 `Locator`/`TextAnchor`/`Rect` 零改动；新增仅桥接 DTO 与 Dart DTO 字段。
- [x] **不跨越限界上下文**：翻译仍在 Translation 上下文（`core/src/dict`），TTS 仍是 Reading 的支撑模块（`core/src/tts` 零改动）；无新表/新上下文；`translation_cache`/`settings` 复用。
- [x] **听读同进度不变式**：`reading_progress` 仍是唯一事实源；进入听书不写、句完成/拖动/退出写、返回重读；`TtsSentenceStarted`/`TtsVoiceFallback` 不写盘。
- [x] **ddd-rules 冻结零改动**：见 §1 分层合规（domain 只依赖契约；interface 不触生成物；services 转换）。
- [x] **REQ-003 契约**：`translate_set_config` 语义不变；`translate(text,from,to)` 签名不变；`Translation` 值对象/缓存键/`deepl_body`/隐私参数不变；`translate_cached` 2 元组签名不变；新增 `translate_routed`/`translate_get_config`/`translate_set_strategy` 为**加法**。唯一存量断言更新：`store/translation.rs:263` 默认 provider 由 `"offline"` → `"auto"`（US-13 授权）。
- [x] **REQ-005 契约**：`TtsEngine` 抽象方法签名不变（仅 sealed 事件新增子类）；`SystemTtsEngine`/`ListenPage`/`ListenFollowHighlight` 既有构造参数保持（新增均可选）；`tts_engine_test.dart:187-214` 的音色回退断言按 US-21 更新（US-23 已明确属测试预期更新）。
- [x] **REQ-004/REQ-001**：选中工具条"翻译"入口复用，不新增入口；分页/滚动选区机制零改动。

---

## 6. 逐屏原型映射（UI 权威，禁止自创布局）

| 线框 | 本 REQ 改动 | 不改动 | 对应 US |
|---|---|---|---|
| `docs/wireframes/09-listen-player.svg` | 正文区**当前朗读句自动滚动进视口**（行为，非布局）；控制条右侧音色标签在无匹配时显示"系统默认音色" | 顶部"听书"标题 + 设置入口；控制条章节名/`⏮`/`⏸▶`/`⏭`/句级 Slider/`1.0x`/`⏱ 定时`（禁用）/`🎙 音色`（禁用） | US-7/US-8/US-9/US-21 |
| `docs/wireframes/10-listen-settings.svg` | 音色可用性提示（P1）：无匹配时显示"系统默认音色"，不误导为已选男/女声 | 音色分组 5 行（系统男/女声可选；AI/Piper/克隆禁用灰置 + 线框文案）；语速滑块；定时关闭禁用；后台播放禁用；隐私文案 | US-21 |
| `docs/wireframes/08-translation.svg` | 译文卡片来源标签：`在线`/`离线`/`缓存` + provider 名 + 回退提示（如"在线失败，已回退离线"）；对应线框"DeepL · 命中缓存" | 浮层结构/选中高亮/卡片位置/查词卡片/加入生词本按钮 | US-17/US-18 |
| `docs/wireframes/03-settings.svg` | "翻译与词典"区块内新增「翻译策略」下拉 + key 掩码回填（不新增页面/不改左侧导航） | 左侧导航（阅读/外观/翻译与词典/数据与备份/快捷键）、外观分组布局 | US-15 |
| `docs/wireframes/reader-ui-v2/04-selection.svg` | **零改动（回归守护）**："翻译"入口复用，不新增入口、不改工具条 5 入口/4 色圆点 | 全部 | US-23 |

> **禁止自创布局**：以上仅"滚动行为 / 标签文案 / 已有区块内新增控件"，不改变任何线框的布局骨架。

---

## 7. US → 模块/测试映射（供阶段 4/5 追溯）

| US | 优先级 | 模块/接口 | 自动化层级 | 主责任务（见 02-plan） |
|---|---|---|---|---|
| US-1 | P0 | main manifest `TTS_SERVICE` query | [配置断言] | T-001 |
| US-2 | P0 | main manifest `INTERNET` | [配置断言] | T-001 |
| US-3 | P0 | `SystemTtsEngine.configure` 调用序列 | [单测] | T-002 |
| US-4 | P0 | `SystemTtsEngine.speak` 失败/focus/Done 恰好一次 | [单测] | T-002 |
| US-5 | **P1** | `TtsSentenceStarted` + `setStartHandler` + `ListenPage` 穷尽 | [单测] | T-002/T-004 |
| US-6 | P0 | `ListenPage` Done 推进回归 | [单测] | T-004/T-005 |
| US-7 | P0 | `ListenFollowHighlight.offsetForHighlight` + controller | [单测] | T-003 |
| US-8 | P0 | `ListenPage` 推进 → 高亮/滚动同步 | [单测] | T-004 |
| US-9 | P0 | `_onSeek`/上下句 → 高亮/滚动同步 | [单测] | T-004 |
| US-10 | P0 | `translate_routed` deepl 成功 | [单测] | T-006 |
| US-11 | P0 | 段落规范化 + 超长明确错误 | [单测] | T-006 |
| US-12 | P0 | 缓存命中不重复请求 | [单测] | T-006 |
| US-13 | P0 | auto 默认 + 未配置回退 offline | [单测] | T-006 |
| US-14 | P0 | 仓库无硬编码 key 扫描 | [配置断言] | T-011 |
| US-15 | P0 | `translate_get_config`/`set_strategy` + 设置页回填 | [单测] | T-007/T-008/T-009 |
| US-16 | P0 | 未配置 key + 离线未命中错误文案 | [单测] | T-006/T-011 |
| US-17 | P0 | 在线失败回退 offline + 可重试 | [单测] | T-006/T-010 |
| US-18 | **P1** | `TranslationResultCard` 标签 | [单测] | T-010 |
| US-19 | P0 | 错误不丢原文 + 重试 | [单测] | T-006/T-011 |
| US-20 | P0 | 隐私：只发 text/from/to | [单测] | T-006/T-011 |
| US-21 | **P1** | 音色回退 `clearVoice` + 提示 | [单测] | T-002/T-004 |
| US-22 | P0 | 新增/更新测试全绿 | [单测] | T-005/T-011/T-012 |
| US-23 | P0 | 既有功能零回归 | [单测] | T-005/T-011/T-012 |

---

## 8. 错误文案契约（精确字符串/子串，供测试断言）

| 场景 | 错误变体 | 文案（精确） | 必须包含子串 |
|---|---|---|---|
| auto 无 key + 离线未命中 | `NotConfigured` | `翻译服务未配置：未配置在线翻译 API Key（deepl），且离线翻译未命中（请先安装内置词库）` | `未配置在线翻译 API Key`、`离线翻译未命中` |
| auto 在线失败 + 离线未命中 | `Network` | `网络请求失败：在线翻译失败：{detail}；离线翻译未命中（请先安装内置词库）（原文：{text}）` | `在线翻译失败`、`离线翻译未命中`、`{text}` |
| 显式 provider 无 key 且无 offline 兜底 | `NotConfigured` | `翻译服务未配置：{provider} 未配置 API Key，请先在设置中配置` | `API Key` |
| 显式 provider 网络失败且无 offline 兜底 | `Network` | `网络请求失败：{detail}（原文：{text}）` | `{text}` |
| 空文本 | `Other` | `待翻译文本为空` | — |
| 未知策略 | `Other` | `未知翻译策略: {strategy}` | `未知翻译策略` |
| 翻译未初始化 | `String`（api） | `翻译未初始化：请先调用 library_open` | — |
| 离线 provider 未命中（底层，保留） | `NotConfigured` | `离线翻译未命中（请先安装内置词库）` | `离线翻译未命中` |
| TTS 朗读失败（UI） | — | `朗读失败：{message}（请检查系统语音是否已安装）` | `语音`、`安装` |
| 回退原因（`fallback_reason`） | — | `在线失败，已回退离线` / `未配置在线翻译 API Key，已回退离线` | — |
| 译文标签 | — | `在线` / `离线` / `缓存` | — |
| 音色提示 | — | `系统默认音色` | — |
| 设置页提示 | — | `已保存 DeepL API Key` / `已清除 DeepL API Key（当前未配置在线翻译）` | — |

---

## 9. §12 设计授权取舍（tradeoff）清单（供阶段 5a 产品验收判"已授权取舍"）

1. **语言固定 `zh-CN`**：本期不做 per-book/设置语言；英文书按系统默认语言朗读（多语言朗读留后续 REQ）。
2. **默认策略 `auto`**：`translate.default_provider` 默认值由 `"offline"` 改 `"auto"`；键名不变、值域扩展。
3. **显式 provider 亦回退 offline**：用户显式选 deepl 时断网也会回退离线并提示（符合 US-17"失败可回退"）。
4. **空 key 保存 = 清除**：清空输入框并保存 = 清除已配置 key + 明确提示（非静默覆盖）。
5. **key 仅掩码回填**：不回填明文；未编辑时不写 key（避免掩码被写回）。
6. **`translate_set_config` 语义不变**：策略回切由新增 `translate_set_strategy` 承担。
7. **TTS 事件驱动推进**：`speak` Future 不参与推进；`awaitSpeakCompletion(true)` 仅作平台设置（防双推进/递归）。
8. **onStart 缺失兜底**：平台不触发 `speak.onStart` 时，仍以 Done 的乐观 `_index` 推进。
9. **自动滚动用 `TextPainter` 计算 offset**（非 span `ensureVisible`）；验收代理为"offset 单调"或"锚点可见"。
10. **长文本不自动分段**：超 DeepL 单请求上限 → 明确错误 + 可重试（US-11 允许）。
11. **音色无匹配显示"系统默认音色"**，男女声切换在缺音色设备上名存实亡（US-21 已接受）。
12. **P1 项延后**：US-5/US-18/US-21 在 P0 全绿后补，不阻塞 P0 交付。
13. **key 明文存 settings**：本期满足"可配置+不硬编码+掩码回填"；加密/钥匙串留后续 REQ（REQ-006 §1.2 明确不做）。

---

## 10. 数据流/桥接再生成说明
- 新增/修改 Rust 桥接面（`TranslationView` 字段、`TranslateConfigView`、2 个 async 函数）后须运行 FRB codegen 再生成 `app/lib/src/rust/*`；生成物中 `TranslationView` 构造函数仅在 `frb_generated.dart` 内使用（已核实），Dart 业务侧只经 `RustTranslateBackend` 映射，字段新增不会破坏手写代码。
- `TranslateBackend` 新增 `getConfig/setStrategy` 后，`FakeTranslateBackend` 必须同步（否则测试编译失败）——列为 T-008 验收项。
