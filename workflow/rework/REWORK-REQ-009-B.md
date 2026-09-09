<!-- wf-meta: req=REQ-009-notes-search | phase=product-preview | agent=product-reviewer | date=2026-09-09 | gate=open -->
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
