<!-- wf-meta: req=REQ-009-notes-search | phase=architecture | agent=architect | date=2026-09-09 | gate=passed -->
# REQ-009 · 架构决策记录（ADR：CJK 全文搜索 / 选区锚点 / 持久化分层 / href 映射 / 索引时机 / 高亮渲染 / 面板与搜索页 / 导出 / 书签 / 桥接 / 真实集成测试 / 冲突）

## 决策（一句话）

在**不改既有 Locator / `reading_progress` / 听读同进度不变式**的前提下，用四条正交链路把「笔记」与「全文搜索」从零落地：

1. **搜索**：`fts_books` 虚拟表**复用**，新增 `href`/`text`（UNINDEXED，存原文）与 `text_bi`（唯一索引列）；**应用层 CJK 二元组（bigram）预处理**索引与查询，解决 `unicode61` 对 2 字中文词零命中的硬需求（US-18），单字 CJK 走 LIKE 回退，空查询短路，特殊字符短语引用防注入；
2. **锚点**：`LocatorResolver::from_selection(text, book_id, href, sel)` 在**章全文**内按归一化匹配 + 当前 `progression` 消歧生成 `TextAnchor{start,end}`（UTF-16 半开区间），失败降级为 `progression` 锚并置 `text=None`；
3. **持久化**：`AnnotationRepository` / `SearchIndexRepository` 契约放 `core/src/types.rs`，实现放 `core/src/store/{annotations,search_index}.rs`（第二连接，**显式 `PRAGMA foreign_keys=ON` + `busy_timeout`**），`core/src/{notes,search}` 只依赖 trait（ddd-rules 合规）；`annotations` 表**逐列对齐 `docs/04 §5:155-167`**；
4. **渲染/交互**：`ChapterSection` 由单 `Text` 改 `Text.rich` 分段合成（纯函数 `composeSpans`），笔记面板为 ReaderPage 内**右侧 360px 覆盖层**（对齐线框 07），搜索页为独立路由（对齐线框 04），书签并入笔记面板（`kind=bookmark`），导出经可注入 `ExportPathPicker`（桌面 file_picker / 移动 path_provider）。

**零布局自创**：入口全部收进既有「⋯更多」弹层（搜索/笔记/导出），底栏书签图标复用（线框 `02-menus.svg:31-32`），不新增顶栏图标、不改顶/底栏结构。

---

## 决策点 D1：CJK 全文搜索分词（最高优先，US-18 强制「2 字中文词必须命中」）

**现状（已核实）**：`fts_books` 未建；`docs/04 §5:198-202` 的 DDL 为 `fts5(book_id UNINDEXED, chapter, text, tokenize='unicode61')`。本机实测（SQLite **3.53.2**，bundled rusqlite 0.40.2 / libsqlite3-sys 0.38.2）语料 `"看不见的城市，卡尔维诺写道：城市是记忆的。"`：

| 方案 | 查 `城市`(2) | 查 `卡尔维诺`(4) | 查 `记忆`(2) | 查 `城`(1) | 查 `看不见的城市`(6) |
|---|---|---|---|---|---|
| `unicode61` 原始 | **0** | **0** | **0** | 0 | 1 |
| `trigram` | **0** | 1 | 0 | **0** | 1 |
| **bigram 预处理 + `unicode61`** | **1** | **1** | **1** | 0 | 1 |

结论与 01-req §5 风险1 一致：`unicode61` 把连续汉字整段当一个 token；`trigram` 对 <3 字查询零命中。**二者都不能满足 US-18**。

### 备选

- **A（选）：应用层 CJK bigram 预处理 → 写入 FTS5 `unicode61` 的可索引列 `text_bi`；查询同法预处理后按 FTS5 短语引用**
  - 索引侧：CJK 连续段（`U+3400..=U+9FFF`/扩展 A、`U+F900..=U+FAFF`、假名 `U+3040..=U+30FF`、谚文 `U+AC00..=U+D7AF`）切成重叠二元组，空格分隔；单字 CJK 段保留单字；ASCII 字母数字按整词小写保留；标点/空白为边界。例：`看不见的城市，卡尔维诺写道` → `看不 不见 见的 的城 城市 卡尔 尔维 维诺 诺写 写道`。
  - 查询侧：对每个空格分词项做同一预处理，`"bigram 序列"` 作为 FTS5 **短语**，多项之间 `AND`；空项过滤；全空 → `None` 短路（不触达 FTS）。
  - 原文另存 `text` 列（**UNINDEXED**）供应用层抽 snippet + 计算关键词区间；`href`/`chapter` 亦 UNINDEXED。
  - 优点：**本机实测 2/4/6 字中文词全部命中**；纯 Rust 字符串处理，**零新依赖、零 Cargo feature、零自定义 tokenizer**（避免 `rusqlite` `fts5` feature + unsafe C API 在 Android 交叉编译的风险）；查询 50–210µs（1000 章语料），索引 1000 章 13ms，远低于 100ms；FTS5 语法注入被短语引用隔离（`%`/`_`/`"`/`*`/`NEAR` 全部安全）。
  - 缺点：① 改 `docs/04 §5` 的 `fts_books` DDL（新增 `href`/`text_bi`，`text` 改 UNINDEXED）；② 索引体积约翻倍（bigram + 原文），实测可忽略；③ 单字 CJK 仍零命中（见降级线）；④ 跨标点短语不匹配（可接受，中文检索按词）。
- **B：`trigram` tokenizer + 短查询回退**
  - 优点：FTS5 内建，索引侧零预处理。
  - 缺点：**2 字/1 字查询零命中**（实测），US-18 强制项不达标；要达标必须叠加「<3 字转 LIKE」，等于把主路径退化为全表 LIKE，失去 FTS 索引收益；`trigram` 还需 SQLite ≥3.34（当前 3.53 满足，但 Android 端 bundled 版本需同步确认）。**拒绝为主方案**。
- **C：自定义 FTS5 tokenizer（`rusqlite` `fts5` feature + `sqlite3_fts5_create_tokenizer`）**
  - 优点：索引/查询侧对上层透明，FTS 语义完整。
  - 缺点：需改 `Cargo.toml` 启用 `rusqlite/fts5`，手写 unsafe FFI tokenizer 回调（生命周期/内存所有权复杂）；Android 三 ABI 交叉编译与 FRB 生成面风险高；CRAP/变异测试难覆盖。**拒绝**（作为 A 在极端语料下失效时的远期备选）。
- **D：纯 LIKE/子串回退（不用 FTS）**
  - 优点：2 字中文必命中、零 DDL。
  - 缺点：无法利用 FTS 索引，全库全表扫描；US-21 的 <100ms 在真实书库规模下不可保证，且 snippet/区间需自研。**拒绝为主方案**（仅保留为**单字 CJK 的短查询回退**）。

### 选择与理由

选 **A**。它是唯一在本机实测中让 `城市`/`卡尔维诺`/`记忆` 全部命中、同时保留 FTS 索引与 snippet 能力的方案，且不引入新依赖/feature/tokenizer。`docs/04 §5` 的 DDL 变更**仍复用 `fts_books` 虚拟表**，不新增不必要的表；对「不新增不必要表结构」约束的满足方式 = **只扩充既有 FTS 虚拟表的列，不新建表**。

### 新 DDL（同步 `docs/04 §5:198-202`，由 developer 在实现阶段落文档）

```sql
-- 全文搜索（FTS5）：text_bi 为唯一索引列（CJK bigram 预处理流）；
-- href/chapter/text 仅存储（UNINDEXED），text 供应用层抽 snippet 与关键词区间。
CREATE VIRTUAL TABLE IF NOT EXISTS fts_books USING fts5(
  book_id UNINDEXED,
  href    UNINDEXED,
  chapter UNINDEXED,
  text    UNINDEXED,
  text_bi,
  tokenize='unicode61'
);
```

> 说明：`CREATE VIRTUAL TABLE IF NOT EXISTS` 幂等；Store 主连接与第二连接共享 `migrate_conn` 时不会重复建表报错（US-23）。

### 可测断言锁定（写入 US-18/US-21 验收）

- `search("城市")`、`search("卡尔维诺")`、`search("记忆")` 各 ≥1 条命中（对含该词的中文语料）。
- 查询耗时 CI 门槛 **≤100ms**（本机实测 ≤0.21ms；测试用 `Instant` 断言并打印实测值）。
- 特殊输入 `% _ " * NEAR` 空串/纯空白 → 不抛异常；空查询短路返回空列表。
- 单字 CJK（如 `城`）→ **LIKE 回退**命中（`text LIKE '%城%'`，实测 1）。

### 影响
- `docs/04 §5` 的 `fts_books` DDL 需同步（developer 落文档）。
- `core/src/search/mod.rs` 新增纯函数 `bigram_index_text` / `build_match_expr` / `extract_snippet`。
- `core/src/store/search_index.rs` 只负责持久化 `text_bi` 与查询，不感知分词算法（算法在 domain）；契约分两条路径：`query_fts(match_expr, …)`（≥2 字 CJK/ASCII）与 `query_substring(needle, …)`（单字 CJK 的 LIKE 回退），由 domain `SearchService::query` 按 `is_single_cjk_char` 选择。

### 降级线（授权）
若真机/大语料下 bigram 索引体积或首查回填超预算：**降级为 A′ = bigram + 每书行数上限**（超长章按段落分片多行插入，保持 `text_bi` 语义），断言不变。若某平台 FTS5 不可用：**降级为 D（LIKE）**，但必须保留 `SearchHit` 结构（`snippet`/`ranges` 不变）并放宽 US-21 为 CI 宽松门槛（真实书库 ≤500ms），由 developer 在 T-007 记录。

---

## 决策点 D2：选区字符偏移与锚点生成（`TextAnchor{start,end}` 从何而来）

**现状（已核实）**：滚动模式 `SelectionArea.onSelectionChanged` 只给 `SelectedContent.plainText`（`reader_page.dart:799`、`_sliceSelection:540`）；Flutter `SelectedContent` 仅 `plainText`（`selection.dart:200-214`），`SelectedContentRange{startOffset,endOffset}` 只能经 `SelectionHandler.getSelection()` 取（`selection.dart:96-100/125-194`）。

### 备选

- **A（选）：`LocatorResolver::from_selection` 用选中文本在**章全文**内匹配 + 当前 `progression` 消歧**
  - 做法：Dart 把 `{book_id, href, 选中 plainText, 当前章内 progression}` 传桥接；`api.rs` 经 `chapter_text(book_id, href)` 取章全文，调 domain `from_selection(text, book_id, href, &TextSelection{snippet, progression})`。
  - 匹配：先按「空白折叠归一化」在章文本内找所有出现位置，并用归一化→原文的 UTF-16 偏移映射表还原 `start/end`；失败再原始精确匹配、再去空白模糊匹配。
  - 消歧：候选 `score = |occ_start / utf16_len(text) - progression|`，取最小；并列取最早。
  - 降级链：文本锚（`text=Some`）→ 无匹配则 `text=None` + `progression` 兜底（UI 标记「位置可能不精确」）→ href 无效则章首。
  - 优点：与 `docs/04 §3` 定位算法逐条一致；纯函数、可 `[单测]`（US-4/5）；不依赖 Flutter 私有 API；UTF-16 半开区间与 REQ-005 `TextAnchor`/`SentenceChunk` 同尺度，Dart `substring` 可直接切片。
  - 缺点：连续滚动跨章选中时只能锚到「当前可见章内」的子串（本期接受，见 §范围）。
- **B：接入 `SelectionHandler.getSelection()` 的 `SelectedContentRange`**
  - 优点：偏移由 Flutter 直接给出，无需文本匹配。
  - 缺点：`SelectionArea` 的 handler 需经 `GlobalKey` 访问（`SelectableRegionState` 非稳定公开面）；连续滚动下偏移是**整个 SelectableRegion 拼接内容**的坐标（跨多个 `Text`、WidgetSpan 被拍平），映射回单章文本极脆弱；测试注入困难。**拒绝为主方案**。
- **C：Dart 侧文本匹配生成偏移**
  - 优点：不新增桥接字段。
  - 缺点：Dart 侧要做归一化/消歧/UTF-16 映射，逻辑与 Rust `LocatorResolver` 重复且无法 `cargo test`；锚点权威应落核心层（docs/03 架构原则）。**拒绝**。

### 选择与理由

选 **A**。`docs/04 §3` 已把「文本锚最稳、progression 兜底」定为领域规则，A 正是该规则的可实现形态；且与 REQ-005 的「domain 文本入参纯函数」先例同构（domain 不读 IO，由 `api.rs` 取文本）。US-4 的「重排后仍命中同段」由「渲染时重新用 snippet 解析」天然满足。

### 接口签名

```rust
// core/src/locator/mod.rs（domain；只 use crate::types / crate::error）
pub struct LocatorResolver;
impl LocatorResolver {
    /// 由选中片段 + 当前章内进度生成文本锚；无匹配 → text=None（progression 兜底）。
    pub fn from_selection(
        text: &str,            // 章全文（UTF-16 语义）
        book_id: &BookId,
        href: &str,
        sel: &TextSelection,   // { snippet, progression }
    ) -> Result<Locator>;
    /// 取锚点对应原文片段（面板/导出用；无文本锚 → Err/空）。
    pub fn text_at(text: &str, loc: &Locator) -> Result<String>;
}
```

### 降级线（授权）
若真机长按选区含大量换行/标点导致归一化匹配失败率超预期：**降级为「原始精确匹配优先，归一化仅作二次」**，并允许 `progression` 兜底比例上升；`TextAnchor` 结构与 US-4/5 断言（不丢/不漂移）不变。**禁止**降级为「只存 progression」（会丢失 US-4 的重排精确定位）。

---

## 决策点 D3：annotations 持久化与分层（契约位置 / 连接 / 事务 / 外键）

**现状（已核实）**：`annotations` 表未建（`store/mod.rs:252-319` 止于 v3）；`TranslationRepo` 第二连接只设 WAL+busy_timeout、**未设 FK**（`translation.rs:32`）；主连接设 `foreign_keys=ON`（`store/mod.rs:54`）但**未设 busy_timeout**；`docs/04 §5:155-167` 已给出 `annotations` DDL。

### 备选

- **A（选）：契约（`AnnotationRepository`/`SearchIndexRepository`）放 `core/src/types.rs`；实现放 `core/src/store/{annotations,search_index}.rs`（各自第二连接，**显式 FK ON + busy_timeout**）；domain 只依赖 trait**
  - 优点：与 REQ-003 `TranslationCacheRepository` 完全同构；ddd-rules 冻结规则下 `store/*` 只 `use crate::types` 即合规（domain 禁 `crate::store` 被满足）；每个仓储独立连接便于单测与并发；FK ON 使笔记插入/删除不会产生孤儿。
  - 缺点：库内连接数增至 4（主 / Translation / Annotation / SearchIndex），需统一 `busy_timeout` 防 `SQLITE_BUSY`。
- **B：让 `AnnotationRepository` 由 `Store` 直接实现（单连接）**
  - 优点：单连接、事务简单。
  - 缺点：`LibraryService` 已持有 `Store`，无法同时把它 move 进 `AnnotationService` 的 `Box<dyn ...>`（所有权冲突）；需引入 `Arc<Mutex<Connection>>` 改造，回归面大。**拒绝**。
- **C：笔记复用 `TranslationRepo` 第二连接**
  - 缺点：语义耦合（翻译仓储承担笔记），且其连接未设 FK，需改既有文件；不如新增专用仓储清晰。**拒绝**。

### 选择与理由

选 **A**。契约落共享内核是 ddd-rules 下 `store` 实现跨层契约的唯一合规路径（REQ-003 先例）。**笔记走 Annotation 专用第二连接**（不是主连接、不是 Translation 连接），并**修复式地给该连接设 `PRAGMA foreign_keys=ON`**；同时给 Store 主连接补 `PRAGMA busy_timeout=5000`（4 连接 WAL 下的必要并发保护，属零语义基础设施改动）。

### 迁移 v4 完整 DDL（同步 `docs/04 §5`；逐列对齐 `docs/04 §5:155-167`）

```sql
-- ===== v4：笔记 + 全文索引（REQ-009）=====
CREATE TABLE IF NOT EXISTS annotations (
  id            TEXT PRIMARY KEY,                                   -- uuid
  book_id       TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  kind          TEXT NOT NULL,                                      -- highlight|underline|note|bookmark
  color         TEXT,                                               -- 高亮/划线颜色（#RRGGBB）
  locator_json  TEXT NOT NULL,                                      -- Locator 序列化
  snippet       TEXT,                                               -- 原文快照（冗余，列表/导出用）
  note_text     TEXT,                                               -- 批注内容（note 类必填）
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  sync_status   TEXT NOT NULL DEFAULT 'local'                       -- local|dirty|synced（同步预留）
);
CREATE INDEX IF NOT EXISTS idx_annot_book ON annotations(book_id, updated_at);

CREATE VIRTUAL TABLE IF NOT EXISTS fts_books USING fts5(
  book_id UNINDEXED,
  href    UNINDEXED,
  chapter UNINDEXED,
  text    UNINDEXED,
  text_bi,
  tokenize='unicode61'
);
PRAGMA user_version = 4;
```

- **幂等**：全部 `IF NOT EXISTS` + `user_version` 判定；主/第二连接共享 `migrate_conn`（`store/mod.rs:252`、`translation.rs:34`），重复打开为 no-op（US-23）。
- **外键边界**：`annotations.book_id` 级联删依赖执行 DELETE 的连接 FK ON。`library_remove` 走主连接（FK ON）→ 级联删 annotations。**`fts_books` 是虚拟表，不参与 FK 级联**，故 `Store::remove_book` 必须在同一事务内显式 `DELETE FROM fts_books WHERE book_id=?`（US-15）。
- **事务**：`remove_book` 用 `conn.transaction()` 包住「删 fts 行 + 删书（级联 annotations/progress）」。

### 影响
- `core/src/store/mod.rs`：v4 分支 + `remove_book` 显式删 FTS + 主连接补 `busy_timeout`。
- 新增 `core/src/store/annotations.rs`、`core/src/store/search_index.rs`。
- `core/src/types.rs`：新增契约与值对象。
- `docs/04 §5` 需同步（developer 落文档）。

### 降级线（授权）
若 4 连接在真机出现 `SQLITE_BUSY` 频发：**降级为「Annotation/SearchIndex 共享一条连接」**（`Store` 暴露 `conn_ref()` 或新增 `Store::open_repositories()` 返回共享句柄），事务语义与断言不变；**禁止**把笔记写进 `reading_progress` 或新建进度表。

---

## 决策点 D4：`fts_books` 的 href/章节映射

**现状（已核实）**：`docs/04 §5:198-202` 的 DDL 只有 `book_id/chapter/text`，**无 href**；而搜索定位必须给 `Locator.href`（`types.rs:21`、`_chapterIndexForHref` 依赖 `chapter_%04d.xhtml`）。

### 备选

- **A（选）：给 `fts_books` 增 `href` 列（UNINDEXED），索引时随章写入**
  - 优点：结果行直接带 href，零回查；`chapter` 列继续存章节标题；与 US-19「定位到命中位置」直接对接。
  - 缺点：改 DDL（已与 D1 的 DDL 变更合并为一次 v4）。
- **B：`chapter` 列改存 href，章节标题查询时回查**
  - 优点：不加列。
  - 缺点：结果列表要显示「第 N 章 · 章节名」，必须再回查书库章节列表，`search` 变两次 IO；且破坏 `chapter` 列语义。**拒绝**。
- **C：结果只给 book_id + 片段，定位时按章节名回查 href**
  - 缺点：章节名可重复/为空，回查不可靠；US-19 跨书定位易错。**拒绝**。

### 选择与理由

选 **A**。一次写入、零回查，且 `href` 与 `book_id` 同源于 `Chapter.href`（`core/src/format/mod.rs:51-54` 已有 href）。

### 结果结构（`core/src/types.rs`）

```rust
pub struct TextRange { pub start: u32, pub end: u32 }   // UTF-16 半开区间
pub struct SearchHit {
    pub book_id: BookId,
    pub book_title: String,
    pub href: String,
    pub chapter_title: String,
    pub snippet: String,          // 上下文片段（应用层抽取，含关键词）
    pub ranges: Vec<TextRange>,   // 关键词在 snippet 内的 UTF-16 区间（可多个）
    pub score: Option<f64>,       // FTS5 bm25 rank（仅排序/展示，可空）
}
```

### 降级线（授权）
若 `href` 在旧书回填时缺失（规范 EPUB 章节非 `chapter_%04d` 命名）：回填时以 `open_book` 的 `Chapter.href` 为准写入；仍缺失则 `href=""` 并在结果中过滤该行（不返回不可定位的命中）。US-18/19 的「可定位」断言不降级。

---

## 决策点 D5：索引构建与旧书回填时机

**现状（已核实）**：`LibraryService::import_file`（`library/mod.rs:32-60`）入库不建索引；`SearchService` 无调用点（R14）；v4 前旧书无 FTS 行。

### 备选

- **A（选）：导入时建索引 + 首次搜索时按书**懒回填**（`is_indexed` 判定）**
  - 导入：`api.rs::library_import` 在 `import_file` 成功后 `open_book` → 组装 `IndexedChapter` → `SearchService::index_book`（FRB 调用在池线程，UI 不阻塞；US-21「导入即可搜」）。
  - 旧书：`api.rs::search` 先按 scope 取书列表，对 `!is_indexed(book_id)` 的书执行一次 `open_book` + `index_book`（每书至多一次；US-23「旧书可搜」）。
  - 打开：`book_open` **不**触发索引，保证打开不被索引拖慢。
  - 优点：US-21/US-23 同时满足；回填有界（按需、每书一次）；迁移只建表，不因解析全书而变慢。
  - 缺点：首次搜索若有大量旧书会有一次批量索引（可接受；可用「逐书 + 进度提示」缓解）。
- **B：v4 迁移时回填全部旧书**
  - 缺点：`migrate_conn` 是 infrastructure，无法解析 EPUB；迁移内做 IO 违反迁移轻量原则，长库升级卡顿。**拒绝**。
- **C：打开书时建索引**
  - 优点：语义自然。
  - 缺点：`book_open` 是同步高频路径，加索引会拖慢打开（与 01-req「不阻塞打开」冲突）；且未打开过的旧书仍搜不到，US-23 不满足。**拒绝**。
- **D：仅导入时建索引，旧书不回填**
  - 缺点：US-23 不达标。**拒绝**。

### 选择与理由

选 **A**。导入即搜 + 首次搜索懒回填，覆盖 US-21/US-23，且把成本放在「确实要搜索」时；索引调用全部在 async 桥接的池线程。

### 影响
- `api.rs::library_import` / `api.rs::search` 编排索引与回填。
- `SearchIndexRepository` 提供 `is_indexed(book_id)` / `replace_book(book_id, chapters)` / `remove_book(book_id)`。
- `IndexedChapter { href, chapter_title, text, text_bi }` 由 `api.rs` 从 `Chapter` + domain `bigram_index_text` 组装。

### 降级线（授权）
若首次搜索懒回填超时：**降级为「本次搜索只回填前 N 本（N=20）+ 返回已索引结果 + 提示『部分书籍正在建立索引』」**，后续搜索继续回填；US-23 断言改为「重复搜索后旧书可搜到」。**禁止**放弃回填。

---

## 决策点 D6：正文高亮渲染与临时高亮

**现状（已核实）**：`ChapterSection` 正文为单个 `Text(chapter.text)`（`continuous_scroll_policy.dart:216-224`），无法内联多色；TTS 跟读高亮是独立 `ListenFollowHighlight`（`listen_follow_highlight.dart`，单色临时，不入库，仅听书页）。

### 备选

- **A（选）：`ChapterSection` 改 `Text.rich`，纯函数 `composeSpans` 计算原子分段；持久化/临时/TTS 三类高亮分离**
  - 纯函数：`composeSpans(text, List<NoteSpanData>, TempHighlightData?) -> List<NoteSpan>`，边界取所有 span 端点并集排序，逐原子区间合并样式（背景取覆盖该区间的**最后一条**高亮颜色；划线取并集；批注加虚线下划线）。
  - 三类分离命名：
    - **持久化**：`NoteSpanData`（来自 `annotations`，多色，落库）。
    - **临时跳转反馈**：`TemporaryHighlight`（`key: Key('temp-highlight')`，蓝色半透明 `0x331A73E8`，超时/滚动/点击消失，不落库）。
    - **TTS 跟读**：`ListenFollowHighlight`（仅听书页，`0x401A73E8`，不改）。
  - 优点：单一渲染出口可 `[单测]`（US-5 重叠不崩溃、US-1 色 span 文本 == snippet）；与 TTS 组件物理隔离；临时高亮有稳定 key 可断言（US-8/19）。
  - 缺点：正文 widget 结构变化 → golden/截图需同步（已列入 plan）。
- **B：用 `WidgetSpan`/自绘 `CustomPaint` 叠加高亮**
  - 缺点：选区坐标与文本流对齐复杂，`SelectionArea` 跨 span 选中易回归；测试困难。**拒绝**。
- **C：把持久化高亮交给 `SelectionArea` 的高亮 API**
  - 缺点：Flutter 无此公开 API。**拒绝**。

### 选择与理由

选 **A**。`Text.rich` 是 Flutter 内联多色文本的既有能力，纯函数分段便于覆盖重叠/多色/划线/批注；三类高亮按「数据源 + 生命周期 + 颜色/组件」彻底分离，符合 01-req §3.5。

### 关键结构

```dart
// app/lib/pages/note_span_policy.dart（interface，纯逻辑）
class NoteSpanData { final int start; final int end; final String kind; final String? color; final int order; }
class TempHighlightData { final int start; final int end; }
class NoteSpan { final int start; final int end; final TextStyle? style; final bool isTemporary; }
List<NoteSpan> composeSpans({ required String text, required List<NoteSpanData> annotations, TempHighlightData? temp });
```
`ChapterSection` 新增**可选**参数 `List<NoteSpanData> annotations = const []`、`TempHighlightData? tempHighlight`（默认 null → 渲染与既有 `Text(chapter.text)` 等价的单 span，保证 REQ-008 既有测试不破）。

### 降级线（授权）
若重叠区间导致 `Text.rich` 在极端情况下性能/断行异常：**降级为「重叠区域取最后一条，其余区间正常分段」**（仍不崩溃、每条记录仍存在），US-5 的「3 条记录 + 区间正确」断言不变。

---

## 决策点 D7：笔记面板与搜索页导航/交互（逐屏映射 06/07/04）

**现状（已核实）**：`notes_page.dart`/`search_page.dart` 各 14 行骨架；`_openMore` 有「笔记/导出」占位（`reader_page.dart:467-468`）；底栏书签为会话内 `_bookmarked`（`:113/:724`）。

### 备选

- **A（选）：笔记面板 = ReaderPage 内右侧 360px 覆盖层（`Stack` + 调暗 + 点外关闭）；搜索页 = 独立路由 `SearchPage`；书签并入笔记面板；入口收进「⋯更多」**
  - 面板对齐线框 07：标题「笔记」+ ✕、搜索框「搜索笔记」、章节分组（组头章节名 + 色标竖条 + 原文片段 + 批注 + 时间 `MM-dd`）、底部「导出 / 全部删除」、编辑批注卡片（保存/删除）、打开时主体调暗、点面板外关闭。宽度 `min(360, 屏宽*0.9)`，右侧贴边，不挤压正文布局（覆盖层）。
  - 搜索页对齐线框 04：顶部搜索框 +「全文搜索」按钮、结果行（书名粗 + 「第 N 章 · 章节名」+ 上下文关键词蓝色加粗 + 「定位」）、右侧筛选面板（按范围 全部书籍/当前书籍 + 按格式 EPUB/PDF/MOBI 复选 + 「结果 N 条 · X.XXs」）。
  - 入口：`_openMore` 增「搜索」项（现有「笔记/导出」改为真实动作）；**不改** `ReaderTopBar`/`ReaderBottomBar` 结构。
  - 书签：`kind=bookmark` 并入笔记面板（书签行显示 🔖 + 位置 + 时间，无颜色竖条），避免新增未在线框中的「书签页」。
  - 优点：线框 07/04 逐项可核对；零顶/底栏布局改版；书签复用 annotations 与面板，无新表新屏。
  - 缺点：书签混在笔记列表需在面板内区分渲染（属同屏渲染变体，非布局自创）。
- **B：笔记面板用 `Drawer`（左侧滑出）**
  - 缺点：与线框 07「右侧 360px、点外部关闭、主体调暗」不符。**拒绝**。
- **C：书签独立页面/独立底部弹层**
  - 缺点：线框无此屏；US-14 明确允许并入。**拒绝**（减少未映射屏）。
- **D：搜索页做成 ReaderPage 内的覆盖层**
  - 缺点：线框 04 是独立全屏（顶部搜索条 + 右侧筛选），覆盖层会与阅读器手势冲突。**拒绝**。

### 选择与理由

选 **A**。线框 07/04 是 UI 权威，A 逐项映射；书签并入满足 US-14 且不新增屏；入口收进既有「更多」满足 01-req §1.5「入口位置由架构定，不新增视觉样式」。

### 逐屏映射（摘要；完整表见 `02-design.md §6`）

| 屏 | 线框 | 关键控件 | 交互 |
|---|---|---|---|
| 选词工具条 | `06-selection-toolbar.svg` | 复制 / 高亮（4 色点）/ 划线 / 批注 / 翻译（+ 保留查词） | 长按/双击选中；随选区定位不遮挡；拖手柄调整 |
| 笔记面板 | `07-annotation-panel.svg` | 标题「笔记」+✕；搜索框「搜索笔记」；章节分组 + 色标 + 片段 + 批注 + 时间；底部导出/全部删除；编辑卡片 | 点条目跳回原文并临时高亮；点外部关闭；多选批量删除 + 二次确认 |
| 全文搜索 | `04-search.svg` | 搜索框 +「全文搜索」；结果行（书名/章节/上下文关键词高亮/定位）；右侧筛选（范围+格式+结果数/耗时） | 输入后点按钮；点「定位」跳转并高亮关键词 |
| 阅读器入口 | `reader-ui-v2/02-menus.svg:31-32`、`05-reader.svg:15` | 底栏 🔖 复用；「⋯更多」增搜索/笔记/导出 | 零布局改版 |

### 降级线（授权）
若 360px 覆盖层在窄屏（<420dp）遮挡正文过多：**降级为「面板宽度 = 屏宽*0.92 且可横向滑动」**，控件与交互顺序不变，线框 07 的「右侧面板 + 点外关闭」语义保留。

---

## 决策点 D8：导出路径策略（桌面保存框 / 移动端应用目录）

**现状（已核实）**：`notes_export` 桥接不存在；`_openMore` 导出为占位（`reader_page.dart:468`）；`file_picker ^8`、`path_provider ^2.1` 均已在 `pubspec.yaml:15-16`。

### 备选

- **A（选）：可注入 `ExportPathPicker` 接口；桌面 `FilePicker.platform.saveFile`，移动 `path_provider` 应用文档目录；`notes_export` 返回 `ExportSummaryView`**
  - 桌面：`saveFile(dialogTitle, fileName, type: custom, allowedExtensions)`；用户取消 → 返回 null → **不调用** `notes_export`、无错误提示。
  - 移动：`getApplicationDocumentsDirectory()/reader_notes/<sanitized-book>_<ts>.<ext>`，导出后可观察/分享路径。
  - 空笔记：`notes_export` 在 `note_count == 0` 时返回 `Err("暂无笔记")`，不创建文件（US-17）。
  - 优点：widget 测试注入 fake picker（返回临时路径/取消/null）即可覆盖 US-17；UI 不阻塞（async 桥接）。
- **B：全部平台直接写应用文档目录（不弹保存框）**
  - 缺点：桌面端与线框/需求「弹保存对话框」不符。**拒绝**。
- **C：Dart 侧组装 Markdown/JSON 文本，Rust 只落库**
  - 缺点：导出字段/转义需在 Dart 重做，违背「核心业务在 Rust」；US-16 的 `[单测]` 无法覆盖 Rust 导出。**拒绝**。

### 选择与理由

选 **A**。路径选择是 UI 职责（可注入、可测），内容生成/转义是核心职责（Rust `notes_export`）。

### 接口签名

```dart
// app/lib/services/export_path_picker.dart（interface）
abstract class ExportPathPicker {
  /// 返回目标绝对路径；用户取消返回 null。
  Future<String?> pick({required String suggestedName, required String extension});
}
```
```rust
// core/src/api.rs
pub async fn notes_export(book_id: String, fmt: String, out_path: String)
    -> std::result::Result<ExportSummaryView, String>;   // fmt: "markdown"|"json"
pub struct ExportSummaryView { pub path: String, pub note_count: u32, pub format: String }
```

### 降级线（授权）
若移动端无可用分享通道：导出后**在面板内显示完整路径并支持「复制路径」**（`Clipboard`），US-17 真机项改为「路径可观察」；桌面保存框行为不降级。

---

## 决策点 D9：书签（`kind=bookmark` + 幂等切换 + 列表跳转）

**现状（已核实）**：`_bookmarked` 仅 `setState`（`reader_page.dart:113/724`），无落库、无列表。

### 备选

- **A（选）：书签 = `annotations` 中 `kind=bookmark` 的一行；`notes_toggle_bookmark` 幂等切换；并入笔记面板列表跳转**
  - 落库：`locator_json` 存当前 `Locator`（`book_id/href/progression/text.snippet`），`color/note_text` 为 NULL。
  - 幂等切换：按 `(book_id, href, round(progression,3))` 查既有 bookmark；有则删（返回 `bookmarked=false`），无则建（返回 `bookmarked=true, note_id`）。
  - 列表：`notes_list` 返回含 bookmark；面板书签行渲染 🔖 + 时间；点击跳转复用 US-8 定位语义。
  - 优点：零新表、复用 `annotations` 与面板；US-14「重开后图标状态正确」由 `notes_list` 反查当前位置书签得到。
- **B：新增 `bookmarks` 表**
  - 缺点：`docs/04 §2.1` 已把书签归入 `Annotation` 聚合（`kind=bookmark`），新表制造第二事实源。**拒绝**。
- **C：仅会话内（维持现状）**
  - 缺点：US-14 不达标。**拒绝**。

### 选择与理由

选 **A**。与 `docs/04 §5` 的 `kind` 枚举（`highlight|underline|note|bookmark`）一致，零新表。

### 接口签名

```rust
pub async fn notes_toggle_bookmark(
    book_id: String, href: String, progression: f32, snippet: Option<String>,
) -> std::result::Result<BookmarkToggleView, String>;
pub struct BookmarkToggleView { pub bookmarked: bool, pub note_id: Option<String> }
```

### 降级线（授权）
若同页多次点击产生「同 href 不同 progression」的重复书签：**降级为「同 href 只保留一条书签」**（切换时按 href 删除旧行再建新行），US-14 幂等断言不变。

---

## 决策点 D10：桥接 DTO 与 FRB codegen

**现状（已核实）**：`api.rs` 无 notes/search DTO 与函数（R8）；`library_open` 已有双单例装配先例（`api.rs:155-183`）；FRB 2.13；codegen 命令见 `bridge/README.md:17-19`。

### 备选

- **A（选）：新增 `*View` DTO（与 Dart DTO 一一对应）+ 全部 async 桥接；`library_open` 增装配 NOTES/SEARCH 单例；codegen 后不手改生成物**
  - 优点：沿用 `DictInfoView`/`LocatorView` 命名与装配模式；async 保证导出/搜索/索引不阻塞 UI；Dart 侧经 services 映射，pages 不碰 `src/rust/`。
- **B：直接桥接 domain `Annotation`/`Locator`**
  - 缺点：`Locator` 含 `Rect/TextAnchor/cfi/page`，桥接面膨胀；`NoteKind` 枚举桥接形态不稳。**拒绝**。
- **C：Dart 直接 import 生成物做页面**
  - 缺点：违反 `ddd-rules.toml:16`。**拒绝**。

### 选择与理由

选 **A**。与 REQ-003/005 桥接面一致，字段一一对应可测（`rust_bridge_test.dart` 模式）。

### DTO 清单（Rust ↔ Dart）

| Rust DTO（`api.rs`） | 字段 | Dart DTO（`services/*_backend.dart`） |
|---|---|---|
| `TextSelectionView` | `book_id, href, text, progression` | `TextSelectionData` |
| `AnnotationView` | `id, book_id, kind, color?, href, progression, snippet?, note_text?, start?, end?, created_at, updated_at, sync_status` | `AnnotationData` |
| `NoteGroupView` | `chapter_title, href, notes: Vec<AnnotationView>` | `NoteGroupData` |
| `NotePatchView` | `note_text?, color?, kind?` | `NotePatchData` |
| `BookmarkToggleView` | `bookmarked, note_id?` | `BookmarkToggleData` |
| `RangeView` | `start, end` | `TextRangeData` |
| `SearchHitView` | `book_id, book_title, href, chapter_title, snippet, ranges: Vec<RangeView>, score?` | `SearchHitData` |
| `SearchScopeView` | `all_books, book_id?, formats: Vec<String>` | `SearchScopeData` |
| `ExportSummaryView` | `path, note_count, format` | `ExportSummaryData` |

### 桥接函数清单（全部 async）

```rust
pub async fn notes_create(book_id: String, href: String, text: String, progression: f32,
                          kind: String, color: Option<String>, note_text: Option<String>)
    -> Result<AnnotationView, String>;
pub async fn notes_update(note_id: String, patch: NotePatchView) -> Result<(), String>;
pub async fn notes_delete(note_id: String) -> Result<(), String>;
pub async fn notes_delete_many(note_ids: Vec<String>) -> Result<u32, String>;
pub async fn notes_delete_all(book_id: String) -> Result<u32, String>;
pub async fn notes_list(book_id: String) -> Result<Vec<NoteGroupView>, String>;
pub async fn notes_resolve(note_id: String) -> Result<LocatorView, String>;
pub async fn notes_export(book_id: String, fmt: String, out_path: String) -> Result<ExportSummaryView, String>;
pub async fn notes_toggle_bookmark(book_id: String, href: String, progression: f32, snippet: Option<String>)
    -> Result<BookmarkToggleView, String>;
pub async fn search(query: String, scope: SearchScopeView) -> Result<Vec<SearchHitView>, String>;
```

> codegen：`flutter_rust_bridge_codegen generate --rust-input crate::api --rust-root core/ --dart-output app/lib/src/rust/`。生成物（`core/src/frb_generated.rs`、`app/lib/src/rust/**`）**不可手改**；Dart 侧只在 `services/rust_notes_backend.dart` / `services/rust_search_backend.dart` 引用并转 DTO。

### 降级线（授权）
若 FRB 对 `Option<u32>`/嵌套 `Vec<RangeView>` 生成异常：**降级为扁平 DTO**（`AnnotationView` 的 start/end 用 `i64` 且 -1 表示缺失；`SearchHitView` 的 ranges 拍平为 `range_starts: Vec<u32>`/`range_ends: Vec<u32>`），字段语义与 Dart 映射不变，由 developer 在 T-011 记录 diff。

---

## 决策点 D11：真实集成测试架构

**现状（已核实）**：真实集成范式见 `app/integration_test/reader_interaction_test.dart`；静态守卫 `no_synthetic_chrome_test.dart` 扫描 `integration_test/*.dart`；`ReaderPage` 已支持注入 `backend`/`translateBackend`/`ttsBackend`/`chapterProvider`。

### 备选

- **A（选）：新增 `app/integration_test/notes_search_integration_test.dart`，向真实 `ReaderPage`/`SearchPage` 注入 fake `NotesBackend`/`SearchBackend`（生产为 Rust），全程真实 `longPress`/点击/面板/导航**
  - 覆盖：US-10（选词→高亮→面板→跳回）与 US-22（搜索→结果→定位→跳转临时高亮）。
  - 不构造 `ReaderTopBar(`/`ReaderBottomBar(`（守卫绿）。
  - 优点：证伪「合成页假绿」；Linux xvfb 可跑；与 US-10/22 逐条对应。
- **B：把用例并入既有 `reader_interaction_test.dart`**
  - 缺点：US-10/22 明确要求新增文件；混入会降低可追溯性。**拒绝**。
- **C：直接连真实 Rust 后端跑集成测试**
  - 缺点：需构建 `.so` + 真实语料，CI 慢且脆；US-10/22 明确「注入 fake backend（生产为 Rust）」。**拒绝**（真实 FFI 由 `rust_bridge_test.dart` 类测试覆盖）。

### 选择与理由

选 **A**。fake backend 接口与 `services` 抽象同构，注入点已在 `ReaderPage`/`SearchPage` 构造函数；测试断言落库调用参数与真实 widget 状态。

### fake backend 接口

```dart
// app/test/fake_notes_backend.dart（widget/集成共用）
class FakeNotesBackend implements NotesBackend {
  final List<AnnotationData> store;
  // create/update/delete/deleteMany/deleteAll/list/resolve/toggleBookmark/export 记录调用并维护内存 store
}
// app/test/fake_search_backend.dart
class FakeSearchBackend implements SearchBackend {
  final List<SearchHitData> hits;
  final List<SearchScopeData> queries;
  // search 记录 query/scope，返回 hits
}
```
`ReaderPage` 新增可选 `notesBackend`/`searchBackend`；`SearchPage` 新增 `searchBackend` + `onLocate` 回调（或 `Navigator.pop(SearchHitData)` 返回给 ReaderPage 定位）。

### 降级线（授权）
若 Linux xvfb 下真实 `longPress` 选中不稳定：保留「真实 `longPress` + 真实工具条点击」主干，允许在选中前 `ensureVisible`/`pumpAndSettle` 调整；**「禁止合成页」不降级**，静态守卫必须绿。

---

## 决策点 D12：冲突检查（与既有业务/约定/测试）

> 完整逐条处置见 `02-design.md §7`；此处给出结论与处置。

| # | 冲突面 | 结论 | 处置 |
|---|---|---|---|
| C1 | `reading_progress` 唯一事实源 | **不冲突** | 笔记写入 `annotations`，**不写** `reading_progress`；面板/搜索跳转复用 `_changeChapter`/`_scrollToChapter` + `ProgressSaver.flush`（US-8/19）。 |
| C2 | 听读同进度 | **不冲突** | 不改 `ListenPage`/`tts` 语义；`from_selection` 为新增函数，`tts::*` 签名/语义不变。 |
| C3 | `Locator.progression` 章内 0..1 | **不冲突** | `from_selection` 输出 `progression ∈ [0,1]`；`TextAnchor.start/end` 用 UTF-16 半开区间（与 REQ-005 一致）。 |
| C4 | `TextSelection` 归属（REQ-003 声明归笔记 REQ） | **不冲突** | 本 REQ 首次定义 `TextSelection`（`types.rs:179` TODO）。 |
| C5 | ddd-rules（domain 禁 `crate::store`） | **不冲突** | 契约在 `types.rs`，实现只在 `store/*`；`notes`/`search` 仅依赖 trait；pages 不 import `src/rust/`。 |
| C6 | 既有测试文案断言 | **冲突，已处置** | 工具条改「复制/高亮/划线/批注/翻译/查词」→ 更新 `reader_selection_test.dart:40-44`、`reader_page_test.dart:336-350`（划重点/笔记 → 高亮/划线/批注）。 |
| C7 | golden/截图 | **冲突，已处置** | `ChapterSection` 改 `Text.rich` + 工具条文案变化 → 更新 `screenshot_golden_test.dart`/`screenshots_test.dart` golden 并记录 diff。 |
| C8 | `ChapterData` 无 href（R13） | **冲突，已处置** | 增可选 `href`（默认 `''`），生产由 `ChapterView.href` 填充；既有 fake 不破。 |
| C9 | `ChapterSection` 既有调用 | **冲突，已处置** | 新参数全部**可选**（`annotations=const[]`、`tempHighlight=null`），REQ-008 测试不破。 |
| C10 | 线框 06 无「查词」 | **已裁定** | 保留查词入口（01-req §1.5 明确），共 6 项；线框 4 色点保留为高亮选色。 |
| C11 | 书签并入面板 vs 线框 07 无书签样式 | **已裁定** | 书签行用 🔖 + 时间，无颜色竖条（同屏渲染变体，非布局自创）。 |
| C12 | 多连接 WAL `SQLITE_BUSY` | **冲突，已处置** | Store 主连接补 `busy_timeout=5000`；笔记/搜索第二连接显式 FK ON + busy_timeout。 |

---

## 影响汇总

- **Rust 新增**：`core/src/store/annotations.rs`、`core/src/store/search_index.rs`；`core/src/notes/mod.rs`、`core/src/search/mod.rs`、`core/src/locator/mod.rs` 实现；`api.rs` DTO + 10 个 async 桥接 + NOTES/SEARCH 单例装配；`types.rs` 值对象 + 2 个 trait。
- **Rust 修改**：`store/mod.rs`（v4 迁移、`remove_book` 删 FTS、主连接 busy_timeout）、`library/mod.rs`（`import_file` 后由 api 编排索引；`open_book` 已含 href）。
- **数据模型**：v4 新增 `annotations` + `idx_annot_book` + `fts_books`（新列）；`reading_progress`/`books`/`translation_cache`/`settings` 零变更。
- **Dart 新增**：`services/notes_backend.dart`+`rust_notes_backend.dart`、`services/search_backend.dart`+`rust_search_backend.dart`、`services/export_path_picker.dart`（+ desktop/mobile 实现）、`pages/note_span_policy.dart`、`widgets/notes_panel.dart`、`widgets/note_editor_card.dart`、`pages/search_page.dart` 重写、`test/fake_notes_backend.dart`、`test/fake_search_backend.dart`、`integration_test/notes_search_integration_test.dart`。
- **Dart 修改**：`pages/reader_page.dart`、`pages/notes_page.dart`（面板内容迁入 `widgets/notes_panel.dart` 后保留薄壳/删除）、`pages/continuous_scroll_policy.dart`（`ChapterSection`）、`widgets/selection_toolbar.dart`、`services/library_backend.dart`（`ChapterData.href`）、`services/rust_library_backend.dart`、`test/reader_selection_test.dart`、`test/reader_page_test.dart`、golden/截图。
- **文档同步（developer 落）**：`docs/03 §4`（新增桥接面）、`docs/04 §5`（v4 DDL + `fts_books` 新列）、`docs/04 §3/§7`（`from_selection`/`SearchHit`）。
- **回归面**：`cargo test --release -p reader_core`、`flutter test`、`flutter test integration_test -d linux`、`flutter analyze`（0 issues）、`scripts/ddd-lint`（违规 0）、`bash scripts/ui-screenshots.sh REQ-009`、`bash scripts/build-android-local.sh`、US-24 真机清单。

## 闸门2 自评（ADR 部分）
- [x] **备选 ≥2 且给出理由**：D1 四备选（A/B/C/D）、D2 三备选、D3 三备选、D4 三备选、D5 四备选、D6 三备选、D7 四备选、D8 三备选、D9 三备选、D10 三备选、D11 三备选、D12 冲突表；每点含选择理由、拒绝论证、影响、降级线。
- [x] **D1 本机实测**：SQLite 3.53.2 实测 `unicode61`/`trigram` 对 2 字中文零命中，bigram 方案命中；查询 ≤0.21ms、索引 1000 章 13ms；给出新 DDL 与迁移 v4 完整语句，仍复用 `fts_books`。
- [x] **与既有约定一致**：Locator 章内 progression 不变式（C3）、`reading_progress` 唯一事实源（C1）、听读同进度（C2）、ddd-rules（C5）均不破坏；契约/实现分层与 REQ-003 同构。
- [x] **原型权威**：D7 逐屏映射 06/07/04 + 底栏书签（02-menus:31-32），零顶/底栏布局改版；入口收进既有「更多」。
- [x] **可测性落定**：US-18 的 2 字中文命中、US-21 的 <100ms/特殊字符、US-10/22 的真实集成测试结构均有可断言出口。
- [ ] **待同步项（非本阶段闸门项）**：`docs/03 §4`/`docs/04 §5` 由 developer 在实现阶段落文档（plan T-024）。
