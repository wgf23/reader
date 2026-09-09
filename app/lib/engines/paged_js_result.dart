/// 分页 JS 返回值解析（REQ-007 · ADR D3）。
///
/// 根因 R2-2：`_runBool` 把 `evaluateJavascript` 结果与字符串 `'true'` 比较，
/// 而插件对 JS 结果做 `json.decode`，布尔返回 Dart `bool`，故 `v == 'true'` 恒
/// false → `nextPage/prevPage` 恒 false → 边缘点击直接跳章、章内永不翻页。
///
/// 本文件不 import `flutter_inappwebview`：纯函数 + 可注入 evaluator，可在
/// 无 WebView 环境（Linux widget/单测）穷举断言。
library;

/// 解析 JS 布尔返回值：兼容 Dart `bool`、`num`、字符串 `'true'/'1'`；
/// `'false'`/`null`/非布尔 → false（不抛错）。
bool parseJsBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    return s == 'true' || s == '1';
  }
  return false;
}

/// JS 执行器签名（生产注入 `controller.evaluateJavascript`；测试注入 fake）。
typedef JsEvaluator = Future<dynamic> Function(String source);

/// 对 `evaluateJavascript` 的薄封装：`runBool` 走 [parseJsBool]，`runInt` 容错解析。
class PagedJsExecutor {
  PagedJsExecutor(this._evaluate);

  final JsEvaluator _evaluate;

  /// 执行 JS 并解析为 bool。
  Future<bool> runBool(String source) async => parseJsBool(await _evaluate(source));

  /// 执行 JS 并解析为正整数；`num`/字符串均可，非法值或 ≤0 → [fallback]。
  Future<int> runInt(String source, {int fallback = 1}) async {
    final v = await _evaluate(source);
    if (v is num) {
      final n = v.toInt();
      return n <= 0 ? fallback : n;
    }
    final n = int.tryParse('$v');
    return (n == null || n <= 0) ? fallback : n;
  }
}
