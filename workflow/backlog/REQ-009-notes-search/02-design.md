<!-- wf-meta: req=REQ-009-notes-search | phase=architecture | agent=architect | date=2026-09-09 | gate=passed -->
# REQ-009 · 模块/接口设计

> 配套 `02-adr.md`（D1–D12 决策）。本文件给出模块职责、Rust/Dart 接口签名、数据模型、关键时序、逐屏映射与冲突检查。
> 分层：`interface`（`core/src/api.rs`、`app/lib/{pages,widgets,engines}`）/ `application`（`core/src/library`、`app/lib/services`）/ `domain`（`core/src/{notes,search,locator,types,error}`）/ `infrastructure`（`core/src/store`、`app/lib/src/rust`）。

## 1. 模块与职责变化

| 层 | 模块 | 变化 | 职责 |
|---|---|---|---|
| domain | `core/src/types.rs` | **改** | 新增 `TextSelection`/`NoteKind`/`Annotation`/`NotePatch`/`ExportFormat`/`ExportSummary`/`NoteGroup`/`GroupBy`/`TextRange`/`SearchHit`/`SearchScope`/`IndexedChapter`/`SearchRow` + 契约 `AnnotationRepository`/`SearchIndexRepository` |
| domain | `core/src/locator/mod.rs` | **改** | 实现 `from_selection`/`text_at`（文本锚 + progression 消歧/降级），纯文本入参 |
| domain | `core/src/notes/mod.rs` | **改** | 实现 `AnnotationService`（CRUD/列表分组/导出/书签切换），只依赖 `AnnotationRepository` |
| domain | `core/src/search/mod.rs` | **改** | 实现 `SearchService` + CJK bigram 预处理纯函数（`bigram_index_text`/`build_match_expr`/`extract_snippet`） |
| infrastructure | `core/src/store/mod.rs` | **改** | v4 迁移；`remove_book` 事务内删 `fts_books`；主连接补 `busy_timeout` |
| infrastructure | `core/src/store/annotations.rs` | **新** | `AnnotationRepo` 实现 `AnnotationRepository`（第二连接，FK ON） |
| infrastructure | `core/src/store/search_index.rs` | **新** | `SearchIndexRepo` 实现 `SearchIndexRepository`（第二连接，FK ON） |
| application | `core/src/library/mod.rs` | **微改** | `import_file` 保持解析入库；索引编排在 `api.rs`（interface） |
| interface | `core/src/api.rs` | **改** | 新增 9 个 DTO + 10 个 async 桥接 + NOTES/SEARCH 单例装配 + 索引/回填编排 |
| application | `app/lib/services/notes_backend.dart` / `search_backend.dart` | **新** | 抽象 + DTO |
| application | `app/lib/services/rust_notes_backend.dart` / `rust_search_backend.dart` | **新** | 生成物 → DTO 映射 |
| application | `app/lib/services/export_path_picker.dart` | **新** | 可注入路径选择（桌面/移动实现） |
| application | `app/lib/services/library_backend.dart` | **改** | `ChapterData` 增 `href` |
| interface | `app/lib/pages/note_span_policy.dart` | **新** | `composeSpans` 纯函数 + `NoteSpanData`/`TempHighlightData` |
| interface | `app/lib/widgets/notes_panel.dart` | **新** | 线框 07 面板（章节分组/搜索/编辑卡片/底部操作） |
| interface | `app/lib/widgets/note_editor_card.dart` | **新** | 编辑批注卡片（保存/删除） |
| interface | `app/lib/pages/reader_page.dart` | **改** | 选区动作接线、面板入口、书签持久化、临时高亮/跳转、注入 notes/search backend |
| interface | `app/lib/pages/continuous_scroll_policy.dart` | **改** | `ChapterSection` 支持 `Text.rich` 分段 |
| interface | `app/lib/widgets/selection_toolbar.dart` | **改** | 复制/高亮(4 色)/划线/批注/翻译/查词 |
| interface | `app/lib/pages/notes_page.dart` | **改** | 薄壳转 `NotesPanel`（或删除，由 developer 定，保持可达） |
| interface | `app/lib/pages/search_page.dart` | **改** | 线框 04 搜索页 |
| infrastructure | `app/lib/src/rust/**`、`core/src/frb_generated.rs` | **生成** | FRB codegen，禁止手改 |

## 2. 接口签名

### 2.1 Rust domain（`core/src/{types,locator,notes,search}.rs`）

```rust
// ---------- types.rs：值对象 ----------
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum NoteKind { Highlight, Underline, Note, Bookmark }
impl NoteKind {
    pub fn as_str(&self) -> &'static str;          // "highlight"|"underline"|"note"|"bookmark"
    pub fn parse(s: &str) -> Option<NoteKind>;
}

#[derive(Debug, Clone, PartialEq)]
pub struct TextSelection { pub snippet: String, pub progression: f32 }

#[derive(Debug, Clone, PartialEq)]
pub struct Annotation {
    pub id: String,
    pub book_id: BookId,
    pub kind: NoteKind,
    pub color: Option<String>,      // "#RRGGBB"
    pub locator: Locator,
    pub snippet: Option<String>,
    pub note_text: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
    pub sync_status: String,        // "local"
}

#[derive(Debug, Clone, Default)]
pub struct NotePatch { pub note_text: Option<String>, pub color: Option<String>, pub kind: Option<NoteKind> }

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExportFormat { Markdown, Json }
impl ExportFormat { pub fn parse(s: &str) -> Option<Self>; pub fn ext(&self) -> &'static str; }

pub struct ExportSummary { pub path: String, pub note_count: u32, pub format: ExportFormat }
pub struct NoteGroup { pub chapter_title: String, pub href: String, pub notes: Vec<Annotation> }
pub enum GroupBy { Chapter, None }

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct TextRange { pub start: u32, pub end: u32 }   // UTF-16 半开区间

#[derive(Debug, Clone)]
pub struct SearchHit {
    pub book_id: BookId,
    pub book_title: String,
    pub href: String,
    pub chapter_title: String,
    pub chapter_index: u32,   // rework-B D1：该书章节顺序 0 基序号，由 api 层回填
    pub snippet: String,
    pub ranges: Vec<TextRange>,
    pub score: Option<f64>,
}
#[derive(Debug, Clone, Default)]
pub struct SearchScope { pub book_id: Option<BookId>, pub formats: Vec<String> } // formats 空 = 全部

#[derive(Debug, Clone)]
pub struct IndexedChapter { pub href: String, pub chapter_title: String, pub text: String, pub text_bi: String }
#[derive(Debug, Clone)]
pub struct SearchRow { pub book_id: BookId, pub book_title: String, pub href: String,
                       pub chapter_title: String, pub text: String, pub score: Option<f64> }

// ---------- types.rs：契约 ----------
pub trait AnnotationRepository {
    fn insert(&mut self, a: &Annotation) -> Result<()>;
    fn update(&mut self, id: &str, patch: &NotePatch, now: i64) -> Result<()>;
    fn delete(&mut self, id: &str) -> Result<()>;
    fn delete_many(&mut self, ids: &[String]) -> Result<usize>;
    fn delete_all(&mut self, book_id: &str, kinds: Option<&[NoteKind]>) -> Result<usize>;
    fn list(&self, book_id: &str) -> Result<Vec<Annotation>>;        // 含全部 kind
    fn get(&self, id: &str) -> Result<Option<Annotation>>;
    fn find_bookmark(&self, book_id: &str, href: &str, progression: f32) -> Result<Option<Annotation>>;
}

pub trait SearchIndexRepository {
    fn replace_book(&mut self, book_id: &str, chapters: &[IndexedChapter]) -> Result<()>; // 事务：先删后插
    fn is_indexed(&self, book_id: &str) -> Result<bool>;
    fn remove_book(&mut self, book_id: &str) -> Result<()>;
    /// FTS5 短语查询（≥2 字 CJK / ASCII 词走此路）。
    fn query_fts(&self, match_expr: &str, scope: &SearchScope, limit: usize) -> Result<Vec<SearchRow>>;
    /// 子串回退（单字 CJK，FTS bigram 不覆盖）：`text LIKE '%needle%'`。
    fn query_substring(&self, needle: &str, scope: &SearchScope, limit: usize) -> Result<Vec<SearchRow>>;
}
```

```rust
// ---------- locator/mod.rs ----------
pub struct LocatorResolver;
impl LocatorResolver {
    pub fn from_selection(text: &str, book_id: &BookId, href: &str, sel: &TextSelection) -> Result<Locator>;
    pub fn text_at(text: &str, loc: &Locator) -> Result<String>;
}
```

```rust
// ---------- notes/mod.rs ----------
pub struct AnnotationService { repo: Box<dyn AnnotationRepository + Send> }
impl AnnotationService {
    pub fn new(repo: Box<dyn AnnotationRepository + Send>) -> Self;
    pub fn create(&mut self, book_id: &str, locator: Locator, kind: NoteKind,
                  color: Option<String>, note_text: Option<String>) -> Result<Annotation>;
    pub fn update(&mut self, id: &str, patch: &NotePatch) -> Result<()>;
    pub fn delete(&mut self, id: &str) -> Result<()>;
    pub fn delete_many(&mut self, ids: &[String]) -> Result<usize>;
    pub fn delete_all(&mut self, book_id: &str) -> Result<usize>;    // 全部 kind（含书签）
    pub fn list(&self, book_id: &str, chapter_titles: &std::collections::HashMap<String, String>) -> Result<Vec<NoteGroup>>;
    pub fn resolve(&self, id: &str) -> Result<Locator>;
    pub fn export(&self, book_title: &str, groups: &[NoteGroup], fmt: ExportFormat, out: &Path) -> Result<ExportSummary>;
    pub fn toggle_bookmark(&mut self, book_id: &str, locator: Locator, snippet: Option<String>) -> Result<(bool, Option<String>)>;
}
```

```rust
// ---------- search/mod.rs（domain；纯函数 + 服务） ----------
/// CJK 连续段 → 重叠 bigram；ASCII 字母数字 → 整词小写；标点/空白为边界。
pub fn bigram_index_text(text: &str) -> String;
/// 查询 → FTS5 安全短语表达式；全空 → None（api 层短路）。
pub fn build_match_expr(query: &str) -> Option<String>;
/// 在原文中抽上下文片段并给出关键词 UTF-16 区间。
pub fn extract_snippet(text: &str, query: &str, window: usize) -> (String, Vec<TextRange>);

pub struct SearchService { repo: Box<dyn SearchIndexRepository + Send> }
impl SearchService {
    pub fn new(repo: Box<dyn SearchIndexRepository + Send>) -> Self;
    pub fn index_book(&mut self, book_id: &str, chapters: &[IndexedChapter]) -> Result<()>;
    pub fn is_indexed(&self, book_id: &str) -> Result<bool>;
    pub fn query(&self, q: &str, scope: &SearchScope) -> Result<Vec<SearchHit>>;
}
```

### 2.2 Rust interface（`core/src/api.rs`）

```rust
// ---------- DTO（FRB 生成面；字段与 Dart DTO 一一对应） ----------
pub struct TextSelectionView { pub book_id: String, pub href: String, pub text: String, pub progression: f32 }
pub struct AnnotationView {
    pub id: String, pub book_id: String, pub kind: String, pub color: Option<String>,
    pub href: String, pub progression: f32, pub snippet: Option<String>, pub note_text: Option<String>,
    pub start: Option<u32>, pub end: Option<u32>, pub created_at: i64, pub updated_at: i64, pub sync_status: String,
}
pub struct NoteGroupView { pub chapter_title: String, pub href: String, pub notes: Vec<AnnotationView> }
pub struct NotePatchView { pub note_text: Option<String>, pub color: Option<String>, pub kind: Option<String> }
pub struct BookmarkToggleView { pub bookmarked: bool, pub note_id: Option<String> }
pub struct RangeView { pub start: u32, pub end: u32 }
pub struct SearchHitView {
    pub book_id: String, pub book_title: String, pub href: String, pub chapter_title: String,
    pub chapter_index: u32,   // rework-B D1：真实章节序号（0 基）
    pub snippet: String, pub ranges: Vec<RangeView>, pub score: Option<f64>,
}
pub struct SearchScopeView { pub all_books: bool, pub book_id: Option<String>, pub formats: Vec<String> }
pub struct ExportSummaryView { pub path: String, pub note_count: u32, pub format: String }

// ---------- 桥接函数（全部 async，FRB 池线程执行） ----------
pub async fn notes_create(book_id: String, href: String, text: String, progression: f32,
                          kind: String, color: Option<String>, note_text: Option<String>)
    -> std::result::Result<AnnotationView, String>;
pub async fn notes_update(note_id: String, patch: NotePatchView) -> std::result::Result<(), String>;
pub async fn notes_delete(note_id: String) -> std::result::Result<(), String>;
pub async fn notes_delete_many(note_ids: Vec<String>) -> std::result::Result<u32, String>;
pub async fn notes_delete_all(book_id: String) -> std::result::Result<u32, String>;
pub async fn notes_list(book_id: String) -> std::result::Result<Vec<NoteGroupView>, String>;
pub async fn notes_resolve(note_id: String) -> std::result::Result<LocatorView, String>;
pub async fn notes_export(book_id: String, fmt: String, out_path: String)
    -> std::result::Result<ExportSummaryView, String>;
pub async fn notes_toggle_bookmark(book_id: String, href: String, progression: f32, snippet: Option<String>)
    -> std::result::Result<BookmarkToggleView, String>;
pub async fn search(query: String, scope: SearchScopeView)
    -> std::result::Result<Vec<SearchHitView>, String>;
```

装配（`library_open` 增）：
```rust
static NOTES: OnceLock<Mutex<AnnotationService>> = OnceLock::new();
static SEARCH: OnceLock<Mutex<SearchService>> = OnceLock::new();
// let ann_repo = Box::new(AnnotationRepo::open(data_dir)?) as Box<dyn AnnotationRepository + Send>;
// let idx_repo = Box::new(SearchIndexRepo::open(data_dir)?) as Box<dyn SearchIndexRepository + Send>;
// NOTES.set(Mutex::new(AnnotationService::new(ann_repo)));
// SEARCH.set(Mutex::new(SearchService::new(idx_repo)));
```
索引编排（`api.rs`）：
```rust
fn chapter_text(book_id: &str, href: &str) -> Result<String, String>;      // 复用既有
fn indexed_chapters(book_id: &str) -> Result<Vec<IndexedChapter>, String>; // open_book + bigram_index_text
fn ensure_indexed(book_id: &str) -> Result<(), String>;                    // is_indexed ? Ok : index_book
// library_import 成功后：ensure_indexed(&rec.id)
// search 开头：按 scope 对未索引书 ensure_indexed（有界：每书一次）
```

### 2.3 Dart application（`app/lib/services/*.dart`）

```dart
// ---------- notes_backend.dart ----------
class AnnotationData {
  const AnnotationData({required this.id, required this.bookId, required this.kind,
    this.color, required this.href, required this.progression, this.snippet, this.noteText,
    this.start, this.end, required this.createdAt, required this.updatedAt, required this.syncStatus});
  final String id, bookId, kind, href, syncStatus;
  final String? color, snippet, noteText;
  final double progression;
  final int? start, end;
  final int createdAt, updatedAt;
}
class NoteGroupData { const NoteGroupData({required this.chapterTitle, required this.href, required this.notes});
  final String chapterTitle, href; final List<AnnotationData> notes; }
class NotePatchData { const NotePatchData({this.noteText, this.color, this.kind});
  final String? noteText, color, kind; }
class BookmarkToggleData { const BookmarkToggleData({required this.bookmarked, this.noteId});
  final bool bookmarked; final String? noteId; }
class ExportSummaryData { const ExportSummaryData({required this.path, required this.noteCount, required this.format});
  final String path, format; final int noteCount; }

abstract class NotesBackend {
  Future<AnnotationData> create({required String bookId, required String href, required String text,
      required double progression, required String kind, String? color, String? noteText});
  Future<void> update(String noteId, NotePatchData patch);
  Future<void> delete(String noteId);
  Future<int> deleteMany(List<String> noteIds);
  Future<int> deleteAll(String bookId);
  Future<List<NoteGroupData>> list(String bookId);
  Future<ProgressData> resolve(String noteId);   // href + progression
  Future<ExportSummaryData> export(String bookId, String fmt, String outPath);
  Future<BookmarkToggleData> toggleBookmark({required String bookId, required String href,
      required double progression, String? snippet});
}
```

```dart
// ---------- search_backend.dart ----------
class TextRangeData { const TextRangeData({required this.start, required this.end}); final int start, end; }
class SearchHitData {
  const SearchHitData({required this.bookId, required this.bookTitle, required this.href,
    required this.chapterTitle, required this.chapterIndex, required this.snippet,
    required this.ranges, this.score});
  final String bookId, bookTitle, href, chapterTitle;
  final int chapterIndex;   // rework-B D1：真实章节序号（0 基，UI 渲染 +1）
  final String snippet;
  final List<TextRangeData> ranges; final double? score;
}
class SearchScopeData { const SearchScopeData({this.allBooks = true, this.bookId, this.formats = const []});
  final bool allBooks; final String? bookId; final List<String> formats; }

abstract class SearchBackend {
  Future<List<SearchHitData>> search(String query, SearchScopeData scope);
}
```

```dart
// ---------- export_path_picker.dart ----------
abstract class ExportPathPicker {
  Future<String?> pick({required String suggestedName, required String extension});
}
class DesktopExportPathPicker implements ExportPathPicker { /* FilePicker.platform.saveFile */ }
class MobileExportPathPicker implements ExportPathPicker { /* path_provider documents/reader_notes */ }
```

### 2.4 Dart interface（pages/widgets）

```dart
// reader_page.dart（新增可选注入，向后兼容）
const ReaderPage({ ..., this.notesBackend, this.searchBackend, this.exportPathPicker });

// search_page.dart（独立路由；返回命中供 ReaderPage 定位）
class SearchPage extends StatefulWidget {
  const SearchPage({ super.key, required this.searchBackend, this.initialBookId, this.initialBookTitle });
}
// 定位：Navigator.pop<SearchHitData>(context, hit) 或 onLocate 回调（由 ReaderPage 处理）

// note_span_policy.dart
class NoteSpanData { const NoteSpanData({required this.start, required this.end, required this.kind, this.color, required this.order}); }
class TempHighlightData { const TempHighlightData({required this.start, required this.end}); }
class NoteSpan { const NoteSpan({required this.start, required this.end, this.style, this.isTemporary = false}); }
List<NoteSpan> composeSpans({ required String text, required List<NoteSpanData> annotations, TempHighlightData? temp });

// continuous_scroll_policy.dart：ChapterSection 新增可选参数
class ChapterSection extends StatelessWidget {
  const ChapterSection({ ..., this.annotations = const [], this.tempHighlight });
}
```

## 3. 数据模型变化

### 3.1 迁移 v4（`store/mod.rs`，与 `02-adr D3` 逐字一致）

```sql
CREATE TABLE IF NOT EXISTS annotations (
  id            TEXT PRIMARY KEY,
  book_id       TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  kind          TEXT NOT NULL,
  color         TEXT,
  locator_json  TEXT NOT NULL,
  snippet       TEXT,
  note_text     TEXT,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  sync_status   TEXT NOT NULL DEFAULT 'local'
);
CREATE INDEX IF NOT EXISTS idx_annot_book ON annotations(book_id, updated_at);
CREATE VIRTUAL TABLE IF NOT EXISTS fts_books USING fts5(
  book_id UNINDEXED, href UNINDEXED, chapter UNINDEXED, text UNINDEXED, text_bi,
  tokenize='unicode61'
);
PRAGMA user_version = 4;
```

### 3.2 列语义与序列化

| 表/列 | 内容 | 说明 |
|---|---|---|
| `annotations.locator_json` | `serde_json::to_string(&Locator)` | 含 `text.start/end`（UTF-16） |
| `annotations.kind` | `highlight/underline/note/bookmark` | `NoteKind::as_str` |
| `annotations.color` | `#RRGGBB` 或 NULL | 书签为 NULL |
| `annotations.snippet` | 选中原文（冗余） | 列表/导出不解析 JSON |
| `fts_books.text_bi` | `bigram_index_text(text)` | **唯一索引列** |
| `fts_books.text` | 章全文 | UNINDEXED，抽 snippet/区间 |
| `fts_books.href` | `Chapter.href` | UNINDEXED，定位用 |

### 3.3 变更点

- `core/src/store/mod.rs`：`migrate_conn` 增 `if version < 4`；`remove_book` 改事务（`DELETE FROM fts_books WHERE book_id=?` + `DELETE FROM books`）；`Store::open` 的 `execute_batch` 增 `PRAGMA busy_timeout=5000;`。
- `core/src/store/annotations.rs`：`AnnotationRepo::open` 设 `PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; PRAGMA foreign_keys=ON;` + `migrate_conn`。
- `core/src/store/search_index.rs`：`SearchIndexRepo::open` 同上。
- `app/lib/services/library_backend.dart`：`ChapterData` 增 `final String href;`（构造默认 `''`）。
- `core/src/api.rs`：`ChapterView` 增 `href: String`；`book_open` 填充；`rust_library_backend.dart` 映射。
- `docs/03 §4`/`docs/04 §5`：由 developer 同步（plan T-024）。

## 4. 关键时序

### 4.1 创建笔记（高亮/划线/批注）

```
用户长按选中 → SelectionArea.onSelectionChanged(plainText)
  → ReaderPage._onSelectedText 记录 _selectedText + 当前 href/progression
  → 点工具条「高亮」→ 选色 → NotesBackend.create(bookId, href, text, progression, "highlight", color, null)
      → api.rs notes_create: chapter_text(book_id, href) → LocatorResolver::from_selection(text, ...)
          → 归一化匹配 + progression 消歧 → Locator{text: Some(TextAnchor), progression}
          （无匹配 → text=None，progression 兜底）
      → AnnotationService.create → AnnotationRepo.insert → annotations 行
      → 返回 AnnotationView
  → ReaderPage setState 重载本书笔记（notes_list）→ ChapterSection 重新分段渲染（composeSpans）
```

### 4.2 渲染持久化高亮 / 临时高亮

```
ReaderPage._load / notes 变更
  → NotesBackend.list(bookId) → List<NoteGroupData>
  → 按 href 归组为 Map<String, List<NoteSpanData>>（start/end 来自 AnnotationData.start/end）
  → _buildChapterItem → ChapterSection(annotations: spans[href], tempHighlight: _temp)
      → composeSpans(text, annotations, temp) 原子分段
      → Text.rich(TextSpan(children: [NoteSpan...]))
临时跳转反馈：
  点击面板条目 / 搜索结果定位 → ReaderPage._jumpTo(href, progression, snippet)
  → _changeChapter(index, progression)（复用既有：flush reading_progress + _scrollToChapter）
  → setState(_temp = TempHighlightData(start, end))（由 notes_resolve/命中区间解析）
  → 渲染 Key('temp-highlight') span；Timer/滚动/点击 → _temp = null
```

### 4.3 跳转（面板条目 / 搜索定位）

```
面板条目 onTap(hit) → Navigator 关闭面板（或保留）→ ReaderPage._jumpTo(hit)
  → idx = _chapterIndexForHref(view, hit.href)
  → _changeChapter(idx, hit.progression)   // 内部：_progressSaver.flush + _scrollToChapter
  → 解析 snippet 在本章的 UTF-16 区间 → 设置临时高亮
  → reading_progress 更新（复用既有路径，听读同进度不变）
搜索跨书：SearchPage 返回 SearchHitData → ReaderPage 若 bookId != 当前 → 由 LibraryPage/路由打开该书并传 initialTarget
```

### 4.4 搜索

```
SearchPage 输入 → 点「全文搜索」
  → SearchBackend.search(query, scope)
      → api.rs search: 空查询短路返回 []
      → 按 scope 取书列表；对 !is_indexed 的书 ensure_indexed（懒回填）
      → SearchService.query:
          空/纯空白 → 返回 []
          单字 CJK（is_single_cjk_char）→ repo.query_substring(query, scope, limit)（LIKE 回退）
          否则 expr = build_match_expr(query)（None → 返回 []）→ repo.query_fts(expr, scope, limit)
              SELECT f.book_id, b.title, f.href, f.chapter, f.text, rank
              FROM fts_books f JOIN books b ON b.id = f.book_id
              WHERE fts_books MATCH ?1 [AND f.book_id=?] [AND b.format IN (...)]
              ORDER BY rank LIMIT ?2
          → extract_snippet(row.text, query, 30) → SearchHit{snippet, ranges}
      → 按命中 book 分组 open_book 枚举章节 → href→真实序号回填 chapter_index（rework-B D1，跨书各自序号）
      → 返回 Vec<SearchHitView>（含耗时由 UI 计时）
  → SearchPage 渲染结果行（书名/章节/上下文关键词高亮/定位）+ 右侧筛选面板
```

### 4.5 导出

```
面板「导出」→ 空笔记? → 提示「暂无笔记」（不弹保存框）
  → ExportPathPicker.pick(suggestedName, ext)
      null（取消）→ 无操作
      path → NotesBackend.export(bookId, fmt, path)
          → api.rs notes_export: groups = service.list(book_id, titles)
              note_count==0 → Err("暂无笔记")
              → AnnotationService.export(book_title, groups, fmt, out)  // Markdown/JSON 转义
          → ExportSummaryView
  → 提示导出路径
```

## 5. 与既有约定的兼容性

- [x] 不破坏 Locator 模型：`Locator` 结构零变更；`from_selection` 只填充既有字段；`progression` 恒 ∈ [0,1]。
- [x] 不跨越限界上下文：契约在共享内核 `types.rs`，实现只在 `store`；`notes`/`search`/`locator` 只依赖 `types`/`error`；`pages` 不 import `src/rust/`。
- [x] 听读同进度不变式保持：`reading_progress` 唯一事实源；笔记不写进度；跳转复用 `_changeChapter` + `ProgressSaver`；`tts::*` 零改动。
- [x] 回归面：`ChapterSection` 新参数可选；`ChapterData.href` 有默认值；既有工具条测试文案按 plan T-024 更新。
- [x] 数据兼容：v4 幂等；旧书懒回填；删书事务内清 FTS + 级联 annotations。

## 6. 逐屏映射原型图（UI 权威）

> 依据 01-req §1.5；实现阶段禁止自由发挥，闸门 3/5a 逐屏核对 deviation=0。

### 6.1 线框 06 · 文本选择与浮动工具条（`docs/wireframes/06-selection-toolbar.svg`）

| 线框元素 | 实现 | 交互/验收 |
|---|---|---|
| 浮动工具条随选区定位、不遮挡正文 | `ReaderPage._toolbarTop`（既有） | 长按/双击选中（`reader_selection_test.dart`）；工具条贴选区上方 |
| 「复制」 | `SelectionAction.copy` → `Clipboard.setData` | US-22 既有 |
| 「高亮」+ 4 色点（黄/蓝/绿/粉） | `SelectionAction.highlight` → 展开 4 色选色（`NoteColors`，复用工具栏既有 4 色 `#FBC02D/#1A73E8/#43A047/#E91E63`） | US-1：选色后落库 `kind=highlight` + 该色 |
| 「划线」 | `SelectionAction.underline`（**新增枚举值**） | US-2：落库 `kind=underline`，渲染 `TextDecoration.underline` |
| 「批注」 | `SelectionAction.note` → `NoteEditorCard` 输入 | US-3：落库 `kind=note` + `note_text`；空输入不落库 |
| 「翻译」 | `SelectionAction.translate`（既有） | REQ-003 回归 |
| （保留）「查词」 | `SelectionAction.lookup`（既有） | REQ-003 回归；线框未画但 01-req §1.5 明确保留 |
| 拖动两端蓝色手柄调整选区 | `SelectionArea` 内建 | 不额外实现 |

> 工具条最终顺序：`复制 / 高亮(4 色) / 划线 / 批注 / 翻译 / 查词`。`reader_selection_test.dart` 与 `reader_page_test.dart` 文案断言同步更新（plan T-024）。

### 6.2 线框 07 · 笔记面板（`docs/wireframes/07-annotation-panel.svg`）

| 线框元素 | 实现 | 交互/验收 |
|---|---|---|
| 右侧 360px 白色面板、左侧竖边框 | `NotesPanel`：`Positioned(right:0, top:0, bottom:0, width: min(360, 屏宽*0.9))` | 覆盖层，不挤压正文 |
| 标题「笔记」+ ✕ | `NotesPanel` 头部 | 点 ✕ 关闭（US-9） |
| 搜索框「搜索笔记」 | `TextField` + `noteFilter` 纯函数 | 输入过滤列表；清空恢复；无匹配空态（US-7） |
| 章节分组（组头「第一章」…） | `ListView` + `NoteGroupData` | 按章节分组（US-6） |
| 色标（左竖条 == `color`） | 每行左侧 4px `Container(color)` | 色值可断言（US-6） |
| 原文片段 | `Text(snippet, maxLines:1, ellipsis)` | 无批注仅片段（US-6） |
| 批注 | `Text(noteText)`（有则显示） | 编辑后更新（US-11） |
| 时间 `01-12` | `Text(MM-dd)` | 格式可断言（US-6） |
| 底部「导出」 | `ElevatedButton` → `ExportPathPicker` 流程 | US-16/17 |
| 底部「全部删除」（红字） | `TextButton` → 二次确认 | 清空该书（US-13） |
| 编辑批注卡片（输入框 + 删除 + 保存） | `NoteEditorCard` 叠加于面板内 | US-11/12 |
| 打开时主体调暗、点外部关闭 | 面板后 `GestureDetector` 半透明黑 + 关闭 | US-9 |
| 多选批量删除 | 长按/复选框进入多选 + 「删除选中」 | US-13；未选禁用 |
| （并入）书签行 | `kind=bookmark`：🔖 + 时间，无颜色竖条 | US-14；点击跳转 |

### 6.3 线框 04 · 全文搜索（`docs/wireframes/04-search.svg`）

| 线框元素 | 实现 | 交互/验收 |
|---|---|---|
| 顶部搜索框 + 放大镜 | `SearchPage` 顶部 `TextField` + 图标 | 输入后点按钮 |
| 「全文搜索」蓝色按钮 | `ElevatedButton` | 触发 `SearchBackend.search` |
| 结果行：书名（粗） | `Text(bookTitle, bold)` | US-18 |
| 「第 N 章 · 章节名」 | `Text('第 ${hit.chapterIndex + 1} 章 · $chapterTitle')`（rework-B D1：`chapterIndex` 为该书真实章节序号 0 基，非结果列表序号） | US-18 |
| 上下文片段（关键词蓝色加粗） | `RichText` 按 `ranges` 分段（`#1A73E8` + bold） | US-18：span 颜色/字重可断言 |
| 「定位」按钮 | `OutlinedButton` → 返回 `SearchHitData` | US-19：跳转 + 关键词临时高亮 |
| 右侧筛选面板「筛选」 | `Container` 固定宽（172） | 线框右侧 |
| 按范围：全部书籍/当前书籍（单选） | `Radio` 两组 | US-20：scope 过滤 |
| 按格式：EPUB/PDF/MOBI（复选） | `Checkbox` 列表 | US-20：格式过滤；会话内保持 |
| 「结果 42 条 · 0.08s」 | 底部统计文案 | US-20：含条数与耗时 |
| 空态 | 「未找到…」 | US-18 无命中 |
| 输入为空/纯空白 | 不发起查询或提示 | US-18 |

### 6.4 阅读器入口（`reader-ui-v2/02-menus.svg:31-32`、`05-reader.svg:15`）

| 线框元素 | 实现 | 约束 |
|---|---|---|
| 底栏 🔖 书签 | `ReaderBottomBar` 既有 `onBookmark` 改为 `notes_toggle_bookmark` + 状态来自 `notes_list` | 零布局改版 |
| 「⋯更多」菜单 | `_openMore` 增「搜索」，现有「笔记/导出」接真实动作 | 不新增顶栏图标 |
| 顶栏 ⌕ 搜索（05-reader.svg） | **不在顶栏新增图标**；入口收进「更多」（01-req §1.5 授权） | 避免 ReaderTopBar 布局/golden 变更 |

## 7. 冲突检查清单（逐条处置）

| # | 冲突 | 严重度 | 处置 | 责任任务 |
|---|---|---|---|---|
| C1 | 笔记误写 `reading_progress` | 高 | 笔记只写 `annotations`；跳转才经 `_changeChapter` 更新进度 | T-006/T-017 |
| C2 | 听读同进度被破坏 | 高 | `tts::*`/`ListenPage` 零改动；`locator` 新增函数不改 tts 语义 | T-005 |
| C3 | `progression` 写成全书比例 | 高 | `from_selection` 恒输出章内 [0,1]；跳转复用 `_scrollToChapter` | T-005/T-018 |
| C4 | domain 依赖 `crate::store` | 高 | 契约在 `types.rs`；`notes`/`search` 只依赖 trait | T-001/T-006/T-007 |
| C5 | pages 直接 import `src/rust/` | 高 | 只经 `services/*_backend.dart`；ddd-lint 校验 | T-012/T-013 |
| C6 | `reader_selection_test.dart` 工具条文案 | 中 | 更新为 复制/高亮/划线/批注/翻译/查词 | T-015/T-024 |
| C7 | `reader_page_test.dart` 划重点/笔记点击 | 中 | 改为高亮/划线/批注流程（注入 fake notes backend） | T-017/T-024 |
| C8 | golden/截图正文结构变化 | 中 | 重跑并更新 `screenshot_golden_test.dart`/`screenshots_test.dart` | T-024 |
| C9 | `ChapterSection` 既有调用 | 中 | 新参数可选默认值 | T-016 |
| C10 | `ChapterData` 新增 href 破坏 fake | 中 | 可选字段默认 `''`；生产填充 | T-014 |
| C11 | `no_synthetic_chrome_test.dart` | 高 | 新集成文件不构造 `ReaderTopBar(`/`ReaderBottomBar(` | T-023 |
| C12 | 多连接 `SQLITE_BUSY` | 中 | 主连接补 busy_timeout；第二连接 FK ON + busy_timeout | T-002 |
| C13 | 删书残留 FTS 行 | 中 | `remove_book` 事务内显式删 `fts_books` | T-002 |
| C14 | 单字 CJK / 空查询 / 特殊字符 | 中 | LIKE 回退 + 短路 + 短语引用 | T-007 |
| C15 | 工具条 4 色与线框色值 | 低 | 复用工具栏既有 4 色（实现 4 色意图），不引入新色板 | T-015 |

## 8. 闸门2 自评（design 部分）
- [x] 模块/职责变化逐层列明；接口签名 Rust trait/函数 + Dart 抽象完整。
- [x] 数据模型：v4 DDL 逐列对齐 `docs/04 §5`；列语义与序列化说明；变更点清单。
- [x] 关键时序：创建笔记/渲染/跳转/搜索/导出五条。
- [x] 逐屏映射：线框 06/07/04 + 入口，逐元素 → 实现 → 验收。
- [x] 冲突检查 15 条，全部含处置与责任任务。
