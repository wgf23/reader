# 03 · 架构设计

> 阅读器设计文档集 · v1.0
> 本文给出系统分层、组件职责、桥接 API、并发模型、关键流程时序、缓存、错误处理、仓库结构与构建发布。

---

## 1. 架构原则

1. **依赖方向单一**：UI → 渲染层 → 核心层 → 存储层，禁止反向依赖。
2. **核心与 UI 解耦**：所有格式/业务逻辑在 Rust 核心，Flutter 只做界面与交互；核心可用任何语言替换而不动 UI。
3. **渲染可替换**：排版引擎封装为接口，当前 WebView 实现，远期可换自研引擎。
4. **离线优先**：核心层无任何网络依赖；在线翻译只是 Provider 之一。
5. **失败不崩溃**：任何输入（含恶意/损坏文件）不得导致进程崩溃，全部走 Result。

---

## 2. 总体架构图

```
┌──────────────────────────────────────────────────────────────────┐
│ UI 层（Flutter，单代码库）                                          │
│   pages: 书架 / 阅读器 / 设置 / 导入 / 搜索                          │
│   widgets: 工具条 / 笔记面板 / 词典卡片 / 翻译卡片 / 进度条            │
│   services(薄): LibrarySvc / ReaderSvc / NoteSvc / TranslateSvc    │
├──────────────────────────────────────────────────────────────────┤
│ 渲染层                                                              │
│   ReflowEngine(接口)                     PdfEngine                  │
│    └ WebViewReflowEngine                  └ PdfiumRenderer          │
│      系统WebView + 分页JS                   页面位图 + 文本层        │
├──────────────────────────────────────────────────────────────────┤
│ 桥接层 flutter_rust_bridge（FFI，见 §4）                             │
├──────────────────────────────────────────────────────────────────┤
│ 核心层（Rust crate: reader_core）                                   │
│   format/  解析器（epub|mobi|azw3|txt|fb2|pdf-meta|cbz）            │
│   convert/ 规范化→规范EPUB + 缓存                                    │
│   locator/ 锚定模型 + 重定位算法                                     │
│   library/ 书库（元数据/书架/文件夹监控）                             │
│   notes/   笔记 + 阅读进度（SQLite）                                  │
│   dict/    StarDict 词库 + 在线Provider接口(翻译)                    │
│   search/  FTS5 全文索引与查询                                        │
│   store/   SQLite 封装（迁移/WAL/事务）                              │
├──────────────────────────────────────────────────────────────────┤
│ 存储层                                                              │
│   library.db(SQLite+WAL)   cache/(规范EPUB|封面|翻译)  fonts/ dicts/ │
└──────────────────────────────────────────────────────────────────┘
```

---

## 3. 分层职责

### 3.1 UI 层（Flutter）

| 页面 | 职责 | 对应线框 |
|---|---|---|
| 书架页 | 封面墙、排序筛选、导入入口、空态引导 | 01 |
| 导入页 | 拖拽/选择、进度列表、失败重试 | 02 |
| 阅读器页 | 顶栏、正文容器（嵌 ReflowEngine/PdfEngine）、底栏进度、翻页手势 | 05 |
| 笔记面板 | 章节分组列表、编辑、导出（侧滑/悬浮窗） | 07 |
| 翻译/词典浮层 | 查词卡片、翻译卡片、生词本 | 08 |
| 设置页 | 外观/翻译与词典/数据/快捷键 | 03 |
| 搜索页 | 搜索框、结果列表、筛选、定位 | 04 |

- 状态管理：Riverpod；阅读器内部用局部状态（翻页/字号），全局设置入 SQLite。
- 与核心的交互全部经 `services` 层（薄封装，转发 FFI 调用），UI 不直接触碰 FFI。

### 3.2 渲染层

- **ReflowEngine（接口）**：
  ```rust
  trait ReflowEngine {
      fn open(&mut self, epub_path: &Path) -> Result<()>;
      fn page_count(&self) -> usize;                 // 当前章页数
      fn goto(&mut self, loc: &Locator) -> Result<()>;
      fn current_locator(&self) -> Locator;
      fn set_style(&mut self, s: &ReaderStyle) -> Result<()>; // 字号/主题/行距
      fn select_text(&self, sel: &TextSelection) -> Result<()>; // 供笔记用
  }
  ```
  当前实现 **WebViewReflowEngine**：加载章节 HTML + 注入分页 JS（CSS columns 列映射）。
- **PdfEngine**：页面位图渲染（LRU 缓存）、文本层选择、outline 目录、缩放/反色。
- 两者之上是统一阅读会话抽象：`Session { current_locator, engine, book_id }`，阅读器页只面向 `Session` 编程 → 未来换引擎不动 UI。

### 3.3 核心层（Rust）

模块划分与职责见模块设计文档 §1–§4；对外 API 见 §4。

### 3.4 存储层

- `library.db`：books / book_files / annotations / reading_progress / translation_cache / vocabulary / settings / fts 表（DDL 见模块设计 §5）。
- 缓存目录 `cache/`：`<sha256>.epub`（规范 EPUB）、`<sha256>.cover.jpg`、翻译缓存入 DB。
- 迁移：`PRAGMA user_version` 版本化迁移脚本，启动时自动执行。

---

## 4. 桥接层 API（flutter_rust_bridge 对外面）

> 约定：`Result<T>` 映射为 FFI 错误对象；大数据（正文/位图）走共享内存/路径传递，避免拷贝；耗时操作全部 async（Rust 侧线程池）。

**library**
```rust
fn library_import_files(paths: Vec<PathBuf>) -> Result<ImportJobId>;   // 后台任务
fn library_import_folder(path: PathBuf, watch: bool) -> Result<ImportJobId>;
fn library_list(sort: SortKey, filter: Filter) -> Result<Vec<BookSummary>>;
fn library_get(book_id: BookId) -> Result<BookDetail>;                  // 含元数据/封面路径/进度
fn library_remove(book_id: BookId, keep_notes: bool) -> Result<()>;
fn library_update_meta(book_id: BookId, meta: BookMetaPatch) -> Result<()>;
fn library_import_status(job_id: ImportJobId) -> Stream<ImportProgress>;
```

**reading**
```rust
fn session_open(book_id: BookId) -> Result<SessionHandle>;
fn session_goto(session: SessionHandle, loc: &Locator) -> Result<()>;
fn session_locator(session: SessionHandle) -> Result<Locator>;
fn session_next_page / prev_page / set_style / toc(session) -> Result<...>;
fn session_close(session: SessionHandle) -> Result<()>;
fn progress_save(book_id: BookId, loc: &Locator) -> Result<()>;        // 防抖调用
```

**notes**
```rust
fn notes_create(book_id: BookId, sel: &TextSelection, kind: NoteKind, color: Option<Color>, text: Option<String>) -> Result<NoteId>;
fn notes_update(note_id: NoteId, patch: NotePatch) -> Result<()>;       // 文本/颜色/kind
fn notes_delete(note_id: NoteId) -> Result<()>;
fn notes_list(book_id: BookId, group_by: GroupBy) -> Result<Vec<NoteGroup>>;
fn notes_resolve(note_id: NoteId) -> Result<Locator>;                   // 锚→位置
fn notes_export(book_id: BookId, fmt: ExportFormat, out: PathBuf) -> Result<ExportSummary>;
```

**dict / translate**
```rust
fn dict_install(path: PathBuf) -> Result<()>;
fn dict_list() -> Result<Vec<DictInfo>>;
fn dict_lookup(word: &str, dict_id: Option<DictId>) -> Result<Option<DictEntry>>;
fn translate(text: &str, from: Lang, to: Lang) -> Result<Translation>;  // 命中缓存直返
fn vocabulary_add(word: &str, entry: &DictEntry) -> Result<()>;
fn vocabulary_list() -> Result<Vec<VocabItem>>;
```

**search**
```rust
fn search(query: &str, scope: SearchScope) -> Result<Vec<SearchHit>>;
```

**settings**
```rust
fn settings_get() -> Result<Settings>;
fn settings_set(patch: SettingsPatch) -> Result<()>;
```

**dict / translate（REQ-003 已实现，async 桥接）**
```rust
async fn dict_install(path: String) -> Result<()>;              // 安装 StarDict 词库（.ifo/.idx/.dict(.dz)）
async fn dict_remove(name: String) -> Result<()>;
async fn dict_list() -> Result<Vec<DictInfo>>;
async fn dict_lookup(word: String) -> Result<Option<DictEntry>>; // 离线查词，多词库首命中
async fn translate(text: String, from: Lang, to: Lang) -> Result<Translation>; // 缓存优先；失败带原文
async fn translate_cache_clear() -> Result<()>;                 // 隐私：清空翻译缓存
async fn translate_set_config(cfg: ProviderConfig) -> Result<()>; // Provider key/开关
```
- 分层：契约类型与 `TranslationCacheRepository` trait 在 `core/src/types.rs`（共享内核）；`store/translation.rs` 实现；装配在 `api.rs` 的 `library_open`（双单例注入）；dict/translation 属 domain 层，不直接依赖 store（经 trait），满足 ddd-rules。
- 异步方案（ADR）：core 内同步（ureq HTTP、rustls），async 由 flutter_rust_bridge 桥接层承载，core 不引入 tokio。

---

## 5. 线程与并发模型

- **UI 线程**（Flutter main isolate）：只做绘制与手势；不执行任何解析/IO。
- **Rust 工作线程池**（tokio 或 rayon + std threads）：解析、转换、导入、搜索、PDF 渲染。
- **WebView 进程**：渲染/JS 独立于 UI 线程（系统管理），分页脚本轻量。
- **异步任务队列**（核心内）：导入任务可取消、可查询进度；转换任务按优先级（打开书 > 导入）；同一本书的转换互斥（锁 + 缓存）。
- **写放大控制**：笔记写入防抖批量落库（WAL + 短事务）；进度保存节流（300ms 防抖 + 退出时强制刷）。

---

## 6. 关键流程时序

### 6.1 打开书籍（首次，需转换）

```
书架页 ──session_open──▶ 核心: 查书库记录
                          ├─ 已有规范EPUB缓存? ──是──▶ 直接进入渲染
                          └─ 否: 提交转换任务(线程池)
                               ├─ format解析(mobi/azw3...) → convert → 缓存写盘
                               └─ 完成后回调
核心 ──返回SessionHandle + 封面/元数据──▶ UI
UI: 创建 ReflowEngine(WebView) ──加载规范EPUB──▶ 分页JS计算──▶ 恢复进度(goto)
```

### 6.2 创建笔记（高亮 + 批注）

```
用户在WebView选中文本 → JS回调选中范围
  → UI 组装 TextSelection(文本片段+字符偏移)
  → notes_create(核心) → LocatorResolver 生成锚(Locator: 片段+progression+CFI)
  → SQLite 写入 annotations → 返回 NoteId
  → UI 在选中处绘制高亮(同步 WebView 内 overlay)
```

### 6.3 翻译请求

```
选中文本 → translate(text, from, to)
  → 核心: 查 translation_cache(原文+语言对+provider) ──命中──▶ 直返(0 网络)
  └─未命中: 调 Provider 适配器(DeepL...) → 写缓存 → 返回
  → UI 展示译文卡片(标注"命中缓存"/provider名)
```

### 6.4 导入多文件

```
UI: library_import_files(paths)
核心: 逐个(并行度=CPU核数): 校验→解析→转换→写缓存→入库
  → Stream<ImportProgress> 推送进度 → UI 进度列表(线框02)
失败项: 记录原因(损坏/加密/未知格式) → UI 可重试
```

---

## 7. 缓存策略

| 缓存 | 键 | 失效 |
|---|---|---|
| 规范 EPUB | 源文件内容 SHA-256 | 源文件变更（重新扫描时对比 hash） |
| 封面缩略图 | book_id + 尺寸 | 元数据手动修改时 |
| 翻译结果 | (原文, from, to, provider) | 用户手动清空；DB 容量上限（LRU 裁剪） |
| PDF 页位图 | (book_id, page, zoom) | LRU 内存/磁盘上限 |

---

## 8. 错误处理与降级

- 核心所有函数返回 `Result<T, CoreError>`；`CoreError` 分类：`NotFound / CorruptFile / Encrypted / UnsupportedFormat / Io / Internal`，每类有用户可读文案（i18n）。
- **降级链**：规范 EPUB 转换失败 → 尝试"原样直读"（MOBI 原始 HTML 直接包装渲染）→ 仍失败给明确错误页。
- **崩溃恢复**：WAL + 原子写；启动时检测上次非正常退出，清残留锁并校验 DB 完整性（`PRAGMA integrity_check`）。
- **日志**：滚动文件日志（debug 级别可开关），导出日志按钮（设置页）。

---

## 9. 配置管理

- 轻量偏好（窗口尺寸、最近目录）→ `shared_preferences`；
- 阅读/翻译/词典等正式设置 → SQLite `settings` 表（便于未来同步与备份）。
- 配置分层：默认值 < 全局设置 < 单书会话覆盖（不持久化）。

---

## 10. 仓库结构

```
reader/
├── app/                    # Flutter 应用（UI + 渲染层 + services）
│   ├── lib/
│   │   ├── pages/ widgets/ services/ engines/ i18n/
│   └── web/                # (可选) Web 壳，仅调试
├── core/                   # Rust crate `reader_core`
│   ├── src/
│   │   ├── format/ convert/ locator/ library/ notes/ dict/ search/ store/
│   ├── tests/              # 黄金样例 + 集成
│   └── fuzz/               # cargo-fuzz 目标
├── bridge/                 # flutter_rust_bridge 生成物
├── assets/                 # 图标/默认字体/内置小词典
├── scripts/                # 打包/发布脚本
└── docs/                   # 本设计文档集
```

---

## 11. 构建与发布

- **CI（GitHub Actions）**：见测试设计 §7；矩阵 = {Windows, macOS, Linux} × {lint, test, bench, build}；移动端阶段加 Android/iOS。
- **打包**：Windows（MSIX + NSIS 便携版）、macOS（dmg + 公证 notarize）、Linux（AppImage + deb）、Android（AAB + 按 ABI 拆分 APK）、iOS（ipa）。
- **版本策略**：语义化版本；DB schema 版本与核心版本解耦（`user_version` 迁移）。
- **更新**：桌面 P2 做自动更新（差分包）；移动端走应用商店。

---

## 12. 可扩展性（接口预留汇总）

| 扩展点 | 现状 | 未来 |
|---|---|---|
| ReflowEngine | WebView 实现 | 自研轻量排版引擎 |
| TranslationProvider | DeepL/Google/有道/OpenAI 适配器 | 更多厂商、本地大模型翻译 |
| AnnotationRepository/ProgressRepository | SQLite 实现 | WebDAV/自建后端同步 |
| Canonicalizer | 现有 5 格式 | DJVU、漫画增强 |
| 朗读 | — | 基于 Locator 的 TTS 模块 |

---

## 13. 听书（TTS）模块设计

> 定位：**听书会话（ListenSession）= 阅读会话 + 音频播放**。不新增独立领域，复用 `Locator` 与 `reading_progress`（docs/04 §9）。

### 13.1 组件归属

| 层 | 新增组件 | 职责 |
|---|---|---|
| UI | 听书控制条 / 迷你播放条 / 听书设置 / 跟读高亮 | 交互与展示（线框 09/10） |
| 渲染层 | `TtsEngine`（接口）+ 三实现（系统/Piper/在线）+ `AudioPlayer`（just_audio）+ `AudioServiceHandler`（audio_service） | 合成编排与播放 |
| 核心层 | `tts/` 模块 | 句切分 + 句↔Locator 映射 + 音色/语速参数 |
| 存储 | 复用 `reading_progress` + `settings` 表 | 听读同一进度 |

### 13.2 TtsEngine 接口（Flutter 侧）

```dart
abstract class TtsEngine {
  Future<void> configure({required String voiceId, required double speed});
  Future<void> speak(SentenceChunk chunk);   // 播一句，完成回调
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Stream<TtsEvent> get events;               // 句完成 / 失败 / 中断
}
```

### 13.3 桥接 API 增补（Rust 侧，对齐 docs/04 §9）

```rust
fn tts_segment(book_id: BookId, href: &str) -> Result<Vec<SentenceChunk>>;
fn tts_locator_for_sentence(book_id: BookId, href: &str, idx: usize) -> Result<Locator>;
fn tts_sentence_index_at(book_id: BookId, href: &str, loc: &Locator) -> Result<usize>;
```

### 13.4 听书启动时序

```
阅读页点"听书"
  → 取当前 Locator
  → core: tts_segment(当前章) + tts_sentence_index_at(定位当前句 idx)
  → TtsEngine.configure(音色, 语速) → speak(句[i])（同时预取句[i+1]）
  → 句完成事件：更新 reading_progress(句[i] 的 Locator) + 跟读高亮推进到句[i+1]
  → 章末：加载下一章 → tts_segment → 连播（目录顺序）
  → 暂停 / 定时到 / 音频中断：ListenSession 状态机（docs/04 §9）
  → 切到其他页面：收听会话不中断，UI 收起为迷你播放条
```

### 13.5 后台播放

- `audio_service` 统一入口；桌面注册媒体会话（Windows SMTC / macOS MPRemoteCommandCenter），媒体键（播放/暂停/下一首）与任务栏媒体控件可用；
- 移动端（P2）：Android 前台服务 + 通知栏控制；iOS 后台音频会话 + 锁屏控制；音频焦点丢失（来电等）→ 暂停并在恢复时按策略续播。

### 13.6 可扩展性表更新

| 扩展点 | 现状 | 未来 |
|---|---|---|
| TtsEngine 实现 | 系统 TTS（P1） | Piper 本地神经音色、在线 AI 音色（火山/Azure）、声音克隆（P2 评估，挂在 VoiceProvider 之上） |
