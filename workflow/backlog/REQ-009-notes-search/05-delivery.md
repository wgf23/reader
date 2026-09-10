<!-- wf-meta: req=REQ-009-notes-search | phase=delivery | agent=release-manager | date=2026-09-09 | gate=passed -->
# REQ-009-notes-search · 阶段5b 交付（验证汇总 / 发布说明 / 追溯矩阵）

> 范围：**笔记 NOTE-01~07**（选中多色高亮/划线/批注、笔记面板分组+搜索+跳回临时高亮、
> 编辑/改色/删除/多选批量删除、书签持久化+列表跳转、Markdown/JSON 导出）+ **全文搜索 READ-06**
> （CJK bigram 索引、结果关键词高亮、定位跳转、范围/格式筛选），并守住进度/听读/选词翻译/连续滚动零回退。
> 版本：`0.8.0+13` → **`0.9.0+14`**（语义化 **minor + build**：新增对外可感知的笔记与全文搜索功能，向后兼容；
> `reading_progress`/`Locator` 契约/`ChapterData` 兼容默认值/`tts::*` 零语义变更；schema 从 v3 → v4 由幂等迁移承载）。
> 分支：`wf/REQ-009-notes-search`（基于 `main` `5f220f9`）。
> 代码提交：`3b8af1d`（开发）、`5c5cf8d`（测试/变异/覆盖）、`40c2260`（产品验收首轮 deviation=1）、
> `1c95920`（rework-B D1 修复）、`975b14a`（5a 复验 deviation=0）、本交付提交。
>
> **闸门5 自评：passed** —— ① 追溯矩阵全闭合（US-1..US-24 = 24/24，孤儿=0；US-24 真机项标 ✅\* 待人工验收，非阻塞）
> ② 全量回归绿（cargo 282/0、flutter 288/5skip/0、analyze 0、DDD 0、FFI 端到端 2/0、真实集成逐文件 2+5+5+17）
> ③ 发布产物齐全（`dist/reader-android-arm64-v0.9.0.apk`，versionName/versionCode/ABI/权限/资产独立 `aapt2`+`unzip` 校验通过）。

---

## 1. 验证结果汇总（release-manager 独立复跑，非引用他人数字）

环境：`export PATH="/root/flutter/bin:/root/.cargo/bin:$PATH"`；`CARGO_BUILD_JOBS=2`；日期 2026-09-09。
日志：`/tmp/opencode/req009-{cargo-test,flutter-test,analyze,ffi,integration,build-android}.log`。

| # | 检查 | 命令 | 本次实测结果 | 结论 |
|---|---|---|---|---|
| 1 | core 全量单测 | `cd core && CARGO_BUILD_JOBS=2 cargo test --release` | **282 passed / 0 failed**（lib 241 + mobi_azw3 21 + notes_search 3 + notes_search_api 1 + p0_corpus 5 + translate_corpus 8 + tts_api 3；Doc-tests 0） | ✅ 绿 |
| 2 | Flutter 全量（普通） | `cd app && flutter test` | **288 passed / 5 skipped / 0 failed**（5 个 FFI 用例无 `.so` 时 skip） | ✅ 绿 |
| 3 | Flutter 静态分析 | `cd app && flutter analyze` | **No issues found!（0 issues）** | ✅ 0 |
| 4 | FFI 端到端（真实 `.so`） | `READER_CORE_SO=core/target/release/libreader_core.so flutter test test/rust_bridge_test.dart test/notes_search_ffi_test.dart` | **2 passed / 0 skipped / 0 failed**（导入真实 EPUB 全链路 + 笔记 CRUD/书签/导出/搜索映射） | ✅ 绿 |
| 5 | 真实集成·笔记/搜索（核心） | `xvfb-run -a flutter test integration_test/notes_search_integration_test.dart -d linux` | **2 passed / 0 failed**（US-10 选词→高亮→面板→跳回；US-22 搜索→结果→定位） | ✅ 绿 |
| 6 | 真实集成·REQ-008 回归 | `xvfb-run -a flutter test integration_test/reader_continuous_scroll_test.dart -d linux` | **5 passed / 0 failed** | ✅ 绿 |
| 7 | 真实集成·REQ-007 回归 | `xvfb-run -a flutter test integration_test/reader_interaction_test.dart -d linux` | **5 passed / 0 failed** | ✅ 绿 |
| 8 | 真实集成·截图 | `xvfb-run -a flutter test integration_test/screenshots_test.dart -d linux` | **17 passed / 0 failed**（含 REQ-009 S1–S4 真实渲染截图） | ✅ 绿 |
| 9 | DDD 分层 | `scripts/ddd-lint/target/release/ddd-lint check /root/reader --rules workflow/rules/ddd-rules.toml` | **违规总数：0**（报告 `workflow/reports/ddd-req009-delivery.md`） | ✅ 0 |
| 10 | 变异（引用 `04-mutation.md`） | `cargo mutants`（域+仓储 7 文件 + api 桥接） | 合计 **96.81%**（364/376；域 96.58%、api 100%）；存活 12/12 有结论 | ✅ ≥80% |
| 11 | 新代码覆盖（引用 `04-coverage.md`） | `flutter test --coverage` + `cargo llvm-cov`（新代码行口径） | Dart **870/874 = 99.54%**、Rust **2210/2231 = 99.06%** | ✅ ≥85% |
| 12 | Android APK 构建 | `bash scripts/build-android-local.sh` | **✓ 成功**：`dist/reader-android-arm64-v0.9.0.apk`，**49,619,805 B（47.3 MiB）** | ✅ 已构建（详见 §5/§6） |

> **一致性**：cargo 282 与 `04-coverage.md`（282）一致；flutter 288 passed / 5 skipped 与 `04-mutation.md`（288）一致；
> 真实集成 `notes_search` 2/2 与 `03-review.md`/`05b` 一致。变异/覆盖数字引用阶段4产物（本阶段未重跑全量，
> 已独立复跑 cargo/flutter/analyze/FFI/集成/DDD 与 APK 构建）。
> **唯一非绿输出**：`cargo test` 打印既有 `core/src/tts/mod.rs:572 unused variable: text` 警告（REQ-005 遗留，
> 非本 REQ 引入），不影响测试结果；`flutter build apk` 打印 `flutter_tts` KGP 弃用警告（未来兼容性提示，非失败）。

### 闸门 1–5 状态

| 闸门 | 结论 | 关键数字 / 证据 |
|---|---|---|
| 闸门1 需求 | ✅ passed | `01-req.md`：US-1..US-24 全部可断言、四类测试层级齐备；R1..R16 根因逐条 file:line；§1.4 与 REQ-003/005/006/008 无重复；影响面 §3.1-§3.6 非空 |
| 闸门2 架构 | ✅ passed | `02-adr.md` D1..D12（每点 ≥2 备选 + 理由 + 降级线）；`02-design.md` 接口/时序/v4 DDL/逐屏映射 06/07/04；`02-plan.md` T-001..T-026 DAG 无环、US 覆盖闭合、C1–C15 冲突全处置 |
| 闸门3 开发 | ✅ passed | `03-review.md`；cargo 259/0（补测后 282/0）、flutter 198/4skip（补测后 288/5skip）、analyze 0、DDD 0、原型 deviation=0；rework-B D1 修复后复验全绿 |
| 闸门4 测试 | ✅ passed | `04-mutation.md` 变异 **96.81%**（存活 12/12 有结论）；`04-coverage.md` 新代码 Dart **99.54%** / Rust **99.06%** |
| 闸门5a 产品验收 | ✅ passed | `05b-product-preview.md` S1/S2/S3/S4 全通过、**deviation=0**（D1 经 `REWORK-REQ-009-B.md` gate=passed 闭环） |
| **闸门5b 交付（本阶段）** | **✅ passed** | 追溯 24/24 闭合（孤儿 0）、全量回归绿、发布产物齐全 + APK 独立校验 |

---

## 2. 变更说明（面向用户）

### 2.1 版本与语义化理由

| 项 | 变更 |
|---|---|
| `app/pubspec.yaml` | `version: 0.8.0+13` → **`0.9.0+14`** |
| `core/Cargo.toml` | **保持 `0.1.0`**（内部 crate，非独立发布单元；全仓发布惯例只动 `app/pubspec.yaml`，REQ-003~008 一致） |
| 其它版本引用 | `README.md`/`docs/**` 无版本标注；Android `versionName/versionCode` 由 Flutter 从 pubspec 派生（`app/android/app/build.gradle.kts:28-29`，已用 `aapt2` 实测 APK = `0.9.0/14`） |

**语义化理由（minor + build）**：本 REQ **新增对外可感知功能**——持久化笔记（NOTE-01~07）与全文搜索
（READ-06），属向后兼容的功能增量，故取 **minor**（`0.8.0 → 0.9.0`），构建号单调 +1（`+13 → +14`）。
无破坏性契约变更：`Locator` 结构零变更（仅新增构造/解析函数）、`reading_progress` 仍是唯一进度事实源、
`ChapterData.href` 带默认值 `''`（既有 fake 不破）、`tts::*` 零改动；数据层 v3 → v4 由幂等迁移承载
（既有数据零丢失，旧书懒回填索引）。

### 2.2 用户可见变更

1. **多色高亮 / 划线 / 批注（NOTE-01~03，US-1~5）**：真实长按选中文字 → 浮动工具条
   `复制 / 高亮(4 色) / 划线 / 批注 / 翻译 / 查词`；高亮取 `NoteColors` 四色
   （`#FBC02D/#1A73E8/#43A047/#E91E63`），划线渲染 `TextDecoration.underline`，批注弹输入卡片；
   均持久化到 `annotations`（v4），文本锚（UTF-16 区间 + progression 消歧）在换字号/主题/重排后重定位。
2. **笔记面板（NOTE-04/05，US-6~13）**：右侧覆盖层按章节分组列出全书笔记（色标 + 原文片段 + 批注 +
   `MM-dd` 时间）、面板内搜索过滤、点击条目跳回原文并临时高亮（`Key('temp-highlight')`，3s/滚动/点击清除）、
   编辑批注/改色、单条删除、多选批量删除、全部删除（均二次确认，删除后原文标记同步清理）、点外部关闭。
3. **书签（NOTE-06，US-14）**：底栏 🔖 落库 `kind=bookmark`（幂等切换），书签行并入面板、点击跳转。
4. **导出（NOTE-07，US-16/17）**：Markdown / JSON 两格式，含书名/章节/锚点/片段/批注/时间；
   桌面弹保存框（取消不写文件），移动端写应用文档目录；空笔记提示「暂无笔记」。
5. **全文搜索（READ-06，US-18~22）**：`SearchPage` 顶部搜索框 + 「全文搜索」；CJK **bigram 预处理 + FTS5
   unicode61**（2 字中文词可命中，单字走 LIKE 回退）；结果行=书名（粗）+「第 N 章 · 章节名」（**真实章节序号**）
   + 上下文关键词蓝色加粗 + 「定位」；右侧筛选面板（范围：全部书籍/当前书籍；格式：EPUB/PDF/MOBI 复选）+
   「结果 N 条 · X.XXs」；点击定位跳转并临时高亮关键词；空/特殊字符输入安全。
6. **零回退**：选词翻译/查词/复制、听书跟读临时高亮、连续滚动/进度恢复、分页翻页、书签会话语义均保持；
   `reading_progress`/听读同进度不变。

### 2.3 变更文件清单（`main..HEAD`，96 files +42,743/-161）

- **core（10 src + 2 tests）**：新增 `store/annotations.rs`、`store/search_index.rs`；改
  `types.rs`（契约/值对象）、`store/mod.rs`（v4 迁移 + `remove_book` 事务清 FTS + busy_timeout）、
  `store/translation.rs`（busy_timeout）、`locator/mod.rs`（from_selection/text_at）、
  `notes/mod.rs`（AnnotationService CRUD/分组/导出/书签）、`search/mod.rs`（bigram/expr/snippet/SearchService）、
  `api.rs`（9 个 notes 桥接 + search + 单例装配 + `chapter_index` 回填）、`frb_generated.rs`（生成物）；
  新增 `tests/notes_search.rs`、`tests/notes_search_api.rs`。
- **app/lib（21 文件）**：新增 `services/{notes_backend,rust_notes_backend,search_backend,rust_search_backend,export_path_picker}.dart`、
  `widgets/{note_colors,note_editor_card,notes_panel}.dart`、`pages/note_span_policy.dart`；改
  `pages/{reader_page,notes_page,search_page,continuous_scroll_policy,library_page}.dart`、
  `widgets/selection_toolbar.dart`、`services/{library_backend,rust_library_backend}.dart`、`src/rust/**`（生成物）。
- **测试/文档**：`app/test/*`（新增 8 文件 + 既有断言更新）、`app/integration_test/{notes_search_integration_test,screenshots_test}.dart`、
  `app/screenshots/*`（4 张真实渲染）、`docs/03 §4`、`docs/04 §3/§5/§7`、`workflow/reports/*`。
- **版本**：`app/pubspec.yaml`。

---

## 3. 已知问题与限制（不阻塞闸门，如实登记）

| # | 项 | 说明 | 处置 |
|---|---|---|---|
| 1 | **Android 真机 8 项手工验收（US-24）** | ① 选中→高亮(4 色)/划线/批注并重开仍在；② 面板分组+跳回临时高亮；③ 编辑/改色/删除/多选批量（含二次确认）后原文标记消失；④ 书签当前页/重开/列表跳转；⑤ 导出 Markdown/JSON（移动端路径可观察）；⑥ 全文搜索/关键词高亮/定位；⑦ 换字号/主题后高亮不丢；⑧ 既有选词翻译/查词/复制、听书跟读、连续滚动、进度恢复零回退 | 清单见 `03-review.md §6` / `01-req.md US-24`；Linux 无 Android 真机，CI 不可自动化；待真机执行（追溯矩阵标 ✅\*） |
| 2 | **视口方向 tradeoff** | 线框 900×640 横屏 vs 实现 1170×2532 竖屏（逻辑 390×844）；结构/元素/行为可校验，横向比例无法校验 | 既有授权沿用（REQ-004~008）；`05b §3/§4` 建议补 390×844 竖屏设计稿 |
| 3 | **既有 `tts` unused 警告** | `core/src/tts/mod.rs:572 unused variable: text`（REQ-005 遗留，非本 REQ 引入） | 不影响测试/构建，后续清理 |
| 4 | **macOS / Windows / iOS 产物** | 非本 REQ 交付目标 | 未构建（如实登记） |
| 5 | **集成测试目录级命令限制** | `flutter test integration_test -d linux`（一次跑目录内多文件）在本环境首个文件后报 `Unable to start the app on the device`（工具链限制，与代码无关） | 采用**逐文件**运行：notes_search 2 + continuous 5 + interaction 5 + screenshots 17 = 29/0 全绿（§1 #5-8） |
| 6 | **jniLibs 二进制中间物** | `app/android/app/src/main/jniLibs/**/libreader_core.so` 为跟踪的构建中间物；本次构建按脚本重新生成（与旧基线不同，因 core 新增笔记/搜索代码） | 按既有发布惯例（REQ-001~008 均未提交更新后的 jniLibs）**回退不入库**；交付物为 APK，可复现构建见 `scripts/build-android-local.sh`（§6） |
| 7 | **构建噪声（非失败）** | `flutter_tts` KGP 弃用警告（未来兼容性提示）；`cargo test` 既有 tts unused 警告 | 不影响构建/测试结果 |
| 8 | **rework-B D1（已闭环）** | 首轮 5a 产品验收 S3「第 N 章」用结果列表序号而非真实章节序号 | `REWORK-REQ-009-B.md` gate=passed；修复 commit `1c95920`（`SearchHit` 增 `chapter_index`，`api.rs` 按书回填）；`975b14a` 复验 deviation=0 |
| 9 | **截图 harness 默认 M3 主题** | 集成测试自建 `MaterialApp`，主色 `#6750A4`（非 `main.dart` indigo 种子色） | 既有 harness 已知限制（REQ-005/006/008 同款），不影响布局/控件/文案 |

> rework 计数：REQ-009 **A=0 B=1 C=0 D=0**（B 已闭环，gate=passed）。

---

## 4. 追溯矩阵（US-1..US-24 全闭合 · 无孤儿）

> 状态图例：**✅** = 实现 + 测试/配置证据闭合；**✅\*** = 上述均闭合，另有**真机项**待手工验收
> （指向 `01-req.md US-24` / `03-review.md §6` 清单，不阻塞闸门5）。
> 原型图：`docs/wireframes/06-selection-toolbar.svg` / `07-annotation-panel.svg` / `04-search.svg` /
> `reader-ui-v2/02-menus.svg:31-32` / `05-reader.svg:15`；「—」= 无专属线框（引擎/测试基建/真机项）。
> 设计列：`02-design.md` 章节 / `02-adr.md` 决策点 D1–D12；计划列：`02-plan.md` Task。
> 代码列：实现提交 `3b8af1d`（测试补强 `5c5cf8d`，rework-B 修复 `1c95920`）。

| US | 验收（`01-req.md §2`） | 原型图 | 设计（02-design § / ADR） | 实现（文件） | 测试证据（具体测试名/报告） | 状态 |
|---|---|---|---|---|---|---|
| **US-1** | 选中文字多色高亮并持久化（含同段多色、重启重渲染） | 06 / 07 | §2.1/§4.1/§4.2/§6.1；D2/D3/D6；T-001/003/005/006/008/012/015/016/017/018/023 | `core/src/{types,locator,notes,api}.rs`、`store/annotations.rs`；`app/lib/widgets/{selection_toolbar,note_colors}.dart`、`pages/{note_span_policy,reader_page}.dart`、`services/{notes_backend,rust_notes_backend}.dart` | Rust `notes::tests::create_highlight_and_underline_and_note`、`locator::tests::unique_snippet_maps_correct_offsets`/`utf16_offsets_match_dart_substring_semantics`、`store::annotations::tests::crud_roundtrip_and_updated_at`、`tests/notes_search.rs::notes_repo_service_and_export_end_to_end`；Dart `note_span_policy_test.dart`「单条高亮→backgroundColor 为色板色」「同区间多条→order 最大者胜出」「相邻同款合并」、`selection_toolbar_highlight_test.dart`（选色两分支）、`reader_notes_test.dart`「选词→划线/批注落库」；集成 `notes_search_integration_test.dart`「US-10」断言 `kind=highlight`/`color=#1A73E8`/`start!=null`；截图 S1/S2 | ✅ |
| **US-2** | 划线（`kind=underline`、装饰线渲染、与高亮并存） | 06 | §4.1/§6.1；D6；T-006/015/017 | `selection_toolbar.dart`（`SelectionAction.underline`）、`note_span_policy.dart`（underline+decorationColor）、`core/src/notes/mod.rs`、`reader_page.dart` | Rust `notes::tests::create_highlight_and_underline_and_note`；Dart `note_span_policy_test.dart`「划线→underline+decorationColor」「高亮+划线叠加：背景+下划线同时生效」、`reader_notes_test.dart`「选词→划线/批注落库」；集成 US-10（同一落库/渲染机制） | ✅ |
| **US-3** | 批注（`kind=note`+`note_text`、空输入不落库、可追加） | 06 / 07 | §4.1/§4.5/§6.1/§6.2；D6/D8；T-006/015/017/019 | `selection_toolbar.dart`、`widgets/note_editor_card.dart`、`widgets/notes_panel.dart`、`core/src/notes/mod.rs`、`reader_page.dart` | Rust `notes::tests::create_highlight_and_underline_and_note`、`empty_note_text_is_rejected`；Dart `note_span_policy_test.dart`「批注→虚线下划线」「批注+划线并存」、`reader_notes_test.dart`「批注编辑器空文本拦截+取消」「批注编辑器『删除』仅关闭弹窗」、`notes_panel_test.dart`「保存批注→update」「批注清空→提示不保存」；集成 US-10 | ✅ |
| **US-4** | 换字号/主题/重新分页后锚点重定位不丢失、消歧、降级标记 | 06 / 07 | §2.1/§4.2；D2/D6；T-005/016/018 | `core/src/locator/mod.rs`（归一化匹配+UTF-16 偏移+progression 消歧+降级链）、`note_span_policy.dart`（按文本锚分段，与排版无关）、`reader_page.dart`（`_notesByHref` 重载） | Rust `locator::tests::duplicate_snippet_disambiguated_by_progression`/`no_match_falls_back_to_progression_without_text`/`whitespace_normalized_match_maps_back`/`utf16_offsets_match_dart_substring_semantics`/`text_at_rejects_bad_anchor`/`tie_prefers_earliest_occurrence`；Dart `note_span_policy_test.dart`「越界端点忽略」「零宽不产生 span」「emoji 按 UTF-16 切分」、`reader_notes_test.dart`「面板条目 resolve 失败→降级按 note.href 跳转」；集成 US-10 断言文本锚 `start!=null`（重排后按锚重算） | ✅（字号/主题切换的人工终验归真机 US-24⑦） |
| **US-5** | 同段叠加多色高亮与批注（重叠区间、`start/end` 正确） | 06 / 07 | §2.1/§4.2；D2/D6；T-005/016/018 | `core/src/locator/mod.rs`、`note_span_policy.dart`（原子区间切分/order 优先）、`core/src/notes/mod.rs` | Rust `locator::tests::tie_prefers_earliest_occurrence`、`notes::tests::create_highlight_and_underline_and_note`；Dart `note_span_policy_test.dart`「部分重叠→按端点切分原子区间」「同区间多条→order 最大者胜出」「两条重叠划线→order 最大者决定 decorationColor」「临时覆盖持久→临时色+isTemporary」 | ✅ |
| **US-6** | 面板按章节分组展示（色标+片段+批注+时间+空态） | 07 | §4.2/§6.2；D7；T-006/012/019 | `widgets/notes_panel.dart`、`core/src/notes/mod.rs`（`list` 分组）、`pages/notes_page.dart` | Rust `notes::tests::list_groups_by_chapter_stable_order`；Dart `notes_panel_test.dart`「渲染章节分组/片段/批注/书签行」「空笔记→暂无笔记+全部删除禁用+导出提示」「加载失败→错误态」；截图 S2（2 组/6 条/色标 3:2） | ✅ |
| **US-7** | 面板内搜索笔记（命中过滤/清空恢复/无匹配空态） | 07 | §6.2；D7；T-019 | `widgets/notes_panel.dart`（`noteFilter` 纯函数） | Dart `notes_panel_test.dart`「空/纯空白返回原列表」「匹配 snippet（大小写不敏感）」「匹配批注」「匹配章节标题→组内全保留」「无匹配→空列表」「面板内搜索过滤：无匹配显示『无匹配』」 | ✅ |
| **US-8** | 点击条目跳回原文并临时高亮（超时/滚动/点击清除、进度更新） | 07 | §4.2/§4.3；D6/D7；T-016/018/020 | `reader_page.dart`（`_jumpTo`/`_changeChapter`/`Key('temp-highlight')`/Timer 清除）、`note_span_policy.dart` | Dart `reader_notes_test.dart`「笔记面板：点条目跳转+临时高亮」「initialTarget：定位目标章+3 秒后自动清除」「点击正文清除临时高亮」；集成 `notes_search_integration_test.dart`「US-10」断言 `temp-highlight` 出现且面板关闭；截图 S4 | ✅ |
| **US-9** | 面板打开/关闭/点外部关闭（✕、scrim） | 07 | §6.2；D7；T-019/020 | `reader_page.dart`（`_openMore` 笔记入口）、`widgets/notes_panel.dart`（scrim `GestureDetector`） | Dart `reader_notes_test.dart`「笔记面板：更多→笔记打开；点外关闭」「笔记面板关闭按钮→面板消失」、`notes_panel_test.dart`「关闭按钮回调」「点外关闭」 | ✅ |
| **US-10** | **真实集成**：选词→高亮→面板显示→跳回原文（临时高亮） | 06 / 07 | §4.1/§4.2/§4.3；D11；T-023 | `integration_test/notes_search_integration_test.dart`（真实 `ReaderPage`+真实 `longPress`/点击/面板） | `xvfb-run -a flutter test integration_test/notes_search_integration_test.dart -d linux` → **2/2**；US-10 断言 `notes.store` 落库 `kind=highlight/color=#1A73E8/start!=null`、面板出现该条、点击后 `temp-highlight` 出现且 `takeException()==null`；`no_synthetic_chrome_test.dart` 守卫绿 | ✅ |
| **US-11** | 编辑批注 / 改色（`notes_update`、`updated_at` 增大） | 07 | §4.5/§6.2；D7；T-006/019 | `core/src/notes/mod.rs`（update/LWW）、`widgets/note_editor_card.dart`、`notes_panel.dart`、`services/rust_notes_backend.dart` | Rust `notes::tests::update_and_delete_roundtrip`、`create_trims_color_and_sets_real_timestamp`、`store::annotations::tests::crud_roundtrip_and_updated_at`；Dart `notes_panel_test.dart`「保存批注→update 并回列表」「点色标→选色→update color」；FFI `notes_search_ffi_test.dart` 改色/批注往返 | ✅ |
| **US-12** | 删除+二次确认+锚点清理（取消保留、幂等、无孤儿标记） | 07 | §4.5/§6.2；D3/D7；T-003/006/019 | `core/src/notes/mod.rs`（delete）、`store/annotations.rs`、`widgets/note_editor_card.dart`、`notes_panel.dart`、`reader_page.dart`（重载清除标记） | Rust `store::annotations::tests::delete_is_idempotent_and_delete_many`/`delete_existing_row_is_removed`/`delete_all_and_fk_cascade`、`notes::tests::update_and_delete_roundtrip`；Dart `notes_panel_test.dart`「编辑卡片删除→确认后删除」「批量删除：取消不删除」「全部删除取消→保留」；集成 US-10 后 `notes.store` 状态断言 | ✅ |
| **US-13** | 面板内多选批量删除 / 全部删除（未选禁用、二次确认） | 07 | §6.2；D7；T-006/019 | `widgets/notes_panel.dart`（长按/复选框/删除选中/全部删除）、`core/src/notes/mod.rs`（delete_many/delete_all） | Rust `notes::tests::delete_many_and_delete_all_return_actual_counts`、`store::annotations::tests::delete_all_with_kind_filter_returns_actual_count`；Dart `notes_panel_test.dart`「长按进入多选；取消选择后删除选中禁用」「取消多选退出选择态」「直接操作复选框」「批量删除：确认后 deleteMany 并刷新」「批量删除：取消不删除」「全部删除→确认后 deleteAll」「全部删除取消→保留」 | ✅ |
| **US-14** | 书签当前页+持久化+列表跳转（幂等切换、重开图标正确） | 02-menus / 07 | §4.3/§6.2/§6.4；D9；T-006/008/020 | `core/src/notes/mod.rs`（`toggle_bookmark`）、`store/annotations.rs`（`find_bookmark` 按 `(book_id,href,round(progression,3))`）、`api.rs`（`notes_toggle_bookmark`）、`reader_page.dart`（底栏/书签行跳转）、`notes_panel.dart` | Rust `notes::tests::toggle_bookmark_idempotent`/`toggle_bookmark_builds_anchor_from_snippet_when_missing`、`store::annotations::tests::find_bookmark_rounds_progression`；Dart `reader_page_test.dart`「书签图标切换（幂等）」（断言 store 中 bookmark 1→0）、`reader_notes_test.dart`「书签切换失败→提示」；FFI `notes_search_ffi_test.dart` 书签往返 | ✅ |
| **US-15** | 删书级联清笔记 / 清 FTS（`ON DELETE CASCADE`+事务） | —（数据） | §3.1/§3.3；D3；T-002/003 | `core/src/store/mod.rs`（`remove_book` 事务 `DELETE FROM fts_books` + FK CASCADE）、`store/annotations.rs`、`store/search_index.rs` | Rust `store::annotations::tests::delete_all_and_fk_cascade`、`store::search_index::tests::store_remove_book_clears_fts`/`remove_book_clears_rows`、`store::tests::remove_book`；DDD/数据层单测 | ✅ |
| **US-16** | 导出 Markdown/JSON 字段完整 + 转义 + 不阻塞 | 07 | §4.5；D8；T-006/008/022 | `core/src/notes/mod.rs`（`export` Markdown/JSON/转义）、`api.rs`（`notes_export`）、`services/export_path_picker.dart`、`notes_panel.dart`/`reader_page.dart`（导出流程） | Rust `notes::tests::export_markdown_and_json_fields_and_escaping`、`export_empty_notes_errors_without_file`、`tests/notes_search.rs::notes_repo_service_and_export_end_to_end`；Dart `notes_panel_test.dart`「有笔记→选 Markdown→picker 返回路径→export 成功」「选 JSON→扩展名 json」「导出异常→提示导出失败」、`export_path_picker_test.dart`（桌面参数/移动路径） | ✅ |
| **US-17** | 空笔记提示 + 导出路径（桌面保存框取消不写/移动端应用目录） | 07 | §4.5；D8；T-022 | `services/export_path_picker.dart`（桌面 `file_picker`/移动 `path_provider`）、`notes_panel.dart`（空态提示）、`reader_page.dart` | Dart `notes_panel_test.dart`「空笔记→暂无笔记+导出提示」「用户取消保存框→不调用 export」「导出格式对话框取消→不调用 picker」、`export_path_picker_test.dart`「桌面：saveFile 参数正确」「桌面：取消→返回 null 不写文件」「移动：应用文档目录+非法字符替换+时间戳」、`reader_notes_test.dart`「更多→导出：无笔记→提示暂无笔记」「picker 取消→不调用 export」；真机 US-24⑤ | ✅（移动端路径终验归真机） |
| **US-18** | 搜索结果列表（书名/章节/关键词高亮/命中数/耗时）+ 2 字 CJK + 空态 | 04 | §2.1/§2.2/§4.4/§6.3；D1/D4/D5/D10；T-001/004/007/009/010/013/021 | `core/src/search/mod.rs`（bigram/expr/snippet）、`store/search_index.rs`、`api.rs`（`search`）、`types.rs`（SearchHit）、`pages/search_page.dart`（关键词 span 蓝加粗）、`services/{search_backend,rust_search_backend}.dart` | Rust `search::tests::bigram_index_text_examples`/`build_match_expr_safe_and_empty`/`extract_snippet_ranges_point_to_keyword`/`service_query_routes_single_cjk_to_substring_and_multi_to_fts`、`store::search_index::tests::query_fts_hits_two_char_cjk_and_scope`、`tests/notes_search.rs::cjk_two_and_four_char_queries_hit_real_fts`（城市/卡尔维诺/记忆 各 1 命中，≤100ms）、`tests/notes_search_api.rs::notes_and_search_bridge_end_to_end`；Dart `search_page_test.dart`「命中渲染：书名/章节/关键词蓝加粗/结果数耗时」「无命中→未找到相关结果」「初始态+空查询提示」；集成 US-22；截图 S3 | ✅ |
| **US-19** | 点击定位跳转 + 原文关键词临时高亮（跨书正确打开） | 04 | §4.3/§4.4/§6.3；D4/D6/D10；T-009/010/014/018/021 | `pages/search_page.dart`（`Navigator.pop` 返回命中）、`reader_page.dart`（`_openHit`/`initialTarget`/跨书 push）、`note_span_policy.dart` | Dart `search_page_test.dart`「定位按钮→Navigator.pop 返回命中」、`reader_notes_test.dart`「更多→搜索→定位命中（同书）→返回并临时高亮」「搜索命中跨书→push 新 ReaderPage 携带 initialTarget」「initialTarget：定位目标章+3 秒后清除」；集成 `notes_search_integration_test.dart`「US-22」断言跳转后 `temp-highlight` 出现；截图 S4 | ✅ |
| **US-20** | 范围筛选（全部/当前书籍）+ 按格式筛选 + 结果数/耗时 | 04 | §4.4/§6.3；D4/D10；T-004/007/009/013/021 | `core/src/types.rs`（SearchScope）、`search/mod.rs`、`store/search_index.rs`（scope/format 过滤）、`api.rs`、`pages/search_page.dart`（单选/复选/统计） | Rust `search::tests::service_query_routes_single_cjk_to_substring_and_multi_to_fts`、`store::search_index::tests::query_scope_with_book_and_format_combined`、`tests/notes_search_api.rs`（scope/格式过滤）；Dart `search_page_test.dart`「范围筛选：切到当前书籍→scope.allBooks=false+bookId」「格式筛选：默认 EPUB+MOBI；取消 EPUB 后仅 MOBI」「多条结果→范围可切回全部书籍」 | ✅ |
| **US-21** | 搜索性能 <100ms / CJK / 特殊字符安全 / 导入即索引 | 04 | §4.4；D1/D5；T-002/004/007/009/010 | `core/src/search/mod.rs`、`store/search_index.rs`、`api.rs`（`ensure_indexed` 懒回填）、`library/mod.rs`/`api.rs`（导入即索引） | Rust `tests/notes_search.rs::cjk_two_and_four_char_queries_hit_real_fts`（158.958µs/80.551µs/65.015µs）、`single_cjk_char_like_fallback_and_special_chars_safe`（`%`/`_`/`"`/`*`/`NEAR`/空串安全）、`store::search_index::tests::query_substring_single_char_and_special_chars_safe`/`replace_book_is_idempotent_and_is_indexed`；`tests/notes_search_api.rs`（懒回填）；真机性能终验 US-24⑥ | ✅（性能/移动端终验归真机） |
| **US-22** | **真实集成**：搜索→结果→定位→关键词临时高亮 | 04 | §4.3/§4.4；D11；T-023 | `integration_test/notes_search_integration_test.dart`（真实 `SearchPage`+`ReaderPage`+真实点击/导航） | `xvfb-run -a flutter test integration_test/notes_search_integration_test.dart -d linux` → **2/2**；US-22 断言真实输入→结果行「第 2 章 · 第二章」+`search-locate-0`→点击后跳转+`temp-highlight`，`takeException()==null`；`no_synthetic_chrome_test.dart` 守卫绿 | ✅ |
| **US-23** | v4 迁移（annotations+fts_books）幂等/向前兼容/旧书回填 | —（数据） | §3.1/§3.2/§3.3/§4.4；D1/D3/D4/D5；T-002/004/009/010/025 | `core/src/store/mod.rs`（`if version<4`：annotations+idx_annot_book+fts_books 扩列 `text_bi`）、`store/{annotations,search_index}.rs`（第二连接 migrate_conn）、`api.rs`（`ensure_indexed` 回填） | Rust `store::tests::v3_to_v4_migration_idempotent_and_preserves_data`（v3→v4 幂等、存量零丢失、`user_version==4`）、`store::tests::open_migrate_insert_list_roundtrip`、`store::search_index::tests::replace_book_is_idempotent_and_is_indexed`、`tests/notes_search_api.rs`（旧书首次搜索可搜）；`docs/04 §5` 已同步 v4 DDL | ✅ |
| **US-24** | Android 真机验收清单 ①–⑧ | —（真机） | `01-req §2` US-24；`03-review §6`；T-026 | APK `dist/reader-android-arm64-v0.9.0.apk`（§5/§6） | 清单见 `01-req.md US-24` / `03-review.md §6`（CI 不可自动化）；已用 APK `aapt2`/`unzip` 版本/权限/ABI/资产校验 + 集成/widget/FFI 全绿兜底 | ✅\* 真机 ①–⑧ |

**闭合统计**：US-1..US-24 共 **24 条** → **✅ 22 条 + ✅\* 2 条（US-17 移动端路径终验、US-24 真机 ①–⑧）= 24/24 全部闭合；孤儿需求 = 0**。
（US-4/US-21 的自动化证据已闭合，其「换字号/主题人工终验」「真机性能」分别并入 US-24⑦/⑥，不重复计为独立未闭合项。）

### 4.1 核心「选词→高亮→面板→跳回」端到端证据链（US-1/6/8/10）

`composeSpans` 纯函数（`note_span_policy_test.dart` 18 例 + `note_colors_test.dart` 6 例）
→ `locator` 文本锚（`locator::tests` 14 例：归一化/消歧/降级/UTF-16）
→ `reader_page.dart:1295` 按 href 分组注入 `ChapterSection(annotations:)` → `continuous_scroll_policy.dart:225` `composeSpans` 分段
→ 真实集成 `integration_test/notes_search_integration_test.dart`「US-10」（真实 `longPress`→选色→面板出现→点击→`Key('temp-highlight')`，`takeException()==null`）
→ 真实渲染截图 `app/screenshots/{selection_toolbar_colors,notes_panel,notes_jump_temp_highlight}.png`（`05b §1` S1/S2/S4 像素/几何判定通过）
→ 真机 US-24①②。

### 4.2 核心「搜索→结果→定位」端到端证据链（US-18/19/20/22）

`bigram_index_text`/`build_match_expr`/`extract_snippet` 纯函数（`search::tests` 10 例）
→ FTS5 真实引擎 `tests/notes_search.rs`（2 字 CJK 命中，≤100ms）+ `store/search_index` scope/格式过滤
→ `api.rs::search` 回填真实 `chapter_index`（rework-B D1，`tests/notes_search_api.rs`）
→ `search_page.dart` 渲染（`search_page_test.dart` 12 例，含跨书真实章号反例）
→ 真实集成 `integration_test/notes_search_integration_test.dart`「US-22」（输入→结果「第 2 章 · 第二章」→定位→`temp-highlight`）
→ 真实渲染截图 `app/screenshots/search_page.png`（`05b §1` S3 判定通过）
→ 真机 US-24⑥。

---

## 5. 发布产物清单

| 项 | 内容 | 状态 |
|---|---|---|
| **版本号** | `0.9.0+14`（`app/pubspec.yaml`）；`core/Cargo.toml` 保持 `0.1.0` | ✅ |
| **源码** | 分支 `wf/REQ-009-notes-search`；`3b8af1d`（feat）、`5c5cf8d`（test）、`40c2260`（产品验收首轮）、`1c95920`（rework-B 修复）、`975b14a`（5a 复验）、本交付提交 | ✅ |
| **Android APK** | `dist/reader-android-arm64-v0.9.0.apk`，**49,619,805 B（47.3 MiB）**；`versionName=0.9.0 / versionCode=14`；`dist/` 已 gitignore，仅登记路径不入库 | ✅ 已构建 |
| **质量报告** | `04-mutation.md`（变异 96.81%，存活 12/12 有结论）；`04-coverage.md`（Dart 99.54% / Rust 99.06%）；`03-review.md`（DDD=0）；`workflow/reports/ddd-req009-delivery.md` | ✅ |
| **产品验收** | `05b-product-preview.md` + `product-preview.manifest.json` + `product-preview-REQ-009-notes-search.html` + `app/screenshots/*.png`（4 张 REQ-009 真实渲染） | ✅ |
| **rework** | `workflow/rework/REWORK-REQ-009-B.md`（gate=passed，D1 闭环） | ✅ |

### 5.1 APK 产物独立校验（`aapt2` build-tools 36.0.0 / `unzip` / `sha256sum`）

| 校验项 | 期望 | 实测 | 结论 |
|---|---|---|---|
| 文件路径 | `dist/reader-android-arm64-v0.9.0.apk` | 存在 | ✅ |
| 大小 | — | `49,619,805 B`（47.3 MiB） | ✅ |
| SHA-256 | — | `26d783ba9d148de973e6c12e00caff61add3d227a94d257368746b3b163a965a` | 记录 |
| versionName | `0.9.0` | `versionName='0.9.0'` | ✅ |
| versionCode | `14` | `versionCode='14'` | ✅ |
| 包名 / SDK | `com.reader.reader_app` | `name='com.reader.reader_app'`，minSdk 24 / targetSdk 36 / compileSdk 36 | ✅ |
| INTERNET 权限 | 含 | `uses-permission: android.permission.INTERNET` | ✅ |
| TTS_SERVICE 可见性 | 含 | `<queries>` 含 `android.intent.action.TTS_SERVICE` | ✅ |
| PROCESS_TEXT 可见性 | 含 | `<queries>` 含 `android.intent.action.PROCESS_TEXT` | ✅ |
| launchable-activity | `MainActivity` | `com.reader.reader_app.MainActivity` | ✅ |
| ABI（native-code） | 3 ABI | `arm64-v8a` `armeabi-v7a` `x86_64` | ✅ |
| `libreader_core.so` | 3 ABI | arm64-v8a `7,481,816 B` / armeabi-v7a `5,388,460 B` / x86_64 `8,071,264 B` | ✅ |
| 词典资产 | `langdao-ec` | `assets/flutter_assets/assets/dict/langdao-ec/{*.dict.dz,*.idx,*.ifo}` | ✅ |

> **确由本 REQ 代码重新构建（非旧产物改名）**：v0.9.0 与 v0.8.0 的 `libapp.so` / `AndroidManifest.xml` /
> `lib/arm64-v8a/libreader_core.so` SHA-256 均不同（实测三对哈希全部变化），且 versionCode 由 13→14。

---

## 6. Android APK 构建记录

- 命令：`bash scripts/build-android-local.sh`（日志 `/tmp/opencode/req009-build-android.log`）。
  本机适配：JDK21 `/usr/lib/jvm/java-21-openjdk-amd64`、Android SDK `/root/android-sdk`、NDK `28.2.13676358`。
- 流程：Rust 交叉编译 3 ABI → 拷入 `app/android/app/src/main/jniLibs/` →
  `flutter build apk --release --target-platform android-arm64` → 归档 `dist/reader-android-arm64-v${VER}.apk`。
- 结果：**✓ 成功**
  - Rust 三目标 `aarch64 / armv7 / x86_64-linux-android` 全部 `Finished release`（27.97s / 24.32s / 22.73s）。
  - Gradle `assembleRelease` 成功（142.5s），`app-release.apk (49.6MB)`。
  - 归档：`/root/reader/dist/reader-android-arm64-v0.9.0.apk`（49,619,805 B）。
- 构建噪声：`flutter_tts` KGP 弃用警告（未来兼容性提示，非失败）；jniLibs 中间物因构建重生成，
  按发布惯例回退不入库（见 §3 #6）。

---

## 7. 闸门5 自评

- [x] **追溯矩阵全闭合**：US-1..US-24 = **24/24**（✅ 22 + ✅\* 2），**孤儿需求 = 0**；每条均有
      原型图/设计章节/实现文件/具体测试名证据；核心端到端证据链见 §4.1/§4.2。
      US-10（选词→高亮→面板→跳回）与 US-22（搜索→结果→跳转）真实集成 **2/2** 通过；US-23 v4 迁移/回填单测通过；
      rework-B D1 已闭环（`REWORK-REQ-009-B.md` gate=passed）。
- [x] **全量回归绿**：cargo **282 passed / 0 failed**；flutter **288 passed / 5 skipped / 0 failed**；
      `flutter analyze` **0 issues**；DDD **违规=0**；FFI 端到端（真实 `.so`）**2 passed / 0 failed**；
      真实集成逐文件 **2 + 5 + 5 + 17 = 29 passed / 0 failed**；变异 **96.81%**（存活 12/12 有结论）；
      新代码覆盖 Dart **99.54%** / Rust **99.06%**（均 ≥85%）。
- [x] **发布产物齐全**：版本 `0.9.0+14`；APK `dist/reader-android-arm64-v0.9.0.apk`
      （49,619,805 B；`versionName=0.9.0`/`versionCode=14`；INTERNET + TTS_SERVICE + PROCESS_TEXT；
      3 ABI `libreader_core.so` + 词典资产，独立 `aapt2`/`unzip` 校验通过）；覆盖率/变异/产品验收/rework 报告齐全。

**结论：闸门5 passed。**

---

## 8. 合并建议与交接

- **建议合并** `wf/REQ-009-notes-search` → `main`（普通合并，**本代理不自行合并、不 force-push、不改 STATE.md**）。
- **前置**：等待 orchestrator / 用户确认。
- **真机交接**：`01-req.md US-24` / `03-review.md §6` 的 8 项 Android 手工清单需在真机执行后方可对外发布；
  重点确认 ① 多色高亮/划线/批注持久化、② 面板跳回临时高亮、③ 删除后原文标记清理、⑤ 导出移动端路径、
  ⑥ 全文搜索定位、⑦ 换字号/主题后高亮不丢、⑧ 既有能力零回退。
- 合并提交信息建议：`chore(release): REQ-009 v0.9.0 笔记+全文搜索`。

---

## 9. 本阶段产物

| 文件 | 变更 |
|---|---|
| `app/pubspec.yaml` | `0.8.0+13` → `0.9.0+14`（本交付提交） |
| `workflow/backlog/REQ-009-notes-search/05-delivery.md` | 新增（本文件，带 wf-meta 头） |
| `dist/reader-android-arm64-v0.9.0.apk` | 本地构建产物（`dist/` gitignored，不入库，见 §5/§6） |
| `workflow/reports/ddd-req009-delivery.md` | DDD 复跑报告（违规=0，交付阶段） |
| `app/android/app/src/main/jniLibs/**`、`app/build/**` | 构建中间物（jniLibs 已回退，不入库） |
