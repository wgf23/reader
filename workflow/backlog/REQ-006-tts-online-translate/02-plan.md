<!-- wf-meta: req=REQ-006 | phase=architecture | agent=architect | date=2026-09-09 | gate=passed -->
# REQ-006 · 计划拆分（Task 分解：听书发声/自动滚动 + 在线翻译策略/回退/读配置）

> 依据：`01-req.md`（US-1..US-23）、`02-adr.md`（7 决策点）、`02-design.md`（接口/时序/文案/取舍）。
> 硬约束：每任务 ≤1 天、有可断言验收、依赖图无环；覆盖全部 US-1..US-23；P0/P1 标注。

## 任务清单

| Task | 内容 | 依赖 | 估算 | 验收（映射 US） |
|---|---|---|---|---|
| **T-001** | **Android 主清单平台配置**（ADR 决策点5）：`app/android/app/src/main/AndroidManifest.xml` 的 `<queries>` 内新增 `<intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>`（保留 `PROCESS_TEXT`）；`<manifest>` 下新增 `<uses-permission android:name="android.permission.INTERNET"/>`；`build.gradle.kts` 不改（`targetSdk=flutter.targetSdkVersion`） | — | 0.5d | **US-1/US-2**（[配置断言]）：新增 `app/test/android_manifest_test.dart` 纯文本解析主清单——含 `android.intent.action.TTS_SERVICE`、`android.permission.INTERNET`，且 `android.intent.action.PROCESS_TEXT` 仍在；`build.gradle.kts` 含 `targetSdk = flutter.targetSdkVersion`（或注释记录来源，US-1 第二句）；debug/profile 清单保留 INTERNET 不冲突 |
| **T-002** | **TTS 引擎契约 + `SystemTtsEngine` 初始化/失败/焦点/音色回退**（ADR 决策点3/6，design §2.3/§4.1）：`tts_engine.dart` 增 `TtsSentenceStarted(index)`/`TtsVoiceFallback(requestedVoiceId)`；`system_tts_engine.dart`：`configure` = `awaitSpeakCompletion(true)`→`setLanguage('zh-CN')`→`setSpeechRate`→`_applyVoice`（匹配→`setVoice`；无匹配/返回0/异常→`clearVoice()`+`TtsVoiceFallback`）；`setStartHandler`→`TtsSentenceStarted`；`speak` 立即返回 + `focus:true` + 返回 `0/false`/异常→`TtsFailed`；`resume` 统一走 `speak` 路径；`fake_tts_engine.dart` 增 `emitStarted`/`emitVoiceFallback` | — | 1d | **US-3**：FakeFlutterTts 调用序列含 `awaitSpeakCompletion(true)`、`setLanguage('zh-CN')` 且都在 `speak` 之前，`setSpeechRate`/`setVoice` 仍被调；fake 抛错时 `configure` 不抛、`speak` 仍被调。**US-4**：`speak` 返回 false/抛错→`TtsFailed`；完成回调恰好一次 `TtsSentenceDone(index)`；`focus==true`。**US-5(P1)**：`setStartHandler` 已注册，fake 触发 start→`TtsSentenceStarted(index)`。**US-21(P1)**：`getVoices` 无 male/female 或抛错→**不** `setVoice(逻辑名)`、调 `clearVoice()`、随后 `speak` 成功；有匹配→`setVoice(真实 name/locale)`。离线约束：无 http/just_audio/audio_service import |
| **T-003** | **`ListenFollowHighlight` 自动滚动**（ADR 决策点4，design §2.3/§4.1）：`StatelessWidget`→`StatefulWidget`；新增可选 `controller`/`autoScroll`/`onScrolled`；`didUpdateWidget` 检测 `highlightStart` 变化 → `TextPainter` 布局整段 `TextSpan`（同 `style`/`textDirection`/`maxWidth`/`textScaler`）→ `offsetForHighlight` 求当前句 y → `controller.animateTo`；导出 `@visibleForTesting static double offsetForHighlight(...)` | — | 1d | **US-7**：纯函数单测——递增 `highlightStart` → 偏移**单调不减**、回退 → 减小；widget 测试注入 `ScrollController`（长文本，`maxScrollExtent>0`），句 0→k 后 `controller.offset` 增大、k→更早句减小；可选 `onScrolled` 被调；既有 `Key('listen-follow-text')` 与"越界 clamp 不抛异常"用例仍通过 |
| **T-004** | **`ListenPage` onStart 接线 + 事件穷尽 + 滚动同步 + 音色标签**（ADR 决策点3/4，design §4.1）：`_onTtsEvent` 改 `switch` 穷尽处理 `TtsSentenceStarted`（`_index=i`，不写盘）/`TtsSentenceDone`（既有推进）/`TtsVoiceFallback`（置 `_voiceFallback`）/`TtsFailed`（既有容错）；`ListenControlBar`/`ListenSettingsSheet` 增可选 `voiceFallback`，为真显示"系统默认音色" | T-002, T-003 | 1d | **US-5(P1)**：fake `emitStarted(i)` → `ListenFollowHighlight.highlightStart` 切到句 i 且 `backend.saved` 不因 Started 增加。**US-8**：连续 `emitDone(i)` → 高亮切句 i+1 且 `controller.offset` 随之变化（旧句不再高亮）。**US-9**：`_onSeek`/上一句/下一句 → `_index=j`、高亮区间与 offset 对应句 j、不越界不崩溃。**US-21(P1)**：`emitVoiceFallback` → 控制条显示"系统默认音色"。**US-6 回归**：Done 推进不重复、不双 `speak` |
| **T-005** | **TTS 测试补齐 + 回归**（design §7）：更新 `tts_engine_test.dart`（`tts_engine_test.dart:187-214` 音色回退断言改为"`clearVoice`/不传逻辑名且仍 `speak`"；新增调用序列/focus/onStart/失败返回用例）；新增/更新 `listen_page_test.dart`（onStart 高亮、滚动同步、seek 同步、音色提示）；`fake_tts_engine.dart` 新事件 | T-002, T-003, T-004 | 0.5d | **US-22/US-23（TTS 侧）**：`flutter test` 全绿；US-3/4/5/7/8/9/21 用例逐项存在；既有 `listen_page_test.dart` 除明确更新外零改动通过；`SystemTtsEngine`/`listen_page` 无网络 import |
| **T-006** | **`TranslationService` auto 路由 + 回退 + 错误文案 + key 语义**（ADR 决策点1，design §2.1/§4.2/§8）：`dict/mod.rs` 增 `TranslationProvider::key_is_missing` 默认方法；`provider.rs` DeepL 覆写；`dict/translation.rs` 增 `AUTO_PROVIDER`/`FALLBACK_REASON_*`/`RoutedTranslation`/`translate_routed`/`config_view`/`set_strategy`，`translate_cached` 委托（2 元组签名不变）；`store/translation.rs` `DEFAULT_PROVIDER="auto"` + 更新 `provider_config_roundtrip` 默认断言 | — | 1d | **US-10**：注入 DeepL stub + key + 默认 auto → `provider=="deepl"`、非空且≠输入、`from_cache==false`、无"离线未命中"错误。**US-11**：跨行段落规范化后整段传给 Provider（`normalize_text`）；超长不 panic、明确错误可重试。**US-12**：同 `(text,from,to,deepl)` 二次 → Provider 计数不增、`from_cache==true`。**US-13**：未配置 key → 走 offline（命中返回离线译文，不 `NotConfigured`）；配置 key → 在线。**US-16**：无 key+离线未命中 → 错误含"未配置在线翻译 API Key"与"离线翻译未命中"、不写缓存。**US-17**：在线失败+离线命中 → offline 结果 + `fallback_reason=="在线失败，已回退离线"`；离线未命中 → 可重试错误含原文。**US-19**：失败携带原文。**US-20**：Provider 入参仅 `text/from/to`（复用 CountingProvider 断言）。**US-23**：`translate_cached` 2 元组/缓存键语义不变；`provider_config_roundtrip` 断言更新为 `"auto"` |
| **T-007** | **桥接 DTO + FFI + codegen**（ADR 决策点1/2，design §2.2）：`api.rs` `TranslationView` 增 `fallback_reason`、`translate` 改调 `translate_routed`；新增 `TranslateConfigView` + async `translate_get_config`/`translate_set_strategy`；运行 FRB codegen 再生成 `app/lib/src/rust/*` | T-006 | 1d | **US-10/US-15/US-17**：`translate(...)` 返回含 `fallbackReason`；`translate_get_config()` 返回 `provider`/`hasDeeplKey`/`deeplKeyMasked`（掩码固定、无明文）；`translate_set_strategy("auto"/"offline"/"deepl"/"echo")` 往返一致，未知策略→Err 含"未知翻译策略"；生成物含 `translateGetConfig`/`translateSetStrategy`；`translate_set_config` 签名/语义不变 |
| **T-008** | **Dart 服务层 + Fake 同步**（design §2.3/§10）：`translate_backend.dart` 增 `TranslateConfigData`/`getConfig`/`setStrategy`，`TranslationData` 增可选 `fallbackReason`；`rust_translate_backend.dart` 转发并映射；`fake_translate_backend.dart` 实现新方法（记录 `lastStrategy`、可配置 `hasDeeplKey`） | T-007 | 0.5d | **US-15/US-18**：`RustTranslateBackend.getConfig` 字段与 DTO 一一对应、`setStrategy` 转发；`FakeTranslateBackend` 可返回配置、记录 `lastStrategy`；`TranslationData(fallbackReason:)` 可选（既有构造零回归）；services 可 import 生成物、engines 不 import（ddd-lint 违规=0） |
| **T-009** | **设置页策略选择 + key 掩码回填 + 空 key 语义**（ADR 决策点2，design §2.3/§6）：`settings_page.dart` `_load` 调 `getConfig`；新增 `DropdownButtonFormField<String>`「翻译策略」（auto/offline/deepl/echo）；已配置时 key 输入框回填 `'••••••••'` + `_keyDirty=false`；`_saveKey` 按 `_keyDirty` 决定是否写 key，空串→清除+提示，随后 `setStrategy(_strategy)` 并重载 | T-008 | 1d | **US-15**：输入 key 保存→`setConfig('deepl', key)` 被调 + 提示"已保存"；重进页面→输入框掩码回填 + 显示当前策略（如"自动（在线优先）"）；空 key 保存→`setConfig('deepl','')` + 提示"已清除…"（不静默覆盖）；策略下拉变更→`setStrategy` 被调；既有 `settings_page_test.dart` 的 `find.byType(TextField)` 仍唯一（策略用 Dropdown，不新增 TextField） |
| **T-010** | **译文来源标签 + 回退提示**（ADR 决策点7，design §6/§8）：`translation_popup.dart` `TranslationResultCard` 标签映射 `fromCache→缓存 / provider=="offline"→离线 / 否则→在线`，始终显示 provider 名；`fallbackReason!=null` → 追加提示行 | T-008 | 0.5d | **US-18(P1)**：`provider=="deepl"&&!fromCache`→显示"在线"；`provider=="offline"`→"离线"；`fromCache==true`→"缓存"；三种情况均显示 provider 名。**US-17**：`fallbackReason=="在线失败，已回退离线"`→卡片显示该提示。golden 若变更按线框 08 更新 |
| **T-011** | **翻译测试补齐 + 隐私/回归**（design §7/§8）：`core` 单测覆盖 auto/回退/错误文案/`key_is_missing`/`config_view`/`set_strategy`；FFI 端到端覆盖 `translate_get_config`/`set_strategy`/`fallback_reason`；Dart widget 覆盖设置页回填、卡片标签、错误重试；US-14 仓库无硬编码 key 扫描；跑 `cargo test -p reader_core` + `flutter test` | T-006, T-007, T-008, T-009, T-010 | 1d | **US-10~US-13/US-16/US-17/US-18/US-19/US-20/US-22/US-23**：全部翻译 US 用例逐项存在且绿；**US-14**：扫描仓库无真实 DeepL key（正则 `[0-9a-f]{8}-...:fx`）与硬编码 `DeepL-Auth-Key <字面量>`，示例仅占位符；隐私断言（Provider 入参 + `deepl_body` 只含 text/target_lang[/source_lang]）；`core/tests/translate_corpus.rs` 除默认值断言外零改动通过 |
| **T-012** | **全量回归 + 原型逐屏自检 + CRAP/DDD + 真机清单**（design §6，闸门3 前置）：`cargo test` + `flutter test` + FFI 端到端；生成 `03-crap-report.md`/`03-ddd-report.md`（FAIL=0、违规=0）；逐屏对照 09/10/08/03/04-selection 输出偏差清单（deviation=0）；输出 Android 真机手工清单（出声/中文语言/音频焦点/release 联网/真实 DeepL） | T-005, T-011 | 1d | **US-22/US-23 + 闸门3 前置**：全量回归绿；CRAP FAIL=0、DDD 违规=0；原型自检逐屏打勾、deviation=0；真机清单含 5 项待验（缺失项在 04/05 明确记录）；`docs/03`/`docs/04` 待同步项登记 |

**总估算**：T-001..T-012 合计 **10d**（关键路径约 5.5d，TTS 与翻译两条线可并行）。

## 依赖图（无环）

```
源点：T-001   T-002   T-003   T-006

T-001 ─────────────────────────────────────────────────────────────┐
T-002 ─┬─→ T-004 ─┬─→ T-005 ──────────────────────────────────────┤
T-003 ─┘          │                                               │
                  └─────────────（T-004→T-005）                    │
T-006 ─→ T-007 ─→ T-008 ─┬─→ T-009 ─┬─→ T-011 ────────────────────┤
                         └─→ T-010 ─┘                              │
                                                                    ▼
                                          T-005 ─┐
                                                 ├─→ T-012（汇点）
                                          T-011 ─┘
```
- **DAG 校验**：T-001/T-002/T-003/T-006 为源点；T-012 为唯一汇点；所有边方向一致，**无环**。
- **关键路径**：T-006 → T-007 → T-008 → T-009 → T-011 → T-012 ≈ 1+1+0.5+1+1+1 = **5.5d**。
- **并行线**：TTS 线 T-002 → T-004 → T-005（3.5d，与翻译线并行）；T-001 独立；T-003 独立（汇入 T-004）。

## US → Task 覆盖矩阵（全闭合，供阶段 4/5 追溯）

| US | 优先级 | 主责 Task | US | 优先级 | 主责 Task |
|---|---|---|---|---|---|
| US-1 | P0 | T-001, T-012 | US-13 | P0 | T-006, T-011 |
| US-2 | P0 | T-001, T-012 | US-14 | P0 | T-011 |
| US-3 | P0 | T-002, T-005 | US-15 | P0 | T-007, T-008, T-009, T-011 |
| US-4 | P0 | T-002, T-005 | US-16 | P0 | T-006, T-011 |
| US-5 | **P1** | T-002, T-004, T-005 | US-17 | P0 | T-006, T-007, T-010, T-011 |
| US-6 | P0 | T-004, T-005 | US-18 | **P1** | T-010, T-011 |
| US-7 | P0 | T-003, T-005 | US-19 | P0 | T-006, T-011 |
| US-8 | P0 | T-004, T-005 | US-20 | P0 | T-006, T-011 |
| US-9 | P0 | T-004, T-005 | US-21 | **P1** | T-002, T-004, T-005 |
| US-10 | P0 | T-006, T-007, T-011 | US-22 | P0 | T-005, T-011, T-012 |
| US-11 | P0 | T-006, T-011 | US-23 | P0 | T-005, T-006, T-011, T-012 |
| US-12 | P0 | T-006, T-011 | — | — | — |

> 全部 US-1..US-23 均有主责 Task；P1（US-5/US-18/US-21）在 P0 全绿后补，不阻塞 P0 交付。

## 冲突检查结果

- **与 ddd-rules 无冲突（1 项未声明层已处置）**：
  1. `core/src/dict/**`（domain）新增代码只 `use crate::types`/`crate::error`/`crate::dict`，auto 路由经既有契约 trait，**不**触 `crate::store|api|library` → 违规=0；
  2. `core/src/api.rs`（interface）可 `use crate::dict`/`crate::library`（interface 无 `forbid_internal`）；
  3. `app/lib/engines/system_tts_engine.dart`（interface）只 import `flutter_tts` + `tts_engine.dart`，不 import `src/rust/`；
  4. `app/lib/pages/listen_page.dart`（interface）经 `TtsBackend` 取 DTO；`app/lib/services/translate_backend.dart`（application）负责生成物→DTO；
  5. **`app/lib/widgets/listen_follow_highlight.dart`/`listen_control_bar.dart`/`listen_settings_sheet.dart`/`translation_popup.dart` 未被 ddd-rules 声明**（同 REQ-005）：处置 = 规则表冻结零改动，按 pages 同级纪律（只经 services/engines、禁 `package:reader_app/src/rust/`、`src/rust/`），03-review 人工核对 import 面；建议后续评审把 `app/lib/widgets` 纳入 interface paths（记录不执行）。
- **与 Locator / 听读同进度无冲突**：`core/src/types.rs` 的 `Locator`/`TextAnchor`/`Rect` 零改动；`reading_progress` 为唯一事实源；`TtsSentenceStarted`/`TtsVoiceFallback` **不写盘**，仅 `TtsSentenceDone`/拖动/退出写；零新表、零迁移、`user_version` 保持 3。
- **与限界上下文无冲突**：翻译仍在 Translation 上下文（`core/src/dict`），TTS 仍是 Reading 支撑模块（`core/src/tts` 零改动）；`translation_cache`/`settings` 复用。
- **与 REQ-003 契约**：`translate_set_config` 语义/签名不变；`translate(text,from,to)` 签名不变；`Translation` 值对象/缓存键/`deepl_body`/隐私不变；`translate_cached` 2 元组签名不变；新增 `translate_routed`/`translate_get_config`/`translate_set_strategy` 为加法。**唯一存量断言更新**：`core/src/store/translation.rs:263` `provider_config_roundtrip` 默认 provider 由 `"offline"` → `"auto"`（US-13 授权，已列 T-006 验收）；`core/tests/translate_corpus.rs:210-214` 默认 offline 结果仍成立（auto→offline）。
- **与 REQ-005 契约**：`TtsEngine` 抽象方法签名不变（仅 sealed 事件新增子类）；`SystemTtsEngine`/`ListenPage`/`ListenFollowHighlight` 既有构造参数保持（新增均可选，`listen_page_test.dart:567-579` 裸构造继续编译）；`tts_engine_test.dart:187-214` 音色回退断言按 US-21 更新（US-23 已明确属测试预期更新，不改 REQ-005 对外行为契约）。
- **与原型一致性无冲突**：09/10/08/03/04-selection 逐屏映射（design §6 + 本表自检清单）；仅"滚动行为/标签文案/已有区块内新增控件"，无自创布局。
- **范围划界（不做）**：AI 音色/Piper/声音克隆/定时关闭/后台播放/媒体键/点读/TRANS-03/04/05 均不实现，线框 09/10 中保持 `onChanged:null`/`onPressed:null` 禁用灰置；`just_audio`/`audio_service` 保持注释。
- **文档同步风险（已登记）**：`docs/03 §4/§13`（新增 `translate_get_config`/`translate_set_strategy`、`TranslationView.fallback_reason`、默认策略 `auto`、TTS 事件/焦点/语言）与 `docs/04 §7/§9.5`（策略回退、音色回退）需在开发/交付阶段同步；本阶段按纪律**只产出 3 份产物，未改 docs**，不阻塞闸门2。

## 原型一致性自检清单（T-012 执行，deviation=0）

| 屏 | 核对项（对照 svg 逐项） |
|---|---|
| `09-listen-player.svg` | 正文区当前句蓝色半透明高亮 + **自动滚动进视口**；控制条第 1 行章节名、第 2 行 `⏮`/`⏸▶`/`⏭`、第 3 行句级 Slider + `1.0x`、右侧 `⏱ 定时`/`🎙 音色` 两个**禁用占位**；顶部"听书"+设置入口；**不实现**底部"迷你播放条/空格/←→"说明（P2） |
| `10-listen-settings.svg` | 标题"听书设置"；音色分组 5 行（系统男/女声可选；AI/Piper/克隆禁用灰置 + 线框文案）；无匹配音色时"系统默认音色"提示（P1）；语速滑块 0.5x—3.0x；定时关闭禁用；后台播放禁用；隐私文案 |
| `08-translation.svg` | 译文卡片标签"在线/离线/缓存" + provider 名（对应"DeepL · 命中缓存"）；回退提示"在线失败，已回退离线"；浮层/选区/查词卡片布局不变 |
| `03-settings.svg` | "翻译与词典"区块内新增「翻译策略」下拉 + key 掩码回填；左侧导航/外观分组布局不变 |
| `reader-ui-v2/04-selection.svg` | **回归守护（零改动）**：工具条 5 入口（划重点/笔记/翻译/查词/复制）+ 4 色圆点不变；不新增翻译入口 |
| `README.md` | 线框 09/10 清单与评审要点核对（P2 项灰置、系统音色可选、听读同进度） |

## 闸门2 自评（计划部分）
- [x] **任务粒度可执行**：T-001..T-012 每项 ≤1 天（0.5~1d），每项含具体文件/行为与可断言验收，并映射 US-1..US-23（覆盖矩阵全闭合）。
- [x] **依赖图无环**：DAG 已标注（源点 T-001/T-002/T-003/T-006，汇点 T-012），关键路径 ≈5.5d；无环。
- [x] **冲突清单为空或已含处置**：ddd-rules（含 widgets 未声明）、Locator/听读同进度、限界上下文、REQ-003（1 处默认值断言更新）、REQ-005（音色测试预期更新）、原型一致性、范围划界、文档同步风险共 8 类，全部无冲突或已列处置。
- [x] **ADR 备选 ≥2 且给出理由**：7 个决策点各 ≥2 备选 + 拒绝论证 + 降级线（详见 02-adr）。
- [ ] **待同步项**：`docs/03`/`docs/04` 文档同步（非本阶段产物）标记为交付前风险，不阻塞闸门2（本阶段只产出 3 份产物）。
