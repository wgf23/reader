<!-- wf-meta: req=REQ-002 | phase=architecture | agent=architect | date=2025-08-30 | gate=passed -->
# REQ-002 · 计划拆分（Task 分解）

## 任务清单

| Task | 内容 | 依赖 | 估算 | 验收 |
|---|---|---|---|---|
| **T-001** | **语料获取与校验**：① 真实公版下载（候选源见下，均已实际探测）；② calibre（开发机）从既有 corpus EPUB 生成受控语料（MOBI7 PalmDOC、AZW3 `--mobi-file-type=new`（KF8-only）与 `both`、GBK 中文 MOBI）；③ 构造坏文件（截断/垃圾/DRM 标记，脚本化）；④ 全部落 `tests/corpus/src/`，更新 `corpus/README.md`（来源/许可/大小/sha256） | — | 1d | `tests/corpus/src/` 新增 ≥6 文件：MOBI7（含图，≥2 pagebreak+INDX）、AZW3 both、AZW3 KF8-only、GBK 中文 MOBI、坏文件 ×2；README 每行含来源 URL、大小 <30MB、sha256；坏文件构造脚本 `scripts/make_bad_mobi.py`（或等效）在仓库内 |
| **T-002** | **mobi_common 内核**（design §2.1）：PdbBook 薄封装 + 错误映射、自研 `palmdoc_decompress`、`decode_text` 编码链（encoding_rs）、`sanitize_html`、`split_chapters`（pagebreak 主/标题回退）、`extract_images` + 魔数嗅探、`first_heading` | T-001 | 1.5d | 单元测试覆盖：PalmDOC 解压正确性（已知明文往返）、GBK(936)/UTF8/CP1252 解码无 `U+FFFD`、pagebreak/标题两种切分、图片嗅探 4 类魔数；损坏字节输入全部返回 `Err` 不 panic |
| **T-003** | **MOBI7 解析**（design §2.2）：mobi.rs 完整管线（元数据 EXTH、INDX 目录解析 + 章节标题回退、`chapters_and_toc`）接入 `format::parse` 的 Mobi 分支 | T-002 | 1.5d | US-1/US-5 在真实语料上通过：`format==Mobi`、title 精确一致、authors 非空、language 与 EXTH 一致、`chapters.len()≥2`、拼接文本逐字含已知句子、`toc[0]` 与语料目录一致、GBK 无乱码；无 INDX 语料不崩溃；`cargo test` 全绿（epub/txt 回归零行为变化） |
| **T-004** | **AZW3/KF8 解析**（design §2.3）：azw3.rs 双路径（`parse_kf8_rawml` 尽力而为 + `parse_fallback` 兜底）；`detect_format` BOOKMOBI 分支增强（type==248→Azw3） | T-002 | 1.5d | US-2 全部通过：both 型 `format==Azw3`、含图 `resources` 有 `image/` 条目；KF8-only 不报错且文本非空含已知句子；无扩展名 AZW3 嗅探为 Azw3（不得误判 Mobi）；与 `.mobi` 正确区分；KF8 双路径皆失败的坏文件返回 `Corrupt` 不 panic |
| **T-005** | **error.rs `Encrypted` + library/api 接入**：新变体 + api 文案断言；library 集成测试（import→open→chapter_html→resource→去重→DRM 错误路径） | T-003, T-004 | 1d | US-3/US-4 通过：DRM 标记语料 `Err` 且消息含"DRM/加密"；截断/坏文件 `Err(Corrupt)` 不 panic；`import_file` 返回 `format=="mobi"/"azw3"`、canonical_path 存在、二次导入同 id、书架仅 1 本；`book_chapter_html` 返回合法 XHTML 含已知句子；含图书 `book_resource` 字节与语料图片哈希一致；api 错误映射测试覆盖新变体 |
| **T-006** | **测试强化 + 基准**：变异测试（mobi/azw3/mobi_common ≥80%）、覆盖率（新代码行 ≥85%）、CRAP 报告、性能基准（criterion 或计时脚本：5MB 级 MOBI 单次解析 <200ms 桌面预算，CI 宽松 ≤2s）、corpus 回归纳入 p0_corpus 模式 | T-003, T-004 | 1.5d | 闸门4 报告齐全：`04-mutation-report.md`（存活体 100% 有结论）、`04-coverage-report.md`、`03-crap-report.md`（FAIL=0）、基准结果记录文件；既有 19 单测 + 5 语料 + FFI 端到端全绿 |

## 依赖图
```
T-001 → T-002 ─┬→ T-003 ─┐
               ├→ T-004 ─┼→ T-005 → T-006
               └─────────┘
（无环；T-003/T-004 并行；T-005 依赖两者；T-006 依赖 T-003/T-004 产出全部代码，
 与 T-005 可并行推进后合并；关键路径 T-001→T-002→T-003→T-005→T-006 ≈ 6.5d，T-004 并行不占关键路径）
```

## 语料候选源与校验（T-001 落地指引，均已实际验证可达性）
| 语料 | 候选源 | 验证结果 | 校验方式 |
|---|---|---|---|
| AZW3/KF8（英文，含图） | `https://www.gutenberg.org/ebooks/1342.kf8.images` → `https://www.gutenberg.org/cache/epub/1342/pg1342-images-kf8.mobi`（P&P Kindle 版） | `curl -sIL` → 302 后 200；`content-type: application/x-mobipocket-ebook`；`content-length: 25334202`（≈24MB，<30MB 上限） | 下载后 `head -c 16 | xxd` 校验 `BOOKMOBI` 魔数；`sha256sum` 记录；T-003/T-004 冒烟断言（章节数、已知句子） |
| AZW3/KF8（中文，UTF-8） | `https://www.gutenberg.org/ebooks/24264.kf8.images` → `https://www.gutenberg.org/cache/epub/24264/pg24264-images-kf8.mobi`（红楼梦 Kindle 版） | 同上，302 后 200；`content-length: 2373899`（≈2.3MB） | 同上；正文中文断言（无 `U+FFFD`） |
| AZW3 both / KF8-only（受控，确定性内容） | calibre（开发机）`ebook-convert tests/corpus/src/hongloumeng.epub out.azw3 --mobi-file-type=both / =new`（01-req §5 风险2 同款方案） | 本环境无 calibre → 由开发机生成后提交 corpus（来源/生成命令记录于 README） | 生成后校验魔数与类型：MOBI 头 type==248（KF8）；both 型再查 EXTH 121 边界存在；大小 <30MB |
| MOBI7 PalmDOC（英文，含图、pagebreak、INDX） | 备选：Feedbooks 公版 `.mobi`（如 `https://www.feedbooks.com/book/275.mobi` 形态）；**实测本环境 403 被拒** → 不作为主源；主用 calibre `ebook-convert pride-and-prejudice.epub out.mobi`（PalmDOC 压缩可控） | Feedbooks 403（需浏览器/UA 或换源，开发机手工下载亦可） | 魔数 + `compression==PalmDoc`（解析冒烟）；断言含 ≥2 pagebreak 与 INDX 记录（T-003 输出校验） |
| GBK 中文 MOBI | calibre `ebook-convert`（GBK 源 TXT → MOBI，或 `--input-encoding=gbk`），或从公版中文 TXT 自造 | 受控生成 | 断言章节文本含已知中文字符串且无 `U+FFFD`/乱码（US-5） |
| 坏文件（截断/垃圾/DRM 标记） | 脚本从真实语料派生：截断（PDB 头完整、记录区切断）、垃圾（`BOOKMOBI` 魔数 + 随机字节）、DRM 标记（PalmDOC encryption 字段置 1/2，或 EXTH DRM 标志 `0xFFFFFFFF`） | 构造 | 对应 `Error::Corrupt` / `Encrypted` 断言（US-3） |

> 语料规则（corpus/README.md + docs/05 §3）：只收无版权争议文件（Gutenberg 公版 / calibre 自造）、
> 单文件 < 30MB、来源与生成命令记录、变更评审；KFX 不做（docs/02 §3.5）。

## 冲突检查结果
- **与既有业务无冲突**：
  1. 不触碰 Locator/进度/听读模型（docs/04 §3/§9）——零改动，听读同进度不变式保持；
  2. 限界上下文（docs/04 §1）：改动全部在 domain 层 `core/src/format|error`，ddd-rules.toml
     的 domain 路径已覆盖新文件，规则表无需改；无 `store/api/library` 依赖；
  3. docs/02 §3.3 算法一致（PDB→解压→EXTH→拆章→抽图→规范 EPUB），§3.5 不做 DRM 破解一致；
  4. docs/03 §8 错误分类本就含 `Encrypted` 类——新增变体是对齐而非新增约定；api 桥接函数全部复用，
     无新接口；
  5. convert/library/api 零改动 → 回归面最小；epub/txt 解析路径零行为变化；
  6. 与 REQ-001（WebView 分页渲染）互不依赖，其 `book_chapter_html`/`book_resource` 作为消费端已就绪。
- **计划完整性**：T-001..T-006 覆盖"语料 → 内核 → MOBI7 → AZW3 → 接入/错误 → 测试/基准"全链，无缺口；
  任务粒度每项 ≤1.5d 且均有可断言验收；依赖图无环。
- **已知取舍（非冲突，已列处置）**：Feedbooks 在本环境 403 → 降级为开发机手工/浏览器下载或
  calibre 自造（处置：corpus 来源记录中注明，不阻塞主路径）；Gutenberg kf8 文件的"both vs
  KF8-only"属性以 T-003/T-004 冒烟实测为准（US-2 验收按可观察行为，不承诺内部路径）。

## 闸门2 自评（计划部分）
- [x] 任务粒度可执行（每任务 ≤1.5d、有验收）
- [x] 无依赖环（依赖图如上，T-003/T-004 并行）
- [x] 冲突检查通过（无冲突；两处已知取舍均含处置方案）
