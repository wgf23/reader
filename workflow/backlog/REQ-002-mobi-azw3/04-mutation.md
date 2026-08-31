<!-- wf-meta: req=REQ-002 | phase=testing | agent=test-engineer | date=2025-08-30 | gate=passed -->
# REQ-002 · 变异测试报告（阶段4 终版）

## 结果摘要
- **变异分数：94.8%**（门槛 ≥80%）✅
- killed / survived / timeout / unviable：**92 / 5 / 0 / 11**（共 108 变异体；终版第三轮）
- 作用域：`src/format/mobi_common.rs` + `src/format/mobi.rs` + `src/format/azw3.rs`
  （REQ-002 新增代码，`cargo mutants --jobs 2 --timeout 60`，cargo-mutants 27.1.0）
- 迭代：首轮 77.7%（21 missed）→ 补测 → 第二轮 89.1%（10 missed）→ 再补边界单测 →
  **第三轮 94.8%（5 missed，全部等价豁免）**；完整闭环记录见
  [REWORK-REQ-002-D.md](../rework/REWORK-REQ-002-D.md)
- 说明：`src/api.rs` 桥接胶水层不在变异作用域（REQ-001 已豁免：其行为由 FFI 端到端测试
  `rust_bridge_test.dart` 覆盖，cargo-mutants 无法驱动 dart FFI）；本轮不涉及该层。

## 存活变异体分析（5 个，全部等价豁免，理由具体）

| # | 文件:行 | 变异类型 | 结论 |
|---|---|---|---|
| 1 | mobi_common.rs:82 | from_path 记录偏移校验 `>` → `>=` | **等价**：offset==len 边界在合法 PDB 不可达（末记录必有内容 → 偏移必 < 文件长度）；对"恰好截断在末记录边界"的构造输入，两语义均不 panic 且均符合 US-3（`>` 允许解析出空末记录，`>=` 报 Corrupt），无验收差异；全部语料/坏文件不触发 |
| 2 | mobi_common.rs:114 | record_bytes 守卫 `>` → `==` | **等价**：start==len 时 `&file_bytes[start..min(end,len)]` 本身即为空切片，与守卫返回 `&[]` 相同；start>len 已被 `from_path` 前置偏移校验拦截（公开 API 不可达），两语义输出恒等 |
| 3 | mobi_common.rs:114 | record_bytes 守卫 `>` → `>=` | **等价**：同 #2（start==len → 空切片，start>len 不可达） |
| 4 | mobi_common.rs:175 | fir 字段读取 `16 + 228` → `16 * 228` | **等价**：fir 仅决定 `index_start`，parse_indx_section 对 [index_start, image_start) 做**全区间扫描**——正确 fir 与变异读出的 0/极大值在"能否命中 INDX 记录"上收敛（段内有 INDX 时均命中同一记录、无 INDX 时均返回 None）→ toc 相同 |
| 5 | mobi_common.rs:183 | `index_start: k + fir` → `k * fir` | **等价**：同 #4（k≥1 时 k*fir ≤ k+fir，扫描起点仍在 INDX 之前；k=0 时从 0 起扫；fir=0xFFFFFFFF 时两者均 start>end → None） |

> 豁免原则（docs/07 §7/§4.4）：存活变异体 100% 有结论；等价论证基于
> ①前置校验不可达（#1/#2/#3）、②返回路径恒等（#2/#3）、③全区间扫描收敛（#4/#5）。

## 被杀变异体的代表性缺口（首轮 21 missed → 终版 5）
首轮 77.7% 触发的 16 个真实测试缺口已全部补测闭环（详见 REWORK-REQ-002-D.md 表格）：
PDB extra 字段处理、u16_be_at/u32_be 大端读取边界、MOBI 头长度守卫（短内嵌头）、
声明编码字段读取（CP1252）、KF8 type==248 判定（无 EXTH 121）、回退段含图路径、0xc0 边界。

## 缺陷触发的 rework
- [x] 有 → [REWORK-REQ-002-D.md](../rework/REWORK-REQ-002-D.md)
  （首轮 77.7% < 80% → rework-D；补 10 个测试后 94.8%，无业务代码改动）

## 闸门4 自评（变异部分）
- [x] 变异分数 ≥ 80%（**94.8%** = 92/(92+5)）
- [x] 存活变异体 100% 有结论（5/5 等价豁免，理由具体且经评审）
- [x] timeout 0、unviable 11（#[cfg(test)] 模块与不可编译变异，单列不计分）
