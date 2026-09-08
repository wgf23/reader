# opencode Runbook —— 用 opencode 驱动本多智能体工作流

> opnecode（`opencode run` / 交互 TUI）可作为这套五阶段流水线的**执行运行时**。
> 角色已映射为 opencode 自定义 agent（见根 `opencode.json`），prompt 直接引用 `workflow/agents/*.md`（单一事实源）。

## 前置
- [ ] opencode 已安装并配好 provider（本例 `deepseek/deepseek-v4-flash`，复用 Hermes 的 DeepSeek key）。
- [ ] 在**项目根**运行（`opencode.json` 在根，agents 从此加载）。`opencode agent list` 应看到 7 个角色。

## 角色映射
| opencode agent | 模式 | 工作流角色 | 阶段 | 产物 |
|---|---|---|---|---|
| `orchestrator` | primary | 编排者 | 全程 | STATE.md（唯一写者） |
| `req-analyst` | subagent | 需求分析 | 1 | 01-req.md |
| `architect` | subagent | 架构设计 | 2 | 02-adr/02-design/02-plan.md |
| `developer` | subagent | 开发 | 3 | 代码 + 03-review.md |
| `test-engineer` | subagent | 测试 | 4 | 04-mutation/04-coverage.md |
| `product-reviewer` | subagent | **产品验收** | 5a | 05b-product-preview.md/.html |
| `release-manager` | subagent | 交付 | 5b | 05-delivery.md |

## 用法

### 模式 A：交互式（推荐，完整流水线）
```bash
cd /root/reader
opencode            # 启动 TUI，Tab 切到 orchestrator
```
在 orchestrator 主对话里下达诉求，例如：
> 处理 REQ-005 听书基础（见 workflow/STATE.md 下一条建议）。先 @req-analyst 出 01-req.md，过闸门1 后 @architect 出 02-*，再 @developer 实现 + @test-engineer 测试，结尾调用 @product-reviewer 生成产品预览对照报告核对设计稿，最后 @release-manager 出交付与追溯矩阵。全程维护 STATE.md。

orchestrator 会按 `agents/*.md` 逐一 `task()` 派单，独立执行闸门并复验。

### 模式 B：一次性驱动
```bash
opencode run --agent orchestrator "处理 REQ-005 ...（同上）"
```

### 单独跑某一环（兜底 / 快速验证）
- 产品验收报告（不依赖模型）：`python3 scripts/product-preview.py --sample` 或
  `python3 scripts/product-preview.py <manifest.json> -o <out.html>`，然后浏览器打开 HTML 逐屏判定。
- 各质量闸门命令见 `workflow/skills/gates.md`（cargo/flutter/crap/ddd-lint/mutants/coverage）。
- 构建 APK：`bash scripts/build-android.sh`。

## 产品验收（重点，解决"真机效果跟设计稿不符"）
一键命令 `bash scripts/ui-screenshots.sh REQ-XXX`

每次涉及 UI 的 REQ，在合并主线**前**由 `product-reviewer` 执行：
1. 用 `skills/product-preview` 生成「设计稿 ↔ 实现截图」对照报告 HTML。
2. 逐屏判定：设计已授权取舍→tradeoff；否则→rework-B。
3. `deviation == 0` 才放行到 release-manager。

> ⚠ 项目设计稿全为 **900×640 横屏**，真机/ golden 为 **1170×2532 竖屏**。核对前先确立竖屏适配映射，
> 否则每屏都会误报方向偏差（`product-preview` 会自动标「⚠ 视口不一致」辅助定位）。

## 已知限制
- subagent 由 orchestrator 用 `task()`/`@` 调度；如需单跑某 subagent，经 orchestrator 提唤，
  或直接手动执行对应 `scripts/` 命令（本仓库脚本均可独立运行）。
- 本机无 Flutter/Android 工具链：构建/真机截图需在具备工具链的环境执行；产品预览报告可复用
  `app/test/goldens/*.png`（已入库）直接生成，无需跑构建。
