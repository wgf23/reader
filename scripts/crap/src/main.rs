//! 自研 CRAP 评分工具（docs/07 §5）。
//!
//! CRAP(f) = CC(f)² × (1 − cov(f))³ + CC(f) + D(f)
//!   CC  = 圈复杂度（syn 统计：if/match-arm/loop/&&/||/?/closure）
//!   cov = 函数级行覆盖率（llvm-cov export --format=json，可缺省）
//!   D   = 重复惩罚（函数体 5-gram Jaccard 相似度 > 阈值 → +15）
//!
//! 用法：
//!   crap scan <src-dir> [--cov <llvm-cov.json>] [--config <crap-config.toml>] [--out <report.md>]
//! 退出码：存在 FAIL → 1；否则 0。

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;

use syn::spanned::Spanned;
use syn::visit::{self, Visit};

#[derive(Debug, Clone, serde::Serialize)]
struct FnInfo {
    name: String,
    file: String,
    line: usize,
    cc: f64,
    cov: Option<f64>,
    dup: f64,
    crap: f64,
    verdict: String,
}

#[derive(Debug, serde::Deserialize)]
struct Config {
    fail_threshold: Option<f64>,
    warn_threshold: Option<f64>,
    dup_threshold: Option<f64>,
    dup_penalty: Option<f64>,
    dup_min_tokens: Option<usize>,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            fail_threshold: Some(25.0),
            warn_threshold: Some(15.0),
            dup_threshold: Some(0.6),
            dup_penalty: Some(15.0),
            dup_min_tokens: Some(120),
        }
    }
}

/// 圈复杂度计数器（visit 每个分支结构）
struct Complexity {
    score: f64,
}

impl<'ast> Visit<'ast> for Complexity {
    fn visit_expr_if(&mut self, node: &'ast syn::ExprIf) {
        self.score += 1.0;
        visit::visit_expr_if(self, node);
    }
    fn visit_expr_match(&mut self, node: &'ast syn::ExprMatch) {
        self.score += node.arms.len() as f64;
        visit::visit_expr_match(self, node);
    }
    fn visit_expr_loop(&mut self, node: &'ast syn::ExprLoop) {
        self.score += 1.0;
        visit::visit_expr_loop(self, node);
    }
    fn visit_expr_while(&mut self, node: &'ast syn::ExprWhile) {
        self.score += 1.0;
        visit::visit_expr_while(self, node);
    }
    fn visit_expr_for_loop(&mut self, node: &'ast syn::ExprForLoop) {
        self.score += 1.0;
        visit::visit_expr_for_loop(self, node);
    }
    fn visit_expr_binary(&mut self, node: &'ast syn::ExprBinary) {
        if matches!(node.op, syn::BinOp::And(_) | syn::BinOp::Or(_)) {
            self.score += 1.0;
        }
        visit::visit_expr_binary(self, node);
    }
    fn visit_expr_try(&mut self, node: &'ast syn::ExprTry) {
        self.score += 0.5;
        visit::visit_expr_try(self, node);
    }
    fn visit_expr_closure(&mut self, node: &'ast syn::ExprClosure) {
        self.score += 0.5;
        visit::visit_expr_closure(self, node);
    }
}

/// 函数收集器（同时保存函数体 token 序列供重复检测）
struct FnCollector {
    fns: Vec<FnInfo>,
    bodies: Vec<String>,
    current_file: String,
}

impl FnCollector {
    fn add(&mut self, name: &str, line: usize, block: &syn::Block) {
        let mut cplx = Complexity { score: 0.0 };
        cplx.visit_block(block);
        use quote::ToTokens;
        let body = block.to_token_stream().to_string();
        self.fns.push(FnInfo {
            name: name.to_string(),
            file: self.current_file.clone(),
            line,
            cc: cplx.score,
            cov: None,
            dup: 0.0,
            crap: 0.0,
            verdict: String::new(),
        });
        self.bodies.push(body);
    }
}

impl<'ast> Visit<'ast> for FnCollector {
    fn visit_item_fn(&mut self, node: &'ast syn::ItemFn) {
        let name = node.sig.ident.to_string();
        self.add(&name, node.sig.span().start().line, &node.block);
    }
    fn visit_impl_item_fn(&mut self, node: &'ast syn::ImplItemFn) {
        let name = node.sig.ident.to_string();
        self.add(&name, node.sig.span().start().line, &node.block);
    }
    fn visit_trait_item_fn(&mut self, node: &'ast syn::TraitItemFn) {
        if let Some(block) = &node.default {
            let name = node.sig.ident.to_string();
            self.add(&name, node.sig.span().start().line, block);
        }
    }
}

/// 解析 llvm-cov JSON 的文件级行覆盖率：文件路径 → 行覆盖百分比
fn load_coverage(path: &str) -> HashMap<String, f64> {
    let text = std::fs::read_to_string(path).unwrap_or_default();
    #[derive(serde::Deserialize)]
    struct CovFile<'a> {
        #[serde(borrow)]
        data: Vec<CovData<'a>>,
    }
    #[derive(serde::Deserialize)]
    struct CovData<'a> {
        #[serde(borrow)]
        files: Vec<CovEntry<'a>>,
    }
    #[derive(serde::Deserialize)]
    struct CovEntry<'a> {
        #[serde(borrow)]
        filename: &'a str,
        summary: CovSummary,
    }
    #[derive(serde::Deserialize)]
    struct CovSummary {
        lines: LinesSummary,
    }
    #[derive(serde::Deserialize)]
    struct LinesSummary {
        percent: f64,
    }
    let mut map = HashMap::new();
    if let Ok(cov) = serde_json::from_str::<CovFile>(&text) {
        for data in cov.data {
            for f in data.files {
                map.insert(f.filename.replace('\\', "/"), f.summary.lines.percent);
            }
        }
    }
    map
}

/// n-gram 重复检测：任意两函数体 Jaccard 相似度 > 阈值 → 各 +D
fn detect_duplication(infos: &mut [FnInfo], bodies: &[String], cfg: &Config) {
    let n = 5usize;
    let grams: Vec<Vec<String>> = bodies
        .iter()
        .map(|b| {
            let tokens: Vec<&str> = b.split_whitespace().collect();
            tokens.windows(n).map(|w| w.join(" ")).collect()
        })
        .collect();
    let min_tokens = cfg.dup_min_tokens.unwrap_or(120);
    let threshold = cfg.dup_threshold.unwrap_or(0.6);
    let penalty = cfg.dup_penalty.unwrap_or(15.0);

    for i in 0..infos.len() {
        for j in (i + 1)..infos.len() {
            let a = &grams[i];
            let b = &grams[j];
            if a.len() < min_tokens || b.len() < min_tokens {
                continue;
            }
            let set_a: HashSet<&String> = a.iter().collect();
            let set_b: HashSet<&String> = b.iter().collect();
            let inter = set_a.intersection(&set_b).count();
            let union = set_a.len() + set_b.len() - inter;
            if union == 0 {
                continue;
            }
            let sim = inter as f64 / union as f64;
            if sim > threshold {
                infos[i].dup = penalty;
                infos[j].dup = penalty;
            }
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 || args[1] != "scan" {
        eprintln!("用法: crap scan <src-dir> [--cov json] [--config toml] [--out report.md]");
        std::process::exit(2);
    }
    let src_dir = PathBuf::from(&args[2]);
    let mut cov_path = None;
    let mut config_path = None;
    let mut out_path = None;
    let mut i = 3;
    while i < args.len() {
        match args[i].as_str() {
            "--cov" => {
                i += 1;
                cov_path = args.get(i).cloned();
            }
            "--config" => {
                i += 1;
                config_path = args.get(i).cloned();
            }
            "--out" => {
                i += 1;
                out_path = args.get(i).cloned();
            }
            _ => {}
        }
        i += 1;
    }

    let cfg: Config = config_path
        .and_then(|p| std::fs::read_to_string(&p).ok())
        .and_then(|t| toml::from_str(&t).ok())
        .unwrap_or_default();
    let fail_th = cfg.fail_threshold.unwrap_or(25.0);
    let warn_th = cfg.warn_threshold.unwrap_or(15.0);
    let has_cov = cov_path.is_some();
    let cov_map = cov_path.as_deref().map(load_coverage).unwrap_or_default();

    // 收集函数
    let mut collector = FnCollector {
        fns: Vec::new(),
        bodies: Vec::new(),
        current_file: String::new(),
    };
    for entry in walkdir::WalkDir::new(&src_dir)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        let path = entry.path();
        let rel = path.display().to_string().replace('\\', "/");
        if path.extension().map(|e| e == "rs").unwrap_or(false)
            && !rel.ends_with("frb_generated.rs")
            && !rel.ends_with("src/api.rs")
        {
            if let Ok(text) = std::fs::read_to_string(path) {
                collector.current_file = path.display().to_string();
                if let Ok(syn_file) = syn::parse_file(&text) {
                    for item in &syn_file.items {
                        match item {
                            syn::Item::Fn(f) => collector.visit_item_fn(f),
                            syn::Item::Impl(imp) => {
                                for it in &imp.items {
                                    if let syn::ImplItem::Fn(f) = it {
                                        collector.visit_impl_item_fn(f);
                                    }
                                }
                            }
                            syn::Item::Trait(tr) => {
                                for it in &tr.items {
                                    if let syn::TraitItem::Fn(f) = it {
                                        collector.visit_trait_item_fn(f);
                                    }
                                }
                            }
                            _ => {}
                        }
                    }
                }
            }
        }
    }

    let mut fns = collector.fns;
    // 覆盖率匹配：文件级行覆盖率（按绝对路径精确匹配）
    for f in fns.iter_mut() {
        let file_key = f.file.replace('\\', "/");
        // 扫描路径可能是相对路径，coverage 为绝对路径 → 后缀匹配
        f.cov = cov_map
            .iter()
            .find_map(|(k, pct)| k.ends_with(&file_key).then(|| *pct / 100.0));
    }
    if !has_cov {
        eprintln!("[crap] 未提供 --cov，覆盖率按 N/A 处理（仅复杂度+重复参与判定）");
    }

    detect_duplication(&mut fns, &collector.bodies, &cfg);

    // 计算 CRAP 与判定
    for f in fns.iter_mut() {
        let cov = f.cov.unwrap_or(0.0);
        let crap = f.cc * f.cc * (1.0 - cov).powi(3) + f.cc + f.dup;
        f.crap = crap;
        f.verdict = if !has_cov && f.cov.is_none() {
            "N/A(缺覆盖)".to_string()
        } else if crap >= fail_th {
            "FAIL".to_string()
        } else if crap >= warn_th {
            "WARN".to_string()
        } else {
            "PASS".to_string()
        };
    }

    // 报告
    let mut md = String::from("# CRAP 评分报告\n\n");
    md.push_str(&format!(
        "> 配置: FAIL≥{fail_th} / WARN≥{warn_th} ｜ 覆盖率数据: {}\n\n",
        has_cov
    ));
    md.push_str("| 文件 | 函数 | 行 | CC | cov | D | CRAP | 判定 |\n|---|---|---|---|---|---|---|---|\n");
    for f in fns.iter() {
        let cov = f
            .cov
            .map(|c| format!("{:.0}%", c * 100.0))
            .unwrap_or_else(|| "N/A".to_string());
        md.push_str(&format!(
            "| {} | {} | {} | {:.0} | {} | {:.0} | **{:.1}** | {} |\n",
            short_path(&f.file),
            f.name,
            f.line,
            f.cc,
            cov,
            f.dup,
            f.crap,
            f.verdict
        ));
    }
    let fails = fns.iter().filter(|f| f.verdict == "FAIL").count();
    let warns = fns.iter().filter(|f| f.verdict == "WARN").count();
    md.push_str(&format!(
        "\n**汇总：FAIL={fails}，WARN={warns}，PASS={}**\n",
        fns.iter().filter(|f| f.verdict == "PASS").count()
    ));

    let out = out_path.unwrap_or_else(|| "crap-report.md".to_string());
    std::fs::write(&out, &md).expect("写报告失败");
    println!("[crap] 报告已写入 {out}（FAIL={fails} WARN={warns}）");

    if fails > 0 {
        std::process::exit(1);
    }
}

fn short_path(p: &str) -> String {
    p.replace('\\', "/")
        .split('/')
        .rev()
        .take(3)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect::<Vec<_>>()
        .join("/")
}
