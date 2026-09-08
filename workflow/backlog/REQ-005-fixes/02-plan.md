<!-- wf-meta: req=REQ-005-fixes | phase=architecture | agent=architect | date=2026-09-08 | gate=passed -->
# REQ-005-fixes · 计划拆分（Task 分解：听书链路贯通 + 分页禁原生菜单）

## 任务清单

| Task | 内容 | 依赖 | 估算 | 验收（映射 US） |
|---|---|---|---|---|
| **T-001** | **Rust domain 切句/映射实现**（ADR 决策点1a/1b，design §2.1）：`core/src/tts/mod.rs` 三函数改文本入参并实现——① 切句规则（`。！？；…`/ASCII、收尾引号成对、`……` 整体、英文缩写不误切、段落不跨合并、`char_range=[start_i,start_{i+1})` 连续不重叠、空文本 `Ok(vec![])`、超长无标点整句）；② `locator_for_sentence`（`progression=char_start/utf16_len`、`TextAnchor{snippet,start,end}`、UTF-16 半开区间）；③ `sentence_index_at`（max `progression_i<=loc.progression`、章首 0/章末 N-1、NaN/<0/>1/href 不匹配/空 → Err）；④ 删除 `:99-103` `not_implemented_yet` | — | 1d | **US-4/US-5/US-6/US-8**：`cargo test -p reader_core` 全绿；句数>0、trim、`prev.1==next.0`、引号成对、空文本空列表；`locator.book_id/href/progression∈[0,1]` 单调、snippet 前缀；往返 `i==index_at(locator_for(i))`；越界/不匹配 `Err` 不 panic；10 万字 `segment` <50ms（CI ≤200ms）；旧 `not_implemented_yet` 已删 |
| **T-002** | **桥接 DTO + FFI 三函数 + codegen**（ADR 决策点1b，design §2.2）：`core/src/api.rs` 新增 `LocatorView`/`SentenceChunkView`（字段与 Dart 一一对应）+ `chapter_text` helper（经 `LibraryService::open_book` 按 href 取 `Chapter.text`）+ async `tts_segment`/`tts_locator_for_sentence`/`tts_sentence_index_at`；`tts_sentence_index_at` 由 `LocatorView` 重建 domain `Locator`；运行 FRB codegen 再生成 `app/lib/src/rust/*` | T-001 | 1d | **US-7**：`core/src/api.rs` 三函数存在且命名与 docs/03 §13.3 对齐；生成物含 `ttsSegment`/`ttsLocatorForSentence`/`ttsSentenceIndexAt`；`tts_segment(bookId,'chapter_0001.xhtml')` 非空；往返一致；DTO 字段名/类型与 ADR 一致（`index/text/charStart/charEnd/locator{bookId,href,progression,totalProgression,snippet}`）；codegen 后无未解决 diff |
| **T-003** | **听书设置持久化桥接**（ADR 决策点6，design §2.2/§3）：`core/src/store/mod.rs` 新增公开 `get_setting/set_setting`（复用既有 `settings` 表与 `upsert` 语义）；`core/src/library/mod.rs` 转发；`core/src/api.rs` 新增 async `tts_listen_settings_get/set`（键 `listen.voice_id/speed/auto_next`，默认 `system_male/1.0/true`，speed clamp `[0.5,3.0]`）+ codegen | T-002 | 0.5d | **US-11（持久化侧）**：`tts_listen_settings_get` 无记录返回默认；`set(voice_id='system_female',speed=1.5,auto_next=false)` 后 `get` 往返一致；`speed=9.9` 读回 clamp 3.0；`settings` 表新增三键、无新表/迁移 |
| **T-004** | **TTS 引擎契约 + `SystemTtsEngine` + 依赖启用**（ADR 决策点1b/3，design §2.3/2.5）：`app/lib/engines/tts_engine.dart` 改 `SentenceChunk{index,text,charStart,charEnd,locator}` + 新增 `SentenceLocator`；新增 `app/lib/engines/system_tts_engine.dart`（封装 `flutter_tts`；`configure→setSpeechRate/setVoice`；`speak→speak(text)` + 完成回调发 `TtsSentenceDone(chunk.index)`；异常发 `TtsFailed`；系统缺音色回退默认）；`app/pubspec.yaml` 取消 `flutter_tts` 注释并 `flutter pub get` | — | 1d | **US-9/US-12**：存在 `class SystemTtsEngine implements TtsEngine`；`flutter_tts` 未被注释且 `pubspec.lock` 含该包；平台通道 mock 下 `configure` 触发 `setSpeechRate/setVoice`、`speak` 触发 `flutterTts.speak(chunk.text)`；`TtsFailed` 可被捕获；无 HTTP/网络 import；`just_audio`/`audio_service` 保持注释 |
| **T-005** | **TtsBackend 服务层**（ADR 决策点3/6，design §2.4）：新增 `app/lib/services/tts_backend.dart`（抽象 + `ListenSettingsData`）与 `app/lib/services/rust_tts_backend.dart`（生成物→`SentenceChunk`/`SentenceLocator`/`ListenSettingsData`）；`segment/locatorForSentence/sentenceIndexAt/loadListenSettings/saveListenSettings` | T-002, T-003, T-004 | 0.5d | **US-7（Dart 侧）**：`RustTtsBackend.segment` 返回 `SentenceChunk` 字段与 DTO 一一对应；`sentenceIndexAt(locatorForSentence(i))==i`；设置往返；services 可 import 生成物、engines 不 import 生成物（ddd-lint 违规=0） |
| **T-006** | **`ListenPage` 状态机 + 控制条**（ADR 决策点3/4，design §2.6/§4.1/§4.3/§5.1）：`StatelessWidget`→`StatefulWidget`，构造注入 `bookId/bookTitle/href/progression/backend/ttsBackend/ttsEngine`；状态 `Idle/Playing/Paused/Stopped`；`initState` 读设置/取章文本/`segment`/`sentenceIndexAt` 定位/`configure`/`speak`（**不写盘**）；`ListenControlBar`（线框 09：章节名/⏮/⏸▶/⏭/Slider/`1.0x`/定时禁用/音色禁用）；AppBar 设置入口（tooltip '听书设置'） | T-004, T-005 | 1d | **US-1/US-2/US-3/US-10/US-12**：`find.byType(ListenPage)` 可达且构造参数存在；起播 `speak` 句索引==`sentenceIndexAt(progression)` 且进入未调用 `saveProgress`；控制条逐控件 `find.byType/find.text` 存在、定时/音色按钮禁用；暂停/播放/停止调用序列 `pause/resume/stop` + 图标态；失败提示含"语音/安装" |
| **T-007** | **听读进度同步 + 句级进度条拖动**（ADR 决策点4，design §4.2/§4.4/§4.5）：句完成 → `_saveProgressDebounced(locator)`（300ms 防抖 + `_dirty`）→ `backend.saveProgress(href,progression)`；拖动松手 `j=round(v*(N-1)).clamp` → `stop+speak(j)+saveProgress`；返回/`dispose` 强制刷；返回阅读页由 T-010 重读 | T-006 | 1d | **US-14/US-15/US-16**：fake 引擎发 `TtsSentenceDone(i)` → `backend.saved.href/progression == 句 i 的 locator`；连续多句都更新；拖动松手 `speak(句 j)` + 保存句 j；退出强刷（防抖窗口内不丢）；`0<=j<N` 不越界 |
| **T-008** | **跟读高亮 + 章末连播**（ADR 决策点4，design §4.2/§4.6/§5.1）：`ListenFollowHighlight`（`chapterText.substring(charStart,charEnd)` 高亮当前句，推进切换）；`auto_next` 开关（默认开）：`TtsSentenceDone(N-1)` → 加载下一章 `segment` + `speak(句 0)` + `saveProgress(nextHref,0)`；关闭 → `Stopped`；末章 → `Stopped` | T-006, T-007 | 1d | **US-17/US-18**：高亮子串 == `chunk.text`，推进后旧句不高亮/新句高亮；连播开→`href` 变下一章、`speak` 首句为新章句 0；关→不加载、`Stopped`；末章停止不越界 |
| **T-009** | **听书设置面板 + 语速**（ADR 决策点4/6，design §2.6/§4.3/§5.2/§8）：`ListenSettingsSheet`（线框 10：系统男/女声可选；AI/Piper/克隆禁用灰置 + "需网络（P2）"/"下载 52MB（P2）"/"评估中"；语速 Slider 0.5–3.0x；定时关闭全部禁用；后台播放禁用；隐私文案）；语速变更 → `configure(speed)` + 文本更新 + `saveListenSettings`；P2 控件 `onChanged==null` | T-006, T-003, T-005 | 1d | **US-11/US-13**：面板逐项存在；系统男/女声可选；P2 控件 `onChanged==null`（点击无状态变更、不崩溃）；语速拖动 → `configure(speed)` + `"1.5x"` 文本 + `listen.speed` 往返；范围 clamp `[0.5,3.0]` |
| **T-010** | **阅读页入口接线 + 返回重读进度 + 复制修复**（ADR 决策点5/关联裁定8，design §2.6/§4.5）：`_openMore` 听书项 `pop` 后 `push ListenPage(...)` 并传参；`ReaderPage` 新增可选 `ttsBackend/ttsEngine`（null 懒创建 `RustTtsBackend`/`SystemTtsEngine`）；`await push` 后 `_reloadProgress()`（`loadProgress` → 章节索引 + `_chapterProgress` + 跳转）；`reader_page.dart:383-386` 复制改 `Clipboard.setData`（US-22 P1 可选） | T-006 | 1d | **US-1/US-2/US-15/US-22**：点"听书"→ 弹层关闭 + `find.byType(ListenPage)` 为 1（不得只 pop 回沉浸态）；fake `loadProgress` 返回值在返回后生效（同章同 progression）；注入 fake `ttsEngine` 生效；复制 → `Clipboard.getData` == 选中文本（若排期紧张可延后，不阻塞 P0） |
| **T-011** | **分页模式禁用原生选择菜单（可测工厂）**（ADR 决策点2，design §2.5/§4.7）：`paged_web_view.dart` 提取顶层 `buildPagedWebViewSettings({bool disableContextMenu = true})`，`build()` 使用且 `disableContextMenu: true`；保留 `selectionchange` 回传与 `onSelectedText`；`next/prev/gotoPage/relayout` 及 fake 构建器契约零改动 | — | 0.5d | **US-19/US-20/US-21**：`buildPagedWebViewSettings().disableContextMenu == true`；`buildPagedWebViewSettings(disableContextMenu:false).disableContextMenu == false`（可覆盖）；fake 分页构建器触发 `onSelectedText` → 工具条出现、五入口齐全；滚动模式 `SelectionArea.contextMenuBuilder` 仍返回 `SizedBox.shrink`、`AdaptiveTextSelectionToolbar` findsNothing |
| **T-012** | **测试基础设施 + 用例补齐**（design §7，02-plan 本表 US 映射）：新增 `app/test/fake_tts_engine.dart`（记录 `configure/speak/pause/resume/stop` 调用序列 + 可控发 `TtsSentenceDone(i)`/`TtsFailed`）、`app/test/fake_tts_backend.dart`、`app/test/listen_page_test.dart`、`app/test/tts_engine_test.dart`、`app/test/tts_ffi_test.dart`（或并入 `rust_bridge_test.dart`）；更新 `reader_page_test.dart:170-182`（"4 占位项"→"听书可跳转 + 其余占位"）；回归 `reader_selection_test.dart`/`translate_reader_test.dart`/`library_page_test.dart` | T-006..T-011 | 1d | **US-23/US-24/US-25**：`flutter test` 全绿；九项 widget 用例（入口/播放暂停停止/语速/句完成写盘/退出重开/跟读/连播/禁菜单配置/滚动只自定义工具条）逐项存在；`cargo test -p reader_core` 全绿；既有测试除明确更新文件外零改动且通过 |
| **T-013** | **全量回归 + 原型一致性自检 + 真机验收清单**（design §5/§6）：`cargo test` + `flutter test` + FFI 端到端（打开书/进度/三 tts 函数/设置往返）；CRAP/DDD 报告（FAIL=0、违规=0）；逐屏对照 09/10/04-selection + README 输出偏差清单（deviation=0）；输出 Android 真机手工清单（分页无 ActionMode、离线出声、语速生效、退出续读） | T-012 | 1d | **US-25 + 闸门3 前置**：全量回归绿；`03-crap-report.md`/`03-ddd-report.md` 就绪（违规=0/FAIL=0）；原型自检清单逐屏打勾、deviation=0；真机清单含 4 项待验（缺失项在 04/05 明确记录） |

## 依赖图（无环）

```
T-001 ─→ T-002 ─┬→ T-003 ─┐
                │         ├→ T-005 ─┐
T-004 ──────────┴─────────┘         │
                T-004 ──────────────┤
                                    ▼
T-005 ─→ T-006 ─┬→ T-007 ─→ T-008 ─┐
                ├→ T-009 ───────────┤
                └→ T-010 ───────────┤
T-011 ──────────────────────────────┤
                                    ▼
T-006..T-011 ─→ T-012 ─→ T-013
```
- 关键路径：**T-001 → T-002 → T-003 → T-005 → T-006 → T-007 → T-008 → T-012 → T-013 ≈ 8d**（T-004 为独立源点、与 T-003 并行汇入 T-005；T-009/T-010/T-011 不占关键路径）。
- 无依赖环（DAG：T-001/004/011 为源点；T-013 为汇点）。

## US → Task 覆盖矩阵

| US | 主责 Task | US | 主责 Task |
|---|---|---|---|
| US-1 | T-006, T-010, T-012 | US-14 | T-007, T-012 |
| US-2 | T-006, T-007, T-010 | US-15 | T-007, T-010, T-012 |
| US-3 | T-006, T-012 | US-16 | T-007, T-012 |
| US-4 | T-001, T-012 | US-17 | T-008, T-012 |
| US-5 | T-001, T-012 | US-18 | T-008, T-012 |
| US-6 | T-001, T-012 | US-19 | T-011, T-012 |
| US-7 | T-002, T-005, T-012 | US-20 | T-011, T-012 |
| US-8 | T-001 | US-21 | T-011, T-012, T-013 |
| US-9 | T-004, T-012 | US-22 | T-010, T-012（P1 可选） |
| US-10 | T-006, T-012 | US-23 | T-012 |
| US-11 | T-003, T-009, T-012 | US-24 | T-001, T-012 |
| US-12 | T-004, T-006, T-012 | US-25 | T-012, T-013 |
| US-13 | T-009, T-012 | — | — |

## 原型一致性自检清单（T-013 执行，deviation=0）

| 屏 | 核对项（对照 svg 逐项） |
|---|---|
| `09-listen-player.svg` | 正文区当前句高亮（蓝色半透明、推进切换）；控制条第 1 行章节名；第 2 行 `⏮`/`⏸▶`/`⏭`；第 3 行句级 `Slider` + `1.0x`；右侧 `⏱ 定时` 与 `🎙 音色` 两个**禁用占位**按钮；顶部听书标题 + 设置入口。**不实现**底部"迷你播放条/空格/←→"说明（P2） |
| `10-listen-settings.svg` | 标题"听书设置"；音色分组 5 行（系统男/女声可选；AI/Piper/克隆禁用灰置 + 线框文案）；语速滑块 0.5x—3.0x + 当前值文本；定时关闭分组 5 项全禁用；后台播放开关禁用；面板外隐私说明文案 |
| `reader-ui-v2/04-selection.svg` | **回归守护（不改布局）**：分页选区回传后浮动工具条 5 入口（划重点/笔记/翻译/查词/复制）+ 笔记 4 色圆点；滚动模式 `contextMenuBuilder → SizedBox.shrink()`；`AdaptiveTextSelectionToolbar` findsNothing |
| `README.md` | 线框 09/10 清单与评审要点核对（P2 项灰置、系统音色可选、语速即时生效、听读同进度） |

## 冲突检查结果

- **与 ddd-rules 无冲突（1 项未声明层已处置）**：
  1. `core/src/tts`（domain）文本入参后仅 `use crate::types`，不触 `crate::store/library/api` → 违规=0；
  2. `core/src/api.rs`（interface）可 `use crate::library`/`crate::tts`（interface 无 `forbid_internal`）；
  3. `app/lib/engines/system_tts_engine.dart`（interface）只 import `flutter_tts` + `tts_engine.dart`，不 import `src/rust/`；`app/lib/pages/listen_page.dart` 经 `TtsBackend` 取 DTO；
  4. `app/lib/services/tts_backend.dart`/`rust_tts_backend.dart`（application）负责生成物→DTO（先例 `rust_library_backend.dart`）；
  5. **`app/lib/widgets/listen_*.dart` 未被 ddd-rules 声明**（与 REQ-004 同）：处置 = 规则表冻结零改动，新增 widget 按 pages 同级纪律（只经 services/engines、禁 `package:reader_app/src/rust/`、`src/rust/`），03-review 人工核对 import 面；建议后续评审把 `app/lib/widgets` 纳入 interface paths（记录不执行）。
- **与 Locator / 听读同进度无冲突**：`core/src/types.rs` 零改动（只加 `LocatorView` 桥接 DTO）；`reading_progress` 为唯一事实源，进入听书不写、句完成/拖动/退出写、返回重读；零新表/零迁移。
- **与 REQ-001/003/004 复用不重做**：`LibraryBackend`/`TranslateBackend`/`ReaderSelectionToolbar`/`SelectionArea`/`translation_popup` 零改动；`PagedWebView` 仅加 settings 工厂（既有 JS/handler/fake 构建器契约不变）；`_openMore` 听书项由占位改跳转（`reader_page_test.dart:170-182` 预期同步更新）。
- **与原型一致性无冲突**：09/10/04-selection 逐屏映射（design §5 + 本表自检清单）；无自创布局；US-3/US-13 入口措辞冲突以 ADR 关联裁定1 处置（设置入口移至 AppBar）。
- **范围划界（P2 不做）**：定时关闭/后台播放/媒体键/多音色/AI/Piper/克隆/点读/笔记/划重点均不实现，线框 09/10 中以 `onChanged:null`/`onPressed:null` 禁用灰置；`just_audio`/`audio_service` 保持注释；US-22 复制为 P1 可选，不阻塞 P0。
- **文档同步风险（已登记）**：`docs/03 §4/§13.3`（新增 `tts_listen_settings_get/set`、tts 三函数 async、`idx:u32`、`LocatorView`）与 `docs/04 §9.5`（domain 文本入参）需在开发/交付阶段同步；本阶段按纪律只产出 3 份产物，**未改 docs**。

## 闸门2 自评（计划部分）
- [x] **任务粒度可执行**：T-001..T-013 每项 ≤1 天（0.5~1d），验收均可断言并映射 US-1..US-25（见覆盖矩阵）；每项含 file/行为与测试断言。
- [x] **依赖图无环**：DAG 已标注（源点 T-001/T-004/T-011，汇点 T-013），关键路径 ≈8.5d。
- [x] **冲突清单为空或已含处置**：ddd-rules（含 widgets 未声明）、Locator/听读同进度、REQ-001/003/004 回归、原型一致性、范围划界、文档同步风险共 6 类，全部无冲突或已列处置。
- [x] **ADR 备选 ≥2 且给出理由**：6 个决策点各 ≥2 备选 + 拒绝论证 + 降级线（详见 02-adr）。
- [ ] **待同步项**：`docs/03`/`docs/04` 文档同步（非本阶段产物）标记为交付前风险，不阻塞闸门2（本阶段只产出 3 份产物）。
