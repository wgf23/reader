//! 翻译基础设施：TranslationRepo（第二连接）实现 `TranslationCacheRepository` +
//! `ProviderConfig` 两个跨层契约（契约定义于 `crate::types`，ADR REQ-003 决策点3）。
//!
//! 分层：infrastructure 层，只依赖 `crate::types`/`crate::error`/rusqlite；
//! 禁 `crate::dict` 等 domain 业务模块（ddd-rules 冻结，违规=0 论证见 02-adr）。
//! SQLite 多连接标准用法：同库双连接 + WAL + busy_timeout（迁移幂等共享）。

use std::path::Path;

use rusqlite::{params, Connection, OptionalExtension};

use crate::error::{Error, Result};
use crate::store::migrate_conn;
use crate::types::{
    CacheEntry, CacheKey, ProviderConfig, Translation, TranslationCacheRepository,
};

/// settings 键约定（docs/04 §5 / REQ-003 02-design §3.1）
const KEY_DEFAULT_PROVIDER: &str = "translate.default_provider";
const DEFAULT_PROVIDER: &str = "deepl";

/// 第二连接（同一 library.db；WAL + busy_timeout=5000）
pub struct TranslationRepo {
    conn: Connection,
}

impl TranslationRepo {
    pub fn open(data_dir: &Path) -> Result<TranslationRepo> {
        std::fs::create_dir_all(data_dir).map_err(Error::Io)?;
        let conn = Connection::open(data_dir.join("library.db")).map_err(Error::from)?;
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;")
            .map_err(Error::from)?;
        migrate_conn(&conn)?;
        Ok(TranslationRepo { conn })
    }

    fn provider_key_setting(provider: &str) -> String {
        format!("translate.key.{provider}")
    }
}

impl TranslationCacheRepository for TranslationRepo {
    fn cache_get(&self, key: &CacheKey) -> Result<Option<CacheEntry>> {
        let row: Option<(String, i64, i64)> = self
            .conn
            .query_row(
                "SELECT result, created_at, hit_count FROM translation_cache
                 WHERE source_text=?1 AND from_lang=?2 AND to_lang=?3 AND provider=?4",
                params![
                    key.source_text,
                    key.from_lang.as_str(),
                    key.to_lang.as_str(),
                    key.provider
                ],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .optional()
            .map_err(Error::from)?;
        let Some((result_json, created_at, hit_count)) = row else {
            return Ok(None);
        };
        let result: Translation = serde_json::from_str(&result_json)
            .map_err(|e| Error::Corrupt(format!("翻译缓存数据损坏: {e}")))?;
        Ok(Some(CacheEntry {
            key: key.clone(),
            result,
            created_at,
            hit_count: hit_count as u64,
        }))
    }

    fn cache_put(&mut self, entry: &CacheEntry) -> Result<()> {
        let result_json = serde_json::to_string(&entry.result)
            .map_err(|e| Error::Other(format!("译文序列化失败: {e}")))?;
        self.conn
            .execute(
                "INSERT INTO translation_cache (source_text,from_lang,to_lang,provider,result,created_at,hit_count)
                 VALUES (?1,?2,?3,?4,?5,?6,?7)
                 ON CONFLICT(source_text,from_lang,to_lang,provider)
                 DO UPDATE SET result=excluded.result, created_at=excluded.created_at",
                params![
                    entry.key.source_text,
                    entry.key.from_lang.as_str(),
                    entry.key.to_lang.as_str(),
                    entry.key.provider,
                    result_json,
                    entry.created_at,
                    entry.hit_count as i64
                ],
            )
            .map_err(Error::from)?;
        Ok(())
    }

    fn cache_incr_hit(&mut self, key: &CacheKey) -> Result<()> {
        self.conn
            .execute(
                "UPDATE translation_cache SET hit_count = hit_count + 1
                 WHERE source_text=?1 AND from_lang=?2 AND to_lang=?3 AND provider=?4",
                params![
                    key.source_text,
                    key.from_lang.as_str(),
                    key.to_lang.as_str(),
                    key.provider
                ],
            )
            .map_err(Error::from)?;
        Ok(())
    }

    fn cache_clear(&mut self) -> Result<()> {
        self.conn
            .execute("DELETE FROM translation_cache", [])
            .map_err(Error::from)?;
        Ok(())
    }

    fn cache_count(&self) -> Result<u64> {
        let n: i64 = self
            .conn
            .query_row("SELECT COUNT(*) FROM translation_cache", [], |r| r.get(0))
            .map_err(Error::from)?;
        Ok(n as u64)
    }
}

impl ProviderConfig for TranslationRepo {
    fn default_provider(&self) -> Result<String> {
        let v: Option<String> = self
            .conn
            .query_row(
                "SELECT value FROM settings WHERE key=?1",
                params![KEY_DEFAULT_PROVIDER],
                |r| r.get(0),
            )
            .optional()
            .map_err(Error::from)?;
        Ok(v.unwrap_or_else(|| DEFAULT_PROVIDER.to_string()))
    }

    fn provider_key(&self, provider: &str) -> Result<Option<String>> {
        self.conn
            .query_row(
                "SELECT value FROM settings WHERE key=?1",
                params![Self::provider_key_setting(provider)],
                |r| r.get(0),
            )
            .optional()
            .map_err(Error::from)
    }

    fn set_provider_key(&mut self, provider: &str, key: &str) -> Result<()> {
        upsert_setting(&self.conn, &Self::provider_key_setting(provider), key)
    }

    fn set_default_provider(&mut self, provider: &str) -> Result<()> {
        upsert_setting(&self.conn, KEY_DEFAULT_PROVIDER, provider)
    }
}

fn upsert_setting(conn: &Connection, key: &str, value: &str) -> Result<()> {
    conn.execute(
        "INSERT INTO settings(key,value) VALUES(?1,?2)
         ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        params![key, value],
    )
    .map_err(Error::from)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::Lang;

    fn key(s: &str, from: Lang, to: Lang, provider: &str) -> CacheKey {
        CacheKey {
            source_text: s.to_string(),
            from_lang: from,
            to_lang: to,
            provider: provider.to_string(),
        }
    }

    fn entry(s: &str, provider: &str) -> CacheEntry {
        CacheEntry {
            key: key(s, Lang::En, Lang::Zh, provider),
            result: Translation {
                text: format!("译文:{s}"),
                from: Lang::En,
                to: Lang::Zh,
                provider: provider.to_string(),
            },
            created_at: 1_700_000_000,
            hit_count: 1,
        }
    }

    #[test]
    fn put_get_roundtrip_and_upsert_preserves_hit_count() {
        let dir = tempfile::tempdir().unwrap();
        let mut repo = TranslationRepo::open(dir.path()).unwrap();
        repo.cache_put(&entry("hello", "echo")).unwrap();
        let got = repo
            .cache_get(&key("hello", Lang::En, Lang::Zh, "echo"))
            .unwrap()
            .expect("应有缓存");
        assert_eq!(got.result.text, "译文:hello");
        assert_eq!(got.hit_count, 1);
        // 命中 +1
        repo.cache_incr_hit(&key("hello", Lang::En, Lang::Zh, "echo"))
            .unwrap();
        // UPSERT 不重置 hit_count（02-design §3.2）
        repo.cache_put(&entry("hello", "echo")).unwrap();
        let got = repo
            .cache_get(&key("hello", Lang::En, Lang::Zh, "echo"))
            .unwrap()
            .unwrap();
        assert_eq!(got.hit_count, 2, "UPSERT 不应重置 hit_count");
        assert_eq!(got.result.text, "译文:hello");
    }

    #[test]
    fn cache_miss_returns_none() {
        let dir = tempfile::tempdir().unwrap();
        let repo = TranslationRepo::open(dir.path()).unwrap();
        assert!(repo.cache_get(&key("nope", Lang::En, Lang::Zh, "echo")).unwrap().is_none());
    }

    #[test]
    fn cache_key_distinguishes_provider_and_lang() {
        let dir = tempfile::tempdir().unwrap();
        let mut repo = TranslationRepo::open(dir.path()).unwrap();
        repo.cache_put(&entry("hello", "echo")).unwrap();
        // 同文不同 Provider → Miss
        assert!(repo
            .cache_get(&key("hello", Lang::En, Lang::Zh, "deepl"))
            .unwrap()
            .is_none());
        // 同文同 Provider 不同语言对 → Miss
        assert!(repo
            .cache_get(&key("hello", Lang::En, Lang::En, "echo"))
            .unwrap()
            .is_none());
    }

    #[test]
    fn cache_clear_and_count() {
        let dir = tempfile::tempdir().unwrap();
        let mut repo = TranslationRepo::open(dir.path()).unwrap();
        repo.cache_put(&entry("a", "echo")).unwrap();
        repo.cache_put(&entry("b", "echo")).unwrap();
        assert_eq!(repo.cache_count().unwrap(), 2);
        repo.cache_clear().unwrap();
        assert_eq!(repo.cache_count().unwrap(), 0);
    }

    #[test]
    fn provider_config_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let mut repo = TranslationRepo::open(dir.path()).unwrap();
        // 默认 deepl
        assert_eq!(repo.default_provider().unwrap(), "deepl");
        assert!(repo.provider_key("deepl").unwrap().is_none());
        repo.set_provider_key("deepl", "my-key").unwrap();
        assert_eq!(repo.provider_key("deepl").unwrap().as_deref(), Some("my-key"));
        repo.set_default_provider("echo").unwrap();
        assert_eq!(repo.default_provider().unwrap(), "echo");
        // 覆盖更新
        repo.set_provider_key("deepl", "new-key").unwrap();
        assert_eq!(repo.provider_key("deepl").unwrap().as_deref(), Some("new-key"));
    }

    #[test]
    fn provider_key_setting_uses_namespaced_key() {
        // 杀死 store/translation.rs:38 provider_key_setting 恒 "xyzzy"/"" 两个变异：
        // set/get 走同一函数会自洽逃逸（写错键名仍能读回），必须直查 settings 表
        // 断言键落在 `translate.key.<provider>` 命名空间（docs/04 §5 键约定）
        let dir = tempfile::tempdir().unwrap();
        let mut repo = TranslationRepo::open(dir.path()).unwrap();
        repo.set_provider_key("deepl", "secret").unwrap();
        let v: Option<String> = repo
            .conn
            .query_row(
                "SELECT value FROM settings WHERE key='translate.key.deepl'",
                [],
                |r| r.get(0),
            )
            .optional()
            .unwrap();
        assert_eq!(v.as_deref(), Some("secret"), "键必须为 translate.key.deepl");
        // 变异会把值写到 "xyzzy"/"" 键下 → 表中出现多余行，数量断言兜底
        let total: i64 = repo
            .conn
            .query_row("SELECT COUNT(*) FROM settings", [], |r| r.get(0))
            .unwrap();
        assert_eq!(total, 1, "settings 表应只有 translate.key.deepl 一行");
    }

    #[test]
    fn v2_to_v3_migration_preserves_existing_data() {
        // 构造 user_version=2 的存量库（含书与进度）→ 重开 → 数据完整 + 新表存在 + v3
        let dir = tempfile::tempdir().unwrap();
        let db = dir.path().join("library.db");
        {
            let conn = Connection::open(&db).unwrap();
            conn.execute_batch(
                "PRAGMA user_version=2;
                 CREATE TABLE books (id TEXT PRIMARY KEY, title TEXT NOT NULL, authors TEXT NOT NULL DEFAULT '[]',
                   language TEXT, source_path TEXT NOT NULL, source_hash TEXT NOT NULL UNIQUE, format TEXT NOT NULL,
                   added_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
                 CREATE TABLE book_files (book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE, canonical_path TEXT);
                 CREATE TABLE reading_progress (book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
                   href TEXT NOT NULL, progression REAL NOT NULL, updated_at INTEGER NOT NULL);
                 INSERT INTO books (id,title,authors,source_path,source_hash,format,added_at,updated_at)
                   VALUES ('bk1','存量书','[\"张三\"]','/x.epub','hash1','epub',1,1);
                 INSERT INTO reading_progress (book_id,href,progression,updated_at) VALUES ('bk1','c1.xhtml',0.5,1);",
            )
            .unwrap();
        }
        // 重开（走迁移）
        let store = crate::store::Store::open(dir.path()).unwrap();
        let books = store.list_books().unwrap();
        assert_eq!(books.len(), 1, "存量书不丢");
        assert_eq!(books[0].title, "存量书");
        let p = store.load_progress("bk1").unwrap().expect("进度不丢");
        assert_eq!(p.href, "c1.xhtml");
        assert!((p.progression - 0.5).abs() < 1e-4);
        // 新表可用 + user_version==3
        let mut repo = TranslationRepo::open(dir.path()).unwrap();
        repo.cache_put(&entry("migrated", "echo")).unwrap();
        assert_eq!(repo.cache_count().unwrap(), 1);
        let ver: i64 = repo
            .conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(ver, 3);
        // dicts/ 目录已建（Store::open）
        assert!(dir.path().join("dicts").is_dir());
    }

    #[test]
    fn hit_query_perf_1000_rows_under_budget() {
        // US-14：≥1000 条缓存命中查询 <10ms（CI 宽松上限 ≤100ms）
        let dir = tempfile::tempdir().unwrap();
        let mut repo = TranslationRepo::open(dir.path()).unwrap();
        for i in 0..1200 {
            let k = format!("text{i:04}");
            repo.cache_put(&entry(&k, "echo")).unwrap();
        }
        let target = key("text0500", Lang::En, Lang::Zh, "echo");
        let start = std::time::Instant::now();
        let got = repo.cache_get(&target).unwrap().expect("应有命中");
        let elapsed = start.elapsed();
        eprintln!("[US-14 基准] ≥1000 行命中查询耗时 {:?}", elapsed);
        assert_eq!(got.result.text, "译文:text0500");
        assert!(
            elapsed.as_millis() <= 100,
            "命中查询应 ≤100ms（CI 上限），实测 {:?}",
            elapsed
        );
    }
}
