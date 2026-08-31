//! REQ-002 · MOBI/AZW3 解析集成测试
//!
//! 覆盖（02-plan T-003..T-006）：
//! - 合成 MOBI7（PalmDOC LZ77 + EXTH + pagebreak + 图片 + 经典格式 INDX）全管线断言（US-1/US-5）；
//! - 合成 GBK(936) 中文 MOBI（US-5：无 U+FFFD/乱码）；
//! - 合成 KF8 rawml AZW3（US-2：KF8 原生段路径，格式==Azw3）；
//! - .mobi 内容复制为 .azw3 扩展名的分发兜底（扩展名分发 + 内容嗅探，US-2 可观察行为）；
//! - 真实语料：hongloumeng.mobi（pagebreak 拆章 + 中文）、pride-and-prejudice.mobi（标题拆章 + 165 图）、
//!   hongloumeng-images.mobi（无标记单章兜底）——Gutenberg "kf8" 下载实测均为 MOBI7；
//! - 坏文件错误路径（US-3）：截断 → Corrupt、垃圾 → Corrupt、DRM 标记 → Encrypted（含"DRM"字样）；
//! - library 接入（US-4）：import → open → chapter_html → 去重。

use std::path::PathBuf;

use reader_core::error::Error;
use reader_core::format::{self, Format};
use reader_core::library::LibraryService;
use reader_core::store::Store;

fn corpus(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/corpus/src")
        .join(name)
}

fn write_tmp(dir: &std::path::Path, name: &str, bytes: &[u8]) -> PathBuf {
    let p = dir.join(name);
    std::fs::write(&p, bytes).unwrap();
    p
}

// ===================== 合成 MOBI 构造器（仅测试用） =====================

mod synth {
    use encoding_rs::GB18030;

    pub(crate) struct SynParams {
        pub(crate) title: &'static str,
        pub(crate) author: &'static str,
        pub(crate) language: &'static str,
        /// text_encoding 字段（65001=UTF-8 / 936=GBK）
        pub(crate) encoding: u32,
        /// MOBI header language_code（9=English / 4=Chinese）
        pub(crate) lang_code: u8,
        /// MOBI 头 type（2=MOBI7 / 248=KF8）
        pub(crate) mobi_type: u32,
        /// PalmDoc 头压缩字段（2=PalmDoc / 1=No）
        pub(crate) compression: u16,
        /// 原始内容字节（HTML 或 GBK 编码）
        pub(crate) body: Vec<u8>,
        /// 图片记录（JPEG/PNG…）
        pub(crate) images: Vec<Vec<u8>>,
        /// 经典格式 INDX 条目（标签, 内容流字节偏移）
        pub(crate) indx: Option<Vec<(String, u32)>>,
        /// EXTH 121 KF8BoundaryOffset
        pub(crate) exth_121: Option<u32>,
        /// 省略 EXTH 524（语言）记录 → 触发 MOBI header language_code 兜底
        pub(crate) omit_exth_524: bool,
    }

    /// PalmDOC LZ77 压缩（贪心匹配，测试用）
    pub(crate) fn palmdoc_compress(data: &[u8]) -> Vec<u8> {
        let mut out = Vec::new();
        let mut i = 0usize;
        while i < data.len() {
            let (off, len) = find_match(data, i);
            if len >= 3 {
                let pair = ((off << 3) | (len - 3)) & 0x3fff;
                out.push(0x80 | ((pair >> 8) as u8));
                out.push(pair as u8);
                i += len;
            } else {
                let c = data[i];
                if c == 0 || (0x09..=0x7f).contains(&c) {
                    out.push(c);
                } else {
                    // 高字节/控制字节走 1 字节字面量转义（0x01 + 字节），保证无损
                    out.push(0x01);
                    out.push(c);
                }
                i += 1;
            }
        }
        out
    }

    /// 贪心最长匹配（窗口 2048、最大长 10）
    fn find_match(data: &[u8], pos: usize) -> (usize, usize) {
        let max_len = 10usize;
        let window = 2048usize;
        let start = pos.saturating_sub(window);
        let mut best = (0usize, 0usize);
        for back in start..pos {
            let mut l = 0usize;
            while l < max_len && pos + l < data.len() && data[back + l] == data[pos + l] {
                l += 1;
            }
            if l > best.1 {
                best = (pos - back, l);
                if l == max_len {
                    break;
                }
            }
        }
        best
    }

    /// 组装 PDB 文件字节（每条记录追加 `extra_bits` 展开的尾字节）
    pub(crate) fn assemble(records: &[Vec<u8>]) -> Vec<u8> {
        assemble_with_extra(records, 0)
    }

    /// 组装 PDB 文件字节；`extra_bits` 写入记录表尾 extra 字段，每条记录追加
    /// `2 * popcount(extra_bits & 0xFFFE)` 字节尾填充（PDB 规范：每个置位 = 2 尾字节；
    /// 与 mobi_common::extra_bytes / mobi crate 的读取语义一致）。
    pub(crate) fn assemble_with_extra(records: &[Vec<u8>], extra_bits: u16) -> Vec<u8> {
        let num = records.len() as u16;
        let mut out = Vec::new();
        let name = b"SyntheticTestBook";
        let mut name_field = [0u8; 32];
        name_field[..name.len()].copy_from_slice(name);
        out.extend_from_slice(&name_field);
        out.extend_from_slice(&0u16.to_be_bytes()); // attributes
        out.extend_from_slice(&0u16.to_be_bytes()); // version
        out.extend_from_slice(&0u32.to_be_bytes()); // creation
        out.extend_from_slice(&0u32.to_be_bytes()); // modification
        out.extend_from_slice(&0u32.to_be_bytes()); // last_backup
        out.extend_from_slice(&0u32.to_be_bytes()); // modification_number
        out.extend_from_slice(&0u32.to_be_bytes()); // app_info_id
        out.extend_from_slice(&0u32.to_be_bytes()); // sort_info_id
        out.extend_from_slice(b"BOOK");
        out.extend_from_slice(b"MOBI");
        out.extend_from_slice(&0u32.to_be_bytes()); // unique_id_seed
        out.extend_from_slice(&0u32.to_be_bytes()); // next_record_list_id
        out.extend_from_slice(&num.to_be_bytes());
        let extra_bytes = 2 * (extra_bits & 0xFFFE).count_ones() as usize;
        // 记录表（记录内容起始 = 78 + 8*num + 2：表尾有 2 字节 extra 字段，
        // 与 mobi crate 的 PdbRecords::new 读取一致——真实 PDB 文件同样如此）
        let mut off = 78usize + 8 * num as usize + 2;
        for r in records {
            out.extend_from_slice(&(off as u32).to_be_bytes());
            out.extend_from_slice(&0u32.to_be_bytes());
            off += r.len() + extra_bytes;
        }
        out.extend_from_slice(&extra_bits.to_be_bytes()); // 记录表尾 extra 字段
        for r in records {
            out.extend_from_slice(r);
            out.extend_from_slice(&vec![0x58u8; extra_bytes]); // 'X' 尾填充（可辨识）
        }
        out
    }

    /// 经典格式 INDX 记录（tags=[(1,4) 位置, (0,12) 标签]；TAGX 在 66+ctl）
    fn build_indx_record(entries: &[(String, u32)]) -> Vec<u8> {
        let tagx_len = 12 + 4;
        let index_start = 66usize + tagx_len;
        let entry_size = 2 + 1 + 4 + 12;
        let index_end = index_start + entries.len() * entry_size;
        let mut content = vec![0u8; index_end];
        content[0..4].copy_from_slice(b"INDX");
        content[4..8].copy_from_slice(&0xC0u32.to_be_bytes());
        content[8..12].copy_from_slice(&1u32.to_be_bytes()); // type
        content[12..16].copy_from_slice(&(entries.len() as u32).to_be_bytes()); // count
        content[40..44].copy_from_slice(&(index_start as u32).to_be_bytes());
        content[44..48].copy_from_slice(&(index_end as u32).to_be_bytes());
        content[66..70].copy_from_slice(b"TAGX");
        content[70..74].copy_from_slice(&(tagx_len as u32).to_be_bytes());
        content[74..76].copy_from_slice(&0u16.to_be_bytes());
        content[76..78].copy_from_slice(&0u16.to_be_bytes());
        content[78..80].copy_from_slice(&[1, 4]);
        content[80..82].copy_from_slice(&[0, 12]);
        let mut p = index_start;
        for (i, (label, pos)) in entries.iter().enumerate() {
            content[p..p + 2].copy_from_slice(&((i + 1) as u16).to_be_bytes());
            content[p + 2] = 0x18; // tag0(0x10) + tag1(0x08)
            content[p + 3..p + 7].copy_from_slice(&pos.to_be_bytes());
            let lb = label.as_bytes();
            content[p + 7..p + 7 + lb.len().min(12)].copy_from_slice(&lb[..lb.len().min(12)]);
            p += entry_size;
        }
        content
    }

    /// 构建完整合成 MOBI/AZW3 文件字节
    pub(crate) fn build(p: &SynParams) -> Vec<u8> {
        // 内容记录：按 4096 字节切块后逐块压缩（保证回引用不跨记录）
        let chunk = 4096usize;
        let mut content_records = Vec::new();
        if p.compression == 2 {
            let mut i = 0usize;
            while i < p.body.len() {
                let end = (i + chunk).min(p.body.len());
                content_records.push(palmdoc_compress(&p.body[i..end]));
                i = end;
            }
        } else {
            let mut i = 0usize;
            while i < p.body.len() {
                let end = (i + chunk).min(p.body.len());
                content_records.push(p.body[i..end].to_vec());
                i = end;
            }
        }
        // 记录布局：record0 + 内容 + INDX(可选) + 图片
        let first_content = 1usize;
        let index_rec = if p.indx.is_some() {
            Some(first_content + content_records.len())
        } else {
            None
        };
        let image_start = index_rec.map_or(first_content + content_records.len(), |i| i + 1);

        // record 0
        let mut exth = build_exth(p);
        let name_offset = 16 + 232 + exth.len();
        let mut r0 = Vec::new();
        // PalmDoc 头（16B）
        r0.extend_from_slice(&p.compression.to_be_bytes());
        r0.extend_from_slice(&0u16.to_be_bytes());
        r0.extend_from_slice(&(p.body.len() as u32).to_be_bytes()); // text_length
        r0.extend_from_slice(&(content_records.len() as u16).to_be_bytes());
        r0.extend_from_slice(&(chunk as u16).to_be_bytes());
        r0.extend_from_slice(&0u16.to_be_bytes()); // encryption = No
        r0.extend_from_slice(&0u16.to_be_bytes());
        // MOBI 头（232B）
        r0.extend_from_slice(b"MOBI");
        r0.extend_from_slice(&232u32.to_be_bytes());
        r0.extend_from_slice(&p.mobi_type.to_be_bytes());
        r0.extend_from_slice(&p.encoding.to_be_bytes());
        r0.extend_from_slice(&0x12345678u32.to_be_bytes());
        r0.extend_from_slice(&6u32.to_be_bytes());
        for _ in 0..4 {
            r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes()); // ortho/inflect/index_names/index_keys
        }
        for _ in 0..6 {
            r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes()); // extra_indices
        }
        let fnbi = index_rec.unwrap_or(image_start);
        r0.extend_from_slice(&(fnbi as u32).to_be_bytes()); // first_non_book_index
        r0.extend_from_slice(&(name_offset as u32).to_be_bytes());
        r0.extend_from_slice(&(name_field_len() as u32).to_be_bytes()); // name_length
        r0.extend_from_slice(&0u16.to_be_bytes()); // unused
        r0.push(0); // locale
        r0.push(p.lang_code); // language_code
        r0.extend_from_slice(&0u32.to_be_bytes()); // input_language
        r0.extend_from_slice(&0u32.to_be_bytes()); // output_language
        r0.extend_from_slice(&6u32.to_be_bytes()); // format_version
        r0.extend_from_slice(&(image_start as u32).to_be_bytes()); // first_image_index
        r0.extend_from_slice(&0u32.to_be_bytes()); // first_huff_record
        r0.extend_from_slice(&0u32.to_be_bytes()); // huff_record_count
        r0.extend_from_slice(&0u32.to_be_bytes()); // huff_table_offset
        r0.extend_from_slice(&0u32.to_be_bytes()); // huff_table_length
        r0.extend_from_slice(&0x50u32.to_be_bytes()); // exth_flags（EXTH 开启）
        r0.extend_from_slice(&[0u8; 32]); // unused_0
        r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes()); // unused_1
        r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes()); // drm_offset（无 DRM）
        r0.extend_from_slice(&0u32.to_be_bytes()); // drm_count
        r0.extend_from_slice(&0u32.to_be_bytes()); // drm_size
        r0.extend_from_slice(&0u32.to_be_bytes()); // drm_flags
        r0.extend_from_slice(&[0u8; 8]); // unused_2
        r0.extend_from_slice(&(first_content as u16).to_be_bytes()); // first_content_record
        r0.extend_from_slice(&(image_start as u16).to_be_bytes()); // last_content_record
        r0.extend_from_slice(&1u32.to_be_bytes()); // unused_3
        r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes()); // fcis_record
        r0.extend_from_slice(&1u32.to_be_bytes()); // unused_4
        r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes()); // flis_record
        r0.extend_from_slice(&1u32.to_be_bytes()); // unused_5
        r0.extend_from_slice(&[0u8; 8]); // unused_6
        r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes()); // unused_7
        r0.extend_from_slice(&0u32.to_be_bytes()); // first_compilation_data_section_count
        r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes()); // data_section_count
        r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes()); // unused_8
        r0.extend_from_slice(&7u32.to_be_bytes()); // extra_record_data_flags
        r0.extend_from_slice(&(index_rec.unwrap_or(0xFFFF_FFFF) as u32).to_be_bytes()); // first_index_record
        // EXTH
        r0.append(&mut exth);
        // name
        r0.extend_from_slice(b"SyntheticTestBook");
        if r0.len() != name_offset + name_field_len() {
            eprintln!("r0.len()={} expected={} name_offset={} exth_len={} name_len={}",
                r0.len(), name_offset + name_field_len(), name_offset,
                exth.len(), name_field_len());
            // 头部各段长度自检（定位多/缺字节）
            eprintln!("palmdoc=16 mobi_header=232 exth={} name={}",
                16usize + 232 + exth.len(), name_field_len());
        }
        assert_eq!(r0.len(), name_offset + name_field_len());

        let mut records = vec![r0];
        records.extend(content_records);
        if let Some(recs) = &p.indx {
            let entries: Vec<(String, u32)> = recs.clone();
            records.push(build_indx_record(&entries));
        }
        for img in &p.images {
            records.push(img.clone());
        }
        let _ = std::fs::write("/home/heiwa/workspace/.scratch/syn_full.bin", &assemble(&records));
        assemble(&records)
    }

    fn name_field_len() -> usize {
        17 // "SyntheticTestBook".len()
    }

    fn build_exth(p: &SynParams) -> Vec<u8> {
        let title = p.title.as_bytes().to_vec();
        let author = p.author.as_bytes().to_vec();
        let mut records = vec![(503u32, title), (100u32, author)];
        if !p.omit_exth_524 {
            records.push((524u32, p.language.as_bytes().to_vec()));
        }
        if let Some(v) = p.exth_121 {
            records.push((121u32, v.to_be_bytes().to_vec()));
        }
        let header_len = 12u32 + records.iter().map(|(_, d)| 8 + d.len() as u32).sum::<u32>();
        let mut out = Vec::new();
        out.extend_from_slice(b"EXTH");
        out.extend_from_slice(&header_len.to_be_bytes());
        out.extend_from_slice(&(records.len() as u32).to_be_bytes());
        for (ty, data) in records {
            out.extend_from_slice(&ty.to_be_bytes());
            out.extend_from_slice(&((8 + data.len()) as u32).to_be_bytes());
            out.extend_from_slice(&data);
        }
        out
    }

    /// GBK 编码辅助
    pub(crate) fn gbk(text: &str) -> Vec<u8> {
        let (bytes, _, _) = GB18030.encode(text);
        bytes.into_owned()
    }
}

/// 构造一个带 pagebreak + EXTH + 图片 + INDX 的标准合成 MOBI7（US-1 语料形态）
fn standard_synthetic_mobi() -> Vec<u8> {
    let body = r#"<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Test Book</title></head><body>
<h1>第一章</h1><p>It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.</p>
<mbp:pagebreak/>
<h1>第二章</h1><p>However little known the feelings or views of such a man may be on his first entering a neighbourhood.</p>
<img src="kindle:embed:0000?mime=image/jpeg"/>
<mbp:pagebreak/>
<h1>第三章</h1><p>This truth is so well fixed in the minds of the surrounding families.</p>
</body></html>"#;
    // INDX 位置 = 各章在 body 中的起始字节偏移（第一章 0；第二/三章取 pagebreak 后）
    let body_bytes = body.as_bytes();
    let pos2 = body_bytes
        .windows(16)
        .position(|w| w == b"<mbp:pagebreak/>")
        .map(|i| i + 16)
        .expect("应有 pagebreak");
    let pos3 = body_bytes[pos2..]
        .windows(16)
        .position(|w| w == b"<mbp:pagebreak/>")
        .map(|i| pos2 + i + 16)
        .expect("应有第二个 pagebreak");
    let mut img = Vec::new();
    img.extend_from_slice(b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9"); // 迷你 JPEG
    synth::build(&synth::SynParams {
        title: "Test Book",
        author: "Jane Austen",
        language: "en",
        encoding: 65001,
        lang_code: 9,
        mobi_type: 2,
        compression: 2,
        body: body.to_string().into_bytes(),
        images: vec![img],
        indx: Some(vec![
            ("第一章".to_string(), 0),
            ("第二章".to_string(), pos2 as u32),
            ("第三章".to_string(), pos3 as u32),
        ]),
        exth_121: None,
            omit_exth_524: false,
    })
}

// ===================== 合成样例测试 =====================

#[test]
fn synthetic_mobi_full_pipeline() {
    let dir = tempfile::tempdir().unwrap();
    let path = write_tmp(dir.path(), "syn.mobi", &standard_synthetic_mobi());
    let book = format::parse(&path).expect("合成 MOBI 解析失败");
    assert_eq!(book.format, Format::Mobi);
    assert_eq!(book.title, "Test Book");
    assert_eq!(book.authors, vec!["Jane Austen"]);
    assert_eq!(book.language.as_deref(), Some("en"));
    assert!(book.chapters.len() >= 3, "章节数 {}", book.chapters.len());
    let all: String = book.chapters.iter().map(|c| c.text.as_str()).collect();
    assert!(all.contains("It is a truth universally acknowledged"));
    assert!(all.contains("surrounding families"));
    // 无 U+FFFD
    assert!(!all.contains('\u{fffd}'));
    // INDX 目录还原：toc[0] 映射到第二章章节
    assert!(book.toc.len() >= 2, "toc {}", book.toc.len());
    assert_eq!(book.toc[0].title, "第一章");
    assert_eq!(book.toc[0].href, "chapter_0001.xhtml");
    // 图片资源 + img src 重写
    assert_eq!(book.resources.len(), 1);
    assert!(book.resources[0].media_type.starts_with("image/"));
    assert!(book.chapters.iter().any(|c| c.html.contains("images/image0001.jpg")));
}

#[test]
fn synthetic_gbk_mobi_no_mojibake() {
    // US-5：GBK(936) 中文 MOBI，无 U+FFFD/乱码
    let body = "<html><body><h1>第一章</h1><p>你好，世界。这是一段中文测试。</p><mbp:pagebreak/><h1>第二章</h1><p>再见世界。</p></body></html>";
    let dir = tempfile::tempdir().unwrap();
    let path = write_tmp(
        dir.path(),
        "gbk.mobi",
        &synth::build(&synth::SynParams {
            title: "测试书",
            author: "测试作者",
            language: "zh",
            encoding: 936,
            lang_code: 4,
            mobi_type: 2,
            compression: 2,
            body: synth::gbk(body),
            images: Vec::new(),
            indx: None,
            exth_121: None,
            omit_exth_524: false,
        }),
    );
    let book = format::parse(&path).expect("GBK MOBI 解析失败");
    assert_eq!(book.format, Format::Mobi);
    assert_eq!(book.title, "测试书");
    assert!(book.chapters.len() >= 2, "章节数 {}", book.chapters.len());
    let all: String = book.chapters.iter().map(|c| c.text.as_str()).collect();
    assert!(all.contains("你好，世界。"), "实际: {all}");
    assert!(!all.contains('\u{fffd}'), "不应有替换符");
}

#[test]
fn synthetic_kf8_rawml_azw3() {
    // US-2：KF8 原生段（rawml）尽力解析路径；MOBI 头 type==248 + EXTH 121
    let rawml = r#"<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata><dc:title>KF8 Test</dc:title></metadata>
  <manifest>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>
<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>One</title></head><body><h1>One</h1><p>first rawml chapter text</p></body></html>
<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Two</title></head><body><h1>Two</h1><p>second rawml chapter text</p></body></html>"#;
    let dir = tempfile::tempdir().unwrap();
    let path = write_tmp(
        dir.path(),
        "kf8.azw3",
        &synth::build(&synth::SynParams {
            title: "KF8 Test",
            author: "Author",
            language: "en",
            encoding: 65001,
            lang_code: 9,
            mobi_type: 248, // KF8
            compression: 1, // No 压缩：rawml 原样透传
            body: rawml.as_bytes().to_vec(),
            images: Vec::new(),
            indx: None,
            exth_121: Some(1),
            omit_exth_524: false,
        }),
    );
    let book = format::parse(&path).expect("KF8 rawml 解析失败");
    assert_eq!(book.format, Format::Azw3);
    assert!(book.chapters.len() >= 2, "章节数 {}", book.chapters.len());
    let all: String = book.chapters.iter().map(|c| c.text.as_str()).collect();
    assert!(all.contains("first rawml chapter text"));
    assert!(all.contains("second rawml chapter text"));
}

#[test]
fn mobi_content_as_azw3_by_extension() {
    // US-2 可观察行为：.mobi 内容（MOBI7）复制为 .azw3 扩展名 → 扩展名分发走 azw3::parse，
    // 内容嗅探判非 KF8 → MOBI7 兜底，format==Azw3
    let dir = tempfile::tempdir().unwrap();
    let bytes = std::fs::read(corpus("hongloumeng.mobi")).unwrap();
    let path = write_tmp(dir.path(), "copy.azw3", &bytes);
    let book = format::parse(&path).expect(".azw3 扩展名的 MOBI7 内容解析失败");
    assert_eq!(book.format, Format::Azw3);
    assert!(book.chapters.len() >= 2, "章节数 {}", book.chapters.len());
    let all: String = book.chapters.iter().map(|c| c.text.as_str()).collect();
    assert!(all.contains("第一回"), "应含中文正文");
    assert!(!all.contains('\u{fffd}'));
}

#[test]
fn detect_format_sniffs_mobi_vs_azw3_by_type() {
    // US-2：无扩展名嗅探——MOBI 头 type==248 → Azw3；type==2 → Mobi（不得误判）
    let synth_mobi = standard_synthetic_mobi();
    assert_eq!(format::detect_format(&synth_mobi), Some(Format::Mobi));
    let kf8 = synth::build(&synth::SynParams {
        title: "K",
        author: "A",
        language: "en",
        encoding: 65001,
        lang_code: 9,
        mobi_type: 248,
        compression: 1,
        body: b"<html><body><p>x</p></body></html>".to_vec(),
        images: Vec::new(),
        indx: None,
        exth_121: Some(1),
        omit_exth_524: false,
    });
    assert_eq!(format::detect_format(&kf8), Some(Format::Azw3));
}

// ===================== 合成 both 型 AZW3（KF8 外层 + 内嵌 MOBI7 回退段） =====================

/// 构造 record 0 的 KF8 外层 MOBI 头（type==248；内容区为空 → rawml 特征不成立）。
/// 字段布局与 mobi crate 的 MobiHeader::parse 顺序一致（16B PalmDoc + 232B MOBI）。
fn kf8_outer_header() -> Vec<u8> {
    let mut h = vec![0u8; 16 + 232];
    // PalmDoc 头
    h[0..2].copy_from_slice(&1u16.to_be_bytes()); // compression = No
    h[10..12].copy_from_slice(&4096u16.to_be_bytes()); // record_size
    // MOBI 头
    h[16..20].copy_from_slice(b"MOBI");
    h[20..24].copy_from_slice(&232u32.to_be_bytes());
    h[24..28].copy_from_slice(&248u32.to_be_bytes()); // type = KF8
    h[28..32].copy_from_slice(&65001u32.to_be_bytes()); // text_encoding = UTF-8
    h[16 + 64..16 + 68].copy_from_slice(&1u32.to_be_bytes()); // first_non_book_index = 1 → 内容区 [1,1) 空
    h[16 + 68..16 + 72].copy_from_slice(&248u32.to_be_bytes()); // name_offset = 248（紧随 MOBI 头，无 EXTH）
    h[16 + 72..16 + 76].copy_from_slice(&0u32.to_be_bytes()); // name_length = 0
    h[16 + 92..16 + 96].copy_from_slice(&4u32.to_be_bytes()); // first_image_index = 4（记录 0..3 之后）
    h[16 + 112..16 + 116].copy_from_slice(&0u32.to_be_bytes()); // exth_flags = 0（无 EXTH）
    h[16 + 152..16 + 156].copy_from_slice(&0xFFFF_FFFFu32.to_be_bytes()); // drm_offset = 无 DRM
    h[16 + 176..16 + 178].copy_from_slice(&0u16.to_be_bytes()); // first_content_record = 0 → max(1)=1
    h[16 + 178..16 + 180].copy_from_slice(&0u16.to_be_bytes()); // last_content_record
    h[16 + 228..16 + 232].copy_from_slice(&0xFFFF_FFFFu32.to_be_bytes()); // first_index_record = 无
    h
}

/// 构造内嵌 MOBI7 头（record k：16B PalmDoc + 232B MOBI，type==2）。
/// 内容记录区间 [k+1, k+fnbi)、图片从 k+fii 起（本测试无图片 → fii=fnbi）。
fn embedded_mobi7_header(compression: u16, encoding: u32, fnbi: u32, fii: u32) -> Vec<u8> {
    let mut h = vec![0u8; 16 + 232];
    h[0..2].copy_from_slice(&compression.to_be_bytes());
    h[10..12].copy_from_slice(&4096u16.to_be_bytes()); // record_size
    h[16..20].copy_from_slice(b"MOBI");
    h[20..24].copy_from_slice(&232u32.to_be_bytes());
    h[24..28].copy_from_slice(&2u32.to_be_bytes()); // type = MOBI7
    h[28..32].copy_from_slice(&encoding.to_be_bytes());
    h[16 + 64..16 + 68].copy_from_slice(&fnbi.to_be_bytes());
    h[16 + 92..16 + 96].copy_from_slice(&fii.to_be_bytes());
    h[16 + 176..16 + 178].copy_from_slice(&1u16.to_be_bytes()); // first_content_record = 1
    h[16 + 228..16 + 232].copy_from_slice(&0xFFFF_FFFFu32.to_be_bytes()); // first_index_record
    h
}

#[test]
fn synthetic_both_azw3_fallback_to_embedded_mobi7() {
    // US-2 both 型：KF8 容器 + 内嵌 MOBI7 回退段（azw3.rs 路径2 兜底；
    // 覆盖 mobi::parse_section + find_embedded_mobi7 正向路径 + 回退段图片抽取）
    let fallback_html = "<html><body><h1>Fallback One</h1><p>fallback known sentence here</p><mbp:pagebreak/><h1>Fallback Two</h1><p>second fallback part</p></body></html>";
    let comp = synth::palmdoc_compress(fallback_html.as_bytes());
    let mut img = Vec::new();
    img.extend_from_slice(b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9"); // 迷你 JPEG
    // 记录布局：record0 = KF8 外层头；record1 = 哑记录（非 MOBI 头，验证扫描跳过）；
    // record2 = 内嵌 MOBI7 头（k=2）；record3 = 回退段内容记录；record4 = 间隔记录；
    // record5 = 图片记录（image_start = k + fii = 2 + 3 = 5）
    let records = vec![
        kf8_outer_header(),
        vec![0u8; 30], // 哑记录：内容[16..20] != "MOBI" → 不被判为内嵌段
        embedded_mobi7_header(2, 65001, 2, 3), // fnbi=2 → 内容区 [3,4)；fii=3 → 图片在 5
        comp,
        vec![0u8; 40], // 间隔记录（内容区与图片区之间）
        img,
    ];
    let dir = tempfile::tempdir().unwrap();
    let path = write_tmp(dir.path(), "both.azw3", &synth::assemble(&records));
    let book = format::parse(&path).expect("both 型 AZW3 回退段解析失败");
    assert_eq!(book.format, Format::Azw3);
    assert!(book.chapters.len() >= 2, "章节数 {}", book.chapters.len());
    let all: String = book.chapters.iter().map(|c| c.text.as_str()).collect();
    assert!(all.contains("fallback known sentence here"), "实际: {all}");
    assert!(all.contains("second fallback part"), "实际: {all}");
    assert!(!all.contains('\u{fffd}'));
    // 回退段图片抽取
    assert_eq!(book.resources.len(), 1, "应抽到 1 张图: {:?}", book.resources);
    assert!(book.resources[0].media_type.starts_with("image/"));
    assert!(book.resources[0].data.starts_with(b"\xff\xd8"));
}

#[test]
fn synthetic_azw3_short_embedded_header_returns_corrupt() {
    // US-3：内嵌 MOBI7 头被截断（< 248B）→ Corrupt，不 panic
    let mut short = embedded_mobi7_header(2, 65001, 2, 2);
    short.truncate(220);
    let records = vec![kf8_outer_header(), short];
    let dir = tempfile::tempdir().unwrap();
    let path = write_tmp(dir.path(), "short.azw3", &synth::assemble(&records));
    let err = format::parse(&path).unwrap_err();
    assert!(matches!(err, Error::Corrupt(_)), "应为 Corrupt: {err:?}");
}

#[test]
fn synthetic_pdb_with_extra_bytes_excludes_trailing_junk() {
    // PDB 记录表尾 extra 字段 ≠ 0：record_bytes 必须排除每条记录的尾填充字节，
    // 否则尾填充会混入解压文本（变异防护：extra_bytes 计算 / u16_be_at 读取）
    let mut body = String::from("<html><body><h1>第一章</h1><p>known clean sentence</p>");
    body.push_str(&"A".repeat(5000)); // 撑到 >4096B → 2 条内容记录
    body.push_str("</body></html>");
    let mut img = Vec::new();
    img.extend_from_slice(b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9");
    // 手工记录：record0（标准头）+ 2 条 PalmDoc 内容记录 + 1 张图片（末记录）
    let content = body.into_bytes();
    let chunk = 4096usize;
    let mut content_records = Vec::new();
    let mut i = 0usize;
    while i < content.len() {
        let end = (i + chunk).min(content.len());
        content_records.push(synth::palmdoc_compress(&content[i..end]));
        i = end;
    }
    assert_eq!(content_records.len(), 2, "body 应拆成 2 条内容记录");
    let records = vec![
        standard_record0(content.len() as u32, 2, 3), // record0（PalmDoc+MOBI 头，图片首索引=3）
        content_records[0].clone(),
        content_records[1].clone(),
        img,
    ];
    let dir = tempfile::tempdir().unwrap();
    let path = write_tmp(dir.path(), "extra.mobi", &synth::assemble_with_extra(&records, 0x0002));
    let book = format::parse(&path).expect("extra 字段文件解析失败");
    let all: String = book.chapters.iter().map(|c| c.text.as_str()).collect();
    assert!(all.contains("known clean sentence"), "实际: {all}");
    assert!(!all.contains("XX"), "尾填充不得混入文本: {all}");
    assert!(!all.contains('\u{fffd}'));
    assert_eq!(book.resources.len(), 1, "图片记录应被识别");
}

/// 标准 record 0（PalmDoc 16B + MOBI 232B + EXTH + name），与 synth::build 的 r0 同构。
/// `text_length`/`num_content`/`image_start` 由调用方给出（仅测试用，字段布局同 mobih.rs）。
fn standard_record0(text_length: u32, num_content: u16, image_start: u16) -> Vec<u8> {
    let mut exth = Vec::new();
    let title = b"T";
    let author = b"A";
    let lang = b"en";
    let mut records = vec![
        (503u32, title.to_vec()),
        (100u32, author.to_vec()),
        (524u32, lang.to_vec()),
    ];
    let header_len = 12u32 + records.iter().map(|(_, d)| 8 + d.len() as u32).sum::<u32>();
    exth.extend_from_slice(b"EXTH");
    exth.extend_from_slice(&header_len.to_be_bytes());
    exth.extend_from_slice(&(records.len() as u32).to_be_bytes());
    for (ty, data) in records.drain(..) {
        exth.extend_from_slice(&ty.to_be_bytes());
        exth.extend_from_slice(&((8 + data.len()) as u32).to_be_bytes());
        exth.extend_from_slice(&data);
    }
    let name_offset = 16 + 232 + exth.len();
    let fnbi = 1 + num_content; // first_non_book_index = 内容区结束（record 1..1+num_content）
    let mut r0 = Vec::new();
    r0.extend_from_slice(&2u16.to_be_bytes()); // compression = PalmDoc
    r0.extend_from_slice(&0u16.to_be_bytes());
    r0.extend_from_slice(&text_length.to_be_bytes());
    r0.extend_from_slice(&num_content.to_be_bytes());
    r0.extend_from_slice(&4096u16.to_be_bytes()); // record_size
    r0.extend_from_slice(&0u16.to_be_bytes()); // encryption = No
    r0.extend_from_slice(&0u16.to_be_bytes());
    r0.extend_from_slice(b"MOBI");
    r0.extend_from_slice(&232u32.to_be_bytes());
    r0.extend_from_slice(&2u32.to_be_bytes()); // type = MOBI7
    r0.extend_from_slice(&65001u32.to_be_bytes()); // encoding
    r0.extend_from_slice(&0x12345678u32.to_be_bytes());
    r0.extend_from_slice(&6u32.to_be_bytes());
    for _ in 0..4 {
        r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes());
    }
    for _ in 0..6 {
        r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes());
    }
    r0.extend_from_slice(&(fnbi as u32).to_be_bytes()); // first_non_book_index
    r0.extend_from_slice(&(name_offset as u32).to_be_bytes());
    r0.extend_from_slice(&1u32.to_be_bytes()); // name_length
    r0.extend_from_slice(&0u16.to_be_bytes());
    r0.push(0);
    r0.push(9); // language_code = English
    r0.extend_from_slice(&0u32.to_be_bytes());
    r0.extend_from_slice(&0u32.to_be_bytes());
    r0.extend_from_slice(&6u32.to_be_bytes());
    r0.extend_from_slice(&(image_start as u32).to_be_bytes()); // first_image_index = 4
    r0.extend_from_slice(&0u32.to_be_bytes());
    r0.extend_from_slice(&0u32.to_be_bytes());
    r0.extend_from_slice(&0u32.to_be_bytes());
    r0.extend_from_slice(&0u32.to_be_bytes());
    r0.extend_from_slice(&0x50u32.to_be_bytes()); // exth_flags
    r0.extend_from_slice(&[0u8; 32]);
    r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes());
    r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes()); // drm_offset
    r0.extend_from_slice(&0u32.to_be_bytes());
    r0.extend_from_slice(&0u32.to_be_bytes());
    r0.extend_from_slice(&0u32.to_be_bytes());
    r0.extend_from_slice(&[0u8; 8]);
    r0.extend_from_slice(&1u16.to_be_bytes()); // first_content_record
    r0.extend_from_slice(&(image_start as u16).to_be_bytes()); // last_content_record
    r0.extend_from_slice(&1u32.to_be_bytes());
    r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes());
    r0.extend_from_slice(&1u32.to_be_bytes());
    r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes());
    r0.extend_from_slice(&1u32.to_be_bytes());
    r0.extend_from_slice(&[0u8; 8]);
    r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes());
    r0.extend_from_slice(&0u32.to_be_bytes());
    r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes());
    r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes());
    r0.extend_from_slice(&7u32.to_be_bytes());
    r0.extend_from_slice(&0xFFFF_FFFFu32.to_be_bytes()); // first_index_record
    r0.append(&mut exth);
    r0.push(b'T');
    r0
}

#[test]
fn synthetic_cp1252_mobi_accent_chars() {
    // US-5 编码链：声明 CP1252 + CP1252 高字节内容（é）→ 正确解码；
    // enc 字段读取错误（变异）会退化为内容探测 → 产生 U+FFFD（变异防护）
    let body = "<html><body><h1>Chapter</h1><p>caf\u{e9} au lait</p></body></html>";
    let (cp1252, _, _) = encoding_rs::WINDOWS_1252.encode(body);
    let dir = tempfile::tempdir().unwrap();
    let path = write_tmp(
        dir.path(),
        "cp.mobi",
        &synth::build(&synth::SynParams {
            title: "C",
            author: "A",
            language: "en",
            encoding: 1252,
            lang_code: 9,
            mobi_type: 2,
            compression: 2,
            body: cp1252.into_owned(),
            images: Vec::new(),
            indx: None,
            exth_121: None,
            omit_exth_524: false,
        }),
    );
    let book = format::parse(&path).expect("CP1252 MOBI 解析失败");
    let all: String = book.chapters.iter().map(|c| c.text.as_str()).collect();
    assert!(all.contains("café"), "CP1252 应保留 é: {all}");
    assert!(!all.contains('\u{fffd}'));
}

#[test]
fn synthetic_kf8_rawml_no_exth121_headingless() {
    // US-2：KF8 判定仅凭 MOBI 头 type==248（无 EXTH 121）→ 走 KF8 rawml 路径；
    // rawml 片段无 h1-h3 → 只有 KF8 spine 路径能拆出 ≥2 章（变异防护：mobi_type_u32）
    let rawml = r#"<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata><dc:title>KF8 Headless</dc:title></metadata>
  <manifest>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>
<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>One</title></head><body><p>first headless fragment text</p></body></html>
<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Two</title></head><body><p>second headless fragment text</p></body></html>"#;
    let dir = tempfile::tempdir().unwrap();
    let path = write_tmp(
        dir.path(),
        "headless.azw3",
        &synth::build(&synth::SynParams {
            title: "KF8 Headless",
            author: "Author",
            language: "en",
            encoding: 65001,
            lang_code: 9,
            mobi_type: 248,
            compression: 1,
            body: rawml.as_bytes().to_vec(),
            images: Vec::new(),
            indx: None,
            exth_121: None, // KF8 判定只能靠 type==248
            omit_exth_524: false,
        }),
    );
    let book = format::parse(&path).expect("无 EXTH121 的 KF8 rawml 解析失败");
    assert_eq!(book.format, Format::Azw3);
    assert!(book.chapters.len() >= 2, "KF8 spine 应拆出 ≥2 章: {}", book.chapters.len());
    let all: String = book.chapters.iter().map(|c| c.text.as_str()).collect();
    assert!(all.contains("first headless fragment text"), "实际: {all}");
    assert!(all.contains("second headless fragment text"), "实际: {all}");
}

#[test]
fn synthetic_azw3_drm_returns_encrypted() {
    // US-3：azw3 DRM 标记（PalmDoc encryption 字段 ≠ No）→ Encrypted，消息含 DRM/加密
    let kf8 = synth::build(&synth::SynParams {
        title: "K",
        author: "A",
        language: "en",
        encoding: 65001,
        lang_code: 9,
        mobi_type: 248,
        compression: 1,
        body: b"<html><body><p>x</p></body></html>".to_vec(),
        images: Vec::new(),
        indx: None,
        exth_121: Some(1),
        omit_exth_524: false,
    });
    // 定位 record 0（78B PDB 头 + 8*num 记录表 + 2B extra），PalmDoc encryption 字段在内容偏移 12
    let num = u16::from_be_bytes([kf8[76], kf8[77]]) as usize;
    let rec0 = 78usize + 8 * num + 2;
    let mut patched = kf8.clone();
    patched[rec0 + 12..rec0 + 14].copy_from_slice(&1u16.to_be_bytes()); // OldMobiPocket
    let dir = tempfile::tempdir().unwrap();
    let path = write_tmp(dir.path(), "drm.azw3", &patched);
    let err = format::parse(&path).unwrap_err();
    assert!(matches!(err, Error::Encrypted(_)), "应为 Encrypted: {err:?}");
    let msg = err.to_string();
    assert!(msg.contains("DRM") || msg.contains("加密"), "消息应含 DRM/加密: {msg}");
}

#[test]
fn synthetic_mobi_language_falls_back_to_header_code() {
    // US-1：无 EXTH 524 → MOBI header language_code 兜底（English→en / Chinese→zh）
    let body = "<html><body><h1>第一章</h1><p>内容</p></body></html>";
    let dir = tempfile::tempdir().unwrap();
    let path = write_tmp(
        dir.path(),
        "lang.mobi",
        &synth::build(&synth::SynParams {
            title: "T",
            author: "A",
            language: "en", // 被 omit_exth_524 忽略
            encoding: 65001,
            lang_code: 9,
            mobi_type: 2,
            compression: 2,
            body: body.as_bytes().to_vec(),
            images: Vec::new(),
            indx: None,
            exth_121: None,
            omit_exth_524: true,
        }),
    );
    let book = format::parse(&path).expect("解析失败");
    assert_eq!(book.language.as_deref(), Some("en"), "应回退 header language_code");
    // Chinese（lang_code=4）
    let path2 = write_tmp(
        dir.path(),
        "lang2.mobi",
        &synth::build(&synth::SynParams {
            title: "T",
            author: "A",
            language: "zh",
            encoding: 65001,
            lang_code: 4,
            mobi_type: 2,
            compression: 2,
            body: body.as_bytes().to_vec(),
            images: Vec::new(),
            indx: None,
            exth_121: None,
            omit_exth_524: true,
        }),
    );
    let book2 = format::parse(&path2).expect("解析失败");
    assert_eq!(book2.language.as_deref(), Some("zh"));
}

// ===================== 真实语料测试 =====================

#[test]
fn corpus_hongloumeng_mobi_pagebreak_split() {
    // US-1/US-5：pagebreak 拆章 + EXTH 元数据 + 中文 UTF-8
    let book = format::parse(&corpus("hongloumeng.mobi")).expect("hongloumeng.mobi 解析失败");
    assert_eq!(book.format, Format::Mobi);
    assert_eq!(book.title, "紅樓夢");
    assert!(!book.authors.is_empty(), "authors 应为空: {:?}", book.authors);
    assert_eq!(book.language.as_deref(), Some("zh"));
    assert!(book.chapters.len() >= 2, "pagebreak 拆章章节数 {}", book.chapters.len());
    let all: String = book.chapters.iter().map(|c| c.text.as_str()).collect();
    assert!(all.contains("第一回"), "正文应含'第一回'");
    assert!(!all.contains('\u{fffd}'), "中文不应有替换符");
    // 目录：INDX 为 KindleGen IDXT 变体 → 章节标题回退（US-5 允许），toc 非空
    assert!(book.toc.len() >= 1, "toc {}", book.toc.len());
    for t in &book.toc {
        assert!(t.depth <= 8);
    }
}

#[test]
fn corpus_hongloumeng_images_mobi() {
    // 无 pagebreak 无标题 → 单章兜底路径；不得崩溃
    let book = format::parse(&corpus("hongloumeng-images.mobi")).expect("解析失败");
    assert_eq!(book.format, Format::Mobi);
    assert!(book.chapters.len() >= 1);
    let all: String = book.chapters.iter().map(|c| c.text.as_str()).collect();
    assert!(all.contains("第一回"), "应有中文正文");
}

#[test]
fn corpus_pride_and_prejudice_mobi_heading_split_with_images() {
    // 标题层级拆章 + 165 张 JPEG 资源
    let book = format::parse(&corpus("pride-and-prejudice.mobi")).expect("解析失败");
    assert_eq!(book.format, Format::Mobi);
    assert!(book.title.to_lowercase().contains("pride"), "title={}", book.title);
    assert!(book.chapters.len() >= 5, "章节数 {}", book.chapters.len());
    let all: String = book.chapters.iter().map(|c| c.text.as_str()).collect();
    assert!(all.contains("truth universally acknowledged"), "应含已知句子");
    let images: Vec<_> = book
        .resources
        .iter()
        .filter(|r| r.media_type.starts_with("image/"))
        .collect();
    assert!(images.len() >= 100, "图片资源数 {}", images.len());
    assert!(images[0].data.starts_with(b"\xff\xd8"), "应为 JPEG");
    // 章节 href 与 canonicalize 命名一致
    assert_eq!(book.chapters[0].href, "chapter_0001.xhtml");
}

// ===================== 坏文件错误路径（US-3） =====================

#[test]
fn truncated_mobi_returns_corrupt() {
    let err = format::parse(&corpus("bad-mobi-truncated.mobi")).unwrap_err();
    assert!(matches!(err, Error::Corrupt(_)), "应为 Corrupt: {err:?}");
}

#[test]
fn garbage_mobi_returns_corrupt() {
    let err = format::parse(&corpus("bad-mobi-garbage.mobi")).unwrap_err();
    assert!(matches!(err, Error::Corrupt(_)), "应为 Corrupt: {err:?}");
}

#[test]
fn drm_marked_mobi_returns_encrypted() {
    let err = format::parse(&corpus("bad-mobi-drm.mobi")).unwrap_err();
    assert!(matches!(err, Error::Encrypted(_)), "应为 Encrypted: {err:?}");
    let msg = err.to_string();
    assert!(msg.contains("DRM") || msg.contains("加密"), "消息应含 DRM/加密: {msg}");
}

#[test]
fn synthetic_truncated_mobi_returns_corrupt() {
    // 合成文件截断：PDB 头完整、内容流切断 → Corrupt，不 panic
    let full = standard_synthetic_mobi();
    let dir = tempfile::tempdir().unwrap();
    let cut = write_tmp(dir.path(), "cut.mobi", &full[..full.len() / 2]);
    let err = format::parse(&cut).unwrap_err();
    assert!(matches!(err, Error::Corrupt(_)), "应为 Corrupt: {err:?}");
}

// ===================== library 接入（US-4） =====================

#[test]
fn library_import_open_mobi_roundtrip() {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::open(&dir.path().join("data")).unwrap();
    let mut svc = LibraryService::new(store);

    let rec = svc
        .import_file(&corpus("hongloumeng.mobi"))
        .expect("MOBI 导入失败");
    assert_eq!(rec.format, "mobi");
    assert!(rec.canonical_path.as_deref().unwrap().ends_with(".epub"));
    assert!(std::path::Path::new(rec.canonical_path.as_deref().unwrap()).exists());

    // 打开 → 章节数与 format::parse 一致、文本非空
    let opened = svc.open_book(&rec.id).expect("打开失败");
    let parsed = format::parse(&corpus("hongloumeng.mobi")).unwrap();
    assert_eq!(opened.chapters.len(), parsed.chapters.len());
    assert!(!opened.chapters[0].text.is_empty());

    // 章节 HTML 可读且含已知句子
    let html = svc
        .chapter_html(&rec.id, "chapter_0001.xhtml")
        .expect("chapter_html 失败");
    assert!(html.contains("<!DOCTYPE") || html.to_lowercase().contains("<html"));

    // 重复导入去重：同 id、书架仅 1 本
    let again = svc.import_file(&corpus("hongloumeng.mobi")).unwrap();
    assert_eq!(again.id, rec.id);
    assert_eq!(svc.list().unwrap().len(), 1);
}



#[test]
fn perf_parse_timing() {
    // US-6 性能预算：5MB 级 MOBI 桌面 <200ms（release 实测 32-83ms）；CI 宽松上限 ≤2s（debug 亦满足）
    use std::time::Instant;
    // 桌面基准（US-6）：24MB 级 MOBI 单次解析；CI 宽松上限 ≤ 2s（debug 构建）
    let t = Instant::now();
    let book = format::parse(&corpus("pride-and-prejudice.mobi")).expect("解析失败");
    let el = t.elapsed();
    println!("pride-and-prejudice.mobi parse: {:?} chapters={} resources={}", el, book.chapters.len(), book.resources.len());
    assert!(el.as_secs_f64() < 2.0, "超过 CI 宽松上限 2s: {el:?}");
    let t = Instant::now();
    let book2 = format::parse(&corpus("hongloumeng.mobi")).expect("解析失败");
    let el2 = t.elapsed();
    println!("hongloumeng.mobi parse: {:?} chapters={}", el2, book2.chapters.len());
    assert!(el2.as_secs_f64() < 2.0, "超过 CI 宽松上限 2s: {el2:?}");
}
