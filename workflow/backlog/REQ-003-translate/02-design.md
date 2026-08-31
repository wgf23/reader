<!-- wf-meta: req=REQ-003 | phase=architecture | agent=architect | date=2025-08-31 | gate=passed -->
# REQ-003 · 模块/接口设计（翻译与词典：TRANS-01 离线查词 + TRANS-02 在线翻译）

## 1. 模块与职责变化

| 模块 | 变化 | 层 | 说明 |
|---|---|---|---|
| `core/src/types.rs` | **新增**（共享内核）：`Lang`/`Translation`/`CacheKey`/`CacheEntry` + 跨层契约 `TranslationCacheRepository`/`ProviderConfig` | domain（共享内核，ddd-rules 的 domain 路径已覆盖 `core/src/types.rs`） | 契约与载荷类型落共享内核的原因（ADR 决策点3）：ddd-lint 对 infrastructure 层禁 `crate::dict`，store 实现契约必须只依赖 `crate::types`；规则表冻结零改动；serde 派生（Translation 需 JSON 落库） |
| `core/src/dict/mod.rs` | 空 stub → 实现：`DictEntry`/`DictInfo` 领域类型 + `TranslationProvider` trait 完整化（同步签名，docs/04 §7）+ 模块装配（stardict/provider/translation 子模块 re-export） | domain | 禁止 `crate::store\|api\|library`（ddd-rules）；只依赖 `crate::error`/`crate::types` 与外部 crate（flate2/ureq/serde_json） |
| `core/src/dict/stardict.rs` | **新增**：StarDict 解析内核（.ifo/.idx/.dict(.dz) + sametypesequence + 内存索引） | domain | 纯解析无网络；坏词库全部结构化 `Err` 不 panic（US-6）；`.dz` 流式解压落盘（ADR 关联裁定5） |
| `core/src/dict/provider.rs` | **新增**：`DeepLProvider`（ureq+rustls）+ `EchoProvider`（mock/演示）+ 测试用 `CountingProvider`/`FailingProvider`（`#[cfg(test)]` 或独立测试模块） | domain | `TranslationProvider` 实现；网络仅封装于 DeepLProvider 内部；隐私：请求只带 text/from/to（US-9/13） |
| `core/src/dict/translation.rs` | **新增**：`TranslationService`（缓存优先编排）+ `DictService`（词库注册/查词） | domain | 只经 `crate::types` 契约访问持久化（trait 注入）；Provider 注册表与默认 Provider 路由 |
| `core/src/store/mod.rs` | **微改**：`migrate()` 提取为 `pub(crate) fn migrate_conn(conn)`（Store::open 与 TranslationRepo::open 共用）；`Store::open` 追加建 `dicts/` 目录（docs/02 §5 目录布局） | infrastructure | v1/v2 迁移路径行为不变；v3 追加 `translation_cache` + `settings` 表 |
| `core/src/store/translation.rs` | **新增**：`TranslationRepo`（第二连接）实现 `TranslationCacheRepository` + `ProviderConfig` | infrastructure | 只依赖 `crate::types`/`crate::error`/rusqlite；WAL + `busy_timeout`；UPSERT 不重置 hit_count |
| `core/src/error.rs` | **新增** `NotConfigured` + `Network{detail, source_text}` 变体 | domain | 对齐 docs/03 §8 错误分类扩展；US-12 错误携带原文 |
| `core/src/api.rs` | **扩展**：新增 7 个 **async** 桥接函数 + 3 个 DTO；`library_open` 装配 DICT/TRANSLATION 两个单例 | interface | 既有同步函数零改动；FRB 2.13 async 支持；错误经 `err_msg(Display)` 映射 |
| `core/src/frb_generated.rs` + `app/lib/src/rust/**` | 再生成（T-006） | interface / infrastructure | 按 bridge/README 现有 codegen 流程 |
| `app/lib/services/translate_backend.dart` | **新增**：`TranslateBackend` 抽象 + DTO（DictEntryData/DictInfoData/TranslationData） | application | 页面禁直接 import 桥接生成物（ddd-rules forbid_imports） |
| `app/lib/services/rust_translate_backend.dart` | **新增**：Rust 后端实现（转发 FFI → DTO） | application | 仿 `rust_library_backend.dart` |
| `app/lib/pages/reader_page.dart` | **修改**：滚动模式 `SelectionArea`；选中工具条（翻译/查词/取消）；译文/词典浮层接入；可选 `translateBackend` 参数 | interface | 既有行为零回归（参数可选，null 隐藏入口） |
| `app/lib/engines/paged_web_view.dart` | **修改**：`paginationJs` 增选区监听；`onSelectedText` 回调 | interface | 最小选区回传（ADR 决策点2）；`onProgress` 等既有行为不动 |
| `app/lib/widgets/translation_popup.dart` | **新增**：译文浮层（loading/错误+重试/结果+provider+缓存标记）与词典卡片（词条/音标/词性/释义/例句） | interface | 可 widget 测试 |
| `app/lib/pages/settings_page.dart` | **修改**：新增"词典与翻译"最小区块（词库导入/列表/移除、Provider key 输入、清空缓存） | interface | TRANS-03 进阶管理 UI 不在本 REQ |
| `core/Cargo.toml` | **修改**：新增 `ureq`（rustls） | — | ADR 决策点4 |
| `docs/03-architecture.md` | **修改**（T-006 同步）：§4 dict/translate 契约（返回类型、`dict_remove`、async 说明） | — | ADR 关联裁定4 |

## 2. 接口签名（Rust 函数级）

### 2.1 `core/src/types.rs` 新增（共享内核 + 跨层契约）
```rust
use serde::{Deserialize, Serialize};

/// 语言（翻译语言对；桥接层用字符串 "en"/"zh"… 经 From/Display 互转）
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Lang { En, Zh, Ja, Ko, Fr, De, Es, Ru, Other(&'static str) }
impl Lang {
    pub fn as_str(&self) -> &str;
    pub fn parse(s: &str) -> Option<Lang>;   // 未知 → None（api 层映射为 Err(Other("不支持的语言代码"))）
}

/// 译文值对象（缓存 result 列的 JSON 载荷）
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Translation {
    pub text: String,
    pub from: Lang,
    pub to: Lang,
    pub provider: String,
}

/// 缓存键：(原文归一化, 语言对, Provider) —— docs/04 §5 唯一索引语义
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CacheKey {
    pub source_text: String,
    pub from_lang: Lang,
    pub to_lang: Lang,
    pub provider: String,
}

/// 缓存行
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheEntry {
    pub key: CacheKey,
    pub result: Translation,
    pub created_at: i64,      // unix 秒
    pub hit_count: u64,
}

/// 翻译缓存仓储契约（domain 契约，store 实现，api 注入）。
/// 落位共享内核的原因见 ADR 决策点3（ddd-lint infrastructure 禁 crate::dict，规则表冻结）。
pub trait TranslationCacheRepository {
    fn cache_get(&self, key: &CacheKey) -> Result<Option<CacheEntry>>;
    fn cache_put(&mut self, entry: &CacheEntry) -> Result<()>;          // UPSERT，不重置 hit_count
    fn cache_incr_hit(&mut self, key: &CacheKey) -> Result<()>;         // 命中 +1
    fn cache_clear(&mut self) -> Result<()>;
    fn cache_count(&self) -> Result<u64>;                               // US-13 行数断言
}

/// Provider 凭据/默认路由契约（settings 表等价通道；docs/04 §5 settings 表）
pub trait ProviderConfig {
    fn default_provider(&self) -> Result<String>;                       // 默认 "deepl"
    fn provider_key(&self, provider: &str) -> Result<Option<String>>;   // None → 未配置
    fn set_provider_key(&mut self, provider: &str, key: &str) -> Result<()>;
    fn set_default_provider(&mut self, provider: &str) -> Result<()>;
}
```

### 2.2 `core/src/dict/mod.rs`（领域类型 + Provider trait）
```rust
/// 词条（docs/04 §2.1：音标/词性/释义/例句；中文词库字段可空，UI 空值不渲染）
#[derive(Debug, Clone, PartialEq)]
pub struct DictEntry {
    pub word: String,
    pub phonetic: Option<String>,
    pub pos: Option<String>,          // 释义首词性标记启发式（"n."/"vt."…），无则 None
    pub definition: String,           // m/g 字段按序拼接（g 为 HTML 原样保留）
    pub example: Option<String>,      // x 字段
}

/// 已安装词库信息（US-7 返回值）
#[derive(Debug, Clone)]
pub struct DictInfo {
    pub id: String,                   // bookname 消毒后作 id（安装幂等键）
    pub name: String,                 // .ifo bookname
    pub word_count: u64,              // .ifo wordcount
    pub path: String,                 // <data_dir>/dicts/<id>/
}

/// 在线 Provider 统一接口（docs/04 §7 同步签名；ADR 决策点1 保持同步）
pub trait TranslationProvider {
    fn name(&self) -> &str;
    fn translate(&self, text: &str, from: Lang, to: Lang) -> Result<Translation>;
    /// 运行时更新凭据（设置页改 key 后无需重建 Provider）；默认 no-op（Echo 忽略）
    fn configure(&mut self, _key: Option<&str>) {}
}
```

### 2.3 `core/src/dict/stardict.rs`（StarDict 解析内核，pub(crate)）
```rust
/// .ifo 元数据（version/bookname/wordcount/idxfilesize/sametypesequence 等；缺失容错，
/// wordcount 缺失 → Err(Corrupt)，US-6）
pub(crate) struct IfoMeta { pub bookname: String, pub wordcount: u64,
    pub idxfilesize: Option<u64>, pub sametypesequence: Option<String> }
pub(crate) fn parse_ifo(path: &Path) -> Result<IfoMeta>;

/// .idx 条目（word + .dict 内偏移/长度）
pub(crate) struct IdxEntry { pub word: String, pub offset: u32, pub size: u32 }

/// 加载 .idx 全量入内存（langdao 级 ~1-2MB；保存 .idx 原序）
pub(crate) fn load_idx(idx_bytes: &[u8]) -> Result<Vec<IdxEntry>>;
/// 查词：二分精确命中；未中则线性扫描做"首字母小写/全小写"归一匹配（US-5；n≤10^5 实测 <1ms）
pub(crate) fn lookup_entry(idx: &[IdxEntry], word: &str) -> Option<&IdxEntry>;

/// 按 sametypesequence 解析 .dict 区段（offset..offset+size）：
/// 类型码 t→phonetic、m→definition(纯文本)、g→definition(HTML)、x→example；
/// 未知类型码读到 \0 跳过（01-req §5 风险2：未知码不崩溃）；区段越界/截断 → Err(Corrupt)
pub(crate) fn parse_entry(seq: &[u8], dict_bytes: &[u8], e: &IdxEntry) -> Result<DictEntry>;

/// .dict.dz（整文件 gzip）流式解压为 .dict 落盘（安装期一次性；flate2 GzDecoder → io::copy）
pub(crate) fn decompress_dz(src: &Path, dst: &Path) -> Result<()>;
```

### 2.4 `core/src/dict/translation.rs`（服务）
```rust
/// 词库注册/查词服务（US-3/5/6/7/8）
pub struct DictService { dicts_dir: PathBuf, registry: Vec<LoadedDict> }
struct LoadedDict { info: DictInfo, ifo: IfoMeta, idx: OnceCell<Vec<IdxEntry>>,
                    dict_file: Option<File>, idx_bytes: Vec<u8> /* 懒加载索引源 */ }
impl DictService {
    pub fn new(data_dir: &Path) -> Result<DictService>;      // 建 <data_dir>/dicts，扫描既有安装
    pub fn install(&mut self, path: &Path) -> Result<DictInfo>;   // 校验→拷贝→.dz 解压→注册（幂等）
    pub fn remove(&mut self, dict_id: &str) -> Result<()>;        // 删目录 + 注销
    pub fn list(&self) -> Result<Vec<DictInfo>>;                  // 安装顺序
    pub fn lookup(&self, word: &str, dict_id: Option<&str>) -> Result<Option<DictEntry>>;
    //   注册表空 → Err(NotFound("未安装词库，请先在设置中导入"))（US-3）
    //   多词库按安装顺序取首个命中（US-5）；dict_id 指定时只查该词库
    //   单词典索引加载失败：跳过该词典继续；全部失败 → Err(Corrupt)
}

/// 翻译服务（缓存优先；US-9~14）
pub struct TranslationService {
    cache: Box<dyn TranslationCacheRepository + Send>,
    config: Box<dyn ProviderConfig + Send>,
    providers: Vec<Box<dyn TranslationProvider>>,
}
impl TranslationService {
    pub fn new(cache: Box<dyn TranslationCacheRepository + Send>,
               config: Box<dyn ProviderConfig + Send>,
               providers: Vec<Box<dyn TranslationProvider>>) -> Self;
    pub fn translate(&mut self, text: &str, from: Lang, to: Lang) -> Result<Translation>;
    //   normalize_text(text)（折叠空白+trim，US-9）→ provider=config.default_provider()
    //   → config.provider_key(provider)?（None → Err(NotConfigured("…未配置 API Key…"))，US-12）
    //   → cache_get((norm,from,to,provider))：命中 → incr_hit + 返回（from_cache 由 api 层标注）
    //   → provider.translate(...)：Err(Network{..}) → 不写缓存直接透出（US-12，携带原文）
    //   → cache_put(hit_count=1) → 返回
    pub fn clear_cache(&mut self) -> Result<()>;
    pub fn set_config(&mut self, provider: &str, key: &str) -> Result<()>;
    //   写 settings（set_provider_key + set_default_provider）并对注册 Provider 调 configure（ADR 关联裁定2）
}
pub fn normalize_text(s: &str) -> String;   // 连续空白折叠为单空格并 trim
```

### 2.5 `core/src/store/translation.rs`（infrastructure 实现）
```rust
/// 第二连接（同一 library.db，WAL + busy_timeout=5000）；实现两个契约 trait
pub struct TranslationRepo { conn: Connection }
impl TranslationRepo {
    pub fn open(data_dir: &Path) -> Result<TranslationRepo>;  // 打开 + migrate_conn（幂等）
}
impl TranslationCacheRepository for TranslationRepo { … }     // SQL: 见 §3
impl ProviderConfig for TranslationRepo { … }                 // settings 表读写
```

### 2.6 `core/src/error.rs` 新增变体
```rust
#[error("翻译服务未配置：{0}")]
NotConfigured(String),                       // US-12 无 key / 未知 Provider
#[error("网络请求失败：{detail}（原文：{source_text}）")]
Network { detail: String, source_text: String },   // US-12 错误携带原文，UI 重试不丢原文
```

### 2.7 `core/src/api.rs` 桥接（新增，全部 async，docs/03 §4 对齐 + US-7 修正）
```rust
// DTO（FRB 生成面）
pub struct DictInfoView   { pub id: String, pub name: String, pub word_count: u64, pub path: String }
pub struct DictEntryView  { pub word: String, pub phonetic: Option<String>, pub pos: Option<String>,
                            pub definition: String, pub example: Option<String> }
pub struct TranslationView { pub text: String, pub from: String, pub to: String,
                             pub provider: String, pub from_cache: bool }

// 单例（library_open 装配，见 §4）
static DICT: OnceLock<Mutex<DictService>> = OnceLock::new();
static TRANSLATION: OnceLock<Mutex<TranslationService>> = OnceLock::new();

pub async fn dict_install(path: String) -> std::result::Result<DictInfoView, String>;   // US-7 返回 DictInfo（docs/03 §4 原 ()，ADR 关联裁定4）
pub async fn dict_remove(dict_id: String) -> std::result::Result<(), String>;          // docs/03 §4 补充
pub async fn dict_list() -> std::result::Result<Vec<DictInfoView>, String>;
pub async fn dict_lookup(word: String, dict_id: Option<String>)
    -> std::result::Result<Option<DictEntryView>, String>;
pub async fn translate(text: String, from: String, to: String)
    -> std::result::Result<TranslationView, String>;      // 命中缓存 from_cache=true（US-10/13）
pub async fn translate_cache_clear() -> std::result::Result<(), String>;
pub async fn translate_set_config(provider: String, key: String) -> std::result::Result<(), String>;
// 错误映射：err_msg(Display) 泛型不变；api 内部 Lang::parse 失败 → Err(Other("不支持的语言代码: …"))
// 注意：FRB async 函数体内不做任何 .await（同步阻塞 ureq/rusqlite），锁在请求期间持有（单用户无并发压力）
```

## 3. 数据模型变化（store v3 迁移）

### 3.1 迁移追加（`migrate_conn` 中 `version < 3` 分支，DDL 对齐 docs/04 §5）
```sql
CREATE TABLE IF NOT EXISTS translation_cache (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  source_text TEXT NOT NULL,
  from_lang   TEXT NOT NULL,
  to_lang     TEXT NOT NULL,
  provider    TEXT NOT NULL,
  result      TEXT NOT NULL,             -- JSON Translation
  created_at  INTEGER NOT NULL,
  hit_count   INTEGER NOT NULL DEFAULT 1
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_tcache
  ON translation_cache(source_text, from_lang, to_lang, provider);
CREATE TABLE IF NOT EXISTS settings (    -- Provider key 最小配置通道（ADR 关联裁定3）
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
PRAGMA user_version = 3;
```
- 迁移 v3 前先 `migrate_conn` 跑 v1/v2（幂等），保证存量 books/reading_progress 不丢；
  迁移测试：构造 user_version=2 的库（含存量书与进度）→ 重开 → 断言数据完整 + 新表存在。
- settings 键约定：`translate.default_provider`（默认 `"deepl"`）、`translate.key.<provider>`。
- `vocabulary` 表本期不建（TRANS-04 排除）。

### 3.2 `TranslationRepo` 关键 SQL
```sql
-- cache_get
SELECT result, created_at, hit_count FROM translation_cache
 WHERE source_text=?1 AND from_lang=?2 AND to_lang=?3 AND provider=?4;
-- cache_put（UPSERT 不重置 hit_count；并发双写安全）
INSERT INTO translation_cache (source_text,from_lang,to_lang,provider,result,created_at,hit_count)
 VALUES (?1,?2,?3,?4,?5,?6,?7)
 ON CONFLICT(source_text,from_lang,to_lang,provider)
 DO UPDATE SET result=excluded.result, created_at=excluded.created_at;
-- cache_incr_hit
UPDATE translation_cache SET hit_count = hit_count + 1
 WHERE source_text=?1 AND from_lang=?2 AND to_lang=?3 AND provider=?4;
-- cache_clear / cache_count / settings 读写（key/value）
DELETE FROM translation_cache;
SELECT COUNT(*) FROM translation_cache;
SELECT value FROM settings WHERE key=?1;  INSERT INTO settings(key,value) VALUES(?1,?2)
  ON CONFLICT(key) DO UPDATE SET value=excluded.value;
```

## 4. 装配与关键时序

### 4.1 `library_open` 装配（api.rs）
```
library_open(data_dir)
 ├─ Store::open(data_dir)                      // 迁移至 v3（含 dicts/ 目录创建）
 ├─ SERVICE.set(Mutex<LibraryService::new(store)>)          // 既有，零改动
 ├─ cache_repo = Box::new(TranslationRepo::open(data_dir)?) as Box<dyn TranslationCacheRepository + Send>
 ├─ config_repo = Box::new(TranslationRepo::open(data_dir)?) as Box<dyn ProviderConfig + Send>
 │      // 两个 trait 各持一个第二连接（同库 WAL + busy_timeout；SQLite 多连接标准用法；迁移幂等）
 ├─ DICT.set(Mutex<DictService::new(data_dir)?>)            // 扫描既有词库注册
 └─ TRANSLATION.set(Mutex<TranslationService::new(cache_repo, config_repo,
        vec![Box::new(DeepLProvider::new()), Box::new(EchoProvider::new())])>)
```

### 4.2 翻译请求时序（docs/03 §6.3 落地）
```
reader_page 选中文本 → translate(text,"auto","zh")
 → api::translate（FRB async，池线程）→ 锁 TRANSLATION
 → svc.translate：normalize → provider=deepl → key?（None→NotConfigured）
 → cache_get 命中 → incr_hit → TranslationView{from_cache:true}（0 网络，US-10/14）
 → 未命中 → DeepLProvider.translate（ureq POST /v2/translate，auth header，仅 text/from/to，US-9/13）
 → 成功 → cache_put(hit_count=1) → TranslationView{from_cache:false}
 → 失败(Network{..}) → 不写缓存 → Err 文案含原文（US-12）
 → UI 浮层：loading → 结果(provider 名 + 缓存/在线标记) | 错误(重试按钮)
```

### 4.3 查词时序
```
reader_page 双击选中单词 → dict_lookup(word)
 → api::dict_lookup（FRB async）→ 锁 DICT → DictService::lookup
 → 注册表空 → Err("未安装词库…")（US-3）
 → 每词库懒加载 .idx 入内存（OnceCell；US-8"首次加载不计入"）
 → 二分/线性归一匹配（US-5）→ .dict 随机读区段 → parse_entry（sametypesequence，US-1/6）
 → Ok(Some(DictEntryView)) | Ok(None)（未收录，US-2）
 → UI 词典卡片：词条/音标/词性/释义/例句；None → "未找到"；Err → 文案
```

## 5. 阅读器翻译浮层与查词卡片最小 UI 方案

### 5.1 app 服务层（application）
`app/lib/services/translate_backend.dart`（仿 library_backend.dart 抽象 + DTO 模式）：
```dart
class DictEntryData { final String word; final String? phonetic; final String? pos;
  final String definition; final String? example; }
class DictInfoData  { final String id; final String name; final int wordCount; final String path; }
class TranslationData { final String text; final String from; final String to;
  final String provider; final bool fromCache; }

abstract class TranslateBackend {
  Future<DictInfoData> installDict(String path);
  Future<void> removeDict(String id);
  Future<List<DictInfoData>> listDicts();
  Future<DictEntryData?> lookup(String word, {String? dictId});
  Future<TranslationData> translate(String text, {String from = 'auto', String to = 'zh'});
  Future<void> clearCache();
  Future<void> setConfig(String provider, String key);
}
```
`rust_translate_backend.dart`：实现（转发 `rust.dictInstall/dictRemove/dictList/dictLookup/translate/
translateCacheClear/translateSetConfig` → DTO）；测试用 `FakeTranslateBackend`（test/）。

### 5.2 reader_page 接入点（interface）
- 构造参数新增 `this.translateBackend`（`TranslateBackend?`；null → 隐藏翻译/查词入口，既有
  测试零回归）。
- 滚动模式：正文 `Text` 外包 `SelectionArea(onSelectionChanged: (s) => _onSelectedText(s.plainText))`。
- 分页模式：`PagedWebView` 增 `onSelectedText` 回调；`paginationJs` 增：
  `document.addEventListener('selectionchange', …)` → 非空时
  `window.flutter_inappwebview.callHandler('selectedText', text)`；组件
  `onCallBackHandler` 接 `selectedText` → `onSelectedText?.call(text)`（与既有 `readerFlutter`
  进度回调同款通道）。
- 选中工具条：`_selectedText` 非空时在正文与底部导航间条件渲染一行
  （`翻译` / `查词` / `取消` 按钮，Material ActionChip 行）。
- 翻译入口：`translate(_selectedText)` → 页面持有浮层状态
  （idle/loading/result/error + `_translation`/`_error`），渲染 `TranslationResultCard`；
  失败显示错误文案 + `重试`（重发同一文本，不丢原文，US-12）。
- 查词入口：`lookup(_selectedText)` → `DictResultCard`；`Ok(None)` → "未找到"（US-2）；
  `Err` 含"词库/未安装"文案（US-3）。
- 浮层组件（`app/lib/widgets/translation_popup.dart`）：
  `TranslationResultCard(translation: TranslationData)` —— 译文 + Provider 名 +
  缓存标记（fromCache → "缓存"徽标，US-13/15 可断言）；`DictResultCard(entry: DictEntryData?)`；
  `OverlayError(message, onRetry)`。加载中显示 `CircularProgressIndicator`（US-15 可断言）。

### 5.3 设置页最小区块（settings_page.dart，TRANS-03 进阶 UI 不在本 REQ）
- 词库：导入（file_picker 选 `.ifo` → `installDict`）、列表（`listDicts` + 移除按钮 `removeDict`）；
- Provider：key 输入框（`setConfig('deepl', key)`，落 settings）；
- 隐私：`清空翻译缓存` 按钮（`clearCache`，docs/02 §10 / docs/04 领域规则4）。

## 6. 错误分类（复用 error.rs + 新增变体）

| 场景 | 检测/触发 | 错误变体 | UI 文案要点 |
|---|---|---|---|
| 无词库查词（US-3） | 注册表空 | `NotFound("未安装词库，请先在设置中导入")` | 含"词库""未安装/导入" |
| 未收录词（US-2） | 索引无命中 | `Ok(None)`（非错误） | "未找到" |
| 坏词库：.ifo 缺 wordcount / .idx 截断 / 偏移越界 / .dz 损坏（US-6） | 解析边界校验 | `Corrupt(原因分类)` | 含原因分类；已装列表不受影响 |
| Provider 未配置 key / 未知 Provider（US-12） | `provider_key` 为 None | **新增** `NotConfigured("…API Key…")` | 含"未配置/API Key" |
| 网络失败/Provider 异常（US-12） | ureq 错误 | **新增** `Network{detail, source_text}` | 含"网络/失败"语义 + 原文 |
| 语言代码非法 | `Lang::parse` None | `Other("不支持的语言代码: …")` | 原样透出 |
| 文件 IO / 数据库 | — | `Io` / `Corrupt("数据库错误: …")`（既有 From） | 原样透出 |

原则：任何输入不 panic（ADR 决策点1 同步模型 + checked 解析）；api 错误映射经
`err_msg(Display)` 泛型自动覆盖新变体（api.rs 零结构改动）。

## 7. 与既有约定的兼容性核对
- [x] **ddd-rules 零改动且违规=0**：新文件路径全部落在既有层声明内（dict/、store/、api.rs、
      types.rs、app/lib/services）；store 实现契约只依赖 `crate::types`（ADR 决策点3 关键论证）；
      app 页面不 import 桥接生成物（services 转发）。
- [x] **不破坏 Locator/听读进度**：不触碰 `locator`/`reading_progress`/`tts`；翻译/查词以选中
      纯文本为输入，不产生新锚定（docs/04 领域规则：听读同进度不变式保持）。
- [x] **不跨越限界上下文**：Translation 上下文内部完成；settings 表为 Provider 凭据最小通道
      （docs/04 §5 已有 DDL）；`vocabulary` 表不建。
- [x] **FRB 生成**：T-006 再生成 `frb_generated.rs` + `app/lib/src/rust/**`；新桥接为 async
      （FRB 2.13 支持），既有 sync 函数不动；生成物属"勿手改"文件，回归验证既有 FFI 端到端。
- [x] **既有 store 迁移**：v1/v2 分支原样保留，v3 追加（CREATE IF NOT EXISTS + user_version）；
      `migrate` 提取 `migrate_conn` 为行为等价重构；存量库升级测试覆盖。
- [x] **docs 同步**：docs/03 §4 dict/translate 契约更新（`dict_install` 返回 DictInfo、新增
      `dict_remove`、async 说明）随 T-006 提交。
- [x] **隐私**：缓存仅存选中文本相关列（US-13 表结构断言）；Provider 请求只带 text/from/to；
      清空入口随设置区块交付（docs/04 领域规则4）。
- [x] **`TextSelection` 不新增**：翻译/查词入口消费选中纯文本（`translate(text,…)` 签名即纯
      文本，docs/03 §4）；`TextSelection`（章+片段+偏移）归笔记 REQ（NOTE 系列）定义，本 REQ
      不占用（01-req §4 已声明与笔记 REQ 无依赖）。

## 8. 已知取舍（非冲突，均含处置）
1. **trait 落位 types.rs 而非 dict 模块**（01-req 措辞偏差）→ ADR 决策点3 论证（ddd-lint 机械
   规则 + 规则表冻结），处置为落共享内核。
2. **分页模式"最小选区回传"纳入本 REQ**（01-req §4 声称既有能力 D3 实际不存在）→ ADR 决策点2
   处置：~20 行 JS + 一个回调，完整选区机制归 REQ-001 演进/笔记 REQ。
3. **Provider 默认 deepl**（无 key 即 `NotConfigured`）→ `translate_set_config("echo","")` 切
   echo 演示（ADR 关联裁定2）。
4. **两 trait 各持一个第二连接**（同库双连接）→ SQLite 多连接 + WAL + busy_timeout 标准用法，
   迁移幂等；未来如需单连接可重构为共享 `Connection`（记录不阻塞）。
5. **大词库 .dz**：流式解压落盘（安装期一次性）；100MB+ mmap/区段解压留 TRANS-03。
6. **g 类型（HTML 释义）原样保留**：UI 最小标签剥离或原样展示（开发阶段定，降级线对齐
   01-req §5 风险8：先支持 m/t/g 主类型 + 朗道词库验证）。
