<!-- wf-meta: req=REQ-006 | phase=testing | agent=test-engineer | date=2026-09-09 | gate=passed -->
# REQ-006 · 变异测试报告（闸门4①③）

> 输入：`03-review.md`（gate=passed）、代码（commit `e2e5798` + 本阶段测试补强）、`workflow/skills/mutants.md`、`workflow/rules/crap-config.toml`。
> 工具：cargo-mutants 27.1.0 / rustc 1.98.1 / Linux x86_64（12 核）。
> 范围：仅 REQ-006 变更的 Rust 生产代码（`core/src/dict/translation.rs`、`dict/provider.rs`、`dict/mod.rs`、`api.rs`、`store/translation.rs`），**排除** `frb_generated.rs`（生成物）。

---

## 1. 结果摘要

| 指标 | 数值 | 门槛 | 判定 |
|---|---|---|---|
| **变异分数** `killed/(killed+survived)` | **119 / 120 = 99.17%** | ≥80% | ✅ |
| 变异分数（timeout 计入分母的保守口径） | 119 / 122 = 97.54% | ≥80% | ✅ |
| killed / survived / timeout / unviable | **119 / 1 / 2 / 17** | — | — |
| 测试的变异体总数 | 139 | — | — |
| 存活体结论覆盖率 | **3 / 3 = 100%**（1 survived + 2 timeout 全部有结论） | 100% | ✅ |

> 说明：`unviable` 为注入后**无法编译**的变异体（如给无 `Default` 的类型返回 `Default::default()`），cargo-mutants 不计入分数。

---

## 2. 环境与命令

```bash
export PATH="$HOME/.cargo/bin:/usr/local/bin:$PATH"; export CARGO_BUILD_JOBS=2
cd /root/reader/core

# ① dict/translation.rs（整文件，含既有 DictService；任务授权）
cargo mutants --file src/dict/translation.rs --timeout 60 --jobs 4 \
  --output /tmp/opencode/mutants-req006-dict2

# ② dict/provider.rs + dict/mod.rs（key_is_missing 等）
cargo mutants --file src/dict/provider.rs --file src/dict/mod.rs --timeout 60 --jobs 4 \
  --output /tmp/opencode/mutants-req006-provider

# ③ api.rs 仅新增/改动函数（正则限定）
cargo mutants --file src/api.rs --re 'translate_get_config|translate_set_strategy|translate\b' \
  --timeout 60 --jobs 4 --output /tmp/opencode/mutants-req006-api2

# ④ store/translation.rs 默认策略
cargo mutants --file src/store/translation.rs \
  --re 'DEFAULT_PROVIDER|default_provider|set_default_provider' \
  --timeout 60 --jobs 4 --output /tmp/opencode/mutants-req006-store

# 超时体隔离复核（jobs=1, timeout=90）
cargo mutants --file src/dict/translation.rs \
  --re 'replace (== with !=|\+= with \*=) in DictService::unique_id' \
  --jobs 1 --timeout 90 --output /tmp/opencode/mutants-req006-timeout-check
```

- 报告落盘：`workflow/reports/mutants-req006/{dict,provider,api,store}-{caught,missed,timeout,unviable,outcomes,mutants}.{txt,json}`。
- `cargo-mutants` 不注入 `#[cfg(test)]` 代码（经 `outcomes.json` 复核：无任何变异体落在测试模块行号区间），故分数纯反映生产代码。
- ①③④ 在补齐阶段4测试后**重跑**，结论反映最终代码+测试状态。

---

## 3. 范围表

| # | 范围 | 变异体 | killed | survived | timeout | unviable | 说明 |
|---|---|---|---|---|---|---|---|
| ① | `core/src/dict/translation.rs`（整文件） | 102 | 87 | 1 | 2 | 12 | REQ-006 新增 `translate_routed`/`translate_auto`/`translate_explicit`/`config_view`/`set_strategy` + 既有 DictService |
| ② | `core/src/dict/provider.rs` + `dict/mod.rs` | 31 | 28 | 0 | 0 | 3 | `key_is_missing` 默认/DeepL 覆写、`needs_key`、`deepl_body`、`deepl_code` |
| ③ | `core/src/api.rs`（regex 限定） | 3 | 1 | 0 | 0 | 2 | `translate`/`translate_get_config`/`translate_set_strategy` |
| ④ | `core/src/store/translation.rs`（regex 限定） | 3 | 3 | 0 | 0 | 0 | `DEFAULT_PROVIDER`/`default_provider`/`set_default_provider` |
| — | **合计** | **139** | **119** | **1** | **2** | **17** | — |

---

## 4. 存活变异体分析（每个必须有结论）

| # | 文件:行 | 变异类型 | 结论 |
|---|---|---|---|
| 1 | `core/src/dict/translation.rs:351:16` | `replace > with >=` in `sanitize_id` | **等价变异 → 豁免**：当 `s.len() == 64` 时 `s.truncate(64)` 为空操作，与 `>` 分支不可区分；`>`→`<`（不截断 80 字符名）与 `>`→`==`（`==64` 对 80 字符为假）已被 `sanitize_id_truncates_overlong` 杀死。 |

## 5. 超时变异体清单（隔离复核 jobs=1 / timeout=90）

| # | 文件:行 | 变异类型 | 结论 |
|---|---|---|---|
| T1 | `core/src/dict/translation.rs:285:56` | `replace == with !=` in `DictService::unique_id` | **超时（死循环，非等价但不可在不挂起的前提下杀死）**：`any(id != candidate)` 在多词库场景恒真，`n` 无限递增/候选永不收敛。隔离复核仍 `Timeout`。原实现 `==` 正确，无生产缺陷。 |
| T2 | `core/src/dict/translation.rs:287:15` | `replace += with *=` in `DictService::unique_id` | **超时（死循环）**：变异为 `n *= 1`，`n` 恒为 2 → `candidate` 反复为已存在的 `foo_bar-2` → `while` 永不退出。隔离复核仍 `Timeout`。原实现 `+= 1` 正确，无生产缺陷。 |

> 两个超时体均位于**既有** `DictService::unique_id`（非 REQ-006 新增逻辑），且测试已能触发其不收敛行为（进程挂起）；受"不可让测试挂起"限制无法转为 killed，按 timeout 单列并给出结论。

---

## 6. 豁免清单

| 文件:行 | 变异 | 豁免理由 | 评审 |
|---|---|---|---|
| `core/src/dict/translation.rs:351:16` | `> with >=` | `len==64` 时 `truncate(64)` 为 no-op，行为完全等价 | 见本报告 §4；等价性可静态论证 |

> 存活体唯一（1 个）已 100% 给出结论并豁免；timeout 2 个已单列并结论。无"0 结论"存活体。

---

## 7. Unviable（无法编译）清单

共 17 个，均为"给无 `Default` 的类型返回 `Ok(Default::default())`"类注入，cargo-mutants 判定 unviable，不计分：

- `dict/translation.rs`（12）：`load_from_installed_dir`/`install`/`list`/`lookup`/`translate_cached`(×2)/`translate_routed`/`translate_auto`/`translate_explicit`/`config_view`/`cache_get_translation`/`translate`。
- `dict/provider.rs`（3）：`DeepLProvider/EchoProvider/OfflineProvider::translate`。
- `api.rs`（2）：`translate`/`translate_get_config`。

---

## 8. 缺陷触发的 rework

- [x] 无
- [ ] 有 → REWORK-REQ-006-D.md

> 本阶段**无生产代码缺陷**。唯一需要补的是**测试覆盖缺口**（非缺陷）：`api.rs:366 translate_set_strategy` 曾被 `Ok(())` 变异体存活（Rust 测试未调用该桥接函数），已补 `core/tests/translate_corpus.rs` 的 `translate_get_config`/`set_strategy` 往返 + 未知策略断言将其杀死（重跑 ③：1 caught / 0 survived）。属测试补强，不触发 rework-D。

---

## 9. 闸门4 自评

- [x] **变异分数 ≥ 80%**：99.17%（保守口径 97.54%）
- [x] **存活变异体 100% 有结论**：survived 1（等价豁免）+ timeout 2（死循环，隔离复核）全部有结论
- [x] 范围限定 REQ-006 变更代码，排除生成物 `frb_generated.rs`
- [x] 结论可审计：分数 / 存活清单（文件:行:类型:结论）/ 豁免 / timeout 隔离复核 / unviable 清单

**闸门4①③结论：通过（passed）。**
