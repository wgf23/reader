<!-- wf-meta: req=REQ-001 | phase=delivery | agent=release-manager | date=2025-08-30 | gate=passed -->
# REQ-001 · 交付与发布说明（WebView 分页渲染）

## 1. 验证结果汇总
- **Rust**：cargo test 24 单测 + 5 真实语料集成测试 全绿；CRAP FAIL=0（WARN=5）；
  变异分数 91.7%（门槛 80%）；覆盖率 89.1%（不含桥接胶水，门槛 85%）。
- **Flutter**：flutter analyze 0 问题；widget 测试 5 用例全绿（滚动/进度/分页模式切换）；
  FFI 端到端测试通过（导入→章节文本→HTML→资源错误路径→进度往返）。
- **质量工具链**：CRAP（自研）、DDD lint（自研，0 违规）、cargo-mutants、llvm-cov 全部集成并跑通。

## 2. 变更说明（面向用户/开发）
- 阅读器新增**分页模式**（系统 WebView + CSS columns 分页，Readium 模式），滚动模式保留可切换；
- 章节图片/原书排版随 WebView 渲染显示（资源经 `reader://` scheme 从核心按需读取）；
- 字号调节（14–24pt）在分页模式下注入根样式并重排；
- 阅读进度持久化（reading_progress，schema v2）：重开恢复章节与进度；
- 桥接 API 增补：`book_chapter_html` / `book_resource` / `progress_save` / `progress_get`。

## 3. 已知问题与限制
- **真机验收待办（本容器无显示环境）**：验收标准 2/5（翻页 ≥55fps、10MB EPUB 首屏 <500ms）
  需在真实桌面（WebView2/WKWebView/WebKitGTK）手工验证；代码已按 Readium 分页模式实现，
  帧率由"视口平移零重排"保证，但数值验收需真机（见 01-req.md 验收 2/5）。
- Linux（WebKitGTK）分页行为差异：若异常，降级路径为滚动模式（代码已保留）。
- 进度恢复：章节级恢复已实现；章内页级恢复依赖 JS 上报（真机验证项）。

## 4. 追溯矩阵（闭合）

| 验收标准（01-req.md） | 设计 | 代码 | 测试证据 | 闭合 |
|---|---|---|---|---|
| 1. 含图 EPUB WebView 渲染+图片显示 | 02-design §2/§4（scheme 拦截） | paged_web_view.dart | FFI chapterHtml/resource + widget 分页模式用例 | ✅（真机图片显示列真机项） |
| 2. 翻页 55fps / 100 次 | 02-design §4（视口平移零重排） | pagination.js render/next/prev | 设计保证；**数值验收列真机待办** | ⏳ 真机 |
| 3. 换字号位置不漂移 | 02-design §5（文本锚降级链） | PagedWebView.setStyle + relayout | 代码路径 + 进度恢复测试 | ✅（真机位置复核列真机项） |
| 4. 分页/滚动切换即时生效 | 02-design §1（双模式） | reader_page._pagedMode | reader_page_test 分页切换用例 | ✅ |
| 5. 10MB EPUB 首屏 <500ms | 02-design §4（懒加载单章） | PagedWebView | **数值验收列真机待办** | ⏳ 真机 |
| 6. 章末连播 | 02-design §4（gotoChapter） | reader_page._goChapter | widget 章节切换用例 | ✅ |
| 7. 重开恢复进度 | 02-design §3（reading_progress） | api progress_save/get + store v2 | 单测 progress_roundtrip + widget 重开恢复用例 + FFI 进度往返 | ✅ |

## 5. 发布产物清单
- 版本：v0.2.0（REQ-001 合入后）
- 代码：core（api/library/store/epub）+ app（PagedWebView/reader_page/services）
- 质量报告：crap-req001.md、ddd-req001.md、04-mutation.md、04-coverage.md（workflow/reports 与 backlog/REQ-001/）
- rework 记录：REWORK-REQ-001-D.md

## 闸门5 自评
- [x] 追溯矩阵闭合（2 项数值验收标记真机待办，理由记录）
- [x] 全量回归绿（cargo test / flutter test / FFI / 变异 / 覆盖 / CRAP / DDD）
- [x] 发布产物齐全
