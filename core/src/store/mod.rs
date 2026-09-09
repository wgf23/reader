//! SQLite 存储封装：迁移（user_version）/ WAL / 事务。
//!
//! DDL：docs/04-module-design.md §5（books / book_files / translation_cache / settings）；
//! 性能：WAL（docs/03 §5）。REQ-003：`migrate_conn` 为 Store 主连接与 TranslationRepo
//! 第二连接共用的幂等迁移；`translation.rs` 实现翻译缓存与 Provider 配置仓储。

mod annotations;
mod search_index;
mod translation;
pub use annotations::AnnotationRepo;
pub use search_index::SearchIndexRepo;
pub use translation::TranslationRepo;

use std::path::Path;

use rusqlite::{Connection, OptionalExtension};

use crate::error::{Error, Result};

/// 数据目录结构：
///   <data_dir>/library.db
///   <data_dir>/cache/        （规范 EPUB 缓存）
///   <data_dir>/dicts/        （StarDict 词库安装目录，docs/02 §5）
pub struct Store {
    conn: Connection,
    data_dir: std::path::PathBuf,
}

/// 书籍记录（books 表行）
#[derive(Debug, Clone)]
pub struct BookRecord {
    pub id: String,
    pub title: String,
    pub authors: Vec<String>,
    pub language: Option<String>,
    pub source_path: String,
    pub source_hash: String,
    pub format: String,
    pub canonical_path: Option<String>,
    pub added_at: i64,
}

/// 阅读进度记录
#[derive(Debug, Clone)]
pub struct ProgressRecord {
    pub href: String,
    pub progression: f32,
    pub updated_at: i64,
}

impl Store {
    /// 打开（或创建）书库；自动执行迁移。
    pub fn open(data_dir: &Path) -> Result<Store> {
        std::fs::create_dir_all(data_dir).map_err(Error::Io)?;
        std::fs::create_dir_all(data_dir.join("cache")).map_err(Error::Io)?;
        std::fs::create_dir_all(data_dir.join("dicts")).map_err(Error::Io)?;
        let conn = Connection::open(data_dir.join("library.db")).map_err(Error::from)?;
        // REQ-009 D3/C12：4 连接 WAL 下补 busy_timeout，避免 SQLITE_BUSY。
        conn.execute_batch(
            "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; PRAGMA foreign_keys=ON;",
        )
        .map_err(Error::from)?;
        migrate_conn(&conn)?;
        let store = Store {
            conn,
            data_dir: data_dir.to_path_buf(),
        };
        Ok(store)
    }

    pub fn cache_dir(&self) -> std::path::PathBuf {
        self.data_dir.join("cache")
    }

    pub fn dicts_dir(&self) -> std::path::PathBuf {
        self.data_dir.join("dicts")
    }

    /// 保存阅读进度（同一本书一行，UPSERT）
    pub fn save_progress(&mut self, book_id: &str, href: &str, progression: f32) -> Result<()> {
        let now = now_unix();
        self.conn
            .execute(
                "INSERT INTO reading_progress (book_id, href, progression, updated_at)
                 VALUES (?1, ?2, ?3, ?4)
                 ON CONFLICT(book_id) DO UPDATE SET href=?2, progression=?3, updated_at=?4",
                rusqlite::params![book_id, href, progression, now],
            )
            .map_err(Error::from)?;
        Ok(())
    }

    /// 读取阅读进度
    pub fn load_progress(&self, book_id: &str) -> Result<Option<ProgressRecord>> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT href, progression, updated_at FROM reading_progress WHERE book_id = ?1",
            )
            .map_err(Error::from)?;
        let mut rows = stmt
            .query_map(rusqlite::params![book_id], |r| {
                Ok(ProgressRecord {
                    href: r.get(0)?,
                    progression: r.get(1)?,
                    updated_at: r.get(2)?,
                })
            })
            .map_err(Error::from)?;
        rows.next().transpose().map_err(Error::from)
    }

    pub fn insert_book(&mut self, record: &BookRecord) -> Result<()> {
        let authors = serde_json::to_string(&record.authors)
            .map_err(|e| Error::Other(format!("authors 序列化失败: {e}")))?;
        let now = now_unix();
        self.conn
            .execute(
                "INSERT OR REPLACE INTO books (id, title, authors, language, source_path, source_hash, format, added_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8)",
                rusqlite::params![
                    record.id,
                    record.title,
                    authors,
                    record.language,
                    record.source_path,
                    record.source_hash,
                    record.format,
                    now
                ],
            )
            .map_err(Error::from)?;
        if let Some(canonical) = &record.canonical_path {
            self.conn
                .execute(
                    "INSERT OR REPLACE INTO book_files (book_id, canonical_path) VALUES (?1, ?2)",
                    rusqlite::params![record.id, canonical],
                )
                .map_err(Error::from)?;
        }
        Ok(())
    }

    pub fn list_books(&self) -> Result<Vec<BookRecord>> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT b.id, b.title, b.authors, b.language, b.source_path, b.source_hash, b.format, b.added_at, f.canonical_path
                 FROM books b LEFT JOIN book_files f ON f.book_id = b.id
                 ORDER BY b.added_at DESC",
            )
            .map_err(Error::from)?;
        let rows = stmt
            .query_map([], |r| {
                let authors_json: String = r.get(2)?;
                let authors = serde_json::from_str(&authors_json).unwrap_or_default();
                Ok(BookRecord {
                    id: r.get(0)?,
                    title: r.get(1)?,
                    authors,
                    language: r.get(3)?,
                    source_path: r.get(4)?,
                    source_hash: r.get(5)?,
                    format: r.get(6)?,
                    added_at: r.get(7)?,
                    canonical_path: r.get(8)?,
                })
            })
            .map_err(Error::from)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row.map_err(Error::from)?);
        }
        Ok(out)
    }

    pub fn get_book(&self, id: &str) -> Result<BookRecord> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT b.id, b.title, b.authors, b.language, b.source_path, b.source_hash, b.format, b.added_at, f.canonical_path
                 FROM books b LEFT JOIN book_files f ON f.book_id = b.id WHERE b.id = ?1",
            )
            .map_err(Error::from)?;
        let row = stmt
            .query_row(rusqlite::params![id], |r| {
                let authors_json: String = r.get(2)?;
                let authors = serde_json::from_str(&authors_json).unwrap_or_default();
                Ok(BookRecord {
                    id: r.get(0)?,
                    title: r.get(1)?,
                    authors,
                    language: r.get(3)?,
                    source_path: r.get(4)?,
                    source_hash: r.get(5)?,
                    format: r.get(6)?,
                    added_at: r.get(7)?,
                    canonical_path: r.get(8)?,
                })
            })
            .map_err(|e| match e {
                rusqlite::Error::QueryReturnedNoRows => {
                    Error::NotFound(format!("书籍不存在: {id}"))
                }
                other => Error::from(other),
            })?;
        Ok(row)
    }

    /// 删除书籍：同一事务内显式删 `fts_books`（虚拟表不参与 FK 级联，ADR D3），
    /// 再删 books（FK 级联清 annotations / reading_progress）。
    pub fn remove_book(&mut self, id: &str) -> Result<()> {
        let tx = self.conn.transaction().map_err(Error::from)?;
        tx.execute("DELETE FROM fts_books WHERE book_id = ?1", rusqlite::params![id])
            .map_err(Error::from)?;
        tx.execute("DELETE FROM books WHERE id = ?1", rusqlite::params![id])
            .map_err(Error::from)?;
        tx.commit().map_err(Error::from)?;
        Ok(())
    }

    /// 读取设置项（无记录返回 None）。REQ-005 决策点6：听书设置 `listen.*` 键。
    pub fn get_setting(&self, key: &str) -> Result<Option<String>> {
        self.conn
            .query_row(
                "SELECT value FROM settings WHERE key = ?1",
                rusqlite::params![key],
                |r| r.get(0),
            )
            .optional()
            .map_err(Error::from)
    }

    /// 写入设置项（UPSERT，复用既有 settings 表，零迁移）。
    pub fn set_setting(&mut self, key: &str, value: &str) -> Result<()> {
        self.conn
            .execute(
                "INSERT INTO settings (key, value) VALUES (?1, ?2)
                 ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                rusqlite::params![key, value],
            )
            .map_err(Error::from)?;
        Ok(())
    }

    pub fn integrity_check(&self) -> Result<bool> {
        let ok: String = self
            .conn
            .query_row("PRAGMA integrity_check", [], |r| r.get(0))
            .map_err(Error::from)?;
        Ok(ok == "ok")
    }
}

fn now_unix() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// 幂等迁移（v1 → v2 → v3）：Store 主连接与 TranslationRepo 第二连接共用（REQ-003 02-design §3）。
/// v1/v2 分支行为与既有完全一致；v3 追加 translation_cache + settings（docs/04 §5 DDL）。
pub(crate) fn migrate_conn(conn: &Connection) -> Result<()> {
    let version: i64 = conn
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .map_err(Error::from)?;
    if version < 1 {
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS books (
  id            TEXT PRIMARY KEY,
  title         TEXT NOT NULL,
  authors       TEXT NOT NULL DEFAULT '[]',
  language      TEXT,
  source_path   TEXT NOT NULL,
  source_hash   TEXT NOT NULL UNIQUE,
  format        TEXT NOT NULL,
  added_at      INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS book_files (
  book_id        TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
  canonical_path TEXT
);
CREATE INDEX IF NOT EXISTS idx_books_hash ON books(source_hash);
PRAGMA user_version = 1;
"#,
        )
        .map_err(Error::from)?;
    }
    if version < 2 {
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS reading_progress (
  book_id     TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
  href        TEXT NOT NULL,
  progression REAL NOT NULL,
  updated_at  INTEGER NOT NULL
);
PRAGMA user_version = 2;
"#,
        )
        .map_err(Error::from)?;
    }
    if version < 3 {
        // REQ-003（docs/04 §5 翻译缓存 + 设置）：vocabulary 表本期不建（TRANS-04 排除，不占迁移号）
        conn.execute_batch(
            r#"
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
"#,
        )
        .map_err(Error::from)?;
    }
    if version < 4 {
        // REQ-009（docs/04 §5 + ADR D3）：annotations + idx_annot_book + fts_books。
        // fts_books 复用既有虚拟表并扩列：text_bi 为唯一索引列（CJK bigram 预处理流），
        // href/chapter/text 仅存储（UNINDEXED），text 供应用层抽 snippet 与关键词区间。
        conn.execute_batch(
            r#"
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
  book_id UNINDEXED,
  href    UNINDEXED,
  chapter UNINDEXED,
  text    UNINDEXED,
  text_bi,
  tokenize='unicode61'
);
PRAGMA user_version = 4;
"#,
        )
        .map_err(Error::from)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_record() -> BookRecord {
        BookRecord {
            id: "b1".to_string(),
            title: "测试书".to_string(),
            authors: vec!["张三".to_string()],
            language: Some("zh".to_string()),
            source_path: "/tmp/x.epub".to_string(),
            source_hash: "abc123".to_string(),
            format: "epub".to_string(),
            canonical_path: Some("/tmp/cache/abc123.epub".to_string()),
            added_at: 1,
        }
    }

    #[test]
    fn open_migrate_insert_list_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = Store::open(dir.path()).unwrap();
        assert!(store.integrity_check().unwrap());
        store.insert_book(&sample_record()).unwrap();
        let books = store.list_books().unwrap();
        assert_eq!(books.len(), 1);
        assert_eq!(books[0].title, "测试书");
        assert_eq!(books[0].authors, vec!["张三".to_string()]);
        assert_eq!(books[0].canonical_path.as_deref(), Some("/tmp/cache/abc123.epub"));
        let got = store.get_book("b1").unwrap();
        assert_eq!(got.format, "epub");
    }

    #[test]
    fn dedup_by_hash() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = Store::open(dir.path()).unwrap();
        store.insert_book(&sample_record()).unwrap();
        let mut dup = sample_record();
        dup.id = "b2".to_string();
        store.insert_book(&dup).unwrap(); // 同 hash，INSERT OR REPLACE → 仍 1 本
        assert_eq!(store.list_books().unwrap().len(), 1);
    }

    #[test]
    fn remove_book() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = Store::open(dir.path()).unwrap();
        store.insert_book(&sample_record()).unwrap();
        store.remove_book("b1").unwrap();
        assert!(store.get_book("b1").is_err());
    }

    #[test]
    fn setting_roundtrip_and_upsert() {
        // US-11（持久化侧）：无记录 → None；写入/覆盖读回；复用 settings 表零迁移
        let dir = tempfile::tempdir().unwrap();
        let mut store = Store::open(dir.path()).unwrap();
        assert!(store.get_setting("listen.speed").unwrap().is_none());
        store.set_setting("listen.speed", "1.5").unwrap();
        assert_eq!(store.get_setting("listen.speed").unwrap().as_deref(), Some("1.5"));
        store.set_setting("listen.speed", "2.0").unwrap();
        assert_eq!(store.get_setting("listen.speed").unwrap().as_deref(), Some("2.0"));
        store.set_setting("listen.voice_id", "system_female").unwrap();
        store.set_setting("listen.auto_next", "0").unwrap();
        assert_eq!(
            store.get_setting("listen.voice_id").unwrap().as_deref(),
            Some("system_female")
        );
        assert_eq!(store.get_setting("listen.auto_next").unwrap().as_deref(), Some("0"));
    }

    #[test]
    fn timestamps_are_real() {
        // 变异防护：now_unix 的常量替换（0/1/-1）必须被识破
        let dir = tempfile::tempdir().unwrap();
        let mut store = Store::open(dir.path()).unwrap();
        store.insert_book(&sample_record()).unwrap();
        let rec = store.get_book("b1").unwrap();
        assert!(rec.added_at > 1_000_000_000, "added_at 应为真实时间戳: {}", rec.added_at);

        store.save_progress("b1", "chapter_0001.xhtml", 0.5).unwrap();
        let p = store.load_progress("b1").unwrap().expect("应有进度");
        assert!(p.updated_at > 1_000_000_000, "updated_at 应为真实时间戳: {}", p.updated_at);
        assert_eq!(p.href, "chapter_0001.xhtml");
        assert!((p.progression - 0.5).abs() < 1e-4);
    }

    #[test]
    fn v3_to_v4_migration_idempotent_and_preserves_data() {
        // US-23：构造 user_version=3 存量库（books/reading_progress/translation_cache/settings）
        let dir = tempfile::tempdir().unwrap();
        let db = dir.path().join("library.db");
        {
            let conn = Connection::open(&db).unwrap();
            conn.execute_batch(
                "PRAGMA user_version=3;
                 CREATE TABLE books (id TEXT PRIMARY KEY, title TEXT NOT NULL, authors TEXT NOT NULL DEFAULT '[]',
                   language TEXT, source_path TEXT NOT NULL, source_hash TEXT NOT NULL UNIQUE, format TEXT NOT NULL,
                   added_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
                 CREATE TABLE book_files (book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE, canonical_path TEXT);
                 CREATE TABLE reading_progress (book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
                   href TEXT NOT NULL, progression REAL NOT NULL, updated_at INTEGER NOT NULL);
                 CREATE TABLE translation_cache (id INTEGER PRIMARY KEY AUTOINCREMENT, source_text TEXT NOT NULL,
                   from_lang TEXT NOT NULL, to_lang TEXT NOT NULL, provider TEXT NOT NULL, result TEXT NOT NULL,
                   created_at INTEGER NOT NULL, hit_count INTEGER NOT NULL DEFAULT 1);
                 CREATE UNIQUE INDEX idx_tcache ON translation_cache(source_text, from_lang, to_lang, provider);
                 CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                 INSERT INTO books (id,title,authors,source_path,source_hash,format,added_at,updated_at)
                   VALUES ('bk1','存量书','[\"张三\"]','/x.epub','hash1','epub',1,1);
                 INSERT INTO reading_progress (book_id,href,progression,updated_at) VALUES ('bk1','c1.xhtml',0.5,1);",
            )
            .unwrap();
        }
        // 重开（走 v4 迁移）
        let store = Store::open(dir.path()).unwrap();
        assert_eq!(store.list_books().unwrap().len(), 1, "存量书不丢");
        let p = store.load_progress("bk1").unwrap().expect("进度不丢");
        assert_eq!(p.href, "c1.xhtml");
        let ver: i64 = store
            .conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(ver, 4);
        // annotations / idx_annot_book / fts_books 均存在且可用
        store
            .conn
            .execute(
                "INSERT INTO annotations (id,book_id,kind,locator_json,created_at,updated_at)
                 VALUES ('a1','bk1','highlight','{}',1,1)",
                [],
            )
            .unwrap();
        store
            .conn
            .execute(
                "INSERT INTO fts_books (book_id,href,chapter,text,text_bi) VALUES ('bk1','c1','章','城市','城市')",
                [],
            )
            .unwrap();
        let n: i64 = store
            .conn
            .query_row("SELECT COUNT(*) FROM fts_books", [], |r| r.get(0))
            .unwrap();
        assert_eq!(n, 1);
        // 重复打开幂等（no-op）
        let store2 = Store::open(dir.path()).unwrap();
        let ver2: i64 = store2
            .conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(ver2, 4);
        assert_eq!(store2.list_books().unwrap().len(), 1);
    }
}
