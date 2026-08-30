//! 词典与翻译：StarDict 离线词库（查词零网络）+ 在线翻译 Provider + 结果缓存。
//!
//! 设计：docs/04-module-design.md §7、docs/02-technical.md §8。
//! 缓存键：(原文, from, to, provider)，见 docs/04 §5 translation_cache 表。

/// 在线翻译 Provider 统一接口（DeepL / Google / 有道 / OpenAI 适配器）
pub trait TranslationProvider {
    fn name(&self) -> &str;
    // TODO(P0): async fn translate(&self, text, from, to) -> Result<Translation>
}

pub struct TranslationService;

impl TranslationService {
    // TODO(P0):
    //   lookup(word) -> Option<DictEntry>          // StarDict 本地查词
    //   translate(text, from, to) -> Translation   // 缓存优先
    //   install_dict(path) / list_dicts()
}
