<!-- wf-meta: req=REQ-002 | phase=development | agent=developer | date=2025-08-30 | gate=passed -->
# REQ-002 · 开发前置审查（Pre-Implementation Review）

## 1. 设计与既有约定核对
| 检查项 | 结果 |
|---|---|
| 与 docs/03 分层/架构冲突？ | 无。改动全部落在 domain 层 `core/src/format` 与 `core/src/error.rs`（ddd-rules.toml 的 domain 路径已覆盖 `core/src/format`，规则表无需改）；新增 `mobi_common.rs` 同属 domain，只依赖 `crate::error`、`crate::format` 内部类型与外部 crate（mobi/encoding_rs/regex/quick-xml），禁止 `crate::store\|api\|library`（ADR 决策1、design §1） |
| 与 docs/04 Locator/限界上下文冲突？ | 无。locator/reading_progress/tts 零改动；不触碰 Locator 不变式与听读同进度；ParsedBook 结构不变，MOBI/AZW3 按其字段填充（design §3） |
| 与既有 ADR 冲突？ | 无。02-adr.md 为本次架构产物：mobi crate 0.8 内核 + 自补缺口（决策1）、pagebreak 主/标题回退拆章（决策2）、AZW3 双路径 KF8 优先回退兜底（决策3）、解析器内预处理 convert 零改动（决策4）、新增 `Error::Encrypted`（决策5，docs/03 §8 已有同名错误分类，属文档-代码对齐） |
| 与既有业务（听读进度/笔记锚定）冲突？ | 无。convert/library/api 零改动；`err_msg<E: Display>` 泛型映射自动透出新变体文案（design §5）；epub/txt 解析路径零行为变化（parse 仅新增两臂） |

## 2. 计划核对
| 检查项 | 结果 |
|---|---|
| 任务缺失/依赖环/估算离谱？ | 无。T-001..T-006 覆盖"语料→内核→MOBI7→AZW3→接入/错误→测试/基准"全链，依赖图无环（T-003/T-004 并行）。**一处事实修正（非 rework，计划已预留处置）**：实测 Gutenberg kf8 下载（24264/1342）均为 **MOBI7**（MOBI 头 type=2、PalmDoc 压缩、无 RESC/BOUNDARY/KF8Boundary），并非 AZW3/KF8；计划语料表已注明"kf8 属性以 T-003/T-004 冒烟实测为准"，处置为：语料按真实格式命名 `.mobi`，真实 KF8/AZW3 语料（both/KF8-only）需 calibre 生成，本环境无 calibre → 留待开发机补录并登记于 corpus README；azw3 路径以「.mobi 语料复制为 .azw3 扩展名的分发测试 + 合成 KF8 rawml 单测 + detect_format 构造头单测」覆盖（US-2 验收按可观察行为，不承诺内部路径） |
| 估算是否受上述修正影响？ | 语料获取与校验（T-001）完成度保持：真实 MOBI7 ×3（含 pagebreak/含图/中文/英文）+ 构造坏文件 ×3（截断/垃圾/DRM 标记）+ 合成 PalmDOC/GBK/INDX 样例（单测内构造） |

## 3. 需求可测性核对
| 检查项 | 结果 |
|---|---|
| 验收标准可实现且可测？ | 是。US-1~US-5 全部落为可断言项：`format` 枚举相等、title/authors 精确比对、`chapters.len()≥N`、已知句子逐字包含、无 `U+FFFD`、`matches!(err, Error::Corrupt|Encrypted)`、`book_resource` 字节哈希、去重 id 相等、缓存路径存在；US-6 性能预算为可测基准（本阶段以计时脚本记录，CI 宽松上限 ≤2s）。本环境无法生成的 KF8-only 真实语料（US-2 第 2 条）按"可观察行为兜底"条款处理，缺陷已在 §2 登记 |

## 4. 实现期前置发现（进入实现前已确认，非 rework）
1. **mobi crate 0.8.0 的 `raw_records()` 对截断文件会 panic**（record.rs `&content[offset..]` 无界切片）——与"任何输入不 panic"冲突。处置：`PdbBook::from_path` 在调用 crate 记录访问前，先校验全部记录偏移 ≤ 文件内容长度，越界即 `Err(Error::Corrupt)`（design §2.1 的 PdbBook 薄封装内补充，属实现细节强化）。
2. **Gutenberg 文件的 MOBI 头 `first_content_record=0`**（非 1），crate 的 `readable_records_range` 因此包含 record 0（头记录，解压后是头部字节的垃圾流）。处置：可读区取 `max(first_content_record,1)..first_non_book_index`，与 palmdoc 头 `text_length` 实测一致。
3. **INDX 为 KindleGen "IDXT" 变体且标签为数字位置串**（"0000000420"），非经典 TAGX 格式，作 TOC 无意义。处置：`parse_indx` 按经典 TAGX 格式实现（calibre/Mobipocket 风格），失败或标签全数字 → `None` → 章节标题回退（design §2.1 与 US-5 明确允许）。
4. **图片引用为 `kindle:embed:NNNN?mime=...`（十六进制编号，与记录序无简单对应）**。处置：`sanitize_html` 将 embed 编号按十六进制解析映射到抽取图片序号（越界保留原样），保证重写后的 src 必然命中资源表 → canonicalize 资源重写精确命中；图片身份为尽力而为（真实语料断言资源条数与 JPEG 魔数，精确哈希断言用合成语料）。

## 5. 结论
- [x] 通过，进入实现（上述发现均为实现细节处置，不构成 rework-A/B/C；真实 KF8 语料缺口按计划既有处置路径登记）

## 6. 实现与自检记录

### 6.1 Task 完成情况
| Task | 完成 | 测试 | CRAP | DDD |
|---|---|---|---|---|
| T-001 语料获取与校验 | ✅ | 真实 MOBI7 ×3 + 坏文件 ×3 落地 `tests/corpus/src/`，README 登记来源/许可/sha256；**实测修正**：Gutenberg "kf8" 下载（24264/1342）均为 MOBI7（MOBI 头 type=2、PalmDoc、无 RESC/BOUNDARY/EXTH121）→ 按真实格式命名 `.mobi`；真实 KF8/AZW3 语料需 calibre 生成（本环境无）→ 留待开发机补录（README 已知缺口登记） | 语料冒烟断言全过 | — | — |
| T-002 mobi_common 内核 | ✅ | 28 项单元测试（palmdoc 往返/重叠/结束标记、GBK/CP1252/Big5 解码链、sanitize 保留 pagebreak+img 重写、pagebreak/标题拆章、INDX 经典格式解析、图片魔数嗅探、TOC 组装） | PASS（无 FAIL） | 0 违规 |
| T-003 MOBI7 解析 | ✅ | 真实语料：hongloumeng.mobi（35 章 pagebreak 拆章、title=紅樓夢、language=zh、无 U+FFFD）、hongloumeng-images.mobi（标题拆章）、P&P（68 章标题拆章、165 JPEG、已知句子） | PASS | 0 违规 |
| T-004 AZW3/KF8 解析 | ✅ | 合成 KF8 rawml（type=248+EXTH121 → 格式==Azw3、章节文本断言）；`.mobi` 内容复制为 `.azw3` 扩展名分发兜底（格式==Azw3、正文正确）；detect_format 无扩展名嗅探（type==248→Azw3、type==2→Mobi，真实 PDB 魔数在偏移 60） | PASS | 0 违规 |
| T-005 error.rs Encrypted + 接入 | ✅ | `Error::Encrypted` 新增；DRM 标记语料 → `Err(Encrypted)` 且消息含"DRM/加密"；截断/垃圾 → `Err(Corrupt)` 不 panic；library 接入：import→open→chapter_html→去重（`format=="mobi"`、canonical 缓存、同 id、书架 1 本） | PASS | 0 违规 |
| T-006 测试强化 + 基准 | ✅ | `cargo test` 全绿：54 单测（含既有）+ 14 mobi_azw3 集成 + 5 语料 = 73 项；性能基准（US-6）：release 解析 P&P(24MB/165图) 82ms、红楼梦 32ms（<200ms 桌面预算）；debug 754/432ms（<2s CI 上限，已入测试断言） | FAIL=0 / WARN=14（新代码 9，均 <25 阈值，允许） | 0 违规 |

### 6.2 实现期发现与处置（相对 02-design 的实现级偏差，均已在代码注释说明）
1. **mobi crate 0.8.0 的 `Mobi.content` 是"头部长度个 0 + 剩余字节"拼接缓冲**（reader.rs `from_reader`），
   而 PDB 记录偏移是绝对文件偏移 → `raw_records()` 返回的记录 0 内容前段是 0 污染（MOBI 头字段读不出来），
   且对越界偏移无界切片会 panic。处置：`PdbBook` 直接保存文件字节并自实现 `record_bytes(i)`（按记录表偏移切片，
   兼容 extra 字段），完全绕开 `raw_records()`；`from_path` 校验全部记录偏移在文件内（截断 → Corrupt，不 panic）。
2. **KindleGen 记录末尾的 offset==0 回引用是"结束标记"**（记录实际解压尺寸 = record_size），
   严格报错会误伤真实文件。处置：`palmdoc_decompress` 宽松停止（与 crate 语义一致，但修正了 crate 对
   `offset > text_pos` 取模会破坏重叠拷贝的问题）；`section_text_bytes` 对每记录输出截断到
   `record_size`（否则记录边界产生杂字节 → 中文解码 U+FFFD，真实语料实测）。
3. **Gutenberg 文件 `first_content_record=0`**（非 1），crate 的 `readable_records_range` 因此含 record 0
   头记录垃圾。处置：内容区取 `max(first_content_record,1)`。
4. **`first_index_record` 位于 MOBI 头偏移 228（非 224）**，且索引记录区 = `[first_index_record, first_image_index)`
   （真实语料核实；索引记录位于内容记录与图片记录之间）。
5. **INDX 为 KindleGen "IDXT" 变体且标签为数字位置串**（如 "0000000420"），无意义。处置：
   `parse_indx` 按经典 TAGX 格式实现（合成样例验证），标签全数字/解析失败 → `None` → 章节标题回退（US-5 允许）。
6. **拆章切断标签嵌套**（如 `<header>…<h2>…</header>` 被标题切分切开）→ `epub::html_to_text` 的
   quick_xml 对错配闭合标签报错中断，章节文本被截断（真实语料实测）。处置：mobi_common 新增
   `html_to_text_lenient`（正则实现：剥 script/style → 块级转行 → 去标签 → 实体解码 → 压缩空行），
   mobi/azw3 章节文本改用它；**epub.rs 零改动**（约束内）。
7. **`detect_format` 原 BOOKMOBI 分支检查 `bytes[..8]`**，但真实 PDB 的魔数在偏移 60（前 32 字节为书名）→
   真实文件内容嗅探失效。处置：`looks_like_pdb` 同时检查偏移 60 与偏移 0（兼容旧约定），满足 US-2 无扩展名嗅探。
8. **图片引用 `kindle:embed:NNNN`（十六进制，与记录序无简单对应）**：sanitize 按十六进制序号映射到
   抽取图片（越界保留原样），保证重写后的 src 必然命中资源表（canonicalize 精确重写）；图片身份为尽力而为
   （真实语料断言资源条数与 JPEG 魔数，精确哈希断言用合成语料）。

### 6.3 闸门3 自评
- [x] CRAP FAIL=0（`workflow/reports/crap-req002.md`；新代码 WARN=9 均 <25 阈值，允许）
- [x] DDD 违规=0（`workflow/reports/ddd-req002.md`；domain 层无 `crate::store|api|library` 依赖）
- [x] `cargo test` 全绿：54 单测 + 14 mobi_azw3 集成 + 5 既有语料 = 73 项，零回归（epub/txt/library 既有断言未改）
- [x] 无未处理 rework（本阶段无 rework-A/B/C 触发；真实 KF8 语料缺口按计划既有处置路径登记于 corpus README）
- [ ] 待办（不阻塞闸门3）：真实 KF8/AZW3 语料（both/KF8-only）由开发机 calibre 生成补录后，
      `synthetic_kf8_rawml_azw3` 之外补充真实 KF8 断言；INDX 经典格式解析器以合成样例验证，
      真实 calibre MOBI 语料补录后可强化。
