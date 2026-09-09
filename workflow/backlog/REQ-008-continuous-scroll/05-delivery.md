<!-- wf-meta: req=REQ-008-continuous-scroll | phase=delivery | agent=release-manager | date=2026-09-09 | gate=passed -->
# REQ-008-continuous-scroll · 阶段5b 交付（验证汇总 / 发布说明 / 追溯矩阵）

> 范围：滚动模式**连续滚动阅读**（一章到底自动衔接下一章，无需手动点"下一章"；末章自然停止），
> 并守住进度/听读/书签/分页零回退。
> 版本：`0.7.1+12` → **`0.8.0+13`**（语义化 **minor + build**：新增对外可感知功能，向后兼容；
> `reading_progress`/`Locator`/`ChapterData`/FFI DTO/schema 全零变更）。
> 分支：`wf/REQ-008-continuous-scroll`（基于 `main` `edfd10f`，REQ-007 已合并）。
> 代码提交：`7e5d97a`（开发）、`51b5746`（测试补强）、`86095a4`（产品验收截图）、`0f165db`（版本 bump）、本交付提交。
>
> **闸门5 自评：passed** —— ① 追溯矩阵全闭合（US-1..US-13 = 13/13，孤儿=0）
> ② 全量回归绿（cargo 222/0、flutter 198/4skip/0、集成逐文件 5+5+13、FFI 端到端 4/0、analyze 0、DDD 0；变异 N/A）
> ③ 发布产物齐全（`dist/reader-android-arm64-v0.8.0.apk`，版本/权限/ABI 独立 `aapt2` 校验通过）。

---

## 1. 验证结果汇总（release-manager 独立复跑，非引用他人数字）

环境：`export PATH=/root/flutter/bin:$HOME/.cargo/bin:$PATH`；`CARGO_BUILD_JOBS=2`；日期 2026-09-09。

| # | 检查 | 命令 | 本次实测结果 | 结论 |
|---|---|---|---|---|
| 1 | core 全量单测 | `cd core && CARGO_BUILD_JOBS=2 cargo test --release` | **222 passed / 0 failed**（lib 185 + mobi_azw3 21 + p0_corpus 5 + translate_corpus 8 + tts_api 3；integration 0；Doc-tests 0） | ✅ 绿 |
| 2 | Flutter 全量（普通） | `cd app && flutter test` | **198 passed / 4 skipped / 0 failed**（4 个 FFI 用例无 `.so` 时 `markTestSkipped`） | ✅ 绿 |
| 3 | Flutter 静态分析 | `cd app && flutter analyze` | **No issues found!（0 issues）** | ✅ 0 |
| 4a | 集成测试·连续滚动（核心） | `xvfb-run -a flutter test integration_test/reader_continuous_scroll_test.dart -d linux` | **5 passed / 0 failed**（US-1/2/3/4/8，真实 `ReaderPage`+真实 `drag`/`fling`） | ✅ 绿 |
| 4b | 集成测试·交互回归 | `xvfb-run -a flutter test integration_test/reader_interaction_test.dart -d linux` | **5 passed / 0 failed**（REQ-007 回归；finder 已改 `CustomScrollView`） | ✅ 绿 |
| 4c | 集成测试·截图 | `xvfb-run -a flutter test integration_test/screenshots_test.dart -d linux` | **13 passed / 0 failed**（13 张真实截图，含"连续滚动到第二章"） | ✅ 绿 |
| 5 | FFI 端到端（真实 `.so`） | `READER_CORE_SO=core/target/release/libreader_core.so flutter test test/{rust_bridge,rust_dict_ffi,translate_ffi,tts_ffi}_test.dart` | **4 passed / 0 skipped / 0 failed**（`rust_bridge` 1、`rust_dict_ffi` 1、`translate_ffi` 1、`tts_ffi` 1） | ✅ 绿 |
| 6 | DDD 分层 | `scripts/ddd-lint/target/release/ddd-lint check /root/reader --rules workflow/rules/ddd-rules.toml` | **违规总数：0**（新增均在 `app/lib/pages` interface 层，未 import `src/rust/`） | ✅ 0 |
| 7 | 变异抽查（引用 `04-mutation.md`） | `git diff --stat main -- core/` + `cargo mutants --list \| wc -l` | **core 对 main 零 diff**（空）；`--list` **1345** 全为既有变异体；本 REQ 新增 Rust 可变异点 **0** | ✅ N/A（基线 ≥80%） |
| 8 | 新代码覆盖（引用 `04-coverage.md`） | `flutter test --coverage` + 新代码行口径 | 新增/改动 Dart **256/260 = 98.46%**（三文件 100% / 100% / 97.62%） | ✅ ≥85% |
| 9 | Android APK 构建 | `bash scripts/build-android-local.sh` | **✓ 成功**：`dist/reader-android-arm64-v0.8.0.apk`，**48,383,561 B（46.1 MiB）** | ✅ 已构建（详见 §5/§6） |

> **一致性**：cargo 222 与 `04-coverage.md`（222）一致；flutter 198 passed / 4 skipped 与 `04-coverage.md`
> 一致（本阶段为普通口径，未带 `--coverage`）；集成 5+5+13=23 与 `03-review.md`（23）一致；变异/覆盖数字
> 引用 `04-mutation.md`/`04-coverage.md`（本阶段未重跑全量，仅复核 core 零 diff）。
> **唯一非绿输出**：`cargo test` 打印既有 `core/src/tts/mod.rs:572 unused variable: text` 警告（REQ-005 遗留，
> 非本 REQ 引入），不影响测试结果；`flutter build apk` 打印 `flutter_tts` KGP 弃用警告（未来兼容性提示，非失败）。

### 闸门 1–5 状态

| 闸门 | 结论 | 关键数字 / 证据 |
|---|---|---|
| 闸门1 需求 | ✅ passed | `01-req.md`：US-1..US-13 全部可断言；R1..R11 根因逐条 file:line；影响面 §3.1-§3.7 非空 |
| 闸门2 架构 | ✅ passed | `02-adr.md` D1..D8（每点 ≥2 备选 + 降级线）；`02-design.md` 接口/时序/逐屏映射；`02-plan.md` T-001..T-008 DAG 无环、US 覆盖全闭合 |
| 闸门3 开发 | ✅ passed | `03-review.md`；cargo 222/0、flutter 193/4skip、集成逐文件 23、analyze 0、DDD 0、原型 deviation=0 |
| 闸门4 测试 | ✅ passed | `04-mutation.md`（core 零改动 → N/A，基线 ≥80%）；`04-coverage.md` 新代码 256/260 = 98.46% |
| 闸门5a 产品验收 | ✅ passed | `05b-product-preview.md` S1/S2/S3 全通过、deviation=0、gap=0 |
| **闸门5b 交付（本阶段）** | **✅ passed** | 追溯 13/13 闭合（孤儿 0）、全量回归绿、发布产物齐全 + APK 独立校验 |

---

## 2. 变更说明（面向用户）

### 2.1 版本与语义化理由

| 项 | 变更 |
|---|---|
| `app/pubspec.yaml` | `version: 0.7.1+12` → **`0.8.0+13`** |
| `core/Cargo.toml` | 保持 `0.1.0`（内部 crate，非独立发布单元；发布惯例只动 `app/pubspec.yaml`） |
| 其它版本引用 | `README.md`/`docs/**` 无版本标注；Android `versionName/versionCode` 由 Flutter 从 pubspec 派生（`app/android/app/build.gradle.kts:28-29`，已核验 APK = `0.8.0/13`）；`app/android/local.properties` 为构建生成物（gitignored）。 |

**语义化理由（minor + build）**：本 REQ **新增对外可感知功能**——滚动模式从"单章到底需点下一章"变为
"连续滚动自动衔接下一章"，属向后兼容的功能增量，故取 **minor**（`0.7.1 → 0.8.0`），构建号单调 +1
（`+12 → +13`）。无破坏性契约变更：`reading_progress`/`Locator`/`ProgressData`/`ChapterData`/FFI DTO/schema
全零变更，分页模式、听书、书签、查词/翻译能力均保持。

### 2.2 用户可见变更

1. **连续滚动自动衔接（核心，US-1）**：滚动模式正文由 `SingleChildScrollView` 单章改为
   `SelectionArea` + `CustomScrollView` + `SliverList.builder` 按章懒构建的连续流；滚到章末**无需点
   "下一章"**，下一章标题 + 正文随滚动自然进入视口（章间距 32px，复用正文留白节奏，非新控件）。
2. **末章自然停止（US-2）**：滚到最后一章继续下滑自然停在 `maxScrollExtent`，不越界、不崩溃、不重复渲染；
   底栏"下一章"按既有语义禁用。
3. **可见章进度（US-3/US-5）**：滚动过程中写入**当前可见章**的 `href`（`chapter_%04d.xhtml`）与**章内**
   `progression`（`0.0..=1.0`）；顶栏章节名、底栏进度条随可见章切换，跨章时进度回到新章起点再增长。
4. **跨章恢复（US-4）**：重开同一本书按 `href + progression` 定位到"目标章起点 + 章内比例"（非全书 0%/第一章）。
5. **上一章/目录跳转（US-7）**：连续流中语义改为"滚动定位到目标章"，并立即落盘目标章进度。
6. **失败路径（US-10）**：某章内容不可用时保留已渲染相邻章、在该章位置内联非阻断 `OverlayError`
   （文案含"加载失败"），同一失败章 provider 调用有界（≤1 次，显式"重试"才清失败记忆），不崩溃。
7. **性能/内存有界（US-11）**：`scrollCacheExtent: 250` + `SliverList` 懒构建，50 章书滚到第二章时已构建
   章数 ≤3（≠50），不一次性构建全书。
8. **零回退（US-8/US-9）**：听书跨章与听读同进度、书签会话内切换、分页模式翻页/切章、`href`/`progression`
   契约、Aa 改主题后锚定均保持可用。

### 2.3 变更文件清单（提交 `7e5d97a` + `51b5746`）

- 新增生产代码：`app/lib/pages/continuous_scroll_policy.dart`（+228）、`app/lib/pages/progress_saver.dart`（+65）。
- 修改生产代码：`app/lib/pages/reader_page.dart`（±359）。
- 测试：`app/integration_test/reader_continuous_scroll_test.dart`（新）、`reader_interaction_test.dart`（1 处
  finder）、`screenshots_test.dart`（+1 截图）；`app/test/{reader_continuous_scroll,continuous_scroll_policy,
  progress_saver,reader_continuous_scroll_coverage}_test.dart`（新增）。
- **零改动**：`core/**`、`app/lib/services/**`、`app/lib/widgets/**`、`app/lib/engines/**`、`app/lib/src/rust/**`。

---

## 3. 已知问题与限制（不阻塞闸门，如实登记）

| # | 项 | 说明 | 处置 |
|---|---|---|---|
| 1 | **Android 真机 6 项手工验收（US-13）** | ① 滚动到底自动出现下一章；② 末章停止不崩溃；③ 重开恢复到该章位置；④ 听书跨章返回定位一致；⑤ 书签切换 + Aa 切分页翻页/切章；⑥ 改字号/行距/主题后仍锚定当前章 | 清单见 `03-review.md §5`；Linux 无 Android 真机/WebView，CI 不可自动化；待真机执行（追溯矩阵标 ✅\*） |
| 2 | **行距重排的 Flutter 框架 debug 断言** | `SelectionArea` + `CustomScrollView` + `RenderParagraph.getBoxesForSelection` 的框架级交互（`paragraph.dart:1134 !debugNeedsLayout`），**仅 debug 断言、release 不受影响**；已核实与本 REQ post-frame 重锚无关（临时禁用仍复现），最小探针无法复现 | US-9 以"改主题"等价路径断言；行距路径由真机 US-13⑥ 人工确认（`03-review.md §4.5`） |
| 3 | **集成测试目录级命令限制** | `flutter test integration_test -d linux`（一次跑目录内多文件）在本环境首个文件后报 `Unable to start the app on the device`（工具链限制，与代码无关）；REQ-007 阶段同款 | 采用**逐文件**运行：continuous 5 + interaction 5 + screenshots 13 = 23/0 全绿（§1 #4a-4c） |
| 4 | **视口方向 tradeoff** | 线框 900×640 横屏 vs 实现 1170×2532 竖屏（逻辑 390×844）；结构/元素可校验，横向比例无法校验 | 既有授权沿用（REQ-004..007）；`05b-product-preview.md §5` 建议补竖屏设计稿 |
| 5 | **分页路径 Linux 不可实跑** | `flutter_inappwebview` 无 Linux 实现 → 分页重载/翻页/进度条由 [widget 测试]（US-9）+ [真机] 兜底；`reader_page.dart:395`（分页 `_onProgressSeek`）固有不可测 | 真机 US-13⑤；见 `04-coverage.md §5` |
| 6 | **变异测试 N/A** | 纯 Flutter/UI REQ，`core/**` 对 `main` 零 diff（实测空）→ 无新增 Rust 可变异点；`cargo mutants --list` = 1345（全既有） | 沿用基线 REQ-003 98.5% / REQ-006 99.17%（保守 98.33%）/ REQ-007 定向 83.3%，均 ≥80%（`04-mutation.md`） |
| 7 | **jniLibs 二进制未入库** | `app/android/app/src/main/jniLibs/**/libreader_core.so` 为跟踪的构建中间物；本次构建重生成（core 零改动，按 `skills/build-android.md` 回退避免噪声） | 已 `git checkout` 回退；交付物为 APK；可复现构建见 `scripts/build-android-local.sh` |
| 8 | **构建噪声（非失败）** | `flutter_tts` KGP 弃用警告；`core/src/tts/mod.rs:572 unused variable: text`（REQ-005 遗留） | 不影响构建/测试，后续清理 |
| 9 | **截图 harness 默认 M3 主题** | 集成测试自建 `MaterialApp`，主色 `#6750A4`（非 `main.dart` indigo 种子色） | 既有 harness 已知限制（REQ-005/006 同款），不影响布局/控件/文案 |
| 10 | **macOS / Windows / iOS 产物** | 非本 REQ 交付目标 | 未构建（如实登记） |

> 无 rework-A/B/C/D（`STATE.md`：A=0 B=0 C=0 D=0）。

---

## 4. 追溯矩阵（US-1..US-13 全闭合 · 无孤儿）

> 状态图例：**✅** = 实现 + 测试/配置证据闭合；**✅\*** = 上述均闭合，另有**真机项**待手工验收
> （指向 `03-review.md §5` 清单，不阻塞闸门5）。
> 原型图：`reader-ui-v2/01-immersive.svg` / `reader-ui-v2/02-menus.svg` / `reader-ui-v2/04-selection.svg` /
> `reader-ui-v2/03-settings.svg`；「—」= 无专属线框（引擎/测试基建/真机项）。
> 设计列：`02-design.md` 章节 / `02-adr.md` 决策点；计划列：`02-plan.md` Task。
> 代码列：实现提交 `7e5d97a`（测试补强 `51b5746`）。

| US | 验收（`01-req.md §2`） | 原型图 | 设计（02-design § / ADR） | 实现（文件/提交 `7e5d97a`） | 测试证据（具体测试名/报告） | 状态 |
|---|---|---|---|---|---|---|
| **US-1** | 滚到章末自动出现下一章正文与标题（未点"下一章"） | 01-immersive | §2.4/§4.2；D1；T-001/T-007 | `pages/reader_page.dart`（滚动分支 `CustomScrollView`+`SliverList.builder`）、`pages/continuous_scroll_policy.dart`（`ChapterSection`） | 集成 `reader_continuous_scroll_test.dart`「US-1 真实滚到章末自动出现下一章正文与标题（未点"下一章"）」；widget `reader_continuous_scroll_test.dart`「US-6 滚到章末自动接续下一章：标题/正文各 1，无重复 Key 异常」 | ✅ |
| **US-2** | 到最后一章自然停止、不越界、不崩溃、不重复 | 01-immersive | §4.2；D1/D2；T-001/T-007 | `reader_page.dart`（`SliverList` 自然停止 + 触底锁）、`continuous_scroll_policy.dart`（`resolveVisibleChapter(atEnd)`） | 集成「US-2 最后一章自然停止：不越界、不崩溃、不重复」（`pixels==maxScrollExtent` 容差、`takeException()==null`、无第 4 章） | ✅ |
| **US-3** | 滚动写入"当前可见章" href + 章内 progression | 01-immersive + 02-menus | §2.1/§4.2；D3/D6；T-003/T-004/T-007 | `pages/progress_saver.dart`、`continuous_scroll_policy.dart`（`chapterProgression`）、`reader_page.dart`（`_onScroll`） | 集成「US-3 滚动写入"当前可见章" href + 章内 progression」；单测 `progress_saver_test.dart`（5 例：300ms 尾沿合并/flush/dispose/debounce/flush 无挂起）；`continuous_scroll_policy_test.dart`「chapterProgression」（5 例） | ✅ |
| **US-4** | 重开恢复到跨章位置（章起点 + 章内比例） | 01-immersive | §2.1/§4.1；D4；T-004/T-006/T-007 | `continuous_scroll_policy.dart`（`proportionalChapterOffset`）、`reader_page.dart`（`_scrollToChapter`/`_load`/`_reloadProgress`） | 集成「US-4 重开恢复到跨章位置（章起点 + 章内比例）」；widget `reader_continuous_scroll_coverage_test.dart`「恢复定位到未构建的远章：有界步进最终落到目标章（不崩溃）」；单测「proportionalChapterOffset」（5 例） | ✅ |
| **US-5** | 章内进度随滚动更新、跨章切换到新章进度 | 02-menus | §2.3/§4.2；D2/D3；T-002/T-004/T-006 | `reader_page.dart`（`_onScroll` 按需 `setState` 更新 `_chapterIndex`/`_chapterProgress`）；`widgets/reader_chrome.dart` 零改动 | widget `reader_continuous_scroll_test.dart`「US-5 顶栏章节名/底栏进度随可见章切换」；单测 `continuous_scroll_policy_test.dart`「resolveVisibleChapter」「chapterProgression」 | ✅ |
| **US-6** | 章末抖动/重复触发不得重复加载同一章 | 01-immersive | §2.1；D1/D2；T-002/T-006 | `continuous_scroll_policy.dart`（`resolveVisibleChapter` 迟滞 + `SliverList` 每章一 item） | widget「US-6 章末小幅抖动不重复加载/不抛异常」；单测 `continuous_scroll_policy_test.dart`「resolveVisibleChapter」（9 例：空/未越界/切前/迟滞带/回滚/触底/回滚到顶/非法视口） | ✅ |
| **US-7** | 上一章 / 目录跳转在连续流中仍正确 | 02-menus | §4.3；D4；T-004/T-006 | `reader_page.dart`（`_changeChapter`/`_scrollToChapter`，`_goChapter`/`_onChapterSelect` 统一） | widget「US-7 上一章 / 目录跳转在连续流中正确」（视口在目标章 + `backend.saved?.href`）；集成 US-1/US-2；`reader_continuous_scroll_coverage_test.dart` 远章恢复 | ✅ |
| **US-8** | 听读同进度：听书跨章与本 REQ 互不破坏 | —（无原型改动） | §4.4；D3；T-004/T-006/T-007 | `reader_page.dart`（`_openListen` 传可见章 `href`/`_chapterProgress`、`_reloadProgress`）；`pages/listen_page.dart` 零改动 | 集成「US-8 听书跨章写入后返回：定位一致 + 连续滚动仍可接续」；`listen_page_test.dart`「US-18 章末连播/末章停止/下一章加载失败」全绿；`reader_continuous_scroll_coverage_test.dart`「分页模式听书返回 → _reloadProgress 分页重排接线」 | ✅ |
| **US-9** | 书签 / Locator 契约 / 分页模式零回退 | 02-menus | §2.3/§3/§4.6；D3/D4；T-004/T-006/T-008 | `reader_page.dart`（书签 `setState` 沿用、分页分支零改动、切回滚动重锚）；`services/library_backend.dart`/`store/mod.rs` 零变更 | widget「US-9 书签切换 + 分页↔滚动互切后连续滚动仍工作」「US-9 Aa 改主题后仍锚定「当前可见章 + 章内比例」」；`reader_continuous_scroll_coverage_test.dart`「分页模式 onProgress 回调 → _saveProgress 立即落盘」；`reader_page_test.dart` 书签/分页用例全绿 | ✅ |
| **US-10** | 下一章不可用时的失败路径（保留内容 + 提示 + 有界重试） | —（复用 OverlayError，无新增原型） | §2.1/§4.5；D5；T-001/T-005/T-006 | `continuous_scroll_policy.dart`（`ChapterContentCache`）、`reader_page.dart`（`_buildChapterItem` 内联 `OverlayError` + `retry`） | 单测 `continuous_scroll_policy_test.dart`「ChapterContentCache」（4 例：成功记忆化/失败记忆化/retry 显式/不自动重试）+ `reader_continuous_scroll_coverage_test.dart`「maxAttempts=0」；widget「US-10 下一章不可用：保留当前章 + 非阻断提示 + provider 调用有界」 | ✅ |
| **US-11** | 已构建章节数有界，不一次性构建全书 | —（无原型改动） | §2.4；D1；T-001/T-006 | `reader_page.dart`（`CustomScrollView(scrollCacheExtent:250)` + `SliverList.builder`）、`continuous_scroll_policy.dart`（`ChapterSection`） | widget「US-11 50 章仅滚到第二章：已构建章数有界（≤3 且 ≠50）」（`find.byType(ChapterSection)` 计数） | ✅ |
| **US-12** | 真实 integration_test 范式 + 静态守卫（禁合成页） | —（测试基建） | §6；D8；T-007/T-008 | `integration_test/reader_continuous_scroll_test.dart`（新，真实 `drag`/`fling`）；`test/no_synthetic_chrome_test.dart` 零改动（自动扫描新文件） | `no_synthetic_chrome_test.dart`「integration_test/*.dart 禁止出现合成 ReaderTopBar(/ReaderBottomBar(」1 passed；本次 `reader_continuous_scroll_test.dart` **5/5 passed**（真实 `ReaderPage`） | ✅ |
| **US-13** | Android 真机验收清单 ①–⑥ | —（真机） | §6；[真机]；T-008 | APK `dist/reader-android-arm64-v0.8.0.apk`（§5/§6） | 清单见 `03-review.md §5`（CI 不可自动化）；已用 `android_manifest_test.dart` + APK `aapt2` 版本/权限/ABI 校验 + 集成/widget/FFI 全绿兜底 | ✅\* 真机 ①–⑥ |

**闭合统计**：US-1..US-13 共 **13 条** → **✅ 12 条 + ✅\* 1 条（US-13 真机 ①–⑥）= 13/13 全部闭合；孤儿需求 = 0**。

### 4.1 核心「连续无缝」端到端证据链（US-1）

`resolveVisibleChapter`/`chapterProgression` 纯函数（`continuous_scroll_policy_test.dart` 28 例 + `reader_continuous_scroll_coverage_test.dart` 5 例）
→ `reader_page.dart` 连续流接线（widget `reader_continuous_scroll_test.dart` 8 例，US-5/6/7/9/10/11）
→ 真实集成 `integration_test/reader_continuous_scroll_test.dart` 5 例（真实 `drag` 滚到第二章，断言标题/正文 `findsOneWidget`
且 `ReaderBottomBar findsNothing` 证明**未点按钮**）
→ 真实渲染截图 `app/screenshots/reader_continuous_scroll_chapter2.png`（`05b-product-preview.md` S3：同帧第一章尾部 + 第二章标题/正文，章间距 131 device px，0 colorful 像素）
→ 真机 US-13①。

---

## 5. 发布产物清单

| 项 | 内容 | 状态 |
|---|---|---|
| **版本号** | `0.8.0+13`（`app/pubspec.yaml`） | ✅ |
| **源码** | 分支 `wf/REQ-008-continuous-scroll`；`7e5d97a`（feat）、`51b5746`（test）、`86095a4`（产品验收截图）、`0f165db`（版本 bump）、本交付提交 | ✅ |
| **Android APK** | `dist/reader-android-arm64-v0.8.0.apk`，**48,383,561 B（46.1 MiB）**；`versionName=0.8.0 / versionCode=13`；`dist/` 已 gitignore，仅登记路径不入库 | ✅ 已构建 |
| **质量报告** | `04-mutation.md`（core 零改动 → N/A，基线 ≥80%）；`04-coverage.md`（新代码 256/260 = 98.46%）；`03-review.md`（开发/DDD=0） | ✅ |
| **产品验收** | `05b-product-preview.md` + `product-preview.manifest.json` + `product-preview-REQ-008-continuous-scroll.html` + `app/screenshots/*.png`（13 张） | ✅ |

### 5.1 APK 产物独立校验（`aapt2`/`unzip`，build-tools 36.0.0）

| 校验项 | 期望 | 实测 | 结论 |
|---|---|---|---|
| 文件路径 | `dist/reader-android-arm64-v0.8.0.apk` | 存在 | ✅ |
| 大小 | — | `48,383,561 B`（46.1 MiB） | ✅ |
| SHA-256 | — | `4d3849646c1564f3bfcf946e097ecff729f5b1cbfd6b9f11c4aa82e05297ac62` | 记录 |
| versionName | `0.8.0` | `versionName='0.8.0'` | ✅ |
| versionCode | `13` | `versionCode='13'` | ✅ |
| 包名 / SDK | `com.reader.reader_app` | `name='com.reader.reader_app'`，targetSdk 36 / compileSdk 36 | ✅ |
| INTERNET 权限 | 含 | `uses-permission: android.permission.INTERNET` | ✅ |
| TTS_SERVICE 可见性 | 含 | `<queries>` 含 `android.intent.action.TTS_SERVICE` | ✅ |
| PROCESS_TEXT 可见性 | 含 | `<queries>` 含 `android.intent.action.PROCESS_TEXT` | ✅ |
| ABI（native-code） | 3 ABI | `arm64-v8a` `armeabi-v7a` `x86_64` | ✅ |
| `libreader_core.so` | 3 ABI | arm64-v8a `7,128,520 B` / armeabi-v7a `5,184,940 B` / x86_64 `7,703,664 B` | ✅ |

> 注：TTS_SERVICE / PROCESS_TEXT 为 Android `<queries>` 包可见性声明（非 `uses-permission`），
> 由 `android_manifest_test.dart` 静态断言 + 本 APK `aapt2 dump xmltree` 实测双重确认。
> 另经 `libapp.so` 对比：v0.8.0 与 v0.7.1 的 `libapp.so`/`AndroidManifest.xml` SHA-256 均不同，
> 证明 APK 确由本 REQ 代码重新构建（非旧产物改名）。

---

## 6. Android APK 构建记录

- 命令：`bash scripts/build-android-local.sh`（本机适配：JDK21 `/usr/lib/jvm/java-21-openjdk-amd64`、
  Android SDK `/root/android-sdk`、NDK `28.2.13676358`；Rust 交叉编译 3 ABI → jniLibs →
  `flutter build apk --release --target-platform android-arm64` → 归档 `dist/reader-android-arm64-v${VER}.apk`）。
- 结果：**✓ 成功**（日志 `/tmp/opencode/req008-build.log`）。
  - Rust 三目标 `aarch64/armv7/x86_64-linux-android` 全部 `Finished release`（16.0s / 15.0s / 14.8s）。
  - Gradle `assembleRelease` 成功（59.4s），产物 `app-release.apk (48.4MB)`。
  - 归档：`/root/reader/dist/reader-android-arm64-v0.8.0.apk`。
- 构建噪声：`flutter_tts` KGP 弃用警告（未来兼容性提示，非失败）；jniLibs 中间物因构建重生成，
  按发布惯例（core 零改动）回退不入库（见 §3 #7）。

---

## 7. 闸门5 自评

- [x] **追溯矩阵全闭合**：US-1..US-13 = **13/13**（✅ 12 + ✅\* 1），**孤儿需求 = 0**；每条均有
      原型图/设计章节/实现文件（提交 `7e5d97a`）/具体测试名证据；核心"连续无缝"端到端证据链见 §4.1。
- [x] **全量回归绿**：cargo **222 passed / 0 failed**；flutter **198 passed / 4 skipped / 0 failed**；
      集成逐文件 **5 + 5 + 13 = 23 passed / 0 failed**；FFI 端到端（真实 `.so`）**4 passed / 0 failed**；
      `flutter analyze` **0 issues**；DDD **违规=0**；变异 **N/A**（core 对 main 零 diff，1345 变异体全既有；
      沿用基线 ≥80%）；新代码覆盖 **256/260 = 98.46% ≥ 85%**。
- [x] **发布产物齐全**：版本 `0.8.0+13`；APK `dist/reader-android-arm64-v0.8.0.apk`
      （48,383,561 B；`versionName=0.8.0`/`versionCode=13`；INTERNET + TTS_SERVICE + PROCESS_TEXT；
      3 ABI `libreader_core.so`，独立 `aapt2` 校验通过）；覆盖率/变异/产品验收报告齐全。

**结论：闸门5 passed。**

---

## 8. 合并建议与交接

- **建议合并** `wf/REQ-008-continuous-scroll` → `main`（普通合并，**本代理不自行合并、不 force-push、不改 STATE.md**）。
- **前置**：等待 orchestrator / 用户确认。
- **真机交接**：`03-review.md §5` 的 6 项 Android 手工清单（US-13）需在真机执行后方可对外发布；
  重点确认 ② 末章停止、③ 重开恢复、④ 听读一致、⑥ 改字号/行距/主题后锚定。
- 合并提交信息建议：`chore(release): REQ-008 v0.8.0 连续滚动阅读`。

---

## 9. 本阶段产物

| 文件 | 变更 |
|---|---|
| `app/pubspec.yaml` | `0.7.1+12` → `0.8.0+13`（提交 `0f165db`） |
| `workflow/backlog/REQ-008-continuous-scroll/05-delivery.md` | 新增（本文件，带 wf-meta 头） |
| `dist/reader-android-arm64-v0.8.0.apk` | 本地构建产物（`dist/` gitignored，不入库，见 §5/§6） |
| `app/build/**`、`app/android/app/src/main/jniLibs/**` | 构建中间物（jniLibs 已回退，不入库） |
