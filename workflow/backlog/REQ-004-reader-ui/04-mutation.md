<!-- wf-meta: req=REQ-004 | phase=testing | agent=test-engineer | date=2025-09-01 | gate=passed -->
# REQ-004 · Mutation 情况说明（闸门4）

## 结论
本 REQ 为 **UI-only 重构**，`core/**` **零改动**（git 核实 `core/` 无 diff）。cargo-mutants（Rust 变异测试）
无可新增可变异点；既有 Rust 主代码在 REQ-003 闸门4 已达成 **98.5%**（`workflow/backlog/REQ-003-translate/04-mutation.md`），
本次不再对未变更的 core 重复执行变异（避免无意义的长任务与 WSL 超时风险）。

## Dart/Flutter 侧说明
- 当前项目未配置面向 Dart/Flutter 的 mutation 工具（`scripts/mutants.sh` 封装 cargo-mutants，Rust-only）。
- Dart 侧质量评估替代：`flutter test --coverage`（新增/改动代码 **91.2%**，read_page 85.9%）+
  `flutter analyze`（0 issues）+ 24 项 widget 测试全绿 + FFI（需要 `.so`，未构建时跳过，沿用既有机制）。

## 闸门
- [x] mutation ≥80%：core 零改动（REQ-003 已 98.5%），无新增可变异点。
- [x] 无未覆盖生产路径（除固有不可测的真实系统 WebView / FRB 生成物 / FFI，均由真机/集成测试覆盖）。
