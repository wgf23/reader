#!/usr/bin/env python3
"""
product-preview.py —— 生成「设计稿 ↔ 实现截图」产品预览对照报告（自包含 HTML）。

用途：工作流「产品验收」环节的工具（workflow/skills/product-preview.md）。
给产品/用户一个可浏览器打开的单文件：每屏左侧设计稿、右侧实现截图，并列出
设计意图 + 验收点（产品勾选）+ 偏差备注，并自动告警视口方向不一致（设计稿横屏、
真机竖屏是常见分歧根源）。

零依赖：仅标准库。SVG 内联（浏览器原生渲染），PNG base64 内嵌，输出单文件可分享。

用法：
  python3 scripts/product-preview.py <manifest.json> -o <out.html> [-r REQ-XXX] [--title "..."]
  python3 scripts/product-preview.py --sample

manifest 结构（JSON），字段见 build_screen_block()：
{
  "req": "REQ-004", "product": "阅读器页交互重构",
  "screens": [
    { "id": "S1", "name": "书架", "device": "mobile",
      "design": {"svg": "docs/wireframes/01-library.svg", "viewport": "900x640", "label": "设计稿 v1"},
      "impl":   {"png": "app/test/goldens/library.png",    "viewport": "1170x2532", "label": "golden 截图"},
      "intent": ["侧边导航 + 封面网格 + 继续阅读徽标"],
      "acceptance": ["侧边导航可见", "封面墙 2 行 6 本", "继续阅读徽标"] }
  ]
}
"""
import argparse
import base64
import html
import json
import os
import re
import sys
from datetime import datetime

# CSS 常量：内含 `%` 与 `{}`，独立存放避开任何格式化冲突。
CSS = """
:root{--fg:#202124;--muted:#5f6368;--line:#e1e4e8;--blue:#1a73e8;--warn:#d93025}
*{box-sizing:border-box;font-family:system-ui,'PingFang SC','Microsoft YaHei',sans-serif}
body{margin:0;background:#f7f8fa;color:var(--fg);padding:24px;font-size:14px}
h1{font-size:20px;margin:0 0 4px}h2{font-size:15px;color:var(--muted);font-weight:400;margin:0 0 16px}
.page{max-width:1100px;margin:0 auto}
.stats{display:flex;gap:12px;margin:12px 0 20px;flex-wrap:wrap}
.stats span{padding:6px 12px;background:#fff;border:1px solid var(--line);border-radius:8px;font-size:13px;color:var(--muted)}
.stats b{color:var(--fg)}
.stats .warn-t{border-color:var(--warn);color:var(--warn)}
.stats .warn-t b{color:var(--warn)}
.gaps{background:#fff5f5;border:1px solid var(--warn);border-radius:10px;padding:14px 18px;margin-bottom:20px}
.gaps ul{margin:8px 0 0;padding-left:20px}
.screen{background:#fff;border:1px solid var(--line);border-radius:12px;margin:0 0 24px;padding:16px 18px;box-shadow:0 1px 2px rgba(0,0,0,.04)}
.screen header h3{margin:0 0 6px;font-size:16px}
.screen header h3 small{color:var(--muted);font-weight:400;margin-left:8px}
.screen .meta{font-size:12px;color:var(--muted);margin-top:4px}
.badge{padding:2px 8px;border-radius:6px;font-size:12px;margin-left:8px}
.badge.warn{background:var(--warn);color:#fff}
.cols{display:flex;gap:16px;margin-top:12px;flex-wrap:wrap}
.col{flex:1;min-width:280px;margin:0}
.col figcaption{font-size:13px;color:var(--muted);margin-bottom:6px}
.col figcaption em{font-style:normal;color:var(--blue)}
.canvas{background:#fafafa;border:1px solid var(--line);border-radius:8px;overflow:hidden;display:flex;justify-content:center;min-height:220px}
.canvas svg{width:100%;max-width:520px;height:auto}
.canvas.empty{color:var(--muted);align-items:center;font-size:13px}
img.impl{width:100%;max-width:300px;border:1px solid var(--line);border-radius:8px;display:block;margin:0 auto}
.notes{margin-top:14px;border-top:1px dashed var(--line);padding-top:12px}
.notes strong{display:inline-block;margin-bottom:6px}
.intent ul{margin:4px 0 12px;padding-left:18px}
.accept .accwrap{display:flex;flex-wrap:wrap;gap:8px}
.acc{display:inline-flex;align-items:center;gap:5px;background:#eef3fd;border:1px solid #d5e2fb;border-radius:6px;padding:5px 10px;font-size:13px;cursor:pointer}
.verdict{margin:14px 0 8px;display:flex;gap:16px;align-items:center;flex-wrap:wrap}
.verdict label{display:inline-flex;align-items:center;gap:5px;cursor:pointer;font-size:13px}
.verdict input[type=radio]{accent-color:var(--blue)}
textarea.dev{width:100%;min-height:52px;border:1px solid var(--line);border-radius:8px;padding:8px;font-size:13px;resize:vertical}
.footer{color:var(--muted);font-size:12px;margin-top:8px;text-align:center}
@media print{.screen{page-break-inside:avoid}}
"""


def read_b64(path: str) -> str:
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


def esc(s: str) -> str:
    return html.escape(str(s))


def svg_inline(path: str) -> str:
    raw = open(path, "r", encoding="utf-8").read()
    raw = re.sub(r"<\?xml[^>]*\?>", "", raw, count=1)
    return raw


def detect_viewport(spec) -> tuple:
    """从 'WxH' 或 svg viewBox 推断 (w, h)。"""
    s = (spec or {}).get("viewport", "")
    m = re.search(r"(\d+)\s*[x×]\s*(\d+)", s)
    if m:
        return int(m.group(1)), int(m.group(2))
    svg_path = (spec or {}).get("svg")
    if svg_path and os.path.exists(svg_path):
        svg = open(svg_path, "r", encoding="utf-8").read()
        vb = re.search(r'viewBox="([^"]+)"', svg)
        if vb:
            parts = vb.group(1).replace(",", " ").split()
            if len(parts) == 4:
                return int(parts[2]), int(parts[3])
    return 0, 0


def orient(w: int, h: int) -> str:
    if w == 0 or h == 0:
        return "未知"
    return "横屏" if w > h else ("竖屏" if h > w else "方正")


def resolve_impl_path(scr: dict, impl_dir: str | None) -> str | None:
    """解析该屏的实现截图路径：manifest 显式 png 优先，否则在 impl_dir 按 id/name 自动发现。
    返回绝对路径或 None（gap）。"""
    i = scr.get("impl", {})
    cands = []
    png = i.get("png")
    if png:
        cands.append(png)
    if impl_dir:
        for name in (scr.get("id"), scr.get("name")):
            if name:
                cands.append(os.path.join(impl_dir, str(name) + ".png"))
    for c in cands:
        if c and os.path.exists(c):
            return os.path.abspath(c)
    return None


def impl_source_label(i: dict, path: str) -> str:
    """标注截图来源：golden/Ahem widget 占位 vs 真实渲染/真机截图。"""
    hay = (os.path.basename(path) + " " + i.get("label", "")).lower()
    if any(k in hay for k in ("golden", "ahem", "widget", "占位")):
        return "golden 占位"
    if any(k in hay for k in ("real", "true", "device", "screencap", "drive", "integration", "真机")):
        return "真实截图"
    return "真实截图"


def build_screen_block(scr: dict, idx: int, impl_dir: str | None = None) -> str:
    d = scr.get("design", {})
    i = scr.get("impl", {})
    dw, dh = detect_viewport(d)
    iw, ih = detect_viewport(i)
    d_or = orient(dw, dh)
    i_or = orient(iw, ih)
    mismatch = (d_or in ("横屏", "竖屏")) and (d_or != i_or)

    if d.get("svg") and os.path.exists(d["svg"]):
        design_html = "<div class='canvas'>" + svg_inline(d["svg"]) + "</div>"
    else:
        design_html = "<div class='canvas empty'>（无设计稿）</div>"

    impl_path = resolve_impl_path(scr, impl_dir)
    if impl_path:
        b64 = read_b64(impl_path)
        src = impl_source_label(i, impl_path)
        impl_html = (
            "<img class='impl' alt='实现截图 · {src}' "
            "src='data:image/png;base64,{b64}'>".format(src=esc(src), b64=b64)
        )
        impl_label = esc(i.get("label", impl_source_label(i, impl_path)))
    else:
        impl_html = "<div class='canvas empty'>（无实现截图）</div>"
        impl_label = esc(i.get("label", ""))

    mismatch_badge = ""
    if mismatch:
        mismatch_badge = (
            "<span class='badge warn'>⚠ 视口不一致：设计 {d_or} ({dw}x{dh}) vs 实现 {i_or} ({iw}x{ih})</span>"
        ).format(d_or=d_or, dw=dw, dh=dh, i_or=i_or, iw=iw, ih=ih)

    intent_items = "".join("<li>{}</li>".format(esc(x)) for x in scr.get("intent", []))
    accept_boxes = "".join(
        "<label class='acc'><input type='checkbox' class='fx'> {}</label>".format(esc(x))
        for x in scr.get("acceptance", [])
    )

    name = esc(scr.get("name", "屏"))
    sid = esc(scr.get("id", ""))
    device = esc(scr.get("device", "mobile"))
    design_label = esc(d.get("label", ""))

    return (
        "<section class='screen' id='s{idx}'>"
        "<header><h3>#{idx} {name} <small>{sid}</small></h3>{badge}"
        "<div class='meta'>期望设备：{device} · 设计 {dl} · 实现 {il}</div></header>"
        "<div class='cols'>"
        "<figure class='col'><figcaption>设计稿 <em>{dl}</em></figcaption>{design}</figure>"
        "<figure class='col'><figcaption>实现截图 <em>{il}</em></figcaption>{impl}</figure>"
        "</div>"
        "<div class='notes'>"
        "<div class='intent'><strong>设计意图</strong><ul>{intent}</ul></div>"
        "<div class='accept'><strong>验收点（产品核对后勾选）</strong>"
        "<div class='accwrap'>{accept}</div></div>"
        "<div class='verdict'><strong>产品判定</strong>"
        "<label><input type='radio' name='v{idx}' class='fx2' value='pass'> 通过</label>"
        "<label><input type='radio' name='v{idx}' class='fx2' value='look'> 有偏差(标注)</label>"
        "<label><input type='radio' name='v{idx}' class='fx2' value='fail'> 不通过 → rework-B</label>"
        "</div>"
        "<textarea class='dev' placeholder='偏差描述 / 与设计稿差异 / 建议'></textarea>"
        "</div></section>"
    ).format(
        idx=idx, name=name, sid=sid, badge=mismatch_badge, device=device,
        dl=design_label, il=impl_label, design=design_html, impl=impl_html,
        intent=intent_items, accept=accept_boxes,
    )


def build_report(cfg: dict, impl_dir: str | None = None) -> str:
    req = esc(cfg.get("req", "REQ-XXX"))
    product = esc(cfg.get("product", ""))
    screens = cfg.get("screens", [])
    now = datetime.now().strftime("%Y-%m-%d %H:%M")

    mism = 0
    gap = ["屏#{} {}".format(i + 1, s.get("name", "")) for i, s in enumerate(screens)
           if resolve_impl_path(s, impl_dir) is None]
    for s in screens:
        d_or = orient(*detect_viewport(s.get("design", {})))
        i_or = orient(*detect_viewport(s.get("impl", {})))
        if d_or in ("横屏", "竖屏") and d_or != i_or:
            mism += 1

    stats = (
        "<div class='stats'>"
        "<span>总屏数 <b>{n}</b></span>"
        "<span class='{mc}'>视口不一致 <b>{m}</b></span>"
        "<span class='{gc}'>无实现截图 <b>{g}</b></span>"
        "</div>"
    ).format(n=len(screens), mc="warn-t" if mism else "ok-t", m=mism,
             gc="warn-t" if gap else "ok-t", g=len(gap))

    gap_block = ""
    if gap:
        items = "".join("<li>{}</li>".format(esc(x)) for x in gap)
        gap_block = (
            "<div class='gaps'><strong>⚠ 下列设计稿屏尚无对应实现截图（gap）：</strong>"
            "<ul>{items}</ul><p>说明：设计稿定义了这些屏，但当前无**实现截图**（真实渲染/真机截图，非 widget golden 占位）—— "
            "产品无法核对该屏是否达成设计，需补充实现截图或标注『未实现』。</p></div>"
        ).format(items=items)

    body = "".join(build_screen_block(s, i + 1, impl_dir) for i, s in enumerate(screens))

    return (
        "<!DOCTYPE html><html lang='zh-CN'><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>产品预览对照 · " + req + "</title>"
        "<style>" + CSS + "</style></head><body><div class='page'>"
        "<h1>产品预览对照报告 · " + req + "</h1>"
        "<h2>" + product + " · 生成于 " + now + "（工作流产品验收环节）</h2>"
        + stats + gap_block + body +
        "<div class='footer'>对照：设计稿（docs/wireframes/** 权威） vs 实现截图 · "
        "本报告仅呈现，最终 deviation 由产品判定</div>"
        "</div></body></html>"
    )


def make_sample() -> dict:
    return {
        "req": "REQ-004",
        "product": "阅读器页交互重构（演示报告）",
        "screens": [
            {
                "id": "S1", "name": "书架", "device": "mobile",
                "design": {"svg": "docs/wireframes/01-library.svg", "viewport": "900x640", "label": "设计稿 v1 · 书架"},
                "impl": {"png": "app/test/goldens/library.png", "viewport": "1170x2532", "label": "golden · 书架"},
                "intent": ["侧边导航(书库/笔记/生词本/设置) + 封面网格 + 继续阅读徽标 + 搜索框 + 导入按钮"],
                "acceptance": ["导航项齐全", "封面网格 ≥2 行", "继续阅读徽标", "搜索/导入入口可见"],
            },
            {
                "id": "S2", "name": "阅读器·沉浸态", "device": "mobile",
                "design": {"svg": "docs/wireframes/reader-ui-v2/01-immersive.svg", "viewport": "900x640", "label": "设计稿 v2 · 沉浸态"},
                "impl": {"png": "app/test/goldens/reader_immersive.png", "viewport": "1170x2532", "label": "golden · 沉浸态"},
                "intent": ["无 AppBar 全屏正文", "左右 15% 边缘热区翻页", "中部 1/3 点击呼出工具栏"],
                "acceptance": ["无常驻顶栏", "正文全屏", "点中部可呼出"],
            },
            {
                "id": "S3", "name": "阅读器·呼出顶底栏", "device": "mobile",
                "design": {"svg": "docs/wireframes/reader-ui-v2/02-menus.svg", "viewport": "900x640", "label": "设计稿 v2 · 呼出工具栏"},
                "impl": {"png": "app/test/goldens/reader_chrome.png", "viewport": "1170x2532", "label": "golden · 呼出工具栏"},
                "intent": ["顶栏:←返回/书名·章节/⋯更多", "底栏:上一章/目录/可拖进度条/书签/Aa/下一章"],
                "acceptance": ["顶底栏控件齐全", "进度条可拖", "Aa 显示设置入口", "书签入口"],
            },
            {
                "id": "S4", "name": "阅读器·长按选词工具条", "device": "mobile",
                "design": {"svg": "docs/wireframes/reader-ui-v2/04-selection.svg", "viewport": "900x640", "label": "设计稿 v2 · 选词工具条"},
                "impl": {"png": "app/test/goldens/reader_selected.png", "viewport": "1170x2532", "label": "golden · 选词工具条"},
                "intent": ["选中文本浮出工具条(划重点/笔记/颜色/翻译/查词)", "两端选柄", "工具条随选中区浮动"],
                "acceptance": ["工具条跟随所选文字", "含翻译/查词", "选柄可见"],
            },
            {
                "id": "S5", "name": "Aa 显示设置面板", "device": "mobile",
                "design": {"svg": "docs/wireframes/reader-ui-v2/03-settings.svg", "viewport": "900x640", "label": "设计稿 v2 · 显示设置"},
                "impl": {"png": "app/test/goldens/aa_panel.png", "viewport": "1170x2532", "label": "golden · 显示设置面板"},
                "intent": ["字号滑块 + 字体 + 主题 + 行距 + 翻页模式切换(分页/滚动)"],
                "acceptance": ["字号可调", "字体/主题可选", "翻页模式切换在此"],
            },
        ],
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="生成产品预览对照报告")
    ap.add_argument("manifest", nargs="?", help="manifest JSON 路径")
    ap.add_argument("-o", "--out", default="workflow/reports/product-preview.html", help="输出 HTML 路径")
    ap.add_argument("-r", "--req", default=None, help="覆盖 REQ 号")
    ap.add_argument("--title", default=None, help="覆盖产品名")
    ap.add_argument("--sample", action="store_true", help="生成演示 manifest 与报告")
    ap.add_argument("--impl-dir", default=None,
                    help="实现截图目录：按每屏 id/name 自动匹配 <id>.png（真实渲染/真机截图）")
    args = ap.parse_args()

    if args.sample:
        cfg = make_sample()
        out = "workflow/reports/product-preview-demo.html"
    else:
        if not args.manifest:
            ap.error("需要 manifest JSON（或 --sample）")
        cfg = json.load(open(args.manifest, "r", encoding="utf-8"))
        out = args.out

    if args.req:
        cfg["req"] = args.req
    if args.title:
        cfg["product"] = args.title

    html_report = build_report(cfg, impl_dir=args.impl_dir)
    out = os.path.abspath(out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write(html_report)
    print("已生成产品预览报告: {} ({} 屏, {} 字节)".format(out, len(cfg.get("screens", [])), len(html_report)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
