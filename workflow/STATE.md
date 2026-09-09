# 工作流状态（唯一状态源 —— 仅 orchestrator 可写，Agent 只读）

| 字段 | 值 |
|---|---|
| 当前阶段 | **REQ-007 全部阶段完成（闸门1-5 全 ✅）**，分支 `wf/REQ-007-reader-interaction-fixes` 待用户确认后合并 main |
| 活跃 REQ | REQ-007-reader-interaction-fixes（P0：①点击正文中部无法呼出顶底栏 ②无法切换下一章 ③在线翻译引导） |
| 分支 | wf/REQ-007-reader-interaction-fixes（已提交 5 个 commit：`d20f789` 开发 / `28d5821` 测试 / `c677f6a` 产品验收 / `5793de6` 交付；基于 main `4f3f55b`） |
| 闸门状态 | 闸门1 ✅（orchestrator 独立复验：`wf-meta-check` 全部头合法；`01-req.md` US-1..US-17 全可测、逐条标注 [集成测试]/[widget 测试]/[单测]/[真机]；根因 R1-1/R1-2/R2-1/R2-2/R2-3/R3-1/R3-2/R3-3 带 file:line；无重复；影响面非空）。闸门2 ✅（`02-adr` D1..D6 各 3-4 备选+理由+降级线；`02-design` 接口/时序/逐屏映射/DDD 分层；`02-plan` T-001..T-009 ≤1d、US 覆盖全闭合、DAG 无环、8 类冲突已处置）。闸门3 ✅（orchestrator 独立复验：cargo **222 passed/0 failed**；flutter **152 passed/4 skipped**（开发时 149，测试阶段补测后 152）；analyze **0**；ddd-lint **违规=0**；集成 `reader_interaction_test` **5/0** + `screenshots_test` **12/0**；`no_synthetic_chrome_test` 静态守卫绿；**独立对照实验**证实旧 `GestureDetector(onTapUp)` 包 `SelectionArea` 点文字 `toggled=0`、新 `Listener` `toggled=1`；原型 deviation=0；CRAP N/A（core 仅字面量追加）；codegen 零改动）。闸门4 ✅（变异：core 仅字符串字面量、`cargo mutants --list` 102 个与 REQ-006 逐条一致，定向 `translate_auto` **83.3%**、基线校正 **98.33%** ≥80%，存活体 **4/4 有结论**；覆盖：本 REQ 新增/改动 Dart **142/142=100%**、whole-file 477/515=92.6% ≥85%；无 rework-D）。闸门5a ✅（product-reviewer 逐屏像素/几何对照 S1-S5，`bash scripts/ui-screenshots.sh REQ-007` **退出码 0**、12 张真实渲染截图、HTML 5 屏，**deviation=0**、gap=0）。闸门5b ✅（release-manager：追溯 **US-1..17 = 17/17 闭合、孤儿=0**；全量回归绿；FFI 3/0；DDD 0；**APK 构建成功** `dist/reader-android-arm64-v0.7.1.apk` 46.1MiB，aapt2 校验 versionName=0.7.1/versionCode=12、含 INTERNET+PROCESS_TEXT+TTS_SERVICE、3 ABI `libreader_core.so`；v0.7.1+12） |
| rework 计数 | REQ-007：**A=0 B=0 C=0 D=0**（无 rework；test-engineer 发现 `translation.rs:492` 为 REQ-006 遗留测试缺口、生产代码正确，登记后续补测，不触发 D） |
| 最近事件 | REQ-007 **全流程完成**。三项 P0 修复：**问题1** 根因 `SelectionArea`(`SelectableRegion`) 在手势竞技场吞掉父 `GestureDetector.onTapUp` → 改为不进竞技场的 `Listener` + `BodyTapTracker` 手动判定（位移≤18px/时长≤500ms/单指/主键），命中区语义逐字保留；**问题2** ①`PagedWebView.didUpdateWidget` 不处理 href/html 变化 → `PagedDocumentReloader` + `PagedLoadGate`（`controller.loadData` 重载，载入完成后再 relayout）；②`_runBool` 与字符串 `'true'` 比较恒 false（插件返回 Dart `bool`）→ `parseJsBool`/`PagedJsExecutor`，章内翻页不再误跳章、章末才续章；**问题3** `auto`+key 在线链路确认，无 key 文案追加"设置"引导 + `OverlayError` 可选"去设置"按钮直接 push `SettingsPage(translateBackend:…)`（打通 R3-3 设置页运行期入口）。集成测试**去合成页**（`screenshots_test.dart:147-179` 合成 `Column` 已删除，改真实点击正文文字）+ `no_synthetic_chrome_test.dart` 静态守卫。orchestrator 独立复验全部闸门（不采信自评）。 |
| 遗留问题（非阻塞） | ① **Android 真机 5 项手工验收**（US-17，`03-review.md §4`）：分页点文字呼出/隐藏、边缘章内翻页/章末续章、底栏下一章、长按选中、无 key"去设置"，需真机执行；② 分页路径 Linux 不可实跑（`flutter_inappwebview` 无 linux 实现）→ 由 US-6/7/8 单测 + US-5/9 widget + 真机兜底；③ REQ-006 遗留测试缺口 `core/src/dict/translation.rs:492`（DeepL 空 key 变异体存活，生产代码正确，建议后续用真实 Provider+空串 key 补测）；④ 横屏设计稿 900×640 vs 竖屏实现 390×844（建议补竖屏稿，REQ-004/005/006 已授权沿用）；⑤ 书架页设置入口（R3-3）为 P1 未做（本 REQ 已由"去设置"打通设置页可达）；⑥ 既有警告 `core/src/tts/mod.rs:572 unused text`（REQ-005 遗留）；⑦ macOS/Windows 未构建（非本 REQ 目标）。 |
| 下一条建议 | ① 用户在 Android 真机按 `03-review.md §4` 执行 5 项验收（APK：`dist/reader-android-arm64-v0.7.1.apk`），重点验证分页模式翻页/切章与点正文文字呼出；② 确认后 `git checkout main && git merge wf/REQ-007-reader-interaction-fixes`（orchestrator 不自行合并）；③ 可选：补 `translation.rs:492` 空 key 测试、补 390×844 竖屏设计稿、书架页设置入口。 |

## 阶段进度

| 阶段 | Agent | 产物 | 状态 |
|---|---|---|---|
| 1 需求 | req-analyst | `01-req.md` | ✅ 完成（闸门1 通过） |
| 2 架构 | architect | `02-adr.md` `02-design.md` `02-plan.md` | ✅ 完成（闸门2 通过） |
| 3 开发 | developer | 代码 + `03-review.md` | ✅ 完成（闸门3 通过，commit `d20f789`） |
| 4 测试 | test-engineer | `04-mutation.md` `04-coverage.md` | ✅ 完成（闸门4 通过，commit `28d5821`） |
| 5a 产品验收 | product-reviewer | `05b-product-preview.md` + HTML | ✅ 完成（deviation=0，commit `c677f6a`） |
| 5b 交付 | release-manager | `05-delivery.md` + APK | ✅ 完成（闸门5 通过，commit `5793de6`） |
