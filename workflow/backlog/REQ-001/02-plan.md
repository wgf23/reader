<!-- wf-meta: req=REQ-001 | phase=architecture | agent=architect | date=2025-08-30 | gate=passed -->
# REQ-001 · 计划拆分（Task 分解）

## 任务清单

| Task | 内容 | 依赖 | 估算 | 验收 |
|---|---|---|---|---|
| T-001 | core：`book_chapter_html` / `book_resource`（经 library 读规范 EPUB 缓存）+ 单元测试 + 重新生成桥接绑定 + FFI 测试 | — | 0.5d | FFI 测试能取到红楼梦某章 HTML 与图片字节；cargo test 全绿 |
| T-002 | app：接入 flutter_inappwebview；`WebViewReflowEngine`（自定义 scheme handler + pagination.js：CSS columns 页断点、翻页平移、字号/主题注入、章内进度上报） | T-001 | 1.5d | widget 测试（fake engine 直测接口）；真机冒烟：含图 EPUB 分页渲染、图片显示 |
| T-003 | app：阅读器页模式切换（分页 WebView / 滚动 Text）+ 字号/主题控件 + 进度保存恢复 + 章末连播 | T-002 | 1d | widget 测试覆盖切换与进度；手测 10MB EPUB 首屏 <500ms、翻页 ≥55fps |
| T-004 | 测试强化：分页 JS 关键路径单测（页断点/重排定位不漂移）、变异测试（变更模块 ≥80%）、覆盖率 ≥85%、性能基准记录 | T-003 | 1d | 闸门4 全过：变异报告/覆盖报告/CRAP 报告归档 |

## 依赖图
```
T-001 → T-002 → T-003 → T-004
（无环；T-004 依赖前三者全部完成）
```

## 冲突检查结果
- 与既有业务冲突：**无**。新接口向后兼容（book_open 保留）；滚动模式路径不动；
  Locator/进度/听读不变式不受影响；ddd-rules.toml 覆盖新文件归属（api.rs 属 interface、
  library 属 application、engines/pages 属 interface）。
- 计划完整性：T-001..T-004 覆盖"桥接→引擎→页面→测试"全链，无缺口。

## 闸门2 自评（计划部分）
- [x] 任务粒度可执行（每任务 ≤1.5d、有验收）
- [x] 无依赖环
- [x] 冲突检查通过
