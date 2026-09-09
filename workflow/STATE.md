# 工作流状态（唯一状态源 —— 仅 orchestrator 可写，Agent 只读）

| 字段 | 值 |
|---|---|
| 当前阶段 | **REQ-009 全部阶段完成（闸门1-5b 全 ✅）**，分支 `wf/REQ-009-notes-search` 待用户确认后合并 main |
| 活跃 REQ | REQ-009-notes-search（P0：笔记 NOTE-01~07 + 全文搜索 READ-06） |
| 分支 | wf/REQ-009-notes-search（基于 main `5f220f9`；6 个 commit：`3b8af1d` 开发（含 01-req/02-* 产物，51 files +10120/-161）→ `5c5cf8d` 测试（变异/覆盖）→ `40c2260` 产品验收（deviation=1）→ `1c95920` rework-B 修复 → `975b14a` 产品复验（deviation=0）→ `c8c089f` 交付 v0.9.0） |
| 范围 | A · 笔记：NOTE-01 高亮(4 色)/NOTE-02 划线/NOTE-03 批注/NOTE-04 笔记面板/NOTE-05 编辑·删除·改色/NOTE-06 书签/NOTE-07 导出 Markdown·JSON；B · 全文搜索 READ-06（全书搜索 + 关键词高亮 + 定位跳转 + 范围/格式筛选） |
| 闸门状态 | 闸门1 ✅（orchestrator 独立复验：`01-req.md` 502 行，US-1..US-24 逐条 Given/When/Then 可断言、四类测试层级齐备、含强制真实集成 US-10/US-22；§1.4 与 REQ-003/005/006/008 无重复（file:line）；§3 影响面 6 类非空；§5 风险 10 项含 CJK 分词硬门槛）。闸门2 ✅（12 决策点 D1-D12 每点≥2 备选+理由+降级线，D1 含 SQLite 3.53.2 实测；T-001..T-026 均 0.5-1d、依赖无环、US-1..24 映射闭合；逐屏映射 06/07/04 + C1-C15 冲突全处置）。闸门3 ✅（orchestrator 独立复验：cargo **282 passed/0 failed**、flutter **288 passed/5 skipped/0 failed**、analyze **0**、ddd-lint **违规=0**、CRAP **FAIL=0/WARN=9(全既有)/PASS=310**、原型 deviation=0；**真实集成** `notes_search_integration_test.dart` **2/2**（US-10 选词→高亮→面板→跳回；US-22 搜索→结果→定位→临时高亮），回归 `continuous_scroll` 5/5、`interaction` 5/5、`screenshots` 17/17、`no_synthetic_chrome` 通过；**CJK 实测** 城市/卡尔维诺/记忆 各 1 命中 199-262µs）。闸门4 ✅（变异域+仓储 **96.58%**、api **100%**、合计 **96.81%**（364/376）、timeout=0；存活 **12 个全部有结论**（11 等价/不可达 + 1 既有 integrity_check）；覆盖 Dart 新代码 **99.54%**（870/874）、Rust 新代码 **99.06%**（2210/2231）；orchestrator 独立解析 lcov 得改动 Dart whole-file 94.2%）。闸门5a ✅（首次 deviation=1 → rework-B；复验 **deviation=0**：`ui-screenshots.sh REQ-009` 退出码 0、17 张真实截图、4 屏对照（S1 工具条/S2 面板/S3 搜索/S4 跳回临时高亮）全通过）。闸门5b ✅（追溯 **US-1..US-24 = 24/24 闭合、孤儿=0**；全量回归绿 + FFI 2/2；**APK 构建成功** `dist/reader-android-arm64-v0.9.0.apk` 49,619,805 B（47.3 MiB），sha256 `26d783ba…a965a`，aapt2 校验 versionName=0.9.0/versionCode=14、3 ABI `libreader_core.so`；v0.9.0+14）。 |
| rework 计数 | REQ-009：A=0 **B=1** C=0 D=0（5a D1：搜索「第 N 章」用结果序号而非真实章号 → `1c95920` 修复：`SearchHit/SearchHitView/SearchHitData` 增 `chapter_index`，`api.rs` 按书库章节顺序回填、跨书各自 0 基，`search_page.dart:198` 用真实章号；复验 deviation=0） |
| 最近事件 | REQ-009 **全流程完成**。实现：core 新增 `store/annotations.rs`/`store/search_index.rs` + 重写 `locator/notes/search`（`LocatorResolver::from_selection` UTF-16 文本锚 + progression 消歧；`AnnotationService` CRUD/分组/导出/书签；`SearchService` **CJK bigram 预处理** + FTS5 `text_bi` 唯一索引列，`unicode61` 下 2 字中文词命中）；v4 迁移（`annotations` + `fts_books(book_id,href,chapter,text UNINDEXED,text_bi)`，`remove_book` 事务显式删 FTS，主连接 `busy_timeout=5000`，仓储第二连接 FK ON）；`api.rs` 9 个 notes async 桥接 + `search` + `NOTES`/`SEARCH` 单例 + 导入即索引/懒回填；FRB codegen。app 新增 `notes_backend`/`search_backend`/`rust_*`/`export_path_picker` 服务、`notes_panel`/`note_editor_card`/`note_colors` 组件、`note_span_policy` 分段渲染；`reader_page` 选区接线（高亮选色/划线/批注/书签/跳转临时高亮/搜索入口）、`search_page`/`notes_page` 真实实现。**唯一 rework**：rework-B D1（真实章号），已闭环。orchestrator 独立复验全部闸门（不采信自评）。 |
| 遗留问题（非阻塞） | ① **Android 真机 US-24 ①–⑧ 手工验收**（本环境无设备，`03-review.md §6`/`01-req.md US-24` 清单）：高亮/划线/批注重开仍在、面板跳回、编辑改色批量删除、书签、导出、搜索定位、换字号主题后高亮不丢、既有功能零回退；② 视口方向 900×640 横屏稿 vs 390×844 竖屏（REQ-004 起既有授权，deviation=0 已记 tradeoff）；③ 既有 `core/src/tts/mod.rs:572 unused text` 警告（REQ-005 遗留）；④ 集成测试目录级运行工具链限制 → 逐文件 29/0；⑤ `paged_web_view.dart` 真实 WebView 固有不可测（真机兜底）；⑥ macOS/Windows/iOS 未构建（非本 REQ 目标）。 |
| 下一条建议 | ① 用户在 Android 真机按 `01-req.md US-24`/`03-review.md §6` 执行 8 项验收（APK：`dist/reader-android-arm64-v0.9.0.apk`），重点验证 CJK 全文搜索、多色高亮重排不丢、面板跳回临时高亮；② 确认后 `git checkout main && git merge wf/REQ-009-notes-search`（orchestrator 不自行合并）；③ 可选：补 390×844 竖屏设计稿；④ 可选：笔记跨设备同步 NOTE-08（P2 接口 `sync_status` 已预留）。 |

## 阶段进度

| 阶段 | Agent | 产物 | 状态 |
|---|---|---|---|
| 1 需求 | req-analyst | `01-req.md` | ✅ 完成（闸门1 通过） |
| 2 架构 | architect | `02-adr.md` `02-design.md` `02-plan.md` | ✅ 完成（闸门2 通过） |
| 3 开发 | developer | 代码 + `03-review.md` | ✅ 完成（闸门3 通过，commit `3b8af1d`） |
| 4 测试 | test-engineer | `04-mutation.md` `04-coverage.md` | ✅ 完成（闸门4 通过，commit `5c5cf8d`） |
| 5a 产品验收 | product-reviewer | `05b-product-preview.md` + HTML + manifest | ✅ 完成（首次 deviation=1 → rework-B → 复验 deviation=0，commit `40c2260`/`975b14a`） |
| 3′ rework-B | developer | 真实章号修复 | ✅ 完成（commit `1c95920`，闸门3 复验通过） |
| 5b 交付 | release-manager | `05-delivery.md` + APK | ✅ 完成（闸门5 通过，commit `c8c089f`） |
