<!-- wf-meta: req=REQ-001 | phase=development | agent=developer | date=2025-08-30 | gate=passed -->
# REQ-001 · 开发前置审查（Pre-Implementation Review）

## 1. 设计与既有约定核对
| 检查项 | 结果 |
|---|---|
| 与 docs/03 分层/架构冲突？ | 无。新增 api 函数归 interface、library 归 application、engines/pages 归 interface，符合 ddd-rules.toml |
| 与 docs/04 Locator/限界上下文冲突？ | 无。进度复用 reading_progress（新增表，语义同 docs/04 §5 设计），不新造进度模型 |
| 与既有 ADR 冲突？ | 无（ADR-001 为本 REQ 产物） |
| 与既有业务（听读同进度/笔记锚定）冲突？ | 无。进度接口为增量（progress_save/get），不影响既有 book_open；滚动模式路径未动 |

## 2. 计划核对
| 检查项 | 结果 |
|---|---|
| 任务缺失/依赖环/估算离谱？ | 无。T-001..T-004 覆盖桥接→引擎→页面→测试全链，依赖无环 |

## 3. 需求可测性核对
| 检查项 | 结果 |
|---|---|
| 验收标准可实现且可测？ | 是。量化指标（帧率/耗时/位置不漂移）可测；其中"真机 55fps/首屏 500ms"需真实桌面验证（本容器无显示环境，列为交付期手工验收项） |

## 4. 结论
- [x] 通过，进入实现

## 5. 实现与自检记录
| Task | 完成 | 测试 | CRAP | DDD |
|---|---|---|---|---|
| T-001 core：book_chapter_html/book_resource/progress_save/progress_get + store v2 | ✅ | cargo test 20 单测 + 5 语料全绿；FFI 端到端补充 | PASS | 0 违规 |
| T-002 app：flutter_inappwebview + PagedWebView（分页 JS/资源拦截/样式注入） | ✅ | widget 测试（fake 构建器） | PASS | 0 违规 |
| T-003 app：阅读器页模式切换 + 字号 + 进度保存/恢复 | ✅ | reader_page_test 3 用例（滚动/进度/分页切换） | PASS | 0 违规 |

> **实现期发现并修复的既有问题（基线修复）**：ddd-lint 首次全仓库扫描发现
> `app/lib/pages/reader_page.dart` 越层直接 import 桥接生成物（`src/rust/api.dart`）。
> 修复：services 层引入 DTO（BookSummaryData/BookViewData/ChapterData），页面只经 services
> 拿数据；复扫 0 违规。此为既有 P0 代码的历史违规，与 REQ-001 同分支修复并记录于此。
