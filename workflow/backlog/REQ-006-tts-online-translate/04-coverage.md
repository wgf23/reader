<!-- wf-meta: req=REQ-006 | phase=testing | agent=test-engineer | date=2026-09-09 | gate=passed -->
# REQ-006 · 覆盖率报告（闸门4②）

> 输入：`03-review.md`（gate=passed）、代码（commit `e2e5798` + 本阶段测试补强）、`workflow/skills/coverage.md`。
> 工具：cargo-llvm-cov 0.9.1（Rust）/ flutter test --coverage（Dart，Flutter 3.47.2）。
> 口径：**新代码 = `git diff e9d75b5..e2e5798` 的新增行 ∩ 可执行行（lcov DA）**；Rust 排除生成物 `frb_generated.rs`，Dart 排除 `app/lib/src/rust/**`（FRB 生成）与 `paged_web_view.dart`（真实 WebView，非本 REQ 改动文件，沿用 REQ-005 先例）。

---

## 1. 结论摘要

| 口径 | 覆盖 | 门槛 | 判定 |
|---|---|---|---|
| **Rust 新代码（生产，排除测试模块）** | **268 / 275 = 97.5%** | ≥85% | ✅ |
| Rust 新代码（含测试模块新增行） | 456 / 463 = 98.5% | ≥85% | ✅ |
| **Dart 新代码（10 个改动文件）** | **170 / 170 = 100%** | ≥85% | ✅ |
| Rust 全仓（排除 `frb_generated.rs`） | 5527 / 5846 = 94.5% | 参考 | ✅ |
| Dart 全仓 | 见 `app/coverage/lcov.info` | 参考 | — |

---

## 2. 采集命令

```bash
export PATH="$HOME/.cargo/bin:/root/flutter/bin:/usr/local/bin:$PATH"
export CARGO_BUILD_JOBS=2

# Rust（llvm-cov 0.9.1）
cd /root/reader/core
cargo llvm-cov --release --json --output-path /root/reader/workflow/reports/coverage-req006.json
cargo llvm-cov report --release --lcov --output-path /root/reader/workflow/reports/coverage-req006.lcov
python3 /root/reader/scripts/cov-summary.py /root/reader/workflow/reports/coverage-req006.json

# Dart（带真实 .so，使 4 个 FFI 端到端用例真实执行，覆盖 RustTranslateBackend 适配层）
cd /root/reader/app
READER_CORE_SO=/root/reader/core/target/release/libreader_core.so \
READER_CORPUS=/root/reader/core/tests/corpus/src/hongloumeng.epub \
READER_CORPUS_DICTS=/root/reader/core/tests/corpus/src/dicts \
flutter test --coverage          # → app/coverage/lcov.info（110 passed / 0 skipped）
```

> `cargo llvm-cov` 使用独立 `target/llvm-cov-target`，不覆盖 `target/release/libreader_core.so`；Dart 覆盖率在 Rust 覆盖率之前采集，FFI 用干净 `.so`。

---

## 3. Rust 覆盖率

### 3.1 新代码口径（REQ-006 新增/改动行）

| 文件 | 新可执行行 | 已覆盖 | 行覆盖 |
|---|---|---|---|
| `core/src/dict/translation.rs` | 242 | 235 | **97.1%** |
| `core/src/dict/provider.rs` | 3 | 3 | **100%** |
| `core/src/dict/mod.rs` | 3 | 3 | **100%** |
| `core/src/store/translation.rs` | 0* | 0 | n/a |
| `core/src/api.rs` | 27 | 27 | **100%** |
| **合计（生产新代码）** | **275** | **268** | **97.5%** ✅ |
| 合计（含 `#[cfg(test)]` 模块新增行） | 463 | 456 | 98.5% |

\* `store/translation.rs` 生产改动仅注释 + `const DEFAULT_PROVIDER: &str = "auto"`（编译期常量，lcov 不计为可执行行）；其行为由 `provider_config_roundtrip` 断言 `default_provider()=="auto"` 覆盖（④ 变异范围 3/3 killed 佐证）。

### 3.2 全文件口径（参考）

| 文件 | 覆盖行/可执行行 | 行覆盖 |
|---|---|---|
| `core/src/dict/translation.rs` | 1397/1439 | 97.1% |
| `core/src/dict/provider.rs` | 217/240 | 90.4% |
| `core/src/dict/mod.rs` | 48/49 | 98.0% |
| `core/src/store/translation.rs` | 263/265 | 99.2% |
| `core/src/api.rs`（含非 REQ 的 library/book/tts 桥接） | 282/353 | 79.9% |
| `core/src/frb_generated.rs`（生成物，排除） | 0/1274 | — |
| 全仓（排除 `frb_generated.rs`） | 5527/5846 | 94.5% |

### 3.3 新代码未覆盖行说明（7 行，均为防御性/不可达）

| 文件:行 | 内容 | 说明 |
|---|---|---|
| `translation.rs:526` | `else { None }`（`translate_auto` 回退原因） | 在线候选非空且无 error/未配置时不可达（每条候选路径要么返回要么置位） |
| `translation.rs:567-569` | 全失败后的最终 `Err(offline_error…)` | 前置分支（online_error / unconfigured）已穷尽，防御性兜底 |
| `translation.rs:655` | `if let Ok(t) = provider.translate(..)` 返回后的闭合 region | 分支已 return，region 闭合行不计执行 |
| `translation.rs:660-661` | `primary_error.unwrap_or_else(…)` | `primary_error` 恒为 `Some`，闭包不可达 |
| `api.rs` | — | 新代码 100% 覆盖 |

> 以上均非行为缺陷；`translate_explicit` 未知 provider / missing-key 回退 / offline 缓存命中 / `config_view` 无 deepl provider 兜底等**可达边界**已由本阶段新增 4 个单测覆盖（见 §5）。

---

## 4. Dart 覆盖率

### 4.1 新代码口径（REQ-006 改动文件）

| 文件 | 新可执行行 | 已覆盖 | 行覆盖 |
|---|---|---|---|
| `lib/engines/system_tts_engine.dart` | 23 | 23 | **100%** |
| `lib/widgets/listen_follow_highlight.dart` | 72 | 72 | **100%** |
| `lib/pages/listen_page.dart` | 15 | 15 | **100%** |
| `lib/pages/settings_page.dart` | 34 | 34 | **100%** |
| `lib/widgets/translation_popup.dart` | 10 | 10 | **100%** |
| `lib/services/translate_backend.dart` | 1 | 1 | **100%** |
| `lib/services/rust_translate_backend.dart` | 9 | 9 | **100%** |
| `lib/engines/tts_engine.dart`（事件子类） | 2 | 2 | **100%** |
| `lib/widgets/listen_control_bar.dart` | 2 | 2 | **100%** |
| `lib/widgets/listen_settings_sheet.dart` | 2 | 2 | **100%** |
| **合计** | **170** | **170** | **100%** ✅ |

### 4.2 全文件口径（改动文件）

| 文件 | 覆盖行/可执行行 | 行覆盖 | 未覆盖说明 |
|---|---|---|---|
| `lib/engines/system_tts_engine.dart` | 62/62 | 100% | — |
| `lib/widgets/listen_follow_highlight.dart` | 74/74 | 100% | — |
| `lib/pages/listen_page.dart` | 247/247 | 100% | — |
| `lib/widgets/translation_popup.dart` | 73/73 | 100% | — |
| `lib/services/translate_backend.dart` | 4/4 | 100% | — |
| `lib/engines/tts_engine.dart` | 6/6 | 100% | — |
| `lib/widgets/listen_control_bar.dart` | 49/49 | 100% | — |
| `lib/pages/settings_page.dart` | 94/106 | 88.7% | L70/97-100/111/136/145 为后端异常 catch 分支、L76/77/79/82 为默认 `FilePicker.platform` 平台闭包（widget 测试环境无平台实现）；**本 REQ 新增行 100%** |
| `lib/services/rust_translate_backend.dart` | 47/48 | 97.9% | L93 `ensureTranslateBackendInit` 为预留初始化入口（当前未被调用，同 REQ-005 `rust_tts_backend` 先例） |
| `lib/widgets/listen_settings_sheet.dart` | 51/52 | 98.1% | L160 定时关闭禁用控件回调（不可达，同 REQ-005 先例） |
| `lib/engines/paged_web_view.dart`（**排除**） | 2/75 | 2.7% | 真实 `InAppWebView` 平台视图，固有不可测；非本 REQ 改动文件 |
| `lib/src/rust/**`（**排除**） | — | — | FRB 生成物 |

---

## 5. 未覆盖热点与补测（本阶段新增）

| 热点 | 补测 | 结果 |
|---|---|---|
| `system_tts_engine.dart:74-75`：`setVoice` 返回 0/false → `clearVoice`+回退 | `tts_engine_test.dart` 新增 `setVoiceResult` + 用例「setVoice 返回 0 → clearVoice + TtsVoiceFallback 不阻断」 | 该文件新代码 100% |
| `listen_follow_highlight.dart:104-105/120-121/162`：换 controller 重挂载 / 注入分支 / 越界高亮 clamp | **新增** `listen_follow_highlight_test.dart`（5 例：`offsetForHighlight` 单调与 clamp、注入+换 controller、`autoScroll=false`、越界 clamp） | 该文件 100% |
| `rust_translate_backend.dart`（FFI 适配层） | **新增** `translate_ffi_test.dart`（真实 `.so`）：DTO 映射 / `getConfig` / `setStrategy` / `fallbackReason` / 掩码 | 新代码 100% |
| `translation.rs`：`translate_explicit` 未知 provider / missing-key 回退 / offline 缓存命中 / `config_view` 无 deepl provider | `translation.rs` 测试模块新增 4 例 | 生产新代码 97.1%（余为防御性不可达） |
| `api.rs:357`：`translate_get_config` 掩码分支 | `translate_corpus.rs` 新增「写 key → has_deepl_key=true + 掩码」断言 | api.rs 新代码 100% |

---

## 6. 不可测项说明

- **`lib/src/rust/**`（FRB 生成物）**：生成代码，不计入新代码口径。
- **`lib/engines/paged_web_view.dart`（真实系统 WebView）**：`InAppWebView` 依赖平台视图/JS 运行时，widget 测试无法实例化，属**固有不可测**（沿用 `workflow/skills/coverage.md` 与 REQ-005 先例）。本 REQ 未改动该文件。
- **FFI（需 `core/target/release/libreader_core.so`）**：本报告用真实 `.so` 运行 4 个端到端用例，覆盖 `rust_translate_backend.dart`；无 `.so` 环境下这些用例自动 `markTestSkipped`（普通 `flutter test` 仍全绿），此时 `rust_translate_backend.dart` 新代码将为 0%——属环境依赖，非代码缺陷，已在 CI/交付说明中登记。
- **真机项**（真正出声/音频焦点/release 联网/真实 DeepL）：CI 不可自动化，见 `03-review.md §4` 手工清单。

---

## 7. 回归与门禁自检

| 检查 | 命令 | 结果 |
|---|---|---|
| core 全量单测 | `cd core && cargo test --release` | **184 + 21 + 5 + 8 + 3 = 221 passed / 0 failed** |
| Flutter 全量（带 `.so`） | `READER_CORE_SO=… flutter test --coverage` | **110 passed / 0 skipped / 0 failed** |
| Flutter 全量（普通） | `cd app && flutter test` | **106 passed / 4 skipped / 0 failed**（4 个 FFI 用例无 `.so` 时跳过） |
| Flutter 静态分析 | `cd app && flutter analyze` | **No issues found!（0）** |
| 变异分数 | `04-mutation.md` | **99.17%**（≥80%） |

---

## 8. 本阶段新增/修改的测试文件

| 文件 | 变更 |
|---|---|
| `app/test/listen_follow_highlight_test.dart` | **新增**（5 例）：`offsetForHighlight` 单调/clamp、注入+换 controller、`autoScroll=false`、越界高亮 clamp |
| `app/test/translate_ffi_test.dart` | **新增**（1 例，真实 `.so`）：`RustTranslateBackend` DTO/策略/回退原因/掩码端到端 |
| `app/test/tts_engine_test.dart` | 修改：`FakeFlutterTts` 增 `setVoiceResult`；新增「setVoice 返回 0」用例 |
| `core/src/dict/translation.rs` | 仅 `#[cfg(test)]` 模块新增 4 例（未知 provider / missing-key 回退 / offline 缓存命中 / `config_view` 兜底），**无业务代码改动** |
| `core/tests/translate_corpus.rs` | 修改：补 `translate_get_config`/`translate_set_strategy` 往返 + 未知策略 + 掩码分支断言 |

> 生产业务代码零改动（新增仅在测试模块/测试文件）；无 rework 文件。

---

## 9. 闸门4 自评

- [x] **新代码行覆盖率 ≥ 85%**：Rust 生产新代码 **97.5%**；Dart 改动文件新代码 **100%**
- [x] **关键分支（错误路径/边界）已覆盖**：auto 在线优先/无 key 回退/在线失败回退/组合错误文案/显式策略回退/缓存命中、TTS 失败可见/focus/onStart/音色回退、滚动单调与 clamp、设置页掩码回填、译文来源标签
- [x] 未覆盖项均为防御性/不可达或固有不可测，逐条说明
- [x] 全量回归绿（221 Rust + 110 Dart 带 `.so`，`flutter analyze` 0 issue）

**闸门4②结论：通过（passed）。**
