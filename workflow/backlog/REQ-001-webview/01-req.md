<!-- wf-meta: req=REQ-001 | phase=requirements | agent=req-analyst | date=2025-08-30 | gate=passed -->
# REQ-001 · WebView 分页渲染 —— 需求分析

## 1. 背景与目标
P0 阅读器用 Flutter Text 滚动模式渲染章节纯文本（占位实现）：无法还原原书排版
（CSS/图片/内联字体），没有真正的"分页"阅读体验。REQ-001 引入**系统 WebView + CSS 分页**
（Readium Navigator 模式，docs/02 §4.1）：分页模式为主、滚动模式保留，翻页 60fps、
换字号/主题不丢位置、正文图片正常显示。成功标准：桌面端读 EPUB 的体验达到主流阅读器水平。

## 2. 用户故事与验收标准（Given/When/Then）
- 故事：作为读者，我想要像翻纸质书一样分页阅读且能看到原书排版与图片，以便长时间阅读不疲劳。
  1. Given 打开任意含图 EPUB 并进入阅读器 When 正文渲染完成 Then 正文由 WebView 渲染，
     分页模式可用且章节图片正常显示（资源路径重写正确）
  2. Given 分页模式 When 点击右侧热区/→ 键 Then 前进一页；点击左侧/← 键后退一页；
     桌面 100 次连续翻页平均帧间隔 ≤ 18ms（≈55fps）
  3. Given 当前页有一段文字 When 字号 12→20 调整 Then 分页重排且当前位置（文本锚/章节内进度）
     不漂移（重排后仍定位到同一句）
  4. Given 分页/滚动两种模式 When 在阅读器内切换 Then 即时生效且阅读进度保持不变
  5. Given 10MB EPUB 首次打开 When 点击封面进入阅读器 Then 首屏内容 < 500ms（桌面）
  6. Given 任意章节 When 翻到章末并继续 Then 自动进入下一章第一页（章间无缝）
  7. Given 阅读器 When 关闭并重开 Then 恢复到上次章节与页（复用 reading_progress）

## 3. 影响面分析
- 既有功能：阅读器页（reader_page.dart）从纯 Text 渲染改为 WebView 渲染（保留滚动模式）；
  书架/导入/书库不受影响。
- 数据模型/接口：`book_open` 目前只返回章节纯文本；**需要新增**章节 HTML 与资源访问接口
  （`book_chapter_html` / `book_resource`，走规范 EPUB 缓存）。
- 听读进度 / Locator：进度仍复用 Locator（章节内进度 + 全书进度 + 文本锚），不变式不破坏。
- 回归面：现有滚动模式、FFI 端到端测试、widget 测试、cargo 测试需全绿。

## 4. 依赖与优先级
- 依赖：core 规范 EPUB 缓存（已有）、`flutter_inappwebview`（新增，桌面 WebView2/WKWebView/WebKitGTK）、
  分页脚本（自研，CSS columns + 页断点）。
- 优先级：P1（试点需求，按 docs/07 流水线全流程推进）。

## 5. 风险
- Linux WebKitGTK 分页行为与 Win/macOS 有差异 → 降级路径：Linux 检测异常自动退回滚动模式。
- 分页 JS 复杂度（大章节、图片加载时序）→ 页断点在 onLoad 后计算 + 图片 onload 重算。
- 大章节内存 → 只加载当前章 + 相邻章；分页表按需计算。
- flutter_inappwebview 桌面成熟度 → 若阻塞（Android/iOS 原生，桌面良好），退路是平台 webview 封装（影响 ADR）。

## 6. 闸门1 自评
- [x] 验收标准全部可测（帧率/耗时/位置不漂移均有量化指标）
- [x] 与既有 REQ 无重复（滚动模式是占位，本需求是分页渲染）
- [x] 影响面清单非空
