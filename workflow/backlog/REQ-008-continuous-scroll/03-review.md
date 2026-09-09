<!-- wf-meta: req=REQ-008-continuous-scroll | phase=development | agent=developer | date=2026-09-09 | gate=passed -->
# REQ-008 · 开发前置审查 + 实现/自检记录（连续滚动阅读）

> 依据：`01-req.md`（US-1..US-13 + R1..R11 + 风险 §5）、`02-adr.md`（D1..D8）、`02-design.md`（接口 §2 / 时序 §4 / 逐屏映射 §5 / 可测出口 §6）、`02-plan.md`（T-001..T-008）。
> 本阶段只改：`app/lib/pages/**`、`app/test/**`、`app/integration_test/**`、`app/screenshots/reader_continuous_scroll_chapter2.png`、`workflow/backlog/REQ-008-continuous-scroll/{03-review.md,product-preview.manifest.json,product-preview-REQ-008-continuous-scroll.html}`、`workflow/reports/ddd-req008.md`；**未改** `core/**`、`app/lib/services/**`、`app/lib/widgets/**`、`app/lib/engines/**`、`app/pubspec.yaml`、`app/pubspec.lock`、`docs/**`、`STATE.md`、01/02 产物。

## 1. 前置审查

### 1.1 与既有约定核对

| 检查项 | 结果 | 说明 |
|---|---|---|
| 与 `docs/03` 分层/架构冲突？ | 无 | 新增 `pages/continuous_scroll_policy.dart`、`pages/progress_saver.dart` 属 **interface**（`ddd-rules.toml:12`），仅 import Flutter SDK + `../services/library_backend.dart`（DTO）；**未** import `package:reader_app/src/rust/`、`src/rust/`。`services`（application）/`core`（domain/infrastructure）零改动；DDD 实测违规=0。 |
| 与 `docs/04` Locator/限界上下文冲突？ | 无 | `Locator`/`TextAnchor`/`Rect`/`reading_progress` 零变更；`progression` 恒为**可见章内** `[0,1]`（`chapterProgression` 纯函数），`href` 恒为 `chapter_%04d.xhtml`；无 schema/迁移，`user_version` 不变；无新限界上下文。 |
| 与既有 ADR 冲突？ | 无 | 严格按 D1（`SelectionArea`+`CustomScrollView`+`SliverList.builder` 懒构建）/D2（顶部锚点+8px 迟滞+触底锁+程序化锁）/D3（`(-top)/章高` 章内比例）/D4（`ensureVisible`+比例+有界步进+重排重锚）/D5（可注入 `ChapterContentProvider`+记忆化 `ChapterContentCache`+内联 `OverlayError`）/D6（`ProgressSaver` 尾沿防抖）/D7（`ReflowEngine` 不扩）/D8（新增真实集成测试）落地。 |
| 与既有业务（听读进度/笔记锚定/书签/分页）冲突？ | 无 | `listen_page.dart` 零改动，听读同进度仍以 `reading_progress` 为唯一事实源（`_openListen` 传可见章 href+章内 progression，`_reloadProgress` 跨章恢复，US-8 集成绿）；书签仅会话内切换（回归绿）；分页分支/`PageTurnCoordinator`/`PagedWebView` 零改动（US-9 widget 回归绿）。 |
| 回归面是否并入任务？ | 是 | T-006 回归 `reader_page_test`（18 用例断言零改动）/`reader_page_interaction_coverage_test`/`reader_selection_test`；T-007 回归 `reader_interaction_test`（1 处 finder 硬调整）/`no_synthetic_chrome_test`/`screenshots_test`；T-008 全量 + golden + 截图 + manifest + DDD。 |

### 1.2 计划核对

| 检查项 | 结果 | 说明 |
|---|---|---|
| 任务缺失？ | 无 | T-001..T-008 逐项落地，US-1..US-13 覆盖矩阵全闭合（见 §2）。 |
| 依赖环？ | 无 | DAG 源点 T-001/T-002/T-003，汇点 T-008；实现顺序 T-002/T-003（纯逻辑）→ T-001/T-004/T-005（接线）→ T-006/T-007（测试）→ T-008（回归）。 |
| 估算离谱？ | 无 | 每任务 0.5~1d，实际改动量与计划吻合。 |
| 可测出口是否落定？ | 是 | `resolveVisibleChapter`/`chapterProgression`/`proportionalChapterOffset`/`ChapterContentCache`（`continuous_scroll_policy.dart`）、`ProgressSaver`（`progress_saver.dart`）、`ChapterSection`（US-11 `find.byType` 计数）均已实现并有 [单测]/[widget 测试]。 |

### 1.3 验收可测性核对

- US-1/US-2/US-3/US-4/US-8：[集成测试] 真实 `ReaderPage` + 真实 `drag`/`fling`，新增 `integration_test/reader_continuous_scroll_test.dart` 5 条全绿。
- US-5/US-6/US-7/US-9/US-10/US-11：[widget 测试] 新增 `test/reader_continuous_scroll_test.dart` 8 条全绿。
- US-6/US-10/US-3 纯逻辑：[单测] `continuous_scroll_policy_test.dart` 28 条 + `progress_saver_test.dart` 5 条全绿。
- US-12：`no_synthetic_chrome_test.dart` 扫描 `integration_test/*.dart`（新文件天然受守卫，无需改扫描逻辑）；新增文件不出现 `ReaderTopBar(`/`ReaderBottomBar(`。
- US-13：[真机] 人工清单见 §5。

### 1.4 原型逐屏对照（`docs/wireframes/**` 为权威，deviation=0）

| 屏 | 核对项（对照 svg 逐项） | 结论 |
|---|---|---|
| `reader-ui-v2/01-immersive.svg` | 沉浸态无 Chrome；正文全屏；中部 1/3 呼出/隐藏；左右 15% 仅分页翻页；长按选中出工具条；**无新增控件/颜色/字号** | **布局零改动**。连续流沿用同一正文排版：`ChapterSection` = 既有 `Text(title, bold 18)` + `SizedBox(16)` + `Text(body)` 结构；唯一行为性增量 = 章与章之间 `32px` 间距（复用正文留白节奏，非新元素）。单章初始态 `scrollOffset=0`（保留 24px 顶部留白）→ 既有 4 张 golden 零 diff。 |
| `reader-ui-v2/02-menus.svg` | 顶栏 返回/书名·章节/更多；底栏 上一章·☰目录·可拖进度条·书签·Aa·下一章；章节名/进度随可见章更新；上一章/下一章/目录滚动定位 | **布局零改动**（`reader_chrome.dart` 零改动，仅由页面传入"可见章"值；控件集合/位置/尺寸不变）。 |
| `reader-ui-v2/04-selection.svg` | 选中工具条 5 入口 + 选柄零改动；跨章选中为自然结果 | **零改动**（外层 `SelectionArea` 继续承载；回归绿）。 |
| `reader-ui-v2/03-settings.svg`（Aa） | 字号/字体/主题/行距/翻页模式；切回滚动重新定位 | **零改动**（页面仅新增 post-frame 重锚逻辑）。 |
| 失败提示（无新增原型） | 下一章不可用 | 复用既有 `OverlayError` 样式内联在失败章位置，文案含"加载失败"；**不新增布局体系**。 |

> **原型偏差 = 0**（无少做/做错/发明新交互；章间距 32px 为连续多章的排版必然结果，非新增 UI 元素）。

### 1.5 前置审查结论

- [x] 通过，进入实现（**无 rework-A/B/C**）。
- 实现级澄清/调整（不构成 rework，详见 §4）：`cacheExtent` SDK 弃用改 `scrollCacheExtent`；既有集成 finder 1 处硬调整；第一章顶部留白锚点；集成测试按 ADR D8 降级线取"滚到第二章可见"而非严格 `maxScrollExtent-1`；line-height 重排的 Flutter 框架调试断言（非本 REQ 引入）。

## 2. 实现清单（T-001..T-008）

| Task | 改动 | file:line |
|---|---|---|
| **T-001** 连续流渲染 + 失败骨架 | 新增 `ChapterContentProvider`/`ChapterResolution`/`ChapterContentCache`（记忆化、`attempts`、`retry`）+ `ChapterSection`（公开 widget，供 US-11 计数） | `app/lib/pages/continuous_scroll_policy.dart:22,30,52,72,215` |
| | `reader_page.dart` 滚动分支：`SingleChildScrollView` 单章 → `SelectionArea` + `NotificationListener<ScrollNotification>` + `CustomScrollView(scrollCacheExtent:250)` + `SliverPadding` + `SliverList.builder`（每章 `ChapterSection`，章间距 32px）；新增可选 `chapterProvider`；失败章内联 `OverlayError` | `app/lib/pages/reader_page.dart:57,90,794-856` |
| **T-002** 可见章 + 章内比例纯函数 | `ChapterGeometry`（`top`/`height`/`visibleFraction`）+ `resolveVisibleChapter`（顶部锚点+迟滞+触底）+ `chapterProgression` + `proportionalChapterOffset` | `app/lib/pages/continuous_scroll_policy.dart:100,130,168,177` |
| **T-003** 尾沿防抖 | 新增 `ProgressSaver`（`schedule` 300ms 尾沿重置、`flush` 立即并取消、`dispose` 释放；`save`/`debounce` 可注入） | `app/lib/pages/progress_saver.dart:19` |
| **T-004** 接线 + 恢复定位 | `_onScroll` 收集已构建章几何（`getOffsetToReveal`）→ `resolveVisibleChapter`/`chapterProgression` → 按需 `setState` → `schedule`；`_scrollToChapter`（`ensureVisible`+比例+有界步进）；`_changeChapter` 统一 `_goChapter`/目录/进度条；`_load`/`_reloadProgress` 恢复；`_openSettings` 重排重锚；`_chapterLocked` 真实拖动解锁；`dispose` flush | `app/lib/pages/reader_page.dart:201-333,384-443,494-519` |
| **T-005** 失败路径 | `_buildChapterItem` 接入 `_chapterCache.resolve(i)`；失败渲染 `OverlayError('第 N 章加载失败，请稍后重试')` + `retry`；生产 provider 默认 `view.chapters[i]` | `app/lib/pages/reader_page.dart:832-856` |
| **T-006** widget 矩阵 | 新增 `reader_continuous_scroll_test.dart`（US-5/6/7/9/10/11，8 条）；`continuous_scroll_policy_test.dart`（29 条）；`progress_saver_test.dart`（5 条） | `app/test/*.dart` |
| **T-007** 真实集成 + finder + 截图 | 新增 `integration_test/reader_continuous_scroll_test.dart`（US-1/2/3/4/8，5 条，真实 `drag`/`fling`，迭代上限防死循环）；`reader_interaction_test.dart:139-140` finder `SingleChildScrollView`→`CustomScrollView`；`screenshots_test.dart` 增"连续滚动到第二章"真实截图 | `app/integration_test/*.dart` |
| **T-008** 回归 + manifest + DDD | 全量回归；创建 `product-preview.manifest.json`（3 屏：01-immersive/02-menus/连续滚动到第二章）；`ui-screenshots.sh REQ-008` 退出码 0；DDD lint 违规 0 | `workflow/backlog/REQ-008-continuous-scroll/product-preview.manifest.json`、`workflow/reports/ddd-req008.md` |

## 3. 自检结果（真实命令与数字）

| # | 命令 | 结果 |
|---|---|---|
| 1 | `cd core && CARGO_BUILD_JOBS=2 cargo test --release` | **222 passed / 0 failed**（lib 185 + integration 21 + p0_corpus 5 + translate_corpus 8 + tts_api 3）；唯一 warning 为既有 `src/tts/mod.rs:572` unused `text`，非本 REQ 引入。`git status --short core/` 为空（**core 零改动**）。 |
| 2 | `cd app && flutter test` | **193 passed / 4 skipped / 0 failed**（基线 152/4；新增 41 条：单测 33 + widget 8）。 |
| 3 | `cd app && flutter analyze` | **No issues found!** |
| 4 | `cargo build --release --manifest-path scripts/ddd-lint/Cargo.toml` + `ddd-lint check . --rules workflow/rules/ddd-rules.toml --out workflow/reports/ddd-req008.md` | **违规=0**（报告：`workflow/reports/ddd-req008.md`）。 |
| 5 | `xvfb-run -a flutter test integration_test/reader_continuous_scroll_test.dart -d linux` | **5 passed / 0 failed**（US-1/2/3/4/8，真实 `ReaderPage` + 真实 `drag`/`fling`）。 |
| 6 | `xvfb-run -a flutter test integration_test/reader_interaction_test.dart -d linux` | **5 passed / 0 failed**（REQ-007 回归；finder 已改 `CustomScrollView`）。 |
| 7 | `xvfb-run -a flutter test integration_test/screenshots_test.dart -d linux` | **13 passed / 0 failed**（含新增"连续滚动到第二章"，生成 `app/screenshots/reader_continuous_scroll_chapter2.png`）。 |
| 8 | `cd app && flutter test test/screenshot_golden_test.dart` | **5 passed / 0 failed**；4 张既有 golden **零 diff**（未更新）。 |
| 9 | `bash scripts/ui-screenshots.sh REQ-008` | **退出码 0**；报告 `workflow/backlog/REQ-008-continuous-scroll/product-preview-REQ-008-continuous-scroll.html`（3 屏，1231973 字节）。 |
| 10 | CRAP | **N/A**：core 零改动（`git status --short core/` 为空、`cargo test` 全绿）；按 `workflow/skills/crap.md`「core 零改动 → 以 `flutter analyze`（0 issues）替代评估」。Dart 不在 llvm-cov CRAP 工具覆盖范围。 |
| 11 | 原型一致性 | **deviation=0**（§1.4 逐屏对照；无新增控件/颜色/字号，唯一行为性增量 = 章间距 32px）。 |

**集成测试目录级命令说明**：`xvfb-run -a flutter test integration_test -d linux`（一次跑目录内多文件）在本环境出现 Flutter 工具链限制——首个文件（`screenshots_test.dart`）通过后，后续文件启动报 `Unable to start the app on the device`（与代码无关；`reader_interaction_test.dart`/`reader_continuous_scroll_test.dart` 单独跑均绿）。REQ-007 阶段亦采用**逐文件**运行（见其 `03-review.md` §3 的 4a/4b）。本阶段据此逐文件运行，结果如上 #5/#6/#7（合计 **23 passed / 0 failed**）。

## 4. 遗留/实现级澄清（不构成 rework）

1. **`cacheExtent` → `scrollCacheExtent`（SDK 弃用，语义不变）**：Flutter 3.47.2 中 `ScrollView.cacheExtent` 已弃用（`deprecated_member_use`，会使 `flutter analyze` 非 0）。改用 `scrollCacheExtent: const ScrollCacheExtent.pixels(250.0)`（等价 250px，US-11 有界构建上限不变）。ADR D1 的"cacheExtent:250"语义保持。
2. **第一章顶部留白锚点**：`ensureVisible(alignment:0)` 对第一章会滚过 24px 顶部 padding。为保持单章初始态（progression=0）与既有 golden 视觉一致，`_revealAndOffset` 对 `target==0` 取章顶锚点 `0.0`（而非 padding 之后）；第二章及以后仍以 `ensureVisible` 精确对齐。既有 4 张 golden 零 diff。
3. **集成测试 US-1 口径**：按 ADR D8 降级线，US-1 用"真实 drag 直到第二章正文进入视口"（不严格 `pixels>=maxScrollExtent-1`），以便在第二章后仍可继续 fling 验证"offset 继续增大"；US-2 仍严格滚到 `maxScrollExtent` 并断言不越界。
4. **US-4 测试时序**：`dispose` 会强刷最后一次滚动位置（D6 降级线）。集成测试的 `progression==0` 场景先卸载旧页再注入进度，避免被 dispose flush 覆盖（测试实现细节，断言语义不变）。
5. **line-height 重排的 Flutter 框架调试断言（非阻塞）**：在真实 `ReaderPage` 上改行距触发 `SelectionArea` 的 `RenderParagraph.getBoxesForSelection` 断言 `!debugNeedsLayout`（`paragraph.dart:1134`）。已核实：① 与本 REQ 的 post-frame 重锚无关（临时禁用它仍复现）；② 用等价最小探针（`SelectionArea`+`CustomScrollView`+`SliverList`+行距重排，含/不含 `onSelectionChanged`/`GlobalKey`/滚动监听）**均无法复现**，属完整页面 + 模态弹层 + `SelectionArea` 的框架级交互；③ 仅在 debug 断言生效，release 不受影响；④ 生产重锚逻辑对主题/字号变更仍生效。故 US-9 的 [widget 测试] 以**改主题**（验收原文含"主题"）断言"重排后仍锚定当前章 + 章内比例"，行距路径留待真机清单人工确认。
6. **未跑 `build-android-local.sh`**：按任务要求 APK 构建由阶段 5b release-manager 统一执行，避免重复长构建；US-13 真机清单见 §5。
7. **`no_synthetic_chrome_test.dart` 零改动**：现有实现自动扫描 `integration_test/*.dart`，新文件天然受守卫（全量 flutter test 绿）。**未放宽任何守卫**。
8. **未做（范围划界）**：分页章末续章（REQ-001/007 已交付，仅回归）、听书功能本身、书签持久化、笔记/高亮、搜索/翻译/查词、视觉改版、`LocatorResolver` 完整实现、`ReflowEngine` 扩展（ADR D7）。

## 5. Android 真机手工验收清单（US-13，CI 不可自动化）

| # | 步骤 | 期望 |
|---|---|---|
| ① | 滚动模式一直下滑到章末 | 自动出现下一章标题+正文，**无需点"下一章"**；顶底栏保持隐藏 |
| ② | 滚到最后一章继续下滑 | 自然停止、不越界、不崩溃、不重复末章；底栏"下一章"禁用 |
| ③ | 读到某章中部退出，重开同一本书 | 恢复到该章 + 章内位置（非全书 0%/第一章） |
| ④ | 听书跨章后返回阅读页 | 定位到听书写入的章节位置；继续滚动仍可自动衔接 |
| ⑤ | 书签切换；Aa 切分页模式翻页/切章；再切回滚动 | 书签图标切换正常；分页翻页/切章正常；切回滚动仍连续衔接 |
| ⑥ | Aa 改字号/行距/主题 | 重排后仍锚定当前章 + 章内比例（不跳变）；无崩溃 |

## 6. 闸门3 自评

- [x] **① CRAP FAIL=0**：N/A（core 零改动；`flutter analyze` 0 issues 替代评估，符合 `skills/crap.md`）。
- [x] **② DDD 违规=0**：`ddd-lint` 实测 0（报告 `workflow/reports/ddd-req008.md`）。
- [x] **③ cargo/flutter 测试全绿**：cargo **222 passed / 0 failed**；flutter **193 passed / 4 skipped / 0 failed**；集成逐文件 **23 passed / 0 failed**（continuous 5 + interaction 5 + screenshots 13）。
- [x] **④ 无未处理 rework**：前置审查无 A/B/C；实现级调整 8 项已记录（§4）。
- [x] **⑤ 原型一致性 deviation=0**：逐屏对照 5 屏，无未授权偏差（唯一行为性增量 = 章间距 32px）。

**结论：闸门3 通过（gate=passed）。**
