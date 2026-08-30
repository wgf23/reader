<!-- wf-meta: req=REQ-001 | phase=architecture | agent=architect | date=2025-08-30 | gate=passed -->
# REQ-001 · 架构决策记录（ADR-001：WebView 渲染引擎选型）

## 决策
采用 **flutter_inappwebview（统一插件）+ 自研分页脚本（CSS columns 页断点）**，
封装在 `ReflowEngine` 接口之后（docs/03 §3.2）；资源访问走自定义 scheme（`reader://`）。

## 备选方案
1. **方案 A：flutter_inappwebview** —— 单一 API 覆盖 Android/iOS/Windows(WebView2)/macOS(WKWebView)/
   Linux(WebKitGTK)/Web；支持自定义 scheme handler、JS 注入、滚动监听。
   优点：跨平台一致、维护活跃；缺点：依赖插件版本、Linux 依赖 WebKitGTK 系统包。
2. **方案 B：各平台 webview 包组合**（webview_windows / 平台原生壳）——
   优点：更贴平台；缺点：接口碎片化，每平台一套实现，违背"一套代码"原则。
3. **方案 C：自研轻量排版引擎**（Flutter Text 直接重排，KOReader 路线）——
   优点：完全可控、零 webview 依赖、体积最小；缺点：CSS 支持子集、实现成本高（月级）。

## 选择与理由
选 **A**：与 docs/02 §4.1 设计一致（系统 WebView 排版 + 不内置浏览器引擎），跨平台统一、
实现成本最低；**C 保留为 `ReflowEngine` 的远期第二实现**（接口隔离已就位，替换不动 UI）。

## 影响
- `app/lib/engines/reflow_engine.dart` 接口落地为 `WebViewReflowEngine`；
- `core` 桥接 API 新增 `book_chapter_html` / `book_resource`（规范 EPUB 缓存按需读取）；
- 阅读器页保留滚动模式（Text），新增分页模式（WebView）；
- 进度/笔记锚定不变（Locator）；docs/02 §4.1、docs/03 §3.2 不变。

## 闸门2 自评（ADR 部分）
- [x] 备选 ≥2 且给出理由
- [x] 与既有约定（ReflowEngine 接口、规范 EPUB）一致
