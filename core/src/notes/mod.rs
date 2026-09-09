//! 笔记：高亮 / 划线 / 批注 / 书签 + 导出（Markdown / JSON）。
//!
//! 设计：docs/04-module-design.md §4–§8（annotations 表、领域规则）；ADR REQ-009 D8/D9。
//! 分层：domain 层，只依赖 `crate::types`/`crate::error`（经 `AnnotationRepository` trait 注入，
//! 禁 `crate::store`）。锚定：本模块只消费 `Locator`，不关心具体格式。

use std::collections::HashMap;
use std::path::Path;

use sha2::{Digest, Sha256};

use crate::error::{Error, Result};
use crate::types::{
    Annotation, AnnotationRepository, ExportFormat, ExportSummary, Locator, NoteGroup, NoteKind,
    NotePatch,
};

pub struct AnnotationService {
    repo: Box<dyn AnnotationRepository + Send>,
}

impl AnnotationService {
    pub fn new(repo: Box<dyn AnnotationRepository + Send>) -> Self {
        AnnotationService { repo }
    }

    /// 创建笔记（note 类空文本不落库；颜色空串视为 None）。
    pub fn create(
        &mut self,
        book_id: &str,
        locator: Locator,
        kind: NoteKind,
        color: Option<String>,
        note_text: Option<String>,
    ) -> Result<Annotation> {
        let note_text = note_text
            .map(|t| t.trim().to_string())
            .filter(|t| !t.is_empty());
        if kind == NoteKind::Note && note_text.is_none() {
            return Err(Error::Other("批注内容不能为空".to_string()));
        }
        let color = color.filter(|c| !c.trim().is_empty());
        let snippet = locator.text.as_ref().map(|t| t.snippet.clone());
        let now = now_unix();
        let a = Annotation {
            id: new_note_id(book_id, kind),
            book_id: book_id.to_string(),
            kind,
            color,
            locator,
            snippet,
            note_text,
            created_at: now,
            updated_at: now,
            sync_status: "local".to_string(),
        };
        self.repo.insert(&a)?;
        Ok(a)
    }

    pub fn update(&mut self, id: &str, patch: &NotePatch) -> Result<()> {
        self.repo.update(id, patch, now_unix())
    }

    pub fn delete(&mut self, id: &str) -> Result<()> {
        self.repo.delete(id)
    }

    pub fn delete_many(&mut self, ids: &[String]) -> Result<usize> {
        self.repo.delete_many(ids)
    }

    /// 清空该书全部笔记（含书签）。
    pub fn delete_all(&mut self, book_id: &str) -> Result<usize> {
        self.repo.delete_all(book_id, None)
    }

    /// 按章节分组（`updated_at` 倒序；组按最近更新笔记首次出现排序，稳定）。
    pub fn list(
        &self,
        book_id: &str,
        chapter_titles: &HashMap<String, String>,
    ) -> Result<Vec<NoteGroup>> {
        let mut notes = self.repo.list(book_id)?;
        notes.sort_by(|a, b| {
            b.updated_at
                .cmp(&a.updated_at)
                .then_with(|| b.id.cmp(&a.id))
        });
        let mut groups: Vec<NoteGroup> = Vec::new();
        for n in notes {
            let href = n.locator.href.clone();
            if let Some(g) = groups.iter_mut().find(|g| g.href == href) {
                g.notes.push(n);
            } else {
                let title = chapter_titles
                    .get(&href)
                    .cloned()
                    .unwrap_or_else(|| href.clone());
                groups.push(NoteGroup {
                    chapter_title: title,
                    href,
                    notes: vec![n],
                });
            }
        }
        Ok(groups)
    }

    pub fn resolve(&self, id: &str) -> Result<Locator> {
        self.repo
            .get(id)?
            .map(|a| a.locator)
            .ok_or_else(|| Error::NotFound(format!("笔记不存在: {id}")))
    }

    /// 导出 Markdown / JSON；空笔记 → `Err("暂无笔记")`（不建文件，US-17）。
    pub fn export(
        &self,
        book_title: &str,
        groups: &[NoteGroup],
        fmt: ExportFormat,
        out: &Path,
    ) -> Result<ExportSummary> {
        let note_count: u32 = groups.iter().map(|g| g.notes.len() as u32).sum();
        if note_count == 0 {
            return Err(Error::Other("暂无笔记".to_string()));
        }
        let content = match fmt {
            ExportFormat::Markdown => to_markdown(book_title, groups),
            ExportFormat::Json => to_json(book_title, groups)?,
        };
        std::fs::write(out, content).map_err(Error::Io)?;
        Ok(ExportSummary {
            path: out.display().to_string(),
            note_count,
            format: fmt,
        })
    }

    /// 幂等切换书签：`(book_id, href, round(progression,3))` 命中则删，否则建。
    pub fn toggle_bookmark(
        &mut self,
        book_id: &str,
        mut locator: Locator,
        snippet: Option<String>,
    ) -> Result<(bool, Option<String>)> {
        if locator.text.is_none() {
            if let Some(s) = snippet.filter(|s| !s.trim().is_empty()) {
                let s = s.trim().to_string();
                let end = s.chars().map(|c| c.len_utf16() as u32).sum();
                locator.text = Some(crate::types::TextAnchor {
                    snippet: s,
                    start: 0,
                    end,
                });
            }
        }
        if let Some(existing) = self
            .repo
            .find_bookmark(book_id, &locator.href, locator.progression)?
        {
            self.repo.delete(&existing.id)?;
            return Ok((false, None));
        }
        let a = self.create(book_id, locator, NoteKind::Bookmark, None, None)?;
        Ok((true, Some(a.id)))
    }
}

fn now_unix() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// 笔记 id：`an_` + SHA-256(book_id + kind + 纳秒 + 进程内计数) 前 12 字节（零新依赖）。
fn new_note_id(book_id: &str, kind: NoteKind) -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let n = COUNTER.fetch_add(1, Ordering::Relaxed);
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let mut hasher = Sha256::new();
    hasher.update(book_id.as_bytes());
    hasher.update(kind.as_str().as_bytes());
    hasher.update(nanos.to_le_bytes());
    hasher.update(n.to_le_bytes());
    let digest = hasher.finalize();
    let mut s = String::from("an_");
    for b in &digest[..12] {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

fn escape_md(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\\' | '`' | '*' | '_' | '[' | ']' | '<' | '>' | '#' | '|' => {
                out.push('\\');
                out.push(c);
            }
            '\n' | '\r' => out.push_str("<br>"),
            _ => out.push(c),
        }
    }
    out
}

fn kind_label(kind: NoteKind) -> &'static str {
    match kind {
        NoteKind::Highlight => "高亮",
        NoteKind::Underline => "划线",
        NoteKind::Note => "批注",
        NoteKind::Bookmark => "书签",
    }
}

fn to_markdown(book_title: &str, groups: &[NoteGroup]) -> String {
    let mut out = String::new();
    out.push_str(&format!("# {} · 笔记\n\n", escape_md(book_title)));
    for g in groups {
        out.push_str(&format!("## {}\n\n", escape_md(&g.chapter_title)));
        for n in &g.notes {
            let color = n.color.as_deref().unwrap_or("");
            out.push_str(&format!(
                "- **[{}]{}** {}\n",
                kind_label(n.kind),
                if color.is_empty() {
                    String::new()
                } else {
                    format!(" {color}")
                },
                escape_md(n.snippet.as_deref().unwrap_or(""))
            ));
            if let Some(t) = n.note_text.as_deref().filter(|t| !t.is_empty()) {
                out.push_str(&format!("  > {}\n", escape_md(t)));
            }
            out.push_str(&format!(
                "  - 位置: {} · {:.4}\n",
                n.locator.href, n.locator.progression
            ));
            out.push_str(&format!("  - 时间: {}\n", format_unix(n.updated_at)));
        }
        out.push('\n');
    }
    out
}

fn to_json(book_title: &str, groups: &[NoteGroup]) -> Result<String> {
    let groups_json: Vec<serde_json::Value> = groups
        .iter()
        .map(|g| {
            let notes: Vec<serde_json::Value> = g
                .notes
                .iter()
                .map(|n| {
                    serde_json::json!({
                        "id": n.id,
                        "kind": n.kind.as_str(),
                        "color": n.color,
                        "href": n.locator.href,
                        "progression": n.locator.progression,
                        "start": n.locator.text.as_ref().map(|t| t.start),
                        "end": n.locator.text.as_ref().map(|t| t.end),
                        "snippet": n.snippet,
                        "note_text": n.note_text,
                        "created_at": n.created_at,
                        "updated_at": n.updated_at,
                        "sync_status": n.sync_status,
                    })
                })
                .collect();
            serde_json::json!({
                "chapter_title": g.chapter_title,
                "href": g.href,
                "notes": notes,
            })
        })
        .collect();
    let root = serde_json::json!({
        "book_title": book_title,
        "exported_at": now_unix(),
        "groups": groups_json,
    });
    serde_json::to_string_pretty(&root)
        .map_err(|e| Error::Other(format!("导出 JSON 序列化失败: {e}")))
}

/// unix 秒 → `YYYY-MM-DD HH:MM:SS`（UTC；零新依赖）。
fn format_unix(secs: i64) -> String {
    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400);
    let (y, m, d) = civil_from_days(days);
    let hh = rem / 3600;
    let mm = (rem % 3600) / 60;
    let ss = rem % 60;
    format!("{y:04}-{m:02}-{d:02} {hh:02}:{mm:02}:{ss:02}")
}

fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{TextAnchor, TextRange};
    use std::sync::{Arc, Mutex};

    /// 内存仓储（domain 单测用；避免依赖 store）。
    #[derive(Default)]
    struct MemRepo {
        rows: Vec<Annotation>,
    }

    impl AnnotationRepository for MemRepo {
        fn insert(&mut self, a: &Annotation) -> Result<()> {
            self.rows.retain(|r| r.id != a.id);
            self.rows.push(a.clone());
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
            self.rows.retain(|r| r.id != id);
            Ok(())
        }
        fn delete_many(&mut self, ids: &[String]) -> Result<usize> {
            let before = self.rows.len();
            self.rows.retain(|r| !ids.contains(&r.id));
            Ok(before - self.rows.len())
        }
        fn delete_all(&mut self, book_id: &str, kinds: Option<&[NoteKind]>) -> Result<usize> {
            let before = self.rows.len();
            self.rows.retain(|r| {
                r.book_id != book_id || kinds.map(|k| !k.contains(&r.kind)).unwrap_or(false)
            });
            Ok(before - self.rows.len())
        }
        fn list(&self, book_id: &str) -> Result<Vec<Annotation>> {
            Ok(self
                .rows
                .iter()
                .filter(|r| r.book_id == book_id)
                .cloned()
                .collect())
        }
        fn get(&self, id: &str) -> Result<Option<Annotation>> {
            Ok(self.rows.iter().find(|r| r.id == id).cloned())
        }
        fn find_bookmark(
            &self,
            book_id: &str,
            href: &str,
            progression: f32,
        ) -> Result<Option<Annotation>> {
            let target = (progression * 1000.0).round() / 1000.0;
            Ok(self.rows.iter().find(|r| {
                r.book_id == book_id
                    && r.kind == NoteKind::Bookmark
                    && r.locator.href == href
                    && ((r.locator.progression * 1000.0).round() / 1000.0 - target).abs() < 1e-6
            }).cloned())
        }
    }

    fn locator(href: &str, p: f32, snippet: &str) -> Locator {
        Locator {
            book_id: "b1".to_string(),
            href: href.to_string(),
            progression: p,
            total_progression: p,
            text: Some(TextAnchor {
                snippet: snippet.to_string(),
                start: 0,
                end: snippet.chars().count() as u32,
            }),
            cfi: None,
            page: None,
            rect: None,
        }
    }

    fn service() -> (AnnotationService, Arc<Mutex<MemRepo>>) {
        let repo = Arc::new(Mutex::new(MemRepo::default()));
        (AnnotationService::new(Box::new(SharedRepo(repo.clone()))), repo)
    }

    /// 共享句柄（测试断言用）
    struct SharedRepo(Arc<Mutex<MemRepo>>);
    impl AnnotationRepository for SharedRepo {
        fn insert(&mut self, a: &Annotation) -> Result<()> {
            self.0.lock().unwrap().insert(a)
        }
        fn update(&mut self, id: &str, patch: &NotePatch, now: i64) -> Result<()> {
            self.0.lock().unwrap().update(id, patch, now)
        }
        fn delete(&mut self, id: &str) -> Result<()> {
            self.0.lock().unwrap().delete(id)
        }
        fn delete_many(&mut self, ids: &[String]) -> Result<usize> {
            self.0.lock().unwrap().delete_many(ids)
        }
        fn delete_all(&mut self, book_id: &str, kinds: Option<&[NoteKind]>) -> Result<usize> {
            self.0.lock().unwrap().delete_all(book_id, kinds)
        }
        fn list(&self, book_id: &str) -> Result<Vec<Annotation>> {
            self.0.lock().unwrap().list(book_id)
        }
        fn get(&self, id: &str) -> Result<Option<Annotation>> {
            self.0.lock().unwrap().get(id)
        }
        fn find_bookmark(
            &self,
            book_id: &str,
            href: &str,
            progression: f32,
        ) -> Result<Option<Annotation>> {
            self.0.lock().unwrap().find_bookmark(book_id, href, progression)
        }
    }

    #[test]
    fn create_highlight_and_underline_and_note() {
        let (mut svc, _repo) = service();
        let h = svc
            .create(
                "b1",
                locator("c1.xhtml", 0.1, "原文"),
                NoteKind::Highlight,
                Some("#FBC02D".to_string()),
                None,
            )
            .unwrap();
        assert_eq!(h.kind, NoteKind::Highlight);
        assert_eq!(h.snippet.as_deref(), Some("原文"));
        let u = svc
            .create("b1", locator("c1.xhtml", 0.2, "划线"), NoteKind::Underline, Some("#1A73E8".to_string()), None)
            .unwrap();
        assert_eq!(u.kind, NoteKind::Underline);
        let n = svc
            .create("b1", locator("c1.xhtml", 0.3, "批注"), NoteKind::Note, None, Some(" 想法 ".to_string()))
            .unwrap();
        assert_eq!(n.note_text.as_deref(), Some("想法"), "应 trim");
    }

    #[test]
    fn empty_note_text_is_rejected() {
        let (mut svc, _repo) = service();
        assert!(svc
            .create("b1", locator("c1.xhtml", 0.1, "x"), NoteKind::Note, None, Some("   ".to_string()))
            .is_err());
        assert!(svc
            .create("b1", locator("c1.xhtml", 0.1, "x"), NoteKind::Note, None, None)
            .is_err());
    }

    #[test]
    fn update_and_delete_roundtrip() {
        let (mut svc, repo) = service();
        let h = svc
            .create("b1", locator("c1.xhtml", 0.1, "x"), NoteKind::Highlight, Some("#FBC02D".to_string()), None)
            .unwrap();
        let before = repo.lock().unwrap().get(&h.id).unwrap().unwrap().updated_at;
        std::thread::sleep(std::time::Duration::from_millis(1100));
        svc.update(
            &h.id,
            &NotePatch {
                color: Some("#43A047".to_string()),
                ..Default::default()
            },
        )
        .unwrap();
        let after = repo.lock().unwrap().get(&h.id).unwrap().unwrap();
        assert_eq!(after.color.as_deref(), Some("#43A047"));
        assert!(after.updated_at >= before);
        svc.delete(&h.id).unwrap();
        assert!(repo.lock().unwrap().get(&h.id).unwrap().is_none());
    }

    #[test]
    fn list_groups_by_chapter_stable_order() {
        let (mut svc, _repo) = service();
        let mut titles = HashMap::new();
        titles.insert("c1.xhtml".to_string(), "第一章".to_string());
        titles.insert("c2.xhtml".to_string(), "第二章".to_string());
        svc.create("b1", locator("c1.xhtml", 0.1, "a"), NoteKind::Highlight, Some("#FBC02D".to_string()), None).unwrap();
        svc.create("b2", locator("c1.xhtml", 0.1, "b"), NoteKind::Highlight, Some("#FBC02D".to_string()), None).unwrap();
        svc.create("b1", locator("c2.xhtml", 0.1, "c"), NoteKind::Highlight, Some("#1A73E8".to_string()), None).unwrap();
        svc.create("b1", locator("c1.xhtml", 0.2, "d"), NoteKind::Highlight, Some("#1A73E8".to_string()), None).unwrap();
        svc.create("b1", locator("c9.xhtml", 0.1, "z"), NoteKind::Highlight, Some("#FBC02D".to_string()), None).unwrap();
        let groups = svc.list("b1", &titles).unwrap();
        assert_eq!(groups.len(), 3, "c1/c2/未知 href 各一组");
        // 每组内 updated_at 倒序（稳定）
        for g in &groups {
            for w in g.notes.windows(2) {
                assert!(w[0].updated_at >= w[1].updated_at, "组内应按 updated_at 倒序");
            }
        }
        // 分组正确：c1 组 2 条、c2 组 1 条、未知 href 回退为 href 本身
        let c1 = groups.iter().find(|g| g.href == "c1.xhtml").unwrap();
        assert_eq!(c1.chapter_title, "第一章");
        assert_eq!(c1.notes.len(), 2);
        let c2 = groups.iter().find(|g| g.href == "c2.xhtml").unwrap();
        assert_eq!(c2.chapter_title, "第二章");
        assert_eq!(c2.notes.len(), 1);
        assert!(groups.iter().any(|g| g.chapter_title == "c9.xhtml"));
        // 稳定性：两次调用结果一致
        assert_eq!(groups, svc.list("b1", &titles).unwrap());
    }

    #[test]
    fn toggle_bookmark_idempotent() {
        let (mut svc, _repo) = service();
        let (on, id) = svc
            .toggle_bookmark("b1", locator("c1.xhtml", 0.5, "位置"), Some("位置".to_string()))
            .unwrap();
        assert!(on);
        assert!(id.is_some());
        let (off, id2) = svc
            .toggle_bookmark("b1", locator("c1.xhtml", 0.5, "位置"), Some("位置".to_string()))
            .unwrap();
        assert!(!off);
        assert!(id2.is_none());
    }

    #[test]
    fn export_markdown_and_json_fields_and_escaping() {
        let (mut svc, _repo) = service();
        svc.create("b1", locator("c1.xhtml", 0.1, "普通"), NoteKind::Highlight, Some("#FBC02D".to_string()), None).unwrap();
        svc.create("b1", locator("c1.xhtml", 0.2, "*特殊_[字符]"), NoteKind::Note, None, Some("批注\n换行".to_string())).unwrap();
        let groups = svc.list("b1", &HashMap::new()).unwrap();
        let dir = tempfile::tempdir().unwrap();

        let md_path = dir.path().join("n.md");
        let sum = svc.export("测试书", &groups, ExportFormat::Markdown, &md_path).unwrap();
        assert_eq!(sum.note_count, 2);
        let md = std::fs::read_to_string(&md_path).unwrap();
        assert!(md.contains("# 测试书"));
        assert!(md.contains("高亮"));
        assert!(md.contains("批注"));
        assert!(md.contains("\\*特殊\\_\\[字符\\]"));
        assert!(md.contains("<br>"));

        let json_path = dir.path().join("n.json");
        svc.export("测试书", &groups, ExportFormat::Json, &json_path).unwrap();
        let raw = std::fs::read_to_string(&json_path).unwrap();
        let v: serde_json::Value = serde_json::from_str(&raw).unwrap();
        assert_eq!(v["book_title"], "测试书");
        assert_eq!(v["groups"][0]["notes"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn export_empty_notes_errors_without_file() {
        let (svc, _repo) = service();
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("empty.md");
        let err = svc
            .export("测试书", &[], ExportFormat::Markdown, &path)
            .unwrap_err();
        assert!(err.to_string().contains("暂无笔记"));
        assert!(!path.exists(), "空笔记不应建文件");
    }

    #[test]
    fn format_unix_known_epoch() {
        assert_eq!(format_unix(0), "1970-01-01 00:00:00");
        assert_eq!(format_unix(1_700_000_000), "2023-11-14 22:13:20");
    }

    #[test]
    fn text_range_serde_roundtrip() {
        let r = TextRange { start: 3, end: 7 };
        let s = serde_json::to_string(&r).unwrap();
        let back: TextRange = serde_json::from_str(&s).unwrap();
        assert_eq!(r, back);
    }
}
