<!-- wf-meta: req=REQ-007-reader-interaction-fixes | phase=delivery | agent=release-manager | date=2026-09-09 | gate=passed -->
# REQ-007-reader-interaction-fixes · 阶段5 交付（验证汇总 / 发布说明 / 追溯矩阵）

> 范围（三项 P0 修复）：**问题1** 点击正文中部（含点在文字上）可靠呼出/隐藏顶底栏（R1-1 手势竞技场 +
> R1-2 测试假阳性）；**问题2** 分页切章/章内翻页（R2-1 不重载 + R2-2 JS 布尔解析）；**问题3** 在线翻译
> 引导（R3-1 链路确认 + R3-2 无 key 文案/入口 + R3-3 设置页可达）。
> 版本：`0.7.0+11` → **`0.7.1+12`**（语义化 **patch**：P0 缺陷修复，无新增/变更对外契约，向后兼容）。
> 分支：`wf/REQ-007-reader-interaction-fixes`。代码提交：`d20f789`（开发）、`28d5821`（测试）、
> `c677f6a`（产品验收）、本交付提交。
>
> **闸门5 自评：passed** —— ① 追溯矩阵全闭合（US-1..US-17 = 17/17，孤儿=0）
> ② 全量回归绿（cargo 222/0、flutter 152/4skip、集成 5+12、FFI 3/0、analyze 0、DDD 违规=0、变异 83.3%/98.33%）
> ③ 发布产物齐全（`dist/reader-android-arm64-v0.7.1.apk`，版本/权限/ABI 校验通过）。

---

## 1. 验证结果汇总（release-manager 独立复跑，非引用他人数字）

环境：`export PATH=/root/flutter/bin:$HOME/.cargo/bin:$PATH`；`CARGO_BUILD_JOBS=2`；日期 2026-09-09。

| # | 检查 | 命令 | 本次实测结果 | 结论 |
|---|---|---|---|---|
| 1 | core 全量单测 | `cd core && CARGO_BUILD_JOBS=2 cargo test --release` | **222 passed / 0 failed**（lib 185 + mobi_azw3 21 + p0_corpus 5 + translate_corpus 8 + tts_api 3；Doc-tests 0） | ✅ 绿 |
| 2 | Flutter 全量（普通） | `cd app && flutter test` | **152 passed / 4 skipped / 0 failed**（4 个 FFI 用例无 `.so` 时 `markTestSkipped`） | ✅ 绿 |
| 3 | Flutter 静态分析 | `cd app && flutter analyze` | **No issues found!（0）** | ✅ 0 |
| 4a | 集成测试·交互 | `xvfb-run -a flutter test integration_test/reader_interaction_test.dart -d linux` | **5 passed / 0 failed**（US-1/2/4/12，真实 `ReaderPage`+真实手势） | ✅ 绿 |
| 4b | 集成测试·截图 | `xvfb-run -a flutter test integration_test/screenshots_test.dart -d linux` | **12 passed / 0 failed**（12 张截图更新，`reader_chrome`/`reader_more` 真实点击文字产生） | ✅ 绿 |
| 5 | FFI 端到端 | `READER_CORE_SO=core/target/release/libreader_core.so flutter test test/{rust_bridge,tts_ffi,translate_ffi}_test.dart` | **3 passed / 0 skipped / 0 failed**（真实 `.so`） | ✅ 绿 |
| 6 | DDD 分层 | `scripts/ddd-lint/target/release/ddd-lint check /root/reader --rules workflow/rules/ddd-rules.toml --out workflow/reports/ddd-req007-delivery.md` | **违规总数：0** | ✅ 0 |
| 7 | 变异抽查（引用 `04-mutation.md`） | 定向 `translate_auto` 7 变异体 / REQ-006 全 scope 基线 | **定向 5/6 = 83.3%**；基线校正 **118/120 = 98.33%**；存活变异体 **4/4 = 100% 有结论** | ✅ ≥80% |
| 8 | 新代码覆盖（引用 `04-coverage.md`） | `flutter test --coverage` + 新代码行口径 | 可测新增/改动 Dart **142/142 = 100%** | ✅ ≥85% |
| 9 | Android APK 构建 | `bash scripts/build-android-local.sh` | **✓ 成功**：`dist/reader-android-arm64-v0.7.1.apk`，**48,383,561 B（46.1 MiB）** | ✅ 已构建（详见 §5/§6） |

> **一致性**：cargo 222 与 `04-coverage.md`（222）一致；flutter 普通口径 152 passed / 4 skipped 与 `04-coverage.md`
> 一致；集成 5 + 12 与 `03-review.md` 一致；变异/覆盖数字引用 `04-mutation.md`/`04-coverage.md`（本阶段未重跑）。
> **唯一非绿输出**：`cargo test` 打印既有 `core/src/tts/mod.rs:572 unused variable: text` 警告（REQ-005 遗留，
> 非本 REQ 引入），不影响测试结果。

### 闸门 1–5 状态

| 闸门 | 结论 | 关键数字 / 证据 |
|---|---|---|
| 闸门1 需求 | ✅ passed | `01-req.md`：US-1..US-17 全部可断言；R1-1..R3-3 根因逐条 file:line |
| 闸门2 架构 | ✅ passed | `02-adr.md` D1..D6（每点 ≥2 备选）；`02-design.md` US 全映射；`02-plan.md` T-001..T-009 DAG 无环 |
| 闸门3 开发 | ✅ passed | `03-review.md`；cargo 222/0、flutter 149/4skip、集成 5+12、analyze 0、DDD 0、原型 deviation=0 |
| 闸门4 测试 | ✅ passed | `04-mutation.md` 定向 83.3% / 基线 98.33%；`04-coverage.md` 新代码 142/142 = 100% |
| 闸门5a 产品验收 | ✅ passed | `05b-product-preview.md` 5 屏全通过、deviation=0、gap=0 |
| **闸门5b 交付（本阶段）** | **✅ passed** | 追溯 17/17 闭合（孤儿 0）、全量回归绿、发布产物齐全 |

---

## 2. 变更说明（面向用户）

### 2.1 版本与语义化理由

| 项 | 变更 |
|---|---|
| `app/pubspec.yaml` | `version: 0.7.0+11` → **`0.7.1+12`** |
| `core/Cargo.toml` | 保持 `0.1.0`（内部 crate，非独立发布单元；发布惯例只动 `app/pubspec.yaml`） |
| 其它版本引用 | `README.md`/`docs/**` 无版本标注；Android `versionName/versionCode` 由 Flutter 从 pubspec 派生（已核验 APK = `0.7.1/12`）。 |

**语义化理由（patch）**：本 REQ 仅为三项 **P0 缺陷修复** —— 手势可达性、分页切章/翻页、未配置翻译引导，
**未新增功能、未变更对外接口/数据模型**（`reading_progress`/`Locator`/`translation_cache` 键/FFI DTO 全部零变更），
唯一 core 改动是无 key 错误文案**追加**"设置"引导（既有子串 `contains` 断言不破）。属向后兼容的修复 →
按 SemVer 取 **patch**（`0.7.0 → 0.7.1`），构建号单调 +1（`+11 → +12`）。

### 2.2 用户可见变更

1. **问题1 · 中部点击可靠呼出/隐藏顶底栏（P0）**：移除外层 `GestureDetector.onTapUp`，改由不进手势
   竞技场的 `Listener` + `BodyTapTracker`（位移 ≤18px、时长 ≤500ms、单指/主键）手动判定；正文文字上、
   文字下方空白两种落点均可 toggle；长按选中、拖拽滚动、边缘热区、进度条拖动均不误伤。
2. **问题2 · 分页切章与章内翻页（P0）**：`PagedWebView.didUpdateWidget` 检测 `href/html` 变化并
   `loadData` 重载新文档（`PagedLoadGate` 保证"载入完成后再 relayout"）；`parseJsBool` 正确解析插件
   `json.decode` 返回的 Dart `bool`，`nextPage/prevPage` 章内返回 true 不再误跳章，到章末才续章；
   滚动模式"下一章"回归守住。
3. **问题3 · 在线翻译引导（P0）**：`auto`+已配 key 走在线（`provider=="deepl"`、`fromCache==false`）
   确认无回归；未配 key + 离线未命中时错误文案追加"；请在「设置」中配置在线翻译或导入词库"，错误
   浮层新增"去设置"按钮（仅翻译未配置时出现，查词错误不串扰），点击直达 `SettingsPage` 并透传同一
   `translateBackend`（打通 R3-3 设置页运行期入口）。

### 2.3 变更文件清单（提交 `d20f789`）

- 新增：`app/lib/pages/body_tap_policy.dart`、`app/lib/engines/paged_document_reloader.dart`、
  `app/lib/engines/paged_js_result.dart`、`app/lib/engines/paged_view_controls.dart`。
- 修改：`app/lib/pages/reader_page.dart`、`app/lib/engines/paged_web_view.dart`、
  `app/lib/widgets/translation_popup.dart`、`core/src/dict/translation.rs`（仅文案追加）。
- 测试：`app/test/*`（新增/更新 8 个文件）、`app/integration_test/reader_interaction_test.dart`（新）、
  `app/integration_test/screenshots_test.dart`（去合成页）。

---

## 3. 已知问题与限制（不阻塞闸门，如实登记）

| # | 项 | 说明 | 处置 |
|---|---|---|---|
| 1 | **Android 真机 5 项手工验收（US-17）** | ① 分页点文字呼出/再点隐藏；② 分页边缘章内翻页/章末续章；③ 底栏"下一章"正文更新；④ 长按选中仍出工具条；⑤ 未配 key 翻译出现"去设置"并可进设置页 | 清单见 `03-review.md §4`；Linux 无 WebView，CI 不可自动化；待真机执行 |
| 2 | **分页路径 Linux 不可实跑** | `flutter_inappwebview` 无 Linux 实现 → 分页重载/JS 解析/翻页决策由 [单测]（US-6/7/8）+ [widget 测试]（US-5/9）覆盖，集成测试只跑滚动模式 | 由 US-17 真机兜底；已在追溯矩阵标 ✅* |
| 3 | **REQ-006 遗留测试缺口 `translation.rs:492`** | `translate_auto` 内 `find(p.name()==name)` 的 `==`→`!=` 变异体存活（仅 DeepL 空/空白 key 与 Offline 结果不同才可区分）；生产代码正确，非本 REQ 引入 | 登记为后续补测项（用真实 `DeepLProvider`+`OfflineProvider`+空串 key 跑 `translate_routed`）；见 `04-mutation.md §5` |
| 4 | **横屏设计稿 vs 竖屏实现** | 5 屏线框均 900×640 横屏，实现截图为 1170×2532 竖屏（逻辑 390×844）；结构/元素可校验，横向比例/间距无法校验 | REQ-004/005/006 已确认授权沿用；建议补 390×844 竖屏设计稿（`05b-product-preview.md §5`） |
| 5 | **书架页设置入口（R3-3）未做** | P1 可选增强；本 REQ 已通过"翻译错误浮层 → 去设置"打通 `SettingsPage` 运行期可达 | 范围划界，不阻塞 P0（`01-req.md §1.2/§4`） |
| 6 | **截图 harness 用默认 M3 主题** | 集成测试自建 `MaterialApp`，主色 `#6750A4`（非 `main.dart` indigo 种子色） | 既有 harness 已知限制（REQ-005/006 同款），不影响布局/控件/文案 |
| 7 | **REQ-005 遗留编译警告** | `core/src/tts/mod.rs:572 unused variable: text`（非本 REQ 引入） | 后续清理，不影响构建/测试 |
| 8 | **jniLibs 二进制未随提交入库** | `app/android/app/src/main/jniLibs/**/libreader_core.so` 为跟踪的构建中间物；本次构建因 core 文案改动而变化，按发布惯例（REQ-005/006 同）回退，不提交二进制 | 交付物为 APK；如需可复现构建，重跑 `scripts/build-android-local.sh` |
| 9 | **本机工具链差异** | Android SDK `/root/android-sdk`、NDK 由脚本 `sort -V` 取最新（本次 `28.2.13676358`）、Flutter `/root/flutter`、JDK21 | 已适配 `scripts/build-android-local.sh` |
| 10 | **macOS / Windows 产物** | 非本 REQ 交付目标 | 未构建（如实登记） |

---

## 4. 追溯矩阵（US-1..US-17 全闭合 · 无孤儿）

> 状态图例：**✅** = 实现 + 测试/配置证据闭合；**✅\*** = 上述均闭合，另有**真机项**待手工验收
> （统一指向 `03-review.md §4` 的 5 项清单，不阻塞闸门5）。
> 原型图：`reader-ui-v2/01-immersive.svg` / `reader-ui-v2/02-menus.svg` / `reader-ui-v2/04-selection.svg` /
> `docs/wireframes/08-translation.svg` / `docs/wireframes/03-settings.svg`；「—」= 无专属线框（引擎/测试基建/工程项）。
> 设计列：`02-design.md` 章节 / `02-adr.md` 决策点；计划列：`02-plan.md` Task。

| US | 验收（`01-req.md §2`） | 原型图 | 设计（02-design § / ADR） | 实现（文件/提交 `d20f789`） | 测试证据（具体测试名/报告） | 状态 |
|---|---|---|---|---|---|---|
| **US-1** | 点击正文文字 toggle 顶底栏（再点隐藏；空白同样 toggle） | 01-immersive + 02-menus | §2.2/§4.1；D1；T-001/T-006 | `pages/body_tap_policy.dart`、`pages/reader_page.dart`（Listener+`_applyTap`） | 集成 `reader_interaction_test.dart`「US-1 点击正文文字 center toggle 顶底栏（再点隐藏 + 空白同样 toggle）」；widget `reader_page_test.dart`「沉浸态进入 + 点击正文文字呼出顶底栏 + 底栏下一章」「点击正文文字再次隐藏 chrome」 | ✅ |
| **US-2** | 呼出/隐藏不误伤长按选中与滚动；分页边缘不 toggle | 01-immersive | §2.2/§4.1；D1；T-001/T-006/T-007 | `body_tap_policy.dart`（阈值四条件）、`reader_page.dart` | 单测 `body_tap_policy_test.dart`（16 例：位移/时长/多指/主键/cancel/分区表）；集成「US-2 长按选中不误触 Chrome」「US-2 拖拽滚动不误触 Chrome」；widget「US-2 长按正文不触发 Chrome toggle」「US-2 分页模式：左右边缘点击翻页且不 toggle Chrome（注入 fake controls）」 | ✅ |
| **US-3** | 呼出态截图/集成用例禁止合成页 | 02-menus | §6；D6；T-006 | `integration_test/screenshots_test.dart`（去合成 `Column`）、`test/no_synthetic_chrome_test.dart` | `no_synthetic_chrome_test.dart`「integration_test/*.dart 禁止出现合成 ReaderTopBar(/ReaderBottomBar(」；集成 `screenshots_test.dart`「screenshot 阅读器·呼出顶底栏（真实点击正文文字）」「screenshot 阅读器·更多菜单（听书入口）」（12/12 passed） | ✅ |
| **US-4** | 滚动模式底栏"下一章"（回归基线） | 02-menus | §4.2；D2；T-006/T-007 | `reader_page.dart`（`_goChapter`） | 集成「US-4 滚动模式底栏"下一章"真实切章并保存进度」（`saved.href=='chapter_0002.xhtml'`）；widget「沉浸态进入 + 点击正文文字呼出顶底栏 + 底栏下一章」 | ✅ |
| **US-5** | 分页模式底栏"下一章"以新 href 重建分页视图 | 02-menus | §4.2；D2/D4；T-002/T-007 | `paged_document_reloader.dart`、`reader_page.dart` | widget `reader_page_test.dart`「US-5 分页模式：底栏下一章 → fake 构建器收到新 href + 保存章首进度」（`href=='chapter_0002.xhtml'`、`progression==0.0`） | ✅ |
| **US-6** | PagedWebView 在 href/html 变化时重载文档（样式变化/幂等不重载） | —（引擎） | §2.3/§4.2；D2；T-002 | `engines/paged_document_reloader.dart`、`engines/paged_web_view.dart` | 单测 `paged_document_reloader_test.dart`（10 例：「href 或 html 变化 → true；均不变 → false（幂等）」「href 变化 → 恰好 1 次 loadData（新 html + reader://book/b1/）」「html 变化 → 重载」「仅 fontSize/theme 变化 → applyStyle 1 次、loadData 0 次」「bookId 变化 → baseUrl 随新 bookId」「begin 后 pending…complete 后放行」等） | ✅ |
| **US-7** | JS 布尔返回值解析正确（bool/'true'/false/null） | —（引擎） | §2.3；D3；T-003 | `engines/paged_js_result.dart`、`engines/paged_web_view.dart` | 单测 `paged_js_result_test.dart`（「Dart bool 原值返回」「num：非 0 为 true，0 为 false」「null / 其它类型 → false（不抛错）」「runBool 解析 bool 与字符串路径」「runInt：num / 字符串 / 非法值 fallback」） | ✅ |
| **US-8** | 边缘点击章内翻页、章末才续章（左右对称） | 01-immersive + 02-menus | §2.3；D4；T-003/T-004 | `engines/paged_view_controls.dart`、`reader_page.dart`（`_page` 委托 `PageTurnCoordinator`） | 单测 `page_turn_coordinator_test.dart`（「US-8 章内 nextPage()==true → 不调用 goChapter」「US-8 章末 nextPage()==false → goChapter(+1) 恰好 1 次」「US-8 章首 prevPage()==false → goChapter(-1) 恰好 1 次」「US-8 章内 prevPage()==true → 不跳章（左边缘对称）」） | ✅\* 真机 ② |
| **US-9** | 分页切章不丢既有能力（fontSize/选中回调/REQ-005 配置） | 02-menus | §6；D4；T-004/T-007 | `engines/paged_web_view.dart`、`reader_page.dart` | widget「US-9 分页切章后 fontSize 仍按当前 Aa 传入且选中回调仍接线」；REQ-005 回归 `reader_selection_test.dart`/`reader_page_test.dart` 全绿；`buildPagedWebViewSettings(disableContextMenu:true)` 未变 | ✅ |
| **US-10** | `auto`+key 走在线（provider=="deepl"、from_cache==false） | 08-translation | §2.1；D5；T-008 | `core/src/dict/translation.rs`（`translate_auto`，零逻辑改动） | 单测 `translation.rs`「translate_auto_configured_key_provider_is_deepl_uncached」「translate_auto_prefers_online_when_key_configured」；FFI `translate_ffi_test.dart`「FFI：RustTranslateBackend DTO 映射 / 策略 / 回退原因（US-10/13/15/17/18）」 | ✅ |
| **US-11** | 无 key + 离线未命中：文案含"设置"引导；离线命中语义不破 | 08-translation | §2.1；D5；T-005/T-008 | `core/src/dict/translation.rs:562-568`（文案追加） | 单测 `translation.rs`「translate_auto_unconfigured_and_offline_miss_message」（三段子串并存，含 `"设置"`）「translate_auto_without_key_falls_back_offline_with_reason」；全量 `cargo test` 222/0 证明既有 `contains` 断言不破 | ✅ |
| **US-12** | 无 key 错误浮层提供"去设置"入口并透传 backend；查词不串扰 | 04-selection + 08-translation | §2.4/§4.3；D5；T-005/T-006/T-008 | `widgets/translation_popup.dart`（`onOpenSettings` 可选）、`reader_page.dart`（`_openTranslateSettings`） | widget `translate_reader_test.dart`「US-12 无 key 翻译错误浮层：文案含"设置" + 去设置/重试，点击去设置进入设置页且透传同一 backend」「US-12 查词失败不出现"去设置"」；集成「US-12 无 key 翻译错误浮层 → 去设置 → SettingsPage」 | ✅ |
| **US-13** | 在线/离线来源标签回归 | 08-translation | §2.4；T-008 | `widgets/translation_popup.dart`（标签逻辑未动） | widget「US-18 译文卡片标签：在线/离线/缓存 + provider 名 + 回退提示」「US-13 在线链路：provider=deepl 且未缓存 → 卡片显示"在线"+"deepl"」；`05b-product-preview.md` S4（真实渲染像素证据） | ✅ |
| **US-14** | 真实 integration_test 覆盖三大问题（禁合成页） | — | §6；D6；T-006 | `integration_test/reader_interaction_test.dart` | 本次 `xvfb-run … reader_interaction_test.dart -d linux` → **5 passed / 0 failed**（US-1/2/4/12，全程真实 `ReaderPage`+`tapAt`/`longPress`/`drag`） | ✅ |
| **US-15** | widget 测试覆盖分页与手势矩阵 | — | §6；T-007/T-008 | `app/test/reader_page_test.dart`、`translate_reader_test.dart` | 见 US-2/5/9/12/13 用例；本次 `flutter test` **152 passed / 4 skipped / 0 failed** | ✅ |
| **US-16** | 零回归（REQ-001/003/004/005/006 既有能力） | — | §7；T-008/T-009 | 既有代码零破坏（新增均为加法/可选参数） | `cargo test --release` **222/0**；`flutter test` **152/4skip/0**；集成 **5+12**；FFI **3/0**；`reader_selection_test`/`settings_page_test`/`listen_*`/`no_hardcoded_key_test` 全绿；`reading_progress`/`Locator`/缓存键/错误语义不变 | ✅ |
| **US-17** | Android 真机验收清单 ①–⑤ | — | §6；[真机]；T-009 | APK `dist/reader-android-arm64-v0.7.1.apk` | 清单见 `03-review.md §4`（CI 不可自动化；已用 manifest 断言 + 单测 + widget + FFI 兜底） | ✅\* 真机 ①–⑤ |

**闭合统计**：US-1..US-17 共 **17 条** → **✅ 15 条 + ✅\* 2 条（US-8 真机 ②、US-17 真机 ①–⑤）= 17/17 全部闭合；孤儿需求 = 0**。

### 4.1 三项 P0 的端到端证据链

- **P0-1 中部点击呼出（问题1）**：`BodyTapTracker`/`resolveBodyTap` 纯函数（`body_tap_policy_test.dart` 16 例）
  → `reader_page.dart` `Listener` 接线（`reader_page_interaction_coverage_test.dart` 覆盖 dismiss/onPointerMove）
  → 真实集成 `reader_interaction_test.dart` US-1/US-2（真实 `tapAt` 文字 center + `longPress` + `drag`）
  → 真实渲染截图 `app/screenshots/reader_chrome.png`（05b S2，非合成页）→ 真机 ①④。
- **P0-2 分页切章/翻页（问题2）**：`PagedDocumentReloader`（`paged_document_reloader_test.dart` 10 例）+
  `parseJsBool`/`PagedJsExecutor`（`paged_js_result_test.dart` 5 例）+ `PageTurnCoordinator`
  （`page_turn_coordinator_test.dart` 4 例）→ widget `reader_page_test.dart` US-5/US-9（新 href + 样式/回调接线）
  → 滚动模式集成 US-4 → 真机 ②③。
- **P0-3 在线翻译引导（问题3）**：`translate_auto` 文案追加（`translation.rs` 单测）→ `OverlayError.onOpenSettings`
  可选按钮 + `isTranslationNotConfiguredError` 谓词（`translate_reader_test.dart` US-12/13）→ `_openTranslateSettings`
  push `SettingsPage(translateBackend: …)` → 集成 US-12（真实长按→翻译→去设置）→ 真机 ⑤。

---

## 5. 发布产物清单

| 项 | 内容 | 状态 |
|---|---|---|
| **版本号** | `0.7.1+12`（`app/pubspec.yaml`） | ✅ |
| **源码** | 分支 `wf/REQ-007-reader-interaction-fixes`；`d20f789`（feat）、`28d5821`（test）、`c677f6a`（test 产品验收）、本交付提交 | ✅ |
| **Android APK** | `dist/reader-android-arm64-v0.7.1.apk`，**48,383,561 B（46.1 MiB）**；`versionName=0.7.1 / versionCode=12`；`dist/` 已 gitignore，仅登记路径不入库 | ✅ 已构建 |
| **质量报告** | `workflow/reports/ddd-req007-delivery.md`（违规=0）；`04-mutation.md`（83.3%/98.33%）；`04-coverage.md`（100%） | ✅ |
| **产品验收** | `05b-product-preview.md` + `product-preview.manifest.json` + `product-preview-REQ-007-*.html` + `app/screenshots/*.png` | ✅ |

### 5.1 APK 产物校验（`aapt2`/`unzip`，build-tools 36.0.0）

| 校验项 | 期望 | 实测 | 结论 |
|---|---|---|---|
| 文件路径 | `dist/reader-android-arm64-v0.7.1.apk` | 存在 | ✅ |
| 大小 | — | `48,383,561 B`（46.1 MiB） | ✅ |
| SHA-256 | — | `049bf900f5d5d07a05694abb55420e0889d5f7050336b648614a0338cdfec880` | 记录 |
| versionName | `0.7.1` | `versionName='0.7.1'` | ✅ |
| versionCode | `12` | `versionCode='12'` | ✅ |
| 包名 / SDK | `com.reader.reader_app` | `name='com.reader.reader_app'`，minSdk 24 / targetSdk 36 | ✅ |
| INTERNET 权限 | 含 | `uses-permission: android.permission.INTERNET` | ✅ |
| TTS_SERVICE 可见性 | 含 | `<queries>` 含 `android.intent.action.TTS_SERVICE` | ✅ |
| PROCESS_TEXT 可见性 | 含 | `<queries>` 含 `android.intent.action.PROCESS_TEXT` | ✅ |
| ABI（native-code） | 3 ABI | `arm64-v8a` `armeabi-v7a` `x86_64` | ✅ |
| `libreader_core.so` | 3 ABI | arm64 `7,128,520 B` / armeabi-v7a `5,184,940 B` / x86_64 `7,703,664 B` | ✅ |

> 注：TTS_SERVICE / PROCESS_TEXT 为 Android `<queries>` 包可见性声明（非 `uses-permission`），
> 由 `android_manifest_test.dart` 静态断言 + 本 APK `xmltree` 实测双重确认。

---

## 6. Android APK 构建记录

- 命令：`bash scripts/build-android-local.sh`（本机适配：JDK21 `/usr/lib/jvm/java-21-openjdk-amd64`、
  Android SDK `/root/android-sdk`、NDK `28.2.13676358`；Rust 交叉编译 3 ABI → jniLibs →
  `flutter build apk --release --target-platform android-arm64` → 归档 `dist/reader-android-arm64-v${VER}.apk`）。
- 结果：**✓ 成功**（日志 `/tmp/opencode/req007-apk-build.log`）。
  - Rust 三目标 `aarch64/armv7/x86_64-linux-android` 全部 `Finished release`（11.3s / 14.0s / 10.2s）。
  - Gradle `assembleRelease` 成功（90.6s），产物 `app-release.apk (48.4MB)`。
  - 归档：`/root/reader/dist/reader-android-arm64-v0.7.1.apk`。
- 构建噪声：`flutter_tts` KGP 弃用警告（Flutter 未来版本兼容性提示，非本次构建失败原因）；
  jniLibs 中间物因 core 文案改动而更新，按发布惯例回退不入库（见 §3 #8）。

---

## 7. 闸门5 自评

- [x] **追溯矩阵全闭合**：US-1..US-17 = **17/17**（✅ 15 + ✅\* 2），**孤儿需求 = 0**；每条均有
      原型图/设计章节/实现文件/具体测试名证据；三项 P0 端到端证据链见 §4.1。
- [x] **全量回归绿**：cargo **222 passed / 0 failed**；flutter **152 passed / 4 skipped / 0 failed**；
      集成 **5 + 12 passed / 0 failed**；FFI 端到端（真实 `.so`）**3 passed / 0 failed**；
      `flutter analyze` **0 issues**；DDD **违规=0**；变异 **定向 83.3% / 基线 98.33% ≥ 80%**，
      存活变异体 100% 有结论；新代码覆盖 **142/142 = 100% ≥ 85%**。
- [x] **发布产物齐全**：版本 `0.7.1+12`；APK `dist/reader-android-arm64-v0.7.1.apk`
      （48,383,561 B；`versionName=0.7.1`/`versionCode=12`；INTERNET + TTS_SERVICE + PROCESS_TEXT；
      3 ABI `libreader_core.so`）；DDD 报告；产品验收产物。

**结论：闸门5 passed。**

---

## 8. 合并建议与交接

- **建议合并** `wf/REQ-007-reader-interaction-fixes` → `main`（普通合并）。
- **前置**：等待 orchestrator / 用户确认；**本代理不自行合并 main、不 force-push、不改 STATE.md**。
- **真机交接**：`03-review.md §4` 的 5 项 Android 手工清单（US-17）需在真机执行后方可对外发布。
- 合并提交信息建议：`chore(release): REQ-007 v0.7.1 阅读器交互修复`。

---

## 9. 本阶段产物

| 文件 | 变更 |
|---|---|
| `app/pubspec.yaml` | `0.7.0+11` → `0.7.1+12` |
| `workflow/backlog/REQ-007-reader-interaction-fixes/05-delivery.md` | 新增（本文件，带 wf-meta 头） |
| `workflow/reports/ddd-req007-delivery.md` | 新增（DDD 违规=0） |
| `dist/reader-android-arm64-v0.7.1.apk` | 本地构建产物（`dist/` gitignored，不入库，见 §5/§6） |
| `app/build/**`、`app/android/app/src/main/jniLibs/**` | 构建中间物（jniLibs 已回退，不入库） |
