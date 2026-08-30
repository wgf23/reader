/// 排版引擎抽象（设计：docs/03-architecture.md §3.2）。
///
/// 骨架期仅定义接口；P0 实现 `WebViewReflowEngine`（系统 WebView + 分页脚本，
/// Readium Navigator 模式），远期可替换为自研轻量排版引擎。
abstract class ReflowEngine {
  /// 打开规范 EPUB，准备分页。
  Future<void> open(String canonicalEpubPath);

  /// 当前章节页数。
  int get pageCount;

  /// 跳到指定全书进度（0.0..=1.0）。
  Future<void> goto(double totalProgression);

  /// 应用阅读样式（字号 / 主题 / 行距），不丢位置。
  Future<void> setStyle({required int fontSize, required String theme});

  // TODO(P0): selectText / currentLocator / toc / nextPage / prevPage
}

/// PDF 引擎抽象（设计：docs/03 §3.2），P0 实现 `PdfiumRenderer`。
abstract class PdfEngine {
  Future<void> open(String pdfPath);
  int get pageCount;
  // TODO(P0): renderPage / selectText / outline
}
