//! 共享错误类型：核心层所有模块统一返回 `Error`。
//!
//! 原则（docs/03 §8）：任何输入（含损坏/恶意文件）不得 panic，一律映射为
//! 结构化错误，UI 侧给出用户可读文案。

use std::io;

/// 核心层统一错误
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("文件损坏或格式异常：{0}")]
    Corrupt(String),

    /// DRM/加密标记（docs/03 §8 错误分类的 Encrypted 类；UI 文案对齐
    /// LIB-01"可能受 DRM 保护"，不涉及任何破解行为）
    #[error("文件可能受 DRM/加密保护，无法解析：{0}")]
    Encrypted(String),

    #[error("不支持的格式：{0}")]
    UnsupportedFormat(String),

    #[error("未找到：{0}")]
    NotFound(String),

    #[error("IO 错误：{0}")]
    Io(#[from] io::Error),

    #[error("尚未实现（P0/P1 里程碑）")]
    NotImplemented,

    #[error("{0}")]
    Other(String),
}

impl From<rusqlite::Error> for Error {
    fn from(e: rusqlite::Error) -> Self {
        Error::Corrupt(format!("数据库错误: {e}"))
    }
}

pub type Result<T> = std::result::Result<T, Error>;
