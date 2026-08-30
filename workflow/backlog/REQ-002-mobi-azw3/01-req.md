<!-- wf-meta: req=REQ-002 | phase=requirements | agent=req-analyst | date=2025-08-30 | gate=passed -->
# REQ-002 · MOBI/AZW3 解析 —— 需求分析

## 1. 背景与目标
P0 只支持 EPUB/TXT（`format::parse` 对 mobi/azw3 返回"尚未实现"，`format/mobi.rs`、`azw3.rs`
为空 stub，`core/Cargo.toml` 已声明 `mobi = "0"` 但未使用）。MOBI/AZW3 是海量存量电子书的主流格式，
LIB-01（导入支持 MOBI/AZW3）、READ-03（目录含"MOBI/AZW3 转换后重建"）在产品层点名该能力，
但解析层缺位。REQ-002 实现 **MOBI7（PalmDOC）与 AZW3（KF8）解析**：输出统一中间表示
`ParsedBook`，复用既有 canonicalize/library 管线，使 .mobi/.azw3 可导入、可打开、可读章节文本与目录；
损坏/截断/DRM 标记输入不崩溃并返回结构化错误。成功标准一句话：**任意合法 MOBI7/AZW3 文件经
"导入 → 打开 → 读章节"全链路可用，非法输入给明确错误且不 panic**。

## 2. 用户故事与验收标准（Given/When/Then，必须可测）
- 故事 1：作为小林，我想要把电脑里的 .mobi/.azw3 书导入书库并正常阅读（含目录跳转），以便读完存量老书。
  - **US-1 MOBI7 解析正确性**
    - Given 一份标准 MOBI7 语料（PalmDOC LZ77 压缩、含 EXTH 元数据、含 INDX 目录、含 ≥2 个 `<mbp:pagebreak/>` 分章）
      When 调用 `format::parse`
      Then 返回 `ParsedBook`，且：`format == Format::Mobi`；`title` 与语料记录书名完全一致；
      `authors` 非空；`language` 与 EXTH 声明一致（可为空）；`chapters.len() ≥ 2` 且首个分章边界落在页断点/标题处；
      全部章节 `text` 拼接后**逐字包含**语料中已知句子（如 "It is a truth universally acknowledged"）。
    - Given 同一语料 When 断言目录 Then `toc.len() ≥ 1` 且 `toc[0].title`、`toc[0].href` 与语料目录首条一致；`toc[i].depth` 均为 `0..=255` 内合法值。
  - **US-2 AZW3/KF8 解析正确性**
    - Given 一份 AZW3 语料（KF8：PDB 内嵌 EPUB 结构 + MOBI7 回退段，含图片；扩展名 `.azw3`）
      When 调用 `format::parse`
      Then 返回 `ParsedBook`，`format == Format::Azw3`；元数据（title/authors）正确；
      `chapters.len() ≥ 1`；章节 `text` 含语料已知句子；含图时 `resources` 中存在 `media_type` 以 `image/` 开头的条目。
    - Given 一份 **KF8-only** AZW3 语料（MOBI7 回退段为空，仅 KF8 原生段；可用 calibre `--mobi-file-type=new` 生成）
      When 调用 `format::parse`
      Then 不报错，`chapters.len() ≥ 1` 且正文文本非空、含已知句子（可观察行为兜底，不承诺内部走哪条路径）。
    - Given 无扩展名的 AZW3 文件（内容嗅探，文件头同为 `BOOKMOBI`）
      When 调用 `format::parse`
      Then 解析成功且 `format == Format::Azw3`（与 `.mobi` 正确区分，不得误判为 Mobi）。
  - **US-3 错误输入不崩溃（结构化错误）**
    - Given 截断的 .mobi（PDB 头完整、记录区/内容流被切断）
      When 调用 `format::parse` 或 `LibraryService::import_file`
      Then 返回 `Err`（`Error::Corrupt` 或 `Error::Other`），**不 panic**；`assert!(matches!(err, …))` 可断言。
    - Given 损坏的 .azw3（记录表偏移越界/魔数错乱）When parse Then 返回 `Err`，不 panic。
    - Given 带 DRM/加密标记的 .mobi（PalmDOC `encryption` 字段 ≠ No，或 EXTH DRM 标志 `0xFFFFFFFF`）
      When parse Then 返回 `Err`，错误**消息含"DRM/加密"字样**（UI 文案对齐 LIB-01"可能受 DRM 保护"）。
    - Given 伪装 .mobi（`BOOKMOBI` 魔数 + 垃圾字节）When parse Then 返回 `Err`，不 panic。
  - **US-4 与既有管线打通（导入 → 打开 → 章节）**
    - Given 一份 .mobi 语料 When `LibraryService::import_file`（复用 canonicalize/library）
      Then 返回 `BookRecord`：`format == "mobi"`、`canonical_path` 存在且为规范 EPUB（`<hash>.epub` 落 cache 目录）；
      `open_book` 章节数与 `format::parse` 一致、`chapters[0].text` 非空；同文件再次导入返回同一 `id`（SHA-256 去重），书架仅 1 本。
    - Given 导入后的 .mobi When `book_chapter_html` 读章节 Then 返回合法 XHTML 且含已知句子；
      Given 含图 MOBI When `book_resource` 读图片 Then 返回字节与语料图片哈希一致（资源路径重写正确）。
  - **US-5 中文编码与目录（TOC）提取**
    - Given UTF-8 编码中文 MOBI When parse Then 章节 `text` 含语料已知中文字符串，且不含 `U+FFFD` 替换符与乱码。
    - Given GBK 编码中文 MOBI（`text_encoding` 字段为 936 或未知值，或声明 CP1252 但实际为 GBK）
      When parse Then 经 `encoding_rs` 正确解码，`text` 含已知中文字符串，无 `U+FFFD`/乱码。
    - Given 无 INDX 的 MOBI（仅靠 `<mbp:pagebreak/>` 分章）When parse Then 仍按页断点切出 `chapters.len() > 1`，
      `toc` 允许为空但**不崩溃**；When 有 INDX 时 Then `toc` 按 INDX 条目还原（回退：按章节标题生成）。
  - **US-6 性能预算（可测基准，非 CI 硬断言）**
    - Given 5MB 级 MOBI 语料 When 桌面环境基准测量单次解析 Then 耗时 < 200ms（docs/02 §6 预算；
      以 bench/计时脚本记录为准；CI 用宽松上限 ≤ 2s 防回归）。

## 3. 影响面分析（必须非空）
- **format 分发**：`core/src/format/mod.rs` —— `parse()` 的 match 新增 `Format::Mobi | Format::Azw3`
  两臂，分别分发到 `mobi::parse` / `azw3::parse`；`detect_format()` 的 `BOOKMOBI` 分支当前一律返回 `Mobi`，
  AZW3 同以 `BOOKMOBI` 开头，需在 azw3 解析内按 MOBI header type（KF8 边界 / EXTH 记录 121 `KF8BoundaryOffset`）
  区分内容嗅探归属（无扩展名场景）；`format_for_path` 已支持 `.azw/.azw3 → Azw3`，无需改但需测试覆盖。
- **format/mobi.rs + format/azw3.rs**：空 stub → 实现。含 PDB 容器读取、解压（PalmDOC LZ77 / HUFF/CDIC）、
  EXTH 元数据、整书 HTML → 章节拆分（`mbp:pagebreak` / 标题层级 / INDX）、TOC 提取（INDX 或回退启发式）、
  图片资源抽取（RECORD 0 内联图 + image 记录）、HTML→text 与编码解码（encoding_rs）。
  两文件属 **domain 层**（ddd-rules `core/src/format`）：**禁止 `use crate::store|api|library`**
  （domain 禁内部依赖，闸门3 DDD 违规=0）；对外只允许依赖 `crate::error`、`crate::format` 内部类型与 `mobi` crate。
- **convert（章节 HTML 规范化）**：MOBI 产出的 HTML 常无 DOCTYPE、含 `mbp:` 命名空间标签、`font`/内联样式、
  坏引用 → 需清洗/白名单化（docs §3.2 规范 EPUB 子集）；资源路径重写正则在含图 MOBI 上需验证（相对路径/data URI 差异）；
  可能新增 MOBI HTML 清洗函数（仍 domain 层，归属 format 或 convert 由架构阶段定）。
- **library（导入流程）**：`import_file`/`open_book` 为通用管线，MOBI/AZW3 无需逻辑改动，但**错误传播面新增**
  （DRM/编码/解压错误文案）；新增 MOBI/AZW3 集成测试（对齐 p0_corpus 的 `library_import_and_open_roundtrip` 模式）。
- **api（桥接）**：**无需新增桥接函数**（`library_import`/`book_open`/`book_chapter_html`/`book_resource`/`progress_*`
  全部复用）；若引入新错误变体（见下），`api.rs` 的 `Error → String` 映射需覆盖新变体文案。
- **error.rs**：建议新增 `Error::Encrypted` 变体（domain 层），使 UI 可区分"DRM 加密"与"文件损坏"（对齐 LIB-01
  验收文案"可能受 DRM 保护"）；当前 `Corrupt`/`Other` 亦可承载但语义不清晰 —— 是否新增由架构阶段决策，
  决策后需同步 `api.rs` 错误映射与测试断言。
- **ddd-rules.toml 层归属**：mobi/azw3 文件落在已声明的 domain 路径 `core/src/format`，**规则表无需修改**；
  实现须通过 ddd-lint（违规=0）；`convert` 同属 domain，遵守同类约束。
- **回归面（非空）**：core 既有测试全量 —— `format/mod.rs` detect 系列、epub/txt 解析、convert 往返、
  library 导入/去重/损坏/进度、`tests/p0_corpus.rs`（5 语料：hongloumeng.epub、pride-and-prejudice.epub/.txt）、
  `tests/integration.rs`、Flutter FFI 端到端（EPUB 导入路径）、workflow 闸门（CRAP/DDD/变异）。
  `parse()` 分发改动必须保证 epub/txt 路径零行为变化；如抽取 epub.rs 的 HTML→text 为共享工具（复用给 MOBI），
  属 epub.rs 微小重构，需专项回归。新增 MOBI/AZW3/坏文件/GBK 语料后 corpus 变更走既有评审规则。

## 4. 依赖与优先级
- **依赖**（均为既有或已声明，无新增 crate）：
  - `mobi` crate（`core/Cargo.toml` 已声明 `mobi = "0"`，本次首次实际使用；建议锁定 `0.8`，其能力边界见 §5 风险1）；
  - `encoding_rs`（已有，GBK/Big5 中文解码）；
  - 既有 `ParsedBook`/`BookCanonicalizer`/`LibraryService` 管线（已有，复用不改）；
  - 新语料：MOBI7/AZW3（KF8-only 与 both）、GBK 中文 MOBI、构造坏文件（截断/垃圾/DRM 标记），
    来源遵循 corpus README 规则（无版权争议、单文件 < 30MB、来源记录、变更评审）。
- **优先级**：**P1**。理由：P0（EPUB/TXT）已支撑 MVP；MOBI/AZW3 是 LIB-01/READ-03 产品级要求的
  底层解析能力，属"应有可延后"。
- **与其他 REQ 关系**：与 REQ-001（WebView 分页渲染）互不依赖；依赖 REQ-001 已落地的
  `book_chapter_html`/`book_resource` 桥接（存在）作为消费端；听读进度/Locator 不受影响（不新增进度模型）。

## 5. 风险
1. **`mobi` crate 能力边界（已核实 0.8.0 源码，风险最高）**：
   - ✅ 内置 PalmDOC LZ77 与 **HUFF/CDIC 解压**（`compression::huff` 自研实现，无外部 huffcdic 依赖）；
     EXTH 元数据（title/author/language/isbn/cover 等，`exth_record` 可扩展访问，含 `KF8BoundaryOffset`=121）；
     `encryption()` 可检测 DRM；`raw_records()` 可访问原始记录。
   - ❌ **KF8/AZW3 支持缺失**：`mobi_type()` 对 KF8（type 248）返回 `Unknown`；**无 KF8 内容 API**，
     只解 MOBI7 回退段 → 纯 KF8 原生 AZW3 需自解析内嵌 EPUB（参考 KindleUnpack 算法）或降级用回退段；
     **无 INDX/TOC API**（目录需自实现 INDX 解析或启发式）；**无章节拆分**（需自实现）；
     `TextEncoding` 仅 CP1252/UTF8，中文 GBK（936）归 `Unknown` 需自解码。
   - ⚠️ 维护停滞（2022-12 后无发布）→ 缺陷无上游修复。
   - **缓解**：解析薄封装在 mobi.rs/azw3.rs（内部实现可整体替换）；验收按**可观察行为**定义（US-2 的
     KF8-only 兜底条款），不承诺内部路径；架构阶段评估备选（kindling crate / 自研 PDB 解析）；
     docs §3.3 允许"缺的压缩分支自补"。
2. **真实语料来源**：公版 MOBI/AZW3 下载源（Feedbooks 公版库、Project Gutenberg Kindle 版、Mobileread 样例区）；
   受控语料用 calibre `ebook-convert` 自造（EPUB→MOBI（UTF-8/GBK 可控）→AZW3（`--mobi-file-type=new|both`）），
   可精确控制断言内容；需满足 corpus 规则（无版权争议、<30MB、来源记录）。
3. **DRM**：Kindle 商店 AZW3 普遍 DRM；仅识别加密标记并返回明确错误（"可能受 DRM 保护"），
   **不做破解**（docs §3.5 明确排除）。
4. **中文编码**：GBK（936）/编码声明缺失或错误 → 解码兜底链（声明值 → 内容探测 → lossy），
   误判风险以 GBK 语料测试 + 替换符断言控制。
5. **性能/内存**：整书 HTML 一次性解压全量入内存、HUFF 单线程；5MB MOBI < 200ms 预算（docs §6）；
   缓解：导入本就在后台任务（已有）、规范 EPUB 缓存二次打开秒开（已有）、US-6 基准监控。
6. **HTML 卫生与资源重写**：MOBI HTML 不规范（mbp 标签、font、无 DOCTYPE、坏引用/相对路径差异）→
   convert 清洗规则与正则重写需覆盖含图/含样式 MOBI，防误伤；以含图语料测试兜底。
7. **范围蔓延**：KF8 原生解析复杂度高 → 明确降级线：本期保证"MOBI7 完整 + AZW3 回退段可读；
   KF8 原生段尽力而为"，超出部分由架构阶段以 ADR 决策是否列入本期。

## 6. 闸门1 自评
- [x] 验收标准全部可测：US-1~US-5 每条均含可断言项（`chapters.len() ≥ N`、已知句子逐字包含、
  错误类型 `matches!`、`format` 枚举相等、无 `U+FFFD`、去重 id 相等、缓存路径存在、哈希一致）；
  US-6 为可测基准（<200ms 预算 + CI 宽松上限），无"体验好"类不可测词。
- [x] 与既有 REQ 无重复：REQ-001（WebView 分页渲染）不涉及解析；LIB-01/READ-03 是产品层
  导入/目录展示故事（验收在 UI 层），本 REQ 是底层解析能力（format::parse），属使能关系而非重复。
- [x] 影响面清单非空：format 分发、mobi/azw3 实现、convert 规范化、library 错误面、api 错误映射、
  error.rs 变体、ddd-rules 层归属、既有测试回归面共 8 项，均列具体条目。
