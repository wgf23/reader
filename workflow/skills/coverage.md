# Skill · coverage（Dart/Flutter 覆盖率）

## 命令
```bash
source /home/heiwa/workspace/.toolchain/env.sh
cd app && flutter test --coverage      # 生成 coverage/lcov.info
```

## 门槛
- 新增/改动代码**行覆盖率 ≥ 85%**。
- 用 `scripts/cov-summary.py coverage/lcov.info` 汇总；可再用 python 按文件过滤新增文件。

## 不可测项说明
- `engines/paged_web_view.dart`（真实系统 WebView）与 `src/rust/**`（FRB 生成）、FFI（需 `.so`）在 widget 测试下 0 覆盖，属**固有不可测**（真机/集成覆盖）。
- 因此统计口径通常**排除**这些，仅统计新增界面/服务层代码。

## 产出
`04-coverage.md`：各文件覆盖率表 + 合计 + 不可测项说明 + 结论（≥85% ✅）。
