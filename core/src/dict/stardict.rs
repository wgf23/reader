//! StarDict 词库解析内核（.ifo / .idx / .dict(.dz)）。
//!
//! 设计：REQ-003 02-design §2.3；格式规范见 StarDict FileFormat（huzheng001/stardict-3）。
//! 原则（US-6）：任何坏词库（截断/偏移越界/缺 wordcount/.dz 损坏）→ 结构化 `Err(Corrupt)`，
//! 绝不 panic；未知类型码跳过不崩溃（01-req §5 风险2）。
//! 纯解析无网络；.dict.dz 为整文件 gzip 流，安装期流式解压落盘（ADR 关联裁定5）。

use std::fs::File;
use std::io::{BufReader, Read, Write};
use std::path::Path;

use flate2::read::GzDecoder;

use crate::dict::DictEntry;
use crate::error::{Error, Result};

/// .ifo 元数据（缺失容错；wordcount 缺失 → Corrupt，US-6）
#[derive(Debug)]
pub(crate) struct IfoMeta {
    pub bookname: String,
    pub wordcount: u64,
    pub idxfilesize: Option<u64>,
    pub sametypesequence: Option<String>,
}

/// .idx 条目（word + .dict 内偏移/长度）
#[derive(Debug)]
pub(crate) struct IdxEntry {
    pub word: String,
    pub offset: u32,
    pub size: u32,
}

/// 解析 .ifo：`key=value` 行；`wordcount` 必填（缺失 → Corrupt）。
pub(crate) fn parse_ifo(path: &Path) -> Result<IfoMeta> {
    let text = std::fs::read_to_string(path).map_err(Error::Io)?;
    let mut bookname = String::new();
    let mut wordcount: Option<u64> = None;
    let mut idxfilesize: Option<u64> = None;
    let mut sametypesequence: Option<String> = None;
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((k, v)) = line.split_once('=') else { continue };
        match k.trim() {
            "bookname" => bookname = v.trim().to_string(),
            "wordcount" => {
                wordcount = v.trim().parse::<u64>().ok().or(wordcount);
            }
            "idxfilesize" => {
                idxfilesize = v.trim().parse::<u64>().ok().or(idxfilesize);
            }
            "sametypesequence" => sametypesequence = Some(v.trim().to_string()),
            _ => {}
        }
    }
    let wordcount = wordcount
        .ok_or_else(|| Error::Corrupt(format!("词库 .ifo 缺少 wordcount 字段: {}", path.display())))?;
    if bookname.is_empty() {
        bookname = path
            .file_stem()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_else(|| "未命名词库".to_string());
    }
    Ok(IfoMeta {
        bookname,
        wordcount,
        idxfilesize,
        sametypesequence,
    })
}

/// 加载 .idx 全量入内存（langdao 级 ~1-2MB；保存原序）。
/// 条目格式：word(UTF-8) \0 + offset(u32 BE) + size(u32 BE)。
/// 尾部残字节：全 0 视为填充忽略；非 0 残片 → Corrupt（.idx 截断，US-6）。
pub(crate) fn load_idx(idx_bytes: &[u8]) -> Result<Vec<IdxEntry>> {
    let mut out = Vec::new();
    let mut pos = 0usize;
    while pos < idx_bytes.len() {
        // 尾部全 0 视为填充忽略（部分工具生成的 idx 带对齐 padding）
        if idx_bytes[pos..].iter().all(|&b| b == 0) {
            break;
        }
        let nul = match idx_bytes[pos..].iter().position(|&b| b == 0) {
            Some(n) => pos + n,
            None => {
                return Err(Error::Corrupt("词库 .idx 条目缺少 word 终止符（截断）".into()));
            }
        };
        let word = String::from_utf8_lossy(&idx_bytes[pos..nul]).into_owned();
        let tail_start = nul + 1;
        if tail_start + 8 > idx_bytes.len() {
            return Err(Error::Corrupt("词库 .idx 条目偏移/长度字段截断".into()));
        }
        let offset = u32::from_be_bytes([
            idx_bytes[tail_start],
            idx_bytes[tail_start + 1],
            idx_bytes[tail_start + 2],
            idx_bytes[tail_start + 3],
        ]);
        let size = u32::from_be_bytes([
            idx_bytes[tail_start + 4],
            idx_bytes[tail_start + 5],
            idx_bytes[tail_start + 6],
            idx_bytes[tail_start + 7],
        ]);
        out.push(IdxEntry { word, offset, size });
        pos = tail_start + 8;
    }
    Ok(out)
}

/// 查词：二分精确命中；未中则线性扫描做"首字母大小写归一 / 全小写 / 忽略大小写"匹配
/// （US-5；n≤10^5 实测 <1ms）。
pub(crate) fn lookup_entry<'a>(idx: &'a [IdxEntry], word: &str) -> Option<&'a IdxEntry> {
    if let Ok(found) = idx.binary_search_by(|e| e.word.as_bytes().cmp(word.as_bytes())) {
        return Some(&idx[found]);
    }
    // 线性扫描归一匹配
    let lower = word.to_lowercase();
    let mut first_flipped = String::new();
    if let Some(c) = word.chars().next() {
        if c.is_ascii_alphabetic() {
            let mut s = word.to_string();
            let rep = if c.is_ascii_lowercase() {
                c.to_ascii_uppercase()
            } else {
                c.to_ascii_lowercase()
            };
            s.replace_range(0..c.len_utf8(), &rep.to_string());
            first_flipped = s;
        }
    }
    for e in idx {
        if e.word == word
            || e.word == lower
            || (!first_flipped.is_empty() && e.word == first_flipped)
            || e.word.eq_ignore_ascii_case(word)
        {
            return Some(e);
        }
    }
    None
}

/// 按 sametypesequence 解析 .dict 区段（offset..offset+size）：
/// 类型码 t→phonetic、m→definition(纯文本)、g→definition(HTML)、x→example；
/// 未知类型码读到 \0 跳过（末字段读到区段尾）；区段越界/截断 → Err(Corrupt)。
/// sametypesequence 为空（旧格式）时：每个字段为 [类型码][数据]\0。
pub(crate) fn parse_entry(seq: &[u8], dict_bytes: &[u8], e: &IdxEntry) -> Result<DictEntry> {
    let start = e.offset as usize;
    let end = (e.offset as usize)
        .checked_add(e.size as usize)
        .ok_or_else(|| Error::Corrupt(format!("词条偏移溢出: {}", e.word)))?;
    if end > dict_bytes.len() {
        return Err(Error::Corrupt(format!(
            "词条区段越界: {} (offset={} size={} dict_len={})",
            e.word,
            e.offset,
            e.size,
            dict_bytes.len()
        )));
    }
    let region = &dict_bytes[start..end];

    let mut phonetic: Option<String> = None;
    let mut definitions: Vec<String> = Vec::new();
    let mut example: Option<String> = None;

    if seq.is_empty() {
        // 旧格式：每字段 [类型码][NUL 终止数据]
        let mut pos = 0usize;
        while pos < region.len() {
            let code = region[pos];
            pos += 1;
            let (field, next) = take_field(region, pos, true);
            pos = next;
            match code {
                b't' => phonetic = non_empty(field),
                b'g' | b'm' => definitions.push(String::from_utf8_lossy(field).into_owned()),
                b'x' => example = non_empty(field),
                _ => {} // 未知类型码跳过不崩溃
            }
        }
    } else {
        // sametypesequence 非空：字段按序拼接，非末字段 NUL 终止，末字段止于区段尾
        let n = seq.len();
        let mut pos = 0usize;
        for (i, code) in seq.iter().enumerate() {
            let is_last = i == n - 1;
            let (field, next) = take_field(region, pos, is_last);
            pos = next;
            match *code {
                b't' => phonetic = non_empty(field),
                b'g' | b'm' => definitions.push(String::from_utf8_lossy(field).into_owned()),
                b'x' => example = non_empty(field),
                _ => {} // 未知类型码跳过不崩溃（US-6 风险2）
            }
        }
    }

    let definition = definitions.join("\n");
    Ok(DictEntry {
        word: e.word.clone(),
        phonetic,
        pos: crate::dict::extract_pos(&definition),
        definition,
        example,
    })
}

/// 从 `from` 起取一个字段：到 \0 或区段尾（is_last 时容忍尾部无 NUL）。
/// 返回 (字段文本, 下一位置)。
fn take_field(region: &[u8], from: usize, is_last: bool) -> (&[u8], usize) {
    if from >= region.len() {
        return (b"", from);
    }
    let rel = region[from..].iter().position(|&b| b == 0);
    match rel {
        Some(n) if !is_last => (&region[from..from + n], from + n + 1),
        Some(n) => {
            // 末字段：到 NUL 或区段尾，取较短者（兼容末尾带/不带 NUL）
            let end = from + n;
            let (field, next) = (&region[from..end], end);
            if next >= region.len() {
                (field, next)
            } else {
                (field, next + 1)
            }
        }
        None => (&region[from..], region.len()),
    }
}

fn non_empty(s: &[u8]) -> Option<String> {
    let t = String::from_utf8_lossy(s).into_owned();
    if t.is_empty() {
        None
    } else {
        Some(t)
    }
}

/// .dict.dz（整文件 gzip）流式解压为 .dict 落盘（安装期一次性；无内存峰值，ADR 关联裁定5）。
pub(crate) fn decompress_dz(src: &Path, dst: &Path) -> Result<()> {
    let file = File::open(src).map_err(Error::Io)?;
    let mut decoder = GzDecoder::new(BufReader::new(file));
    let mut out = File::create(dst).map_err(Error::Io)?;
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = decoder.read(&mut buf).map_err(|_| {
            Error::Corrupt(format!("词库 .dz gzip 流损坏: {}", src.display()))
        })?;
        if n == 0 {
            break;
        }
        out.write_all(&buf[..n]).map_err(Error::Io)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_idx_bytes(entries: &[(&str, u32, u32)]) -> Vec<u8> {
        let mut b = Vec::new();
        for (w, off, size) in entries {
            b.extend_from_slice(w.as_bytes());
            b.push(0);
            b.extend_from_slice(&off.to_be_bytes());
            b.extend_from_slice(&size.to_be_bytes());
        }
        b
    }

    #[test]
    fn load_idx_parses_entries_in_order() {
        let bytes = sample_idx_bytes(&[("apple", 10, 20), ("book", 30, 40)]);
        let idx = load_idx(&bytes).unwrap();
        assert_eq!(idx.len(), 2);
        assert_eq!(idx[0].word, "apple");
        assert_eq!(idx[0].offset, 10);
        assert_eq!(idx[0].size, 20);
        assert_eq!(idx[1].word, "book");
    }

    #[test]
    fn load_idx_truncated_mid_entry_is_corrupt() {
        // 截断在最后条目 offset/size 字段中间（非全 0 残片）
        let mut bytes = sample_idx_bytes(&[("apple", 10, 20), ("book", 30, 40)]);
        bytes.truncate(bytes.len() - 4);
        let err = load_idx(&bytes).unwrap_err();
        assert!(matches!(err, Error::Corrupt(_)), "应 Corrupt: {err}");
    }

    #[test]
    fn load_idx_missing_nul_is_corrupt() {
        let bytes = b"no-nul-terminator-here";
        let err = load_idx(bytes).unwrap_err();
        assert!(matches!(err, Error::Corrupt(_)));
    }

    #[test]
    fn load_idx_zero_padding_tail_ignored() {
        let mut bytes = sample_idx_bytes(&[("apple", 10, 20)]);
        bytes.extend_from_slice(&[0, 0, 0, 0]);
        let idx = load_idx(&bytes).unwrap();
        assert_eq!(idx.len(), 1);
    }

    #[test]
    fn lookup_binary_exact_and_case_normalization() {
        let bytes = sample_idx_bytes(&[
            ("Apple", 0, 4),
            ("book", 8, 4),
            ("zebra", 16, 4),
        ]);
        let idx = load_idx(&bytes).unwrap();
        // 精确命中（二进制搜索）
        assert_eq!(lookup_entry(&idx, "book").unwrap().word, "book");
        // 首字母归一：索引存 "Apple"，查 "apple"
        assert_eq!(lookup_entry(&idx, "apple").unwrap().word, "Apple");
        // 首字母归一反向：索引存 "apple" 场景由上面覆盖；全小写/忽略大小写
        assert_eq!(lookup_entry(&idx, "ZEBRA").unwrap().word, "zebra");
        // 未收录
        assert!(lookup_entry(&idx, "zzzqqq").is_none());
    }

    fn dict_with_seq(seq: &[u8], data: &[u8]) -> DictEntry {
        let e = IdxEntry {
            word: "w".into(),
            offset: 0,
            size: data.len() as u32,
        };
        parse_entry(seq, data, &e).unwrap()
    }

    #[test]
    fn parse_entry_tgm_fields_in_place() {
        // t\0 g\0 m(末字段，无尾 NUL)
        let data = "/pho/\0<b>n.</b> A fruit\0n. 苹果".as_bytes();
        let entry = dict_with_seq(b"tgm", data);
        assert_eq!(entry.phonetic.as_deref(), Some("/pho/"));
        assert_eq!(entry.definition, "<b>n.</b> A fruit\nn. 苹果");
        assert_eq!(entry.pos.as_deref(), Some("n."));
        assert_eq!(entry.example, None);
    }

    #[test]
    fn parse_entry_tgmx_example_field() {
        let data = "/pho/\0<b>n.</b> X\0n. 释义\0an example sentence".as_bytes();
        let entry = dict_with_seq(b"tgmx", data);
        assert_eq!(entry.phonetic.as_deref(), Some("/pho/"));
        assert_eq!(entry.example.as_deref(), Some("an example sentence"));
    }

    #[test]
    fn parse_entry_empty_phonetic_is_none() {
        let data = "\0<b>n.</b> X\0n. 释义".as_bytes();
        let entry = dict_with_seq(b"tgm", data);
        assert_eq!(entry.phonetic, None);
    }

    #[test]
    fn parse_entry_unknown_type_code_skipped() {
        // tgz：z 为未知类型码（末字段，读到区段尾）→ 跳过不崩溃
        let data = b"/pho/\0<b>n.</b> X\0some unknown payload";
        let entry = dict_with_seq(b"tgz", data);
        assert_eq!(entry.phonetic.as_deref(), Some("/pho/"));
        assert_eq!(entry.definition, "<b>n.</b> X");
        assert_eq!(entry.example, None);
    }

    #[test]
    fn parse_entry_empty_seq_old_format() {
        // 旧格式：每字段 [类型码][数据]\0；末字段无尾 NUL
        let data = "t/pho/\0g<b>n.</b> X\0m纯文本释义".as_bytes();
        let entry = dict_with_seq(b"", data);
        assert_eq!(entry.phonetic.as_deref(), Some("/pho/"));
        assert_eq!(entry.definition, "<b>n.</b> X\n纯文本释义");
    }

    #[test]
    fn parse_entry_region_out_of_bounds_is_corrupt() {
        let e = IdxEntry {
            word: "oob".into(),
            offset: 0,
            size: 9999,
        };
        let err = parse_entry(b"m", b"short", &e).unwrap_err();
        assert!(matches!(err, Error::Corrupt(_)), "应 Corrupt: {err}");
    }

    #[test]
    fn parse_ifo_requires_wordcount() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("a.ifo");
        std::fs::write(&p, "version=2.4.2\nbookname=X\n").unwrap();
        let err = parse_ifo(&p).unwrap_err();
        assert!(matches!(err, Error::Corrupt(_)), "应 Corrupt: {err}");
    }

    #[test]
    fn parse_ifo_full() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("a.ifo");
        std::fs::write(
            &p,
            "StarDict's dict ifo file\nversion=2.4.2\nbookname=Langdao\nwordcount=42\nidxfilesize=1024\nsametypesequence=tgm\n",
        )
        .unwrap();
        let meta = parse_ifo(&p).unwrap();
        assert_eq!(meta.bookname, "Langdao");
        assert_eq!(meta.wordcount, 42);
        assert_eq!(meta.idxfilesize, Some(1024));
        assert_eq!(meta.sametypesequence.as_deref(), Some("tgm"));
    }

    #[test]
    fn decompress_dz_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let src = dir.path().join("t.dict.dz");
        let dst = dir.path().join("t.dict");
        let data = b"hello world gzip payload";
        let mut enc = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        enc.write_all(data).unwrap();
        std::fs::write(&src, enc.finish().unwrap()).unwrap();
        decompress_dz(&src, &dst).unwrap();
        assert_eq!(std::fs::read(&dst).unwrap(), data);
    }

    #[test]
    fn decompress_dz_truncated_stream_is_corrupt() {
        let dir = tempfile::tempdir().unwrap();
        let src = dir.path().join("bad.dict.dz");
        let dst = dir.path().join("bad.dict");
        let mut enc = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        enc.write_all(b"payload payload payload").unwrap();
        let full = enc.finish().unwrap();
        std::fs::write(&src, &full[..full.len() / 2]).unwrap();
        let err = decompress_dz(&src, &dst).unwrap_err();
        assert!(matches!(err, Error::Corrupt(_)), "应 Corrupt: {err}");
    }
}
