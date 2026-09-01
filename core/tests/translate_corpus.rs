//! REQ-003 集成测试：真实/自造 StarDict 词库查词 + 翻译缓存落库 + api 桥接全链路。
//!
//! 语料：tests/corpus/src/dicts/（来源/许可见 corpus/README.md）。
//! 真实 langdao 词库用例在文件缺失时跳过（真实语料不入 CI 硬依赖，对齐 REQ-002 纪律）；
//! 自造语料（test-tgm/test-tgmx/坏词库）为确定性 CI 主语料。

use std::path::PathBuf;

use reader_core::api;
use reader_core::dict::{DictService, TranslationService};
use reader_core::store::TranslationRepo;
use reader_core::types::{Lang, TranslationCacheRepository};

fn dicts_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/corpus/src/dicts")
}

fn corpus_dict(name: &str) -> PathBuf {
    dicts_dir().join(name)
}

fn langdao_ec_ifo() -> Option<PathBuf> {
    let p = corpus_dict("langdao-ec/langdao-ec-gb.ifo");
    if p.exists() {
        Some(p)
    } else {
        None
    }
}

/// 极简 block_on：本工程 async 桥接函数体内无任何 .await（同步阻塞 ureq/rusqlite），
/// 首轮 poll 即 Ready，无需真实运行时（ADR 决策点1 的"core 不拥有运行时"在测试侧同理）。
fn block_on<F: std::future::Future>(mut fut: F) -> F::Output {
    use std::pin::Pin;
    use std::ptr;
    use std::task::{Context, Poll, RawWaker, RawWakerVTable, Waker};
    const VTABLE: RawWakerVTable = RawWakerVTable::new(|_| RAW, |_| {}, |_| {}, |_| {});
    const RAW: RawWaker = RawWaker::new(ptr::null(), &VTABLE);
    let waker = unsafe { Waker::from_raw(RAW) };
    let mut cx = Context::from_waker(&waker);
    let fut = unsafe { Pin::new_unchecked(&mut fut) };
    match fut.poll(&mut cx) {
        Poll::Ready(v) => v,
        Poll::Pending => panic!("阻塞在无 await 的桥接函数上（不应发生）"),
    }
}

// ---------- 真实词库：朗道英汉（en→zh，435468 词条，seq='m'） ----------

#[test]
fn dict_service_real_langdao_ec_lookup() {
    let Some(ifo) = langdao_ec_ifo() else {
        eprintln!("[skip] langdao-ec 语料缺失，跳过真实词库集成");
        return;
    };
    let dir = tempfile::tempdir().unwrap();
    let mut svc = DictService::new(dir.path()).unwrap();
    let info = svc.install(&ifo).expect("朗道安装失败");
    assert_eq!(info.word_count, 435_468, "wordcount 与 .ifo 一致");
    assert!(info.path.contains("dicts"));
    assert!(svc.list().unwrap().len() == 1);

    // 已知词 "apple"：m 字段释义含"苹果"；无 t 字段 → phonetic=None；pos 启发式取 "n."
    let e = svc.lookup("apple", None).unwrap().expect("应命中 apple");
    assert_eq!(e.word, "apple");
    assert!(e.definition.contains("苹果"), "释义应含'苹果': {}", e.definition);
    assert_eq!(e.phonetic, None, "seq='m' 无音标字段 → None");
    assert_eq!(e.pos.as_deref(), Some("n."), "行首词性标记: {}", e.definition);

    // 未收录 → Ok(None)
    assert!(svc.lookup("zzzqqq", None).unwrap().is_none());

    // 指定 dict_id 查词
    let e2 = svc.lookup("book", Some(&info.id)).unwrap().expect("应命中 book");
    assert!(e2.definition.contains("书"));
}

#[test]
fn dict_service_real_langdao_ce_zh_headword_no_phonetic() {
    let p = corpus_dict("langdao-ce/langdao-ce-gb.ifo");
    if !p.exists() {
        eprintln!("[skip] langdao-ce 语料缺失，跳过");
        return;
    }
    let dir = tempfile::tempdir().unwrap();
    let mut svc = DictService::new(dir.path()).unwrap();
    let info = svc.install(&p).expect("朗道汉英安装失败");
    assert_eq!(info.word_count, 405_719);
    // 中文词条：phonetic=None（US-1 可空断言），定义非空
    let e = svc.lookup("苹果", None).unwrap().expect("应命中'苹果'");
    assert_eq!(e.phonetic, None, "中文词库无音标 → None");
    assert!(!e.definition.is_empty());
}

// ---------- 自造语料：tgm/tgmx/坏词库（确定性 CI） ----------

#[test]
fn dict_service_selfmade_tgmx_and_case_normalization() {
    let dir = tempfile::tempdir().unwrap();
    let mut svc = DictService::new(dir.path()).unwrap();
    // .dict.dz 变体安装（流式解压）
    let info = svc
        .install(&corpus_dict("test-tgmx/test-tgmx.ifo"))
        .expect("tgmx 安装失败");
    assert_eq!(info.word_count, 26);
    let e = svc.lookup("book", None).unwrap().expect("应命中 book");
    assert_eq!(e.phonetic.as_deref(), Some("/bʊk/"));
    assert!(e.definition.contains("n. 书"));
    assert_eq!(e.pos.as_deref(), Some("n."));
    assert_eq!(e.example.as_deref(), Some("an interesting book"), "x 字段 → example");

    // 大小写归一（US-5）：test-tgm 同时含 "Apple" 与 "apple"；
    // 查全大写 "APPLE" → 二分精确未中 → 线性扫描忽略大小写命中 idx 首个 "Apple"
    let tgm = svc.install(&corpus_dict("test-tgm/test-tgm.ifo")).unwrap();
    let e = svc.lookup("APPLE", Some(&tgm.id)).unwrap().expect("应命中");
    assert_eq!(e.word, "Apple", "忽略大小写归一命中 'Apple'");
    // 未收录（US-2）
    assert!(svc.lookup("zzzqqq", None).unwrap().is_none());
}

#[test]
fn dict_service_bad_dicts_install_fails_list_unaffected() {
    let dir = tempfile::tempdir().unwrap();
    let mut svc = DictService::new(dir.path()).unwrap();
    // 先装一个好词库
    svc.install(&corpus_dict("test-tgm/test-tgm.ifo")).unwrap();
    let before = svc.list().unwrap().len();
    // .idx 截断
    let err = svc.install(&corpus_dict("bad-idx-truncated/bad-idx-truncated.ifo")).unwrap_err();
    assert!(err.to_string().contains("损坏"), "截断应 Corrupt: {err}");
    // .ifo 缺 wordcount
    let err = svc.install(&corpus_dict("bad-ifo-nocount/bad-ifo-nocount.ifo")).unwrap_err();
    assert!(err.to_string().contains("wordcount"), "缺 wordcount 应 Corrupt: {err}");
    // .dz 损坏
    let err = svc.install(&corpus_dict("bad-dz-truncated/bad-dz-truncated.ifo")).unwrap_err();
    assert!(err.to_string().contains("损坏"), ".dz 损坏应 Corrupt: {err}");
    assert_eq!(svc.list().unwrap().len(), before, "坏词库不影响已装列表");
}

#[test]
fn dict_service_bad_offset_oob_lookup_corrupt() {
    let dir = tempfile::tempdir().unwrap();
    let mut svc = DictService::new(dir.path()).unwrap();
    // 安装可成功（idx 可解析），查被 patch 的首条（"Apple"）→ Corrupt（US-6 偏移越界）
    svc.install(&corpus_dict("bad-offset-oob/bad-offset-oob.ifo")).unwrap();
    let err = svc.lookup("Apple", None).unwrap_err();
    assert!(err.to_string().contains("越界"), "越界应 Corrupt: {err}");
}

// ---------- api 桥接全链路（async 函数，block_on 驱动） ----------

#[test]
fn api_bridge_dict_translate_cache_full_chain() {
    let dir = tempfile::tempdir().unwrap();
    let data_dir = dir.path().join("data");
    // 1) 装配（DICT/TRANSLATION 双单例 + 迁移 v3）
    api::library_open(data_dir.display().to_string()).unwrap();

    // 2) dict_install（自造 tgmx，.dict.dz 变体）→ dict_list → dict_lookup
    let info = block_on(api::dict_install(
        corpus_dict("test-tgmx/test-tgmx.ifo").display().to_string(),
    ))
    .expect("安装失败");
    assert!(info.word_count > 0);
    let list = block_on(api::dict_list()).unwrap();
    assert_eq!(list.len(), 1);
    assert_eq!(list[0].id, info.id);

    let view = block_on(api::dict_lookup("book".to_string(), None))
        .unwrap()
        .expect("应命中 book");
    assert_eq!(view.word, "book");
    assert_eq!(view.example.as_deref(), Some("an interesting book"));
    // 未收录 → Ok(None)
    assert!(block_on(api::dict_lookup("zzzqqq".to_string(), None)).unwrap().is_none());
    // 未装词库的移除 → Err
    assert!(block_on(api::dict_remove("no_such".to_string())).is_err());

    // 3) translate：未配置 key → NotConfigured（US-12，消息含 API Key）
    let err = block_on(api::translate(
        "Hello world".to_string(),
        "en".to_string(),
        "zh".to_string(),
    ))
    .unwrap_err();
    assert!(err.contains("API Key"), "应含 API Key: {err}");

    // 4) translate_set_config("echo","") → 无 key 演示 → translate 走通（US-17/ADR 裁定2）
    block_on(api::translate_set_config("echo".to_string(), String::new())).unwrap();
    let t1 = block_on(api::translate(
        "Hello world".to_string(),
        "en".to_string(),
        "zh".to_string(),
    ))
    .expect("echo 翻译应成功");
    assert_eq!(t1.text, "译文:Hello world");
    assert_eq!(t1.provider, "echo");
    assert!(!t1.from_cache, "首次未命中缓存");
    assert_eq!(t1.from, "en");
    assert_eq!(t1.to, "zh");

    // 5) 命中缓存（US-10）：from_cache=true，且 Provider 不重复调用（行数不变）
    let t2 = block_on(api::translate(
        "Hello world".to_string(),
        "en".to_string(),
        "zh".to_string(),
    ))
    .unwrap();
    assert!(t2.from_cache, "第二次应命中缓存");
    assert_eq!(t2.text, t1.text);

    // 6) 缓存落库行数断言（US-13）：translation_cache 恰 1 行（失败不写、命中不重复写）
    let repo = TranslationRepo::open(&data_dir).unwrap();
    assert_eq!(repo.cache_count().unwrap(), 1);

    // 7) 清空（US-13）→ 行数 0；再翻同文 → 重新调 Provider（from_cache=false）
    block_on(api::translate_cache_clear()).unwrap();
    assert_eq!(repo.cache_count().unwrap(), 0);
    let t3 = block_on(api::translate(
        "Hello world".to_string(),
        "en".to_string(),
        "zh".to_string(),
    ))
    .unwrap();
    assert!(!t3.from_cache, "清空后应重新翻译");

    // 8) 不支持的语言代码 → Err（Lang::parse None 映射）
    let err = block_on(api::translate(
        "hi".to_string(),
        "xx".to_string(),
        "zh".to_string(),
    ))
    .unwrap_err();
    assert!(err.contains("不支持的语言代码"), "应含提示: {err}");
}

#[test]
fn translation_service_with_real_repo_and_lang_pair_cache() {
    // 服务层 + 真实 TranslationRepo 的缓存键区分（US-11 的语言对维度）
    let dir = tempfile::tempdir().unwrap();
    let cache = Box::new(TranslationRepo::open(dir.path()).unwrap());
    let config = Box::new(TranslationRepo::open(dir.path()).unwrap());
    let mut svc = TranslationService::new(
        cache,
        config,
        vec![Box::new(reader_core::dict::EchoProvider)],
    );
    svc.set_config("echo", "").unwrap();
    svc.translate("你好", Lang::Zh, Lang::En).unwrap();
    // 同文反向语言对 → Miss（再调一次）
    let (_, from_cache) = svc.translate_cached("你好", Lang::Zh, Lang::En).unwrap();
    assert!(from_cache);
    let (_, from_cache) = svc.translate_cached("你好", Lang::En, Lang::Zh).unwrap();
    assert!(!from_cache, "反向语言对应 Miss");
}
