<!-- wf-meta: req=REQ-009-notes-search | phase=development | agent=developer | date=2026-09-09 | gate=passed -->
# REQ-009 · 阶段3 开发审查（03-review）

> 分支 `wf/REQ-009-notes-search`（基于 main `5f220f9`）。产物：代码 + 本文件 + `docs/03 §4`/`docs/04 §3/§5/§7` 同步。
> 依据：`02-plan.md` T-001..T-025（T-026 真机不在本环境，遗留登记）；`02-adr.md` D1–D12；`02-design.md` 接口/DDL/逐屏映射。

## 0. 结论

- **闸门3：pass**（CRAP FAIL=0；DDD 违规=0；cargo/flutter 全绿；无未处理 rework；原型 deviation=0）。
- **CJK 硬需求实测**：`search("城市")`=1、`search("卡尔维诺")`=1、`search("记忆")`=1（真实 FTS5，158.958µs / 80.551µs / 65.015µs）。
- **真实集成测试**：`notes_search_integration_test.dart` 2/2（US-10、US-22）逐文件 xvfb 通过。
- **遗留**：T-026 Android 真机 8 项人工验收无法在本环境执行，如实登记（未假装跑过）。

## 1. 前置审查

### 1.1 与 `docs/03`、`docs/04` 既有约定

| 检查项 | 结论 |
|---|---|
| `docs/04 §5` 的 `annotations` DDL（155–167） | 逐列一致（id/book_id/kind/color/locator_json/snippet/note_text/created_at/updated_at/sync_status + idx_annot_book）；v4 迁移新增 |
| `docs/04 §5` 的 `fts_books` DDL | 原为 `fts5(book_id UNINDEXED, chapter, text)` 无 href；按 ADR D1/D4 扩列为 `book_id/href/chapter/text UNINDEXED + text_bi + unicode61`，**复用虚拟表不新建表**，已同步 `docs/04 §5` |
| `reading_progress` 唯一事实源 | 不破坏：笔记只写 `annotations`；面板/搜索跳转复用 `_changeChapter`→`ProgressSaver.flush` 更新进度（US-8/19） |
| Locator 章内 progression / UTF-16 | 不破坏：`from_selection` 输出 `progression∈[0,1]`，`TextAnchor.start/end` 用 UTF-16 半开区间（与 REQ-005 同尺度） |
| TTS 句↔Locator | 零改动：`tts::*` 签名/语义不变；`api.rs` 新增函数不触碰 TTS 段 |
| ddd-rules（domain 禁 `crate::store`） | 合规：契约在 `types.rs`，实现在 `store/{annotations,search_index}.rs`，`notes/search/locator` 只依赖 trait；`api.rs`（interface）装配 |
| `ChapterData`/`ChapterSection` 既有调用 | 不破坏：`href` 默认 `''`、`annotations=const[]`、`tempHighlight=null`，REQ-008 调用零改动 |

### 1.2 计划问题

- 无任务缺失、无依赖环（拓扑序 T-001→…→T-026 与实现一致）；估算无离谱。
- T-026（Android 真机）依赖真机，本环境无法执行 → 遗留登记，不构成 rework-A。

### 1.3 验收可测性

US-1..24 均可断言：cargo 单测（US-4/5/12/15/16/18/20/21/23）、widget 测试（US-6/7/9/11/13/17）、真实集成（US-10/22）、真机（US-24）。无不可测措辞。→ 无 rework-C。

### 1.4 原型逐屏对照（前置）

| 屏 | 线框 | 前置结论 |
|---|---|---|
| 选词工具条 | `06-selection-toolbar.svg` | 实现 6 入口 `复制/高亮(4色)/划线/批注/翻译/查词`，顺序与线框一致，查词为 01-req §1.5 明确保留 |
| 笔记面板 | `07-annotation-panel.svg` | 右侧 360px 覆盖层/标题✕/搜索笔记/章节分组/色标/片段/批注/MM-dd/底部导出·全部删除/编辑卡片/点外关闭/多选 |
| 全文搜索 | `04-search.svg` | 搜索框+全文搜索按钮/书名粗/第 N 章·章节名/关键词蓝加粗/定位/右侧筛选（范围+格式）/结果 N 条·X.XXs/空态 |
| 阅读器入口 | `02-menus.svg:31-32`、`05-reader.svg:15` | 底栏书签复用；「⋯更多」增搜索、笔记/导出接真实动作；**未新增顶栏图标、未改顶/底栏结构** |

无自创布局。详见 §4。

### 1.5 回归面（已并入 T-024 并执行）

`reader_selection_test.dart`（工具条文案）、`reader_page_test.dart`（书签/工具条）、`translate_reader_test.dart`（工具条文案）、`reader_continuous_scroll_test.dart`（书签）、`screenshot_golden_test.dart`（工具条 golden 重跑）、`screenshots_test.dart`（截图重跑）、`no_synthetic_chrome_test.dart`（守卫绿）。

## 2. T-001..T-025 逐项

| Task | 状态 | 证据 |
|---|---|---|
| T-001 types 契约/值对象 | ✅ | `types.rs`：`NoteKind::parse/as_str` 往返、`TextRange` serde 单测；`AnnotationRepository`/`SearchIndexRepository` trait |
| T-002 v4 迁移 + remove_book + busy_timeout | ✅ | `store/mod.rs` `if version<4`；`v3_to_v4_migration_idempotent_and_preserves_data`；`remove_book` 事务删 fts；主连接 busy_timeout=5000 |
| T-003 `store/annotations.rs` | ✅ | 第二连接 FK ON+busy_timeout；insert/get/update/delete/delete_many/delete_all/list/find_bookmark 往返 + 删书级联 + 幂等删除 |
| T-004 `store/search_index.rs` | ✅ | replace_book 幂等、query_fts JOIN+scope+format 过滤、query_substring LIKE 回退、特殊字符安全 |
| T-005 `locator` from_selection/text_at | ✅ | 唯一/重复片段消歧、无匹配降级、UTF-16 与 Dart substring 同尺度（含 emoji） |
| T-006 `notes` AnnotationService | ✅ | CRUD/分组/导出/书签幂等；空 note_text 不落库；Markdown/JSON 转义与字段完整 |
| T-007 `search` bigram/expr/snippet/service | ✅ | `bigram_index_text`/`build_match_expr`/`extract_snippet` 单测；空/特殊字符短路；单字 CJK LIKE |
| T-008 notes DTO + 9 async 桥接 + NOTES 单例 | ✅ | `api.rs`；`library_open` 装配 |
| T-009 search DTO + search 桥接 + SEARCH + 懒回填 | ✅ | `search` 空查询短路；`books_in_scope`+`ensure_indexed` |
| T-010 导入即索引 + `ChapterView.href` | ✅ | `library_import` 后 `ensure_indexed`；`book_open` 填 href |
| T-011 FRB codegen + 检查 | ✅ | `flutter_rust_bridge_codegen generate`；生成物未手改；`flutter analyze` 0 |
| T-012 Dart notes_backend + rust_notes_backend | ✅ | DTO 一一对应；`fake_notes_backend.dart` 可注入 |
| T-013 Dart search_backend + rust_search_backend | ✅ | `SearchHitData`/`SearchScopeData` |
| T-014 `ChapterData.href` 默认 `''` | ✅ | `rust_library_backend` 映射；既有 fake 不破 |
| T-015 selection_toolbar 6 入口 + 4 色 | ✅ | `NoteColors` 单一色源；`reader_page_test` 断言四色 key |
| T-016 note_span_policy + ChapterSection | ✅ | `composeSpans` 单测（多色/重叠/划线/批注/临时）；新参数可选 |
| T-017 选区动作接线 | ✅ | highlight 选色/underline/note 落库；translate/lookup/copy 不变 |
| T-018 加载渲染 + `_jumpTo` 临时高亮 | ✅ | 按 href 归组渲染；`Key('temp-highlight')`；超时/滚动/点击清除；复用 `_changeChapter` 更新进度 |
| T-019 notes_panel + note_editor_card + notes_page | ✅ | 分组/色标/片段/批注/时间/空态/搜索过滤/编辑改色/多选/二次确认/点外关闭 |
| T-020 面板入口 + 书签持久化 | ✅ | `_openMore` 笔记项；`_toggleBookmark`+`notes_list` 状态；书签行跳转 |
| T-021 search_page 线框 04 | ✅ | 结果行/关键词蓝加粗/定位/范围+格式/结果数耗时/空态；`Navigator.pop` 返回命中 |
| T-022 export_path_picker + 导出流程 | ✅ | 桌面保存框取消不写；移动应用目录；空笔记提示「暂无笔记」 |
| T-023 真实集成测试 | ✅ | `notes_search_integration_test.dart` US-10/US-22，真实 longPress/点击/面板/导航 |
| T-024 既有测试/golden 同步 | ✅ | 见 §3.2/§3.5；golden 变更已记录 |
| T-025 docs 同步 + 静态/构建闸门 | ✅ | `docs/03 §4`、`docs/04 §3/§5/§7`；ddd 违规=0；cargo/analyze 绿 |

## 3. 测试结果

### 3.1 cargo（`cd core && CARGO_BUILD_JOBS=2 cargo test --release`）

| 目标 | 结果 |
|---|---|
| lib（含新增 notes/search/locator/store 单测） | **219 passed / 0 failed** |
| `tests/mobi_azw3.rs` | 21 / 0 |
| `tests/notes_search.rs`（新增，CJK+笔记+导出端到端） | **3 / 0** |
| `tests/p0_corpus.rs` | 5 / 0 |
| `tests/translate_corpus.rs` | 8 / 0 |
| `tests/tts_api.rs` | 3 / 0 |
| `tests/integration.rs` | 0 / 0 |
| **合计** | **259 passed / 0 failed** |

### 3.2 flutter test（`cd app && flutter test`）

**198 passed / 4 skipped / 0 failed**（含更新后的 `reader_selection_test`/`reader_page_test`/`translate_reader_test`/`reader_continuous_scroll_test`/`screenshot_golden_test`/`no_synthetic_chrome_test`）。

### 3.3 flutter analyze

**No issues found!**（0 issues；含生成物）。

### 3.4 ddd-lint

`scripts/ddd-lint/... check /root/reader --rules workflow/rules/ddd-rules.toml --out workflow/reports/ddd-req009.md` → **违规=0**。

### 3.5 集成测试（逐文件 `xvfb-run -a flutter test <file> -d linux`）

| 文件 | 结果 | 覆盖 |
|---|---|---|
| `integration_test/notes_search_integration_test.dart`（新增） | **2/2** | US-10 选词→高亮→面板→跳回临时高亮；US-22 搜索→结果→定位→临时高亮 |
| `integration_test/reader_continuous_scroll_test.dart` | **5/5** | REQ-008 回归（US-1/2/3/4/8） |
| `integration_test/reader_interaction_test.dart` | **5/5** | REQ-007 回归（US-1/2/4/12） |
| `integration_test/screenshots_test.dart` | **13/13** | 真实截图（含更多菜单、翻译卡、听书） |

> 目录级运行在本环境首个文件后报 `Unable to start the app`（与代码无关，REQ-008 已知），按逐文件运行全部通过。`no_synthetic_chrome_test.dart` 绿（新文件不含 `ReaderTopBar(`/`ReaderBottomBar(`）。

### 3.6 CRAP（`workflow/reports/crap-req009.md`）

- **FAIL=0，WARN=9，PASS=310**。
- WARN 全部为**既有代码**（`convert/mod.rs canonicalize`、`format/epub.rs parse_*`、`dict/translation.rs translate_*`、`types.rs Lang::as_str/parse`）；**新增代码 WARN=0**（`store/search_index.rs` 抽出 `run_rows` 消除重复惩罚后 PASS）。WARN 数 ≤ 新增行 1%。

### 3.7 CJK 搜索实测（`cargo test --release --test notes_search -- --nocapture`）

真实 SQLite/FTS5 语料 `"看不见的城市，卡尔维诺写道：城市是记忆的。他还说，每一座城市都藏着记忆。"`：

| 查询 | 命中 | 耗时 |
|---|---|---|
| `城市`（2 字） | **1** | 158.958µs |
| `卡尔维诺`（4 字） | **1** | 80.551µs |
| `记忆`（2 字） | **1** | 65.015µs |
| `城`（单字 CJK） | ≥1（LIKE 回退） | — |
| `""`/纯空白/`%`/`_`/`"`/`*`/`NEAR` | 安全（空/不抛异常） | — |

全部 ≤100ms（ADR D1 门槛）。

## 4. 原型一致性（deviation=0）

| 线框 | 逐项核对 | 判定 |
|---|---|---|
| `06-selection-toolbar.svg` | 复制/高亮/划线/批注/翻译 + 保留查词；高亮 4 色取自 `NoteColors`（`#FBC02D/#1A73E8/#43A047/#E91E63`）；工具条随选区定位（既有 `_toolbarTop`） | ✅ |
| `07-annotation-panel.svg` | 右侧覆盖层、标题「笔记」+✕、搜索框「搜索笔记」、章节分组头、4px 色标竖条、原文片段单行省略、批注、时间 `MM-dd`、底部「导出 / 全部删除」、编辑批注卡片（输入框+删除+保存）、主体调暗+点外关闭、多选批量删除；书签行 🔖 无色标 | ✅ |
| `04-search.svg` | 顶部搜索框+放大镜+「全文搜索」按钮；结果行书名粗 +「第 N 章 · 章节名」+ 关键词蓝色加粗 +「定位」；右侧「筛选」面板：按范围（全部/当前书籍）、按格式（EPUB/PDF/MOBI 复选）、「结果 N 条 · X.XXs」；空态 | ✅ |
| `02-menus.svg:31-32`/`05-reader.svg:15` | 底栏 🔖 复用；「⋯更多」增搜索，笔记/导出接真实动作；零顶/底栏布局改版 | ✅ |

**已授权取舍（非偏差，02-design/ADR 降级线）**：面板宽度 `min(360, 屏宽*0.9)`（D7 降级线）；高亮四色在点「高亮」后展开（design §6.1「展开 4 色选色」）；书签行渲染变体（C11）；临时高亮 key 落在 `Text.rich` 组件（Flutter `TextSpan` 无 key，断言等价）。

## 5. 与计划的偏差处置（均非 rework）

1. **`library_import` 保持既有同步签名**：内部新增 `ensure_indexed`（导入即索引，US-21）。FRB Dart 侧仍返回 `Future`，调用面零改动（回归最小）；未改为 `async fn` 属签名稳定性取舍。
2. **`notes_page.dart` 薄壳**：plan 允许「薄壳转 NotesPanel 或删除，保持可达」，实现为薄壳。
3. **跨书搜索定位**：design §4.3 提到经 LibraryPage/路由；实现为 `ReaderPage._openHit` push 新 `ReaderPage(initialTarget:)`，语义等价（US-19），且不新增入口。
4. **搜索命中区间映射**：`SearchHit.ranges` 相对 `snippet`；`_openHit` 先 `indexOf(snippet)` 平移到章文本偏移再设临时高亮（design §4.3「解析 snippet 在本章的区间」）。
5. **golden/截图**：`reader_selected.png`（工具条）与 `reader_more.png`（更多菜单增搜索）重跑更新并随提交记录。

## 6. 遗留问题

1. **T-026 Android 真机验收（US-24 ①–⑧）**：本环境无 Android 设备，**未执行**；APK 构建与人工清单留待交付阶段/真机执行。
2. `docs/04 §5` 的 `vocabulary` 表本期不建（沿用既有约定）；`fts_books` 已按 v4 扩列。
3. 既有告警 `core/src/tts/mod.rs:572 unused variable text`（REQ-005 遗留，非本 REQ 引入）。
4. 本阶段未跑 `scripts/ui-screenshots.sh REQ-009` / 产品预览（属阶段 5a）。
