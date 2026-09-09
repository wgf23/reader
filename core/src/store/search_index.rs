//! 搜索基础设施：`SearchIndexRepo`（第二连接）实现 `SearchIndexRepository`
//! （契约定义于 `crate::types`，ADR REQ-009 D1/D3）。
//!
//! 只负责持久化 `text_bi` 与查询（分词算法在 domain `search`）；两条查询路径：
//! `query_fts`（≥2 字 CJK / ASCII 词，FTS5 短语）与 `query_substring`（单字 CJK LIKE 回退）。

use std::path::Path;

use rusqlite::{params, params_from_iter, Connection};

use crate::error::{Error, Result};
use crate::store::migrate_conn;
use crate::types::{IndexedChapter, SearchIndexRepository, SearchRow, SearchScope};

/// 第二连接（同一 library.db；WAL + busy_timeout + FK ON）
pub struct SearchIndexRepo {
    conn: Connection,
}

impl SearchIndexRepo {
    pub fn open(data_dir: &Path) -> Result<SearchIndexRepo> {
        std::fs::create_dir_all(data_dir).map_err(Error::Io)?;
        let conn = Connection::open(data_dir.join("library.db")).map_err(Error::from)?;
        conn.execute_batch(
            "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; PRAGMA foreign_keys=ON;",
        )
        .map_err(Error::from)?;
        migrate_conn(&conn)?;
        Ok(SearchIndexRepo { conn })
    }
}

/// 组装 scope 过滤子句与参数（返回 SQL 片段 + 参数）。
fn scope_clause(scope: &SearchScope, start_index: usize) -> (String, Vec<rusqlite::types::Value>) {
    use rusqlite::types::Value;
    let mut sql = String::new();
    let mut args: Vec<Value> = Vec::new();
    let mut n = start_index;
    if let Some(book_id) = &scope.book_id {
        sql.push_str(&format!(" AND f.book_id = ?{n}"));
        args.push(Value::Text(book_id.clone()));
        n += 1;
    }
    if !scope.formats.is_empty() {
        let placeholders: Vec<String> = (0..scope.formats.len())
            .map(|i| format!("?{}", n + i))
            .collect();
        sql.push_str(&format!(" AND b.format IN ({})", placeholders.join(",")));
        for f in &scope.formats {
            args.push(Value::Text(f.clone()));
        }
    }
    let _ = n;
    (sql, args)
}

/// 执行查询并映射为 `SearchRow`（`query_fts`/`query_substring` 共用）。
fn run_rows(conn: &Connection, sql: &str, args: Vec<rusqlite::types::Value>) -> Result<Vec<SearchRow>> {
    let mut stmt = conn.prepare(sql).map_err(Error::from)?;
    let rows = stmt
        .query_map(params_from_iter(args), |r| {
            Ok(SearchRow {
                book_id: r.get(0)?,
                book_title: r.get(1)?,
                href: r.get(2)?,
                chapter_title: r.get(3)?,
                text: r.get(4)?,
                score: r.get::<_, Option<f64>>(5)?,
            })
        })
        .map_err(Error::from)?;
    let mut out = Vec::new();
    for row in rows {
        out.push(row.map_err(Error::from)?);
    }
    Ok(out)
}

impl SearchIndexRepository for SearchIndexRepo {
    fn replace_book(&mut self, book_id: &str, chapters: &[IndexedChapter]) -> Result<()> {
        let tx = self.conn.transaction().map_err(Error::from)?;
        tx.execute("DELETE FROM fts_books WHERE book_id = ?1", params![book_id])
            .map_err(Error::from)?;
        for c in chapters {
            tx.execute(
                "INSERT INTO fts_books (book_id, href, chapter, text, text_bi)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                params![book_id, c.href, c.chapter_title, c.text, c.text_bi],
            )
            .map_err(Error::from)?;
        }
        tx.commit().map_err(Error::from)?;
        Ok(())
    }

    fn is_indexed(&self, book_id: &str) -> Result<bool> {
        let exists: i64 = self
            .conn
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM fts_books WHERE book_id = ?1)",
                params![book_id],
                |r| r.get(0),
            )
            .map_err(Error::from)?;
        Ok(exists != 0)
    }

    fn remove_book(&mut self, book_id: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM fts_books WHERE book_id = ?1", params![book_id])
            .map_err(Error::from)?;
        Ok(())
    }

    fn query_fts(
        &self,
        match_expr: &str,
        scope: &SearchScope,
        limit: usize,
    ) -> Result<Vec<SearchRow>> {
        let (extra, args) = scope_clause(scope, 2);
        let sql = format!(
            "SELECT f.book_id, b.title, f.href, f.chapter, f.text, rank
             FROM fts_books f JOIN books b ON b.id = f.book_id
             WHERE fts_books MATCH ?1{extra}
             ORDER BY rank LIMIT ?{}",
            args.len() + 2
        );
        let mut all: Vec<rusqlite::types::Value> =
            vec![rusqlite::types::Value::Text(match_expr.to_string())];
        all.extend(args);
        all.push(rusqlite::types::Value::Integer(limit as i64));
        run_rows(&self.conn, &sql, all)
    }

    fn query_substring(
        &self,
        needle: &str,
        scope: &SearchScope,
        limit: usize,
    ) -> Result<Vec<SearchRow>> {
        let escaped = needle
            .replace('\\', "\\\\")
            .replace('%', "\\%")
            .replace('_', "\\_");
        let pattern = format!("%{escaped}%");
        let (extra, args) = scope_clause(scope, 2);
        let sql = format!(
            "SELECT f.book_id, b.title, f.href, f.chapter, f.text, NULL
             FROM fts_books f JOIN books b ON b.id = f.book_id
             WHERE f.text LIKE ?1 ESCAPE '\\'{extra}
             LIMIT ?{}",
            args.len() + 2
        );
        let mut all: Vec<rusqlite::types::Value> =
            vec![rusqlite::types::Value::Text(pattern)];
        all.extend(args);
        all.push(rusqlite::types::Value::Integer(limit as i64));
        run_rows(&self.conn, &sql, all)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn book(store: &mut crate::store::Store, id: &str, title: &str, format: &str, hash: &str) {
        store
            .insert_book(&crate::store::BookRecord {
                id: id.to_string(),
                title: title.to_string(),
                authors: vec![],
                language: Some("zh".to_string()),
                source_path: "/x".to_string(),
                source_hash: hash.to_string(),
                format: format.to_string(),
                canonical_path: None,
                added_at: 1,
            })
            .unwrap();
    }

    fn chapter(href: &str, title: &str, text: &str) -> IndexedChapter {
        IndexedChapter {
            href: href.to_string(),
            chapter_title: title.to_string(),
            text: text.to_string(),
            text_bi: crate::search::bigram_index_text(text),
        }
    }

    fn setup() -> (tempfile::TempDir, SearchIndexRepo) {
        let dir = tempfile::tempdir().unwrap();
        let mut store = crate::store::Store::open(dir.path()).unwrap();
        book(&mut store, "b1", "看不见的城市", "epub", "h1");
        book(&mut store, "b2", "马可瓦尔多", "mobi", "h2");
        drop(store);
        let repo = SearchIndexRepo::open(dir.path()).unwrap();
        (dir, repo)
    }

    #[test]
    fn replace_book_is_idempotent_and_is_indexed() {
        let (_dir, mut repo) = setup();
        let ch = vec![chapter("chapter_0001.xhtml", "城市与记忆", "看不见的城市，卡尔维诺写道：城市是记忆的。")];
        repo.replace_book("b1", &ch).unwrap();
        assert!(repo.is_indexed("b1").unwrap());
        repo.replace_book("b1", &ch).unwrap(); // 重复索引不翻倍
        let n: i64 = repo
            .conn
            .query_row("SELECT COUNT(*) FROM fts_books WHERE book_id='b1'", [], |r| r.get(0))
            .unwrap();
        assert_eq!(n, 1);
        assert!(!repo.is_indexed("nope").unwrap());
    }

    #[test]
    fn query_fts_hits_two_char_cjk_and_scope() {
        let (_dir, mut repo) = setup();
        repo.replace_book("b1", &[chapter("c1.xhtml", "城市与记忆", "看不见的城市，卡尔维诺写道：城市是记忆的。")])
            .unwrap();
        repo.replace_book("b2", &[chapter("c1.xhtml", "城市与符号", "马可瓦尔多里也有城市。")])
            .unwrap();

        let expr = crate::search::build_match_expr("城市").unwrap();
        let all = repo.query_fts(&expr, &SearchScope::default(), 10).unwrap();
        assert_eq!(all.len(), 2, "全部书籍应命中两本");
        let one = repo
            .query_fts(
                &expr,
                &SearchScope {
                    book_id: Some("b1".to_string()),
                    formats: vec![],
                },
                10,
            )
            .unwrap();
        assert_eq!(one.len(), 1);
        assert_eq!(one[0].book_id, "b1");
        // 格式过滤：b1 是 epub，b2 是 mobi
        let epub = repo
            .query_fts(
                &expr,
                &SearchScope {
                    book_id: None,
                    formats: vec!["epub".to_string()],
                },
                10,
            )
            .unwrap();
        assert_eq!(epub.len(), 1);
        assert_eq!(epub[0].book_title, "看不见的城市");
    }

    #[test]
    fn query_substring_single_char_and_special_chars_safe() {
        let (_dir, mut repo) = setup();
        repo.replace_book("b1", &[chapter("c1.xhtml", "城市", "看不见的城市，卡尔维诺写道。")])
            .unwrap();
        let hits = repo.query_substring("城", &SearchScope::default(), 10).unwrap();
        assert_eq!(hits.len(), 1);
        // 特殊字符（LIKE 元字符）被转义，不抛异常、不误匹配
        assert!(repo.query_substring("%", &SearchScope::default(), 10).unwrap().is_empty());
        assert!(repo.query_substring("_", &SearchScope::default(), 10).unwrap().is_empty());
    }

    #[test]
    fn remove_book_clears_rows() {
        let (_dir, mut repo) = setup();
        repo.replace_book("b1", &[chapter("c1.xhtml", "城市", "看不见的城市。")])
            .unwrap();
        repo.remove_book("b1").unwrap();
        assert!(!repo.is_indexed("b1").unwrap());
    }

    #[test]
    fn store_remove_book_clears_fts() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = crate::store::Store::open(dir.path()).unwrap();
        book(&mut store, "b1", "书", "epub", "h1");
        {
            let mut repo = SearchIndexRepo::open(dir.path()).unwrap();
            repo.replace_book("b1", &[chapter("c1.xhtml", "城市", "看不见的城市。")])
                .unwrap();
        }
        store.remove_book("b1").unwrap();
        let repo = SearchIndexRepo::open(dir.path()).unwrap();
        assert!(!repo.is_indexed("b1").unwrap(), "删书事务内应显式清 fts_books");
    }
}
