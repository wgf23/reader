# Skills — 可复用的工作流能力（每个 = 一个可调用的操作 + 命令 + 验收）

> 任一 Agent / orchestrator 按 `skills/*.md` 调用；命令自包含、可复制执行。

| Skill | 用途 | 关键命令 |
|---|---|---|
| [wf-meta-check](wf-meta-check.md) | 校验阶段产物头 | `python3 scripts/wf-meta-check.py workflow` |
| [gates](gates.md) | 闸门1-5 执行清单 | 见文件 |
| [crap](crap.md) | CRAP 评分（CC²(1-cov)³+CC+D） | `scripts/crap/target/release/crap ...` |
| [ddd-lint](ddd-lint.md) | 分层合规 | `scripts/ddd-lint/... check` |
| [mutants](mutants.md) | 变异测试 | `bash scripts/mutants.sh` |
| [coverage](coverage.md) | 覆盖率 | `flutter test --coverage` |
| [prototype-conformance](prototype-conformance.md) | UI 原型一致性 | 逐屏对照 wireframes |
| [build-android](build-android.md) | Android APK | `bash scripts/build-android.sh` |
| [build-platform](build-platform.md) | macOS/Windows 构建 | `bash scripts/build.sh` / `scripts/build-windows.ps1` |
