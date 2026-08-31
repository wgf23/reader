<!-- wf-meta: req=REQ-002 | phase=testing | agent=test-engineer | date=2025-08-30 | gate=passed -->
# REQ-002 · 覆盖率报告（阶段4）

## 数据（cargo llvm-cov 0.9，`cargo llvm-cov --workspace`，2025-08-30；补测后终版）

| 口径 | 行覆盖 | 说明 |
|---|---|---|
| 全部文件 | 2347/3105（75.6%） | 含 frb_generated（0%）与 api.rs（0%，cargo 视角） |
| 排除生成代码 frb_generated | 2347/2590（90.6%） | |
| 排除生成代码 + api.rs（桥接胶水，FFI 端到端覆盖，REQ-001 先例豁免） | 2347/2508（93.6%） | |
| **REQ-002 新增代码（mobi_common.rs + mobi.rs + azw3.rs）** | **1063/1088（97.7%）** | **门槛 ≥85% ✅** |

### REQ-002 新增/相关文件逐文件行覆盖

| 文件 | 行覆盖 | 说明 |
|---|---|---|
| format/mobi_common.rs | 898/920（97.6%） | 解析内核（PalmDOC/编码链/sanitize/拆章/INDX/图片/TOC）；未覆盖为防御分支 |
| format/mobi.rs | 64/64（100.0%） | |
| format/azw3.rs | 101/104（97.1%） | 未覆盖 3 行为 KF8 rawml 解析失败回退的防御分支 |
| format/mod.rs | 59/87（67.8%，文件摘要口径） | REQ-002 新增（parse 分发两臂 + detect BOOKMOBI 增强）已覆盖；未覆盖为**既有**非本 REQ 分支（fb2/cbz/pdf 未实现臂、PK 嗅探、`looks_like_fb2`、`parse()` 无扩展名 or_else 兜底、`UnsupportedFormat` 臂） |
| error.rs | 0/3（0%） | 3 条未覆盖为**既有** `From<rusqlite::Error>`（非 REQ-002 新增）；`Encrypted` 变体为 thiserror 声明无可执行行，行为由 `drm_marked_mobi_returns_encrypted` 断言（Encrypted 变体 + Display 含 "DRM/加密"） |

## 未覆盖热点与结论

1. **mobi_common.rs 防御分支（约 25 行）**：`record_bytes` 越界返回空、`u16_be_at`/`u32_be` 越界返回 0、
   INDX 计数/边界/控制位防御、`decode_cp1252_or_gbk` 的 cp 已含 CJK 分支等 —— 均为畸形输入防御，
   经合法语料公开 API 不可达；变异阶段逐条给出结论（补测或等价豁免），非真实缺口。
2. **Huff 压缩分支**（mobi_common.rs `section_html` Huff 臂）：全部语料为 PalmDoc/No 压缩，
   Huff（HUFF/CDIC 记录）语料无法受控构造（需 HUFF 编码器，超出 calibre/合成能力）。
   → 变异阶段按"无可用语料、尽力而为降级线（01-req §5 风险7）"论证豁免。
3. **azw3.rs KF8 rawml 失败回退**（`parse_kf8_rawml` 返回 None 后的 L36 空语句）：KF8 判定为真但
   rawml 特征不成立 → 走回退段（both 型）路径已由合成测试覆盖；L36 本身是控制流汇合点。
4. **既有非本 REQ 缺口**（mod.rs 未实现格式臂、error.rs From<rusqlite>、epub.rs 极端畸形文件分支）：
   属其他格式/既有代码，不在 REQ-002 新代码口径内，不阻塞本闸门（与 REQ-001 报告口径一致）。

### 补测记录（本阶段新增，使新代码覆盖 95.1% → 97.4% → 97.7%）
- `synthetic_both_azw3_fallback_to_embedded_mobi7`：合成 both 型 AZW3（KF8 外层头 + 哑记录 +
  内嵌 MOBI7 回退段 + 间隔记录 + 图片记录），覆盖 azw3 路径2 兜底 + `mobi::parse_section` +
  `find_embedded_mobi7` 正向路径 + 回退段图片抽取（k=2）；
- `synthetic_azw3_drm_returns_encrypted`：azw3 DRM 标记 → Encrypted（US-3 的 azw3 侧）；
- `synthetic_mobi_language_falls_back_to_header_code`：无 EXTH 524 → header language_code 兜底
  （English→en / Chinese→zh）；
- `synthetic_azw3_short_embedded_header_returns_corrupt`：220B 短内嵌头 → Corrupt（US-3）；
- `synthetic_pdb_with_extra_bytes_excludes_trailing_junk`：PDB 记录表尾 extra 字段 ≠ 0 →
  record_bytes 排除尾填充（变异防护：extra_bytes/u16_be_at）；
- `synthetic_cp1252_mobi_accent_chars`：声明 CP1252 + é 高字节 → 无 FFFD（变异防护：enc 字段读取）；
- `synthetic_kf8_rawml_no_exth121_headingless`：KF8 判定仅凭 type==248（无 EXTH 121），
  无标题 rawml 仅 KF8 spine 路径可拆 ≥2 章（变异防护：mobi_type_u32）；
- mobi_common 单测：未知声明 + 合法 UTF-8 内容解码、sanitize 保留既有 DOCTYPE、INDX 位置线性映射、
  front-matter 位置映射、连续/尾随 pagebreak 拆章、0xc0 空格编码边界、`u16_be_at`/`u32_be`
  大端读取与越界守卫（变异防护：边界运算符）。

## 闸门4 自评（覆盖部分）
- [x] 新代码行覆盖率 ≥ 85%（**97.7%**，三新文件；mod.rs REQ-002 新增部分亦覆盖）
- [x] 关键分支（错误路径/边界）已覆盖：截断/垃圾/DRM 坏文件（Corrupt/Encrypted，mobi+azw3 双格式）、
  GBK/CP1252/UTF-8 解码链（含未知声明嗅探与 header 语言兜底）、pagebreak/标题双拆章与边界、
  INDX 目录映射（含线性映射语义）、图片魔数嗅探、无扩展名嗅探 Mobi/Azw3 区分、both 型 AZW3
  回退段（含图）、library 导入-打开-去重全链路；剩余未覆盖为防御/降级分支，逐条见上。
