<!-- wf-meta: req=REQ-009-notes-search | phase=architecture | agent=architect | date=2026-09-09 | gate=passed -->
# REQ-009 · 计划拆分（Task 分解）

> 依赖无环（见 §2）。每任务 ≤1 天、验收可断言并映射 US。DDL/契约变更由 T-025 同步 `docs/03 §4`/`docs/04 §5`。

## 1. 任务清单

| Task | 内容 | 依赖 | 估算 | 验收（映射 US） |
|---|---|---|---|---|
| T-001 | `core/src/types.rs` 契约与值对象：`NoteKind`/`TextSelection`/`Annotation`/`NotePatch`/`ExportFormat`/`ExportSummary`/`NoteGroup`/`GroupBy`/`TextRange`/`SearchHit`/`SearchScope`/`IndexedChapter`/`SearchRow` + `AnnotationRepository`/`SearchIndexRepository` trait（签名见 02-design §2.1） | — | 1d | `cargo test -p reader_core` 编译；`NoteKind::parse/as_str` 往返单测；`serde` 序列化 `TextRange` 单测（US-1/18/23 前置） |
| T-002 | v4 迁移：`migrate_conn` 增 `if version<4`（`annotations` + `idx_annot_book` + `fts_books` 新列，DDL 见 02-design §3.1）；`remove_book` 事务内 `DELETE FROM fts_books WHERE book_id=?` + 删书；主连接补 `PRAGMA busy_timeout=5000` | T-001 | 1d | v3→v4 迁移幂等（重复开 no-op）、存量数据零丢失、`user_version==4`、删书后 `fts_books` 无残留行、`PRAGMA foreign_keys` 级联删 annotations（US-15/23） |
| T-003 | `core/src/store/annotations.rs`：`AnnotationRepo` 实现 `AnnotationRepository`（第二连接 WAL + `busy_timeout=5000` + `foreign_keys=ON` + `migrate_conn`）；`locator_json` serde；`find_bookmark` 按 `(book_id,href,round(progression,3))` | T-002 | 1d | insert/get/update/delete/delete_many/delete_all/list 往返；`updated_at` 递增；删书级联后 `list` 为空；非法 id 幂等不崩溃（US-1/12/15） |
| T-004 | `core/src/store/search_index.rs`：`SearchIndexRepo` 实现 `SearchIndexRepository`；`replace_book` 事务先删后插；`is_indexed`；`query` JOIN books（scope 书/格式过滤 + `ORDER BY rank LIMIT`）；单字 CJK LIKE 回退 | T-002 | 1d | `replace_book` 幂等（重复索引不翻倍）；`query` 命中 2 字 CJK；`is_indexed` 真/假；格式过滤只返回所选格式；特殊字符不抛异常（US-18/20/21/23） |
| T-005 | `core/src/locator/mod.rs`：实现 `from_selection`（归一化匹配 + UTF-16 偏移映射 + progression 消歧 + 降级链）与 `text_at` | T-001 | 1d | 唯一 snippet 命中正确 start/end；同 snippet 多处按 progression 消歧；无匹配 → `text=None` + progression；UTF-16 偏移与 Dart `substring` 一致（US-4/5） |
| T-006 | `core/src/notes/mod.rs`：实现 `AnnotationService`（create/update/delete/delete_many/delete_all/list 分组/resolve/export/toggle_bookmark）；`chapter_titles` 由调用方注入 | T-001, T-003 | 1d | CRUD 往返；`list` 按章节分组且顺序稳定（`updated_at` 倒序）；空 `note_text` 的 note 不落库；导出 Markdown/JSON 字段完整 + 转义；toggle 幂等（US-1/2/3/6/11/12/13/14/16） |
| T-007 | `core/src/search/mod.rs`：`bigram_index_text`/`build_match_expr`/`extract_snippet` 纯函数 + `SearchService`（index_book/is_indexed/query） | T-001, T-004 | 1d | `bigram_index_text("城市")`→`"城市"`；2 字中文词命中；空查询 `build_match_expr`→`None`；`% _ " * NEAR` 安全；snippet `ranges` 指向关键词；1000 章查询 ≤100ms（实测打印）（US-18/20/21） |
| T-008 | `core/src/api.rs`：新增 notes DTO（`TextSelectionView`/`AnnotationView`/`NoteGroupView`/`NotePatchView`/`BookmarkToggleView`/`ExportSummaryView`）+ 9 个 notes async 桥接 + `NOTES` 单例装配（`library_open`） | T-003, T-005, T-006 | 1d | `library_open` 后可调 `notes_create/list/update/delete/toggle/export`；`notes_create` 返回的 `start/end/snippet` 可断言；`notes_list` 分组含章节名（US-1/2/3/6/11/14/16） |
| T-009 | `core/src/api.rs`：search DTO（`RangeView`/`SearchHitView`/`SearchScopeView`）+ `search` async 桥接 + `SEARCH` 单例 + `ensure_indexed` 懒回填 + 空查询短路 | T-004, T-007 | 1d | `search("城市")` ≥1 命中且字段齐全；scope 当前书/全部书正确；旧书首次搜索后可搜（回填）；空查询返回 `[]`（US-18/19/20/21/23） |
| T-010 | 导入即索引：`library_import` 成功后 `ensure_indexed`；`ChapterView` 增 `href` 并 `book_open` 填充 | T-009 | 0.5d | 导入新书后立即可搜（US-21）；`book_open` 返回每章 `href` 非空（US-18/19/23） |
| T-011 | FRB codegen：`flutter_rust_bridge_codegen generate --rust-input crate::api --rust-root core/ --dart-output app/lib/src/rust/`；检查 diff 干净；补 `rust_bridge_test.dart` 类 FFI 往返 | T-008, T-009, T-010 | 1d | 生成物含 10 个新函数与 9 个 DTO；`flutter analyze` 0 issues；FFI 往返（notes 创建/查询/搜索）通过；**生成物未手改**（US-1/18） |
| T-012 | Dart `services/notes_backend.dart`（抽象 + DTO）+ `services/rust_notes_backend.dart`（生成物→DTO） | T-011 | 1d | 抽象方法齐全；fake 可注入；Rust 实现映射字段一一对应（US-1/6/11/14/16） |
| T-013 | Dart `services/search_backend.dart` + `services/rust_search_backend.dart` | T-011 | 0.5d | `search(query, scope)` 返回 `SearchHitData`（含 `ranges`）；scope 映射正确（US-18/20） |
| T-014 | `services/library_backend.dart` `ChapterData` 增 `href`（默认 `''`）+ `rust_library_backend.dart` 映射 + `fake_backend.dart` 兼容 | T-011 | 0.5d | 生产 `ChapterData.href` 非空；既有 fake 不破；`flutter test` 全绿（US-18/19） |
| T-015 | `widgets/selection_toolbar.dart`：动作改 `复制/高亮(4 色)/划线/批注/翻译/查词`；新增 `SelectionAction.underline`；高亮选色子交互；`NoteColors` 单一色源 | — | 1d | 6 个入口可见；点高亮弹出 4 色；点划线/批注回调对应 action；颜色取自 `NoteColors`（US-1/2/3，线框 06） |
| T-016 | `pages/note_span_policy.dart`：`composeSpans` 纯函数（多色/重叠/划线/批注/临时优先级）；`ChapterSection` 改 `Text.rich`（新参数可选） | T-012 | 1d | 单测：单色/多色/重叠原子分段、划线 decoration、临时高亮 `isTemporary`；既有 `ChapterSection` 调用不破（US-1/2/4/5/8） |
| T-017 | `reader_page.dart` 选区动作接线：`highlight`（选色）/`underline`/`note`（编辑卡片）→ `NotesBackend.create`；保留 translate/lookup/copy | T-012, T-014, T-015, T-016 | 1d | 长按选中→高亮/划线/批注各落库一条；空批注不落库；translate/lookup/copy 语义不变（US-1/2/3） |
| T-018 | `reader_page.dart`：加载本书笔记并按 href 分组渲染持久化高亮；`_jumpTo` + 临时高亮（Key `temp-highlight`）+ 超时/滚动清除；复用 `_changeChapter` 更新进度 | T-016, T-017 | 1d | 重开/换字号后带色 span 文本 == snippet；点面板条目跳转并出现临时高亮，超时消失而持久高亮仍在；`reading_progress` 更新（US-4/5/8） |
| T-019 | `widgets/notes_panel.dart` + `widgets/note_editor_card.dart`：线框 07 面板（标题/搜索/章节分组/色标/片段/批注/时间/底部导出·全部删除/多选/二次确认/点外关闭）；`pages/notes_page.dart` 薄壳接入 | T-012 | 1d | 分组/色标/时间/空态；面板内搜索过滤；编辑/改色/删除；多选批量删除 + 二次确认；未选禁用；点外关闭（US-6/7/9/11/12/13，线框 07） |
| T-020 | `reader_page.dart` 面板入口（`_openMore` 笔记项）+ 书签持久化（`toggleBookmark` + 图标状态来自 `notes_list`）+ 书签行跳转 | T-012, T-018, T-019 | 1d | 更多→笔记打开面板；书签落库/取消幂等；重开图标状态正确；书签行点击跳转（US-9/14） |
| T-021 | `pages/search_page.dart`：线框 04（搜索框+按钮/结果行/关键词高亮/定位/右侧筛选范围+格式/结果数耗时/空态）；返回 `SearchHitData` 给 ReaderPage 定位 | T-013, T-014 | 1d | 结果行含书名/章节/上下文；关键词 span 蓝色加粗；scope/格式过滤；空态；点定位返回命中（US-18/19/20，线框 04） |
| T-022 | `services/export_path_picker.dart`（桌面 `file_picker` / 移动 `path_provider`）+ 面板导出流程 + 空笔记提示 | T-012 | 1d | 桌面取消不写文件；移动写应用目录；空笔记提示「暂无笔记」不建文件；导出内容字段完整（US-16/17） |
| T-023 | `app/integration_test/notes_search_integration_test.dart`：真实 `ReaderPage`/`SearchPage` + 真实 `longPress`/点击/面板/导航，注入 `FakeNotesBackend`/`FakeSearchBackend`；不构造合成 Chrome | T-017, T-018, T-020, T-021, T-022 | 1d | US-10 选词→高亮→面板→跳回；US-22 搜索→结果→定位→临时高亮；`takeException()==null`；`no_synthetic_chrome_test.dart` 绿（US-10/22） |
| T-024 | 既有测试/golden 同步：`reader_selection_test.dart`（工具条文案）、`reader_page_test.dart`（划重点/笔记→高亮/划线/批注）、`screenshot_golden_test.dart`/`screenshots_test.dart` golden 重跑更新、`continuous_scroll_policy_test.dart` 兼容 | T-023 | 1d | `flutter test` 全绿；golden diff 已记录并更新；`flutter test integration_test -d linux` 全绿（全 US 回归） |
| T-025 | 文档同步 + 静态/构建闸门：`docs/03 §4` 新增桥接面、`docs/04 §5` v4 DDL + `fts_books` 新列、`docs/04 §3/§7` 签名；`scripts/ddd-lint` 违规 0；`cargo test --release`、`flutter analyze` 0 issues | T-024 | 1d | docs 与代码一致；ddd-lint 违规 0；三命令全绿（闸门3 前置） |
| T-026 | Android 真机验收：`bash scripts/build-android-local.sh` 出 APK；按 US-24 八项人工清单逐项记录 | T-025 | 1d | APK 产出；US-24 ①–⑧ 全通过并留痕（US-24） |

## 2. 依赖图（无环）

```
T-001 ──┬─▶ T-002 ──┬─▶ T-003 ──┐
        │           └─▶ T-004 ──┼──────────────┐
        ├─▶ T-005 ──────────────┼──▶ T-008 ────┤
        └─▶ T-006(需 T-003)     │              │
                                └─▶ T-007 ──▶ T-009 ──▶ T-010
                                                       │
T-008, T-009, T-010 ──────────────────────────────────┴─▶ T-011
                                                              │
        ┌─────────────────────────────────────────────────────┤
        ▼                                                     ▼
T-012 ──┬─▶ T-016 ──┐                                 T-013 ──▶ T-021
        ├─▶ T-019 ──┼─▶ T-017 ──▶ T-018 ──▶ T-020 ─┐
        └─▶ T-022   │                              │
T-014 ──▶ T-017     │                              │
T-015 ──▶ T-017     └──────────────────────────────┼─▶ T-023 ──▶ T-024 ──▶ T-025 ──▶ T-026
T-013 ──▶ T-021 ───────────────────────────────────┘
```

拓扑序（线性化，供并行编排）：
`T-001 → T-002 → {T-003, T-004, T-005} → T-006 → T-007 → T-008 → T-009 → T-010 → T-011 → {T-012, T-013, T-014} → {T-015, T-016, T-019, T-022} → T-017 → T-018 → T-020 → T-021 → T-023 → T-024 → T-025 → T-026`

- 无环：所有依赖边方向一致（序号递增方向），无回边。
- 并行机会：T-003/T-004/T-005 可并行；T-012/T-013/T-014 可并行；T-015/T-016/T-019/T-022 可并行。

## 3. 验收 → US 映射（闭合检查）

| US | 覆盖任务 |
|---|---|
| US-1 多色高亮 | T-001/T-003/T-005/T-006/T-008/T-012/T-015/T-016/T-017/T-018/T-023 |
| US-2 划线 | T-006/T-015/T-017 |
| US-3 批注 | T-006/T-015/T-017 |
| US-4 重排重定位 | T-005/T-016/T-018 |
| US-5 重叠多色 | T-005/T-016/T-018 |
| US-6 面板分组 | T-006/T-012/T-019 |
| US-7 面板搜索 | T-019 |
| US-8 跳回临时高亮 | T-016/T-018/T-020 |
| US-9 面板开关 | T-019/T-020 |
| US-10 集成：选词→高亮→面板→跳回 | T-023 |
| US-11 编辑/改色 | T-006/T-019 |
| US-12 删除+二次确认+清理 | T-003/T-006/T-019 |
| US-13 多选批量删除 | T-006/T-019 |
| US-14 书签 | T-006/T-008/T-020 |
| US-15 删书级联 | T-002/T-003 |
| US-16 导出字段 | T-006/T-008/T-022 |
| US-17 空笔记/路径 | T-022 |
| US-18 搜索结果/CJK | T-001/T-004/T-007/T-009/T-010/T-013/T-021 |
| US-19 定位跳转/关键词高亮 | T-009/T-010/T-014/T-018/T-021 |
| US-20 范围/格式筛选 | T-004/T-007/T-009/T-013/T-021 |
| US-21 性能/CJK/特殊字符 | T-002/T-004/T-007/T-009/T-010 |
| US-22 集成：搜索→结果→跳转 | T-023 |
| US-23 v4 迁移/回填 | T-002/T-004/T-009/T-010/T-025 |
| US-24 真机清单 | T-026 |

## 4. 冲突检查结果

- [x] 与既有业务无冲突（或已列处置方案）：见 `02-design.md §7` 的 C1–C15，全部含处置与责任任务；`reading_progress` 唯一事实源、听读同进度、Locator 章内 progression、TTS 句↔Locator 语义均不破坏。
- [x] 任务粒度可执行：26 个任务，估算 0.5–1d（均 ≤1 天），每个任务有可断言验收并映射 US。
- [x] 无依赖环：§2 依赖图所有边方向一致（T 序号递增），无回边。
- [x] DDL/契约同步：v4 DDL 与桥接签名由 T-025 同步 `docs/03 §4`/`docs/04 §5`（developer 实现阶段落文档）。

## 5. 闸门2 自评（计划部分）
- [x] 必含项齐全：v4 迁移（T-002）、types 契约（T-001）、locator（T-005）、notes（T-006）、search（T-007）、store 仓储（T-003/T-004）、api+FRB codegen（T-008/T-009/T-010/T-011）、Dart services（T-012/T-013/T-014）、ReaderPage 接线（T-017/T-018/T-020）、notes_page（T-019）、search_page（T-021）、正文 span 渲染（T-016）、导出（T-022）、书签（T-020）、真实集成测试（T-023）、docs 同步（T-025）、golden/既有测试同步（T-024）。
- [x] 每任务 ≤1 天、有验收、映射 US；依赖无环。
- [x] 冲突清单 C1–C15 全部有处置，无未决冲突。
