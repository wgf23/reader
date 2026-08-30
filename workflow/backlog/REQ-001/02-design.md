<!-- wf-meta: req=REQ-001 | phase=architecture | agent=architect | date=2025-08-30 | gate=passed -->
# REQ-001 · 模块/接口设计（WebView 分页渲染）

## 1. 模块与职责变化

| 模块 | 变化 | 层 |
|---|---|---|
| `core/src/api.rs` | 新增 `book_chapter_html(id, href)`、`book_resource(id, path)` | interface |
| `core/src/library/mod.rs` | 新增"从规范 EPUB 缓存读章节 HTML / 资源字节"（复用 format::epub 读取） | application |
| `app/lib/engines/reflow_engine.dart` | 接口保持；新增 `WebViewReflowEngine` 实现 | interface |
| `app/lib/services/` | 后端 DTO 增补：`chapterHtml` / `resource` 访问（经桥接） | application |
| `app/lib/pages/reader_page.dart` | 分页/滚动模式切换；分页模式由 WebView 渲染 | interface |
| `app/assets/` | `pagination.js`（分页脚本，CSS columns + 页断点 + 翻页） | — |

## 2. 接口签名

### Rust（core/src/api.rs，桥接契约）
```rust
/// 取规范 EPUB 中某章节的原始 HTML（WebView 渲染用）
pub fn book_chapter_html(id: String, href: String) -> Result<String, String>;
/// 取规范 EPUB 中某资源（图片/CSS/字体）的字节
pub fn book_resource(id: String, path: String) -> Result<Vec<u8>, String>;
```

### Dart（services 层 DTO 增补，页面不直接触碰桥接）
```dart
abstract class LibraryBackend {
  Future<String> chapterHtml(String bookId, String href);      // 新增
  Future<Uint8List> resource(String bookId, String path);      // 新增
}
```

### ReflowEngine（app/lib/engines/reflow_engine.dart）
```dart
abstract class ReflowEngine {
  Future<void> open(BookViewData view, LibraryBackend backend);
  int get pageCount;                                   // 当前章页数
  Future<void> nextPage() / prevPage() / gotoChapter(int i);
  Future<void> setStyle({required int fontSize, required String theme});
  String get currentHref;                              // 当前章节 href（进度用）
  double get chapterProgression;                       // 章内进度 0..1
}
```

## 3. 数据模型变化
无数据库变更；`reading_progress` 语义不变（章内进度 + 全书进度 + 文本锚）。

## 4. 关键时序

```
阅读器页（分页模式）
  → backend.openBook(id) → BookViewData（章节标题列表）
  → WebViewReflowEngine.open(view, backend)
      → 加载 reader://book/{id}/{chapter0.href}（HTML 字符串 + baseUrl=自定义 scheme）
      → 自定义 scheme handler：reader://book/{id}/{path} → backend.resource(path)
         （图片/CSS/字体按需取字节，返回 mime 类型）
      → 注入 pagination.js：CSS columns 排版 → 测量列断点 → 页表（page → column）
      → 渲染第 1 页（视口平移）
  → 翻页：nextPage = 平移视口到下一列（零重排）；章末 → gotoChapter(i+1)
  → 字号/主题：setStyle 注入根样式 → 重算页表 → 用当前文本锚重新定位（不漂移）
  → 进度：currentHref + chapterProgression → Locator → reading_progress 节流保存
```

## 5. 与既有约定的兼容性
- [x] 不破坏 Locator 模型（文本锚重定位复用 docs/04 §3 降级链）
- [x] 不跨越限界上下文（HTML/资源读取在 core 的 library/application 层，桥接在 api/interface）
- [x] 听读同进度不变式保持（进度仍写 reading_progress）
- [x] 滚动模式保留（Text 渲染路径不动），分页模式为新增路径
