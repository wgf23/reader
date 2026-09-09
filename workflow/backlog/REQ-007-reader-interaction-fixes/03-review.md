<!-- wf-meta: req=REQ-007-reader-interaction-fixes | phase=development | agent=developer | date=2026-09-09 | gate=passed -->
# REQ-007 · 开发前置审查 + 实现/自检记录

> 依据：`01-req.md`（US-1..US-17）、`02-adr.md`（D1..D6）、`02-design.md`（接口 §2 / 时序 §4 / 逐屏映射 §5 / 可测出口 §6）、`02-plan.md`（T-001..T-009）。
> 本阶段只改：`app/lib/**`、`app/test/**`、`app/integration_test/**`、`core/src/dict/translation.rs`；未改 `app/pubspec.yaml`、`app/lib/src/rust/**`、docs、STATE.md、01/02 产物。

## 1. 前置审查

### 1.1 与既有约定核对

| 检查项 | 结果 | 说明 |
|---|---|---|
| 与 `docs/03` 分层/架构冲突？ | 无 | 新增 `pages/body_tap_policy.dart`、`engines/paged_*.dart` 属 interface，仅 import Flutter SDK + 同层文件；未 import `package:reader_app/src/rust/`、`src/rust/`。`core/src/dict` 仍 domain，只 `use crate::types/error/dict`。DDD 实测违规=0。 |
| 与 `docs/04` Locator/限界上下文冲突？ | 无 | `Locator`/`TextAnchor`/`Rect`/`reading_progress` 零改动；分页切章仍 `chapter_%04d.xhtml` + `progression=0.0`；无 schema/迁移，`user_version` 不变。 |
| 与既有 ADR 冲突？ | 无 | 严格按 D1（Listener 手动判定）/D2（reloader + gate）/D3（parseJsBool + executor）/D4（controls + coordinator）/D5（文案追加 + 可选按钮 + 直接 push 设置页）/D6（真实集成测试 + 去合成页）落地。 |
| 与既有业务（听读进度/笔记锚定）冲突？ | 无 | 未触 `ListenPage`/`_reloadProgress`/`saveProgress` 语义；`reading_progress` 仍是唯一事实源；`translate_reader`/`reader_selection`/`listen_*` 全量回归绿。 |
| 回归面是否并入任务？ | 是 | T-007/T-008 覆盖 `reader_page_test`/`translate_reader_test`/`reader_selection_test`/`screenshot_golden_test` + core 全量；goldens 与截图已同步。 |

### 1.2 计划核对

| 检查项 | 结果 | 说明 |
|---|---|---|
| 任务缺失？ | 无 | T-001..T-009 覆盖 US-1..US-17（02-plan 覆盖矩阵全闭合），本阶段全部落地。 |
| 依赖环？ | 无 | DAG 源点 T-001/T-002/T-003/T-005，汇点 T-009；T-003→T-004→T-007、T-002→T-007、T-005→T-008/T-006 全部单向。 |
| 估算离谱？ | 无 | 每任务 0.5~1d，与实际改动量吻合。 |
| 可测出口是否落定？ | 是 | `BodyTapTracker`/`resolveBodyTap`、`PagedDocumentReloader`/`PagedLoadGate`、`parseJsBool`/`PagedJsExecutor`、`PagedViewControls`/`PageTurnCoordinator` 均已实现并有单测。 |

### 1.3 验收可测性核对

- US-1/US-2/US-4/US-12：[集成测试] 真实 `ReaderPage` + 真实 `tapAt`/`longPress`/`drag`，5 条用例全绿（Linux/xvfb）。
- US-5/US-9：`reader_page_test.dart` 注入 fake 构建器捕获 `href=='chapter_0002.xhtml'`、fake `pagedControls` 断言边缘不 toggle。
- US-6/US-7/US-8：新增 4 个单测文件穷举分支。
- US-11/US-10：core 内嵌测试断言三段子串 + `provider=="deepl" && !from_cache`。
- US-12/US-13：`translate_reader_test.dart` 断言"去设置"跳转/透传、查词无按钮、在线/离线标签。
- US-3/US-14：`no_synthetic_chrome_test.dart` 静态守卫 + `screenshots_test.dart` 去合成页。
- US-17：[真机] 人工清单（§4）。

### 1.4 原型逐屏对照（`docs/wireframes/**` 为权威，deviation=0）

| 屏 | 核对项 | 结论 |
|---|---|---|
| `reader-ui-v2/01-immersive.svg` | 沉浸态无 Chrome；中部 1/3 呼出/隐藏（含点在文字上）；左右 15% 仅分页模式翻页；长按/选中出工具条 | **布局零改动**；`resolveBodyTap` 命中区比例逐字保留，仅把手势层由 `GestureDetector.onTapUp` 换成不进竞技场的 `Listener`。 |
| `reader-ui-v2/02-menus.svg` | 顶栏返回/书名·章节/更多；底栏上一章·☰目录·可拖进度条·书签·Aa·下一章 | **布局零改动**；"下一章"分页模式经 reloader 真正重载新章。 |
| `reader-ui-v2/04-selection.svg` | 工具条 5 入口 + 选柄零改动；错误态结果卡片仅多"去设置"按钮 | **工具条/卡片布局零改动**；唯一增量 = 翻译未配置时 `OverlayError` 多一个按钮（ADR 关联裁定1）。 |
| `08-translation.svg` | 翻译卡片标签（在线/离线/缓存）+ provider + 回退提示零改动；错误文案追加"设置"引导；查词卡片零改动 | **无布局改动**；仅 core 文案追加，卡片标签逻辑未动。 |
| `03-settings.svg` | "去设置"目标页；直接 push 并透传 backend；页面布局零改动 | **无布局改动**；`SettingsPage` 零改动。 |
| `reader-ui-v2/03-settings.svg` | Aa 面板本 REQ 不涉及 | 零改动。 |

> **原型偏差 = 0**（唯一允许增量：错误浮层"去设置"按钮，未改变工具条/卡片/顶底栏/设置页布局）。

### 1.5 前置审查结论

- [x] 通过，进入实现（无 rework-A/B/C）。
- 实现级澄清（不构成 rework，见 §5）：`BodyTapTracker` 增加 Timer 时长判定；`PagedViewBuilder` 不暴露 theme，US-9 以 fontSize + 选中回调接线断言；`reader_chrome` golden 修正为真实呼出态。

## 2. 实现清单（T-001..T-008）

| Task | 改动 | file:line |
|---|---|---|
| **T-001** 手势 | 新增 `BodyTapAction`/`resolveBodyTap`/`BodyTapTracker`（阈值 `kTouchSlop=18.0`、`kLongPressTimeout=500ms`；单指/主键/位移/时长四条件；时长用事件 timeStamp + Timer 双路径） | `app/lib/pages/body_tap_policy.dart:18,41,71` |
| | `reader_page.dart` 移除外层 `GestureDetector.onTapUp`，改由 `Listener(behavior: translucent)` 承载 down/move/up/cancel + `_applyTap`；`_lastDataPointer` 维护不变；新增 `pagedControls` 可选参数 | `app/lib/pages/reader_page.dart:49,62,194,496-519` |
| **T-002** 分页重载 | 新增 `PagedDocumentReloader`（`shouldReload`/`baseUrlFor`/`onWidgetUpdated`）+ `PagedLoadGate` | `app/lib/engines/paged_document_reloader.dart:14,38,90` |
| | `PagedWebViewState.didUpdateWidget` 委托 reloader（href/html→`controller.loadData(data, baseUrl: reader://book/{bookId}/)`；仅样式→`_applyStyle`）；`onLoadStop` 末尾 `_loadGate.complete()`；新增 `relayoutAfterLoad()` | `app/lib/engines/paged_web_view.dart:78,89-108,142,195` |
| | `_jumpToProgress` 分页分支改调 `relayoutAfterLoad()` | `app/lib/pages/reader_page.dart:244-248` |
| **T-003** JS 解析 | 新增 `parseJsBool` + `PagedJsExecutor.runBool/runInt`（不 import flutter_inappwebview） | `app/lib/engines/paged_js_result.dart:13,27` |
| | 删除内联 `_runBool` 字符串比较；`nextPage/prevPage/gotoPage` 走 `runBool`、`pageCount` 走 `runInt` | `app/lib/engines/paged_web_view.dart:170,183,210` |
| **T-004** 翻页决策 | 新增 `PagedViewControls` 抽象 + `PageTurnCoordinator` | `app/lib/engines/paged_view_controls.dart:9,30` |
| | `PagedWebViewState implements PagedViewControls`；`ReaderPage` 增 `pagedControls`，`_page` 委托 coordinator（`widget.pagedControls ?? _pagedKey.currentState`） | `app/lib/engines/paged_web_view.dart:67`；`app/lib/pages/reader_page.dart:214-221` |
| | 新增测试用 `FakePagedViewControls` | `app/test/fake_paged_view_controls.dart` |
| **T-005** 翻译引导 | core `translate_auto` 无 key 分支**仅追加**"；请在「设置」中配置在线翻译或导入词库"（三段旧子串保留） | `core/src/dict/translation.rs:562-568` |
| | `OverlayError` 增可选 `onOpenSettings`/`openSettingsLabel`（null 时逐字同现状）+ 顶层 `isTranslationNotConfiguredError` | `app/lib/widgets/translation_popup.dart:150,163-170,175-208` |
| | 翻译错误按谓词传 `onOpenSettings: _openTranslateSettings`（查词错误不传）；新增 `_openTranslateSettings` push `SettingsPage(translateBackend: widget.translateBackend)` | `app/lib/pages/reader_page.dart:289-295,578-585` |
| **T-006** 集成/去合成页 | 新增真实集成测试（US-1/2/4/12，5 条） | `app/integration_test/reader_interaction_test.dart:88,119,134,148,163` |
| | `screenshots_test.dart` 删除合成 `Column(ReaderTopBar, ReaderBottomBar)`；`reader_chrome`/`reader_more` 改真实 `tapAt(getCenter(find.text(_readerText)))`；移除 `reader_chrome.dart` import | `app/integration_test/screenshots_test.dart:25,149-155,224-227` |
| | 新增静态守卫扫描 `integration_test/*.dart` 禁 `ReaderTopBar(`/`ReaderBottomBar(` | `app/test/no_synthetic_chrome_test.dart` |
| **T-007** widget 矩阵 | `reader_page_test.dart` 落点改正文文字 center；新增分页"下一章"新 href、注入 fake controls 边缘不 toggle、长按不 toggle、US-9 切章接线 | `app/test/reader_page_test.dart` |
| **T-008** 翻译/回归 | `translate_reader_test.dart` 新增"去设置"跳转/透传、查词无按钮、在线/deepl 标签 | `app/test/translate_reader_test.dart` |
| | core 增补 `msg.contains("设置")` 与 `translate_auto_configured_key_provider_is_deepl_uncached` | `core/src/dict/translation.rs:1728,1733` |
| **T-009** 自检 | 全量回归 + DDD + 原型自检 + 真机清单 | 见 §3/§4 |

## 3. 自检结果（真实命令，T-009）

| # | 命令 | 结果 |
|---|---|---|
| 1 | `cd core && CARGO_BUILD_JOBS=2 cargo test --release` | **222 passed / 0 failed**（lib 185 + p0_corpus 5 + translate_corpus 8 + tts_api 3 + 其它 21）；唯一 warning 为既有 `src/tts/mod.rs:572` unused `text`，非本 REQ 引入。 |
| 2 | `cd app && flutter test` | **149 passed / 4 skipped / 0 failed**。 |
| 3 | `cd app && flutter analyze` | **No issues found!** |
| 4a | `xvfb-run -a flutter test integration_test/reader_interaction_test.dart -d linux` | **5 passed / 0 failed**（US-1 文字 center toggle + 空白 toggle；US-2 长按/拖拽不误触；US-4 下一章 + `saved.href`；US-12 去设置→`SettingsPage`）。 |
| 4b | `xvfb-run -a flutter test integration_test/screenshots_test.dart -d linux` | **12 passed / 0 failed**；`reader_chrome`/`reader_more` 由真实点击文字产生，12 张截图更新。 |
| 5 | `ddd-lint check /root/reader --rules workflow/rules/ddd-rules.toml --out workflow/reports/ddd-req007.md` | **违规=0**（报告：`workflow/reports/ddd-req007.md`）。 |
| 6 | CRAP | **N/A**：core 仅错误文案追加 + 测试，无逻辑/分支变更；按 `workflow/skills/crap.md`（零逻辑改动以 `flutter analyze` 0 issues 替代评估）。Dart 不在 llvm-cov CRAP 工具覆盖范围。 |
| 7 | 原型一致性 | **deviation=0**（§1.4 逐屏对照；唯一增量 = 错误浮层"去设置"按钮）。 |
| 8 | codegen 幂等 | `app/lib/src/rust/**` **零改动**（`git status --short app/lib/src/rust/` 为空）；无 FRB 再生成。 |

**golden/截图同步**：`app/test/goldens/reader_chrome.png` 修正（旧 golden 恰是 R1-2 假阳性——点在文字上未 toggle 的沉浸态；现为真实呼出态，diff 12.63% → 更新后 golden 绿）；`app/screenshots/reader_chrome.png` 重新生成为真实呼出态。

## 4. Android 真机手工验收清单（US-17，CI 不可自动化）

| # | 步骤 | 期望 |
|---|---|---|
| ① | 分页模式进入阅读器，点正文文字中部，再点一次 | 顶底栏呼出 → 隐藏（含点在文字上） |
| ② | 分页模式点左右边缘 15% | 章内翻页（正文变化、章节名不变）；到章末再点 → 进入下一章 |
| ③ | 呼出底栏点"下一章" | 正文更新为新章、章节名更新、进度回章首 |
| ④ | 长按正文选中 | 出现浮动工具条（划重点/笔记/翻译/查词/复制），顶底栏不被误呼出 |
| ⑤ | 未配 DeepL key 时选中文本点"翻译" | 错误浮层含"设置"引导 + "去设置"按钮；点击进入设置页并可配置 DeepL key |

## 5. 遗留/未覆盖项与实现级澄清

1. **分页路径 Linux 不可实跑**（平台约束）：`flutter_inappwebview` 无 Linux 实现 → 分页重载/JS 解析/翻页决策由 [单测]（US-6/7/8）+ [widget 测试]（US-5/9）覆盖，真机由 §4 兜底；集成测试只跑滚动模式。
2. **US-9 theme 断言口径**：`PagedViewBuilder` typedef 未暴露 theme（theme 仅在真实 `PagedWebView` 内部经 `_themeForPaged()` 注入），故 widget 测试断言切章后 `fontSize` 仍为当前 Aa 值 + `onSelectedText` 仍接线；theme 路径由 REQ-001/004 既有测试覆盖。属测试口径澄清，非功能偏差。
3. **`BodyTapTracker` 时长判定双路径**：生产事件带真实 `timeStamp`（差值判定）；Flutter 测试框架合成的 pointer 事件 `timeStamp` 恒为 0，故按下同时启动 `Timer(kLongPressTimeout)`，与 Flutter 识别器同构。单测用构造事件 timeStamp 断言时长，widget/集成测试用真实 `longPress` 断言不误触。
4. **`_onProgressSeek` 仍用 `_pagedKey.currentState`**：按 02-design D2「`_onProgressSeek` 的 `gotoPage` 不变」；仅 `_jumpToProgress` 改走 `_pagedControls.relayoutAfterLoad()`。
5. **截图/golden 提交**：`app/screenshots/reader_chrome.png` 与 `app/test/goldens/reader_chrome.png` 为 T-006 真实呼出态的必需更新（非 build 产物），随本次提交。
6. **US-2 集成用例拆分**：长按与拖拽拆为两个 `testWidgets`（避免同 `ReaderPage` State 复用导致 backend 不重载），覆盖不变。
7. **未做（范围划界）**：书架页设置入口（P1 可选）、TTS/笔记/Provider 进阶/生词本/对照阅读/key 加密/视觉改版均不做。

## 6. 闸门3 自评

- [x] **① CRAP FAIL=0**：N/A（core 零逻辑变更；`flutter analyze` 0 issues 替代评估，符合 crap.md）。
- [x] **② DDD 违规=0**：ddd-lint 实测 0。
- [x] **③ cargo/flutter 测试全绿**：cargo 222 passed / 0 failed；flutter 149 passed / 4 skipped / 0 failed；集成 5 + 12 passed / 0 failed。
- [x] **④ 无未处理 rework**：前置审查无 A/B/C；实现级澄清 3 项已记录。
- [x] **⑤ 原型一致性 deviation=0**：逐屏对照 6 屏，唯一允许增量为错误浮层"去设置"按钮。

**结论：闸门3 通过（gate=passed）。**
