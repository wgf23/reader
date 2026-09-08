<!-- wf-meta: req=REQ-005-fixes | phase=delivery | agent=release-manager | date=2026-09-08 | gate=passed -->
# REQ-005-fixes · 阶段5 交付（验证汇总 / 发布说明 / 追溯矩阵）

> 范围：**听书链路贯通**（入口 → 系统离线 TTS → 播放控制/语速/跟读/连播 → 听读同进度）
> + **分页模式禁用 WebView 原生选择菜单**（回归守护滚动模式）
> + 相邻缺陷「复制」修复（P1 可选，已实现）。
> 版本：`0.6.3+9` → **`0.6.4+10`**（语义化补丁版本）。分支：`wf/REQ-005-fixes`。
>
> 闸门5 自评：**① 追溯矩阵全闭合（US-1..US-25，孤儿=0）② 全量回归绿 ③ 发布产物齐全（Linux 可构建；
> Android 因本机无 SDK/NDK 无法构建，已如实登记与给出复现命令）** → **passed**。

---

## 1. 全量回归（release-manager 独立复跑，非引用他人数字）

环境：本机无 `/home/heiwa/workspace/.toolchain/env.sh`（**未** source）；
`export PATH="/root/flutter/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"`；`CARGO_BUILD_JOBS=2`。

| # | 检查 | 命令 | 本次实测结果 | 结论 |
|---|---|---|---|---|
| 1 | core 全量单测 | `cd core && cargo test --release` | **207 passed / 0 failed**（lib 170 + mobi_azw3 21 + p0_corpus 5 + translate_corpus 8 + tts_api 3；Doc-tests 0） | ✅ 绿 |
| 2 | Flutter 全量 | `cd app && flutter test` | **77 passed / 3 skipped / 0 failed** | ✅ 绿 |
| 3 | Flutter 静态分析 | `cd app && flutter analyze` | **No issues found!（0）** | ✅ 0 |
| 4 | FFI 端到端 | `cargo build --release` 后 `READER_CORE_SO=../core/target/release/libreader_core.so flutter test test/rust_bridge_test.dart test/tts_ffi_test.dart` | **2 passed / 0 failed**（导入真实中文 EPUB→章节/资源/进度；tts_segment / locator 往返 / 听书设置） | ✅ 绿 |
| 5 | DDD 分层 | `scripts/ddd-lint/target/release/ddd-lint check . --rules workflow/rules/ddd-rules.toml --out workflow/reports/ddd-req005-delivery.md` | **违规=0**（`workflow/reports/ddd-req005-delivery.md`） | ✅ 0 |
| 6 | CRAP | `scripts/crap/target/release/crap scan core --cov workflow/reports/coverage-req005.json --config workflow/rules/crap-config.toml --out workflow/reports/crap-req005-delivery.md` | **FAIL=0，WARN=7（均既有函数），PASS=291**（`workflow/reports/crap-req005-delivery.md`） | ✅ FAIL=0 |
| 7 | 变异抽查（重跑） | `cd core && cargo mutants --file src/store/mod.rs --re 'get_setting\|set_setting' --timeout 60 --jobs 2 --output /tmp/opencode/mutants-relcheck` | **4 mutants：4 caught / 0 missed**（60s） | ✅ |
| 8 | 变异原始结果复核 | `/tmp/opencode/mutants-{tts,api,store,321}` | tts **109 caught / 0 missed**（15 timeout / 4 unviable）；api **9/0**；store+library **8/0**；321:13 隔离复核 **3/0** | ✅ 存活=0 |
| 9 | 发布构建（可执行） | `cd app && flutter build linux --release` | **✓ Built bundle**（`build/linux/x64/release/bundle/`，39 MB / 18 文件，`version.json = 0.6.4+10`） | ✅ 可构建 |
| 10 | 发布构建（Android APK） | `bash scripts/build-android.sh` | **无法执行**（本机无 `~/Android/Sdk`、无 NDK、无 `.toolchain/env.sh`） | ⚠ 环境受限（见 §5） |

- 变异总口径（闸门4）：`killed/(killed+survived) = 127/127 = 100%`，存活=0；含超时严格口径 `127/(127+14)=90.1%`（≥80%）。
- 覆盖率（闸门4）：Rust 本 REQ 新增/改动行 **98.3%**（`core/src/tts/mod.rs` 98.4%）；Dart 新增 8 文件 **85.1%**（排除真实 WebView 固有不可测后 **99.5%**）。
- US-8 性能：`segment_100k_chars_under_budget` 本次随 `cargo test --release` 通过（断言 ≤200ms；03-review 实测 11.25 万字 / 12500 句 = **6.52ms**，预算 <50ms）。

---

## 2. 需求追溯矩阵（US-1..US-25，逐条闭合 · 无孤儿）

> 状态图例：**✅** = 已实现且测试/配置证据闭合；**✅\*** = 上述均闭合，另有**真机项**待手工验收
> （统一指向 `03-review.md` §5 的 4 项清单，不阻塞闸门5）。
> 原型图：`docs/wireframes/09-listen-player.svg` / `10-listen-settings.svg` / `reader-ui-v2/04-selection.svg`；
> 「—」= 无专属线框（后端/入口/工程项）。

| US | 原型图 | 设计（02-design § / ADR 决策点） | 实现文件 | 测试证据（具体测试名 / 断言） | 状态 |
|---|---|---|---|---|---|
| **US-1** 听书入口进入听书页 | —（入口） | §2.6/§4.1；ADR 决策点5 | `reader_page.dart`（`_openMore`）、`listen_page.dart` | `reader_page_test.dart`「⋯更多弹层：听书可跳转 ListenPage，其余三项仍占位（US-1/US-25）」 | ✅ |
| **US-2** 当前阅读位置起播、进入不改位置 | 09 | §4.1；ADR 决策点1(a)/4 | `listen_page.dart`（`initState`）、`services/tts_backend.dart` | `listen_page_test.dart`「US-2 从当前阅读位置起播且进入不写盘」 | ✅ |
| **US-3** 听书页布局符合线框 09 | 09 | §2.6/§5.1 | `widgets/listen_control_bar.dart`、`listen_page.dart` | `listen_page_test.dart`「US-3 控制条含线框 09 控件，定时/音色禁用」 | ✅ |
| **US-4** `tts::segment` 中文切句 | — | §2.1；ADR 决策点1(a)/1(b) | `core/src/tts/mod.rs`（`segment`/`delimiter_end`/`sentence_starts`） | `core/src/tts/mod.rs`：`splits_chinese_punctuation_and_keeps_closing_quotes`、`does_not_merge_across_paragraphs`、`ellipsis_run_is_single_delimiter`、`ascii_abbreviation_not_split`、`empty_or_whitespace_returns_empty_vec`、`long_run_without_punctuation_is_one_sentence`、`pure_punctuation_each_becomes_sentence_and_ranges_continuous`、`crlf_and_blank_lines_force_sentence_breaks`、`mixed_chinese_english_splits_on_both_punctuation_sets`、`decimal_and_version_numbers_not_split` | ✅ |
| **US-5** `locator_for_sentence` 句→Locator | — | §2.1/§2.2 | `core/src/tts/mod.rs` | `core/src/tts/mod.rs`：`locator_fields_and_monotonic_progression`、`locator_for_sentence_out_of_range_errors` | ✅ |
| **US-6** `sentence_index_at` Locator→句索引 | — | §2.1/§2.2 | `core/src/tts/mod.rs` | `core/src/tts/mod.rs`：`roundtrip_index_at_locator_for_sentence`、`sentence_index_at_boundaries`、`sentence_index_at_rejects_bad_input`、`sentence_index_at_exact_boundary_and_epsilon`、`sentence_index_at_rejects_non_finite_and_out_of_range` | ✅ |
| **US-7** FFI 三函数 + 契约对齐 | — | §2.2/§2.3/§2.4；ADR 决策点1(b) | `core/src/api.rs`、`core/src/frb_generated.rs`、`app/lib/src/rust/*`、`services/rust_tts_backend.dart` | `core/tests/tts_api.rs`：`tts_segment_fields_source_and_error_paths`、`tts_locator_roundtrip_and_error_paths`；`tts_ffi_test.dart`「FFI：tts_segment / locator 往返 / 听书设置（US-7/US-11）」（真实 `.so`） | ✅ |
| **US-8** 切句性能预算 | — | §2.1 | `core/src/tts/mod.rs` | `core/src/tts/mod.rs`：`segment_100k_chars_under_budget`（本次 cargo test 通过；实测 6.52ms < 50ms，CI ≤200ms） | ✅ |
| **US-9** `SystemTtsEngine` + `flutter_tts` 启用 | 09/10 | §2.5；ADR 决策点3 | `engines/system_tts_engine.dart`、`engines/tts_engine.dart`、`pubspec.yaml` | `tts_engine_test.dart`：`SystemTtsEngine implements TtsEngine（US-9）`、`configure 触发 setSpeechRate/setVoice（US-9）`、`speak 触发 flutterTts.speak(chunk.text)（US-9）` | ✅ |
| **US-10** 播放/暂停/停止 | 09 | §4.3 | `listen_page.dart`、`engines/system_tts_engine.dart` | `listen_page_test.dart`：「US-10 暂停/播放/停止调用引擎并切图标」「US-10 Stopped 态点播放 → 从当前句重读」；`tts_engine_test.dart`「pause/resume/stop 转发（US-10）」 | ✅ |
| **US-11** 语速可调 + 记忆 | 10 | §4.3/§5.2；ADR 决策点6 | `widgets/listen_settings_sheet.dart`、`listen_page.dart`、core settings 通道 | `listen_page_test.dart`「US-11 语速调节触发 configure + 文本更新 + 持久化」；`tts_ffi_test.dart`（`listen.speed` 往返/clamp）；`tts_engine_test.dart`「configure 触发 setSpeechRate/setVoice（US-9）」 | ✅\* 真机语速即时变化待验（03-review §5-3） |
| **US-12** 完全离线朗读 | 09/10 | §2.5/§4.1 | `engines/system_tts_engine.dart`、`listen_page.dart` | `tts_engine_test.dart`：「离线约束：引擎/服务层无网络依赖（US-12）」「错误回调派发 TtsFailed（US-12）」「枚举音色失败 → 回退默认音色不阻断（US-12）」；`listen_page_test.dart`：「US-12 TtsFailed → 可读提示含 语音/安装」「US-12 连续失败 >5 次 → 停止播放」「US-12 末句失败 → 停止播放」 | ✅\* 真机离线出声待验（03-review §5-2） |
| **US-13** 听书设置面板符合线框 10 | 10 | §5.2/§8；关联裁定1 | `widgets/listen_settings_sheet.dart`、`listen_control_bar.dart` | `listen_page_test.dart`「US-13 设置面板：系统音色可选，P2 控件禁用灰置」；`tts_engine_test.dart`「configure 女声：从系统音色表挑选 female（US-13）」 | ✅ |
| **US-14** 句完成写 `reading_progress` | 09 | §4.2 | `listen_page.dart`（`_saveProgressDebounced`） | `listen_page_test.dart`：「US-14 句完成写 saveProgress（300ms 防抖）」「US-14 防抖：300ms 内连续完成只落盘最后一次」 | ✅ |
| **US-15** 退出听书/重开位置一致 | 09 | §4.5 | `listen_page.dart`（退出强刷）、`reader_page.dart`（`_reloadProgress`） | `listen_page_test.dart`「US-15 退出强刷进度，重开位置一致」；`reader_page_test.dart`「听书返回后阅读页重读进度（US-15）」 | ✅\* 真机杀进程重开待验（03-review §5-4） |
| **US-16** 进度条拖动 = 移动阅读进度 | 09 | §4.4 | `listen_page.dart`、`listen_control_bar.dart` | `listen_page_test.dart`：「US-16 拖动进度条松手 → speak 句 j + saveProgress」「US-16 拖动到两端 clamp 到首句/末句」「控制条拖动中仅本地预览，松手才回调 onSeek」 | ✅ |
| **US-17** 跟读当前句高亮 | 09 | §2.6/§5.1 | `widgets/listen_follow_highlight.dart`、`listen_page.dart` | `listen_page_test.dart`：「US-17 跟读高亮子串 == 当前句，推进切换」「跟读高亮越界区间被 clamp，不抛异常」 | ✅ |
| **US-18** 章末自动连播开关 | 10 | §4.6 | `listen_page.dart` | `listen_page_test.dart`：「US-18 章末连播：开 → 下一章句 0」「US-18 章末连播：关 → 不加载下一章、Stopped」「US-18 末章末句 autoNext 开 → Stopped 不再加载」「US-18 下一章加载失败 → 可读错误且停止」 | ✅ |
| **US-19** 分页禁用 WebView 原生选择菜单 | 04-selection | §2.5/§4.7；ADR 决策点2 | `engines/paged_web_view.dart`（`buildPagedWebViewSettings`） | `listen_page_test.dart`「US-19 buildPagedWebViewSettings 禁用 WebView 原生选择菜单（可覆盖）」（`disableContextMenu == true`） | ✅\* Android 真机长按无 ActionMode 待验（03-review §5-1） |
| **US-20** 禁用菜单后选区回传仍可用 | 04-selection | §4.7 | `engines/paged_web_view.dart`（`selectionchange`）、`reader_page.dart`（`_onSelectedText`） | `translate_reader_test.dart`「US-15 分页模式：选中回调产生 → 同一翻译入口可用」（模拟 JS 选区回传）；`reader_selection_test.dart`「滚动模式：真实长按正文 → 浮动工具条出现且含翻译/查词」（五入口齐全） | ✅\* 真机不出现第二套菜单待验（03-review §5-1） |
| **US-21** 滚动模式只有自定义工具条 | 04-selection | §4.7/§6 | `reader_page.dart:601`（`contextMenuBuilder → SizedBox.shrink()`） | `reader_selection_test.dart`「滚动模式：真实长按正文 → 浮动工具条出现且含翻译/查词」（仅自定义工具条）；`reader_page_test.dart`「分页模式渲染（initialPagedMode）」；代码断言 `reader_page.dart:601`；orchestrator Android 探针 `AdaptiveTextSelectionToolbar=0`（01-req R2-1） | ✅ |
| **US-22** 工具条「复制」写剪贴板（P1 可选） | 04-selection | §2.6 | `reader_page.dart`（`Clipboard.setData`） | `reader_page_test.dart`「US-22 选中工具条"复制"写入系统剪贴板」（mock `Clipboard.setData` 内容 == '很久以前'） | ✅ |
| **US-23** widget 测试覆盖关键交互 | — | §7 + 02-plan T-013 | `app/test/*` | 本次 `flutter test` **77 passed / 3 skipped / 0 failed**（`listen_page_test` 28、`tts_engine_test` 16、`reader_page_test`、`reader_selection_test`、`translate_reader_test`、`library_page_test`、`settings_page_test` 等） | ✅ |
| **US-24** core 测试更新 | — | §2.1 | `core/src/tts/mod.rs`（测试模块）、`core/tests/tts_api.rs` | 本次 `cargo test --release` **207 passed / 0 failed**（`tts/mod.rs` 40+ 用例 + `tts_api.rs` 3） | ✅ |
| **US-25** 既有功能零回归 | 04-selection | §6 | 既有代码零改动（`types.rs`/`library_backend.dart`/`library_page.dart`/04-selection UI） | 本次全量回归：`reader_page_test`、`reader_selection_test`、`translate_reader_test`、`library_page_test`、`settings_page_test`、`rust_bridge_test` 全绿 | ✅ |

**闭合统计**：US-1..US-25 共 **25 条** → **✅ 20 条 + ✅\* 5 条（US-11/12/15/19/20，真机项）= 25 条全部闭合；孤儿需求 = 0**。

---

## 3. 变更说明 · 语义化版本

### 3.1 版本变更

| 项 | 变更 |
|---|---|
| `app/pubspec.yaml` | `version: 0.6.3+9` → **`0.6.4+10`** |
| `core/Cargo.toml` | 保持 `0.1.0`（**内部 crate**，非独立发布单元；仓库发布惯例仅动 `app/pubspec.yaml`，见 `9f92ffc build(release): 版本 0.6.2 → 0.6.3`） |
| 其它显式版本引用 | `grep -rn "0.6.3" --include=*.yaml --include=*.dart --include=*.md .`（排除 backlog/ephemeral）→ **0 处**（Android `versionName/versionCode` 由 `flutter.versionName/versionCode` 从 pubspec 派生，无需另改） |

**语义化理由**：本 REQ 为 **P0 缺陷修复**（听书入口空转/引擎未实现/FFI 未桥接、分页模式原生选择菜单覆盖自定义工具条），无破坏性接口变更（`TtsEngine`/`Locator`/`reading_progress` 契约不变，新增桥接 DTO 与可选构造参数向后兼容）→ 按 SemVer 取**补丁号 +1**（`0.6.3 → 0.6.4`），构建号 +1（`+9 → +10`）。

### 3.2 变更内容

1. **听书链路贯通**：`_openMore`「听书」由仅 `pop` 改为 `pop` 后 `push ListenPage`；`ListenPage` 由占位 `StatelessWidget` 重写为 `StatefulWidget`（`Idle/Playing/Paused/Stopped` 状态机 + 引擎编排 + 控制条 + 跟读高亮 + 设置面板 + 句级进度条）。
2. **Rust 核心句级切分/映射 + FFI**：`core/src/tts/mod.rs` 实现 `segment`/`locator_for_sentence`/`sentence_index_at`（UTF-16 半开区间、中文标点/引号/省略号/缩写/中英混排/段落边界）；`api.rs` 新增 `LocatorView`/`SentenceChunkView`/`ListenSettingsView` + 5 个 async 桥接并再生成 FRB 绑定。
3. **系统离线 TTS + 播放控制**：`SystemTtsEngine`（封装 `flutter_tts`，`configure/speak/pause/resume/stop` + 完成/失败事件）；播放/暂停/停止、语速 0.5–3.0x 实时生效并记忆（`settings` 三键 `listen.voice_id/speed/auto_next`）。
4. **听读同一进度**：复用 `reading_progress`（零新表）；进入听书不写盘，句完成/拖动/退出写盘（300ms 防抖 + 退出强刷），返回阅读页重读定位。
5. **分页禁原生菜单**：`buildPagedWebViewSettings({disableContextMenu=true})` 工厂；`selectionchange` 选区回传与自定义工具条零改动；滚动模式 `contextMenuBuilder → SizedBox.shrink()` 回归守住。
6. **复制修复（P1 可选，已实现）**：`Clipboard.setData` 写入选中文本，失败静默。

---

## 4. 发布产物清单

| 项 | 内容 | 状态 |
|---|---|---|
| **源码** | 分支 `wf/REQ-005-fixes`；提交 `9a250c4`（feat 听书链路+分页禁原生菜单）、`d4b01d0`（test 变异/覆盖+边界）、`a505e5d`（test product-preview 真实截图）、本交付提交（`chore(release)` 版本+交付说明） | ✅ |
| **可执行产物（Linux 桌面）** | `app/build/linux/x64/release/bundle/`：`reader_app` + `lib/libapp.so` + `lib/libflutter_linux_gtk.so` + `data/`（含内置词典资产），**39 MB / 18 文件**；`data/flutter_assets/version.json = {"version":"0.6.4","build_number":"10"}` | ✅ 已构建（**不入库**：`app/.gitignore:33 /build/`；与仓库发布惯例一致，release 提交仅含 `app/pubspec.yaml`） |
| **Android APK** | 预期 `dist/reader-android-arm64-v0.6.4.apk` | ⚠ **本机无法构建**：`~/Android/Sdk` 不存在、无 NDK r27、无 `.toolchain/env.sh`。复现命令：`bash scripts/build-android.sh`（前置见 `workflow/skills/build-android.md`：JDK21 + Android SDK/NDK r27 + rustup android targets） |
| **macOS / Windows** | 由 `workflow/skills/build-platform.md` 覆盖（macOS zip 可交叉；Windows 需 Windows 宿主） | ⚠ 本 REQ 未构建（非本次环境目标） |
| **质量报告** | `workflow/reports/{ddd-req005-delivery.md, crap-req005-delivery.md, coverage-req005.json}`；变异原始结果 `/tmp/opencode/mutants-*` | ✅ |

**Linux 产物运行说明（如实）**：`flutter build linux` 的 CMake 未把 `libreader_core.so` 复制进 `bundle/lib/`（既有打包现状，非本 REQ 引入）。运行需将 `core/target/release/libreader_core.so` 放入 `bundle/lib/`（rpath `$ORIGIN/lib`）或 `--dart-define=READER_CORE_SO=<path>`。已做 headless 冒烟：`Xvfb` 下 `./reader_app` 运行 20s 无崩溃（超时终止），但启动未触发 Rust 加载，故**仅证明可启动，不替代打开书籍的运行时验证**。

---

## 5. 闸门链汇总

| 闸门 | 结论 | 关键数字 |
|---|---|---|
| 闸门1 需求 | passed | US-1..US-25 全部可断言；影响面 7+3 根因 |
| 闸门2 架构 | passed | ADR 6 决策点（每点 ≥2 备选）；02-design §7 US 全映射 |
| 闸门3 开发 | passed | cargo 207/0、flutter 77/3skip/0、analyze 0、ddd 0、CRAP FAIL=0、原型 deviation=0 |
| 闸门4 测试 | passed | 变异 **127/127=100%**（存活 0，严格口径 90.1%）；覆盖 Rust 98.3% / Dart 85.1%（排除固有不可测 99.5%） |
| 闸门5a 产品预览 | passed | 3 屏全通过、deviation=0、无 rework |
| **闸门5b 交付（本阶段）** | **passed** | 追溯 25/25 闭合（孤儿 0）、全量回归绿、Linux 可构建 / Android 如实登记 |

---

## 6. 已知限制 / 交接项（不阻塞闸门，如实登记）

| # | 项 | 说明 | 处置 |
|---|---|---|---|
| 1 | **Android 真机 4 项手工验收** | ① 分页长按无原生 ActionMode（US-19/US-20）② 离线出声（US-12）③ 语速即时生效（US-11）④ 退出/杀进程重开续读（US-15） | 清单见 `03-review.md` §5；widget/FFI 层已兜底，待真机执行 |
| 2 | **真实 WebView 固有不可测** | `paged_web_view.dart` 除 `buildPagedWebViewSettings` 工厂外为平台视图（覆盖 2.7%，工厂 100%）；US-19 以配置断言兜底 | 真机/集成覆盖；报告已单列（04-coverage §4） |
| 3 | **设计稿横屏 vs 实现竖屏** | 线框 09/10/04-selection 均 900×640 横屏，实现为 1170×2532 竖屏（逻辑 390×844）；结构/元素可校验，横向比例/间距级视觉还原无法校验 | 建议补 390×844 竖屏设计稿（非阻塞，05b-product-preview §4） |
| 4 | `RustTtsBackend.ensureTtsBackendInit` | 预留初始化入口，当前未被调用（与 `RustLibraryBackend.open` 共用幂等 init） | 保留，登记（03-review §7） |
| 5 | `Interrupted` 事件（音频焦点） | P2，本期未补，`TtsEvent` 保持 `TtsSentenceDone/TtsFailed` | 01-req §1.3 已授权；另立 REQ |
| 6 | Linux 包未自动打包 `libreader_core.so` | 既有 CMake 现状；运行需手动放入 `bundle/lib/` 或 `--dart-define` | 建议后续 REQ 修 CMake（非本 REQ 范围） |
| 7 | 未构建 Android APK / macOS / Windows | 本机无 SDK/NDK，且非本 REQ 交付目标 | 复现命令已列（§4）；CI/发布机执行 |
| 8 | `sentence_index_at` 每次重建 Locator 并重切句 | 章内句数有限、调用稀疏（起播/拖动），性能可接受 | 02-design §9.5 已记录；后续高频调用再引缓存 |
| 9 | `total_progression` 为章内近似 | 无全书权重，仅展示 | 02-design §9.3/关联裁定6 |

---

## 7. 合并建议

- **建议合并** `wf/REQ-005-fixes` → `main`（快进或普通合并）。
- **前置**：等待 orchestrator / 用户确认；**本代理不自行合并 main、不 force-push**。
- 合并前建议（非阻塞）：在具备 Android SDK/NDK 的环境执行 `bash scripts/build-android.sh` 产出 APK，并完成 `03-review.md` §5 的 4 项真机验收。
- 合并提交信息建议：`chore(release): REQ-005 v0.6.4 听书链路贯通 + 分页禁原生菜单（交付）`。

---

## 8. 本阶段产物

| 文件 | 变更 |
|---|---|
| `app/pubspec.yaml` | `0.6.3+9` → `0.6.4+10` |
| `workflow/backlog/REQ-005-fixes/05-delivery.md` | 新增（本文件，带 wf-meta 头） |
| `workflow/reports/ddd-req005-delivery.md` | 新增（ddd-lint 违规=0） |
| `workflow/reports/crap-req005-delivery.md` | 新增（CRAP FAIL=0 / WARN=7 / PASS=291） |
| `app/build/linux/x64/release/bundle/` | 本地构建产物（gitignored，不入库） |
