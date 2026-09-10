<!-- wf-meta: req=REQ-009-notes-search | phase=testing | agent=test-engineer | date=2026-09-09 | gate=passed -->
# REQ-009 · 变异测试报告（闸门4①③）

> 输入：`03-review.md`（gate=passed，commit `3b8af1d`）、代码（含本阶段补测）、`workflow/skills/mutants.md`、`workflow/skills/gates.md`。
> 工具：cargo-mutants 27.1.0 / rustc 1.98.1 / Linux x86_64（12 核）。
> 范围：REQ-009 变更的 **8 个 Rust 生产文件**（`types.rs`、`store/mod.rs`、`store/annotations.rs`、
> `store/search_index.rs`、`locator/mod.rs`、`notes/mod.rs`、`search/mod.rs`、`api.rs`），
> **排除** `frb_generated.rs`（FRB 生成物）。
> 原始数据：`workflow/reports/mutants-req009/core-domain/mutants.out/`（域+仓储 7 文件）、
> `workflow/reports/mutants-req009/api-inplace/mutants.out/`（api 桥接）。

---

## 1. 结果摘要

| 指标 | 数值 | 门槛 | 判定 |
|---|---|---|---|
| **变异分数（域+仓储 7 文件）** | **339 / (339+12) = 96.58%** | ≥80% | ✅ |
| **变异分数（`api.rs` REQ-009 桥接）** | **25 / (25+0) = 100%** | ≥80% | ✅ |
| **合计变异分数** `killed/(killed+survived)` | **364 / (364+12) = 96.81%** | ≥80% | ✅ |
| killed / survived / timeout / unviable（合计） | **364 / 12 / 0 / 42** | — | — |
| 测试的变异体总数 | **418**（379 + 39） | — | — |
| **存活体结论覆盖率** | **12 / 12 = 100%**（11 等价豁免 + 1 既有代码，均有结论） | 100% | ✅ |
| timeout 变异体 | **0** | — | — |

> `unviable` = 注入后**无法编译**的变异体（如给无 `Default` 的类型返回 `Ok(Default::default())`、
> 给无 `Default` 的服务返回 `Ok(Box::leak(...))`），cargo-mutants 不计入分数。

---

## 2. 环境与命令（可复现）

```bash
export PATH="/root/flutter/bin:/root/.cargo/bin:$PATH"
export TMPDIR=/root/mutants-tmp          # 关键：/tmp 为 7.5G tmpfs，cargo-mutants 复制 target 会撑爆
cd /root/reader/core

# ① 域+仓储 7 文件（in-place，避免复制 2.9G target；过滤到本模块单测提速）
cargo mutants --in-place \
  --file src/types.rs --file src/store/mod.rs --file src/store/annotations.rs \
  --file src/store/search_index.rs --file src/locator/mod.rs \
  --file src/notes/mod.rs --file src/search/mod.rs \
  --timeout 120 --output /root/reader/workflow/reports/mutants-req009/core-domain \
  -- --lib -- notes::tests:: search::tests:: locator::tests:: \
     store::annotations::tests:: store::search_index::tests:: \
     store::tests:: types::tests::
# 379 mutants：336 caught / 15 missed / 28 unviable

# ② 对 ① 的 15 个 missed 用补测后的测试重跑（--iterate 跳过已 caught）
cargo mutants --in-place --iterate \
  --file src/types.rs --file src/store/mod.rs --file src/store/annotations.rs \
  --file src/store/search_index.rs --file src/locator/mod.rs \
  --file src/notes/mod.rs --file src/search/mod.rs \
  --timeout 120 --output /root/reader/workflow/reports/mutants-req009/core-domain \
  -- --lib -- notes::tests:: search::tests:: locator::tests:: \
     store::annotations::tests:: store::search_index::tests:: \
     store::tests:: types::tests::
# 15 mutants：3 caught / 12 missed（最终存活 12）

# ③ api.rs 仅 REQ-009 桥接函数（regex 限定），in-place + 端到端 api 测试
cargo mutants --in-place --file src/api.rs \
  --re 'notes_|search|ensure_indexed|indexed_chapters|domain_scope|books_in_scope|chapter_titles|book_title_of|to_annotation_view|to_group_view|to_hit_view|library_open|library_import|book_open' \
  --timeout 120 --output /root/reader/workflow/reports/mutants-req009/api-inplace \
  -- --test notes_search_api
# 39 mutants：25 caught / 0 missed / 14 unviable
```

### 2.1 环境坑与处置（如实登记）

- 首轮在默认 `/tmp`（7.5G tmpfs）跑 `--jobs 4`：每个 job 复制 `core/target`（约 2.9–4.1G），
  4 job 撑爆 tmpfs → 出现 `No space left on device`，把大量变异体**误判为 unviable**。
  已删除该轮结果、`TMPDIR` 改到根盘（38G 可用）并改用 `--in-place`（不复制 target、增量编译），
  重跑后结果稳定可复现。**报告只采用重跑后的有效数据。**
- `scripts/mutants.sh` 会 `source $TC/env.sh`，本环境 `TC` 不存在 → 按任务指引直接运行 `cargo mutants`。
- 测试耗时受并发影响：最终采用 `--in-place`（单 worker）+ 模块过滤（51 个单测，约 1s），
  单变异体约 4s，全量约 28 分钟。
- ② 的 15 个 missed 是 ① 的**同一批变异体**（`--iterate` 只重跑 missed），非新增；合计分数按
  339 caught（336+3）/ 12 missed 计算，无重复计数。

---

## 3. 范围表

| # | 范围 | 变异体 | killed | survived | timeout | unviable |
|---|---|---|---|---|---|---|
| ① | 域+仓储 7 文件（`types`/`store/mod`/`annotations`/`search_index`/`locator`/`notes`/`search`） | 379 | 339 | 12 | 0 | 28 |
| ② | `api.rs`（REQ-009 桥接函数，regex 限定） | 39 | 25 | 0 | 0 | 14 |
| — | **合计** | **418** | **364** | **12** | **0** | **42** |

逐文件存活分布：`locator` 3、`notes` 2、`search` 1、`store/mod` 5、`store/annotations` 1、`api` 0。

---

## 4. 存活变异体分析（12 个，每个必须有结论）

| # | 文件:行 | 变异类型 | 结论 |
|---|---|---|---|
| 1 | `core/src/locator/mod.rs:61:19` | `replace += with *=` in `from_selection` | **等价/不可达**：位于「归一化无命中 → 原始精确匹配兜底」块。对任意非空 needle，`N(text)` 必含 `N(needle)`（空白折叠+ASCII 小写是子串保持的），故归一化分支总能给出候选，原始兜底块**不可达**（防御性代码）。 |
| 2 | `core/src/locator/mod.rs:65:64` | `replace + with -` in `from_selection` | **等价/不可达**：同上（原始兜底块内 `offsets[start + len]`）。 |
| 3 | `core/src/locator/mod.rs:65:64` | `replace + with *` in `from_selection` | **等价/不可达**：同上。 |
| 4 | `core/src/notes/mod.rs:308:40` | `replace - with +` in `civil_from_days` | **等价（有效日期域）**：`z - 146_096` 仅在 `z<0`（公元前）分支使用。对公元 1–9999 年逐日暴力比对（2,932,897 天）**零差异**；`format_unix` 输入为笔记时间戳（正 unix 秒），该分支生产不可达。 |
| 5 | `core/src/notes/mod.rs:308:40` | `replace - with /` in `civil_from_days` | **等价（有效日期域）**：同 #4（同一分支、同一暴力验证）。 |
| 6 | `core/src/search/mod.rs:132:21` | `replace > with >=` in `extract_snippet` | **等价**：`if ws.len() > 1 { 分词 } else { vec![query] }`；当 `ws.len()==1` 时两分支产物相同（均为 `[query]`），`>=` 与 `>` 行为一致。 |
| 7 | `core/src/store/mod.rs:247:9` | `integrity_check -> Ok(true)` | **既有代码（非 REQ-009 引入）**：`git diff main` 未改该函数。要杀死需构造损坏的 SQLite 文件（`PRAGMA integrity_check` 返回非 "ok"），属破坏性/平台相关构造，风险高于收益；由 `store/mod.rs` 的 `integrity_check_passes_on_fresh_db` 覆盖正路径。 |
| 8 | `core/src/store/mod.rs:268:16` | `replace < with <=` in `migrate_conn`（v1） | **等价**：`if version < 1` 的迁移块全为 `CREATE TABLE IF NOT EXISTS` + `PRAGMA user_version=1`；`version==1` 时重复执行是幂等 no-op，无可观察差异。 |
| 9 | `core/src/store/mod.rs:292:16` | `replace < with <=` in `migrate_conn`（v2） | **等价**：同 #8（`reading_progress` 幂等 DDL）。 |
| 10 | `core/src/store/mod.rs:306:16` | `replace < with <=` in `migrate_conn`（v3） | **等价**：同 #8（`translation_cache`/`settings` 幂等 DDL）。 |
| 11 | `core/src/store/mod.rs:331:16` | `replace < with <=` in `migrate_conn`（v4，REQ-009） | **等价**：REQ-009 的 `if version < 4` 块全为 `CREATE TABLE IF NOT EXISTS` + `CREATE VIRTUAL TABLE IF NOT EXISTS` + `PRAGMA user_version=4`；`version==4` 时重复执行幂等，`v3_to_v4_migration_idempotent_and_preserves_data` 已证重复开库 no-op。 |
| 12 | `core/src/store/annotations.rs:191:87` | `replace < with <=` in `find_bookmark` | **等价**：`((p*1000).round()/1000 - target).abs() < 1e-6`；浮点差值恰等于 `1e-6` 为测度零，且 `round(…,3)` 后差值只有 0 或 ≥1e-3 两档，`<=` 与 `<` 对可观察输入不可区分。 |

> **结论：12/12 存活体均有结论**，其中 11 个为可静态论证的等价/不可达变异（豁免清单见 §5），
> 1 个为既有代码（`integrity_check`，非本 REQ 引入）。**无「无结论」存活体，无真缺陷。**

---

## 5. 豁免清单（等价/不可达，评审用）

| 文件:行 | 变异 | 豁免理由 | 等价性依据 |
|---|---|---|---|
| `core/src/locator/mod.rs:61:19` | `+=` → `*=` | 原始兜底块不可达 | `N(text) ⊇ N(needle)` 对任意子串成立（归一化保序、折叠空白、ASCII 小写） |
| `core/src/locator/mod.rs:65:64` | `+` → `-` / `*` | 同上 | 同上 |
| `core/src/notes/mod.rs:308:40` | `-` → `+` / `/` | `z<0`（公元前）分支生产不可达 | 公元 1–9999 年逐日暴力比对零差异（2.93M 天） |
| `core/src/search/mod.rs:132:21` | `>` → `>=` | 单元素分支两路等价 | `ws.len()==1` 时 `split` 与整体查询产物相同 |
| `core/src/store/mod.rs:268/292/306/331` | `<` → `<=` | 迁移块幂等 | 全 `CREATE ... IF NOT EXISTS` + 固定 `PRAGMA user_version` |
| `core/src/store/annotations.rs:191:87` | `<` → `<=` | 浮点差值不可达边界 | `round(,3)` 后差值为 0 或 ≥1e-3 |

**既有代码豁免（非本 REQ）**：`core/src/store/mod.rs:247` `integrity_check -> Ok(true)`
（`git diff main` 未改动该函数；正路径已覆盖）。

---

## 6. 本阶段为杀死变异体补充的测试

| 文件 | 新增用例 | 杀死的变异体（示例） |
|---|---|---|
| `core/src/types.rs` | 3 | `Lang/NoteKind/ExportFormat` 的 `parse`/`as_str`/`ext` 全 arm（此前 19 个存活） |
| `core/src/locator/mod.rs` | 6 | `text_at` 的 `>`/`>=`、`progression ==`/`/`、并列 `<`/`<=`、needle 超长/等长（`find_all` 的 `>`/`||`） |
| `core/src/notes/mod.rs` | 4 | `color` 的 `!`、`delete_many/delete_all` 的 `Ok(0/1)`、`toggle_bookmark` 的 `!`、`now_unix`、`civil_from_days` 漂移项 |
| `core/src/search/mod.rs` | 4 | `eq_ci` 的 `&&`、`find_ci` 的 `||`/`>`、`extract_snippet` 的 `>`/`&&`、`index_book`/`is_indexed` 委托 |
| `core/src/store/annotations.rs` | 2 | `delete -> Ok(())`、`delete_all` 的 `+=` |
| `core/src/store/search_index.rs` | 1 | `scope_clause` 的 `+=`（book_id+formats 组合占位符） |
| `core/src/store/mod.rs` | 2 | `cache_dir`/`dicts_dir -> Default::default()` |
| `core/tests/notes_search_api.rs` | 1（集成） | `api.rs` 的 `chapter_titles`/`book_title_of`/`domain_scope`/`books_in_scope`/`ensure_indexed`/`notes_delete` 等（此前 6 个存活 → 重跑 0 存活） |

> 测试补强**只增不改**：既有断言零削弱；无空断言。`api.rs` 此前 Rust 侧 0 测试覆盖，
> 新增 `core/tests/notes_search_api.rs` 端到端驱动后 6 个存活体全部被杀，重跑 **25 caught / 0 missed**。

---

## 7. Unviable（无法编译）清单（42 个，不计分）

- **域+仓储 28 个**：主要为对无 `Default` 的类型返回 `Ok(Default::default())`
  （如 `SearchRow`、`Vec<SearchRow>` 的 `vec![Default::default()]`）、对无 `Default` 的服务返回
  `Ok(Box::leak(Box::new(Mutex::new(Default::default()))))`、以及 `replace … -> Result<…> with Ok(())`
  在签名/借用不成立时的编译失败。
- **`api.rs` 14 个**（完整清单见 `workflow/reports/mutants-req009/api-inplace/mutants.out/unviable.txt`）：
  `notes_service`/`search_service` 的 `Box::leak(Default)`、`library_import`/`book_open`/
  `notes_create`/`notes_list`/`notes_resolve`/`notes_export`/`notes_toggle_bookmark`/`search` 的
  `Ok(Default::default())`、`to_annotation_view`/`to_group_view`/`to_hit_view` 的 `Default::default()`、
  `indexed_chapters` 的 `Ok(vec![Default::default()])`——对应 view 类型未实现 `Default`，注入后无法编译。

---

## 8. 缺陷触发的 rework

- [x] **无**（本阶段未发现生产代码缺陷）
- [ ] 有 → `REWORK-REQ-009-D.md`

> 本阶段所有测试补强均为**提升边界/异常覆盖与杀死变异体**，未修改任何生产逻辑。
> 未触发 rework-D。

---

## 9. 闸门4①③自评

- [x] **变异分数 ≥ 80%**：域+仓储 **96.58%**（339/351）、`api.rs` **100%**（25/25）、
      合计 **96.81%**（364/376）；timeout 0
- [x] **存活变异体 100% 有结论**：12 个存活体全部给出结论（11 等价/不可达豁免 + 1 既有代码），
      豁免依据含暴力比对/幂等论证/不可达证明
- [x] 范围限定 REQ-009 变更的 Rust 生产代码，排除生成物 `frb_generated.rs`
- [x] 结论可审计：分数 / 命令 / 范围表 / 存活清单（文件:行:类型:结论）/ 豁免清单 / unviable 清单 / 环境坑登记
- [x] 全量回归绿（Rust 282 + Dart 292 + 集成 2 + analyze 0），既有断言零削弱

**闸门4①③结论：通过（passed）。**
