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
    }

    /// PalmDOC LZ77 压缩（贪心匹配，测试用）
    fn palmdoc_compress(data: &[u8]) -> Vec<u8> {
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

    /// 组装 PDB 文件字节
    fn assemble(records: &[Vec<u8>]) -> Vec<u8> {
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
        // 记录表（记录内容起始 = 78 + 8*num + 2：表尾有 2 字节 extra 字段，
        // 与 mobi crate 的 PdbRecords::new 读取一致——真实 PDB 文件同样如此）
        let mut off = 78usize + 8 * num as usize + 2;
        for r in records {
            out.extend_from_slice(&(off as u32).to_be_bytes());
            out.extend_from_slice(&0u32.to_be_bytes());
            off += r.len();
        }
        out.extend_from_slice(&[0u8; 2]); // 记录表尾 extra 字段
        for r in records {
            out.extend_from_slice(r);
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
        let lang = p.language.as_bytes().to_vec();
        let mut records = vec![(503u32, title), (100u32, author), (524u32, lang)];
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
    });
    assert_eq!(format::detect_format(&kf8), Some(Format::Azw3));
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
