//! DDD / 分层合规检测（docs/07 §6）。
//!
//! 读 ddd-rules.toml（层 → 路径前缀 + 禁止依赖），扫描 .rs/.dart 的 use/import，
//! 违例输出报告；退出码：存在违规 → 1。
//!
//! 用法：ddd-lint check <repo-root> [--rules <ddd-rules.toml>] [--out <report.md>]

use std::path::{Path, PathBuf};

use serde::Deserialize;
use syn::spanned::Spanned;

#[derive(Debug, Deserialize)]
struct Layer {
    name: String,
    #[serde(default)]
    paths: Vec<String>,
    #[serde(default)]
    forbid_internal: Vec<String>,
    #[serde(default)]
    forbid_external: Vec<String>,
    #[serde(default)]
    forbid_imports: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct RulesFile {
    #[serde(default)]
    layers: Vec<Layer>,
}

#[derive(Debug)]
struct Violation {
    file: String,
    line: usize,
    rule: String,
    import: String,
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 || args[1] != "check" {
        eprintln!("用法: ddd-lint check <repo-root> [--rules <ddd-rules.toml>] [--out <report.md>]");
        std::process::exit(2);
    }
    let root = PathBuf::from(&args[2]);
    let mut rules_path = PathBuf::from("ddd-rules.toml");
    let mut out_path = "ddd-report.md".to_string();
    let mut i = 3;
    while i < args.len() {
        match args[i].as_str() {
            "--rules" => {
                i += 1;
                if let Some(p) = args.get(i) {
                    rules_path = PathBuf::from(p);
                }
            }
            "--out" => {
                i += 1;
                if let Some(p) = args.get(i) {
                    out_path = p.clone();
                }
            }
            _ => {}
        }
        i += 1;
    }

    let rules: RulesFile = std::fs::read_to_string(&rules_path)
        .ok()
        .and_then(|t| toml::from_str(&t).ok())
        .unwrap_or_else(|| {
            eprintln!("[ddd-lint] 无法读取规则文件: {}", rules_path.display());
            std::process::exit(2);
        });

    let mut violations = Vec::new();
    for entry in walkdir::WalkDir::new(&root).into_iter().filter_map(|e| e.ok()) {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let rel = path
            .strip_prefix(&root)
            .unwrap_or(path)
            .to_string_lossy()
            .replace('\\', "/");
        if is_ignored(&rel) {
            continue;
        }
        let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("");
        let Some(layer) = rules.layers.iter().find(|l| matches_layer(&rel, &l.paths)) else {
            continue; // 未声明层的文件不检查
        };
        let text = std::fs::read_to_string(path).unwrap_or_default();
        match ext {
            "rs" => check_rust(&rel, &text, layer, &mut violations),
            "dart" => check_dart(&rel, &text, layer, &mut violations),
            _ => {}
        }
    }

    // 报告
    let mut md = String::from("# DDD / 分层合规报告\n\n");
    md.push_str("| 文件 | 行 | 规则 | 违规 import |\n|---|---|---|---|\n");
    for v in &violations {
        md.push_str(&format!(
            "| {} | {} | {} | `{}` |\n",
            v.file, v.line, v.rule, v.import
        ));
    }
    md.push_str(&format!("\n**违规总数：{}**\n", violations.len()));
    std::fs::write(&out_path, &md).expect("写报告失败");
    println!("[ddd-lint] 报告已写入 {out_path}（违规={}）", violations.len());

    if !violations.is_empty() {
        std::process::exit(1);
    }
}

fn is_ignored(rel: &str) -> bool {
    let parts: Vec<&str> = rel.split('/').collect();
    parts.iter().any(|p| {
        matches!(
            *p,
            "target" | "build" | ".git" | ".dart_tool" | "node_modules" | ".idea" | "Pods"
        )
    }) || rel.ends_with("frb_generated.rs")
        || rel.starts_with("app/lib/src/rust/")
}

fn matches_layer(rel: &str, paths: &[String]) -> bool {
    paths.iter().any(|p| rel == p || rel.starts_with(&format!("{p}/")) || rel.starts_with(p))
}

fn check_rust(rel: &str, text: &str, layer: &Layer, out: &mut Vec<Violation>) {
    let Ok(syn_file) = syn::parse_file(text) else {
        return;
    };
    for item in &syn_file.items {
        if let syn::Item::Use(u) = item {
            let import = tokens_of_use(u);
            let line = u.span().start().line;
            // 内部依赖检查
            for forb in &layer.forbid_internal {
                if let Some(key) = normalize_internal(forb) {
                    if let Some(norm) = normalize_internal(&import) {
                        if norm.starts_with(&key) {
                            out.push(Violation {
                                file: rel.to_string(),
                                line,
                                rule: format!("layer[{}].forbid_internal={forb}", layer.name),
                                import: import.clone(),
                            });
                        }
                    }
                }
            }
            // 外部 crate 检查
            if let Some(crate_name) = external_crate_name(&import) {
                if layer.forbid_external.iter().any(|f| f == &crate_name) {
                    out.push(Violation {
                        file: rel.to_string(),
                        line,
                        rule: format!("layer[{}].forbid_external", layer.name),
                        import: import.clone(),
                    });
                }
            }
        }
    }
}

fn tokens_of_use(u: &syn::ItemUse) -> String {
    use quote::ToTokens;
    u.to_token_stream().to_string().replace("use ", "").replace(';', "")
}

/// 归一化内部路径：剥掉 crate::/reader_core::/self::/super:: 前缀 → 首段
fn normalize_internal(path: &str) -> Option<String> {
    let mut p = path.trim().to_string();
    for _ in 0..4 {
        for pre in ["crate::", "reader_core::", "self::", "super::"] {
            if p.starts_with(pre) {
                p = p[pre.len()..].to_string();
            }
        }
    }
    if p.is_empty() || p.starts_with("::") {
        None
    } else {
        Some(p.split("::").next().unwrap_or("").to_string())
    }
}

fn external_crate_name(path: &str) -> Option<String> {
    let first = path.split("::").next()?.trim().to_string();
    let builtin = ["crate", "self", "super", "std", "core", "alloc"];
    if builtin.contains(&first.as_str()) {
        None
    } else {
        Some(first)
    }
}

fn check_dart(rel: &str, text: &str, layer: &Layer, out: &mut Vec<Violation>) {
    for (idx, line) in text.lines().enumerate() {
        let line = line.trim();
        if !line.starts_with("import ") {
            continue;
        }
        for forb in &layer.forbid_imports {
            if line.contains(forb.as_str()) {
                out.push(Violation {
                    file: rel.to_string(),
                    line: idx + 1,
                    rule: format!("layer[{}].forbid_imports={forb}", layer.name),
                    import: line.to_string(),
                });
            }
        }
    }
}
