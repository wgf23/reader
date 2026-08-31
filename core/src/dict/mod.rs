//! 词典与翻译：StarDict 离线词库（查词零网络）+ 在线翻译 Provider + 结果缓存。
//!
//! 设计：docs/04-module-design.md §7、docs/02-technical.md §8、REQ-003 02-design §2。
//! 缓存键：(原文, from, to, provider)，见 docs/04 §5 translation_cache 表。
//! 分层（ddd-rules 冻结）：本模块属 domain 层，禁止 `crate::store|api|library`；
//! 持久化一律经 `crate::types` 的契约 trait（TranslationCacheRepository/ProviderConfig）
//! 由 infrastructure 实现、interface 装配注入（ADR REQ-003 决策点3）。
//! 网络仅封装于 `provider::DeepLProvider` 内部（ADR 决策点4：ureq + rustls）。

mod provider;
mod stardict;
mod translation;

pub use provider::{DeepLProvider, EchoProvider};
pub use translation::{DictService, TranslationService};

use crate::error::Result;
use crate::types::{Lang, Translation};

/// 词条（docs/04 §2.1：音标/词性/释义/例句；中文词库字段可空，UI 空值不渲染）
#[derive(Debug, Clone, PartialEq)]
pub struct DictEntry {
    pub word: String,
    pub phonetic: Option<String>,
    pub pos: Option<String>, // 释义首词性标记启发式（"n."/"vt."…），无则 None
    pub definition: String,  // m/g 字段按序拼接（g 为 HTML 原样保留）
    pub example: Option<String>, // x 字段
}

/// 已安装词库信息（US-7 返回值）
#[derive(Debug, Clone)]
pub struct DictInfo {
    pub id: String,      // bookname 消毒后作 id（安装幂等键）
    pub name: String,    // .ifo bookname
    pub word_count: u64, // .ifo wordcount
    pub path: String,    // <data_dir>/dicts/<id>/
}

/// 在线 Provider 统一接口（docs/04 §7 同步签名；ADR 决策点1 保持同步，FRB 桥接层 async）。
/// `Send` 超 trait：TranslationService 以 `static Mutex` 进程级单例持有（api.rs 装配），
/// 要求容器 Send —— 全部内置 Provider 天然 Send，属实现约束（ADR 决策点1 的"无 Send/Sync
/// 升级约束"指不引入 async trait 的 Send Future 约束，与本超 trait 不冲突）。
pub trait TranslationProvider: Send {
    fn name(&self) -> &str;
    fn translate(&self, text: &str, from: Lang, to: Lang) -> Result<Translation>;
    /// 运行时更新凭据（设置页改 key 后无需重建 Provider）；默认 no-op（Echo 忽略）
    fn configure(&mut self, _key: Option<&str>) {}
}

/// 释义首词性标记启发式：剥 HTML 后扫描前几行的行首 "n."/"vt."/"adj."…；无则 None。
/// langdao 等真实词库的 m 字段形如 "*['æpl]\nn. 苹果, 家伙"（标记在次行行首）。
pub(crate) fn extract_pos(definition: &str) -> Option<String> {
    let stripped = strip_html_tags(definition);
    // 长标记优先（vt./vi./prep. 等避免被 v./n. 前缀误吞）
    const MARKERS: [&str; 15] = [
        "interj.", "prep.", "conj.", "pron.", "num.", "art.", "aux.",
        "abbr.", "adj.", "adv.", "vt.", "vi.", "n.", "v.", "int.",
    ];
    for line in stripped.lines().take(4) {
        let t = line.trim_start();
        if t.is_empty() {
            continue;
        }
        for m in MARKERS {
            if t.starts_with(m) {
                return Some(m.to_string());
            }
        }
    }
    None
}

/// 极简 HTML 标签剥离（仅用于词性启发式与 UI 展示兜底；g 字段释义仍原样保留于
/// `DictEntry.definition`，02-design §8 已知取舍6）。
pub(crate) fn strip_html_tags(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut in_tag = false;
    for c in s.chars() {
        match c {
            '<' => in_tag = true,
            '>' if in_tag => in_tag = false,
            _ if !in_tag => out.push(c),
            _ => {}
        }
    }
    out
}
