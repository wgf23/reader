#!/usr/bin/env python3
"""llvm-cov JSON → 覆盖率口径汇总（REQ-002 阶段4 测试用）。

口径：
  1. 总体行覆盖（全部文件）
  2. 排除生成代码（frb_generated）
  3. 排除生成代码 + api.rs（桥接胶水层，由 FFI 端到端覆盖，REQ-001 先例豁免）
  4. 逐文件行覆盖（关注 mobi/azw3 新增文件）
用法: python3 scripts/cov-summary.py workflow/reports/coverage.json
"""
import json
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "workflow/reports/coverage.json"
with open(path) as f:
    data = json.load(f)

files = data["data"][0]["files"]

def lines_of(f):
    s = f.get("summary", {}).get("lines", {})
    return s.get("count", 0), s.get("covered", 0)

def fmt(count, covered):
    pct = (covered / count * 100.0) if count else 100.0
    return f"{covered}/{count} ({pct:.1f}%)"

total_c = sum(lines_of(f)[0] for f in files)
total_k = sum(lines_of(f)[1] for f in files)
print("== 总体 ==")
print("全部文件:", fmt(total_c, total_k))

def subset(files, exclude=()):
    fs = [f for f in files if not any(f["filename"].endswith(e) for e in exclude)]
    c = sum(lines_of(f)[0] for f in fs)
    k = sum(lines_of(f)[1] for f in fs)
    return c, k

c, k = subset(files, ("frb_generated.rs",))
print("排除生成代码(frb_generated):", fmt(c, k))
c, k = subset(files, ("frb_generated.rs", "api.rs"))
print("排除生成代码+api.rs:", fmt(c, k))

print("\n== 逐文件（行覆盖）==")
for f in sorted(files, key=lambda f: f["filename"]):
    c0, k0 = lines_of(f)
    print(f"{f['filename']}: {fmt(c0, k0)}")

print("\n== REQ-002 新增/相关文件（新代码口径）==")
for name in ("mobi_common.rs", "mobi.rs", "azw3.rs", "format/mod.rs", "error.rs"):
    for f in files:
        if f["filename"].endswith(name):
            c0, k0 = lines_of(f)
            print(f"{f['filename']}: {fmt(c0, k0)}")
            break
