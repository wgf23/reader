# Skill · product-preview（产品预览：设计稿 ↔ 实现截图 对照报告）

> 给「产品/用户」一个可浏览器打开的单文件，逐屏对照设计稿与实现截图，并自动告警视口方向不一致。
> 由 `scripts/product-preview.py` 生成，零额外依赖（标准库，SVG 内联 + PNG base64）。

## 命令
```bash
# 一键（推荐，opencode/CI 直接调）：真实截图 + 对照报告
bash scripts/ui-screenshots.sh REQ-XXX

# 生成演示报告（快速看效果）
python3 scripts/product-preview.py --sample

# 生成正式报告：manife 清单 → 自包含 HTML
python3 scripts/product-preview.py <manifest.json> -o workflow/backlog/REQ-XXX/product-preview-REQ-XXX.html
```

## manifest 清单（JSON）
```json
{
  "req": "REQ-XXX", "product": "阅读器页交互重构",
  "screens": [
    { "id": "S1", "name": "书架", "device": "mobile",
      "design": {"svg": "docs/wireframes/01-library.svg", "viewport": "900x640", "label": "设计稿 v1"},
      "impl":   {"png": "app/test/goldens/library.png",    "viewport": "1170x2532", "label": "golden 截图"},
      "intent": ["侧边导航 + 封面网格 + 继续阅读徽标"],
      "acceptance": ["导航项齐全", "封面网格 ≥2 行", "继续阅读徽标"] }
  ]
}
```
- `device`：期望目标设备方向（mobile/tablet/desktop），用于交叉核对。
- `design.viewport` / `impl.viewport`：脚本据此判断方向是否一致，不一致自动标「⚠ 视口不一致」。
- `intent`：该屏的设计意图（供产品核对）；`acceptance`：产品逐条勾选的验收点。
- `impl.png`：实现截图（`app/test/goldens/*.png` 或真机截图）。缺省则该屏被标记为 gap。

## 验收（供 gate5 使用）
- 每屏产品判定「通过 / 有偏差 / 不通过」。
- `deviation = 0`（无未授权偏差）→ gate5 放行；否则 → rework-B。
- 报告 HTML 会给出统计：总屏数、视口不一致数、无实现截图 gap 数。

## 产物
- `workflow/backlog/REQ-XXX/product-preview-REQ-XXX.html`（人工验收载体）。
- `05b-product-preview.md`（偏差清单 + deviation 计数，见 `agents/product-reviewer.md`）。

## 已知坑
- **⚠ 首要：widget golden ≠ 真机效果。** `app/test/goldens/*.png` 是 `flutter test` widget 渲染的**占位态**：
  默认用 Ahem 方块字体（文字=实心方块）、不加载真实封面/资源、无渐变（实测全部 < 820 色）。
  **绝不能**拿它当"实现效果"做产品验收对照（这正是"golden 看着一致、真机却不满"的根源）。
  → `impl.png` 必须来自**真实渲染**：`flutter drive`（integration_test，真实字体/资源）截图、或真机/模拟器 `adb screencap`。
- **视口方向不一致**：项目设计稿全为 900×640 横屏，真机/ golden 为 1170×2532 竖屏。
  对照前先确认竖屏适配映射（或要求补竖屏设计稿），否则每屏都会误报偏差。
- **golden 缺口**：设计稿定义了某屏但无对应真实截图 → 该屏被标 gap，产品无法核验。
