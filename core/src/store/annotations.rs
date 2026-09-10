//! 笔记基础设施：`AnnotationRepo`（第二连接）实现 `AnnotationRepository`
//! （契约定义于 `crate::types`，ADR REQ-009 D3）。
//!
//! 分层：infrastructure 层，只依赖 `crate::types`/`crate::error`/rusqlite；
//! 第二连接显式 `PRAGMA foreign_keys=ON`（级联删）+ `busy_timeout=5000` + 共享 `migrate_conn`。

use std::path::Path;

use rusqlite::{params, Connection, OptionalExtension};

use crate::error::{Error, Result};
use crate::store::migrate_conn;
use crate::types::{Annotation, AnnotationRepository, Locator, NoteKind, NotePatch};

/// 第二连接（同一 library.db；WAL + busy_timeout + FK ON）
pub struct AnnotationRepo {
    conn: Connection,
}

impl AnnotationRepo {
    pub fn open(data_dir: &Path) -> Result<AnnotationRepo> {
        std::fs::create_dir_all(data_dir).map_err(Error::Io)?;
        let conn = Connection::open(data_dir.join("library.db")).map_err(Error::from)?;
        conn.execute_batch(
            "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; PRAGMA foreign_keys=ON;",
        )
        .map_err(Error::from)?;
        migrate_conn(&conn)?;
        Ok(AnnotationRepo { conn })
    }
}

/// 行 → `Annotation`（`locator_json` 反序列化）。
fn row_to_annotation(row: &rusqlite::Row<'_>) -> rusqlite::Result<Annotation> {
    let locator_json: String = row.get(4)?;
    let kind_str: String = row.get(2)?;
    let locator: Locator = serde_json::from_str(&locator_json).unwrap_or_else(|_| Locator {
        book_id: row.get::<_, String>(1).unwrap_or_default(),
        href: String::new(),
        progression: 0.0,
        total_progression: 0.0,
        text: None,
        cfi: None,
        page: None,
        rect: None,
    });
    Ok(Annotation {
        id: row.get(0)?,
        book_id: row.get(1)?,
        kind: NoteKind::parse(&kind_str).unwrap_or(NoteKind::Highlight),
        color: row.get(3)?,
        locator,
        snippet: row.get(5)?,
        note_text: row.get(6)?,
        created_at: row.get(7)?,
        updated_at: row.get(8)?,
        sync_status: row.get(9)?,
    })
}

const SELECT_COLS: &str = "id, book_id, kind, color, locator_json, snippet, note_text, \
                           created_at, updated_at, sync_status";

impl AnnotationRepository for AnnotationRepo {
    fn insert(&mut self, a: &Annotation) -> Result<()> {
        let locator_json = serde_json::to_string(&a.locator)
            .map_err(|e| Error::Other(format!("Locator 序列化失败: {e}")))?;
        self.conn
            .execute(
                "INSERT OR REPLACE INTO annotations
                 (id, book_id, kind, color, locator_json, snippet, note_text, created_at, updated_at, sync_status)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)",
                params![
                    a.id,
                    a.book_id,
                    a.kind.as_str(),
                    a.color,
                    locator_json,
                    a.snippet,
                    a.note_text,
                    a.created_at,
                    a.updated_at,
                    a.sync_status
                ],
            )
            .map_err(Error::from)?;
        Ok(())
    }

    fn update(&mut self, id: &str, patch: &NotePatch, now: i64) -> Result<()> {
        let mut a = self
            .get(id)?
            .ok_or_else(|| Error::NotFound(format!("笔记不存在: {id}")))?;
        if let Some(t) = &patch.note_text {
            a.note_text = Some(t.clone());
        }
        if let Some(c) = &patch.color {
            a.color = Some(c.clone());
        }
        if let Some(k) = patch.kind {
            a.kind = k;
        }
        a.updated_at = now;
        self.insert(&a)
    }

    fn delete(&mut self, id: &str) -> Result<()> {
        // 幂等：不存在也返回 Ok（US-12）。
        self.conn
            .execute("DELETE FROM annotations WHERE id = ?1", params![id])
            .map_err(Error::from)?;
        Ok(())
    }

    fn delete_many(&mut self, ids: &[String]) -> Result<usize> {
        let tx = self.conn.transaction().map_err(Error::from)?;
        let mut n = 0usize;
        for id in ids {
            n += tx
                .execute("DELETE FROM annotations WHERE id = ?1", params![id])
                .map_err(Error::from)?;
        }
        tx.commit().map_err(Error::from)?;
        Ok(n)
    }

    fn delete_all(&mut self, book_id: &str, kinds: Option<&[NoteKind]>) -> Result<usize> {
        match kinds {
            None => self
                .conn
                .execute("DELETE FROM annotations WHERE book_id = ?1", params![book_id])
                .map_err(Error::from),
            Some(ks) => {
                let tx = self.conn.transaction().map_err(Error::from)?;
                let mut n = 0usize;
                for k in ks {
                    n += tx
                        .execute(
                            "DELETE FROM annotations WHERE book_id = ?1 AND kind = ?2",
                            params![book_id, k.as_str()],
                        )
                        .map_err(Error::from)?;
                }
                tx.commit().map_err(Error::from)?;
                Ok(n)
            }
        }
    }

    fn list(&self, book_id: &str) -> Result<Vec<Annotation>> {
        let mut stmt = self
            .conn
            .prepare(&format!(
                "SELECT {SELECT_COLS} FROM annotations WHERE book_id = ?1 ORDER BY updated_at DESC, id DESC"
            ))
            .map_err(Error::from)?;
        let rows = stmt
            .query_map(params![book_id], row_to_annotation)
            .map_err(Error::from)?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r.map_err(Error::from)?);
        }
        Ok(out)
    }

    fn get(&self, id: &str) -> Result<Option<Annotation>> {
        self.conn
            .query_row(
                &format!("SELECT {SELECT_COLS} FROM annotations WHERE id = ?1"),
                params![id],
                row_to_annotation,
            )
            .optional()
            .map_err(Error::from)
    }

    fn find_bookmark(
        &self,
        book_id: &str,
        href: &str,
        progression: f32,
    ) -> Result<Option<Annotation>> {
        // href/progression 在 locator_json 内，无法直接 SQL 过滤 → 取该书书签在 Rust 侧匹配
        // （单书书签量小；`round(progression,3)` 语义与 ADR D9 一致）。
        let all = self.list(book_id)?;
        let target = (progression * 1000.0).round() / 1000.0;
        Ok(all.into_iter().find(|a| {
            a.kind == NoteKind::Bookmark
                && a.locator.href == href
                && ((a.locator.progression * 1000.0).round() / 1000.0 - target).abs() < 1e-6
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{BookId, TextAnchor};

    fn locator(book: &str, href: &str, p: f32) -> Locator {
        Locator {
            book_id: BookId::from(book),
            href: href.to_string(),
            progression: p,
            total_progression: p,
            text: Some(TextAnchor {
                snippet: "片段".to_string(),
                start: 1,
                end: 3,
            }),
            cfi: None,
            page: None,
            rect: None,
        }
    }

    fn sample(id: &str, book: &str, href: &str, kind: NoteKind, updated: i64) -> Annotation {
        Annotation {
            id: id.to_string(),
            book_id: book.to_string(),
            kind,
            color: Some("#FBC02D".to_string()),
            locator: locator(book, href, 0.25),
            snippet: Some("原文片段".to_string()),
            note_text: Some("批注".to_string()),
            created_at: 1,
            updated_at: updated,
            sync_status: "local".to_string(),
        }
    }

    fn repo_with_book(dir: &Path) -> (AnnotationRepo, Connection) {
        // 建库并插入一本书（annotations 有 FK）
        let mut store = crate::store::Store::open(dir).unwrap();
        store
            .insert_book(&crate::store::BookRecord {
                id: "b1".to_string(),
                title: "书".to_string(),
                authors: vec![],
                language: None,
                source_path: "/x".to_string(),
                source_hash: "h1".to_string(),
                format: "epub".to_string(),
                canonical_path: None,
                added_at: 1,
            })
            .unwrap();
        drop(store);
        let repo = AnnotationRepo::open(dir).unwrap();
        let conn = Connection::open(dir.join("library.db")).unwrap();
        (repo, conn)
    }

    #[test]
    fn crud_roundtrip_and_updated_at() {
        let dir = tempfile::tempdir().unwrap();
        let (mut repo, _conn) = repo_with_book(dir.path());
        let a = sample("a1", "b1", "chapter_0001.xhtml", NoteKind::Highlight, 100);
        repo.insert(&a).unwrap();
        let got = repo.get("a1").unwrap().expect("应有");
        assert_eq!(got, a);
        assert_eq!(got.locator.text.as_ref().unwrap().start, 1);

        let patch = NotePatch {
            note_text: Some("改".to_string()),
            color: Some("#1A73E8".to_string()),
            kind: Some(NoteKind::Note),
        };
        repo.update("a1", &patch, 200).unwrap();
        let got = repo.get("a1").unwrap().unwrap();
        assert_eq!(got.note_text.as_deref(), Some("改"));
        assert_eq!(got.color.as_deref(), Some("#1A73E8"));
        assert_eq!(got.kind, NoteKind::Note);
        assert_eq!(got.updated_at, 200);
    }

    #[test]
    fn delete_is_idempotent_and_delete_many() {
        let dir = tempfile::tempdir().unwrap();
        let (mut repo, _conn) = repo_with_book(dir.path());
        repo.insert(&sample("a1", "b1", "h1", NoteKind::Highlight, 1)).unwrap();
        repo.insert(&sample("a2", "b1", "h1", NoteKind::Note, 2)).unwrap();
        assert_eq!(repo.delete_many(&["a1".to_string(), "a2".to_string()]).unwrap(), 2);
        assert!(repo.list("b1").unwrap().is_empty());
        repo.delete("missing").unwrap(); // 幂等不崩溃
    }

    #[test]
    fn list_order_by_updated_at_desc() {
        let dir = tempfile::tempdir().unwrap();
        let (mut repo, _conn) = repo_with_book(dir.path());
        repo.insert(&sample("old", "b1", "h1", NoteKind::Highlight, 10)).unwrap();
        repo.insert(&sample("new", "b1", "h1", NoteKind::Highlight, 20)).unwrap();
        let list = repo.list("b1").unwrap();
        assert_eq!(list[0].id, "new");
        assert_eq!(list[1].id, "old");
    }

    #[test]
    fn find_bookmark_rounds_progression() {
        let dir = tempfile::tempdir().unwrap();
        let (mut repo, _conn) = repo_with_book(dir.path());
        let mut a = sample("bm", "b1", "chapter_0002.xhtml", NoteKind::Bookmark, 5);
        a.locator.progression = 0.123456;
        repo.insert(&a).unwrap();
        assert!(repo
            .find_bookmark("b1", "chapter_0002.xhtml", 0.12349)
            .unwrap()
            .is_some());
        assert!(repo
            .find_bookmark("b1", "chapter_0001.xhtml", 0.123)
            .unwrap()
            .is_none());
        // 非 bookmark kind 不命中
        repo.insert(&sample("hl", "b1", "chapter_0002.xhtml", NoteKind::Highlight, 6))
            .unwrap();
        assert!(repo
            .find_bookmark("b1", "chapter_0002.xhtml", 0.25)
            .unwrap()
            .is_none());
    }

    #[test]
    fn delete_all_and_fk_cascade() {
        let dir = tempfile::tempdir().unwrap();
        let (mut repo, _conn) = repo_with_book(dir.path());
        repo.insert(&sample("a1", "b1", "h1", NoteKind::Highlight, 1)).unwrap();
        repo.insert(&sample("a2", "b1", "h2", NoteKind::Bookmark, 2)).unwrap();
        assert_eq!(repo.delete_all("b1", None).unwrap(), 2);
        assert!(repo.list("b1").unwrap().is_empty());

        repo.insert(&sample("a3", "b1", "h1", NoteKind::Highlight, 3)).unwrap();
        // 删书（主连接 FK 级联）→ 笔记清空
        let mut store = crate::store::Store::open(dir.path()).unwrap();
        store.remove_book("b1").unwrap();
        assert!(repo.list("b1").unwrap().is_empty(), "删书应级联清笔记");
    }

    #[test]
    fn delete_existing_row_is_removed() {
        let dir = tempfile::tempdir().unwrap();
        let (mut repo, _conn) = repo_with_book(dir.path());
        repo.insert(&sample("a1", "b1", "h1", NoteKind::Highlight, 1)).unwrap();
        assert!(repo.get("a1").unwrap().is_some());
        repo.delete("a1").unwrap();
        assert!(repo.get("a1").unwrap().is_none(), "delete 应真正删除已存在行");
        assert!(repo.list("b1").unwrap().is_empty());
    }

    #[test]
    fn delete_all_with_kind_filter_returns_actual_count() {
        let dir = tempfile::tempdir().unwrap();
        let (mut repo, _conn) = repo_with_book(dir.path());
        repo.insert(&sample("a1", "b1", "h1", NoteKind::Highlight, 1)).unwrap();
        repo.insert(&sample("a2", "b1", "h1", NoteKind::Underline, 2)).unwrap();
        repo.insert(&sample("a3", "b1", "h1", NoteKind::Note, 3)).unwrap();
        assert_eq!(
            repo.delete_all("b1", Some(&[NoteKind::Highlight])).unwrap(),
            1
        );
        assert_eq!(repo.list("b1").unwrap().len(), 2);
        assert_eq!(
            repo.delete_all("b1", Some(&[NoteKind::Note, NoteKind::Underline]))
                .unwrap(),
            2
        );
        assert!(repo.list("b1").unwrap().is_empty());
    }
}
