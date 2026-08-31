<!-- wf-meta: req=REQ-002 | phase=delivery | agent=release-manager | date=2025-08-30 | gate=passed -->
# REQ-002 · 交付与发布说明（MOBI/AZW3 解析）

## 1. 验证结果汇总

**全量回归（release-manager 于阶段5 逐项实测，2025-08-30；WSL 降载 CARGO_BUILD_JOBS=2 下执行）**

| 回归项 | 命令 | 结果 | 说明 |
|---|---|---|---|
| Rust 全量测试 | `cd core && cargo test --all-targets` | ✅ **88 项全绿，0 失败** | 62 单测 + 21 mobi/azw3 集成（`tests/mobi_azw3.rs`）+ 5 p0 语料（`tests/p0_corpus.rs`）；`tests/integration.rs` 0 用例（空壳，无断言）；epub/txt/library 既有断言零回归 |
| CRAP 评分 | `crap scan core/src --cov workflow/reports/coverage.json --out workflow/reports/crap-req002-final.md` | ✅ **FAIL=0，WARN=5，PASS=161** | 5 个 WARN 全部为**既有代码**（epub.rs parse_metadata 21.8 / html_to_text 19.7 / parse_nav_xhtml 18.6 / parse_ncx 20.2、convert canonicalize 23.1），均 <25 阈值且非本 REQ 变更面；**REQ-002 新代码（mobi_common/mobi/azw3）全 PASS**（阶段4 终版 coverage.json 匹配后，阶段3 报告的 mobi_common N/A-cov WARN 已消除） |
| DDD / 分层合规 | `ddd-lint check . --rules workflow/rules/ddd-rules.toml --out workflow/reports/ddd-req002-final.md` | ✅ **违规=0** | domain 层 `core/src/format` 无 `crate::store\|api\|library` 依赖（ADR 决策1 约束） |
| release 构建 | `cd core && CARGO_BUILD_JOBS=2 cargo build --release` | ✅ 成功 | 产出 `core/target/release/libreader_core.so`（6.4MB，供 FFI） |
| Flutter 静态检查 | `cd app && flutter analyze` | ✅ **0 问题** | — |
| Flutter 测试 | `cd app && flutter test` | ✅ **5 用例全绿** | widget/library_page/reader_page 用例；`rust_bridge_test.dart`（FFI）在默认路径下按设计跳过（未指定 .so），不视为失败 |
| FFI 端到端 | `READER_CORE_SO=../core/target/release/libreader_core.so flutter test test/rust_bridge_test.dart` | ✅ **1 用例全绿** | 桥接全链路（导入→章节文本/HTML→资源→进度往返）经真实 .so 验证 |

**闸门 1–5 状态**：闸门1（需求）、闸门2（架构/ADR/计划）、闸门3（CRAP/DDD/测试）、闸门4（变异 94.8% / 覆盖 97.7%）均 ✅（上游产物确认）；**闸门5 本次执行 ✅**（见文末自评）。

**阶段4 质量数据（本次回归复核，未重跑）**：变异分数 **94.8%**（92 killed / 5 survived 全等价豁免 / 11 unviable，门槛 ≥80%）；新代码行覆盖 **97.7%**（mobi_common 97.6% / mobi 100% / azw3 97.1%，门槛 ≥85%）；rework-D 已闭环（77.7% → 94.8%，16 测试缺口补齐、5 等价豁免，无业务代码改动）。

## 2. 变更说明（面向用户/开发）

**面向用户**：
- `.mobi`（MOBI7）与 `.azw3`（AZW3/KF8）文件现在可以**导入书库、打开阅读、按章节翻页、目录跳转**（"导入 → 打开 → 读章节"全链路打通，复用既有规范 EPUB 缓存管线，二次打开秒开）；
- 中文书籍支持 UTF-8 / **GBK(936)** / Big5 / CP1252 编码解码，正文无乱码、无 U+FFFD 替换符；
- 含图书籍的**插图**随章节显示（MOBI 内嵌图片记录抽取，`kindle:embed:` 引用重写为规范资源路径）；
- 目录（TOC）按书内 INDX 目录还原，无有效目录时回退为按章节标题生成；
- **DRM/加密**文件导入时给出明确提示"文件可能受 DRM/加密保护"（`Error::Encrypted`），不再含糊地报"损坏"；
- 损坏/截断/伪装文件返回结构化错误（`Error::Corrupt`），**任何输入不崩溃（不 panic）**；
- 既有 EPUB/TXT 导入与阅读行为**零变化**（parse 仅新增两分支）。

**面向开发**：
- 新增 `core/src/format/mobi_common.rs`（domain 层解析内核：PDB 薄封装、自研 PalmDOC LZ77 解压、encoding_rs 解码链、HTML 清洗、`<mbp:pagebreak/>`/标题双拆章、INDX 解析、图片抽取与魔数嗅探），`mobi.rs`/`azw3.rs` 由空 stub 实现完整管线（AZW3 双路径：KF8 rawml 尽力而为 + MOBI7 回退段兜底）；
- `format/mod.rs`：`parse()` 新增 `Format::Mobi | Format::Azw3` 两臂；`detect_format` 的 `BOOKMOBI` 分支按 MOBI 头 type（==248 → Azw3）区分无扩展名嗅探；
- `error.rs` 新增 `Encrypted` 变体（对齐 docs/03 §8 错误分类）；`api.rs` 经泛型 `err_msg(Display)` 自动透出文案，**桥接零新增函数**；
- `convert/library/api` **零改动**（回归验证）；ddd-rules.toml 无需修改；
- 新增语料 6 个（真实 MOBI7 ×3 + 构造坏文件 ×3）落 `core/tests/corpus/src/` 并登记来源/sha256。

## 3. 已知问题与限制

1. **真实 KF8/AZW3 语料缺口（已登记，不阻塞）**：Gutenberg "kf8" 下载（24264/1342）实测均为 MOBI7（type=2、PalmDoc、无 RESC/BOUNDARY/EXTH121），本环境无 calibre 无法生成 both/KF8-only 真实 AZW3 → **留待开发机 calibre 生成后补录**（corpus README 已知缺口节）。AZW3 路径当前由「.mobi 语料复制为 .azw3 扩展名的分发测试（`mobi_content_as_azw3_by_extension`）+ 合成 KF8 rawml 集成测试（`synthetic_kf8_rawml_*`）+ `detect_format` 构造头单测」覆盖；US-2 按**可观察行为兜底条款**验收（01-req §5 风险1），不承诺内部路径。
2. **Huff（HUFF/CDIC）压缩分支**：全部语料为 PalmDoc/No 压缩，Huff 语料需 HUFF 编码器无法受控构造 → 按"尽力而为降级线"（01-req §5 风险7）论证，Huff 臂走 mobi crate 受限路径，覆盖报告已逐条说明（04-coverage §2）。
3. **INDX 目录**：KindleGen "IDXT" 变体标签为数字位置串（无意义）→ `parse_indx` 按经典 TAGX 格式实现，失败/标签全数字 → `None` → 章节标题回退（US-5 明确允许）；真实 calibre MOBI 语料补录后可强化经典 INDX 断言。
4. **图片身份为尽力而为**：`kindle:embed:NNNN` 为十六进制编号（与记录序无简单对应），sanitize 按十六进制映射到抽取图片（越界保留原样）；真实语料断言资源条数与 JPEG 魔数（165 张），**精确哈希断言用合成语料**。
5. **真机验收项**：本 REQ **无新增**真机数值验收项（US-6 为桌面基准，本环境可测；导入/打开本就在后台任务既有能力）；REQ-001 遗留的真机待办（55fps/首屏 <500ms）为 REQ-001 交付项，与本 REQ 无关，不重复登记。
6. **rework-D 遗留**：已闭环无遗留；5 个存活变异体全部等价豁免（前置校验不可达/返回路径恒等/全区间扫描收敛，理由见 04-mutation.md 与 REWORK-REQ-002-D.md）。

## 4. 追溯矩阵（闭合）

| 验收标准（01-req.md） | 设计（02-*） | 代码（文件） | 测试证据（测试名/报告） | 闭合 |
|---|---|---|---|---|
| **US-1 MOBI7 解析正确性**：`format==Mobi`、title 精确一致、authors 非空、language 与 EXTH 一致、`chapters.len()≥2` 且首章边界在页断点/标题处、拼接文本逐字含已知句子；`toc[0]` 与语料目录首条一致、depth 合法 | 02-adr 决策1（mobi crate 内核）/决策2（pagebreak 主+标题回退）/决策4（解析器内清洗）；02-design §2.1/§2.2/§3 填充约定/§4.1 时序 | `format/mobi_common.rs`（PdbBook/palmdoc_decompress/sanitize_html/split_chapters/parse_indx/first_heading）、`format/mobi.rs`（parse/chapters_and_toc）、`format/mod.rs`（Mobi 分发臂） | `corpus_hongloumeng_mobi_pagebreak_split`（format==Mobi、title=紅樓夢、34 pagebreak 拆 35 章、language=zh、无 U+FFFD）；`corpus_pride_and_prejudice_mobi_heading_split_with_images`（66 h2 标题拆 68 章、正文含 "It is a truth universally acknowledged"）；`synthetic_mobi_full_pipeline`（EXTH 元数据+pagebreak+INDX→toc 断言）；`corpus_hongloumeng_images_mobi`（无 pagebreak/标题→单章兜底路径） | ✅ |
| **US-2 AZW3/KF8 解析正确性**：`format==Azw3`、元数据正确、`chapters.len()≥1`、含图时 `resources` 有 `image/` 条目；KF8-only 不报错且正文含已知句子；无扩展名内容嗅探区分 Mobi/Azw3 | 02-adr 决策3（KF8 优先+回退段兜底）；02-design §2.3（parse_kf8_rawml/parse_fallback/is_kf8）/§4.2 时序；02-plan 语料表（KF8 缺口处置） | `format/azw3.rs`（parse 双路径）、`format/mobi_common.rs`（from_embedded/find_embedded_mobi7）、`format/mod.rs`（detect_format type==248→Azw3、`looks_like_pdb` 偏移 60 兼容） | `synthetic_kf8_rawml_azw3`（type=248+EXTH121→Format::Azw3、章节文本断言）；`synthetic_kf8_rawml_no_exth121_headingless`（KF8-only、无标题 rawml 拆 ≥2 章）；`synthetic_both_azw3_fallback_to_embedded_mobi7`（both 型回退段+图片资源）；`mobi_content_as_azw3_by_extension`（.azw3 分发）；`detect_format_sniffs_mobi_vs_azw3_by_type`（无扩展名嗅探区分） | ✅（真实 KF8 语料缺口已登记 corpus README，按可观察行为兜底条款验收，见 §3.1） |
| **US-3 错误输入不崩溃（结构化错误）**：截断/损坏/伪装 → `Err(Corrupt)` 不 panic；DRM 标记 → `Err` 且消息含"DRM/加密" | 02-adr 决策5（新增 Encrypted）；02-design §5 错误分类表（Corrupt/Encrypted/Io）；03-review §4.1（PdbBook 记录偏移前置校验防 crate panic） | `error.rs`（`Encrypted(String)` 变体，Display 含"DRM/加密"）、`format/mobi_common.rs`（from_path 全记录偏移校验、checked 运算、宽松解压停止）、`mobi.rs`/`azw3.rs`（错误传播） | `truncated_mobi_returns_corrupt`、`synthetic_truncated_mobi_returns_corrupt`（截断→Corrupt 不 panic）；`garbage_mobi_returns_corrupt`（伪装→Corrupt）；`drm_marked_mobi_returns_encrypted`、`synthetic_azw3_drm_returns_encrypted`（DRM→Encrypted 且消息含"DRM/加密"）；`synthetic_azw3_short_embedded_header_returns_corrupt`（短内嵌头→Corrupt） | ✅ |
| **US-4 与既有管线打通**：`import_file` 返回 `format=="mobi"`、canonical_path 为规范 EPUB 落 cache、open_book 章节数与 parse 一致、二次导入同 id 去重书架 1 本；`book_chapter_html` 合法 XHTML 含已知句子；`book_resource` 字节与语料图片哈希一致 | 02-design §1（library/api **零改动**，复用 canonicalize/library 管线）/§4.1 时序（下游 canonicalize → import/open） | `library/mod.rs`（既有，零改动）、`api.rs`（既有，`err_msg` 泛型透出；无新桥接函数）、`format/mobi_common.rs`（img src 重写与 `Resource.source_path` 对齐保证 canonicalize 精确命中） | `library_import_open_mobi_roundtrip`（format=="mobi"、canonical 缓存路径存在、章节数与 parse 一致、二次导入同 id、书架 1 本、chapter_html 合法 XHTML 含已知句子）；`corpus_pride_and_prejudice_mobi_heading_split_with_images`（book_resource：165 张 JPEG 魔数断言）；FFI `rust_bridge_test.dart`（真实 .so 全链路，EPUB 路径回归） | ✅ |
| **US-5 中文编码与目录提取**：UTF-8 中文无乱码；GBK(936)/声明 CP1252 实际 GBK 正确解码无 U+FFFD；无 INDX 时按页断点切 `chapters>1`、toc 允许空不崩溃；有 INDX 按条目还原（失败回退章节标题） | 02-adr 决策2；02-design §2.1（decode_text 编码链：声明→内容探测→lossy）、§3（toc depth clamp 0..=8） | `format/mobi_common.rs`（decode_text/utf8_or_declared/decode_cp1252_or_gbk/gb18030_decode/big5_decode、parse_indx（TAGX）、build_toc 回退、split_chapters） | 集成：`corpus_hongloumeng_mobi_pagebreak_split`（UTF-8 中文无 U+FFFD）、`synthetic_gbk_mobi_no_mojibake`（GBK 936 无乱码）、`synthetic_cp1252_mobi_accent_chars`（CP1252 é 无 FFFD）、`corpus_hongloumeng_images_mobi`（IDXT 变体→toc 回退不崩溃）；单测：`decode_gbk_936`/`decode_declared_cp1252_but_actual_gbk`/`decode_unknown_declaration_sniffs_gbk`/`decode_big5_950`/`parse_classic_indx_record`/`parse_indx_rejects_numeric_labels`/`build_toc_maps_indx_positions_to_chapters`/`build_toc_falls_back_to_chapter_titles`/`split_falls_back_to_headings` | ✅ |
| **US-6 性能预算**：5MB 级 MOBI 桌面单次解析 <200ms（预算）；CI 宽松上限 ≤2s | 02-plan T-006（criterion/计时脚本 + CI 宽松断言）；docs/02 §6 预算 | `tests/mobi_azw3.rs`（perf_parse_timing） | `perf_parse_timing`（CI 宽松上限 ≤2s 已入断言，debug 754/432ms 通过）；桌面基准实测（阶段3 记录）：P&P（24MB/165图）**82ms**、紅樓夢 **32ms**（release，<200ms 预算） | ✅ |

> 闭合口径：US-1~US-6 每条验收标准均有**具体测试名/报告**作为证据链（设计→代码→测试）；US-2 的真实 KF8 语料缺口属**已登记限制**（corpus README + §3.1），按 01-req §5 风险1 的"可观察行为兜底条款"闭合，非未完成项；本 REQ 无 ⏳ 真机待办（见 §3.5）。

## 5. 发布产物清单

- **版本号建议：v0.2.1**（在 REQ-001 v0.2.0 之后增量合入；REQ-002 为解析能力**向后兼容**增量：无 API/数据结构破坏、无库表变更，0.x 阶段按合入节奏取 patch 递增；若严格按语义化 minor 亦可定 v0.3.0 —— 由 orchestrator 合并时最终裁定并在合并信息中记录）。
- **代码**（分支 `wf/REQ-002-mobi-azw3`）：
  - 新增：`core/src/format/mobi_common.rs`（解析内核）
  - 实现（stub→完整）：`core/src/format/mobi.rs`、`core/src/format/azw3.rs`
  - 变更：`core/src/format/mod.rs`（parse 分发 + detect_format 嗅探）、`core/src/error.rs`（Encrypted）
  - 零改动（回归验证）：`convert/mod.rs`、`library/mod.rs`、`api.rs`、`app/**`
- **测试与语料**：`core/tests/mobi_azw3.rs`（21 集成，新增）、`core/src/format/mobi_common.rs` 内单测（~40，新增）、`core/tests/corpus/src/*.mobi` ×6（3 真实 + 3 构造坏文件）+ `corpus/README.md`（来源/sha256/生成命令/已知缺口登记）
- **质量报告**：`workflow/reports/crap-req002-final.md`（本次，FAIL=0）、`workflow/reports/ddd-req002-final.md`（本次，违规=0）、`workflow/reports/crap-req002.md`（阶段3）、`workflow/backlog/REQ-002-mobi-azw3/04-mutation.md`、`04-coverage.md`
- **rework 记录**：`workflow/rework/REWORK-REQ-002-D.md`
- **交付文档**：`workflow/backlog/REQ-002-mobi-azw3/05-delivery.md`（本文）
- 合并建议：闸门1–5 全过后 `--no-ff` 合并回 main，合并信息引用本文与追溯矩阵。

## 闸门5 自评

- [x] **追溯矩阵全闭合**：US-1~US-6 全部映射到 设计→代码→测试证据（具体测试名/报告），无一遗漏；US-2 真实 KF8 语料缺口为已登记限制并按兜底条款闭合（§3.1/§4），本 REQ 无 ⏳ 真机待办
- [x] **全量回归绿**：cargo test 88 项全绿（62 单测 + 21 mobi/azw3 集成 + 5 语料）；flutter analyze 0 问题；flutter test 5 用例全绿；FFI 端到端（真实 .so）全绿；CRAP FAIL=0（WARN=5 全为既有代码）；DDD 违规=0；变异 94.8% ≥80%；新代码覆盖 97.7% ≥85%
- [x] **发布产物齐全**：05-delivery.md（本文）、crap/ddd 终版报告（本次落盘）、04-mutation/04-coverage、REWORK-REQ-002-D.md、语料登记 README 均在仓库内且工作树干净
