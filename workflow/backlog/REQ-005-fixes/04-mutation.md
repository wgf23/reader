<!-- wf-meta: req=REQ-005-fixes | phase=testing | agent=test-engineer | date=2026-09-08 | gate=passed -->
# REQ-005-fixes · 阶段4 变异测试报告（cargo-mutants 27.1.0）

> 闸门4①：**变异分数 = 127/127 = 100%**（killed/(killed+survived)，survived=0）✅ ≥80%
> 含超时口径：127/(127+14) = **90.1%** ✅ ≥80%
> 存活变异体：**0**；超时变异体：**14**（逐一结论见 §4）；不可执行（unviable）：**8**（豁免见 §5）。

---

## 1. 环境与命令

本机无 `/home/heiwa/workspace/.toolchain/env.sh`（**未** `source`），直接调用 `cargo mutants`：

```bash
export PATH="$HOME/.cargo/bin:/usr/local/bin:$PATH"
export CARGO_BUILD_JOBS=2
cd core

# ① 本 REQ 核心新增模块（整文件）
cargo mutants --file src/tts/mod.rs --timeout 60 --jobs 4 --output /tmp/opencode/mutants-tts

# ② api.rs 仅本 REQ 新增函数（正则限定，避免全量 api.rs 小时级）
cargo mutants --file src/api.rs \
  --re 'chapter_text|to_locator_view|tts_segment|tts_locator_for_sentence|tts_sentence_index_at|tts_listen_settings' \
  --timeout 60 --jobs 4 --output /tmp/opencode/mutants-api

# ③ store/library 仅新增 get_setting/set_setting
cargo mutants --file src/store/mod.rs --file src/library/mod.rs \
  --re 'get_setting|set_setting' --timeout 60 --jobs 4 --output /tmp/opencode/mutants-store

# ④ 全量运行中 321:13 因并发 CPU 饥饿被记为 timeout，隔离复核（jobs=1）
cargo mutants --file src/tts/mod.rs --re '321:13' --timeout 90 --jobs 1 --output /tmp/opencode/mutants-321
```

原始结果：`/tmp/opencode/mutants-*/mutants.out/{caught,missed,timeout,unviable}.txt` 与 `outcomes.json`。

## 2. 范围与总分

| 文件/函数范围 | total | caught | survived | timeout | unviable |
|---|---|---|---|---|---|
| `core/src/tts/mod.rs`（整文件，本 REQ 全部新增/改写） | 128 | 110¹ | **0** | 14 | 4 |
| `core/src/api.rs`（REQ-005 新增 7 函数） | 13 | 9 | **0** | 0 | 4 |
| `core/src/store/mod.rs`（`get_setting`/`set_setting`） | 4 | 4 | **0** | 0 | 0 |
| `core/src/library/mod.rs`（`get_setting`/`set_setting`） | 4 | 4 | **0** | 0 | 0 |
| **合计** | **149** | **127** | **0** | **14** | **8** |

¹ 全量运行记 109 caught + 15 timeout；其中 `321:13 replace < with <=` 经隔离复核（`--re 321:13`，jobs=1）3/3 caught，故计入 caught，timeout 减为 14。

**分数**

- 主口径（技能定义）：`killed / (killed + survived) = 127 / 127 = 100.0%` ✅
- 严格口径（timeout 视为未杀死）：`127 / (127 + 14) = 90.1%` ✅
- 排除不可执行：`127 / (149 − 8) = 90.1%` ✅

## 3. 存活清单

**无**（`missed.txt` 为空）。0 个存活变异体，无需豁免真实缺陷，未触发 rework。

## 4. 超时变异体逐条结论（14 条，均为非终止循环变异体）

> 结论类型：**非终止变异体**——变异使某个循环计数器/跳转目标退化，测试进程无法正常返回，被 cargo-mutants 60s 超时终止。它们**不通过测试**（不属 survived），但 cargo-mutants 单列为 timeout。均非真实缺陷（源码逻辑正确），亦非等价变异（变异后行为可观察地错误/不终止）。

| # | 文件:行:变异类型 | 结论 |
|---|---|---|
| 1 | `tts/mod.rs:259:19 replace -= with /= in word_before` | `start /= 1` 恒等 → 回溯循环不前进 → 无限循环（超时） |
| 2 | `tts/mod.rs:291:5 delimiter_end → Some(0)` | `j=end+1` 恒为 1 → `sentence_starts` 主循环 i 不前进 → 无限循环 |
| 3 | `tts/mod.rs:291:5 delimiter_end → Some(1)` | 同上，`j` 恒为 2 → 无限循环 |
| 4 | `tts/mod.rs:295:15 replace += with -= in delimiter_end`（`……` run） | j 回退 → run 扫描不终止 → 无限循环 |
| 5 | `tts/mod.rs:295:15 replace += with *= in delimiter_end`（`……` run） | j 不变 → 无限循环 |
| 6 | `tts/mod.rs:303:19 replace += with -= in delimiter_end`（`...` run） | j 回退 → 无限循环 |
| 7 | `tts/mod.rs:303:19 replace += with *= in delimiter_end`（`...` run） | j 不变 → 无限循环 |
| 8 | `tts/mod.rs:323:15 replace += with *= in sentence_starts` | `i *= 1` 恒等 → 主扫描不前进 → 无限循环 |
| 9 | `tts/mod.rs:326:25 replace + with * in sentence_starts`（`end+1`） | `j=end` 与定界符重合 → 反复命中同一位置 → 无限循环 |
| 10 | `tts/mod.rs:326:25 replace + with - in sentence_starts`（`end+1`） | `j=end-1` 回退 → 无限循环 |
| 11 | `tts/mod.rs:328:15 replace += with -= in sentence_starts`（收尾引号扫描） | j 回退 → 无限循环 |
| 12 | `tts/mod.rs:328:15 replace += with *= in sentence_starts`（收尾引号扫描） | j 不变 → 无限循环 |
| 13 | `tts/mod.rs:331:15 replace += with -= in sentence_starts`（空白跳过） | j 回退 → 无限循环 |
| 14 | `tts/mod.rs:331:15 replace += with *= in sentence_starts`（空白跳过） | j 不变 → 无限循环 |

**已澄清的伪超时**：`tts/mod.rs:321:13 replace < with <= in sentence_starts` 在全量并发（jobs=4）下与多个无限循环变异体争抢 CPU 被记为 timeout；隔离复核（jobs=1）同一行 3 个变异体 **3/3 caught**（`/tmp/opencode/mutants-321/mutants.out/caught.txt`），故不是存活体，已计入 caught。

## 5. 豁免清单（unviable，8 条，不计入分母）

> 全部为 cargo-mutants 生成的 `Default::default()` 替换，因目标类型**未实现 `Default`** 而编译失败（unviable），非存活、非等价，无需处理。

| # | 文件:行 | 变异 | 原因 |
|---|---|---|---|
| 1 | `tts/mod.rs:76:5` | `segment → Ok(vec![Default::default()])` | `SentenceChunk` 无 `Default` |
| 2 | `tts/mod.rs:136:5` | `locator_for_sentence → Ok(Default::default())` | `Locator` 无 `Default` |
| 3 | `tts/mod.rs:196:5` | `char_table → (vec![Default::default()], 0)` | 内部 `Ch` 无 `Default` |
| 4 | `tts/mod.rs:196:5` | `char_table → (vec![Default::default()], 1)` | 内部 `Ch` 无 `Default` |
| 5 | `api.rs:378:5` | `tts_segment → Ok(vec![Default::default()])` | `SentenceChunkView` 无 `Default` |
| 6 | `api.rs:399:5` | `tts_locator_for_sentence → Ok(Default::default())` | `LocatorView` 无 `Default` |
| 7 | `api.rs:364:5` | `to_locator_view → Default::default()` | `LocatorView` 无 `Default` |
| 8 | `api.rs:439:5` | `tts_listen_settings_get → Ok(Default::default())` | `ListenSettingsView` 无 `Default` |

## 6. 为杀死变异体补齐的测试（本阶段新增/加强）

- `core/src/tts/mod.rs`：新增 24 个用例（空/纯标点/`\r\n`/中英混排/单大写缩写/小数点/多重省略号/串尾省略号/UTF-16 代理对/区间连续/前导与句中空白/`snippet` 40 单元截断与代理对边界/`sentence_index_at` 边界与 NaN/Inf/越界/空白文本），并**直接覆盖内部辅助函数** `is_hard_end`/`is_closing`/`is_abbreviation`/`word_before`/`is_ascii_period_end`/`delimiter_end`/`sentence_starts`/`char_table`/`utf16_prefix`，使函数级语义变异（如串尾句点 `None` 分支）也被杀死。
- `core/src/library/mod.rs`：新增 `settings_forwarded_to_store_roundtrip`（薄转发落库）。
- `core/tests/tts_api.rs`（新增）：真实 EPUB 全链路覆盖 `chapter_text` 命中/空串/错章、`tts_segment`/`tts_locator_for_sentence`/`tts_sentence_index_at` 字段与错误路径、听书设置默认/往返/clamp/非有限值/空白过滤。

## 7. 结论

- 本 REQ 改动/新增 Rust 代码变异分数 **100%（127/127）**，严格含超时口径 **90.1%**，均 **≥80%** ✅
- 存活变异体 **0**，超时变异体 14 条全部给出结论（非终止变异体）✅
- 未发现真实缺陷 → **无 rework**，未修改任何业务代码。
- 全量回归见 `04-coverage.md` §5。
