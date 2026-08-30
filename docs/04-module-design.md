# 04 · 模块设计（领域设计）

> 阅读器设计文档集 · v1.0
> 本文给出限界上下文、领域模型、Locator 锚定模型、SQLite 数据模型（DDL）、核心模块接口、用例时序、状态机与领域规则。

---

## 1. 限界上下文划分

```
┌─────────────────────────────────────────────────────────┐
│                    阅读器 (Reader)                         │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐ │
│  │ 书库 Library│ │ 阅读 Reading│ │ 笔记 Notes │ │翻译 Translation│ │
│  └───────────┘ └───────────┘ └───────────┘ └───────────┘ │
│  ┌───────────┐   ┌───────────────────────────────┐      │
│  │ 设置 Settings│   │ 支撑：格式解析 / 规范化 / 锚定 / 存储 │      │
│  └───────────┘   └───────────────────────────────┘      │
└─────────────────────────────────────────────────────────┘
```

**上下文映射规则**：
- 书库持有书籍与导入；阅读只消费"可读会话"（不直接碰文件）；笔记依赖**定位器（Locator）**而非具体格式；翻译独立成上下文，与笔记通过"生词本"弱关联。
- 共享内核（Shared Kernel）：`BookId`、`Locator`、`BookMeta` 为跨上下文共享值对象，定义在一处（`core::types`），禁止各上下文自造。

---

## 2. 领域模型

### 2.1 实体与值对象总览

| 名称 | 类型 | 所属上下文 | 职责 |
|---|---|---|---|
| `Book` | 聚合根 | Library | 一本书的身份与元数据；持有封面、文件、进度 |
| `BookFile` | 实体 | Library | 源文件与规范 EPUB 缓存文件的物理信息 |
| `BookMeta` | 值对象 | 共享 | title/authors/language/cover/toc/spine 等（不可变） |
| `ReadingProgress` | 实体 | Reading | 最近阅读位置（Locator）+ 时间 |
| `Annotation` | 聚合根 | Notes | 一条笔记：高亮/划线/批注/书签 + 锚点 + 内容 |
| `Locator` | 值对象 | 共享 | 统一位置锚定（见 §3） |
| `TextSelection` | 值对象 | Notes | 用户选中的文本范围（章 + 片段 + 偏移） |
| `DictEntry` | 值对象 | Translation | 词条：音标/词性/释义/例句 |
| `Translation` | 值对象 | Translation | 译文 + provider + 语言对 |
| `VocabItem` | 实体 | Translation | 生词本条目 |
| `DictInfo` | 值对象 | Translation | 已安装词库信息 |
| `Settings` | 实体 | Settings | 全局配置聚合 |

### 2.2 聚合与不变式

- **Book 聚合**：`Book + BookFile + BookMeta + ReadingProgress`。不变式：一本书至多一条"当前进度"；删除书必须先删除其笔记（或显式选择保留）。
- **Annotation 聚合**：`Annotation + Locator`。不变式：锚点非空且可解析；笔记的 `snippet` 是创建时文本的冗余快照（列表展示/导出用），定位失效时仍可展示。
- **领域服务**（无状态、编排聚合）：
  - `BookCanonicalizer`（format→规范 EPUB，§2.3）
  - `LocatorResolver`（TextSelection/Locator ↔ 渲染位置互转，§3）
  - `AnnotationService`（笔记 CRUD + 导出编排）
  - `TranslationService`（缓存 + Provider 路由）
  - `LibraryService`（导入/书架/监控编排）

### 2.3 领域模型关系图

```
Book 1 ──< BookFile 1..*（源文件 / 规范EPUB缓存）
Book 1 ── 1 ReadingProgress ──> Locator
Book 1 ──< Annotation 0..* ────> Locator
Book 1 ──< VocabItem 0..*（记录来源书，弱引用）
TranslationCache（DB 表，键=原文+语言对+provider）
```

---

## 3. Locator 锚定模型（跨上下文基石）

```rust
pub struct Locator {
    pub book_id: BookId,
    pub href: String,            // 章/资源路径（规范EPUB内相对路径）
    pub progression: f32,        // 章内进度 0.0..=1.0（页/列粒度）
    pub total_progression: f32,  // 全书进度 0.0..=1.0（跨设备用）
    pub text: Option<TextAnchor>,// 文本片段锚（最稳）
    pub cfi: Option<String>,     // EPUB CFI（冗余精确锚，reflow 专用）
    // PDF 变体：
    pub page: Option<u32>,       // PDF: 页码
    pub rect: Option<Rect>,      // PDF: 页面矩形（锚定高亮）
}

pub struct TextAnchor {
    pub snippet: String,   // 创建时的原文片段（8–40 字符）
    pub start: u32,        // snippet 在章文本中的起始偏移
    pub end: u32,          // snippet 在章文本中的结束偏移
}
```

**定位算法（LocatorResolver）**：
1. `href` 命中 → 加载该章文本；
2. 优先用 `text.snippet` 在章文本内**模糊匹配**（规范化空白/标点后精确匹配，失败则允许 1–2 字符容错）→ 得字符偏移；
3. 匹配失败降级：用 `progression`（章内列/页比例）近似定位；
4. 再降级：`cfi`（EPUB 专用）；
5. 全部失败：章首 + 标记"位置可能不精确"。

**为什么 snippet 最稳**：换字号/换主题/换设备重排，页号与 CFI 都失效，但原文文本不变 → 重排后重新解析即恢复。代价是原文变动时模糊匹配，领域规则接受这一近似。

---

## 4. 用例 → 模块接口映射

| 用例（用户故事） | 主模块 | 关键调用 |
|---|---|---|
| LIB-01 导入 | Library + BookCanonicalizer | `library_import_files → canonicalize → store` |
| LIB-02 书架 | Library | `library_list / library_get` |
| READ-01 打开恢复 | Reading + LocatorResolver | `session_open → progress_save/goto` |
| READ-06 搜索 | Search + store | `search(query)` |
| NOTE-01..05 笔记 | Notes + LocatorResolver | `notes_create/update/delete/list/resolve` |
| NOTE-07 导出 | Notes | `notes_export` |
| TRANS-01 查词 | Translation(dict) | `dict_lookup` |
| TRANS-02 翻译 | Translation | `translate` |
| TRANS-04 生词本 | Translation | `vocabulary_add/list` |

---

## 5. 数据模型（SQLite DDL）

> 单库 `library.db`，WAL 模式，`PRAGMA user_version` 迁移。

```sql
-- 书籍
CREATE TABLE books (
  id            TEXT PRIMARY KEY,          -- uuid
  title         TEXT NOT NULL,
  authors       TEXT NOT NULL DEFAULT '[]',-- JSON 数组
  language      TEXT,
  cover_path    TEXT,                      -- 缓存缩略图相对路径
  source_hash   TEXT NOT NULL,             -- 源文件内容 SHA-256（去重）
  source_path   TEXT NOT NULL,             -- 原文件绝对路径
  format        TEXT NOT NULL,             -- epub|pdf|mobi|azw3|txt|fb2|cbz
  toc_json      TEXT,                      -- 目录树缓存
  added_at      INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);
CREATE UNIQUE INDEX idx_books_hash ON books(source_hash);

-- 规范 EPUB 缓存
CREATE TABLE book_files (
  book_id       TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
  canonical_path TEXT,                     -- cache/<hash>.epub（reflow 类）
  pages_hint    INTEGER                    -- 可选：预计算页数
);

-- 阅读进度（每书一条）
CREATE TABLE reading_progress (
  book_id       TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
  locator_json  TEXT NOT NULL,             -- Locator 序列化
  updated_at    INTEGER NOT NULL
);

-- 笔记
CREATE TABLE annotations (
  id            TEXT PRIMARY KEY,          -- uuid
  book_id       TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  kind          TEXT NOT NULL,             -- highlight|underline|note|bookmark
  color         TEXT,                      -- 高亮/划线颜色
  locator_json  TEXT NOT NULL,             -- Locator
  snippet       TEXT,                      -- 原文快照（冗余，列表/导出用）
  note_text     TEXT,                      -- 批注内容（note 类必填）
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  sync_status   TEXT NOT NULL DEFAULT 'local'  -- local|dirty|synced（同步预留）
);
CREATE INDEX idx_annot_book ON annotations(book_id, updated_at);

-- 翻译缓存
CREATE TABLE translation_cache (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  source_text   TEXT NOT NULL,
  from_lang     TEXT NOT NULL,
  to_lang       TEXT NOT NULL,
  provider      TEXT NOT NULL,
  result        TEXT NOT NULL,             -- JSON Translation
  created_at    INTEGER NOT NULL,
  hit_count     INTEGER NOT NULL DEFAULT 1
);
CREATE UNIQUE INDEX idx_tcache ON translation_cache(source_text, from_lang, to_lang, provider);

-- 生词本
CREATE TABLE vocabulary (
  id            TEXT PRIMARY KEY,
  word          TEXT NOT NULL,
  entry_json    TEXT NOT NULL,             -- DictEntry
  source_book   TEXT,                      -- 来源书（可空）
  added_at      INTEGER NOT NULL
);
CREATE INDEX idx_vocab_word ON vocabulary(word);

-- 设置
CREATE TABLE settings (
  key           TEXT PRIMARY KEY,
  value         TEXT NOT NULL
);

-- 全文搜索（FTS5，入库时构建）
CREATE VIRTUAL TABLE fts_books USING fts5(
  book_id UNINDEXED, chapter, text,
  tokenize='unicode61'
);
```

**说明**：
- 笔记锚定用 `locator_json`（灵活性），列表/导出用 `snippet` 冗余列（不解析 JSON）。
- 删除书默认 `ON DELETE CASCADE` 清笔记；LIB-04 的"保留笔记"选项 = 先导出再删（由 UI 编排）。
- 搜索：`fts_books` 按章插入；搜索时 JOIN books 过滤范围。

---

## 6. 状态机

**导入任务**（每文件）：`Pending → Parsing → Converting → Ready`，任一步失败 → `Failed(reason)`；`Ready`/`Failed` 可 `Retry`（重试从 Parsing 起）。转换幂等：先查缓存（hash），命中直接 `Ready`。

**笔记同步（预留，本期不实现）**：`local → dirty → synced`，冲突 `conflict`（LWW + 人工合并）。

**翻译请求**：`Miss → (Provider成功 → Cached | Provider失败 → Failed(可重试))`，命中缓存直接 `Cached`。

---

## 7. 核心模块接口（Rust 侧摘要）

> 完整签名见架构文档 §4。此处给出模块边界与关键类型。

```rust
// format/ —— 解析器，输出统一中间表示
pub trait FormatParser {
    fn detect(bytes: &[u8]) -> Option<Format>;
    fn parse(path: &Path) -> Result<ParsedBook>;   // ParsedBook: 章节+资源+元数据+目录
}

// convert/ —— 规范化
pub struct BookCanonicalizer;
impl BookCanonicalizer {
    pub fn canonicalize(parsed: &ParsedBook, out_dir: &Path) -> Result<CanonicalEpub>;
}

// locator/
pub struct LocatorResolver;
impl LocatorResolver {
    pub fn from_selection(book: &Book, sel: &TextSelection) -> Result<Locator>;
    pub fn resolve(book: &Book, loc: &Locator) -> Result<ResolvedPosition>; // 供引擎 goto
    pub fn text_at(book: &Book, loc: &Locator) -> Result<String>;           // 供面板/导出
}

// notes/
pub struct AnnotationService;
impl AnnotationService {
    pub fn create(book: &Book, sel: &TextSelection, kind: NoteKind, color: Option<Color>, text: Option<String>) -> Result<Annotation>;
    pub fn update(id: NoteId, patch: NotePatch) -> Result<()>;
    pub fn delete(id: NoteId) -> Result<()>;
    pub fn list(book_id: BookId) -> Result<Vec<Annotation>>;
    pub fn export(book_id: BookId, fmt: ExportFormat, out: &Path) -> Result<ExportSummary>;
}

// dict/ —— 词典 + 翻译
pub trait TranslationProvider {          // 在线 Provider 统一接口
    fn name(&self) -> &str;
    fn translate(&self, text: &str, from: Lang, to: Lang) -> Result<Translation>;
}
pub struct TranslationService;
impl TranslationService {
    pub fn lookup(word: &str) -> Result<Option<DictEntry>>;   // StarDict 本地
    pub fn translate(text: &str, from: Lang, to: Lang) -> Result<Translation>; // 缓存优先
    pub fn install_dict(path: &Path) -> Result<()>;
}

// search/
pub struct SearchService;
impl SearchService {
    pub fn index_book(book: &Book) -> Result<()>;              // 入库时调用
    pub fn query(q: &str, scope: Scope) -> Result<Vec<SearchHit>>;
}
```

---

## 8. 领域规则汇总

1. **去重**：同 `source_hash` 只入库一次；重复导入提示"已在书库"。
2. **锚定近似性**：文本锚允许容错匹配；重定位失败时标记不精确，不静默丢失笔记。
3. **缓存一致性**：规范 EPUB 以源文件 hash 为键；hash 变化即重新转换。
4. **隐私边界**：翻译缓存仅存用户自己选中的文本；设置页可一键清空。
5. **删除级联**：删书默认级联删笔记与进度；"保留笔记"须显式导出。
6. **并发写**：同一笔记的并发更新以 `updated_at` LWW；事务内完成。

---

## 9. 听书（Listening）领域设计

> 参考番茄小说：听读一体。听书不新建领域表，**进度复用 `reading_progress`**，只新增 `tts/` 模块与设置键。

### 9.1 新增类型

```rust
/// 朗读句子块（切句粒度 = 句子）
pub struct SentenceChunk {
    pub text: String,
    pub char_range: (u32, u32),   // 在章文本中的字符区间
    pub locator: Locator,         // 句 ↔ 位置映射（听读进度统一的基石）
}

/// 音色信息
pub struct VoiceInfo {
    pub id: String,
    pub name: String,
    pub kind: VoiceKind,          // System | Local(piper) | Online(ai)
    pub lang: String,
}
pub enum VoiceKind { System, Local, Online }

/// 听书会话（运行态，不入库）
pub struct ListenSession {
    pub book_id: BookId,
    pub chapter_href: String,
    pub sentence_idx: usize,
    pub speed: f32,               // 0.5..=3.0
    pub voice_id: String,
    pub state: ListenState,
    pub timer: Option<TimerSpec>, // 定时关闭
}
pub enum ListenState { Idle, Playing, Paused, Stopped, Interrupted }
```

### 9.2 设置键（入 `settings` 表，JSON 值）

`listen.voice_id`、`listen.speed`、`listen.timer`、`listen.auto_next`（章节连播开关）。

### 9.3 状态机

```
Idle → Playing
Playing ⇄ Paused
Playing →(句完成)→ Playing(idx+1)
Playing →(章末)→ Playing(下一章, idx=0)      // auto_next 开启时
Playing →(定时到 | 用户停止)→ Stopped
Playing →(音频焦点丢失, 移动端 P2)→ Interrupted →(恢复策略)→ Playing | Paused
```

### 9.4 领域规则

1. **听读同一进度**：朗读位置即阅读位置（`reading_progress` 是唯一事实源），进入/退出听书不改变位置；
2. **切句粒度 = 句子**：中文按 `。！？；…` 与段落边界切分，保持引号/书名号完整；
3. **容错**：单句合成失败跳过继续，连续失败 > 5 次停止并提示；
4. **写盘节流**：进度更新与阅读一致（300ms 防抖 + 退出时强刷）；
5. **隐私**：在线音色为显式授权功能，仅发送所选句文本。

### 9.5 核心接口摘要（Rust `tts/` 模块）

```rust
fn segment(book_id: BookId, href: &str) -> Result<Vec<SentenceChunk>>;
fn locator_for_sentence(book_id: BookId, href: &str, idx: usize) -> Result<Locator>;
fn sentence_index_at(book_id: BookId, href: &str, loc: &Locator) -> Result<usize>;
```
