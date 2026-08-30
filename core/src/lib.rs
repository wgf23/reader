//! `reader_core` —— 阅读器核心库（Rust）。
//!
//! 分层与职责：docs/03-architecture.md；领域模型与接口：docs/04-module-design.md。
//! 骨架状态：模块桩就位，业务逻辑自 P0 起逐模块填充。
//!
//! 约定：
//! - 任何输入（含损坏/恶意文件）不得 panic，一律返回 `Result`。
//! - 不依赖网络；在线翻译只通过 Provider 接口接入。

pub mod error;
pub mod types;

pub mod api;
pub mod frb_generated;

pub mod format;
pub mod convert;
pub mod locator;
pub mod library;
pub mod notes;
pub mod dict;
pub mod search;
pub mod tts;
pub mod store;

/// 核心库版本（展示用，与 Cargo 版本解耦）
pub const CORE_VERSION: &str = env!("CARGO_PKG_VERSION");

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn core_version_present() {
        assert!(!CORE_VERSION.is_empty());
    }
}
