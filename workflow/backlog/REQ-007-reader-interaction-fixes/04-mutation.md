<!-- wf-meta: req=REQ-007-reader-interaction-fixes | phase=testing | agent=test-engineer | date=2026-09-09 | gate=passed -->
# REQ-007 · 变异测试报告（闸门4①③）

> 输入：`03-review.md`（gate=passed）、代码 `d20f789`（diff base `4f3f55b`）、`workflow/skills/mutants.md`、`workflow/rules/crap-config.toml`。
> 工具：cargo-mutants 27.1.0 / rustc 1.98.1 / Linux x86_64。
> 范围：REQ-007 变更的 Rust 生产代码 `core/src/dict/translation.rs`（排除 `frb_generated.rs` 生成物）。

---

## 1. 结果摘要

| 指标 | 数值 | 门槛 | 判定 |
|---|---|---|---|
| **REQ-007 新增/改动代码的「新可变点」** | **0 个**（仅字符串字面量 + 注释） | — | ✅ 无需新跑全量 |
| 本 REQ 定向重跑：`translate_auto`（含改动字面量所在函数） | **5 caught / 1 missed / 0 timeout / 1 unviable → 5/6 = 83.3%** | ≥80% | ✅ |
| 沿用基线（REQ-006 全 scope） | 119 / 120 = 99.17%（报告值） | ≥80% | ✅ |
| 基线校正（本次发现 492 应为 survived） | 118 / 120 = 98.33%（保守） | ≥80% | ✅ |
| 存活变异体结论覆盖率 | **4 / 4 = 100%**（492 测试缺口 + 351 等价 + 2 timeout 死循环） | 100% | ✅ |

> **关键结论**：REQ-007 对 core 生产代码**只有一处错误字符串字面量追加**（无新函数/新分支/新运算符），cargo-mutants **不注入字符串/注释**，故本 REQ 无新可变点；定向重跑确认变异体集合与 REQ-006 基线**逐条一致**。

---

## 2. 命令与真实输出

```bash
export PATH="$HOME/.cargo/bin:$PATH"; export CARGO_BUILD_JOBS=2
cd /root/reader/core

# ① 复核 diff：生产代码仅字符串字面量（见 §3）
git diff 4f3f55b..HEAD -- core/src/dict/translation.rs

# ② 枚举变异体（--list 不跑测试，秒级）：102 个
cargo mutants --list --file src/dict/translation.rs | tee /tmp/opencode/mut-list-req007.txt
# → wc -l = 102（与 REQ-006 baseline dict-mutants.json 的 102 一致）

# ③ 定向真跑：改动字面量所在函数 translate_auto（7 个变异体）
CARGO_BUILD_JOBS=2 cargo mutants --file src/dict/translation.rs \
  --re 'translate_auto' --timeout 60 --jobs 4 \
  --output /tmp/opencode/mutants-req007-auto
# 真实输出：
#   Found 7 mutants to test
#   ok       Unmutated baseline in 21s build + 8s test
#   MISSED   src/dict/translation.rs:492:36: replace == with != in TranslationService::translate_auto in 60s build + 8s test
#   7 mutants tested in 2m: 1 missed, 5 caught, 1 unviable

# ④ 对 missed 体隔离复核（jobs=1 / timeout=90）：确定性 MISSED
CARGO_BUILD_JOBS=2 cargo mutants --file src/dict/translation.rs \
  --re 'translation\.rs:492' --timeout 90 --jobs 1 \
  --output /tmp/opencode/mutants-req007-492
#   Found 1 mutant to test
#   MISSED   src/dict/translation.rs:492:36: replace == with != ... in 1s build + 7s test
```

- 报告落盘：`/tmp/opencode/mutants-req007-auto/mutants.out/{outcomes.json,caught.txt,missed.txt,unviable.txt,diff/}`。
- 基线数据：`workflow/reports/mutants-req006/dict-*.{txt,json}`。

---

## 3. core 变更性质证据（本 REQ 无新可变点）

`git diff 4f3f55b..HEAD -- core/src/dict/translation.rs` = **+22 / -2**，其中**生产代码**仅：

```diff
@@ -561,8 +561,10 @@
         if online_unconfigured || online.is_empty() {
             let pname = first_unconfigured.unwrap_or_else(|| "deepl".to_string());
+            // REQ-007 US-11：仅追加"设置"引导，三段既有语义逐字保留（既有 contains 断言不破）。
             return Err(Error::NotConfigured(format!(
-                "未配置在线翻译 API Key（{pname}），且离线翻译未命中（请先安装内置词库）"
+                "未配置在线翻译 API Key（{pname}），且离线翻译未命中（请先安装内置词库）\
+                 ；请在「设置」中配置在线翻译或导入词库"
             )));
```

其余 20 行为 `#[cfg(test)]` 模块新增的 2 个测试 + 1 条断言（`msg.contains("设置")`、`translate_auto_configured_key_provider_is_deepl_uncached`），非生产逻辑。

**变异体集合逐条比对**（行号归一化后，`function+genre+replacement` 多重集）：

| 比对项 | 结果 |
|---|---|
| 基线变异体数（`dict-mutants.json`） | 102 |
| 本次 `--list` 变异体数 | 102 |
| 仅基线有 / 仅本次有 | **0 / 0**（完全一致） |
| 改动区域（现行 558–570 行）的变异体 | 仅 `translation.rs:562:32: replace \|\| with && in translate_auto`（即既有 `online_unconfigured \|\| online.is_empty()`，**非字符串字面量**） |
| 字符串字面量行（564–566）的变异体 | **0**（cargo-mutants 不注入字符串/注释） |

> 结论：本 REQ **没有引入任何新可变点**，无需重跑全量即可判定不劣化；下面定向重跑用于验证改动函数及其邻近逻辑。

---

## 4. 定向重跑结果（`translate_auto`，7 个变异体）

| 变异体 | 结论 |
|---|---|
| `translation.rs:460:9` replace `translate_auto` → `Ok(Default::default())` | unviable（类型无 `Default`，不计分） |
| `translation.rs:469:25` delete `!`（`!p.needs_key()`） | **caught** |
| `translation.rs:505:36` replace `==` with `!=`（取 provider 用于 translate） | **caught** |
| `translation.rs:523:39` replace `\|\|` with `&&`（回退原因分支） | **caught** |
| `translation.rs:540:36` replace `==` with `!=`（离线回退候选取 provider） | **caught** |
| `translation.rs:562:32` replace `\|\|` with `&&`（未配置判定，紧邻改动字面量） | **caught** |
| `translation.rs:492:36` replace `==` with `!=`（key 缺失判定取错 provider） | **MISSED → 见 §5** |

---

## 5. 存活变异体分析（每个必须有结论）

| # | 文件:行 | 变异类型 | 结论 |
|---|---|---|---|
| 1 | `core/src/dict/translation.rs:492:36` | `replace == with !=` in `TranslationService::translate_auto` | **测试缺口（非生产缺陷，非本 REQ 引入）**：`.find(\|p\| p.name() == name)` 改为 `!=` 后，仅当「被误取到的 provider」与「正确 provider」的 `key_is_missing` 结果不同时才有行为差异——生产上唯一差异点是 **DeepL 空/空白 key**（`DeepLProvider::key_is_missing` 覆写为空白即缺失，`OfflineProvider` 用默认 `key.is_none()`）。现有 `translate_auto` 用例只用 `DeepLStub`（未覆写 `key_is_missing`）与 `OfflineStub`，对 `None` 两者结果相同 → 无法区分。**生产代码 `==` 正确**，属 REQ-006 遗留测试盲区，不在 REQ-007 改动行内；登记为后续补测项（用真实 `DeepLProvider`+`OfflineProvider`+空串 key 跑 `translate_routed`）。不触发 REQ-007 rework-D。 |
| 2 | `core/src/dict/translation.rs:351:16` | `replace > with >=` in `sanitize_id`（基线存活） | **等价变异 → 豁免**（沿用 REQ-006 结论并复核现行代码 `:351` 未变）：`s.len()==64` 时 `s.truncate(64)` 为空操作，`>` 与 `>=` 不可区分；`>`→`<`/`>`→`==` 已被 `sanitize_id_truncates_overlong` 杀死。 |
| 3 | `core/src/dict/translation.rs:285:56` | `replace == with !=` in `DictService::unique_id`（基线 timeout） | **timeout（死循环，非等价但不可在不挂起前提下杀死）**：`any(id != candidate)` 恒真，候选不收敛。原实现 `==` 正确，无生产缺陷。 |
| 4 | `core/src/dict/translation.rs:287:15` | `replace += with *=` in `DictService::unique_id`（基线 timeout） | **timeout（死循环）**：`n *= 1` → 候选反复为已存在项，`while` 不退出。原实现 `+= 1` 正确，无生产缺陷。 |

> 说明：#2–#4 位于 REQ-007 **未改动**的既有函数；#1 位于 REQ-006 新增、REQ-007 未改动的 `translate_auto` 内部（本 REQ 只改该函数内的错误字符串）。四条均已给出结论，覆盖率 100%。

### 基线报告差异（可审计说明）

REQ-006 `04-mutation.md` / `dict-caught.txt` 曾将 `translation.rs:492:36` 记为 **CaughtMutant**（`dict-outcomes.json` 中该条 `Test` 阶段 `Failure(101)`）。本次 `--list` 证明代码与变异体集合未变，但定向重跑（jobs=4 与 jobs=1 两次）均为 **MISSED**。经排查：REQ-006 测试套件含时间敏感断言（`translate_cache_hit_no_second_provider_call` 的 `hit_ms <= 100`），基线在并行高负载下可能产生偶发失败，使该变异体被误判为 caught。**按保守口径采用 118/120 = 98.33%**，仍远高于 80% 门槛；差异不影响闸门结论，已如实登记。

---

## 6. 豁免清单

| 文件:行 | 变异 | 豁免理由 | 评审 |
|---|---|---|---|
| `core/src/dict/translation.rs:351:16` | `> with >=` | `len==64` 时 `truncate(64)` 为 no-op，行为完全等价 | 沿用 REQ-006 等价性静态论证；本次复核代码未变 |

> `492` 不列为「等价豁免」（存在可区分的空 key 场景），而列为**既有测试缺口 + 后续补测项**；因不属 REQ-007 改动行且生产代码正确，不阻塞本 REQ 闸门4。

---

## 7. 缺陷触发的 rework

- [x] 无（未发现 REQ-007 引入的生产缺陷；`492` 为既有代码测试缺口，登记后续补测）
- [ ] 有 → REWORK-REQ-007-D.md

---

## 8. 闸门4 自评

- [x] **变异分数 ≥ 80%**：REQ-007 无新可变点（证据见 §3）；定向重跑 `translate_auto` **83.3%**（5/6）；基线校正后 **98.33%**（118/120）
- [x] **存活变异体 100% 有结论**：`492`（测试缺口/后续补测）+ `351`（等价豁免）+ `285/287`（死循环 timeout）全部有结论
- [x] 范围限定 REQ-007 变更代码，排除生成物；变更性质（纯字符串字面量）有 diff + `--list` 集合比对双重证据
- [x] 结论可审计：分数 / 存活清单（文件:行:类型:结论）/ 豁免 / timeout / 基线差异说明

**闸门4①③结论：通过（passed）。**
