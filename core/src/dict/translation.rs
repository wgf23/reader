//! 词库注册/查词服务（DictService）+ 翻译服务（TranslationService，缓存优先）。
//!
//! 设计：REQ-003 02-design §2.4；分层：本模块属 domain，持久化仅经 `crate::types` 契约
//! trait（TranslationCacheRepository/ProviderConfig）访问，由 infrastructure 实现注入。
//! 缓存键：(原文归一化, from, to, provider)；命中 incr_hit、失败不写缓存（US-12）。

use std::cell::OnceCell;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

use crate::dict::stardict::{self, IdxEntry, IfoMeta};
use crate::dict::{DictEntry, DictInfo, TranslationProvider};
use crate::error::{Error, Result};
use crate::types::{
    CacheEntry, CacheKey, Lang, ProviderConfig, Translation, TranslationCacheRepository,
};

// ===================== DictService（词库注册/查词） =====================

struct LoadedDict {
    info: DictInfo,
    ifo: IfoMeta,
    /// 懒加载索引（US-8"首次加载不计入"；启动扫描的坏词库在此跳过不崩溃）
    idx: OnceCell<std::result::Result<Vec<IdxEntry>, Error>>,
    idx_bytes: Vec<u8>,
    dict_file: Option<File>,
}

/// 词库注册/查词服务（US-3/5/6/7/8）
pub struct DictService {
    dicts_dir: PathBuf,
    registry: Vec<LoadedDict>,
}

impl DictService {
    /// 建 `<data_dir>/dicts`，扫描既有安装（坏词库跳过不注册）。
    pub fn new(data_dir: &Path) -> Result<DictService> {
        let dicts_dir = data_dir.join("dicts");
        std::fs::create_dir_all(&dicts_dir).map_err(Error::Io)?;
        let mut svc = DictService {
            dicts_dir,
            registry: Vec::new(),
        };
        svc.scan_existing();
        Ok(svc)
    }

    fn scan_existing(&mut self) {
        let Ok(entries) = std::fs::read_dir(&self.dicts_dir) else {
            return;
        };
        let mut dirs: Vec<PathBuf> = entries
            .filter_map(|e| e.ok().map(|e| e.path()))
            .filter(|p| p.is_dir())
            .collect();
        dirs.sort();
        for dir in dirs {
            let Some(ifo) = find_ifo_in(&dir) else { continue };
            match self.load_from_installed_dir(&dir, &ifo) {
                Ok(ld) => self.registry.push(ld),
                Err(e) => log::warn!("跳过损坏词库 {}: {e}", dir.display()),
            }
        }
    }

    fn load_from_installed_dir(&self, dir: &Path, ifo: &Path) -> Result<LoadedDict> {
        let meta = stardict::parse_ifo(ifo)?;
        let stem = dict_stem(ifo);
        let idx_path = dir.join(format!("{stem}.idx"));
        let idx_bytes = std::fs::read(&idx_path).map_err(Error::Io)?;
        let base = dir.join(&stem);
        let dict_file = match dict_path_of(&base) {
            Some(p) => {
                if p.extension().and_then(|e| e.to_str()) == Some("dz") {
                    // .dict.dz：扫描路径也解压成明文 .dict（与 install 一致；随机访问
                    // 不能直接读 gzip，否则区段取到的是压缩字节 → 乱码）。这使按内置资源
                    // 直接落盘的 .dict.dz、以及用户重启后扫描的 .dz 词典都可用。
                    let plain = dir.join(format!("{stem}.dict"));
                    stardict::decompress_dz(&p, &plain)?;
                    File::open(&plain).ok()
                } else {
                    File::open(&p).ok()
                }
            }
            None => None,
        };
        let id = sanitize_id(&meta.bookname);
        Ok(LoadedDict {
            info: DictInfo {
                id,
                name: meta.bookname.clone(),
                word_count: meta.wordcount,
                path: dir.display().to_string(),
            },
            ifo: meta,
            idx: OnceCell::new(),
            idx_bytes,
            dict_file,
        })
    }

    /// 安装词库：校验三件套 → 拷贝 → .dz 流式解压落盘 → 注册（幂等）。
    /// 入参为 `.ifo` 文件路径（或含 .ifo 的目录）；坏词库 → Err(Corrupt)，已装列表不受影响。
    pub fn install(&mut self, path: &Path) -> Result<DictInfo> {
        let ifo_path = if path.is_dir() {
            find_ifo_in(path)
                .ok_or_else(|| Error::Corrupt(format!("目录内未找到 .ifo: {}", path.display())))?
        } else {
            path.to_path_buf()
        };
        let meta = stardict::parse_ifo(&ifo_path)?;
        // 幂等：同名（bookname）词库已注册 → 返回既有（不重复注册；US-7）
        if let Some(existing) = self
            .registry
            .iter()
            .find(|ld| ld.info.name == meta.bookname)
        {
            return Ok(existing.info.clone());
        }
        let id = self.unique_id(&meta.bookname);

        let base = strip_ifo(&ifo_path);
        let idx_path = PathBuf::from(format!("{}.idx", base.display()));
        let idx_bytes = std::fs::read(&idx_path).map_err(|e| {
            Error::Corrupt(format!(
                "词库 .idx 缺失或不可读: {} ({e})",
                idx_path.display()
            ))
        })?;
        // 校验 .idx 可完整解析（截断 → Corrupt，US-6）
        let idx = stardict::load_idx(&idx_bytes).map_err(|e| {
            Error::Corrupt(format!("词库 .idx 损坏: {e}"))
        })?;
        if let Some(expected) = meta.idxfilesize {
            if expected != idx_bytes.len() as u64 {
                log::warn!(
                    "词库 {} 的 idxfilesize 声明 {} 与实际 {} 不一致",
                    meta.bookname,
                    expected,
                    idx_bytes.len()
                );
            }
        }
        // .dict 或 .dict.dz 至少存在其一
        let dict_src = dict_path_of(&base).ok_or_else(|| {
            Error::Corrupt(format!("词库缺少 .dict/.dict.dz: {}", base.display()))
        })?;

        // 落盘到 <dicts_dir>/<id>/
        let target_dir = self.dicts_dir.join(&id);
        std::fs::create_dir_all(&target_dir).map_err(Error::Io)?;
        let target_ifo = target_dir.join(format!("{id}.ifo"));
        let target_idx = target_dir.join(format!("{id}.idx"));
        let target_dict = target_dir.join(format!("{id}.dict"));
        std::fs::copy(&ifo_path, &target_ifo).map_err(Error::Io)?;
        std::fs::copy(&idx_path, &target_idx).map_err(Error::Io)?;
        if dict_src.extension().and_then(|e| e.to_str()) == Some("dz") {
            // .dict.dz：流式解压落盘（ADR 关联裁定5）
            stardict::decompress_dz(&dict_src, &target_dict)?;
        } else {
            std::fs::copy(&dict_src, &target_dict).map_err(Error::Io)?;
        }

        let info = DictInfo {
            id: id.clone(),
            name: meta.bookname.clone(),
            word_count: meta.wordcount,
            path: target_dir.display().to_string(),
        };
        self.registry.push(LoadedDict {
            info: info.clone(),
            ifo: meta,
            idx: {
                let cell = OnceCell::new();
                let _ = cell.set(Ok(idx));
                cell
            },
            idx_bytes,
            dict_file: File::open(&target_dict).ok(),
        });
        Ok(info)
    }

    /// 移除词库：删目录 + 注销；未注册 → Err(NotFound)。
    pub fn remove(&mut self, dict_id: &str) -> Result<()> {
        let pos = self
            .registry
            .iter()
            .position(|ld| ld.info.id == dict_id)
            .ok_or_else(|| Error::NotFound(format!("词库不存在: {dict_id}")))?;
        let ld = self.registry.remove(pos);
        let dir = PathBuf::from(&ld.info.path);
        if dir.is_dir() {
            std::fs::remove_dir_all(&dir).map_err(Error::Io)?;
        }
        Ok(())
    }

    /// 已装词库列表（安装顺序，US-5/7）
    pub fn list(&self) -> Result<Vec<DictInfo>> {
        Ok(self.registry.iter().map(|ld| ld.info.clone()).collect())
    }

    /// 查词：注册表空 → Err("未安装词库…")（US-3）；多词库按安装顺序取首个命中（US-5）；
    /// 单词典索引加载失败跳过继续；全部失败 → Err(Corrupt)。
    pub fn lookup(&self, word: &str, dict_id: Option<&str>) -> Result<Option<DictEntry>> {
        if self.registry.is_empty() {
            return Err(Error::NotFound(
                "未安装词库，请先在设置中导入".to_string(),
            ));
        }
        if let Some(id) = dict_id {
            if !self.registry.iter().any(|ld| ld.info.id == id) {
                return Err(Error::NotFound(format!("词库不存在: {id}")));
            }
        }
        let mut attempted = 0usize;
        for ld in &self.registry {
            if let Some(id) = dict_id {
                if ld.info.id != id {
                    continue;
                }
            }
            attempted += 1;
            let idx = match ld.idx.get_or_init(|| stardict::load_idx(&ld.idx_bytes)) {
                Ok(v) => v,
                Err(e) => {
                    log::warn!("词库 {} 索引加载失败，跳过: {e}", ld.info.name);
                    continue;
                }
            };
            let Some(entry) = stardict::lookup_entry(idx, word) else {
                continue;
            };
            // 命中条目的区段读取/解析失败 = 词库损坏（US-6 偏移越界/截断）→ 直接透出
            let dict_bytes = self.read_region(ld, entry)?;
            let seq = ld
                .ifo
                .sametypesequence
                .as_deref()
                .map(|s| s.as_bytes())
                .unwrap_or(b"");
            // 区段字节即 [offset, offset+size)，重定基后交给 parse_entry（其边界校验针对全文件）
            let rebased = IdxEntry {
                word: entry.word.clone(),
                offset: 0,
                size: dict_bytes.len() as u32,
            };
            return stardict::parse_entry(seq, &dict_bytes, &rebased).map(Some);
        }
        if attempted == 0 {
            Err(Error::Corrupt("已安装词库均无法读取".to_string()))
        } else {
            Ok(None) // 查遍无命中 → 未收录（US-2）
        }
    }

    /// 随机读 .dict 区段（只读命中条目，大词库无整包读取峰值）；偏移越界 → Corrupt（US-6）
    fn read_region(&self, ld: &LoadedDict, entry: &IdxEntry) -> Result<Vec<u8>> {
        let file = ld
            .dict_file
            .as_ref()
            .ok_or_else(|| Error::Corrupt(format!("词库 {} 缺少 .dict 文件", ld.info.name)))?;
        let file_len = file.metadata().map_err(Error::Io)?.len();
        let end = entry.offset as u64 + entry.size as u64;
        if end > file_len {
            return Err(Error::Corrupt(format!(
                "词条区段越界: {} (offset={} size={} file_len={})",
                entry.word, entry.offset, entry.size, file_len
            )));
        }
        let mut buf = vec![0u8; entry.size as usize];
        (&*file).seek(SeekFrom::Start(entry.offset as u64)).map_err(Error::Io)?;
        (&*file)
            .read_exact(&mut buf)
            .map_err(Error::Io)?;
        Ok(buf)
    }

    fn unique_id(&self, bookname: &str) -> String {
        let base = sanitize_id(bookname);
        let mut candidate = base.clone();
        let mut n = 2;
        while self.registry.iter().any(|ld| ld.info.id == candidate) {
            candidate = format!("{base}-{n}");
            n += 1;
        }
        candidate
    }
}

fn find_ifo_in(dir: &Path) -> Option<PathBuf> {
    let entries = std::fs::read_dir(dir).ok()?;
    let mut ifos: Vec<PathBuf> = entries
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().and_then(|e| e.to_str()) == Some("ifo"))
        .collect();
    ifos.sort();
    ifos.into_iter().next()
}

/// 目录内词库文件名主干（id.ifo → id）
fn dict_stem(ifo: &Path) -> String {
    ifo.file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| "dict".to_string())
}

/// 取 `<base>.dict` 或 `<base>.dict.dz`（都存在时优先 .dict）；base 无扩展名
fn dict_path_of(base: &Path) -> Option<PathBuf> {
    let plain = base.with_extension("dict");
    if plain.exists() {
        return Some(plain);
    }
    let dz = PathBuf::from(format!("{}.dict.dz", base.display()));
    if dz.exists() {
        return Some(dz);
    }
    None
}

/// 去掉 .ifo 后缀（大小写不敏感）得基名
fn strip_ifo(path: &Path) -> PathBuf {
    let s = path.display().to_string();
    let lower = s.to_ascii_lowercase();
    if lower.ends_with(".ifo") {
        PathBuf::from(&s[..s.len() - 4])
    } else {
        path.with_extension("")
    }
}

/// bookname 消毒作目录名/id（幂等键）；空 → "dict"；截断防超长路径。
/// 消毒结果过于退化（如中文词库名全映射为下划线，仅剩 "5_0" 这类）→ 回退
/// "dict-<fnv32 哈希>"，避免不同中文名词库 id 碰撞（langdao-ec/ce 实测）。
fn sanitize_id(name: &str) -> String {
    let mut s: String = name
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '_'
            }
        })
        .collect();
    if s.is_empty() {
        s = "dict".to_string();
    }
    if s.len() > 64 {
        s.truncate(64);
    }
    let alnum_count = s.chars().filter(|c| c.is_ascii_alphanumeric()).count();
    if alnum_count < 3 {
        s = format!("dict-{:08x}", fnv32(name));
    }
    s
}

/// FNV-1a 32 位稳定哈希（仅用于 id 消歧，无密码学用途）
fn fnv32(s: &str) -> u32 {
    let mut h: u32 = 0x811c_9dc5;
    for b in s.as_bytes() {
        h ^= *b as u32;
        h = h.wrapping_mul(0x0100_0193);
    }
    h
}

// ===================== TranslationService（缓存优先编排） =====================

/// 虚拟策略名：在线优先（deepl/echo）→ 失败/无 key 回退离线（REQ-006 决策点1）。
/// 仅作为 `settings` 值域的策略名，**不注册为 Provider**。
pub const AUTO_PROVIDER: &str = "auto";
/// 回退原因：在线 Provider 被实际尝试且失败。
pub const FALLBACK_REASON_ONLINE_FAILED: &str = "在线失败，已回退离线";
/// 回退原因：无可用在线 key（或唯一候选为离线）。
pub const FALLBACK_REASON_ONLINE_UNCONFIGURED: &str = "未配置在线翻译 API Key，已回退离线";

/// 策略路由结果（`fallback_reason` 不进 `Translation` 值对象、不写缓存）。
#[derive(Debug)]
pub struct RoutedTranslation {
    pub translation: Translation,
    pub from_cache: bool,
    pub fallback_reason: Option<String>,
}

/// 翻译配置视图（供桥接 `translate_get_config`；不含明文 key）。
#[derive(Debug)]
pub struct TranslateConfig {
    /// "auto" | "offline" | "deepl" | "echo"（= default_provider）
    pub provider: String,
    /// `DeepLProvider::key_is_missing` 语义（空串=false）
    pub has_deepl_key: bool,
}

/// 翻译服务（缓存优先；US-9~14）
pub struct TranslationService {
    cache: Box<dyn TranslationCacheRepository + Send>,
    config: Box<dyn ProviderConfig + Send>,
    providers: Vec<Box<dyn TranslationProvider>>,
}

impl TranslationService {
    pub fn new(
        cache: Box<dyn TranslationCacheRepository + Send>,
        config: Box<dyn ProviderConfig + Send>,
        providers: Vec<Box<dyn TranslationProvider>>,
    ) -> Self {
        TranslationService {
            cache,
            config,
            providers,
        }
    }

    /// 翻译（缓存优先）；返回 (译文, 是否命中缓存)。from_cache 供 api 层标注（US-10/13）。
    ///
    /// REQ-006：委托 [`Self::translate_routed`]（**2 元组签名不变**，丢弃 `fallback_reason`）。
    pub fn translate_cached(
        &mut self,
        text: &str,
        from: Lang,
        to: Lang,
    ) -> Result<(Translation, bool)> {
        self.translate_routed(text, from, to)
            .map(|r| (r.translation, r.from_cache))
    }

    /// 策略路由（REQ-006 决策点1）：`auto` 在线优先 → 失败/无 key 回退离线；
    /// 显式 provider → 该 provider 优先，失败回退离线；缓存按**真实 provider** 分行。
    pub fn translate_routed(
        &mut self,
        text: &str,
        from: Lang,
        to: Lang,
    ) -> Result<RoutedTranslation> {
        let norm = normalize_text(text);
        if norm.is_empty() {
            return Err(Error::Other("待翻译文本为空".to_string()));
        }
        let strategy = self.config.default_provider()?;
        if strategy == AUTO_PROVIDER {
            return self.translate_auto(text, &norm, from, to);
        }
        self.translate_explicit(&strategy, &norm, from, to)
    }

    /// `auto` 策略：在线优先（deepl/echo）→ 失败/无 key 回退离线（REQ-006 决策点1）。
    fn translate_auto(
        &mut self,
        text: &str,
        norm: &str,
        from: Lang,
        to: Lang,
    ) -> Result<RoutedTranslation> {
        // 在线候选 = 注册顺序中 needs_key 的 Provider（实际即 deepl、echo）；
        // 离线候选 = needs_key==false（offline）。
        let online: Vec<String> = self
            .providers
            .iter()
            .filter(|p| p.needs_key())
            .map(|p| p.name().to_string())
            .collect();
        let offline: Vec<String> = self
            .providers
            .iter()
            .filter(|p| !p.needs_key())
            .map(|p| p.name().to_string())
            .collect();

        // 1) 在线优先：逐个候选查缓存（命中即返回，避免离线先缓存导致永远走缓存）
        for name in &online {
            if let Some(t) = self.cache_get_translation(&norm, from, to, name)? {
                return Ok(RoutedTranslation {
                    translation: t,
                    from_cache: true,
                    fallback_reason: None,
                });
            }
        }
        // 2) 在线未命中：逐个校验 key → translate
        let mut online_error: Option<Error> = None;
        let mut online_unconfigured = false;
        let mut first_unconfigured: Option<String> = None;
        for name in &online {
            let key = self.config.provider_key(name)?;
            let missing = self
                .providers
                .iter()
                .find(|p| p.name() == name)
                .map(|p| p.key_is_missing(key.as_deref()))
                .unwrap_or(key.is_none());
            if missing {
                online_unconfigured = true;
                if first_unconfigured.is_none() {
                    first_unconfigured = Some(name.clone());
                }
                continue;
            }
            let provider = self
                .providers
                .iter()
                .find(|p| p.name() == name)
                .expect("候选 provider 必存在");
            match provider.translate(&norm, from, to) {
                Ok(t) => {
                    self.cache_put_translation(&norm, from, to, name, &t)?;
                    return Ok(RoutedTranslation {
                        translation: t,
                        from_cache: false,
                        fallback_reason: None,
                    });
                }
                Err(e) => online_error = Some(e),
            }
        }

        // 3) 回退离线（先缓存后翻译）
        let reason = if online_error.is_some() {
            Some(FALLBACK_REASON_ONLINE_FAILED.to_string())
        } else if online_unconfigured || online.is_empty() {
            Some(FALLBACK_REASON_ONLINE_UNCONFIGURED.to_string())
        } else {
            None
        };
        let mut offline_error: Option<Error> = None;
        for name in &offline {
            if let Some(t) = self.cache_get_translation(&norm, from, to, name)? {
                return Ok(RoutedTranslation {
                    translation: t,
                    from_cache: true,
                    fallback_reason: reason,
                });
            }
            let provider = self
                .providers
                .iter()
                .find(|p| p.name() == name)
                .expect("离线候选 provider 必存在");
            match provider.translate(&norm, from, to) {
                Ok(t) => {
                    self.cache_put_translation(&norm, from, to, name, &t)?;
                    return Ok(RoutedTranslation {
                        translation: t,
                        from_cache: false,
                        fallback_reason: reason,
                    });
                }
                Err(e) => offline_error = Some(e),
            }
        }

        // 4) 全部失败 → 组合错误（§8 文案契约）
        if let Some(ne) = online_error {
            return Err(Error::Network {
                detail: format!("在线翻译失败：{ne}；离线翻译未命中（请先安装内置词库）"),
                source_text: text.to_string(),
            });
        }
        if online_unconfigured || online.is_empty() {
            let pname = first_unconfigured.unwrap_or_else(|| "deepl".to_string());
            return Err(Error::NotConfigured(format!(
                "未配置在线翻译 API Key（{pname}），且离线翻译未命中（请先安装内置词库）"
            )));
        }
        Err(offline_error
            .unwrap_or_else(|| Error::NotConfigured("离线翻译未命中（请先安装内置词库）".to_string())))
    }

    /// 显式策略：该 provider 优先（缓存 → key 校验 → translate），失败回退离线。
    fn translate_explicit(
        &mut self,
        name: &str,
        norm: &str,
        from: Lang,
        to: Lang,
    ) -> Result<RoutedTranslation> {
        if !self.providers.iter().any(|p| p.name() == name) {
            return Err(Error::NotConfigured(format!("未知翻译 Provider: {name}")));
        }
        // 1) 缓存优先
        if let Some(t) = self.cache_get_translation(norm, from, to, name)? {
            return Ok(RoutedTranslation {
                translation: t,
                from_cache: true,
                fallback_reason: None,
            });
        }
        // 2) key 校验 + translate（保留 REQ-003 语义）
        let key = self.config.provider_key(name)?;
        let missing = self
            .providers
            .iter()
            .find(|p| p.name() == name)
            .map(|p| p.key_is_missing(key.as_deref()))
            .unwrap_or(key.is_none());
        let mut primary_error: Option<Error>;
        if missing {
            primary_error = Some(Error::NotConfigured(format!(
                "{name} 未配置 API Key，请先在设置中配置"
            )));
        } else {
            let provider = self
                .providers
                .iter()
                .find(|p| p.name() == name)
                .expect("provider 必存在");
            match provider.translate(norm, from, to) {
                Ok(t) => {
                    self.cache_put_translation(norm, from, to, name, &t)?;
                    return Ok(RoutedTranslation {
                        translation: t,
                        from_cache: false,
                        fallback_reason: None,
                    });
                }
                Err(e) => primary_error = Some(e),
            }
        }
        // 3) offline 兜底（排除显式 provider 自身；显式 offline 时无额外兜底）
        let offline: Vec<String> = self
            .providers
            .iter()
            .filter(|p| !p.needs_key() && p.name() != name)
            .map(|p| p.name().to_string())
            .collect();
        if !offline.is_empty() {
            let reason = if missing {
                FALLBACK_REASON_ONLINE_UNCONFIGURED
            } else {
                FALLBACK_REASON_ONLINE_FAILED
            };
            for off in &offline {
                if let Some(t) = self.cache_get_translation(norm, from, to, off)? {
                    return Ok(RoutedTranslation {
                        translation: t,
                        from_cache: true,
                        fallback_reason: Some(reason.to_string()),
                    });
                }
                let provider = self
                    .providers
                    .iter()
                    .find(|p| p.name() == off)
                    .expect("离线 provider 必存在");
                if let Ok(t) = provider.translate(norm, from, to) {
                    self.cache_put_translation(norm, from, to, off, &t)?;
                    return Ok(RoutedTranslation {
                        translation: t,
                        from_cache: false,
                        fallback_reason: Some(reason.to_string()),
                    });
                }
            }
        }
        // 4) 无兜底/兜底失败 → 透出显式 provider 的错误（保留 REQ-003 文案）
        Err(primary_error.unwrap_or_else(|| {
            Error::NotConfigured(format!("{name} 未配置 API Key，请先在设置中配置"))
        }))
    }

    /// 读配置视图（供 `translate_get_config`）。
    pub fn config_view(&self) -> Result<TranslateConfig> {
        let provider = self.config.default_provider()?;
        let key = self.config.provider_key("deepl")?;
        let has_deepl_key = self
            .providers
            .iter()
            .find(|p| p.name() == "deepl")
            .map(|p| !p.key_is_missing(key.as_deref()))
            .unwrap_or_else(|| {
                key.as_deref()
                    .map(|k| !k.trim().is_empty())
                    .unwrap_or(false)
            });
        Ok(TranslateConfig {
            provider,
            has_deepl_key,
        })
    }

    /// 设置策略（`auto` 或已注册 provider）；未知 → `Err(Other("未知翻译策略: {s}"))`。
    pub fn set_strategy(&mut self, strategy: &str) -> Result<()> {
        if strategy == AUTO_PROVIDER || self.providers.iter().any(|p| p.name() == strategy) {
            self.config.set_default_provider(strategy)
        } else {
            Err(Error::Other(format!("未知翻译策略: {strategy}")))
        }
    }

    fn cache_get_translation(
        &mut self,
        norm: &str,
        from: Lang,
        to: Lang,
        provider: &str,
    ) -> Result<Option<Translation>> {
        let key = CacheKey {
            source_text: norm.to_string(),
            from_lang: from,
            to_lang: to,
            provider: provider.to_string(),
        };
        if let Some(entry) = self.cache.cache_get(&key)? {
            self.cache.cache_incr_hit(&key)?;
            return Ok(Some(entry.result));
        }
        Ok(None)
    }

    fn cache_put_translation(
        &mut self,
        norm: &str,
        from: Lang,
        to: Lang,
        provider: &str,
        t: &Translation,
    ) -> Result<()> {
        let key = CacheKey {
            source_text: norm.to_string(),
            from_lang: from,
            to_lang: to,
            provider: provider.to_string(),
        };
        self.cache.cache_put(&CacheEntry {
            key,
            result: t.clone(),
            created_at: now_unix(),
            hit_count: 1,
        })
    }

    /// 翻译（薄包装，保持 02-design §2.4 签名）
    pub fn translate(&mut self, text: &str, from: Lang, to: Lang) -> Result<Translation> {
        self.translate_cached(text, from, to).map(|(t, _)| t)
    }

    pub fn clear_cache(&mut self) -> Result<()> {
        self.cache.cache_clear()
    }

    /// 写 settings（set_provider_key + set_default_provider）并对注册 Provider 调 configure
    /// （ADR 关联裁定2：`translate_set_config("echo","")` 切 echo 即无 key 演示）
    pub fn set_config(&mut self, provider: &str, key: &str) -> Result<()> {
        self.config.set_provider_key(provider, key)?;
        self.config.set_default_provider(provider)?;
        for p in &mut self.providers {
            if p.name() == provider {
                p.configure(Some(key));
            }
        }
        Ok(())
    }
}

/// 连续空白折叠为单空格并 trim（US-9 跨行自动合并）
pub fn normalize_text(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut last_ws = false;
    for c in s.chars() {
        if c.is_whitespace() {
            if !out.is_empty() && !last_ws {
                out.push(' ');
            }
            last_ws = true;
        } else {
            out.push(c);
            last_ws = false;
        }
    }
    out.trim().to_string()
}

fn now_unix() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dict::provider::{CountingProvider, EchoProvider, FailingProvider};
    use std::collections::HashMap;
    use std::io::Write;
    use std::time::Instant;

    // ---------- 测试辅助 ----------

    /// 内存缓存仓储（服务层测试不碰 SQLite，ADR 决策点3 可单测性论证）
    #[derive(Default)]
    struct MemCache {
        map: HashMap<CacheKey, (Translation, i64, u64)>,
    }

    impl TranslationCacheRepository for MemCache {
        fn cache_get(&self, key: &CacheKey) -> Result<Option<CacheEntry>> {
            Ok(self.map.get(key).map(|(t, ts, hits)| CacheEntry {
                key: key.clone(),
                result: t.clone(),
                created_at: *ts,
                hit_count: *hits,
            }))
        }
        fn cache_put(&mut self, entry: &CacheEntry) -> Result<()> {
            let prev_hits = self
                .map
                .get(&entry.key)
                .map(|(_, _, h)| *h)
                .unwrap_or(0);
            self.map.insert(
                entry.key.clone(),
                (
                    entry.result.clone(),
                    entry.created_at,
                    if prev_hits > 0 { prev_hits } else { entry.hit_count },
                ),
            );
            Ok(())
        }
        fn cache_incr_hit(&mut self, key: &CacheKey) -> Result<()> {
            if let Some((_, _, h)) = self.map.get_mut(key) {
                *h += 1;
            }
            Ok(())
        }
        fn cache_clear(&mut self) -> Result<()> {
            self.map.clear();
            Ok(())
        }
        fn cache_count(&self) -> Result<u64> {
            Ok(self.map.len() as u64)
        }
    }

    /// 内存配置仓储
    #[derive(Default)]
    struct MemConfig {
        default: String,
        keys: HashMap<String, String>,
    }

    impl MemConfig {
        fn with_default(provider: &str) -> Self {
            MemConfig {
                default: provider.to_string(),
                keys: HashMap::new(),
            }
        }
    }

    impl ProviderConfig for MemConfig {
        fn default_provider(&self) -> Result<String> {
            Ok(self.default.clone())
        }
        fn provider_key(&self, provider: &str) -> Result<Option<String>> {
            Ok(self.keys.get(provider).cloned())
        }
        fn set_provider_key(&mut self, provider: &str, key: &str) -> Result<()> {
            self.keys.insert(provider.to_string(), key.to_string());
            Ok(())
        }
        fn set_default_provider(&mut self, provider: &str) -> Result<()> {
            self.default = provider.to_string();
            Ok(())
        }
    }

    struct DeepLStub;
    impl TranslationProvider for DeepLStub {
        fn name(&self) -> &str {
            "deepl"
        }
        fn translate(&self, text: &str, from: Lang, to: Lang) -> Result<Translation> {
            Ok(Translation {
                text: format!("DEEPL:{text}"),
                from,
                to,
                provider: "deepl".into(),
            })
        }
    }

    /// 共享计数器 Provider（测试需在注入后仍能断言调用计数；Arc 满足 Send 约束）
    struct SharedCounting {
        calls: std::sync::Arc<std::sync::atomic::AtomicU32>,
        inner: Box<dyn TranslationProvider>,
    }

    impl TranslationProvider for SharedCounting {
        fn name(&self) -> &str {
            "shared-count"
        }
        fn translate(&self, text: &str, from: Lang, to: Lang) -> Result<Translation> {
            self.calls.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            self.inner.translate(text, from, to)
        }
    }

    /// 配置门 Provider：configure 之前 translate 失败 → 观察 set_config 是否只配置了
    /// 目标 Provider（杀死 translation.rs:441 `==`→`!=` 变异）
    struct KeyGateProvider {
        name: &'static str,
        key: std::cell::RefCell<Option<String>>,
    }

    impl KeyGateProvider {
        fn new(name: &'static str) -> Self {
            Self {
                name,
                key: std::cell::RefCell::new(None),
            }
        }
    }

    impl TranslationProvider for KeyGateProvider {
        fn name(&self) -> &str {
            self.name
        }
        fn translate(&self, text: &str, from: Lang, to: Lang) -> Result<Translation> {
            if self.key.borrow().is_none() {
                return Err(Error::NotConfigured(format!("{} 未配置", self.name)));
            }
            Ok(Translation {
                text: format!("OK:{text}"),
                from,
                to,
                provider: self.name.to_string(),
            })
        }
        fn configure(&mut self, key: Option<&str>) {
            *self.key.borrow_mut() = key.map(|s| s.to_string());
        }
    }

    fn svc_with(cache: MemCache, config: MemConfig, providers: Vec<Box<dyn TranslationProvider>>) -> TranslationService {
        TranslationService::new(Box::new(cache), Box::new(config), providers)
    }

    /// 合成词库写入器：(word, phonetic, html, plain, example)
    fn write_synth_dict(dir: &Path, name: &str, seq: &str, entries: &[(&str, &str, &str, &str, Option<&str>)]) {
        let d = dir.join(name);
        std::fs::create_dir_all(&d).unwrap();
        let mut entries: Vec<(&str, &str, &str, &str, Option<&str>)> = entries.to_vec();
        entries.sort_by_key(|e| e.0.to_string());
        // 先算 dict 内容与偏移
        let mut dict = Vec::new();
        let mut offsets = Vec::new();
        for (_w, ph, g, m, x) in &entries {
            let fields: Vec<Vec<u8>> = seq
                .chars()
                .map(|c| match c {
                    't' => ph.as_bytes().to_vec(),
                    'g' => g.as_bytes().to_vec(),
                    'm' => m.as_bytes().to_vec(),
                    'x' => x.unwrap_or("").as_bytes().to_vec(),
                    _ => b"unknown".to_vec(),
                })
                .collect();
            let off = dict.len();
            for (i, f) in fields.iter().enumerate() {
                dict.extend_from_slice(f);
                if i < fields.len() - 1 {
                    dict.push(0);
                }
            }
            offsets.push((off, dict.len() - off));
        }
        let mut idx = Vec::new();
        for ((w, _, _, _, _), (off, size)) in entries.iter().zip(offsets.iter()) {
            idx.extend_from_slice(w.as_bytes());
            idx.push(0);
            idx.extend_from_slice(&(*off as u32).to_be_bytes());
            idx.extend_from_slice(&(*size as u32).to_be_bytes());
        }
        std::fs::write(d.join(format!("{name}.idx")), &idx).unwrap();
        std::fs::write(d.join(format!("{name}.dict")), &dict).unwrap();
        let ifo = format!(
            "StarDict's dict ifo file\nversion=2.4.2\nbookname={name}\nwordcount={}\nidxfilesize={}\nsametypesequence={seq}\n",
            entries.len(),
            idx.len()
        );
        std::fs::write(d.join(format!("{name}.ifo")), ifo).unwrap();
    }

    fn install_named(svc: &mut DictService, dir: &Path, name: &str) -> DictInfo {
        let ifo = dir.join(name).join(format!("{name}.ifo"));
        svc.install(&ifo).unwrap()
    }

    fn sample_entries() -> Vec<(&'static str, &'static str, &'static str, &'static str, Option<&'static str>)> {
        vec![
            ("apple", "/æp/", "<b>n.</b> fruit", "n. 苹果", None),
            ("Apple", "", "<b>n.</b> company", "n. 苹果公司", None),
            ("book", "/bʊk/", "<b>n.</b> work", "n. 书", Some("a good book")),
            ("hello", "/hə/", "<b>int.</b> greeting", "int. 你好", None),
            ("zebra", "/z/", "<b>Zebra</b>", "一种非洲动物", None),
        ]
    }

    // ---------- DictService：US-3/5/6/7/8 ----------

    #[test]
    fn dict_install_list_and_lookup_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let mut svc = DictService::new(dir.path()).unwrap();
        write_synth_dict(dir.path(), "test-tgmx", "tgmx", &sample_entries());
        let info = install_named(&mut svc, dir.path(), "test-tgmx");
        assert_eq!(info.name, "test-tgmx");
        assert_eq!(info.word_count, 5);
        assert!(info.path.contains("dicts"));

        let list = svc.list().unwrap();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].id, info.id);

        let e = svc.lookup("book", None).unwrap().expect("应有词条");
        assert_eq!(e.word, "book");
        assert_eq!(e.phonetic.as_deref(), Some("/bʊk/"));
        assert_eq!(e.pos.as_deref(), Some("n."));
        assert!(e.definition.contains("n. 书"));
        assert_eq!(e.example.as_deref(), Some("a good book"));
    }

    #[test]
    fn dict_lookup_empty_registry_is_err_with_hint() {
        let dir = tempfile::tempdir().unwrap();
        let svc = DictService::new(dir.path()).unwrap();
        let err = svc.lookup("apple", None).unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("词库"), "应含'词库': {msg}");
        assert!(msg.contains("未安装"), "应含'未安装': {msg}");
    }

    #[test]
    fn dict_lookup_case_normalization_apple() {
        // 该词库只含 "Apple"（大写首字母），不含小写 "apple" → 归一命中（US-5）
        let only_apple: Vec<(&str, &str, &str, &str, Option<&str>)> = vec![
            ("Apple", "", "<b>n.</b> company", "n. 苹果公司", None),
            ("zebra", "/z/", "<b>Zebra</b>", "一种非洲动物", None),
        ];
        let dir = tempfile::tempdir().unwrap();
        let mut svc = DictService::new(dir.path()).unwrap();
        write_synth_dict(dir.path(), "t1", "tgm", &only_apple);
        install_named(&mut svc, dir.path(), "t1");
        let e = svc.lookup("apple", None).unwrap().expect("应有词条");
        assert_eq!(e.word, "Apple", "首字母归一应命中 'Apple'");
        assert_eq!(e.phonetic, None, "空音标应 None");
        // 未收录仍 None
        assert!(svc.lookup("zzzqqq", None).unwrap().is_none());
    }

    #[test]
    fn dict_lookup_unknown_word_returns_none() {
        let dir = tempfile::tempdir().unwrap();
        let mut svc = DictService::new(dir.path()).unwrap();
        write_synth_dict(dir.path(), "t1", "tgm", &sample_entries());
        install_named(&mut svc, dir.path(), "t1");
        assert!(svc.lookup("zzzqqq", None).unwrap().is_none(), "未收录 → Ok(None)");
    }

    #[test]
    fn dict_multi_dict_install_order_first_hit() {
        let dir = tempfile::tempdir().unwrap();
        let mut svc = DictService::new(dir.path()).unwrap();
        // A、B 均含 apple；按安装序 A 先 → 只返回 A
        let a: Vec<(&str, &str, &str, &str, Option<&str>)> = vec![
            ("apple", "/A/", "<b>n.</b> A", "n. A 释义", None),
        ];
        let b: Vec<(&str, &str, &str, &str, Option<&str>)> = vec![
            ("apple", "/B/", "<b>n.</b> B", "n. B 释义", None),
            ("zzz", "/Z/", "<b>n.</b> Z", "n. Z", None),
        ];
        write_synth_dict(dir.path(), "dictA", "tgm", &a);
        write_synth_dict(dir.path(), "dictB", "tgm", &b);
        install_named(&mut svc, dir.path(), "dictA");
        install_named(&mut svc, dir.path(), "dictB");
        let e = svc.lookup("apple", None).unwrap().expect("应有词条");
        assert!(e.definition.contains("A 释义"), "应取 A 词库: {}", e.definition);
        // 指定 dict_id 只查该词库
        let info_b = &svc.list().unwrap()[1];
        let e = svc.lookup("apple", Some(&info_b.id)).unwrap().expect("B 含 apple");
        assert!(e.definition.contains("B 释义"));
    }

    #[test]
    fn dict_install_idempotent() {
        let dir = tempfile::tempdir().unwrap();
        let mut svc = DictService::new(dir.path()).unwrap();
        write_synth_dict(dir.path(), "t1", "tgm", &sample_entries());
        let ifo = dir.path().join("t1").join("t1.ifo");
        let i1 = svc.install(&ifo).unwrap();
        let i2 = svc.install(&ifo).unwrap();
        assert_eq!(i1.id, i2.id);
        assert_eq!(svc.list().unwrap().len(), 1, "重复安装不重复注册");
    }

    #[test]
    fn dict_remove_deletes_dir_and_falls_back() {
        let dir = tempfile::tempdir().unwrap();
        let mut svc = DictService::new(dir.path()).unwrap();
        write_synth_dict(dir.path(), "t1", "tgm", &sample_entries());
        let info = install_named(&mut svc, dir.path(), "t1");
        let dict_dir = std::path::PathBuf::from(&info.path);
        assert!(dict_dir.exists());
        svc.remove(&info.id).unwrap();
        assert!(!dict_dir.exists(), "目录应被删除");
        assert!(svc.list().unwrap().is_empty());
        // 移除后查词回落 US-3（注册表空）
        let err = svc.lookup("apple", None).unwrap_err();
        assert!(err.to_string().contains("未安装"));
    }

    #[test]
    fn dict_install_bad_files_do_not_affect_list() {
        let dir = tempfile::tempdir().unwrap();
        let mut svc = DictService::new(dir.path()).unwrap();
        write_synth_dict(dir.path(), "good", "tgm", &sample_entries());
        install_named(&mut svc, dir.path(), "good");

        // 坏 1：.idx 截断
        let bad1 = dir.path().join("bad1");
        std::fs::create_dir_all(&bad1).unwrap();
        write_synth_dict(dir.path(), "bad1", "tgm", &sample_entries());
        let idx_bytes = std::fs::read(bad1.join("bad1.idx")).unwrap();
        std::fs::write(bad1.join("bad1.idx"), &idx_bytes[..idx_bytes.len() - 12]).unwrap();
        let err = svc.install(&bad1.join("bad1.ifo")).unwrap_err();
        assert!(matches!(err, Error::Corrupt(_)), "截断应 Corrupt: {err}");

        // 坏 2：.ifo 缺 wordcount
        let bad2 = dir.path().join("bad2");
        std::fs::create_dir_all(&bad2).unwrap();
        write_synth_dict(dir.path(), "bad2", "tgm", &sample_entries());
        let ifo = std::fs::read_to_string(bad2.join("bad2.ifo")).unwrap();
        let ifo2: String = ifo.lines().filter(|l| !l.starts_with("wordcount=")).collect::<Vec<_>>().join("\n");
        std::fs::write(bad2.join("bad2.ifo"), ifo2).unwrap();
        let err = svc.install(&bad2.join("bad2.ifo")).unwrap_err();
        assert!(matches!(err, Error::Corrupt(_)));

        // 已装列表不受影响
        assert_eq!(svc.list().unwrap().len(), 1, "坏词库安装失败不影响已装列表");
    }

    #[test]
    fn dict_lookup_offset_oob_is_corrupt_not_panic() {
        let dir = tempfile::tempdir().unwrap();
        let mut svc = DictService::new(dir.path()).unwrap();
        // 构造条目 size 越界：直接用 patch 后的 idx
        write_synth_dict(dir.path(), "oob", "tgm", &sample_entries());
        let idx_path = dir.path().join("oob").join("oob.idx");
        let mut idx = std::fs::read(&idx_path).unwrap();
        let nul = idx.iter().position(|&b| b == 0).unwrap();
        // 第一条目 size 字段（word\0 后 8 字节，size 在后 4 字节）
        let size_off = nul + 1 + 4;
        idx[size_off..size_off + 4].copy_from_slice(&0x7FFFFFFFu32.to_be_bytes());
        std::fs::write(&idx_path, &idx).unwrap();
        // 安装可成功（idx 可解析），查被 patch 的首条（"Apple"）→ Corrupt（US-6 偏移越界）
        install_named(&mut svc, dir.path(), "oob");
        let err = svc.lookup("Apple", None).unwrap_err();
        assert!(matches!(err, Error::Corrupt(_)), "越界应 Corrupt: {err}");
    }

    #[test]
    fn dict_dz_install_decompresses_and_lookup_works() {
        let dir = tempfile::tempdir().unwrap();
        let mut svc = DictService::new(dir.path()).unwrap();
        write_synth_dict(dir.path(), "dz", "tgmx", &sample_entries());
        // 压成 .dict.dz 并删 .dict
        let dict_path = dir.path().join("dz").join("dz.dict");
        let raw = std::fs::read(&dict_path).unwrap();
        let mut enc = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        enc.write_all(&raw).unwrap();
        std::fs::write(dir.path().join("dz").join("dz.dict.dz"), enc.finish().unwrap()).unwrap();
        std::fs::remove_file(&dict_path).unwrap();
        let info = install_named(&mut svc, dir.path(), "dz");
        let e = svc.lookup("book", Some(&info.id)).unwrap().expect("应有词条");
        assert_eq!(e.word, "book");
        assert!(e.definition.contains("n. 书"));
        assert_eq!(e.example.as_deref(), Some("a good book"), "x 字段应解析为例句");
    }

    #[test]
    fn dict_scan_existing_on_reopen_registers_installed() {
        // US-7 安装持久化语义：重开服务后 scan_existing 必须把已装词库重新注册。
        // 杀死 translation.rs:50（scan_existing → ()）、:279（find_ifo_in 恒 None/空路径）、
        // :282（== → !=，选错文件）、:290（dict_stem 恒 ""/"xyzzy"，拼错 .idx 名）等变异。
        let dir = tempfile::tempdir().unwrap();
        {
            let mut svc = DictService::new(dir.path()).unwrap();
            write_synth_dict(dir.path(), "t1", "tgm", &sample_entries());
            install_named(&mut svc, dir.path(), "t1");
            assert_eq!(svc.list().unwrap().len(), 1);
        }
        let svc = DictService::new(dir.path()).unwrap();
        let list = svc.list().unwrap();
        assert_eq!(list.len(), 1, "重开应重扫已装词库");
        assert_eq!(list[0].name, "t1");
        let e = svc.lookup("book", None).unwrap().expect("重开后仍可查词");
        assert!(e.definition.contains("n. 书"));
    }

    #[test]
    fn dict_install_with_directory_argument() {
        // install 入参为含 .ifo 的目录（US-7 路径变体）；杀死 find_ifo_in 三个变异
        // （恒 None / 恒空路径 / == → != 选错扩展名文件）
        let dir = tempfile::tempdir().unwrap();
        let mut svc = DictService::new(dir.path()).unwrap();
        write_synth_dict(dir.path(), "t1", "tgm", &sample_entries());
        let info = svc.install(&dir.path().join("t1")).unwrap();
        assert_eq!(info.name, "t1");
        assert_eq!(svc.list().unwrap().len(), 1);
        assert!(svc.lookup("book", None).unwrap().is_some());
    }

    #[test]
    fn dict_unique_id_colliding_sanitized_names_get_suffix() {
        // 三个 bookname 消毒后同为 "foo_bar"（名字互异 → 不走同名幂等短路）→
        // unique_id 依次产出 foo_bar / foo_bar-2 / foo_bar-3。
        // 杀死 translation.rs:272 `+=`→`-=`（第三次会产出 foo_bar-1）；
        // `+=`→`*=` 变异在第三次碰撞时 n 恒 2 死循环 → 超时单列（timeout 口径）。
        let dir = tempfile::tempdir().unwrap();
        let mut svc = DictService::new(dir.path()).unwrap();
        write_synth_dict(dir.path(), "foo bar", "tgm", &sample_entries());
        write_synth_dict(dir.path(), "foo_bar", "tgm", &sample_entries());
        write_synth_dict(dir.path(), "foo*bar", "tgm", &sample_entries());
        let i1 = install_named(&mut svc, dir.path(), "foo bar");
        let i2 = install_named(&mut svc, dir.path(), "foo_bar");
        let i3 = install_named(&mut svc, dir.path(), "foo*bar");
        assert_eq!(i1.id, "foo_bar");
        assert_eq!(i2.id, "foo_bar-2");
        assert_eq!(i3.id, "foo_bar-3", "第三次碰撞应继续递增后缀");
    }

    #[test]
    fn dict_lookup_perf_budget_100_lookups() {
        // US-8：索引已加载后连续 100 次查词平均 <50ms（CI 宽松断言 ≤200ms）
        let dir = tempfile::tempdir().unwrap();
        let mut svc = DictService::new(dir.path()).unwrap();
        // 合成 2 万条目词库（大索引才有意义）
        let words: Vec<String> = (0..20_000u32).map(|i| format!("word{i:05}")).collect();
        let big: Vec<(&str, &str, &str, &str, Option<&str>)> = words
            .iter()
            .map(|w| (w.as_str(), "/p/", "<b>n.</b> def", "n. 释义", None))
            .collect();
        write_synth_dict(dir.path(), "big", "tgm", &big);
        let info = install_named(&mut svc, dir.path(), "big");
        // 预热（首次加载不计入）
        assert!(svc.lookup("word00001", Some(&info.id)).unwrap().is_some());
        let start = Instant::now();
        let mut hits = 0;
        for i in 0..100u32 {
            let w = format!("word{:05}", (i * 137) % 20_000);
            if svc.lookup(&w, Some(&info.id)).unwrap().is_some() {
                hits += 1;
            }
        }
        let avg_ms = start.elapsed().as_micros() as f64 / 100.0 / 1000.0;
        eprintln!("[US-8 基准] 100 次查词共 {:?}，单次均值 {avg_ms:.3}ms", start.elapsed());
        assert_eq!(hits, 100);
        assert!(
            start.elapsed().as_millis() <= 200,
            "100 次查词应 ≤200ms（CI 上限），实测 {avg_ms:.2}ms/次"
        );
    }

    // ---------- sanitize_id / fnv32（id 生成契约） ----------

    #[test]
    fn sanitize_id_keeps_alnum_hyphen_underscore() {
        // 杀死 sanitize_id 恒 ""/"xyzzy"（L323）与 `||`→`&&`（L326）、`==`→`!=`（L326）变异
        assert_eq!(sanitize_id("foo-bar_baz2"), "foo-bar_baz2");
        assert_eq!(sanitize_id("hello world"), "hello_world");
    }

    #[test]
    fn sanitize_id_empty_becomes_dict() {
        assert_eq!(sanitize_id(""), "dict");
    }

    #[test]
    fn sanitize_id_cjk_falls_back_to_hash() {
        // 中文名全映射下划线且 alnum<3 → dict-<fnv32>（防不同中文名词库 id 碰撞）。
        // 期望值硬编码（不自调用 fnv32，否则 fnv32 变异自洽逃逸）；
        // 杀死 fnv32 恒 0/1 与 `^=`→`|=`/`&=` 四个变异。
        assert_eq!(sanitize_id("中文名"), "dict-3009aee7");
    }

    #[test]
    fn sanitize_id_alnum_count_threshold() {
        // alnum==3（"abc"）与 alnum==4（"abcd"）均不触发哈希回退；
        // 杀死 L340 `<`→`==`（abc）、`<`→`>`（abcd）、`<`→`<=`（abc）
        assert_eq!(sanitize_id("abc"), "abc");
        assert_eq!(sanitize_id("abcd"), "abcd");
        assert_eq!(sanitize_id("a1b2c3d4"), "a1b2c3d4");
    }

    #[test]
    fn sanitize_id_truncates_overlong() {
        // 杀死 L336 `>`→`==` 与 `>`→`<`（80 字符名 → 原实现截断到 64，变异不截断）
        let long = "a".repeat(80);
        let s = sanitize_id(&long);
        assert_eq!(s.len(), 64);
        assert!(s.starts_with("aaaa"));
    }

    #[test]
    fn fnv32_matches_known_vector() {
        // 标准 FNV-1a 32 测试向量（杀死 fnv32 全部 4 个变异：恒 0/1、^=→|=、^=→&=）
        assert_eq!(fnv32("hello"), 0x4f9f_2cab);
        assert_eq!(fnv32("中文名"), 0x3009_aee7);
    }

    // ---------- TranslationService：US-9~14 ----------

    #[test]
    fn normalize_text_folds_whitespace_and_trims() {
        assert_eq!(normalize_text("  Hello\n  world\t!\n"), "Hello world !");
        assert_eq!(normalize_text("单 词 之间"), "单 词 之间");
        assert_eq!(normalize_text("   "), "");
    }

    #[test]
    fn translate_echo_returns_expected_and_records_only_args() {
        // US-9：Echo 固定返回 "译文:"+原文；Counting 记录参数只含 text/from/to
        let cache = MemCache::default();
        let mut config = MemConfig::with_default("echo");
        config.set_provider_key("echo", "").unwrap();
        let mut svc = svc_with(
            cache,
            config,
            vec![Box::new(CountingProvider::new(Box::new(EchoProvider)))],
        );
        let t = svc.translate("Hello world", Lang::En, Lang::Zh).unwrap();
        assert_eq!(t.text, "译文:Hello world");
        assert_eq!(t.provider, "echo");
        assert_eq!(t.from, Lang::En);
        assert_eq!(t.to, Lang::Zh);
        // 参数只含 text/from/to：TranslationProvider::translate 签名即仅这三个参数
        // （无书路径/元数据等），由 CountingProvider::translate 的 last_* 记录覆盖断言
    }

    #[test]
    fn translate_echo_basic() {
        let cache = MemCache::default();
        let mut config = MemConfig::with_default("echo");
        config.set_provider_key("echo", "").unwrap();
        let mut svc = svc_with(cache, config, vec![Box::new(EchoProvider)]);
        let t = svc.translate("Hello world", Lang::En, Lang::Zh).unwrap();
        assert_eq!(t.text, "译文:Hello world");
        assert_eq!(t.provider, "echo");
    }

    #[test]
    fn translate_normalizes_text_before_provider() {
        // US-9 第 2 句：跨行空白折叠后传给 Provider
        let cache = MemCache::default();
        let mut config = MemConfig::with_default("echo");
        config.set_provider_key("echo", "").unwrap();
        let mut svc = svc_with(cache, config, vec![Box::new(EchoProvider)]);
        let t = svc.translate("Hello\n  world\t  again", Lang::En, Lang::Zh).unwrap();
        assert_eq!(t.text, "译文:Hello world again");
    }

    #[test]
    fn translate_cache_hit_no_second_provider_call() {
        // US-10：同文+同语言对+同 Provider 连续 2 次 → Provider 计数 == 1
        let cache = MemCache::default();
        let mut config = MemConfig::with_default("shared-count");
        config.set_provider_key("shared-count", "").unwrap();
        let calls = std::sync::Arc::new(std::sync::atomic::AtomicU32::new(0));
        let mut svc = svc_with(
            cache,
            config,
            vec![Box::new(SharedCounting {
                calls: calls.clone(),
                inner: Box::new(EchoProvider),
            })],
        );
        let t1 = svc.translate("Hello world", Lang::En, Lang::Zh).unwrap();
        let start = Instant::now();
        let t2 = svc.translate("Hello world", Lang::En, Lang::Zh).unwrap();
        let hit_ms = start.elapsed().as_millis();
        assert_eq!(t1, t2, "两次返回一致");
        assert!(hit_ms <= 100, "缓存命中应 ≤100ms（CI 上限），实测 {hit_ms}ms");
        assert_eq!(
            calls.load(std::sync::atomic::Ordering::SeqCst),
            1,
            "第二次应命中缓存，Provider 只调一次"
        );
    }

    #[test]
    fn translate_miss_on_provider_or_lang_change() {
        // US-11：Provider 或语言对任一不同即 Miss
        let cache = MemCache::default();
        let mut config = MemConfig::with_default("echo");
        config.set_provider_key("echo", "").unwrap();
        config.set_provider_key("deepl", "").unwrap();
        let mut svc = svc_with(
            cache,
            config,
            vec![Box::new(EchoProvider), Box::new(DeepLStub)],
        );
        let _ = svc.translate("Hello world", Lang::En, Lang::Zh).unwrap();
        // 切默认 Provider（deepl）→ 不同 Provider → 应再调（Miss）
        svc.set_config("deepl", "").unwrap();
        let t = svc.translate("Hello world", Lang::En, Lang::Zh).unwrap();
        assert_eq!(t.provider, "deepl");
        assert_eq!(t.text, "DEEPL:Hello world");
        // 切回 echo + 不同语言对 → Miss
        svc.set_config("echo", "").unwrap();
        let t = svc.translate("Hello world", Lang::Zh, Lang::En).unwrap();
        assert_eq!(t.text, "译文:Hello world");
    }

    #[test]
    fn translate_no_key_is_not_configured() {
        // US-12：未配置 key → Err 含"未配置/API Key"
        let cache = MemCache::default();
        let config = MemConfig::with_default("deepl"); // deepl 无 key
        let mut svc = svc_with(cache, config, vec![Box::new(DeepLStub)]);
        let err = svc.translate("hello", Lang::En, Lang::Zh).unwrap_err();
        assert!(matches!(err, Error::NotConfigured(_)), "应 NotConfigured: {err}");
        let msg = err.to_string();
        assert!(msg.contains("API Key"), "应含 API Key: {msg}");
    }

    #[test]
    fn translate_failing_provider_no_cache_write_and_keeps_text() {
        // US-12：FailingProvider → Err 含网络/失败语义且携带原文；重复失败不写缓存
        let cache = MemCache::default();
        let mut config = MemConfig::with_default("failing");
        config.set_provider_key("failing", "x").unwrap();
        let mut svc = svc_with(
            cache,
            config,
            vec![Box::new(FailingProvider { detail: "模拟断网".into() })],
        );
        let err = svc.translate("原文文本", Lang::En, Lang::Zh).unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("网络") || msg.contains("失败"), "应含网络/失败: {msg}");
        assert!(msg.contains("原文文本"), "错误应携带原文本: {msg}");
        // 重复失败 → 缓存行数不变（0）
        let _ = svc.translate("原文文本", Lang::En, Lang::Zh).unwrap_err();
        assert_eq!(svc.cache.cache_count().unwrap(), 0, "失败不写缓存");
    }

    #[test]
    fn translate_retry_after_config_succeeds() {
        // US-12 末句：失败后再配置可用 Provider → 重试同一文本成功
        let cache = MemCache::default();
        let config = MemConfig::with_default("failing");
        let mut svc = svc_with(
            cache,
            config,
            vec![
                Box::new(FailingProvider { detail: "x".into() }),
                Box::new(EchoProvider),
            ],
        );
        assert!(svc.translate("hello", Lang::En, Lang::Zh).is_err());
        svc.set_config("echo", "").unwrap();
        let t = svc.translate("hello", Lang::En, Lang::Zh).unwrap();
        assert_eq!(t.text, "译文:hello");
    }

    #[test]
    fn translate_clear_cache_and_repopulate() {
        // US-13：清空 → 行数 0；再翻同文 → 重新调 Provider
        let cache = MemCache::default();
        let mut config = MemConfig::with_default("echo");
        config.set_provider_key("echo", "").unwrap();
        let mut svc = svc_with(cache, config, vec![Box::new(EchoProvider)]);
        svc.translate("hello", Lang::En, Lang::Zh).unwrap();
        svc.translate("world", Lang::En, Lang::Zh).unwrap();
        assert_eq!(svc.cache.cache_count().unwrap(), 2);
        svc.clear_cache().unwrap();
        assert_eq!(svc.cache.cache_count().unwrap(), 0);
        let (t, from_cache) = svc.translate_cached("hello", Lang::En, Lang::Zh).unwrap();
        assert!(!from_cache, "清空后重新调 Provider");
        assert_eq!(t.text, "译文:hello");
    }

    #[test]
    fn translate_cached_flag_and_hit_count() {
        let cache = MemCache::default();
        let mut config = MemConfig::with_default("echo");
        config.set_provider_key("echo", "").unwrap();
        let mut svc = svc_with(cache, config, vec![Box::new(EchoProvider)]);
        let (_, hit1) = svc.translate_cached("hello", Lang::En, Lang::Zh).unwrap();
        assert!(!hit1);
        let (t, hit2) = svc.translate_cached("hello", Lang::En, Lang::Zh).unwrap();
        assert!(hit2, "第二次应命中缓存");
        assert_eq!(t.text, "译文:hello");
        // hit_count 递增（US-13 表结构 hit_count 语义）
        let key = CacheKey {
            source_text: "hello".into(),
            from_lang: Lang::En,
            to_lang: Lang::Zh,
            provider: "echo".into(),
        };
        let entry = svc.cache.cache_get(&key).unwrap().expect("应有缓存");
        assert_eq!(entry.hit_count, 2, "命中一次后 hit_count==2");
    }

    #[test]
    fn translate_set_config_updates_provider_and_key() {
        let cache = MemCache::default();
        let config = MemConfig::with_default("deepl");
        let mut svc = svc_with(
            cache,
            config,
            vec![Box::new(DeepLStub), Box::new(EchoProvider)],
        );
        // 默认 deepl 无 key → NotConfigured
        assert!(svc.translate("hi", Lang::En, Lang::Zh).is_err());
        svc.set_config("echo", "").unwrap();
        let t = svc.translate("hi", Lang::En, Lang::Zh).unwrap();
        assert_eq!(t.provider, "echo");
    }

    #[test]
    fn translate_created_at_is_recent_epoch() {
        // 杀死 translation.rs:468 now_unix 恒 0/1/-1 三个变异：缓存行 created_at
        // 必须为当前 unix 秒（docs/04 §5 created_at 语义）
        let cache = MemCache::default();
        let mut config = MemConfig::with_default("echo");
        config.set_provider_key("echo", "").unwrap();
        let mut svc = svc_with(cache, config, vec![Box::new(EchoProvider)]);
        svc.translate("hello", Lang::En, Lang::Zh).unwrap();
        let key = CacheKey {
            source_text: "hello".into(),
            from_lang: Lang::En,
            to_lang: Lang::Zh,
            provider: "echo".into(),
        };
        let entry = svc.cache.cache_get(&key).unwrap().expect("应有缓存");
        assert!(
            entry.created_at > 1_700_000_000,
            "created_at 应为当前 unix 秒（≥2023-11），实测 {}",
            entry.created_at
        );
    }

    #[test]
    fn set_config_configure_only_target_provider() {
        // 杀死 translation.rs:441 `==`→`!=`：set_config 只应 configure 目标 Provider。
        // gate-a 未 configure 前 translate 失败；set_config("gate-a") 后仅 gate-a 有 key → 成功。
        let cache = MemCache::default();
        let mut config = MemConfig::with_default("gate-a");
        config.set_provider_key("gate-a", "k").unwrap();
        let mut svc = svc_with(
            cache,
            config,
            vec![
                Box::new(KeyGateProvider::new("gate-a")),
                Box::new(KeyGateProvider::new("gate-b")),
            ],
        );
        assert!(
            matches!(svc.translate("hi", Lang::En, Lang::Zh).unwrap_err(), Error::NotConfigured(_)),
            "set_config 前 gate-a 实例应未配置"
        );
        svc.set_config("gate-a", "k").unwrap();
        let t = svc.translate("hi", Lang::En, Lang::Zh).unwrap();
        assert_eq!(t.text, "OK:hi", "仅 gate-a 应被 configure（!= 变异会把 key 配给 gate-b）");
    }

    // ---------- REQ-006：auto 路由 / 回退 / 文案 / 配置视图 / 策略 ----------

    /// 可用的离线 Provider stub（needs_key=false）。
    struct OfflineStub;
    impl TranslationProvider for OfflineStub {
        fn name(&self) -> &str {
            "offline"
        }
        fn needs_key(&self) -> bool {
            false
        }
        fn translate(&self, text: &str, from: Lang, to: Lang) -> Result<Translation> {
            Ok(Translation {
                text: format!("OFF:{text}"),
                from,
                to,
                provider: "offline".into(),
            })
        }
    }

    /// 离线未命中（NotConfigured），用于组合错误断言。
    struct MissingOffline;
    impl TranslationProvider for MissingOffline {
        fn name(&self) -> &str {
            "offline"
        }
        fn needs_key(&self) -> bool {
            false
        }
        fn translate(&self, _t: &str, _f: Lang, _to: Lang) -> Result<Translation> {
            Err(Error::NotConfigured(
                "离线翻译未命中（请先安装内置词库）".to_string(),
            ))
        }
    }

    /// 在线失败（Network），用于回退失败断言。
    struct FailingDeepL;
    impl TranslationProvider for FailingDeepL {
        fn name(&self) -> &str {
            "deepl"
        }
        fn translate(&self, text: &str, _f: Lang, _to: Lang) -> Result<Translation> {
            Err(Error::Network {
                detail: "模拟断网".to_string(),
                source_text: text.to_string(),
            })
        }
    }

    #[derive(Clone, Default)]
    struct Recorder {
        text: std::sync::Arc<std::sync::Mutex<Option<String>>>,
        from: std::sync::Arc<std::sync::Mutex<Option<Lang>>>,
        to: std::sync::Arc<std::sync::Mutex<Option<Lang>>>,
    }

    struct RecordingDeepL {
        rec: Recorder,
    }
    impl TranslationProvider for RecordingDeepL {
        fn name(&self) -> &str {
            "deepl"
        }
        fn translate(&self, text: &str, from: Lang, to: Lang) -> Result<Translation> {
            *self.rec.text.lock().unwrap() = Some(text.to_string());
            *self.rec.from.lock().unwrap() = Some(from);
            *self.rec.to.lock().unwrap() = Some(to);
            Ok(Translation {
                text: format!("DEEPL:{text}"),
                from,
                to,
                provider: "deepl".into(),
            })
        }
    }

    #[test]
    fn translate_auto_prefers_online_when_key_configured() {
        // US-10：已配置 key → 在线（deepl）优先，provider 为真实名、from_cache=false
        let mut config = MemConfig::with_default(AUTO_PROVIDER);
        config.set_provider_key("deepl", "k").unwrap();
        let mut svc = svc_with(
            MemCache::default(),
            config,
            vec![Box::new(DeepLStub), Box::new(OfflineStub)],
        );
        let r = svc.translate_routed("Hello", Lang::En, Lang::Zh).unwrap();
        assert_eq!(r.translation.provider, "deepl");
        assert_eq!(r.translation.text, "DEEPL:Hello");
        assert!(!r.from_cache);
        assert!(r.fallback_reason.is_none());
        // 二次命中 deepl 缓存（US-12），不再回退
        let r2 = svc.translate_routed("Hello", Lang::En, Lang::Zh).unwrap();
        assert!(r2.from_cache);
        assert!(r2.fallback_reason.is_none());
    }

    #[test]
    fn translate_auto_without_key_falls_back_offline_with_reason() {
        // US-13：未配置任何在线 key → 走 offline，不 NotConfigured；带"未配置…回退"原因
        let mut svc = svc_with(
            MemCache::default(),
            MemConfig::with_default(AUTO_PROVIDER),
            vec![Box::new(DeepLStub), Box::new(OfflineStub)],
        );
        let r = svc.translate_routed("book", Lang::En, Lang::Zh).unwrap();
        assert_eq!(r.translation.provider, "offline");
        assert_eq!(r.translation.text, "OFF:book");
        assert!(!r.from_cache);
        assert_eq!(
            r.fallback_reason.as_deref(),
            Some(FALLBACK_REASON_ONLINE_UNCONFIGURED)
        );
        // 二次命中 offline 缓存
        let r2 = svc.translate_routed("book", Lang::En, Lang::Zh).unwrap();
        assert!(r2.from_cache);
        assert_eq!(
            r2.fallback_reason.as_deref(),
            Some(FALLBACK_REASON_ONLINE_UNCONFIGURED)
        );
    }

    #[test]
    fn translate_auto_online_failure_falls_back_offline_with_reason() {
        // US-17：在线失败 + 离线命中 → offline 结果 + "在线失败，已回退离线"
        let mut config = MemConfig::with_default(AUTO_PROVIDER);
        config.set_provider_key("deepl", "k").unwrap();
        let mut svc = svc_with(
            MemCache::default(),
            config,
            vec![Box::new(FailingDeepL), Box::new(OfflineStub)],
        );
        let r = svc.translate_routed("book", Lang::En, Lang::Zh).unwrap();
        assert_eq!(r.translation.provider, "offline");
        assert_eq!(
            r.fallback_reason.as_deref(),
            Some(FALLBACK_REASON_ONLINE_FAILED)
        );
    }

    #[test]
    fn translate_auto_unconfigured_and_offline_miss_message() {
        // US-16：无 key + 离线未命中 → 错误同时含两句语义；失败不写缓存
        let mut svc = svc_with(
            MemCache::default(),
            MemConfig::with_default(AUTO_PROVIDER),
            vec![Box::new(DeepLStub), Box::new(MissingOffline)],
        );
        let err = svc.translate_routed("原文", Lang::En, Lang::Zh).unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("未配置在线翻译 API Key"), "msg={msg}");
        assert!(msg.contains("离线翻译未命中"), "msg={msg}");
        assert_eq!(svc.cache.cache_count().unwrap(), 0, "失败不写缓存");
    }

    #[test]
    fn translate_auto_online_failure_and_offline_miss_message_keeps_text() {
        // US-17/US-19：在线失败 + 离线未命中 → 组合错误含原因与原文
        let mut config = MemConfig::with_default(AUTO_PROVIDER);
        config.set_provider_key("deepl", "k").unwrap();
        let mut svc = svc_with(
            MemCache::default(),
            config,
            vec![Box::new(FailingDeepL), Box::new(MissingOffline)],
        );
        let err = svc.translate_routed("原文文本", Lang::En, Lang::Zh).unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("在线翻译失败"), "msg={msg}");
        assert!(msg.contains("离线翻译未命中"), "msg={msg}");
        assert!(msg.contains("原文文本"), "错误应携带原文: {msg}");
        assert_eq!(svc.cache.cache_count().unwrap(), 0, "失败不写缓存");
    }

    #[test]
    fn translate_auto_normalizes_paragraph_and_passes_only_args() {
        // US-11（跨行折叠）+ US-20（Provider 入参只含 text/from/to）
        let rec = Recorder::default();
        let mut config = MemConfig::with_default(AUTO_PROVIDER);
        config.set_provider_key("deepl", "k").unwrap();
        let mut svc = svc_with(
            MemCache::default(),
            config,
            vec![
                Box::new(RecordingDeepL { rec: rec.clone() }),
                Box::new(OfflineStub),
            ],
        );
        let r = svc
            .translate_routed("Hello\n  world\t  again", Lang::En, Lang::Zh)
            .unwrap();
        assert_eq!(r.translation.text, "DEEPL:Hello world again");
        assert_eq!(
            rec.text.lock().unwrap().as_deref(),
            Some("Hello world again"),
            "跨行空白应折叠后整段传给 Provider"
        );
        assert_eq!(*rec.from.lock().unwrap(), Some(Lang::En));
        assert_eq!(*rec.to.lock().unwrap(), Some(Lang::Zh));
    }

    #[test]
    fn config_view_reports_provider_and_deepl_key_state() {
        // US-15：读配置视图（provider + has_deepl_key），空串视为未配置
        let mut svc = svc_with(
            MemCache::default(),
            MemConfig::with_default(AUTO_PROVIDER),
            vec![
                Box::new(crate::dict::DeepLProvider::new()),
                Box::new(OfflineStub),
            ],
        );
        let v = svc.config_view().unwrap();
        assert_eq!(v.provider, AUTO_PROVIDER);
        assert!(!v.has_deepl_key);
        svc.set_config("deepl", "real-key").unwrap();
        let v = svc.config_view().unwrap();
        assert_eq!(v.provider, "deepl");
        assert!(v.has_deepl_key);
        svc.set_config("deepl", "").unwrap();
        assert!(!svc.config_view().unwrap().has_deepl_key, "空串视为未配置");
    }

    #[test]
    fn set_strategy_accepts_auto_and_registered_rejects_unknown() {
        let mut svc = svc_with(
            MemCache::default(),
            MemConfig::with_default(AUTO_PROVIDER),
            vec![Box::new(DeepLStub), Box::new(OfflineStub)],
        );
        svc.set_strategy("offline").unwrap();
        assert_eq!(svc.config.default_provider().unwrap(), "offline");
        svc.set_strategy(AUTO_PROVIDER).unwrap();
        assert_eq!(svc.config.default_provider().unwrap(), AUTO_PROVIDER);
        let err = svc.set_strategy("nope").unwrap_err();
        assert!(err.to_string().contains("未知翻译策略"), "{err}");
    }

    #[test]
    fn translate_explicit_online_falls_back_offline_with_reason() {
        // 显式 deepl + 断网 → 回退 offline 并带原因（决策点1 契约）
        let mut config = MemConfig::with_default("deepl");
        config.set_provider_key("deepl", "k").unwrap();
        let mut svc = svc_with(
            MemCache::default(),
            config,
            vec![Box::new(FailingDeepL), Box::new(OfflineStub)],
        );
        let r = svc.translate_routed("book", Lang::En, Lang::Zh).unwrap();
        assert_eq!(r.translation.provider, "offline");
        assert_eq!(
            r.fallback_reason.as_deref(),
            Some(FALLBACK_REASON_ONLINE_FAILED)
        );
    }

    #[test]
    fn translate_explicit_unknown_provider_is_error() {
        // 覆盖 translate_explicit 未知 provider 防御分支（配置被外部写脏时）
        let mut svc = svc_with(
            MemCache::default(),
            MemConfig::with_default("nope"),
            vec![Box::new(OfflineStub)],
        );
        let err = svc.translate_routed("hi", Lang::En, Lang::Zh).unwrap_err();
        assert!(err.to_string().contains("未知翻译 Provider"), "{err}");
    }

    #[test]
    fn translate_explicit_missing_key_falls_back_offline_unconfigured_reason() {
        // 显式 deepl 无 key + offline 可用 → 回退原因应为"未配置…"（missing 分支）
        let mut svc = svc_with(
            MemCache::default(),
            MemConfig::with_default("deepl"),
            vec![Box::new(DeepLStub), Box::new(OfflineStub)],
        );
        let r = svc.translate_routed("book", Lang::En, Lang::Zh).unwrap();
        assert_eq!(r.translation.provider, "offline");
        assert!(!r.from_cache);
        assert_eq!(
            r.fallback_reason.as_deref(),
            Some(FALLBACK_REASON_ONLINE_UNCONFIGURED)
        );
    }

    #[test]
    fn translate_explicit_missing_key_offline_cache_hit_with_reason() {
        // 预置 offline 缓存 → 显式 deepl 无 key 回退时命中 offline 缓存并带原因
        let mut cache = MemCache::default();
        cache
            .cache_put(&CacheEntry {
                key: CacheKey {
                    source_text: "book".into(),
                    from_lang: Lang::En,
                    to_lang: Lang::Zh,
                    provider: "offline".into(),
                },
                result: Translation {
                    text: "OFF-CACHED".into(),
                    from: Lang::En,
                    to: Lang::Zh,
                    provider: "offline".into(),
                },
                created_at: 1,
                hit_count: 1,
            })
            .unwrap();
        let mut svc = svc_with(
            cache,
            MemConfig::with_default("deepl"),
            vec![Box::new(DeepLStub), Box::new(OfflineStub)],
        );
        let r = svc.translate_routed("book", Lang::En, Lang::Zh).unwrap();
        assert_eq!(r.translation.text, "OFF-CACHED");
        assert!(r.from_cache);
        assert_eq!(
            r.fallback_reason.as_deref(),
            Some(FALLBACK_REASON_ONLINE_UNCONFIGURED)
        );
    }

    #[test]
    fn config_view_without_deepl_provider_uses_key_fallback() {
        // 未注册 deepl provider → has_deepl_key 走 key 非空兜底闭包（空白=false/非空=true）
        let mut config = MemConfig::with_default(AUTO_PROVIDER);
        config.set_provider_key("deepl", "   ").unwrap();
        let svc = svc_with(MemCache::default(), config, vec![Box::new(OfflineStub)]);
        assert!(!svc.config_view().unwrap().has_deepl_key, "空白 key=false");

        let mut config2 = MemConfig::with_default(AUTO_PROVIDER);
        config2.set_provider_key("deepl", "k").unwrap();
        let svc2 = svc_with(MemCache::default(), config2, vec![Box::new(OfflineStub)]);
        assert!(svc2.config_view().unwrap().has_deepl_key, "非空 key=true");
    }
}
