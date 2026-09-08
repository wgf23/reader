<!-- wf-meta: req=REQ-005-fixes | phase=testing | agent=test-engineer | date=2026-09-08 | gate=passed -->
# REQ-005-fixes · 阶段4 覆盖率报告

> 闸门4②：本 REQ 新增/改动代码行覆盖 **≥85%** ✅
> - Rust（REQ-005 新增行）：**687/699 = 98.3%**；核心 `core/src/tts/mod.rs` **98.4%**。
> - Dart（新增界面/服务层 8 文件）：**429/504 = 85.1%**；**排除真实 WebView 固有不可测项后 427/429 = 99.5%**。
> - 不可测项：真实系统 WebView（`paged_web_view.dart` 除工厂函数外）、FRB 生成物、需 `.so` 的 FFI 入口（已在报告中单列说明）。

---

## 1. 采集命令

```bash
export PATH="/root/flutter/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"
export CARGO_BUILD_JOBS=2

# Rust（llvm-cov 0.9.1）
cd core
cargo llvm-cov --release --json --output-path ../workflow/reports/coverage-req005.json
cargo llvm-cov --release --lcov --output-path ../workflow/reports/coverage-req005.lcov
python3 ../scripts/cov-summary.py ../workflow/reports/coverage-req005.json

# Dart（含真实 .so，使 FFI 端到端与 RustTtsBackend 适配层被覆盖）
cd ../app
READER_CORE_SO=../core/target/release/libreader_core.so flutter test --coverage
# → app/coverage/lcov.info；用下方 python 按文件过滤
```

> 说明：`flutter test --coverage` 带 `READER_CORE_SO` 运行时，`rust_bridge_test.dart`/`tts_ffi_test.dart` 由跳过转为真实执行，从而覆盖手写 FFI 适配层 `lib/services/rust_tts_backend.dart`。

## 2. Rust 覆盖率

### 2.1 本 REQ 相关文件（行覆盖，llvm-cov lcov）

| 文件 | 覆盖行/可执行行 | 行覆盖 |
|---|---|---|
| `core/src/tts/mod.rs`（整模块本 REQ 新增/改写） | 557/566 | **98.4%** |
| `core/src/api.rs`（仅 REQ-005 新增函数区 L349–489） | 105/108 | **97.2%** |
| `core/src/store/mod.rs`（`get_setting`/`set_setting` L208–232） | 19/19 | **100%** |
| `core/src/library/mod.rs`（`get_setting`/`set_setting` L111–120） | 6/6 | **100%** |
| **REQ-005 新增/改动行合计** | **687/699** | **98.3%** |

未覆盖行说明（均为防御性/不可达分支，非行为缺陷）：

- `tts/mod.rs`：81（`chars.is_empty()` 兜底，前有 `trim().is_empty()` 早返回）、91–97（`trimmed.is_empty()` 兜底合并分支，注释即标注"理论不可达"）、101（`total == 0` 分支，`chars` 非空时 `total ≥ 1`）。合计 9 行。
- `api.rs`：487–489（`_unused_result_type`，`#[allow(dead_code)]` 占位）。

### 2.2 全仓口径（供参考）

| 口径 | 行覆盖 |
|---|---|
| 全部文件 | 5012/6496 = 77.2% |
| 排除生成代码（`frb_generated.rs`） | 5012/5319 = 94.2% |
| 排除生成代码 + `api.rs` 胶水层 | 4752/4990 = 95.2% |

## 3. Dart 覆盖率（新增/改动文件）

| 文件 | 覆盖行/可执行行 | 行覆盖 | 未覆盖说明 |
|---|---|---|---|
| `lib/engines/system_tts_engine.dart` | 43/43 | **100%** | — |
| `lib/services/tts_backend.dart` | 6/6 | **100%** | — |
| `lib/services/rust_tts_backend.dart` | 39/40 | **97.5%** | L81 `ensureTtsBackendInit` 为预留初始化入口（当前未被调用） |
| `lib/widgets/listen_control_bar.dart` | 48/48 | **100%** | — |
| `lib/widgets/listen_settings_sheet.dart` | 41/42 | **97.6%** | L148 定时关闭 RadioGroup 的 `onChanged`（全项禁用，回调不可达） |
| `lib/widgets/listen_follow_highlight.dart` | 13/13 | **100%** | — |
| `lib/pages/listen_page.dart` | 237/237 | **100%** | — |
| `lib/engines/paged_web_view.dart` | 2/75 | **2.7%** | 仅 `buildPagedWebViewSettings` 工厂被单测覆盖；其余为真实 `InAppWebView` 平台视图，属**固有不可测** |
| **合计（8 文件）** | **429/504** | **85.1%** ✅ | |
| **合计（排除 `paged_web_view.dart` 固有不可测）** | **427/429** | **99.5%** ✅ | |

## 4. 不可测项说明

- **`lib/engines/paged_web_view.dart`（真实系统 WebView）**：`InAppWebView` 依赖平台视图/JS 运行时，widget 测试下无法实例化；本阶段新增可测工厂 `buildPagedWebViewSettings` 已 100% 覆盖（禁用原生选择菜单的 US-19 断言）。其余属真机/集成覆盖，按 `workflow/skills/coverage.md` 先例单列。
- **`lib/src/rust/**`（FRB 生成物）**：生成代码，不计入新代码口径。
- **FFI（需 `core/target/release/libreader_core.so`）**：本报告已用真实 `.so` 运行端到端，覆盖 `rust_tts_backend.dart`；无 `.so` 环境下该测试自动跳过（不影响普通 `flutter test` 全绿）。
- **`rust_tts_backend.dart` L81 / `listen_settings_sheet.dart` L148**：分别为预留入口与禁用控件回调，属不可达/暂不启用，已注明。

## 5. 回归与门禁自检

| 检查 | 命令 | 结果 |
|---|---|---|
| core 全量单测 | `cd core && cargo test --release` | **170 + 21 + 5 + 8 + 3 = 207 passed / 0 failed** |
| Flutter 全量 | `cd app && flutter test` | **77 passed / 3 skipped / 0 failed** |
| Flutter 静态分析 | `cd app && flutter analyze` | **No issues found!（0）** |
| FFI 端到端 | `READER_CORE_SO=../core/target/release/libreader_core.so flutter test test/rust_bridge_test.dart test/tts_ffi_test.dart` | **2 passed / 0 failed**（含 `RustTtsBackend` 适配层映射） |
| DDD 分层 | `scripts/ddd-lint/target/release/ddd-lint check . --rules workflow/rules/ddd-rules.toml` | **违规=0** |
| CRAP | `scripts/crap/target/release/crap scan core --cov workflow/reports/coverage-req005.json` | **FAIL=0，WARN=7（均既有），PASS=291** |

## 6. 本阶段新增/修改的测试文件

| 文件 | 变更 |
|---|---|
| `core/src/tts/mod.rs` | 新增 24 个边界/异常/辅助函数用例（测试模块内，无业务代码改动） |
| `core/src/library/mod.rs` | 新增 `settings_forwarded_to_store_roundtrip` |
| `core/tests/tts_api.rs` | **新增**：听书桥接 API 集成测试（真实 EPUB 全链路 + 设置默认/往返/clamp/错误路径） |
| `app/test/rust_bridge_test.dart` | 修复硬编码语料绝对路径 → 仓库相对路径推导 + `READER_CORPUS` 覆盖 |
| `app/test/tts_engine_test.dart` | 新增 9 个用例：女声挑选/枚举失败回退/非 List 回退/setVoice 抛错/resume 无当前句/stop 清空/dispose/取消回调/非字符串错误 |
| `app/test/listen_page_test.dart` | 新增 15 个用例：防抖合并/拖动两端 clamp/末章停播/空章节/章节不存在/连续失败阈值/上一下一句/设置关闭/高亮越界 clamp/拖动仅预览/末句失败/下一章加载失败/Stopped 重读/href 非法/设置数据 copyWith |
| `app/test/tts_ffi_test.dart` | 扩充：`RustTtsBackend` DTO↔domain 映射 + 设置往返（真实 `.so`） |

> 生产代码零改动（无行为变更）；无 rework 文件。

## 7. 结论

- Rust REQ-005 新增/改动行覆盖 **98.3%**（`tts/mod.rs` **98.4%**）✅ ≥85%
- Dart 新增界面/服务层 8 文件覆盖 **85.1%**（排除固有不可测 WebView 后 **99.5%**）✅ ≥85%
- 未覆盖项均为防御性/不可达分支或固有不可测平台代码，已逐条说明。
