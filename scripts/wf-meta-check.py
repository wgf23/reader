#!/usr/bin/env python3
"""wf-meta 产物头校验（docs/07 §3）：workflow/backlog/REQ-*/ 下阶段产物必须带合法 wf-meta 头。

用法：python3 scripts/wf-meta-check.py <workflow-dir> [--strict]
--strict：所有产物都必须存在且合法（闸门用）；默认只校验已存在的文件。
退出码：存在非法/缺失（strict）→ 1。
"""
import re
import sys
from pathlib import Path

HEADER = re.compile(
    r"<!--\s*wf-meta:\s*req=(\S+)\s*\|\s*phase=(\S+)\s*\|\s*agent=(\S+)\s*\|\s*date=(\d{4}-\d{2}-\d{2})\s*\|\s*gate=(passed|failed)\s*-->"
)
PHASES = {
    "requirements": "01-req.md",
    "architecture": ["02-adr.md", "02-design.md", "02-plan.md"],
    "development": ["03-review.md"],
    "testing": ["04-mutation.md", "04-coverage.md"],
    "delivery": "05-delivery.md",
}


def norm(files):
    return files if isinstance(files, list) else [files]


def main() -> int:
    args = sys.argv[1:]
    wf = Path(args[0]) if args else Path("workflow")
    strict = "--strict" in args
    errors = []

    for req_dir in sorted((wf / "backlog").glob("REQ-*")):
        req = req_dir.name
        for phase, files in PHASES.items():
            for f in norm(files):
                p = req_dir / f
                if not p.exists():
                    if strict:
                        errors.append(f"[缺失] {req}/{f}（{phase} 阶段产物）")
                    continue
                text = p.read_text(encoding="utf-8", errors="ignore")
                m = HEADER.match(text)
                if not m:
                    errors.append(f"[非法头] {req}/{f}")
                    continue
                if m.group(1) != req or m.group(2) != phase:
                    errors.append(
                        f"[头不一致] {req}/{f}: meta(req={m.group(1)}, phase={m.group(2)})"
                    )

    if errors:
        for e in errors:
            print(f"wf-meta ✗ {e}")
        return 1
    print(f"wf-meta ✓ 全部产物头合法（strict={strict}）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
