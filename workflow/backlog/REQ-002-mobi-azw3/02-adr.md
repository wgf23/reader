<!-- wf-meta: req=REQ-002 | phase=architecture | agent=architect | date=2025-08-30 | gate=passed -->
# REQ-002 · 架构决策记录（ADR：MOBI/AZW3 解析内核与章节/TOC/错误策略）

## 决策
以 **mobi crate 0.8 为 PDB/PalmDOC/HUFF 内核 + 自补 KF8 内容、拆章、INDX 目录、GBK 解码**
（薄封装于 `format/mobi_common.rs`，内部实现可整体替换）；AZW3 采用 **KF8 原生段优先 + MOBI7
回退段兜底** 双路径（验收按可观察行为，见 01-req.md §5 风险1 兜底条款）；章节拆分以
`<mbp:pagebreak/>` 为主、标题层级为回退；新增 `Error::Encrypted` 错误变体（对齐 docs/03 §8）。

## 备选方案
1. **方案 A：mobi crate 为主 + 自补缺口** —— PDB 容器、PalmDOC LZ77、HUFF/CDIC 解压、
   EXTH 元数据、加密检测、raw records / 图片记录全部复用 crate（已核实 0.8.0 源码，
   见下"核实结论"）；自补 KF8 rawml 解析、INDX 目录、GBK 解码、章节拆分。
   优点：解压与容器层正确性由 crate 的健壮测试背书（其内置防 OOM/越界/回溯游标测试），
   自研量最小；缺点：crate 维护停滞（2022-12 后无发布），缺口需自补且缺陷无上游修复；
   风险通过"薄封装 + 验收按可观察行为"对冲。
2. **方案 B：完全自研 PDB/PalmDOC/HUFF 解析（不依赖 mobi crate）** —— 容器/压缩/编码全自写。
   优点：零第三方依赖、行为完全可控；缺点：HUFF/CDIC 解码是公认难点（自研易错、工作量大），
   与 docs/02 §8 依赖清单（已声明 mobi crate）冲突，重复造轮子，测试成本高。
3. **方案 C：calibre / 外部转换服务（子进程或远程 API）** —— 文件先转成 EPUB 再走既有管线。
   优点：格式兼容性最好（calibre 生态）；缺点：违背**离线优先**与体积约束（docs/02 §1/§7：
   calibre 无法打包进 <40MB 安装包，需网络/外置进程），导入延迟与失败面变大，且与
   "Rust 原生解析（docs/02 §2 核心层选型）"矛盾。

## 选择与理由
选 **A**：
- **能力核实结论（读 mobi-0.8.0 源码）**：`Mobi::from_path/new/from_read` 解析 PDB 头+记录表
  +PalmDOC+MOBI+EXTH；`content_as_string[_lossy]()` 覆盖 No/PalmDoc/Huff 三种压缩；`encryption()`
  与 `MobiHeader::has_drm()`（`drm_offset != 0xFFFF_FFFF`）可检测 DRM；`exth_record()` 可访问
  EXTH 全部记录（含 **121 KF8BoundaryOffset**、503 Title、524 Language、100 Author）；
  `raw_records()` / `readable_records_range()` / `image_records()` 提供记录级与图片访问。
- **缺口（已核实）**：`mobi_type()` 对 KF8（type 248）返回 `Unknown`，**无 KF8 内容 API**；
  **无 INDX/TOC API**；`TextEncoding` 仅 1252/65001，GBK(936) 归 `Unknown(936)` 需自解码；
  `palmdoc::decompress` 为 crate 私有（`pub(crate)`），外部解码需自研 LZ77 或走编码受限的
  `content_as_string`。
- docs/02 §3.3 明确"缺的压缩分支自补"、§8 依赖清单已声明 mobi crate、§3.5 排除 DRM 破解
  （只识别标记）——方案 A 与既有文档逐条一致；B/C 与 docs/02 §2/§8 冲突。01-req.md §5 风险1
  的缓解策略（薄封装可替换 + 可观察行为验收）即为 A 的落地形态。

## 决策点（本 ADR 明确裁定的五个具体决策）
1. **解析内核（A/B/C）**：选 A（理由如上）。
2. **拆章策略**：**`<mbp:pagebreak/>` 为主，标题层级（h1-h3）回退，INDX 仅用于目录还原**。
   - 备选 D2-1：按 INDX 位置切分（目录即章节）——INDX pos 是内容流偏移，与页断点切出的段落
     边界未必重合，语义更绕、失败面大；仅当既无 pagebreak 又无标题层级时才可考虑。
   - 备选 D2-2：纯标题层级切分——无标题书（小说常只有 pagebreak）会退回单章。
   - 选 D2（pagebreak 主 + 标题回退）：满足 US-1"首个分章边界落在页断点/标题处"与
     US-5"无 INDX 时按页断点切出 chapters > 1"，且实现简单、可预测。
3. **AZW3 的 KF8 vs 回退段取舍**：**双路径，KF8 优先、回退段兜底**（不做二选一降级）：
   - KF8 优先：可读记录区解压产物若呈现 rawml 特征（`<?xml` / `<package` / `<html`），自解析
     内嵌 OPF 的 manifest/spine/nav → 章节与资源（参考 KindleUnpack 思路，规模受限）。
   - 兜底：按 EXTH 121 KF8BoundaryOffset + 记录内二次 MOBI 头（type==2）扫描定位 MOBI7 回退段，
     自解析其 MOBI 头并自研 PalmDOC 解压 → 复用 MOBI7 管线。
   - 备选 D3-1：仅回退段（本期不做 KF8）——KF8-only 文件（US-2 第 2 条）直接失败，不达标。
   - 备选 D3-2：仅 KF8（放弃回退）——both 型文件回退段有更高保真度时反而读不到，且 KF8 解析
     风险大无兜底。双路径与 01-req §5 风险7 的降级线一致（"MOBI7 完整 + AZW3 回退段可读；
     KF8 尽力而为"）。
4. **章节 HTML 喂给既有 canonicalize 的方式**：**解析器内预处理，convert 零改动**。
   - 备选 D4-1：在 convert 增加 MOBI HTML 清洗函数——convert 是通用管线，为单一格式加私有清洗
     破坏复用性，且回归面变大。
   - 备选 D4-2（选）：在 mobi_common 内做清洗——剥 `mbp:` 命名空间标签、去内联 `font` 样式、
     补 DOCTYPE、**将 `<img src>` 重写为与 `Resource.source_path` 完全一致的规范化路径
     （`images/imageNNNN.ext`）**，使 canonicalize 的资源重写正则（精确匹配 + 后缀匹配）必然命中。
5. **错误分类**：**新增 `Error::Encrypted`**（domain 层 error.rs 追加变体），DRM 检测 =
   `encryption() != Encryption::No || metadata.mobi.has_drm()`，错误消息含"DRM/加密"字样。
   - 备选 D5-1：复用 `Error::Corrupt` 承载 DRM——01-req 指出语义不清晰，UI 无法区分"加密"与
     "损坏"，且 docs/03 §8 的 CoreError 分类本就列出 `Encrypted` 类，属文档-代码对齐。
   - 选 D5：新增变体；`api.rs` 的 `err_msg(Display)` 泛型映射无需改动即可透出文案。

## 影响
- **format/mod.rs**：`parse()` match 新增 `Format::Mobi | Format::Azw3` 两臂；
  `detect_format()` 的 `BOOKMOBI` 分支增强为"读 MOBI 头 type 字段，==248 判 Azw3，否则 Mobi"
  （满足 US-2 无扩展名嗅探；解析失败保守回退 Mobi）。
- **format/mobi.rs、format/azw3.rs**：空 stub → 实现；新增 **format/mobi_common.rs**（domain 层，
  ddd-rules 路径已覆盖，无需改规则表）。
- **error.rs**：新增 `Encrypted(String)` 变体（docs/03 §8 已有同名分类，属对齐而非新增约定）。
- **convert / library / api**：零改动（回归验证）；api 错误文案经泛型 Display 自动覆盖新变体。
- **docs/02 §3.3**：算法一致，无需改；**ddd-rules.toml**：无需改。
- **回归面**：epub/txt 解析路径零行为变化（parse 仅新增分支）；`detect_format` BOOKMOBI 分支
  仅影响 mobi/azw3 判定；corpus 新增 MOBI/AZW3/GBK/坏文件语料走既有评审规则。

## 闸门2 自评（ADR 部分）
- [x] 备选 ≥2 且给出理由（内核 A/B/C + 4 个决策点各含备选与选择理由）
- [x] 与既有约定一致（docs/02 §3.3/§8、docs/03 §8、ddd-rules、ParsedBook/canonicalize 管线）
