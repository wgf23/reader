<!-- wf-meta: req=REQ-007-reader-interaction-fixes | phase=architecture | agent=architect | date=2026-09-09 | gate=passed -->
# REQ-007 · 计划拆分（Task 分解：手势可达性 / 分页切章重载 / JS 解析 / 翻页决策 / 翻译引导 / 真实集成测试）

> 依据：`01-req.md`（US-1..US-17 + R1-1/R1-2/R2-1/R2-2/R2-3/R3-1/R3-2/R3-3）、`02-adr.md`（D1..D6）、`02-design.md`（接口/时序/逐屏映射）。
> 硬约束：每任务 ≤1 天、有可断言验收、依赖图无环；覆盖全部 US-1..US-17；测试分层标注 [集成测试]/[widget 测试]/[单测]/[真机]；无新增依赖、零 schema、零布局自创。

## 任务清单

| Task | 内容 | 依赖 | 估算 | 验收（映射 US） |
|---|---|---|---|---|
| **T-001** | **手势命中层重构 + 可测纯函数**（D1，design §2.2/§4.1）：新增 `app/lib/pages/body_tap_policy.dart`（`BodyTapAction`/`resolveBodyTap`/`BodyTapTracker`，阈值 `kTouchSlop=18.0`、`kLongPressTimeout=500ms`）；`reader_page.dart` 移除外层 `GestureDetector.onTapUp`，改由既有 `Listener`（`behavior: translucent`）承载 down/move/up/cancel + `_applyTap`；`_lastDataPointer` 维护不变；命中区语义逐字保留 | — | 1d | **US-2 [单测]**：`body_tap_policy_test.dart`——位移 ≤18px 且时长 ≤500ms 且单指/主键 → `onPointerUp==true`；位移 >18px / 时长 ≥500ms / 多指 / 非主键 → `false`；`resolveBodyTap` 分区表：分页 `relX<0.15`→prevPage、`>0.85`→nextPage、中部 1/3→toggleChrome、其余→dismiss（`hasSelection`/`chromeVisible` 两态）。**US-1 前置**：真实 tap 由 T-006 集成测试验收 |
| **T-002** | **分页切章重载 + 载入门**（D2，design §2.3/§2.5/§4.2）：新增 `app/lib/engines/paged_document_reloader.dart`（`PagedDocumentReloader`/`PagedLoadGate`）；`paged_web_view.dart` `didUpdateWidget` 委托 reloader（`loadData(data:newHtml, baseUrl:'reader://book/{bookId}/')`）、`onLoadStop` 末尾 `_loadGate.complete()`、新增 `relayoutAfterLoad()`；`reader_page.dart` 分页分支 `_jumpToProgress` 改调 `relayoutAfterLoad()` | — | 1d | **US-6 [单测]**：`paged_document_reloader_test.dart`——href 变化 / html 变化 → `shouldReload==true` 且 spy `loadData` 恰好 1 次、参数 = 新 html + `reader://book/b1/`；仅 fontSize/theme 变化 → `applyStyle` 被调、`loadData` 0 次；href/html 均不变 → 两者 0 次（幂等）；bookId 变化 → baseUrl 随新 bookId；`PagedLoadGate`：`begin()` 后 `pending==true` 且 `done` 未完成，`complete()` 后 `done` 完成 |
| **T-003** | **JS 布尔解析可测出口**（D3，design §2.3）：新增 `app/lib/engines/paged_js_result.dart`（`parseJsBool`/`PagedJsExecutor`）；`paged_web_view.dart` 删除 `_runBool` 内联比较，`nextPage/prevPage/gotoPage` 走 `runBool`、`pageCount` 走 `runInt` | — | 0.5d | **US-7 [单测]**：`paged_js_result_test.dart`——`parseJsBool(true)==true`、`'true'==true`、`1==true`、`false/'false'/0/null/{}=='false'`；`PagedJsExecutor` 注入 fake evaluator 返回 `true`/`'true'` → `runBool('readerPager.next()')==true`；返回 `false`/`'false'`/`null`/非布尔 → `false` 且不抛错；`runInt` 对 num/字符串/非法值 fallback |
| **T-004** | **翻页决策可测 + 分页控件抽象**（D4，design §2.3/§2.5）：新增 `app/lib/engines/paged_view_controls.dart`（`PagedViewControls`/`PageTurnCoordinator`）；`PagedWebViewState implements PagedViewControls`；`ReaderPage` 增可选 `pagedControls`，`_page` 委托 `PageTurnCoordinator`（`widget.pagedControls ?? _pagedKey.currentState`）；新增 `app/test/fake_paged_view_controls.dart` | T-003 | 0.5d | **US-8 [单测]**：`page_turn_coordinator_test.dart`——`nextPage()==true` → `goChapter` 0 次（章节索引不变）；`nextPage()==false` → `goChapter(+1)` 1 次；`prevPage()==true` → 0 次；`prevPage()==false` → `goChapter(-1)` 1 次。**US-2 前置**：分页边缘注入 fake controls 不 toggle 由 T-007 验收。**US-9 回归**：`PagedWebViewState` 仍 `onProgress`/`onSelectedText` 接线、`buildPagedWebViewSettings(disableContextMenu:true)` 不变 |
| **T-005** | **翻译未配置引导（core 文案 + Dart 浮层 + 设置跳转）**（D5，design §2.1/§2.4/§4.3）：`core/src/dict/translation.rs:564-566` 追加"；请在「设置」中配置在线翻译或导入词库"（三段旧子串保留）；`translation_popup.dart` `OverlayError` 增可选 `onOpenSettings`/`openSettingsLabel` + `isTranslationNotConfiguredError`；`reader_page.dart` 翻译错误按谓词传 `onOpenSettings: _openTranslateSettings`（查词错误不传）、新增 `_openTranslateSettings` push `SettingsPage(translateBackend: widget.translateBackend)` | — | 1d | **US-11 [单测]**：`cargo test -p reader_core`——无 key + 离线未命中 `to_string()` **同时**含 `"未配置在线翻译 API Key"`、`"设置"`、`"离线翻译未命中"`，且失败不写缓存；无 key 但离线命中仍返回 offline + `fallback_reason=="未配置在线翻译 API Key，已回退离线"`。**US-12 [widget 测试]**：`translate_reader_test.dart`——注入抛"未配置在线翻译 API Key…"的 fake → 浮层含"设置" + `find.text('去设置')` + `find.text('重试')` 各 1；点"去设置" → `find.byType(SettingsPage)` 1 且同一 fake backend 实例被透传；查词失败 → `find.text('去设置')` findsNothing。**US-16**：既有 `contains` 断言零改动通过 |
| **T-006** | **真实 integration_test + 去合成页 + 静态守卫**（D6，design §6）：新增 `app/integration_test/reader_interaction_test.dart`（真实 `ReaderPage` 滚动模式，长文本 fake 使文字铺满中部；真实 `tapAt` 文字 center/`longPress`/`drag`；覆盖 US-1/2/4/12）；改写 `screenshots_test.dart`——删除 `:147-179` 合成 `Column(ReaderTopBar, ReaderBottomBar)`、`reader_chrome` 改真实 ReaderPage 点文字、`:247` 改 `tapAt(getCenter(find.text(...)))`、移除 `reader_chrome.dart` import；新增 `app/test/no_synthetic_chrome_test.dart` 扫描 `integration_test/*.dart` 无 `ReaderTopBar(`/`ReaderBottomBar(` | T-001, T-005 | 1d | **US-1 [集成测试]**：点正文文字 center → `find.byTooltip('返回书架')`/`find.byType(ReaderBottomBar)`/`find.text('下一章')` 各 1；再点 → findsNothing；点文字下方空白同样 toggle。**US-2 [集成测试]**：`longPress` 文字 → `ReaderSelectionToolbar` 1 且 Chrome findsNothing；`drag(SingleChildScrollView, (0,-200))` → 偏移 >0 且 Chrome 可见性不变。**US-4 [集成测试]**：呼出 → 点"下一章" → 第二章文字 + `backend.saved?.href=='chapter_0002.xhtml'`；末章按钮禁用/不越界。**US-12 [集成测试]**：无 key 翻译 → "去设置" → `SettingsPage`。**US-3/US-14**：`no_synthetic_chrome_test.dart` 绿；`flutter test integration_test -d linux`（xvfb）全绿 |
| **T-007** | **分页与手势 widget 测试矩阵**（US-5/US-9/US-2 分页侧）：更新 `app/test/reader_page_test.dart`——`_toggleChrome` 落点由 `_center=Offset(400,300)` 改为正文文字 center（或显式空白并注明）；新增"分页模式点下一章 → fake 构建器收到 `href=='chapter_0002.xhtml'` + 第二章文本 + `backend.saved?.href` + `progression==0.0`"；新增"注入 fake `pagedControls`，点左右边缘不 toggle 且 `nextPage/prevPage` 被调"；既有"边缘不崩"用例改注入 fake controls 后断言语义 | T-002, T-004 | 1d | **US-5 [widget 测试]**：fake 构建器捕获新 href 并渲染第二章；`backend.saved?.href=='chapter_0002.xhtml'`、`progression==0.0`。**US-9 [widget 测试]**：切章后 `fontSize/theme` 仍按当前 Aa 传入 fake 构建器；`onProgress`/`onSelectedText` 仍接线（触发后工具条可用）。**US-2 [widget 测试]**：分页模式注入 fake controls，`tapAt` 左/右边缘 → Chrome 不可见、`prevPage`/`nextPage` 各被调 1 次；长按文字 → 工具条出现且 Chrome 不出现；`flutter test` 全绿 |
| **T-008** | **翻译链路测试补齐 + core/Dart 回归**（US-10/US-12/US-13/US-16）：`core/src/dict/translation.rs` 增补显式 `provider=="deepl" && !from_cache` 断言；`translate_reader_test.dart` 增补"去设置"跳转/透传、查词无按钮、来源标签（在线/deepl、离线/回退提示）；回归 `translate_ffi_test.dart`/`no_hardcoded_key_test.dart`/`settings_page_test.dart` | T-005 | 1d | **US-10 [单测]**：注入 DeepL stub + key + `auto` → `provider=="deepl"`、`from_cache==false`、译文非空、无"离线未命中"错误。**US-12 [widget 测试]**：见 T-005 + 点击"去设置"后 `SettingsPage` 收到同一 fake 实例（`getConfig` 用该 fake）。**US-13 [widget 测试]**：`provider:'deepl'&&!fromCache` → "在线"+"deepl"；`provider:'offline'+fallbackReason` → "离线"+回退提示。**US-16 [单测]/[widget 测试]**：`cargo test --release -p reader_core` + `flutter test` 全绿；`reading_progress`/`Locator`/`translation_cache` 键/`translate` 错误语义/`disableContextMenu`/选区回传不变；既有 `contains('未配置在线翻译 API Key')` 断言仍通过 |
| **T-009** | **全量回归 + 原型逐屏自检 + CRAP/DDD + 真机清单**（闸门3 前置）：`cargo test --release -p reader_core` + `flutter test` + `flutter test integration_test -d linux`（xvfb）+ `bash scripts/ui-screenshots.sh REQ-007`；生成 `03-crap-report.md`/`03-ddd-report.md`（FAIL=0、违规=0）；逐屏对照 `01-immersive`/`02-menus`/`04-selection`/`08-translation`/`03-settings` 输出偏差清单（deviation=0）；输出 Android 真机手工清单 | T-001..T-008 | 1d | **US-16 [单测]/[widget 测试]/[集成测试]**：全量绿；CRAP FAIL=0、DDD 违规=0；`ui-screenshots.sh REQ-007` 退出码 0、截图更新。**US-17 [真机]**：清单含 ① 分页点文字呼出/再点隐藏；② 分页边缘章内翻页/章末续章；③ 底栏"下一章"正文更新；④ 长按选中仍出工具条；⑤ 未配 key 翻译出现"去设置"并可进入设置页。**US-3**：截图无合成页、`reader_chrome`/`reader_more` 由真实点击产生。**原型自检**：逐屏打勾、deviation=0 |

**总估算**：T-001..T-009 合计 **8d**；关键路径 ≈ **3d**（三条并行线在 T-009 汇合）。

## 依赖图（无环）

```
源点：T-001   T-002   T-003   T-005

T-001 ───────────────────────────────────────────────────────────┐
T-005 ───────────────────────────────────────────────────────────┤
T-003 ─→ T-004 ─→ T-007 ──────────────────────────────────────────┤
T-002 ───────────→ T-007 ─────────────────────────────────────────┤
T-005 ─→ T-008 ───────────────────────────────────────────────────┤
                                                                  ▼
                                          T-006（T-001,T-005）─┐
                                          T-007（T-002,T-004）─┼─→ T-009（汇点）
                                          T-008（T-005）───────┘
```
- **DAG 校验**：源点 T-001/T-002/T-003/T-005；唯一汇点 T-009；所有边方向一致，**无环**。
- **关键路径**：T-003(0.5) → T-004(0.5) → T-007(1) → T-009(1) = **3d**（T-001→T-006→T-009 与 T-005→T-008→T-009 同为 3d）。
- **并行线**：手势线 T-001；分页线 T-002 + T-003→T-004；翻译线 T-005；三条线在 T-009 汇合。

## US → Task 覆盖矩阵（全闭合，供阶段 4/5 追溯）

| US | 优先级 | 验证层 | 主责 Task | US | 优先级 | 验证层 | 主责 Task |
|---|---|---|---|---|---|---|---|
| US-1 | P0 | [集成测试] | T-001, T-006 | US-10 | P0 | [单测] | T-008 |
| US-2 | P0 | [集成测试]+[widget 测试]+[单测] | T-001, T-006, T-007 | US-11 | P0 | [单测] | T-005, T-008 |
| US-3 | P0 | [集成测试]+[单测] | T-006 | US-12 | P0 | [widget 测试]+[集成测试] | T-005, T-006, T-008 |
| US-4 | P0 | [集成测试] | T-006, T-007 | US-13 | P0 | [widget 测试] | T-008 |
| US-5 | P0 | [widget 测试] | T-002, T-007 | US-14 | P0 | [集成测试] | T-006 |
| US-6 | P0 | [单测] | T-002 | US-15 | P0 | [widget 测试] | T-007, T-008 |
| US-7 | P0 | [单测] | T-003 | US-16 | P0 | [单测]/[widget 测试]/[集成测试] | T-008, T-009 |
| US-8 | P0 | [单测]+[真机] | T-003, T-004 | US-17 | P0 | [真机] | T-009 |
| US-9 | P0 | [widget 测试] | T-004, T-007 | — | — | — | — |

> 全部 US-1..US-17 均有主责 Task，无遗漏；US-6/7/8 的可测出口由 T-002/T-003/T-004 落定（否则无法验收）。

## 冲突检查结果

- **与 ddd-rules 无冲突（1 项未声明层沿用处置）**：
  1. `core/src/dict/translation.rs`（domain）仅追加错误文案，仍只 `use crate::types/error/dict`，**不**触 `crate::store/api/library` → 违规=0；
  2. 新增 `app/lib/pages/body_tap_policy.dart`、`app/lib/engines/paged_*.dart` 均属 interface（`ddd-rules.toml:12`），只 import Flutter SDK + 本层文件，**不** import `package:reader_app/src/rust/`、`src/rust/`；
  3. `app/lib/widgets/translation_popup.dart` 未被 ddd-rules 声明（同 REQ-005/006）：处置 = 规则表冻结零改动，按 pages 同级纪律人工核对 import 面；
  4. `app/lib/services/*`（application）零改动；`PagedWebViewState` 经插件 API 而非生成物。
- **与 Locator 不变式无冲突**：`core/src/types.rs` 的 `Locator`/`TextAnchor`/`Rect` 零改动；分页切章仍 `href=chapter_%04d.xhtml` + `progression=0.0`（US-5），无 schema/迁移，`user_version` 不变。
- **与听读同进度无冲突**：`reading_progress` 仍是唯一事实源；手势/分页改动不触碰 `ListenPage`/`_reloadProgress`/`saveProgress` 语义；零新表。
- **与既有 REQ 复用不重做无冲突**：REQ-001 分页/进度、REQ-003 选中→翻译/查词、REQ-004 沉浸态/顶底栏/热区、REQ-005 `disableContextMenu`/选区回传/听书、REQ-006 `auto` 策略/回退标签全部**复用**；本 REQ 仅修可达性与补引导。**唯一存量断言影响**：US-11 文案"追加"（`contains` 断言保留，零更新）；错误浮层错误态 golden 若存在需同步（T-005/T-008）。
- **与 `flutter_inappwebview` 平台约束无冲突（已处置）**：Linux 无 WebView → `flutter test integration_test -d linux` 只跑滚动模式（US-1/2/4/12）；分页走 [widget 测试]（T-007，fake 构建器/fake controls）+ [单测]（T-002/003/004）+ [真机]（US-17）；集成测试不实例化 `PagedWebView`；无新增依赖（重载用插件既有 `loadData`）。
- **与 golden/截图影响无冲突（已处置）**：`reader_chrome`/`reader_more` 截图落点改为文字 center（T-006）；错误浮层错误态 golden 若变更同步（T-005/T-008）；`ui-screenshots.sh REQ-007` 退出码 0（T-009）；`product-preview.manifest.json` 截图清单在交付阶段同步。
- **范围划界（不做）**：书架页设置入口（P1 可选，不阻塞 P0）、TTS/听书、笔记/划重点、Provider 进阶管理、生词本、对照阅读、key 加密/钥匙串、WebView 原生选择菜单、阅读器视觉改版均不做（沿用 01-req §1.2）。
- **文档同步风险（已登记，非闸门项）**：`docs/03`/`docs/04` 零签名变更（仅可补"分页重载时序/手势手动判定"注释），开发/交付阶段处理；本阶段按纪律只产出 3 份产物。

## 原型一致性自检清单（T-009 执行，deviation=0）

| 屏 | 核对项（对照 svg 逐项） |
|---|---|
| `reader-ui-v2/01-immersive.svg` | 沉浸态无 Chrome；中部 1/3 呼出/隐藏（含点在文字上）；左右 15% 热区仅分页模式翻页；长按/选中出工具条；**布局零改动** |
| `reader-ui-v2/02-menus.svg` | 顶栏返回/书名·章节/更多；底栏上一章·☰目录·可拖进度条·书签·Aa·下一章；"下一章"真实切章（滚动即时 / 分页重载）；**布局零改动** |
| `reader-ui-v2/04-selection.svg` | 工具条 5 入口 + 选柄零改动；错误态结果卡片仅多"去设置"按钮（未配置翻译时）；**工具条/卡片布局零改动** |
| `08-translation.svg` | 翻译卡片标签（在线/离线/缓存）+ provider 名 + 回退提示零改动；错误文案追加"设置"引导；查词卡片零改动 |
| `03-settings.svg` | "去设置"目标页；直接 push 并透传 backend；页面布局零改动 |
| `reader-ui-v2/03-settings.svg` | Aa 面板本 REQ 不涉及（零改动） |

## 闸门2 自评（计划部分）

- [x] **任务粒度可执行**：T-001..T-009 每项 0.5~1d（合计 8d），每项含具体文件/行为与可断言验收，并映射 US-1..US-17（覆盖矩阵全闭合）。
- [x] **依赖图无环**：DAG 已标注（源点 T-001/T-002/T-003/T-005，汇点 T-009），关键路径 ≈3d；无环。
- [x] **冲突清单为空或已含处置**：ddd-rules（含 widgets 未声明）、Locator 不变式、听读同进度、既有 REQ 复用、`flutter_inappwebview` 平台约束、golden/截图、范围划界、文档同步风险共 8 类，全部无冲突或已列处置。
- [x] **ADR 备选 ≥2 且给出理由**：6 个决策点（D1 四备选 / D2 三 / D3 三 / D4 三 / D5 四 / D6 三）+ 降级线（详见 02-adr）。
- [x] **可测出口落定**：US-6/7/8 分别由 `PagedDocumentReloader`/`parseJsBool`+`PagedJsExecutor`/`PagedViewControls`+`PageTurnCoordinator` 提供（02-design §6），否则不可验收。
- [ ] **待同步项（非本阶段闸门项）**：`docs/03`/`docs/04` 注释同步与 `product-preview.manifest.json` 截图清单在开发/交付阶段完成；不阻塞闸门2。
