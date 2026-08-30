<!-- wf-meta: req=REQ-001 | phase=testing | agent=test-engineer | date=2025-08-30 | gate=passed -->
# REWORK-REQ-001-D · 变异测试缺陷修复记录（rework-D）

## 触发
阶段 4 变异测试（cargo-mutants，作用域 src/library/mod.rs + src/store/mod.rs，44 变异体）
首轮结果：27 caught / 9 missed → **变异分数 75%，低于 80% 门槛** → 触发 rework-D。

## 存活变异体分析（首轮 9 个）

| # | 位置 | 变异 | 判定 | 处置 |
|---|---|---|---|---|
| 1 | library/mod.rs:38 | `==`→`!=`（import_file 去重） | **真测试缺口** | 新增 `dedup_returns_existing_book_when_multiple_books`（两本不同书存在时去重须返回正确既有记录）→ 已杀 |
| 2 | library/mod.rs:120 | `remove` → `Ok(())` | **真测试缺口** | 新增 `library_remove_deletes_book`（删除后列表空、打开失败）→ 已杀 |
| 3 | store/mod.rs:58 | `cache_dir` → `Default` | **真测试缺口** | 新增独立断言 `cache_dir == data/cache`（与实现无关的期望路径）→ 已杀 |
| 4 | store/mod.rs:257 | `now_unix` → `0/1/-1`（3 个） | **真测试缺口** | 新增 `timestamps_are_real`（added_at/updated_at > 1e9）→ 已杀 |
| 5 | store/mod.rs:66 | 迁移 `version < 1`→`<= 1` | **等价变异** | 豁免：DDL 全部 `IF NOT EXISTS` 幂等，重复执行无副作用，行为等价 |
| 6 | store/mod.rs:91 | 迁移 `version < 2`→`<= 2` | **等价变异** | 豁免：同上 |
| 7 | store/mod.rs:248 | `integrity_check` → `Ok(true)` | **等价变异** | 豁免：健康库路径已测；损坏库在 `open()` 的迁移阶段即失败（API 前置校验），`integrity_check=false` 分支经公开 API 不可达 |

## 修复与复验
- 新增 4 个测试（含 3 个变异杀死的断言组），`cargo test` 24 单测 + 5 语料全绿；
- 复跑变异：**44 mutants → 33 caught / 3 missed（全部为等价豁免）/ 8 unviable**；
- **变异分数 = 33 / (33+3) = 91.7% ≥ 80%** ✅

## 结论
- 修复 6 个真实测试缺口（3 个缺失测试场景 + 时间戳/路径断言），豁免 3 个等价变异（理由如上，评审通过）。
- 无行为缺陷需改代码；测试质量显著提升（75% → 91.7%）。
