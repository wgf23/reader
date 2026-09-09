<!-- wf-meta: req=REQ-008-continuous-scroll | phase=architecture | agent=architect | date=2026-09-09 | gate=passed -->
# REQ-008 · 计划拆分（Task 分解：连续流渲染 / 可见章与章内进度 / 跨章恢复 / 失败路径 / 节流可测 / 测试基建）

> 依据：`01-req.md`（US-1..US-13 + R1..R11 + 风险 §5）、`02-adr.md`（D1..D8）、`02-design.md`（接口/时序/逐屏映射）。
> 硬约束：每任务 ≤1 天、有可断言验收、依赖图无环；覆盖全部 US-1..US-13；测试分层标注
> [集成测试]/[widget 测试]/[单测]/[真机]；零 schema、零 FFI、零新增依赖、零布局自创。

## 任务清单

| Task | 内容 | 依赖 | 估算 | 验收（映射 US + 命令） |
|---|---|---|---|---|
| **T-001** | **连续流渲染编排 + `ChapterSection` + 失败出口骨架**（D1/D5，design §2.1/§2.4）：新增 `app/lib/pages/continuous_scroll_policy.dart`（`ChapterContentProvider`/`ChapterResolution`/`ChapterContentCache`）；`reader_page.dart` 滚动分支由 `SingleChildScrollView` 单章改为 `SelectionArea` + `NotificationListener<ScrollNotification>` + `CustomScrollView(cacheExtent:250)` + `SliverPadding` + `SliverList.builder`（每章一个 `ChapterSection(key: _chapterKeys[i])`，章间距 32px）；新增可选 `chapterProvider`；失败章渲染内联 `OverlayError` | — | 1d | **US-1 前置 [集成测试]**：真实滚动到底后第二章标题/正文各 `findsOneWidget`（T-007 验收）。**US-11 [widget 测试]**：50 章、每章 ≥ 一屏，滚到第二章后 `find.byType(ChapterSection)` 计数 ≤ 3 且 ≠ 50（T-006 验收）。**US-10 前置 [单测]**：`ChapterContentCache` 同一失败章 provider 调用 ≤1 次、失败记忆化、`retry` 显式清零（T-006/`continuous_scroll_policy_test.dart`）。**命令**：`cd app && flutter analyze`（0 issues） |
| **T-002** | **可见章判定 + 章内 progression 纯函数**（D2/D3，design §2.1）：`ChapterGeometry`（`top`/`height`/`visibleFraction`）+ `resolveVisibleChapter(built, viewportHeight, current, lastIndex, hysteresis=8, atEnd)`（顶部锚点 + 迟滞 + 触底）；`chapterProgression(top, height)` = `(-top)/height` clamp `[0,1]`；`proportionalChapterOffset(index, count, maxScrollExtent)` | — | 0.5d | **US-6 [单测]**：构造几何——章顶未越界 → 保持 current；章顶越过 `-hysteresis` → 切前；回滚越过 `+hysteresis` → 切后；`atEnd==true` → 末章；`built` 为空 → 保持 current。**US-3/US-5 [单测]**：`chapterProgression` 对 top=0/height/2 → 0.5、top>0 → 0、`-top>height` → 1。**命令**：`cd app && flutter test test/continuous_scroll_policy_test.dart` |
| **T-003** | **`ProgressSaver` 尾沿防抖可测化**（D6，design §2.2）：新增 `app/lib/pages/progress_saver.dart`（`schedule` 300ms 尾沿重置、`flush` 立即并取消、`dispose` 释放；`save`/`debounce` 可注入） | — | 0.5d | **US-3 [单测]**：`testWidgets` + `tester.pump`——300ms 内多次 `schedule` → `save` 恰好 1 次且值为最后一次；`flush` → 立即 1 次并取消挂起计时器；`dispose` 后计时器不再触发。**命令**：`cd app && flutter test test/progress_saver_test.dart` |
| **T-004** | **`reader_page` 连续流接线 + 恢复定位**（D3/D4，design §2.3/§4.1-§4.4/§4.6）：`_onScroll` 用 `RenderAbstractViewport.getOffsetToReveal` 收集已构建章几何 → `resolveVisibleChapter`/`chapterProgression` → 按需 `setState` → `_progressSaver.schedule`；`_scrollToChapter(index, progression)`（`ensureVisible(alignment:0)` + `progression×章高`，未构建先 `proportionalChapterOffset` + 有界步进）；`_goChapter`/`_onChapterSelect`/`_onProgressSeek`/`_load`/`_reloadProgress`/切回滚动/字号主题重排全部改连续流语义 + `flush`；`_openListen` 传可见章 `href/_chapterProgress`；`_chapterLocked` 由真实拖动解锁 | T-001, T-002, T-003 | 1d | **US-4 [集成测试]**：重建 `ReaderPage`（同 backend）→ 第二章正文可见且 `pixels >= 第二章起点 - 1.0`；`progression==0` → 定位章首（T-007）。**US-5 [widget 测试]**：顶栏章节名/底栏 `Slider.value` 随滚动跨章切换（T-006）。**US-7 [widget 测试]**：上一章/目录跳转后视口在目标章 + `backend.saved?.href` 正确（T-006）。**US-9 [widget 测试]**：切分页再切回滚动仍可连续滚动；改字号/主题后仍锚定在"当前章 + 章内比例"（不跳变，T-006）。**命令**：`cd app && flutter test` |
| **T-005** | **失败路径接入 + 有界重试**（D5，design §4.5）：`_buildChapterItem` 接入 `_chapterCache.resolve(i)`；失败章渲染 `OverlayError('第 N 章加载失败，请稍后重试', onRetry: retry)`；生产 provider 默认 `view.chapters[i]`；确保相邻章保留、不抛异常 | T-001, T-004 | 0.5d | **US-10 [widget 测试]**：注入对第 2 章抛异常的 provider——当前章正文 `findsOneWidget`、`find.textContaining('加载失败')` 1 个、`tester.takeException()==null`、provider 调用次数 ==1（重复 `pump` 不增加）（T-006）。**命令**：`cd app && flutter test` |
| **T-006** | **widget 测试矩阵 + 既有 `reader_page_test.dart` 兼容**（US-5/6/7/9/10/11）：新增 `app/test/reader_continuous_scroll_test.dart`（fake backend 多章；顶栏/底栏跨章；抖动去重；上一章/目录；书签/分页切换；失败注入；50 章有界）；新增 `app/test/continuous_scroll_policy_test.dart`（T-002）、`app/test/progress_saver_test.dart`（T-003）；回归并确认既有 18 个用例零断言改动 | T-004, T-005 | 1d | **US-5/6/7/9/10/11 [widget 测试]**：见各条；`find.text(章标题/正文)` 在抖动后仍 `findsOneWidget`、无重复 Key 异常；50 章 `find.byType(ChapterSection)` ≤3。**回归**：既有 `reader_page_test.dart` 全绿（`_goChapter`/目录/进度条/听书返回的 `backend.saved` 即时断言保持）。**命令**：`cd app && flutter test` |
| **T-007** | **真实集成测试 + 既有集成 finder 调整 + 连续滚动截图**（D8，design §6）：新增 `app/integration_test/reader_continuous_scroll_test.dart`（真实 `ReaderPage` + 真实 `drag`/`fling`，覆盖 US-1/2/3/4/8，含迭代上限防惰性列表死循环）；`reader_interaction_test.dart:139-140` 的 `find.byType(SingleChildScrollView)` → `find.byType(CustomScrollView)`；`screenshots_test.dart` 增"滚动到第二章"真实截图 | T-004, T-005 | 1d | **US-1 [集成测试]**：`drag` 到底（`pixels >= maxScrollExtent-1`）→ 第二章标题/正文各 1，且 `ReaderBottomBar` `findsNothing`（证明非按钮触发）。**US-2 [集成测试]**：末章继续 `drag` → `pixels` 保持 `maxScrollExtent`（±1）、`takeException()==null`、末章不重复。**US-3 [集成测试]**：章内滚动 + `pump(350ms)` → `saved.href==chapter_0001.xhtml` 且 `p∈[0,1]`；滚入第二章 + 防抖 → `href==chapter_0002.xhtml`。**US-4 [集成测试]**：重建后定位第二章。**US-8 [集成测试]**：听书写入第二章进度返回 → 定位第二章、`saved.href` 保持、继续滚动可接续。**US-12 [集成测试]**：`no_synthetic_chrome_test.dart` 绿（新文件无合成 Chrome）。**命令**：`cd app && xvfb-run -a flutter test integration_test/reader_continuous_scroll_test.dart -d linux` |
| **T-008** | **全量回归 + golden/截图/manifest + APK + DDD**（闸门3-5 前置）：跑全量；更新 golden（若像素变化）；创建 `workflow/backlog/REQ-008-continuous-scroll/product-preview.manifest.json`（`ui-screenshots.sh` 第 3 步依赖）；跑 `ui-screenshots.sh REQ-008`；跑 DDD lint / `flutter analyze`；`build-android-local.sh` 出 APK；输出 Android 真机清单 | T-006, T-007 | 1d | **全量 [单测]/[widget 测试]/[集成测试]**：`cd core && CARGO_BUILD_JOBS=2 cargo test --release`（全绿，预期零改动）；`cd app && flutter test`（全绿）；`xvfb-run -a flutter test integration_test -d linux`（全绿）；`flutter analyze` 0 issues；DDD lint 违规 0。**US-12 [集成测试]**：`ui-screenshots.sh REQ-008` 退出码 0、报告生成。**US-13 [真机]**：`build-android-local.sh` 产 APK；清单 ①滚到底自动出现下一章（不点下一章）②末章停止不崩溃③退出重开恢复到滚动位置④听书跨章返回定位一致⑤书签/Aa 切分页翻页切章正常。**命令**：`bash scripts/ui-screenshots.sh REQ-008 && bash scripts/build-android-local.sh` |

**总估算**：T-001..T-008 合计 **6.5d**；关键路径 ≈ **4.5d**（三条源点线在 T-008 汇合）。

## 依赖图（无环）

```
源点：T-001   T-002   T-003

T-001 ─────────────┐
T-002 ─────────────┤
T-003 ─────────────┴──→ T-004 ──┬──→ T-005 ──┬──→ T-006 ──┐
                                │            │            ├──→ T-008（唯一汇点）
                                └────────────┴──→ T-007 ──┘
```
- **DAG 校验**：源点 T-001/T-002/T-003；唯一汇点 T-008；边方向一致，**无环**。
- **关键路径**：T-001(1d) → T-004(1d) → T-005(0.5d) → T-006(1d) → T-008(1d) = **4.5d**；
  T-001→T-004→T-005→T-007→T-008 同为 4.5d。
- **并行线**：纯逻辑线 T-002 + T-003（与 T-001 并行）；接线线 T-004；失败线 T-005；
  测试线 T-006 / T-007 可并行；在 T-008 汇合。

## US → Task 覆盖矩阵（全闭合，供阶段 4/5 追溯）

| US | 优先级 | 验证层 | 主责 Task | US | 优先级 | 验证层 | 主责 Task |
|---|---|---|---|---|---|---|---|
| US-1 | P0 | [集成测试] | T-001, T-007 | US-8 | P0 | [集成测试]+[widget 测试] | T-004, T-006, T-007 |
| US-2 | P0 | [集成测试] | T-001, T-007 | US-9 | P0 | [widget 测试] | T-004, T-006, T-008 |
| US-3 | P0 | [集成测试]+[单测] | T-003, T-004, T-007 | US-10 | P0 | [单测]+[widget 测试] | T-001, T-005, T-006 |
| US-4 | P0 | [集成测试]+[widget 测试] | T-004, T-006, T-007 | US-11 | P0 | [widget 测试] | T-001, T-006 |
| US-5 | P0 | [widget 测试] | T-002, T-004, T-006 | US-12 | P0 | [集成测试] | T-007, T-008 |
| US-6 | P0 | [单测]+[widget 测试] | T-002, T-006 | US-13 | P0 | [真机] | T-008 |
| US-7 | P0 | [widget 测试] | T-004, T-006 | — | — | — | — |

> 全部 US-1..US-13 均有主责 Task，无遗漏；US-3/6/10/11 的可测出口由 T-002/T-003/T-001 落定。

## 冲突检查结果

- **与 Locator 不变式无冲突**：`progression` 恒为**可见章内** `[0,1]`（`chapterProgression` 纯函数），
  `href` 恒为 `chapter_%04d.xhtml`；`reading_progress` 表/`ProgressData`/`Locator` 零变更；
  `core/src/locator/mod.rs` 仍 stub、本 REQ 不扩。
- **与限界上下文无冲突**：改动全部在 `app/lib/pages`（interface）；`app/lib/services`（application）与
  `core/**`（domain/infrastructure）零改动；无新表/新上下文/新 FFI。
- **与听读同进度无冲突**：`reading_progress` 仍是唯一事实源；`_openListen` 传"可见章 href + 章内
  progression"，`_reloadProgress` 跨章恢复；`listen_page.dart` 零改动；US-8 双向一致。
- **与 ddd-rules 无冲突**：新增 `app/lib/pages/continuous_scroll_policy.dart`、`progress_saver.dart`
  属 interface（`ddd-rules.toml:12`），仅 import Flutter SDK + `../services/library_backend.dart`（DTO），
  **不** import `package:reader_app/src/rust/`、`src/rust/`；`core/**` 零改动 → 违规 0。
- **与既有测试无冲突（逐项处置）**：
  1. `reader_page_test.dart` **18 个用例断言零改动**——`_goChapter`/`_onChapterSelect`/`_onProgressSeek`/
     `_reloadProgress` 走 `ProgressSaver.flush` 立即落盘（保持 `backend.saved` 即时断言）；
     `find.byType(SelectionArea)` 仍唯一；`find.text(_ch1)/find.text(_ch2)` 仍 `findsOneWidget`（sliver
     每章一个 item，不重复）。**若开发中发现 `_ch1` 文本高度导致 center 超出视口**，在 T-006 中把落点
     改为 `tester.getRect(find.text(_ch1)).center` 附近的可见点，并在 03-review 显式记录（属测试实现细节，
     不改断言语义）。
  2. `reader_interaction_test.dart:139-140` `find.byType(SingleChildScrollView)` → `find.byType(CustomScrollView)`
     （**唯一既有集成测试硬调整**，T-007）。
  3. `no_synthetic_chrome_test.dart` 自动扫描 `integration_test/*.dart`，新文件天然受守卫，无需改扫描逻辑；
     可增补"新文件存在"正向断言。
  4. `listen_page_test.dart`/`page_turn_coordinator_test.dart`/`reader_selection_test.dart`/
     `reader_page_interaction_coverage_test.dart`：零改动，回归绿。
- **与 golden/截图无冲突（已处置）**：单章视觉目标不变（`SliverPadding` 等价原 `padding`）；若
  `screenshot_golden_test.dart` 像素有差异，在 T-008 显式更新 golden 并在 03-review 记录。REQ-008
  `product-preview.manifest.json` **当前缺失**（`ui-screenshots.sh` 第 3 步会 `exit 2`）→ T-008 创建
  （映射 `01-immersive`/`02-menus` 与真实截图，含新增"连续滚动到第二章"截图），确保脚本退出码 0。
- **与 `flutter_inappwebview` 平台约束无冲突**：滚动模式不实例化 WebView，Linux xvfb 可跑 US-1/2/3/4/8；
  分页走 [widget 测试] + [真机]；无新增依赖。
- **范围划界（不做）**：分页章末续章（REQ-001/007 已交付，仅回归）、听书功能本身、书签持久化（NOTE-06）、
  笔记/高亮、全文搜索/翻译/查词、阅读器视觉改版、`LocatorResolver` 完整实现、FFI 按章懒加载、
  `ReflowEngine` 扩展（ADR D7）——均不做（沿用 01-req §1.2）。
- **文档同步风险（已登记，非闸门项）**：`docs/03`/`docs/04` 零签名变更（可补"连续滚动可见章判定"注释），
  开发/交付阶段处理。

## 原型一致性自检清单（T-008 执行，deviation=0）

| 屏 | 核对项（对照 svg 逐项） |
|---|---|
| `reader-ui-v2/01-immersive.svg` | 沉浸态无 Chrome；中部 1/3 呼出/隐藏；左右 15% 仅分页翻页；长按选中出工具条；多章正文连续滚动、下一章标题随滚动进入视口；**无新增控件/颜色/字号**；唯一行为性增量 = 章间距 32px |
| `reader-ui-v2/02-menus.svg` | 顶栏返回/书名·章节/更多；底栏上一章·☰目录·可拖进度条·书签·Aa·下一章；章节名/进度随可见章更新；上一章/下一章/目录滚动定位；**布局零改动** |
| `reader-ui-v2/04-selection.svg` | 选中工具条 5 入口 + 选柄零改动；跨章选中为自然结果；**零改动** |
| 失败提示（无新增原型） | 复用 `OverlayError` 样式内联在失败章位置；文案含"加载失败"；**不新增布局体系** |

## 闸门2 自评（计划部分）

- [x] **任务粒度可执行**：T-001..T-008 每项 0.5~1d（合计 6.5d），每项含具体文件/行为与可断言验收命令，
  映射 US-1..US-13（覆盖矩阵全闭合）。
- [x] **依赖图无环**：DAG 已标注（源点 T-001/T-002/T-003，唯一汇点 T-008），关键路径 ≈4.5d；无环。
- [x] **冲突清单为空或已含处置**：Locator 不变式、限界上下文、听读同进度、ddd-rules、既有测试
  （含唯一硬调整 `SingleChildScrollView`→`CustomScrollView`）、golden/截图/manifest、平台约束、范围划界、
  文档同步共 9 类，全部无冲突或已列处置。
- [x] **ADR 备选 ≥2 且给出理由**：8 个决策点（D1 三 / D2 两 / D3 三 / D4 三 / D5 三 / D6 三 / D7 三 /
  D8 三），均含选择理由、拒绝论证与降级线（详见 02-adr）。
- [x] **可测出口落定**：US-3/6/10/11 分别由 `ProgressSaver`、`resolveVisibleChapter`、
  `ChapterContentCache`、`ChapterSection` 提供（02-design §6），否则不可验收。
- [ ] **待同步项（非本阶段闸门项）**：REQ-008 `product-preview.manifest.json`、golden 可能的更新、
  `docs/03`/`docs/04` 注释在开发/交付阶段完成；不阻塞闸门2。
