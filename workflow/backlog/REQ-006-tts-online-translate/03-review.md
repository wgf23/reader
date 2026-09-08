<!-- wf-meta: req=REQ-006 | phase=development | agent=developer | date=2026-09-09 | gate=passed -->
# REQ-006 · 开发评审（前置审查 + 实现/自检记录 + 闸门3 自评）

> 输入：`01-req.md`（US-1..US-23）、`02-adr.md`（7 决策点）、`02-design.md`（接口/时序/文案/取舍）、`02-plan.md`（T-001..T-012）、`docs/03`/`docs/04`、`workflow/rules/ddd-rules.toml`、线框 09/10/08/03/04-selection。
> 分支：`wf/REQ-006-tts-online-translate`。

---

## 1. 前置审查

### 1.1 与 `docs/03-architecture.md` 既有约定核对

| 项 | 既有约定 | 本 REQ 处置 | 结论 |
|---|---|---|---|
| §4 dict/translate 桥接面 | `translate`/`translate_set_config` 等 async | 新增 `translate_get_config`/`translate_set_strategy`、`TranslationView.fallback_reason`、`TranslateConfigView`；**签名均为加法** | 无冲突，已同步 docs/03 §4 |
| §6.3 翻译请求时序 | 缓存优先 → Provider → 写缓存 | 扩展为 auto 路由（在线优先→回退离线），缓存键仍真实 provider | 无冲突，已同步 §6.3 |
| §13.2 TtsEngine 接口 | `TtsEngine` 抽象方法 + `TtsEvent` 流 | 抽象方法签名不变，`sealed TtsEvent` 增 2 子类；事件驱动推进 | 无冲突，已同步 §13.2 |
| §13.4 听书启动时序 | 句完成写进度 + 高亮推进 | onStart 仅确认高亮/滚动锚点、**不写盘** | 无冲突 |

### 1.2 与 `docs/04-module-design.md` 既有约定核对

| 项 | 既有约定 | 本 REQ 处置 | 结论 |
|---|---|---|---|
| §7 `TranslationProvider` trait | `name/translate` | 增默认方法 `key_is_missing`（既有 impl 零改动），DeepL 覆写 | 无冲突，已同步 §7 |
| §7 `TranslationService` | `translate` 缓存优先 | 增 `translate_routed/config_view/set_strategy`；`translate_cached` 2 元组签名不变 | 无冲突 |
| §9.2 设置键 | `listen.*` 三键、`translate.default_provider` | `listen.*` 零改动；`translate.default_provider` 键名不变、默认值 `offline`→`auto` | 无冲突，已同步 §9.5 |
| §9.4 领域规则 | 听读同进度/300ms 防抖/连续失败>5 停 | `TtsSentenceStarted`/`TtsVoiceFallback` 不写盘；写盘仍只在 Done/拖动/退出 | 无冲突 |

### 1.3 与既有 ADR 契约核对

| 来源 | 契约 | 处置 |
|---|---|---|
| REQ-003 | `translate(text,from,to)` 签名 | 不变 |
| REQ-003 | `translate_cached` 2 元组签名 | 不变（委托 `translate_routed` 后丢弃 reason） |
| REQ-003 | `translate_set_config` 语义（保存 key + 切默认 provider） | 不变；策略回切由新增 `translate_set_strategy` 承担 |
| REQ-003 | `Translation` 值对象/缓存键/`deepl_body`/隐私参数 | 不变；`fallback_reason` 不进值对象、不写缓存 |
| REQ-003 | `translation_cache` schema / `user_version=3` | 零改动、无迁移 |
| REQ-005 | `TtsEngine` 抽象方法签名 | 不变 |
| REQ-005 | `ListenSettingsData` 字段 / `listen.*` 键 | 不变 |
| REQ-005 | 听读同进度 / Locator | 不变；新增事件不写盘 |
| REQ-005 | `tts_engine_test.dart:187-214` 音色回退断言 | 按 US-21 更新为"clearVoice/不传逻辑名且仍 speak"（US-23 已授权测试预期更新） |
| 存量 | `provider_config_roundtrip` 默认 provider 断言 | 按 US-13 更新为 `"auto"`（唯一存量断言更新） |

### 1.4 业务/范围冲突核对

- **不做项零实现**：AI 音色/Piper/声音克隆/定时关闭/后台播放/媒体键/点读/TRANS-03/04/05 均未实现；线框 09/10 中 `onTimer:null`/`onVoice:null` 禁用占位保持。
- **无硬编码 key**：新增代码示例仅占位符；`no_hardcoded_key_test.dart` 扫描 app/lib、app/android/app/src、app/test、core/src、docs 通过。
- **隐私**：在线请求仍只含 `text/target_lang[/source_lang]`；`TranslationProvider::translate(text,from,to)` 入参不变。
- **无新表/新迁移**：`settings` 复用、`translation_cache` 零 schema 变更、`user_version` 保持 3。

### 1.5 计划核对（T-001..T-012 / 依赖 / 估算）

- T-001..T-012 全部有明确文件/行为/可断言验收，依赖图（T-006→T-007→T-008→{T-009,T-010}→T-011→T-012；TTS 线 T-002/T-003→T-004→T-005→T-012）**无环**；估算 0.5~1d 合理。
- 计划中"`docs/03`/`docs/04` 同步留交付阶段"与本任务 T-012 明确要求同步一致——**本阶段已执行 docs 同步**（见 §2 T-012），不构成偏差。
- **无任务缺失/依赖环/估算离谱** → 无 rework-A。

### 1.6 需求可测性

- US-1/US-2/US-14 为 `[配置断言]`（manifest 文本 + 仓库扫描），已落地纯文本测试。
- US-3/US-4/US-5/US-7/US-8/US-9/US-10~US-13/US-15~US-21 为 `[单测]`，均有 fake/stub 断言（调用序列、focus、事件、滚动 offset、provider/fallback_reason、配置回填）。
- US-6/US-12/US-19/US-20/US-23 为回归验证，既有用例全绿。
- `[真机]`（真正出声/中文语言/音频焦点/release 联网/真实 DeepL）不可 CI 自动化 → §4 提供手工清单。
- **无不可测验收词** → 无 rework-C。

### 1.7 原型一致性（逐屏，deviation=0）

| 线框 | 核对 | 结论 |
|---|---|---|
| `09-listen-player.svg` | 正文当前句高亮 + **自动滚动进视口**（行为）；控制条布局/`⏮⏸▶⏭`/Slider/`1.0x`/`⏱ 定时`/`🎙 音色` 禁用占位不变；无匹配音色时音色按钮文案变"🎙 系统默认音色" | 一致 |
| `10-listen-settings.svg` | 音色 5 行（系统男/女可选；AI/Piper/克隆禁用灰置）、语速 0.5–3.0、定时/后台禁用、隐私文案不变；仅新增一行"当前：系统默认音色（未找到所选音色）"提示（P1，区块内文案） | 一致 |
| `08-translation.svg` | 译文卡片标签"在线/离线/缓存" + provider 名（对应"DeepL · 命中缓存"）+ 回退提示；浮层/选区/查词卡片布局不变 | 一致 |
| `03-settings.svg` | 仅在既有"词典与翻译"区块内新增「翻译策略」下拉 + key 掩码回填；不新增页面/不改左侧导航 | 一致 |
| `reader-ui-v2/04-selection.svg` | **零改动**：工具条 5 入口 + 4 色圆点不变，未新增翻译入口 | 一致 |

> **deviation = 0**（REQ-006 仅"滚动行为 / 标签文案 / 既有区块内新增控件"，未自创布局）。线框 03 的左侧导航为 REQ-003 既存形态，非本 REQ 引入。

### 1.8 前置审查结论

**未发现与 docs/03、docs/04、既有 ADR 或业务范围的冲突；计划无缺失/环/估算问题；验收可测；原型 deviation=0 → 无 rework-A/B/C，进入实现。**

---

## 2. 实现与自检记录表（T-001..T-012）

| Task | 状态 | 实现要点 / 证据 | 自检 |
|---|---|---|---|
| **T-001** | ✅ | `AndroidManifest.xml` 增 `INTERNET` + `<queries>` `TTS_SERVICE`（保留 `PROCESS_TEXT`）；新增 `app/test/android_manifest_test.dart`（TTS_SERVICE/INTERNET/PROCESS_TEXT/targetSdk） | 4 断言全绿 |
| **T-002** | ✅ | `tts_engine.dart` 增 `TtsSentenceStarted`/`TtsVoiceFallback`；`system_tts_engine.dart` 按序 `awaitSpeakCompletion(true)`→`setLanguage('zh-CN')`→`setSpeechRate`→`_applyVoice`（无匹配/返回0/异常→`clearVoice()`+`TtsVoiceFallback`）；`setStartHandler`→判空后 `TtsSentenceStarted`；`speak` 立即返回 + `focus:true` + 返回 0/false/异常→`TtsFailed`；`resume` 走 `speak`；`fake_tts_engine.dart` 增 `emitStarted`/`emitVoiceFallback` | US-3/4/5/21 单测全绿 |
| **T-003** | ✅ | `ListenFollowHighlight` 改 `StatefulWidget`，可选 `controller`/`autoScroll`/`onScrolled`；`didUpdateWidget` + 初始帧用同参数 `TextPainter` 布局 → `offsetForHighlight` → `animateTo(clamp)`；`Key('listen-follow-text')` 与越界 clamp 保留 | 纯函数 + widget 滚动断言绿 |
| **T-004** | ✅ | `_onTtsEvent` 改 sealed 穷尽 `switch`：Started→`_index`（不写盘）/Done→既有推进/VoiceFallback→`_voiceFallback`/Failed→既有容错；控制条/设置面板 `voiceFallback` 可选参数显示"系统默认音色" | US-5/8/9/21 + US-6 回归绿 |
| **T-005** | ✅ | `tts_engine_test.dart` 更新音色回退断言 + 新增序列/focus/onStart/失败返回；`listen_page_test.dart` 新增 onStart 高亮/滚动同步/seek 同步/音色提示 | flutter test 全绿 |
| **T-006** | ✅ | `dict/mod.rs` 增 `key_is_missing` 默认方法；`provider.rs` DeepL 覆写；`translation.rs` 增 `AUTO_PROVIDER`/`FALLBACK_REASON_*`/`RoutedTranslation`/`translate_routed`/`config_view`/`set_strategy`，`translate_cached` 委托（2 元组不变）；`store/translation.rs` 默认 `"auto"` + 更新断言；错误文案严格按 design §8 | 72 个 dict 单测绿（含 auto/回退/文案/key 语义/隐私） |
| **T-007** | ✅ | `api.rs` `TranslationView.fallback_reason` + `TranslateConfigView` + async `translate_get_config`/`translate_set_strategy`；`translate` 改 `translate_routed`；**FRB codegen 已运行**（`translateGetConfig`/`translateSetStrategy`/`TranslateConfigView` 生成） | codegen Done；FFI 用例覆盖 |
| **T-008** | ✅ | `translate_backend.dart` 增 `TranslateConfigData`/`getConfig`/`setStrategy`、`TranslationData.fallbackReason`；`rust_translate_backend.dart` 转发；`fake_translate_backend.dart` 同步（记录 `lastStrategy`、可配置 key 状态） | analyze 0 issues |
| **T-009** | ✅ | `settings_page.dart` `_load` 调 `getConfig`；`DropdownButtonFormField<String>` 策略（auto/offline/deepl/echo）；key 已配置回填 `'••••••••'`+`_keyDirty=false`；`_saveKey` 按 `_keyDirty` 写 key、空串→清除+提示，随后 `setStrategy(_strategy)` + `_load()`；`find.byType(TextField)` 唯一 | US-15 用例绿 |
| **T-010** | ✅ | `translation_popup.dart` 标签 `fromCache→缓存 / provider=="offline"→离线 / 否则→在线`，始终显示 provider 名；`fallbackReason!=null` 追加提示行 | US-18 用例绿 |
| **T-011** | ✅ | core 单测覆盖 auto/回退/文案/`key_is_missing`/`config_view`/`set_strategy`；FFI 端到端覆盖新桥接；Dart widget 覆盖设置页回填/卡片标签/错误重试；`no_hardcoded_key_test.dart`（US-14 正则扫描） | 见 §3 全量结果 |
| **T-012** | ✅ | `docs/03 §4/§6.3/§13.2`、`docs/04 §7/§9.5` 同步；生成本报告 + DDD/CRAP/覆盖率报告；输出 §4 真机手工清单 | 见 §3 |

### 2.1 实现级澄清 / 偏差处置（不构成 rework）

1. **CRAP 重构**：`translate_routed` 初版 CC=27（FAIL），按"职责分离"拆为 `translate_routed`（分发）+ `translate_auto`（auto 路由）+ `translate_explicit`（显式策略）。**行为/契约零变化**，FAIL→0。属实现级重构，非架构偏差。
2. **`offsetForHighlight` 的 `textScaler` 传 1.0**：`RichText` 未设置 `textScaler`（默认 `noScaling`），故 widget 内传 1.0 与真实排版一致；纯函数保留该参数供测试/未来。
3. **初始句也滚动**：`ListenFollowHighlight.initState` 首帧后对当前句滚动一次（resume 到中段时也能进视口），是 US-7 的正向增强，不改变 `didUpdateWidget` 契约。
4. **显式 `offline` 策略**：显式 provider 为 offline 时不重复兜底（避免双调/错误文案误判为"在线失败"），符合 §8"显式 provider 文案保留 REQ-003"。
5. **FFI 既有断言语义更新**：`rust_dict_ffi_test.dart` 原"未配置 key → 抛错"改为"默认 auto → 回退 offline + `fallback_reason`"（US-13 授权）；该用例在无 `.so`/语料时跳过。
6. **docs 同步提前**：ADR 决策点9 将 docs 同步列为开发/交付阶段项，本任务 T-012 明确要求 → 本阶段完成，属授权范围。

---

## 3. 闸门3 自评

| 项 | 命令 | 真实结果 | 判定 |
|---|---|---|---|
| cargo 测试 | `cd core && cargo test --release` | **217 passed / 0 failed**（lib 180 + mobi_azw3 21 + p0_corpus 5 + translate_corpus 8 + tts_api 3） | ✅ |
| flutter 测试 | `cd app && flutter test` | **100 passed / 3 skipped**（3 个 FFI 用例因无 `.so`/语料跳过，符合预期） | ✅ |
| flutter analyze | `cd app && flutter analyze` | **No issues found!** | ✅ |
| DDD 分层 | `ddd-lint check ... --rules workflow/rules/ddd-rules.toml` | **违规总数：0**（报告 `workflow/reports/ddd-req006.md`） | ✅ |
| CRAP | `crap scan core/src --cov ... --config crap-config.toml` | **FAIL=0，WARN=7，PASS=249**（报告 `workflow/reports/crap-req006.md`） | ✅ |
| 原型一致性 | 逐屏对照 09/10/08/03/04-selection | **deviation=0**（§1.7） | ✅ |
| 未处理 rework | — | 前置审查无 rework-A/B/C；实现期唯一重构为 CRAP 拆分（已闭环） | ✅ |
| 范围/契约 | — | P2 项零实现；`translate_cached` 2 元组、`translate` 签名、`translate_set_config` 语义、`TtsEngine` 抽象签名、`ListenSettingsData` 字段、Locator/进度均未破坏 | ✅ |

**CRAP WARN 明细（7 项，均 < 25 故非 FAIL）**：
- 预存 5 项：`convert/mod.rs::canonicalize` 23.1、`format/epub.rs::{parse_metadata 21.8, html_to_text 19.7, parse_nav_xhtml 18.6, parse_ncx 20.2}`（REQ-006 未触碰）。
- 本 REQ 新增 2 项：`dict/translation.rs::translate_auto` 24.5（CC=24，cov 96%）、`translate_explicit` 17.5（CC=18，cov 96%）。二者 CC 本身 < 25，即使 100% 覆盖亦不会 FAIL；如需进一步降 WARN，可后续把 key 校验/候选遍历再抽纯函数（非本闸门要求）。

**闸门3 结论：通过（passed）。**

---

## 4. Android 真机手工验收清单（交付阶段执行，CI 不可自动化）

| # | 场景 | 步骤 | 期望 |
|---|---|---|---|
| 1 | 真正出声 | 真机（targetSdk 36，装有中文 TTS 引擎）打开一本书 → 点"听书" | 听到系统 TTS 朗读当前句；顶部"朗读中"出现 |
| 2 | 中文语言 | 系统语言非中文的机型重复 #1 | `setLanguage('zh-CN')` 生效，按中文朗读（不读成英文/无声） |
| 3 | 音频焦点 | 朗读中播放音乐/来电 | 音频焦点按系统策略处理（`focus:true`）；恢复后行为符合预期 |
| 4 | 自动滚动 | 长章节朗读至中后段 | 当前句自动滚动进视口并高亮；回退/seek 同步 |
| 5 | 音色回退 | 设备无 male/female 命名音色 → 打开听书设置 | 不误报"已选男/女声"，控制条/面板显示"系统默认音色"，仍能朗读 |
| 6 | release 联网 | `release` 构建，配置真实 DeepL key → 翻译任意段落 | 返回非空译文（provider=deepl，标签"在线"） |
| 7 | 未配置/断网回退 | 清空 key 或断网 → 翻译 | 离线命中返回并标注"离线"+回退提示；未命中给出含原文的可重试错误 |
| 8 | 隐私 | 抓包/观察 | 在线请求体只含 `text`/`target_lang`[/`source_lang`]，无书路径/元数据/设备信息 |

> 以上 1~5 为 US-1/3/4/7/21 的真机补充验证；6~8 为 US-10/11/16/17/20。CI 已用 fake/静态断言兜底，真机项需用户提供 key 与设备。

---

## 5. 未解决项 / 风险

1. **真机项不可自动化（高）**：出声/焦点/release 联网/真实 DeepL 需真机与用户 key，按 §4 清单交付阶段验收。
2. **DeepL 额度/长度（中）**：单请求上限约 128 KiB，超限不自动分段 → auto 回退离线/明确错误（design 授权取舍 10）。
3. **音色枚举差异（中）**：无匹配时"系统默认音色"，男女声切换在缺音色设备上名存实亡（US-21 已接受）。
4. **语言固定 `zh-CN`（中）**：英文书按中文引擎朗读，多语言朗读留后续 REQ（授权取舍 1）。
5. **key 明文存 settings（中）**：本期仅"可配置+不硬编码+掩码回填"，加密/钥匙串留后续（授权取舍 13）。
6. **`translate_auto` CRAP WARN 24.5**：CC=24 < 25 恒不 FAIL，记录为技术债（可再抽函数降至 <15）。
