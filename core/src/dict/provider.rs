//! 在线翻译 Provider：DeepL（真实，ureq+rustls）+ Echo（mock/无 key 演示）。
//!
//! 设计：REQ-003 02-design §2.2 + ADR 决策点4（ureq blocking + rustls，禁 native-tls/OpenSSL）。
//! 隐私（US-9/US-13）：DeepL 请求体只含 text/from/to，无书路径/元数据/设备信息。
//! 网络仅封装在本模块（DeepLProvider 内部），domain 其余代码零网络依赖。

use crate::dict::{DictEntry, TranslationProvider};
use crate::error::{Error, Result};
use crate::types::{Lang, Translation};

/// DeepL Provider（真实）：REST POST /v2/translate，`Authorization: DeepL-Auth-Key <key>`。
/// 默认走 Free 层端点 api-free.deepl.com（Free 层 50 万字符/月）。
pub struct DeepLProvider {
    key: Option<String>,
}

impl DeepLProvider {
    pub fn new() -> Self {
        Self { key: None }
    }
}

impl Default for DeepLProvider {
    fn default() -> Self {
        Self::new()
    }
}

impl TranslationProvider for DeepLProvider {
    fn name(&self) -> &str {
        "deepl"
    }

    fn translate(&self, text: &str, from: Lang, to: Lang) -> Result<Translation> {
        let key = self.key.clone().ok_or_else(|| {
            Error::NotConfigured("DeepL 未配置 API Key，请先在设置中配置".to_string())
        })?;
        let body = deepl_body(text, from, to);
        let resp = ureq::post("https://api-free.deepl.com/v2/translate")
            .set("Authorization", &format!("DeepL-Auth-Key {key}"))
            .send_json(body)
            .map_err(|e| Error::Network {
                detail: format!("DeepL 请求失败: {e}"),
                source_text: text.to_string(),
            })?;
        let json: serde_json::Value = resp.into_json().map_err(|e| Error::Network {
            detail: format!("DeepL 响应解析失败: {e}"),
            source_text: text.to_string(),
        })?;
        let translated = json["translations"][0]["text"].as_str().ok_or_else(|| {
            Error::Network {
                detail: "DeepL 响应缺少 translations[0].text".to_string(),
                source_text: text.to_string(),
            }
        })?;
        Ok(Translation {
            text: translated.to_string(),
            from,
            to,
            provider: self.name().to_string(),
        })
    }

    fn configure(&mut self, key: Option<&str>) {
        self.key = key.map(|s| s.to_string());
    }
}

/// Echo Provider（mock/演示）：无 key 可用，返回 "译文:" + 原文。
/// 经 `translate_set_config("echo", "")` 切换默认 Provider 后即无 key 演示（ADR 关联裁定2）。
pub struct EchoProvider;

impl TranslationProvider for EchoProvider {
    fn name(&self) -> &str {
        "echo"
    }

    fn translate(&self, text: &str, from: Lang, to: Lang) -> Result<Translation> {
        Ok(Translation {
            text: format!("译文:{text}"),
            from,
            to,
            provider: self.name().to_string(),
        })
    }
}

/// 离线翻译 Provider：基于已装入的内置/用户词典做词/短语查义（零网络、零 API Key）。
/// 「查词闭包」由 api.rs 注入（锁定 DICT 静态），避免 domain→interface 依赖。
/// 词典式离线翻译：整词/整句命中 → 释义；未命中 → 按空格分词逐词查义并拼合。
pub struct OfflineProvider {
    lookup: Box<dyn Fn(&str, Option<&str>) -> Result<Option<DictEntry>> + Send>,
}

impl OfflineProvider {
    pub fn new(
        lookup: Box<dyn Fn(&str, Option<&str>) -> Result<Option<DictEntry>> + Send>,
    ) -> Self {
        Self { lookup }
    }
}

impl TranslationProvider for OfflineProvider {
    fn name(&self) -> &str {
        "offline"
    }

    fn needs_key(&self) -> bool {
        false
    }

    fn translate(&self, text: &str, from: Lang, to: Lang) -> Result<Translation> {
        let norm = crate::dict::translation::normalize_text(text);
        if norm.is_empty() {
            return Err(Error::Other("待翻译文本为空".to_string()));
        }
        let mut parts: Vec<String> = Vec::new();
        if let Some(e) = (self.lookup)(&norm, None)? {
            parts.push(e.definition);
        } else {
            for w in norm.split_whitespace() {
                if let Some(e) = (self.lookup)(w, None)? {
                    parts.push(e.definition);
                }
            }
        }
        if parts.is_empty() {
            return Err(Error::NotConfigured(
                "离线翻译未命中（请先安装内置词库）".to_string(),
            ));
        }
        Ok(Translation {
            text: parts.join("；"),
            from,
            to,
            provider: self.name().to_string(),
        })
    }
}

/// 构造 DeepL 请求体（纯函数：把"只含 text/from/to"的隐私约束与 Auto 分支抽成
/// 可无网络单测的结构单元；行为与内联版完全一致，rework-D 仅做提取不改语义）。
/// 隐私（US-9/US-13）：请求体只含 text/target_lang[/source_lang]，无书路径/元数据。
/// Auto（自动检测）不传 source_lang（DeepL 语义）。
fn deepl_body(text: &str, from: Lang, to: Lang) -> serde_json::Value {
    let mut body = serde_json::json!({
        "text": [text],
        "target_lang": deepl_code(to),
    });
    if from != Lang::Auto {
        body["source_lang"] = serde_json::json!(deepl_code(from));
    }
    body
}

/// DeepL 语言代码（大写）："en"→"EN"、"zh"→"ZH"…
fn deepl_code(l: Lang) -> &'static str {
    match l {
        Lang::Auto => "EN", // 不会被使用（Auto 分支不传 source_lang）
        Lang::En => "EN",
        Lang::Zh => "ZH",
        Lang::Ja => "JA",
        Lang::Ko => "KO",
        Lang::Fr => "FR",
        Lang::De => "DE",
        Lang::Es => "ES",
        Lang::Ru => "RU",
        Lang::Other(s) => s,
    }
}

// ---------- 测试用 Provider（cfg(test)，服务层单测注入用） ----------

/// 计数 + 参数记录 Provider（US-9/10/11 的 mock 计数与参数断言锚点）
#[cfg(test)]
pub(crate) struct CountingProvider {
    pub calls: std::cell::Cell<u32>,
    pub last_text: std::cell::RefCell<Option<String>>,
    pub last_from: std::cell::Cell<Lang>,
    pub last_to: std::cell::Cell<Lang>,
    pub inner: Box<dyn TranslationProvider>,
}

#[cfg(test)]
impl CountingProvider {
    pub fn new(inner: Box<dyn TranslationProvider>) -> Self {
        Self {
            calls: std::cell::Cell::new(0),
            last_text: std::cell::RefCell::new(None),
            last_from: std::cell::Cell::new(Lang::Auto),
            last_to: std::cell::Cell::new(Lang::Auto),
            inner,
        }
    }
}

#[cfg(test)]
impl TranslationProvider for CountingProvider {
    fn name(&self) -> &str {
        // 包装 Provider 的名字透传内层（路由按 name 匹配）
        self.inner.name()
    }

    fn translate(&self, text: &str, from: Lang, to: Lang) -> Result<Translation> {
        self.calls.set(self.calls.get() + 1);
        *self.last_text.borrow_mut() = Some(text.to_string());
        self.last_from.set(from);
        self.last_to.set(to);
        self.inner.translate(text, from, to)
    }
}

/// 必然失败的 Provider（US-12：FailingProvider 调用即 Err(Network)，不写缓存）
#[cfg(test)]
pub(crate) struct FailingProvider {
    pub detail: String,
}

#[cfg(test)]
impl TranslationProvider for FailingProvider {
    fn name(&self) -> &str {
        "failing"
    }

    fn translate(&self, text: &str, _from: Lang, _to: Lang) -> Result<Translation> {
        Err(Error::Network {
            detail: self.detail.clone(),
            source_text: text.to_string(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn echo_returns_translation_with_provider_name() {
        let echo = EchoProvider;
        let t = echo.translate("Hello world", Lang::En, Lang::Zh).unwrap();
        assert_eq!(t.text, "译文:Hello world");
        assert_eq!(t.provider, "echo");
        assert_eq!(t.from, Lang::En);
        assert_eq!(t.to, Lang::Zh);
    }

    #[test]
    fn deepl_unconfigured_is_not_configured() {
        let deepl = DeepLProvider::new();
        let err = deepl.translate("hi", Lang::En, Lang::Zh).unwrap_err();
        assert!(matches!(err, Error::NotConfigured(_)), "应 NotConfigured: {err}");
        let msg = err.to_string();
        assert!(msg.contains("API Key"), "消息应含 API Key: {msg}");
    }

    #[test]
    fn deepl_configured_builds_request_without_network() {
        // 不真发网络：仅验证 configure 生效后错误变体为 Network（而非 NotConfigured）
        let mut deepl = DeepLProvider::new();
        deepl.configure(Some("fake-key"));
        let err = deepl.translate("hi", Lang::En, Lang::Zh).unwrap_err();
        assert!(
            matches!(err, Error::Network { .. }),
            "配置后应走网络路径: {err}"
        );
        // 错误携带原文（US-12）
        let msg = err.to_string();
        assert!(msg.contains("hi"), "错误应携带原文本: {msg}");
    }

    #[test]
    fn counting_provider_counts_and_records_args() {
        let cp = CountingProvider::new(Box::new(EchoProvider));
        cp.translate("a b", Lang::En, Lang::Zh).unwrap();
        cp.translate("a b", Lang::En, Lang::Zh).unwrap();
        assert_eq!(cp.calls.get(), 2);
        assert_eq!(cp.last_text.borrow().as_deref(), Some("a b"));
        assert_eq!(cp.last_from.get(), Lang::En);
        assert_eq!(cp.last_to.get(), Lang::Zh);
    }

    #[test]
    fn deepl_body_omits_source_lang_for_auto() {
        // 杀死 provider.rs:42 的 `!=`→`==` 变异：变异后 from=Auto 会错误附加
        // source_lang=EN（违反 DeepL 自动检测语义与 US-9 参数契约）
        let b = deepl_body("hello", Lang::Auto, Lang::Zh);
        assert_eq!(b["text"][0], "hello");
        assert_eq!(b["target_lang"], "ZH");
        assert!(b.get("source_lang").is_none(), "Auto 不应传 source_lang");
    }

    #[test]
    fn deepl_body_includes_source_lang_when_specified() {
        let b = deepl_body("hello", Lang::En, Lang::Zh);
        assert_eq!(b["text"][0], "hello");
        assert_eq!(b["target_lang"], "ZH");
        assert_eq!(b["source_lang"], "EN");
    }

    #[test]
    fn deepl_code_maps_all_langs() {
        // 杀死 deepl_code 恒 "" / 恒 "xyzzy" 两个变异（provider.rs:97）
        assert_eq!(deepl_code(Lang::Auto), "EN");
        assert_eq!(deepl_code(Lang::En), "EN");
        assert_eq!(deepl_code(Lang::Zh), "ZH");
        assert_eq!(deepl_code(Lang::Ja), "JA");
        assert_eq!(deepl_code(Lang::Ko), "KO");
        assert_eq!(deepl_code(Lang::Fr), "FR");
        assert_eq!(deepl_code(Lang::De), "DE");
        assert_eq!(deepl_code(Lang::Es), "ES");
        assert_eq!(deepl_code(Lang::Ru), "RU");
        assert_eq!(deepl_code(Lang::Other("PT")), "PT", "Other 臂原样透传");
    }

    #[test]
    fn offline_provider_looks_up_dict_without_key_and_misses_error() {
        use crate::dict::OfflineProvider;
        // 命中闭包（模拟词典大小写不敏感查义）
        let hit = OfflineProvider::new(Box::new(|word, _| {
            if word.to_lowercase() == "apple" {
                Ok(Some(crate::dict::DictEntry {
                    word: "apple".into(),
                    phonetic: Some("/ˈæp.əl/".into()),
                    pos: Some("n.".into()),
                    definition: "苹果".into(),
                    example: None,
                }))
            } else {
                Ok(None)
            }
        }));
        // offline 不需要 key（核心诉求：开箱即用离线翻译）
        assert!(!hit.needs_key(), "offline 不需要 key");
        let t = hit.translate("Apple", Lang::En, Lang::Zh).unwrap();
        assert_eq!(t.text, "苹果");
        assert_eq!(t.text.is_empty(), false);
        assert_eq!(t.provider, "offline");

        // 整词未命中 → 逐词查义拼合
        let t2 = hit.translate("apple apple", Lang::En, Lang::Zh).unwrap();
        assert_eq!(t2.text, "苹果；苹果");

        // 全未命中 → Err
        let miss = OfflineProvider::new(Box::new(|_, _| Ok(None)));
        assert!(miss.translate("zzzqqq", Lang::En, Lang::Zh).is_err());
    }
}
