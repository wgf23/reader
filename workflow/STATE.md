# 工作流状态（唯一状态源 —— 仅 orchestrator 可写，Agent 只读）

| 字段 | 值 |
|---|---|
| 当前阶段 | **REQ-005 全部阶段完成（闸门1-5 全 ✅）**，分支 `wf/REQ-005-fixes` 待用户确认后合并 main |
| 活跃 REQ | REQ-005-fixes（P0 听书不可用 + P0 安卓原生选择菜单覆盖自定义工具条） |
| 分支 | wf/REQ-005-fixes（已创建；阶段3 起代码+产物在此分支提交） |
| 闸门状态 | 闸门1 ✅（orchestrator 独立复验：wf-meta ✓ exit 0；25 条 US 全可测、无非测措辞；与既有 REQ 复用不重复；影响面 10+ 类带 file:line）。闸门2 ✅（orchestrator 独立复验：`wf-meta-check.py workflow` exit 0；ADR 6 决策点各 ≥2 备选+选择理由+影响+降级线（含重点决策点1 Rust 桥接契约、决策点2 分页禁原生菜单）；design 逐屏映射 09/10/04-selection（引用 5 处）+ US-1..US-25 对应表 + 兼容性清单；plan T-001..T-013 全部 ≤1d、验收映射 US、脚本检测依赖环 = NONE；业务代码零改动）。闸门3 ✅（orchestrator 独立复验：cargo test --release 207 passed/0 failed；flutter test 77 passed/3 skipped；flutter analyze 0；ddd-lint 违规=0；CRAP 重跑 FAIL=0/WARN=7；codegen 幂等；原型逐屏 deviation=0）。闸门4 ✅（orchestrator 独立复验：cargo-mutants 本 REQ 变更范围 missed=0，分数 100%（127/127）/含 timeout 90.1%；Rust tts/mod.rs 覆盖 98.2%；新增 Dart 8 文件 85.1%（排除真实 WebView 固有不可测 99.5%）；存活体 0、14 timeout 逐一有结论）。闸门5a ✅（product-reviewer：真实渲染截图 3 屏 + HTML 对照报告，deviation=0，无 rework）。闸门5 ✅（release-manager：追溯矩阵 US-1..25 全闭合、孤儿=0；全量回归绿；Linux bundle v0.6.4+10 构建成功；Android APK 因本机无 SDK/NDK 未构建，已登记复现命令） |
| rework 计数 | REQ-005：0（orchestrator 复验发现 2 处文档笔误并直接修订：design §6 `T-014`→`T-013`；plan 关键路径标签由误列 T-004 修正为经 T-003，8.5d→8d） |
| 最近事件 | REQ-005 **全流程完成**（分支 `wf/REQ-005-fixes`，4 次提交）：`9a250c4` 阶段3 听书链路+分页禁原生菜单；`d4b01d0` 阶段4 变异/覆盖+边界用例；`a505e5d` 阶段5a 真实截图对照 09/10 + 05b；`16f8451` 阶段5b v0.6.4+10 交付+追溯矩阵。orchestrator 独立复验全部闸门（不采信子代理自评）：cargo 207/0、flutter 77/3skip、analyze 0、ddd-lint 0、CRAP FAIL=0、变异 missed=0、覆盖 ≥85%、原型 deviation=0、追溯 25/25 闭合。环境解除 2 项阻塞：安装 FRB codegen 2.13.0 与 cargo-mutants 27.1.0 预编译二进制到 `~/.cargo/bin`；修正 `rust_bridge_test.dart` 硬编码语料路径为仓库相对。遗留：Android 真机 4 项手工验收、`paged_web_view` 真实 WebView 固有不可测、横屏稿↔竖屏真机建议补稿（均非阻塞，见 05-delivery §已知限制）。 |
| 下一条建议 | ① 用户在具 Android SDK/NDK 环境执行 `bash scripts/build-android.sh` 并完成 03-review §5 的 4 项真机验收；② 确认后 `git checkout main && git merge wf/REQ-005-fixes`（orchestrator 不自行合并）；③ 可选：补 390×844 竖屏设计稿以支持像素级视觉验收 |
