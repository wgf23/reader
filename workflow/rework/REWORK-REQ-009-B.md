<!-- wf-meta: req=REQ-009-notes-search | phase=product-preview | agent=product-reviewer | date=2026-09-09 | gate=passed -->
# REWORK-REQ-009-B · 产品验收偏差处置（rework-B）

## 触发
阶段 5a 产品验收（`workflow/backlog/REQ-009-notes-search/05b-product-preview.md`）逐屏对照
设计稿 ↔ 真实渲染截图，发现 **1 项未授权偏差**（deviation=1）→ 闸门5 前置 **failed** → 本 rework-B。

采集命令：`bash scripts/ui-screenshots.sh REQ-009`（退出码 0；17 passed / 0 failed；4 屏对照报告已生成）。

## 偏差 D1（S3 全文搜索 · 结果行「第 N 章」语义错误）

| 项 | 内容 |
|---|---|
| **屏** | S3 全文搜索（线框 `docs/wireframes/04-search.svg`） |
| **类型** | 做错（语义） |
| **现象** | 结果行的「第 N 章」显示的是**结果列表序号**，而非该命中所属书籍的**真实章节序号**。线框 04 示例三条结果为「第 1 / 3 / 2 章」（各书真实章号，非顺序号）；S3 截图复刻线框同三本书/三章，实际渲染为「第 1 / 2 / 3 章」，第 2、3 条与线框不符。极端示例：命中第二章却显示「第 1 章 · 第二章」，标签自相矛盾。 |
| **证据** | `app/lib/pages/search_page.dart:171` `itemBuilder: (context, i) => _resultRow(i, _hits[i])`；`:198` `Text('第 ${index + 1} 章 · ${hit.chapterTitle}')`（`index` = 结果序号）。数据模型无章节序号字段：`core/src/types.rs:307`（`SearchHit`）、`core/src/api.rs:187`（`SearchHitView`）、`app/lib/services/search_backend.dart:14`（`SearchHitData`）。集成测试 `app/integration_test/notes_search_integration_test.dart:166` 断言 `'第 1 章 · 第二章'`，锁定该行为。 |
| **根因** | `SearchHit` 数据模型未携带章节序号，02-design §6.3 用 `i+1`（结果序号）近似，UI 无从取真实章号。 |
| **影响** | 用户可见的标签语义错误；跨书/多章结果时「第 N 章」与相邻章节名矛盾，误导定位。 |

## 修复方案（择一，由架构裁定）

1. **忠实修复（推荐）**：`SearchHit` / `SearchHitView` / `SearchHitData` 增 `chapter_index: u32`（`api.rs` 组装命中时按书库章节顺序回填，或索引时随章写入 `fts_books`）；UI 渲染
   `第 ${hit.chapterIndex + 1} 章 · ${hit.chapterTitle}`。
   - 同步更新：`app/test/search_page_test.dart`、`app/integration_test/notes_search_integration_test.dart` 断言；`02-design §6.3`；必要时 `docs/04 §5`（索引列）。
   - 验收：S3 复测时三条结果分别显示「第 1 / 3 / 2 章」，与线框 04 一致；跨书搜索（scope=全部书籍）章号取各书自身序号。
2. **降级并改设计/原型**：若架构判定真实章号超出本期范围，则去掉「第 N 章 · 」前缀、只显示章节名，并同步修订 `02-design §6.3` 与线框 04，消除「第 N 章」与章节名自相矛盾。

## 责任与复验

- **责任**：architect 裁定方案 → developer 实现（T-021 修订）+ test-engineer 同步断言。
- **复验**：重跑 `cargo test` / `flutter test` / `flutter analyze` / 真实集成测试 → 重跑
  `bash scripts/ui-screenshots.sh REQ-009` → product-reviewer 复核 S3「第 N 章」与线框一致，
  deviation 归零后闸门5 前置放行。

## 非偏差项（无需处置，见 05b §3）
视口方向 900×640 横屏 vs 390×844 竖屏（既有授权）；「查词」入口保留（REQ-003）；高亮四色展开与色值（ADR C15）；
面板宽度 `min(360,屏宽*0.9)`（ADR D7 降级线）；M3 主题色（既有基线）；书签行并入面板（02-design §6.2）。

## 结论
- **deviation = 1（D1）→ 闸门5 前置 failed**；修复并复验后回填本文件 `gate=passed` 并重跑闸门3–5a。

---

## 修复实现 + 复验结果（developer，2026-09-09）

**方案**：采用**方案 1（忠实修复）**，且为**零 schema 变更**（不在 `fts_books` 加 UNINDEXED 列、无迁移/回填）。

### chapter_index 的来源与回填

- `core/src/types.rs::SearchHit` 增 `chapter_index: u32`：domain 查询阶段无从得知书库章节顺序，置 0（带注释），由 `api.rs::search` 回填。
- `core/src/api.rs` 新增 `chapter_indices(book_id)`（与既有 `chapter_titles` 同处）：`open_book` 枚举该书章节顺序 → `href → 0 基序号`。
- `core/src/api.rs::search`：查询后按命中 `book_id` 去重，逐书构建 `href→序号` 映射，再回填每条命中的 `chapter_index`；**跨书 scope 每本书各自 0 基**；`href` 查不到时保持 0（不 panic）。
- `SearchHitView` / `SearchHitData` 同步增字段；`search_page.dart` 渲染
  `第 ${hit.chapterIndex + 1} 章 · ${hit.chapterTitle}`（不再用结果列表 `index`；`index` 仅保留给 `search-locate-N` key）。
- `core/src/search/mod.rs` 查询结果已携带 `href`，api 据此回填，domain 层零新依赖（DDD 分层不变）。

### 改动文件

| 文件 | 变更 |
|---|---|
| `core/src/types.rs` | `SearchHit.chapter_index: u32` |
| `core/src/search/mod.rs` | `query` 产出 `SearchHit.chapter_index = 0`（占位，api 回填） |
| `core/src/api.rs` | `SearchHitView.chapter_index`；`chapter_indices`；`search` 按书回填 |
| `core/src/frb_generated.rs` | FRB codegen 生成物（未手改） |
| `app/lib/src/rust/{api.dart,frb_generated.dart}` | FRB codegen 生成物（未手改） |
| `app/lib/services/search_backend.dart` | `SearchHitData.chapterIndex`（required） |
| `app/lib/services/rust_search_backend.dart` | 映射 `chapterIndex` |
| `app/lib/pages/search_page.dart` | 渲染真实章号 |
| `app/test/search_page_test.dart` | 断言真实章号 + 跨书/非首章「第 3 / 第 2 章」反例（证明非列表序号） |
| `app/test/reader_notes_test.dart` | 两处 `SearchHitData` 补 `chapterIndex` |
| `app/integration_test/notes_search_integration_test.dart` | 断言改为「第 2 章 · 第二章」 |
| `app/integration_test/screenshots_test.dart` | S3 三条命中 `chapterIndex=0/2/1` + 断言「第 1/3/2 章」 |
| `core/tests/notes_search_api.rs` | 全量命中 `chapter_index == 书库章节序号`；非首章命中 `chapter_index == idx(>=1)` |
| `workflow/backlog/REQ-009-notes-search/02-design.md` | §3 类型、§4.4 时序、§6.3 逐屏映射同步（标注 rework-B D1） |
| `app/screenshots/search_page.png` | S3 重生成（真实章号） |
| `workflow/reports/{coverage-req009-rust.json,coverage-req009-rust.lcov,crap-req009.md}` | 覆盖率/CRAP 重跑 |

> `docs/04 §5/§7` **无需改**：零 schema 变更（`fts_books` 列不变）、`SearchService::query` 签名不变；章节序号在 interface 层（`api.rs`）组装。`02-design.md` 已同步。

### 复验（本机实跑）

| # | 命令 | 结果 |
|---|---|---|
| 1 | `cd core && cargo test --release` | **全绿**（0 failed；lib 241 + 集成 41） |
| 2 | `cd app && flutter test` | **288 passed / 0 failed / 5 skipped** |
| 3 | `cd app && flutter analyze` | **No issues found!** |
| 4 | `xvfb-run -a flutter test integration_test/notes_search_integration_test.dart -d linux` | **2/2**（US-10、US-22） |
| 5 | `xvfb-run -a flutter test integration_test/screenshots_test.dart -d linux` | **17/17**；S3 断言「第 1 / 3 / 2 章」通过；`search_page.png` 重生成（223,092 B） |
| 6 | `ddd-lint check /root/reader` | **违规=0** |
| 7 | `crap scan core/src`（重跑覆盖率） | **FAIL=0 / WARN=7 / PASS=312** |

**S3 三条结果真实章号**（`search_page.png`，与线框 04 一致）：
- 看不见的城市 · 城市与记忆 → **第 1 章**
- 马可瓦尔多 · 城市与符号 → **第 3 章**
- 树上的男爵 · 城市与贸易 → **第 2 章**

**闸门3 自评**：CRAP FAIL=0；DDD 违规=0；cargo/flutter/analyze 全绿；无未处理 rework；S3 原型一致性 deviation=0。→ **gate=passed**，请 product-reviewer 重跑闸门5a 复核。
