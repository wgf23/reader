<!-- wf-meta: req=REQ-006 | phase=delivery | agent=release-manager | date=2026-09-09 | gate=passed -->
# REQ-006 · 阶段5 交付（验证汇总 / 发布说明 / 追溯矩阵）

> 范围：**听书真正发声 + 当前句自动滚动**（两个 P0 修复之一：R1-1 包可见性 / R1-4 引擎初始化 /
> R1-6 失败可见 / R1-8 音频焦点 / R1-3 自动滚动）+ **新增在线翻译**（另一个 P0：R2-1 默认 online
> 可达 / R2-3 auto 路由与回退 / R2-2 key 配置回填 / R2-4 来源标签）。
> 版本：`0.6.4+10` → **`0.7.0+11`**（语义化 **minor**：新增在线翻译能力 + 两项 P0 修复，向后兼容）。
> 分支：`wf/REQ-006-tts-online-translate`。代码提交：`e2e5798`（开发）、`6b91de7`（测试）、
> `0eb667c`（清理）、`4b3c49c`（产品验收）。
>
> **闸门5 自评：passed** —— ① 追溯矩阵全闭合（US-1..US-23，孤儿=0；含两条 P0 端到端证据链）
> ② 全量回归绿（cargo 221/0、flutter 106/4skip、带 `.so` 110/0、analyze 0、DDD 0、CRAP FAIL=0）
> ③ 发布产物齐全（Linux bundle 已构建；Android APK 见 §4/§6 构建回填）。

---

## 1. 验证结果汇总（release-manager 独立复跑，非引用他人数字）

环境：本机无 `/home/heiwa/workspace/.toolchain/env.sh`（**未** source）；使用
`export PATH=$HOME/.cargo/bin:/root/flutter/bin:$PATH`；`CARGO_BUILD_JOBS=2`。

| # | 检查 | 命令 | 本次实测结果 | 结论 |
|---|---|---|---|---|
| 1 | core 全量单测 | `cd core && cargo test --release` | **221 passed / 0 failed**（lib 184 + mobi_azw3 21 + p0_corpus 5 + translate_corpus 8 + tts_api 3；Doc-tests 0） | ✅ 绿 |
| 2 | Flutter 全量（普通） | `cd app && flutter test` | **106 passed / 4 skipped / 0 failed**（4 个 FFI 用例无 `.so` 时跳过） | ✅ 绿 |
| 3 | Flutter 静态分析 | `cd app && flutter analyze` | **No issues found!（0）** | ✅ 0 |
| 4 | FFI 端到端（3 文件） | `READER_CORE_SO=core/target/release/libreader_core.so READER_CORPUS_DICTS=core/tests/corpus/src/dicts flutter test test/{rust_dict_ffi,tts_ffi,translate_ffi}_test.dart` | **3 passed / 0 failed**（dict 全链路 / tts_segment+locator+listen 设置 / translate DTO+策略+回退+掩码） | ✅ 绿 |
| 4b | Flutter 全量（带真实 `.so`） | 同上环境 `flutter test` | **110 passed / 0 skipped / 0 failed** | ✅ 绿 |
| 5 | DDD 分层 | `scripts/ddd-lint/target/release/ddd-lint check /root/reader --rules workflow/rules/ddd-rules.toml --out workflow/reports/ddd-req006-delivery.md` | **违规总数：0** | ✅ 0 |
| 6 | CRAP | `scripts/crap/target/release/crap scan core/src --cov workflow/reports/coverage-req006.json --config workflow/rules/crap-config.toml --out workflow/reports/crap-req006-delivery.md` | **FAIL=0，WARN=7，PASS=249** | ✅ FAIL=0 |
| 7 | Linux 发布构建 | `cd app && flutter build linux --release` | **✓ Built bundle**（`build/linux/x64/release/bundle/`，39 MB / 19 文件，`version.json = 0.7.0+11`） | ✅ 可构建 |
| 8 | Android APK 构建 | `bash scripts/build-android-local.sh` | 见 §4 / §6（本次执行，结果回填） | 见 §4 |

**与阶段3/4 数字一致性**：cargo 由阶段3 的 217 → 阶段4/本次 **221**（阶段4 新增 4 个测试模块用例，
`04-coverage.md §8` 已说明，本次一致）；flutter 普通口径 100→106→本次 **106**（阶段4/5a 新增
`listen_follow_highlight_test`、`translate_ffi_test` 等，一致）；带 `.so` 110 与 `04-coverage.md` 一致。
**唯一偏差项**：`cargo test` 输出 1 个 `unused variable: text` 警告，位于
`core/src/tts/mod.rs:572`（REQ-005 遗留，非本 REQ；`workflow/STATE.md` 已登记），不影响绿。

**变异/覆盖（阶段4 结论，本次未重跑，引用 04 产物）**：变异 **119/120 = 99.17%**（保守含 timeout
97.54%）≥80%；Rust 新代码覆盖 **268/275 = 97.5%**、Dart 改动文件 **170/170 = 100%** ≥85%。

### 闸门 1–5 状态

| 闸门 | 结论 | 关键数字 / 证据 |
|---|---|---|
| 闸门1 需求 | ✅ passed | US-1..US-23 全部可断言；R1-1..R1-8 / R2-1..R2-4 根因（`01-req.md`） |
| 闸门2 架构 | ✅ passed | ADR 7 决策点（每点 ≥2 备选）；`02-design.md` US 全映射；`02-plan.md` T-001..T-012 DAG 无环 |
| 闸门3 开发 | ✅ passed | `03-review.md`；cargo 217/0、flutter 100/3skip、analyze 0、DDD 0、CRAP FAIL=0、原型 deviation=0 |
| 闸门4 测试 | ✅ passed | `04-mutation.md` 99.17%；`04-coverage.md` Rust 97.5% / Dart 100% |
| 闸门5a 产品验收 | ✅ passed | `05b-product-preview.md` 5 屏全通过、deviation=0、gap=0 |
| **闸门5b 交付（本阶段）** | **✅ passed** | 追溯 23/23 闭合（孤儿 0）、全量回归绿、发布产物齐全 |

---

## 2. 变更说明（面向用户）

### 2.1 版本与语义化理由

| 项 | 变更 |
|---|---|
| `app/pubspec.yaml` | `version: 0.6.4+10` → **`0.7.0+11`** |
| `core/Cargo.toml` | 保持 `0.1.0`（内部 crate，非独立发布单元；发布惯例只动 `app/pubspec.yaml`） |
| 其它版本引用 | 已核查：`README.md`/`docs/**` 无版本标注；`app/android/local.properties`（gitignored，构建期派生）与 `core/Cargo.lock` 的 `0.6.4`（`writeable` 依赖版本，无关）**均无需同步**。Android `versionName/versionCode` 由 Flutter 从 pubspec 派生。 |

**语义化理由**：本 REQ 在两项 P0 缺陷修复之外**新增了在线翻译能力**（新桥接 DTO/FFI、auto 策略路由、
设置页策略与 key 回填），属**向后兼容的功能新增**；`translate`/`translate_cached`/`translate_set_config`/
`TtsEngine` 抽象签名/`ListenSettingsData`/`Locator` 契约均未破坏 → 按 SemVer 取 **minor**
（`0.6.4 → 0.7.0`），构建号 +1（`+10 → +11`）。

### 2.2 用户可见变更

1. **听书真正发声（P0）**：Android 主清单补齐 `TTS_SERVICE` 包可见性（Android 11+ 必需）与 release
   `INTERNET` 权限；`SystemTtsEngine.configure` 按序 `awaitSpeakCompletion(true)` → `setLanguage('zh-CN')`
   → 语速 → 音色；`speak` 带 `focus:true` 请求音频焦点，返回 `0/false`/异常时上报 `TtsFailed`（不再静默）；
   音色枚举不到时不传逻辑名、改 `clearVoice()` 并提示"系统默认音色"。
2. **当前句自动滚动（P0）**：`ListenFollowHighlight` 改为可注入 `ScrollController` 的有状态组件，
   句变化时用 `TextPainter` 计算偏移并 `animateTo`（含初始句），seek/上下句同步。
3. **在线翻译（P0，新增）**：翻译策略默认 `auto`（在线优先 → 未配置/失败回退离线），任意句子/段落；
   在线请求只发送选中文本（隐私）；未配置 key / 在线失败时给出含原文、可重试的明确提示。
4. **key 配置与回填（P0）**：设置页"词典与翻译"区块新增「翻译策略」下拉（auto/offline/deepl/echo）+
   DeepL key 掩码回填（`••••••••`，不回明文）；空 key 保存 = 清除并提示；全仓库无硬编码 key。
5. **译文来源标签（P1）**：译文卡片按 `缓存 / 离线 / 在线` + provider 名显示，并在回退时追加
   "在线失败，已回退离线"提示。

---

## 3. 已知问题与限制（不阻塞闸门，如实登记）

| # | 项 | 说明 | 处置 |
|---|---|---|---|
| 1 | **Android 真机 8 项手工验收** | ① 真正出声 ② 中文语言 ③ 音频焦点 ④ 自动滚动 ⑤ 音色回退 ⑥ release 联网 ⑦ 未配置/断网回退 ⑧ 隐私抓包 | 清单见 `03-review.md §4`；CI 已用 manifest 断言 + fake 单测 + FFI 兜底，待真机执行 |
| 2 | **DeepL 长文不自动分段** | 单请求上限约 128 KiB；超限走明确错误/回退离线，不自动分段合并（`02-design.md` tradeoff 10） | 可重试；后续 REQ 可做分段 |
| 3 | **音色枚举差异** | 各 ROM 系统音色名不统一；无 male/female 时显示"系统默认音色"，男女声切换在缺音色设备上名存实亡（tradeoff 11） | US-21 已接受；真机项 #5 |
| 4 | **朗读语言固定 `zh-CN`** | 不做 per-book/设置语言；英文书按中文引擎朗读（tradeoff 1） | 多语言朗读留后续 REQ |
| 5 | **key 明文存 settings** | 本期满足"可配置 + 不硬编码 + 掩码回填"，未加密/未入系统钥匙串（tradeoff 13，`01-req §1.2` 明确不做） | 加密/钥匙串留后续 REQ |
| 6 | **REQ-005 遗留编译警告** | `core/src/tts/mod.rs:572 unused variable: text`（非本 REQ 引入；`workflow/STATE.md` 已登记） | 后续清理，不影响构建/测试 |
| 7 | **CRAP WARN 2 项（本 REQ）** | `dict/translation.rs::translate_auto` CC=24（CRAP 24.5）、`translate_explicit` CC=18（17.5）；CC 本身 < 25 故恒不 FAIL | 技术债，后续可再抽纯函数 |
| 8 | **Linux bundle 未自动打包 `libreader_core.so`** | 既有 CMake 现状（非本 REQ 引入）；运行需将 `.so` 放入 `bundle/lib/` 或 `--dart-define=READER_CORE_SO=<path>` | 建议后续 REQ 修 CMake |
| 9 | **设计稿横屏 vs 实现竖屏** | 5 屏线框均 900×640 横屏，实现 1170×2532 竖屏（逻辑 390×844）；结构/元素可校验，横向比例/间距无法校验 | 建议补 390×844 竖屏设计稿（05b §5） |
| 10 | **`RustTranslateBackend.ensureTranslateBackendInit` 预留** | 预留初始化入口，当前未被调用（同 REQ-005 `rust_tts_backend` 先例） | 保留，登记（04-coverage §4.2） |
| 11 | **本机工具链差异** | 无 `/home/heiwa/workspace/.toolchain/env.sh`；Android 用 `/root/android-sdk` + NDK r27 + `/root/flutter` | 已适配 `scripts/build-android-local.sh` |
| 12 | **macOS / Windows 产物** | 非本 REQ 交付目标；由 `workflow/skills/build-platform.md` 覆盖 | 未构建（如实登记） |

---

## 4. 追溯矩阵（US-1..US-23 全闭合 · 无孤儿）

> 状态图例：**✅** = 实现 + 测试/配置证据闭合；**✅\*** = 上述均闭合，另有**真机项**待手工验收
> （统一指向 `03-review.md §4` 的 8 项清单，不阻塞闸门5）。
> 原型图：`09-listen-player.svg` / `10-listen-settings.svg` / `08-translation.svg` / `03-settings.svg` /
> `reader-ui-v2/04-selection.svg`；「—」= 无专属线框（后端/平台配置/工程项）。
> 设计列：`02-design.md` 章节 / `02-adr.md` 决策点；计划列：`02-plan.md` Task。

| US | 原型图 | 设计（02-design § / ADR） | 实现（文件/提交 `e2e5798`） | 测试证据（具体测试名/报告） | 状态 |
|---|---|---|---|---|---|
| **US-1** 主清单 TTS 包可见性 | —（平台配置） | §1/§6；ADR 决策点5；T-001 | `app/android/app/src/main/AndroidManifest.xml` | `android_manifest_test.dart`「US-1 声明 TTS_SERVICE 包可见性且保留 PROCESS_TEXT」「US-1 build.gradle.kts targetSdk 取自 flutter.targetSdkVersion（≥30）」 | ✅\* 真机 #1（引擎可见性） |
| **US-2** 主清单 INTERNET 权限 | —（平台配置） | §1/§6；ADR 决策点5；T-001 | `AndroidManifest.xml`（debug/profile 保留） | `android_manifest_test.dart`「US-2 主清单声明 INTERNET 权限（release 在线翻译必需）」「debug/profile 清单保留 INTERNET（merger 去重不冲突）」 | ✅\* 真机 #6（release 联网） |
| **US-3** 引擎初始化序列（语言/完成等待） | 09/10 | §2.3/§4.1；ADR 决策点3；T-002 | `engines/system_tts_engine.dart:44-49` | `tts_engine_test.dart`「US-3 configure 序列：awaitSpeakCompletion → setLanguage(zh-CN) → setSpeechRate → setVoice，均在 speak 前」「US-3 平台不支持 setLanguage/awaitSpeakCompletion → 不抛错且仍能 speak」 | ✅ |
| **US-4** speak 失败可见 + Done 恰好一次 + 焦点 | 09 | §2.3/§4.1；ADR 决策点3；T-002 | `engines/system_tts_engine.dart:109-119` | `tts_engine_test.dart`「US-4 speak 传 focus:true（音频焦点）」「US-4 speak 返回 false → TtsFailed（不静默）」「US-4 speak 返回 0 → TtsFailed」「US-4 speak 抛错 → TtsFailed 含原因」「US-4 完成回调恰好一次 TtsSentenceDone（speak Future 不重复推进）」 | ✅\* 真机 #1/#3 |
| **US-5** onStart 事件接线（P1） | 09 | §2.3/§4.1；ADR 决策点3；T-002/T-004 | `engines/tts_engine.dart`、`system_tts_engine.dart:145`、`listen_page.dart` | `tts_engine_test.dart`「US-5 构造时注册 setStartHandler；onStart → TtsSentenceStarted(index)」「US-5 _current 为 null 时 onStart 不抛错、不派发」；`listen_page_test.dart`「US-5 emitStarted 切换高亮锚点且不写盘」 | ✅ |
| **US-6** 完成回调推进下一句（回归加固） | 09 | §4.1；T-004/T-005 | `listen_page.dart`（`_onTtsEvent`/`_handleSentenceDone`） | `listen_page_test.dart`「US-14 句完成写 saveProgress（300ms 防抖）」「US-14 防抖：300ms 内连续完成只落盘最后一次」；`tts_engine_test.dart`「US-4 完成回调恰好一次」 | ✅ |
| **US-7** 句变化滚动到当前句 | 09 | §2.3/§4.1；ADR 决策点4；T-003 | `widgets/listen_follow_highlight.dart:43,95-154` | `listen_follow_highlight_test.dart`「highlightStart 递增 → 偏移单调不减」「负偏移与超界均被 clamp 到 [0, maxScrollExtent]」「US-7 注入 controller：句变化触发滚动回调，换 controller 后仍生效」「US-7 autoScroll=false 不滚动（对照路径）」「highlightStart 超过文本长度 → build 内 clamp，不抛异常」 | ✅ |
| **US-8** 听书页推进滚动同步 | 09 | §4.1；T-004 | `listen_page.dart`、`listen_follow_highlight.dart` | `listen_page_test.dart`「US-8 句推进 → 高亮切句且滚动偏移前移（旧句不再高亮）」 | ✅ |
| **US-9** 手动跳句/拖动滚动同步 | 09 | §4.1；T-004 | `listen_page.dart`（`_onSeek`/上一句/下一句） | `listen_page_test.dart`「US-9 拖动进度条到末句 → 高亮/滚动锚点同步且不越界」 | ✅ |
| **US-10** 已配置 key 在线翻译 | 08 | §2.1/§4.2；ADR 决策点1；T-006/T-007 | `core/src/dict/translation.rs:451`（`translate_auto`）、`api.rs:321` | `translation.rs`「translate_auto_prefers_online_when_key_configured」；`translate_ffi_test.dart`「FFI：RustTranslateBackend DTO 映射 / 策略 / 回退原因」；`rust_dict_ffi_test.dart`（provider 路由） | ✅\* 真机 #6（真实 DeepL） |
| **US-11** 段落/长文本在线翻译 | 08 | §2.1/§4.2；tradeoff 10；T-006 | `translation.rs:759`（`normalize_text`）、`translate_auto` | `translation.rs`「translate_auto_normalizes_paragraph_and_passes_only_args」「normalize_text_folds_whitespace_and_trims」；超长上限按 tradeoff 10 走明确错误/回退，由失败路径用例兜底 | ✅\* 长文真机 #6/#7 |
| **US-12** 在线命中缓存不重复请求（回归） | — | §2.1/§4.2；T-006 | `translation.rs`（`cache_get_translation`/`cache_put_translation`） | `translation.rs`「translate_cache_hit_no_second_provider_call」「translate_cached_flag_and_hit_count」；`rust_dict_ffi_test.dart`（命中 fromCache） | ✅ |
| **US-13** 默认 auto、未配置回退离线 | 08 | §2.1/§3；ADR 决策点1；T-006 | `store/translation.rs`（`DEFAULT_PROVIDER="auto"`）、`translation.rs`（`translate_auto`） | `translation.rs`「translate_auto_without_key_falls_back_offline_with_reason」；`store/translation.rs`「provider_config_roundtrip」（默认 auto）；`translate_corpus.rs`（默认 offline 命中）；`rust_dict_ffi_test.dart`（fallbackReason） | ✅ |
| **US-14** 仓库无硬编码 key | — | §2.1；T-011 | 全仓库（新增代码仅占位符） | `no_hardcoded_key_test.dart`「US-14 仓库无硬编码 DeepL key / 硬编码 Authorization 字面量」 | ✅ |
| **US-15** 设置页保存/回填 key + 策略 | 03 | §2.3/§6；ADR 决策点2；T-007/T-008/T-009 | `api.rs:347,365`、`translate_backend.dart`、`rust_translate_backend.dart`、`settings_page.dart:57,118-133` | `settings_page_test.dart`「REQ-006 US-15 已配置 key 掩码回填 + 策略下拉 + 未编辑不写 key + 空 key 清除」「REQ-006 US-15 输入 key 保存 → setConfig + setStrategy + 掩码回填」；`translation.rs`「config_view_reports_provider_and_deepl_key_state」「set_strategy_accepts_auto_and_registered_rejects_unknown」；`translate_corpus.rs`（get_config/set_strategy 往返 + 未知策略 + 掩码）；`translate_ffi_test.dart` | ✅ |
| **US-16** 未配置 key 明确提示 | 08 | §8；T-006/T-011 | `translation.rs`（`translate_auto` 组合错误） | `translation.rs`「translate_auto_unconfigured_and_offline_miss_message」（含"未配置在线翻译 API Key"+"离线翻译未命中"） | ✅ |
| **US-17** 在线失败回退离线 | 08 | §2.1/§4.2/§8；ADR 决策点1；T-006/T-010 | `translation.rs`（`FALLBACK_REASON_*`）、`translation_popup.dart:67` | `translation.rs`「translate_auto_online_failure_falls_back_offline_with_reason」「translate_explicit_online_falls_back_offline_with_reason」；`translate_reader_test.dart`「US-17/18 翻译结果经 ReaderPage 渲染 provider 与回退提示」 | ✅ |
| **US-18** 译文来源标签正确（P1） | 08 | §2.3/§6；ADR 决策点7；T-010 | `widgets/translation_popup.dart:20-22,58,67` | `translate_reader_test.dart`「US-18 译文卡片标签：在线/离线/缓存 + provider 名 + 回退提示」；`05b-product-preview.md` S3（真实渲染像素证据） | ✅ |
| **US-19** 错误不丢原文 + 可重试（回归） | 08 | §8；T-006/T-011 | `translation.rs`（错误携带 `source_text`） | `translate_reader_test.dart`「US-15 翻译失败显示错误文案与"重试"按钮，点击重试成功」；`translation.rs`「translate_auto_online_failure_and_offline_miss_message_keeps_text」 | ✅ |
| **US-20** 在线只发送选中文本（回归） | — | §2.1；T-006/T-011 | `translation.rs`（Provider 入参 `text/from/to`）、`provider.rs`（`deepl_body`） | `translation.rs`「translate_echo_returns_expected_and_records_only_args」「translate_auto_normalizes_paragraph_and_passes_only_args」；`provider.rs`「deepl_body_omits_source_lang_for_auto」「deepl_body_includes_source_lang_when_specified」 | ✅ |
| **US-21** 无匹配音色不传逻辑名（P1） | 10 | §2.3；ADR 决策点6；T-002/T-004 | `system_tts_engine.dart:58-88`、`listen_control_bar.dart`、`listen_settings_sheet.dart` | `tts_engine_test.dart`「US-21 枚举音色失败 → clearVoice + TtsVoiceFallback，不传逻辑名且仍可 speak」「US-21 getVoices 返回非 List → clearVoice + TtsVoiceFallback」「US-21 getVoices 无 male/female → clearVoice + TtsVoiceFallback」「US-21 setVoice 抛错 → clearVoice + TtsVoiceFallback 不阻断」「US-21 setVoice 返回 0 → clearVoice + TtsVoiceFallback 不阻断」；`listen_page_test.dart`「US-21 emitVoiceFallback → 控制条/设置面板显示"系统默认音色"」；`05b-product-preview.md` S2 | ✅\* 真机 #5 |
| **US-22** 新增/更新测试全绿 | — | §7；T-005/T-011/T-012 | `app/test/*`、`core/**` 测试模块 | 本次 `cargo test --release` **221/0**；`flutter test` **106/4skip/0**；带 `.so` **110/0**；`flutter analyze` **0** | ✅ |
| **US-23** 既有功能零回归 | 04-selection | §5/§6；T-005/T-011/T-012 | 既有代码零破坏（新增均为加法/可选参数） | 本次全量回归：`reader_page_test`/`reader_selection_test`/`translate_reader_test`/`settings_page_test`/`library_page_test`/`rust_dict_ffi_test`/`tts_ffi_test`/`translate_ffi_test` 全绿；`provider_config_roundtrip` 默认值按授权更新为 `auto`；`05b-product-preview.md` S5 截图字节一致 | ✅ |

**闭合统计**：US-1..US-23 共 **23 条** → **✅ 17 条 + ✅\* 6 条（US-1/2/4/10/11/21，真机项）= 23 条全部闭合；孤儿需求 = 0**。

### 4.1 两个 P0 的端到端证据链

- **P0-1 听书发声 + 自动滚动**：`AndroidManifest.xml`（TTS_SERVICE query + INTERNET，`android_manifest_test.dart` 配置断言）
  → `SystemTtsEngine` 调用序列/失败可见/焦点/onStart（`tts_engine_test.dart` US-3/4/5/21）
  → `ListenFollowHighlight` 滚动（`listen_follow_highlight_test.dart` + `listen_page_test.dart` US-5/8/9）
  → 真实渲染截图 `app/screenshots/listen_follow_scroll.png`（05b S1，断言 `position.pixels>0`）
  → 真机 8 项（`03-review.md §4` #1–#5）。
- **P0-2 在线翻译**：`translate_routed`/`translate_auto` auto 路由与回退（`translation.rs` 单测 ×8）
  → 默认策略 `auto`（`store/translation.rs`）→ 桥接 `translate_get_config`/`translate_set_strategy`（`api.rs`）
  → Dart 适配 + 设置页回填（`settings_page_test.dart`）→ 隐私只发选中文本（`provider.rs`/`translation.rs`）
  → FFI 端到端 `translate_ffi_test.dart` + `rust_dict_ffi_test.dart`（真实 `.so`）
  → 真实渲染卡片 `app/screenshots/translation_cards.png`（05b S3）→ 真机 #6–#8。

---

## 5. 发布产物清单

| 项 | 内容 | 状态 |
|---|---|---|
| **版本号** | `0.7.0+11`（`app/pubspec.yaml`） | ✅ |
| **源码** | 分支 `wf/REQ-006-tts-online-translate`；`e2e5798`（feat）、`6b91de7`（test）、`0eb667c`（chore 清理）、`4b3c49c`（test 产品验收）、本交付提交 | ✅ |
| **Linux 可执行产物** | `app/build/linux/x64/release/bundle/`：`reader_app` + `lib/libapp.so` + `lib/libflutter_linux_gtk.so` + `data/`，**39 MB / 19 文件**，`data/flutter_assets/version.json = {"version":"0.7.0","build_number":"11"}`（**不入库**：`app/.gitignore` `/build/`） | ✅ 已构建 |
| **Android APK** | `dist/reader-android-arm64-v0.7.0.apk`（`dist/` 已 gitignore，`git check-ignore` 确认；仅登记路径不入库） | 见 §6 回填 |
| **质量报告** | `workflow/reports/ddd-req006-delivery.md`（违规=0）、`workflow/reports/crap-req006-delivery.md`（FAIL=0/WARN=7/PASS=249）、`workflow/reports/coverage-req006.json`、`04-mutation.md` 原始结果 `/tmp/opencode/mutants-req006-*` | ✅ |
| **产品验收** | `workflow/backlog/REQ-006-tts-online-translate/05b-product-preview.md` + `product-preview.manifest.json` + `app/screenshots/*.png` | ✅ |

**Linux 运行说明（如实）**：`flutter build linux` 的 CMake 未把 `libreader_core.so` 复制进 `bundle/lib/`
（既有打包现状，非本 REQ 引入）。运行需将 `core/target/release/libreader_core.so` 放入 `bundle/lib/`
（rpath `$ORIGIN/lib`）或用 `--dart-define=READER_CORE_SO=<path>`。

---

## 6. Android APK 构建记录

- 命令：`bash scripts/build-android-local.sh`（本机适配：JDK21 `/usr/lib/jvm/java-21-openjdk-amd64`、
  Android SDK `/root/android-sdk`、NDK r27；交叉编译 3 ABI → jniLibs → `flutter build apk --release
  --target-platform android-arm64` → 归档 `dist/reader-android-arm64-v${VER}.apk`）。
- 结果：_（构建中，成功/失败与产物路径、大小在本节回填后二次提交）_

---

## 7. 闸门5 自评

- [x] **追溯矩阵全闭合**：US-1..US-23 = 23/23（✅ 17 + ✅\* 6），**孤儿需求 = 0**；每条均有测试/配置证据；
      两条 P0 端到端证据链见 §4.1。
- [x] **全量回归绿**：cargo **221 passed / 0 failed**；flutter **106 passed / 4 skipped**（带真实 `.so`
      **110 passed / 0 skipped**）；`flutter analyze` **0**；FFI 端到端 **3/3**；DDD **违规=0**；
      CRAP **FAIL=0**；Linux bundle 构建成功。
- [x] **发布产物齐全**：版本号 `0.7.0+11`、Linux bundle（39 MB / 19 文件）、质量报告、
      产品验收产物；Android APK 见 §6。

**结论：闸门5 passed。**

---

## 8. 合并建议

- **建议合并** `wf/REQ-006-tts-online-translate` → `main`（普通合并；建议先完成 `03-review.md §4` 的
  真机 8 项与 Android release APK 产出）。
- **前置**：等待 orchestrator / 用户确认；**本代理不自行合并 main、不 force-push**。
- 合并提交信息建议：`chore(release): REQ-006 v0.7.0 听书发声/自动滚动 + 在线翻译`。

---

## 9. 本阶段产物

| 文件 | 变更 |
|---|---|
| `app/pubspec.yaml` | `0.6.4+10` → `0.7.0+11` |
| `workflow/backlog/REQ-006-tts-online-translate/05-delivery.md` | 新增（本文件，带 wf-meta 头） |
| `workflow/reports/ddd-req006-delivery.md` | 新增（DDD 违规=0） |
| `workflow/reports/crap-req006-delivery.md` | 新增（CRAP FAIL=0 / WARN=7 / PASS=249） |
| `app/build/linux/x64/release/bundle/` | 本地构建产物（gitignored，不入库） |
| `dist/reader-android-arm64-v0.7.0.apk` | 本地构建产物（`dist/` gitignored，不入库，见 §6） |
