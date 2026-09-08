<!-- wf-meta: req=REQ-005-fixes | phase=development | agent=developer | date=2026-09-08 | gate=passed -->
# REQ-005-fixes · 阶段3 开发（03-review：前置审查 + 实现记录 + 自检）

> 闸门3 结论：**passed**（cargo 全绿 / flutter 全绿 / analyze 0 / ddd-lint 违规=0 /
> CRAP FAIL=0 且新增 WARN=0 / 原型 deviation=0 / 无未处理 rework）。

---

## 1. 前置审查（对照 docs/03、docs/04、交互原型）

| 审查项 | 结论 | 依据 |
|---|---|---|
| 与 `docs/03-architecture.md` §4/§13 既有约定冲突？ | 无冲突；实现前 §13.3 为**旧签名**（同步、`usize`、领域 `Locator`），ADR 已授权改 async/`u32`/`LocatorView`，本阶段已同步文档（见 §6）。 | docs/03 §4（新增 listen settings 通道）、§13.2/§13.3 |
| 与 `docs/04-module-design.md` §9 既有约定冲突？ | 无冲突；§9.5 旧签名 `segment(book_id,href)` 无文本来源（domain 禁 store/library），ADR 决策点1a 选「文本入参」，本阶段已同步 §9.5；§9.2 `listen.timer` 本期不建已注明。 | docs/04 §9.2/§9.5 |
| 计划问题（任务缺失/依赖环/估算离谱）？ | 无。T-001..T-013 与依赖 DAG 可执行；T-001→T-013 全部落地。 | 02-plan.md |
| 验收可测性？ | 逐条映射 US-1..US-25，均有断言；新测试覆盖 US-2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/22。 | 01-req §2 |
| 回归面？ | 已并入 T-012：reader_page/reader_selection/translate_reader/library/settings/rust_bridge 全量回归绿。 | 02-plan T-012/T-013 |
| **实现是否与交互原型图一致（逐屏）** | **一致，deviation=0**（唯一可见新增=AppBar「停止」图标，见 §5 说明；线框正文/控制条/设置面板布局零自创）。 | `docs/wireframes/09`、`10`、`reader-ui-v2/04-selection` |
| DDD 冲突？ | 无。`core/src/tts` 仅 `use crate::types`；`engines/*` 不 import 生成物；`widgets/listen_*.dart` 人工核对 import 面合规。 | `workflow/rules/ddd-rules.toml`（零改动） |

**实现级裁定（非 rework，理由如下）**

1. **`ListenPage` AppBar 增加「停止」图标**：线框 09 的**正文控制条**无停止位（仅 ⏮/⏸▶/⏭/Slider/语速/定时/音色），而 US-10 为 P0「点击停止 → `ttsEngine.stop()`」。
   处置：正文控制条**严格保持**线框 09「恰好含」清单；停止按 ADR 关联裁定1（次要控制放顶部栏）置于 AppBar。
   该图标不改变线框正文/控制条布局，不属自创布局；已在 §5 记录。
2. **`ListenControlBar` / `ListenSettingsSheet` 用 `StatefulWidget`**：仅承载「拖动中本地预览、松手回调」「滑块/单选即时反馈」的局部态，**布局/文案与线框逐项一致**，不改设计契约的构造参数与回调语义。
3. **`flutter_tts: ^4.0.0`**：`pubspec` 语法不接受 `^4`（须完整语义化版本），语义仍为 `^4`。
4. **US-22 复制（P1 可选）已实现**：`Clipboard.setData`，失败静默（测试/无剪贴板平台不崩溃）。

---

## 2. 逐任务实现记录（T-001..T-013）

| Task | 状态 | 落地要点 | 关键文件 |
|---|---|---|---|
| T-001 | ✅ | domain 三函数改文本入参并实现：中文/ASCII 定界、收尾引号成对、`……`/`...` 整体、缩写/数字不误切、段落强制断句、`char_range=[start_i,start_{i+1})` 连续、空文本 `Ok(vec![])`、超长无标点整句；`progression=char_start/utf16_len`（clamp）、`TextAnchor{snippet,start,end}`、UTF-16 半开区间；`sentence_index_at` max `progression_i<=p`、章首 0/章末 N-1、NaN/<0/>1/href/book_id 不匹配/空 → Err；删 `not_implemented_yet`，补 13 个用例（含 11.25 万字计时）。 | `core/src/tts/mod.rs` |
| T-002 | ✅ | `LocatorView`/`SentenceChunkView` + `chapter_text`（`LibraryService::open_book` 按 href 取 `Chapter.text`）+ async `tts_segment`/`tts_locator_for_sentence`/`tts_sentence_index_at`（api 层重建 domain `Locator`）；codegen 生成 `ttsSegment/ttsLocatorForSentence/ttsSentenceIndexAt`，字段与 Dart 一一对应。 | `core/src/api.rs`、`app/lib/src/rust/*`、`core/src/frb_generated.rs` |
| T-003 | ✅ | `Store::get_setting/set_setting`（复用 settings 表 UPSERT）+ `LibraryService` 薄转发 + async `tts_listen_settings_get/set`（键 `listen.voice_id/speed/auto_next`，默认 `system_male/1.0/true`，speed clamp `[0.5,3.0]`）。 | `core/src/store/mod.rs`、`core/src/library/mod.rs`、`core/src/api.rs` |
| T-004 | ✅ | Dart `SentenceChunk{index,text,charStart,charEnd,locator}` + `SentenceLocator`；新增 `SystemTtsEngine`（flutter_tts；`configure→setSpeechRate/setVoice`、`speak→speak(text)`、完成→`TtsSentenceDone(index)`、异常→`TtsFailed`、音色不可用回退）；启用 `flutter_tts`（`just_audio`/`audio_service` 保持注释）。 | `app/lib/engines/tts_engine.dart`、`app/lib/engines/system_tts_engine.dart`、`app/pubspec.yaml` |
| T-005 | ✅ | `TtsBackend` 抽象 + `ListenSettingsData`；`RustTtsBackend`（生成物→DTO）；engines 不 import 生成物。 | `app/lib/services/tts_backend.dart`、`app/lib/services/rust_tts_backend.dart` |
| T-006 | ✅ | `ListenPage` 重写为 `StatefulWidget`（注入 bookId/bookTitle/href/progression/backend/ttsBackend/ttsEngine）；`Idle/Playing/Paused/Stopped`；`initState` 读设置→取章文本→segment→`sentenceIndexAt` 定位→configure→speak（**不写盘**）；`ListenControlBar` 线框 09 全控件（定时/音色禁用）；AppBar 设置入口 tooltip '听书设置'。 | `app/lib/pages/listen_page.dart`、`app/lib/widgets/listen_control_bar.dart` |
| T-007 | ✅ | 句完成→`_saveProgressDebounced`（300ms + `_dirty`/`_pending`）→`backend.saveProgress(href,progression)`；拖动松手 `j=round(v*(N-1)).clamp`→stop+speak(j)+saveProgress；退出/dispose 强刷。 | `app/lib/pages/listen_page.dart` |
| T-008 | ✅ | `ListenFollowHighlight`（`chapterText.substring(charStart,charEnd)` 高亮、推进切换）；`auto_next` 默认开→末句加载下一章 segment+speak(0)+saveProgress(nextHref,0)；关→Stopped；末章→Stopped。 | `app/lib/widgets/listen_follow_highlight.dart`、`app/lib/pages/listen_page.dart` |
| T-009 | ✅ | `ListenSettingsSheet`：系统男/女声可选（RadioGroup）；AI/Piper/克隆禁用灰置 + 线框文案；语速 Slider 0.5–3.0x + 当前值；定时关闭全禁用；后台播放禁用；隐私文案；语速变更→configure+持久化。 | `app/lib/widgets/listen_settings_sheet.dart` |
| T-010 | ✅ | `_openMore` 听书项 pop 后 push `ListenPage` 并传参；`ReaderPage` 新增可选 `ttsBackend/ttsEngine`（null 懒创建）；`await push` 后 `_reloadProgress()`；复制改 `Clipboard.setData`（US-22）。 | `app/lib/pages/reader_page.dart` |
| T-011 | ✅ | 顶层 `buildPagedWebViewSettings({disableContextMenu=true})`，`build()` 使用；`selectionchange` 回传与 `onSelectedText`、`next/prev/gotoPage/relayout` 零改动。 | `app/lib/engines/paged_web_view.dart` |
| T-012 | ✅ | 新增 `fake_tts_engine.dart`/`fake_tts_backend.dart`/`listen_page_test.dart`/`tts_engine_test.dart`/`tts_ffi_test.dart`；更新 `reader_page_test.dart`（听书可跳转 + 返回重读 + 复制）；回归 reader_selection/translate_reader/library/settings。 | `app/test/*` |
| T-013 | ✅ | 全量回归 + FFI 端到端 + ddd-lint + CRAP + 逐屏对照 + 真机清单 + docs 同步（§6）。 | 本文件、`workflow/reports/*` |

---

## 3. 自检结果（闸门3）

### 3.1 测试与静态检查

| 检查 | 命令 | 结果 |
|---|---|---|
| core 单测 | `cd core && cargo test --release` | **145 passed / 0 failed**（含新增 13 tts 用例；另有 mobi 21、p0_corpus 5、translate_corpus 8，合计 **179 passed / 0 failed**） |
| Flutter | `cd app && flutter test` | **53 passed / 0 failed / 3 skipped**（skip 为 3 个需真实 `.so` 的 FFI 测试；基线 31/2 → 净增 22） |
| 静态分析 | `cd app && flutter analyze` | **No issues found!（0）** |
| FFI 端到端 | `READER_CORE_SO=../core/target/release/libreader_core.so READER_CORPUS=../core/tests/corpus/src/hongloumeng.epub flutter test test/rust_bridge_test.dart test/tts_ffi_test.dart` | **2 passed / 0 failed**（导入 EPUB→segment 非空→区间连续→往返一致→设置默认/往返/clamp 3.0） |
| DDD | `ddd-lint check . --rules workflow/rules/ddd-rules.toml` | **违规=0**（`workflow/reports/ddd-req005.md`；规则表零改动） |
| CRAP | `crap scan core --cov coverage-req005.json` | **FAIL=0，WARN=7（全部为既有函数），PASS=285**；本次新增/修改函数全部 PASS（tts 域 `segment` 8.0、`sentence_index_at` 8.0、`delimiter_end` 10.0、`sentence_starts` 7.0 …）。`workflow/reports/crap-req005.md` |
| US-8 性能 | `cargo test --release segment_100k_chars_under_budget -- --nocapture` | **112500 字 / 12500 句 → 6.52ms**（预算 <50ms；CI 上限 200ms） |
| codegen | `flutter_rust_bridge_codegen generate …` | 再生成后 `app/lib/src/rust/*`、`core/src/frb_generated.rs` **无未解决 diff**（幂等；`frb_generated.web.dart` inline-class 告警为既有、可忽略） |

### 3.2 覆盖/质量

- CRAP 覆盖数据由 `cargo llvm-cov --release --json` 生成（`workflow/reports/coverage-req005.json`，`core/src/tts/mod.rs` 行覆盖 **96%**）。
- 未新增 WARN：`sentence_starts` 初版 CC=20（WARN）经抽取 `delimiter_end` 后 CC=7（PASS），WARN 数由 8 降回既有 7。
- 变异测试归闸门4（本阶段不执行）。

---

## 4. 原型逐屏自检（deviation=0）

### 4.1 `docs/wireframes/09-listen-player.svg`

| 线框元素 | 实现 | 核对 |
|---|---|---|
| 顶部标题「听书模式 · 跟读」 | AppBar title `听书` + 设置入口 tooltip `听书设置` | ✅（ADR 裁定1：设置入口在顶部栏） |
| 正文区当前句蓝色半透明高亮 + 「朗读中」徽标 | `ListenFollowHighlight`（`backgroundColor: 0x401A73E8`）+ 蓝色「朗读中」徽标 | ✅ US-17 |
| 控制条第 1 行章节名 | `ListenControlBar.chapterTitle` | ✅ |
| 第 2 行 `⏮` / `⏸`（播放中）/ `⏭` | `Icons.skip_previous` / `pause`/`play_arrow` / `skip_next` | ✅ US-3/US-10 |
| 第 3 行句级进度条 + `1.0x` | `Slider`（松手回调）+ 速度文本 | ✅ US-16 |
| 右侧 `⏱ 30 分钟` / `🎙 男声·AI` | 两个 `OutlinedButton(onPressed:null)` 禁用灰置（音色显示「🎙 系统男声/女声」） | ✅ US-3/US-13 |
| 底部「迷你播放条/空格/←→」说明 | **不实现**（后台播放/跨页常驻为 P2，01-req §1.2 划界） | ✅ 范围划界 |
| 正文上方注释「听读共用同一进度」 | 行为已实现（进入不写、句完成/拖动/退出写、返回重读），注释为说明非控件 | ✅ US-2/US-14/US-15 |

### 4.2 `docs/wireframes/10-listen-settings.svg`

| 线框元素 | 实现 | 核对 |
|---|---|---|
| 标题「听书设置」 | Sheet 标题 | ✅ |
| 系统男声（选中）/系统女声「离线」 | `RadioGroup` + `RadioListTile` 可选 | ✅ US-13 |
| AI 音色「需网络（P2）」 | `RadioListTile(enabled:false)` | ✅ |
| 本地神经音色 Piper「下载 52MB（P2）」 | `RadioListTile(enabled:false)` | ✅ |
| 声音克隆「评估中」 | `ListTile(enabled:false)` | ✅ |
| 语速 0.5x—3.0x 滑块 + 当前值 + 两端标签 | `Slider(min .5,max 3.0)` + `1.0x` + `0.5x/3.0x` | ✅ US-11 |
| 定时关闭 5 项（关闭/15/30/60/本章结束） | `RadioListTile(enabled:false)`（30 分钟为选中态） | ✅ |
| 后台播放开关（开） | `SwitchListTile(value:true, onChanged:null)` | ✅ |
| 面板外隐私文案 | 静态文案含「离线音色不联网…」 | ✅ |

### 4.3 `docs/wireframes/reader-ui-v2/04-selection.svg`（回归守护，零改动）

- 分页模式 `buildPagedWebViewSettings().disableContextMenu == true`（US-19）；`selectionchange`/`onSelectedText` 保留（US-20）；`ReaderSelectionToolbar` 五入口回归通过。
- 滚动模式 `SelectionArea.contextMenuBuilder → SizedBox.shrink()` **未被回退**（US-21，既有测试绿）。
- 04-selection 布局**零改动**。

### 4.4 唯一可见新增及处置

- **AppBar「停止」图标**：线框 09 正文控制条无停止位，而 US-10 为 P0。按 ADR 关联裁定1 置于顶部栏，正文控制条保持线框「恰好含」清单；不构成布局 deviation（详见 §1 裁定1）。

---

## 5. Android 真机手工验收清单（4 项，待 orchestrator/发布验证）

1. **分页模式长按无原生 ActionMode**：长按 WebView 正文选中 → 仅出现 `ReaderSelectionToolbar`（划重点/笔记/翻译/查词/复制），无系统「复制/全选」浮动菜单（US-19/US-20）。
2. **离线出声**：断网进入听书 → 系统 TTS 从当前阅读位置逐句朗读（US-12）。
3. **语速生效**：设置面板拖动语速 → 语速文本更新且朗读速度即时变化；退出重进读回（US-11）。
4. **退出续读**：听书听到第 k 句 → 返回阅读页定位同章同位置；杀进程重开仍从该位置继续（US-15）。

---

## 6. 文档同步（消除架构阶段登记的待同步风险）

| 文档 | 变更 |
|---|---|
| `docs/03-architecture.md` §4 | settings 增补 `tts_listen_settings_get/set`（键/默认/clamp） |
| `docs/03-architecture.md` §13.2/§13.3 | `TtsEngine` 落地说明（新 DTO）；桥接改 **async**、`idx: u32`、`locator: LocatorView`；domain 文本入参；UTF-16 半开区间 |
| `docs/04-module-design.md` §9.2 | 注明本期仅建三键、`listen.timer` 不建 |
| `docs/04-module-design.md` §9.5 | domain 三函数改**文本入参**、progression/边界语义、FFI 适配说明 |

---

## 7. 遗留 / 偏差处置

| 项 | 处置 |
|---|---|
| AppBar 停止图标（线框外新增） | 已按 ADR 裁定1 记录；正文控制条零偏差（§1 裁定1、§4.4） |
| `ListenControlBar`/`ListenSettingsSheet` 为 Stateful | 仅局部态，布局/契约不变（§1 裁定2） |
| `pubspec` 用 `^4.0.0` | 语法要求，语义等价（§1 裁定3） |
| 后台播放/媒体键/定时/多音色/AI/Piper/克隆/点读/笔记/划重点 | **未实现**（P2 禁用灰置；`just_audio`/`audio_service` 保持注释） |
| `Interrupted`（音频焦点）事件 | P2 不做（01-req §1.3 已授权），`TtsEvent` 保持 `TtsSentenceDone/TtsFailed` |
| Android 真机 4 项 | 见 §5，widget/FFI 层已兜底；真机项由发布阶段记录 |
| `app/lib/services/rust_tts_backend.dart` 的 `ensureTtsBackendInit` | 预留初始化入口（与 `RustLibraryBackend.open` 共用幂等 init），当前未被调用，保留 |
| 通用 `settings_get/set` | 本期不做（ADR 决策点6 备选 B），听书专用类型化通道已落地 |

---

## 8. 提交文件清单（本 REQ）

**新增**：`app/lib/engines/system_tts_engine.dart`、`app/lib/services/tts_backend.dart`、
`app/lib/services/rust_tts_backend.dart`、`app/lib/widgets/listen_control_bar.dart`、
`app/lib/widgets/listen_settings_sheet.dart`、`app/lib/widgets/listen_follow_highlight.dart`、
`app/test/fake_tts_engine.dart`、`app/test/fake_tts_backend.dart`、`app/test/listen_page_test.dart`、
`app/test/tts_engine_test.dart`、`app/test/tts_ffi_test.dart`、`workflow/backlog/REQ-005-fixes/03-review.md`、
`workflow/reports/ddd-req005.md`、`workflow/reports/crap-req005.md`、`workflow/reports/coverage-req005.json`。

**修改**：`core/src/tts/mod.rs`、`core/src/api.rs`、`core/src/store/mod.rs`、`core/src/library/mod.rs`、
`core/src/frb_generated.rs`、`app/lib/src/rust/{api,frb_generated,frb_generated.io,frb_generated.web}.dart`、
`app/lib/engines/tts_engine.dart`、`app/lib/engines/paged_web_view.dart`、`app/lib/pages/listen_page.dart`、
`app/lib/pages/reader_page.dart`、`app/test/reader_page_test.dart`、`app/pubspec.yaml`、`app/pubspec.lock`、
`app/macos/Flutter/GeneratedPluginRegistrant.swift`、`app/windows/flutter/generated_plugin_registrant.cc`、
`app/windows/flutter/generated_plugins.cmake`、`docs/03-architecture.md`、`docs/04-module-design.md`。

**零改动（约束遵守）**：`core/src/types.rs`、`app/lib/services/library_backend.dart`、
`app/lib/pages/library_page.dart`、`workflow/rules/ddd-rules.toml`、04-selection 相关 UI。

**未纳入提交（本 REQ 无关，工作区既有改动/未跟踪）**：`.gitignore`、`docs/08-multiagent-workflow-manual.md`、
`workflow/{README,STATE,porting}.md`、`workflow/agents/README.md`、`workflow/skills/{README,gates}.md`、
`app/integration_test/`、`app/screenshots/`、`app/test_driver/`、`opencode.json`、`scripts/product-preview.py`、
`scripts/ui-screenshots.sh`、`workflow/agents/product-reviewer.md`、`workflow/backlog/REQ-004-reader-ui/*`、
`workflow/opencode-runbook.md`、`workflow/reports/product-preview-demo.html`、`workflow/skills/product-preview.md`。
