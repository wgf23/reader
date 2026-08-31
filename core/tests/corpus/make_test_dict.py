#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""REQ-003 T-001：自造受控 StarDict 词库生成器（CI 主语料，无版权争议）。

产出（相对本脚本目录 src/dicts/）：
  test-tgm/    sametypesequence='tgm'（t=音标 g=HTML 释义 m=纯文本释义）—— US-1 主断言语料
  test-tgmx/   sametypesequence='tgmx'（追加 x=例句），含 .dict.dz gzip 变体 —— .dz 路径语料
  test-tgz/    sametypesequence='tgz'（z 为未知类型码）—— "未知类型码不崩溃" 语料
  bad-idx-truncated/   坏词库：.idx 尾部截断（切在条目中间）
  bad-offset-oob/      坏词库：.idx 某条目 size 越出 .dict 长度
  bad-ifo-nocount/     坏词库：.ifo 缺 wordcount 行
  bad-dz-truncated/    坏词库：.dict.dz gzip 流截断

可复现：两次运行产物字节一致（条目固定顺序、内容固定、gzip mtime=0、无时间戳写入）。
运行：python3 core/tests/corpus/make_test_dict.py（在 reader/ 根目录执行）。
"""
import gzip
import hashlib
import os
import struct
import sys

OUT_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src", "dicts")

# (word, phonetic, html_def, plain_def, example) —— example=None 表示无例句
# pos 词性标记启发式取自 plain_def 行首（"n."/"v."/"adj."…）；zebra 无标记 → pos=None 断言
ENTRIES = [
    ("apple", "/ˈæp.əl/", "<b>n.</b> A round fruit.", "n. 苹果；苹果树", None),
    ("Apple", "", "<b>n.</b> The company.", "n. 苹果公司", None),
    ("bad", "/bæd/", "<b>adj.</b> Poor.", "adj. 坏的", None),
    ("big", "/bɪɡ/", "<b>adj.</b> Large.", "adj. 大的", None),
    ("book", "/bʊk/", "<b>n.</b> A written work.", "n. 书；书籍", "an interesting book"),
    ("earth", "/ɜːθ/", "<b>n.</b> The planet.", "n. 地球；泥土", None),
    ("fast", "/fɑːst/", "<b>adj.</b> Quick.", "adj. 快的", None),
    ("fire", "/ˈfaɪə/", "<b>n.</b> Flame.", "n. 火", None),
    ("good", "/ɡʊd/", "<b>adj.</b> Of high quality.", "adj. 好的", "a good day"),
    ("happy", "/ˈhæpi/", "<b>adj.</b> Joyful.", "adj. 快乐的", "a happy child"),
    ("hello", "/həˈləʊ/", "<b>int.</b> A greeting.", "int. 你好；喂", "Hello, world!"),
    ("learn", "/lɜːn/", "<b>v.</b> To gain knowledge.", "v. 学习", "learn English"),
    ("love", "/lʌv/", "<b>n.</b> Deep affection.", "n. 爱；热爱", None),
    ("moon", "/muːn/", "<b>n.</b> Earth's satellite.", "n. 月亮", None),
    ("read", "/riːd/", "<b>v.</b> To look at text.", "v. 阅读", "read a book"),
    ("run", "/rʌn/", "<b>v.</b> To move fast.", "v. 跑；奔跑", "run fast"),
    ("sky", "/skaɪ/", "<b>n.</b> The heavens.", "n. 天空", None),
    ("small", "/smɔːl/", "<b>adj.</b> Little.", "adj. 小的", None),
    ("star", "/stɑː/", "<b>n.</b> A luminous body.", "n. 星星", None),
    ("sun", "/sʌn/", "<b>n.</b> The star.", "n. 太阳", None),
    ("time", "/taɪm/", "<b>n.</b> Duration.", "n. 时间", None),
    ("translate", "/trænzˈleɪt/", "<b>v.</b> To render in another language.", "v. 翻译", None),
    ("water", "/ˈwɔːtə/", "<b>n.</b> A liquid.", "n. 水", None),
    ("wind", "/wɪnd/", "<b>n.</b> Moving air.", "n. 风", None),
    ("world", "/wɜːld/", "<b>n.</b> The earth.", "n. 世界", "the whole world"),
    ("zebra", "/ˈzebrə/", "<b>Zebra</b>", "一种非洲哺乳动物", None),
]

# 条目按 word 字节序排序（StarDict .idx 要求）
ENTRIES = sorted(ENTRIES, key=lambda e: e[0].encode("utf-8"))

# 条目字段 → 在 (word, ph, g, m, x) 元组中的下标
F_T, F_G, F_M, F_X = 1, 2, 3, 4


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def write_ifo(path, bookname, wordcount, idxfilesize, seq):
    lines = [
        "StarDict's dict ifo file",
        "version=2.4.2",
        f"bookname={bookname}",
        f"wordcount={wordcount}",
        f"idxfilesize={idxfilesize}",
        f"sametypesequence={seq}",
        "author=reader-dev",
        "description=REQ-003 自造受控语料（无版权争议）",
        "date=2026.08.31",
        "",
    ]
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def entry_field(entry, code):
    """按类型码取字段文本；未知码给固定文本（解析器应跳过不崩溃）。"""
    if code == "t":
        return entry[F_T]
    if code == "g":
        return entry[F_G]
    if code == "m":
        return entry[F_M]
    if code == "x":
        return entry[F_X] if entry[F_X] is not None else ""
    return "arbitrary unknown field data"


def build_dict_data(entries, seq):
    """返回 (bytes, [(offset, size), ...])：按 sametypesequence 拼接；
    非末字段 NUL 终止，末字段止于条目边界（解析器同时容忍末字段带 NUL）。"""
    offsets = []
    body = bytearray()
    for e in entries:
        parts = [entry_field(e, c).encode("utf-8") for c in seq]
        off = len(body)
        for i, p in enumerate(parts):
            body += p
            if i < len(parts) - 1:
                body += b"\x00"
        offsets.append((off, len(body) - off))
    return bytes(body), offsets


def write_dict_with_idx(base, entries, seq):
    """一次写齐 .idx 与 .dict（offset/size 一一回填）。"""
    dict_bytes, offsets = build_dict_data(entries, seq)
    with open(base + ".idx", "wb") as f:
        for (word, _ph, _g, _m, _x), (off, size) in zip(entries, offsets):
            f.write(word.encode("utf-8"))
            f.write(b"\x00")
            f.write(struct.pack(">II", off, size))
    with open(base + ".dict", "wb") as f:
        f.write(dict_bytes)
    return len(dict_bytes)


def write_dz(src_dict, dst_dz):
    data = open(src_dict, "rb").read()
    with open(dst_dz, "wb") as out:
        out.write(gzip.compress(data, mtime=0))  # mtime=0 → 可复现


def make_dict(name, seq, with_dz=False, bookname=None):
    d = os.path.join(OUT_ROOT, name)
    os.makedirs(d, exist_ok=True)
    base = os.path.join(d, name)
    write_dict_with_idx(base, ENTRIES, seq)
    idx_size = os.path.getsize(base + ".idx")
    write_ifo(base + ".ifo", bookname or name.replace("-", " ").title(),
              len(ENTRIES), idx_size, seq)
    if with_dz:
        write_dz(base + ".dict", base + ".dict.dz")


def copy_file(src, dst):
    with open(src, "rb") as f, open(dst, "wb") as g:
        g.write(f.read())


def make_bad_dicts():
    # 坏词库从 test-tgmx 派生（需先建）
    src = os.path.join(OUT_ROOT, "test-tgmx", "test-tgmx")
    # 1) .idx 截断（切在最后一条目中间）
    d = os.path.join(OUT_ROOT, "bad-idx-truncated")
    os.makedirs(d, exist_ok=True)
    copy_file(src + ".ifo", d + "/bad-idx-truncated.ifo")
    copy_file(src + ".dict", d + "/bad-idx-truncated.dict")
    idx = open(src + ".idx", "rb").read()
    with open(d + "/bad-idx-truncated.idx", "wb") as f:
        f.write(idx[:-12])  # 尾部切断 12 字节（条目中间）
    # 2) 偏移越界：patch 第一条目 size 指向 .dict 之外
    d = os.path.join(OUT_ROOT, "bad-offset-oob")
    os.makedirs(d, exist_ok=True)
    for ext in (".ifo", ".idx", ".dict"):
        copy_file(src + ext, d + "/bad-offset-oob" + ext)
    idx_path = d + "/bad-offset-oob.idx"
    with open(idx_path, "r+b") as f:
        buf = bytearray(f.read())
        first_nul = buf.index(b"\x00")
        struct.pack_into(">I", buf, first_nul + 1 + 4, 0x7FFFFFFF)  # size 置超大
        f.seek(0)
        f.write(bytes(buf))
    # 3) .ifo 缺 wordcount
    d = os.path.join(OUT_ROOT, "bad-ifo-nocount")
    os.makedirs(d, exist_ok=True)
    for ext in (".idx", ".dict"):
        copy_file(src + ext, d + "/bad-ifo-nocount" + ext)
    ifo = open(src + ".ifo", encoding="utf-8").read()
    lines = [ln for ln in ifo.splitlines() if not ln.startswith("wordcount=")]
    with open(d + "/bad-ifo-nocount.ifo", "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    # 4) .dict.dz gzip 流截断
    d = os.path.join(OUT_ROOT, "bad-dz-truncated")
    os.makedirs(d, exist_ok=True)
    for ext in (".ifo", ".idx"):
        copy_file(src + ext, d + "/bad-dz-truncated" + ext)
    dz = gzip.compress(open(src + ".dict", "rb").read(), mtime=0)
    with open(d + "/bad-dz-truncated.dict.dz", "wb") as f:
        f.write(dz[: len(dz) // 2])  # 截断 gzip 流


def main():
    os.makedirs(OUT_ROOT, exist_ok=True)
    make_dict("test-tgm", "tgm", bookname="Test TGM Dictionary")
    make_dict("test-tgmx", "tgmx", with_dz=True, bookname="Test TGMX Dictionary")
    make_dict("test-tgz", "tgz", bookname="Test TGZ Dictionary")
    make_bad_dicts()
    print("dicts 生成于:", OUT_ROOT)
    for root, _dirs, files in sorted(os.walk(OUT_ROOT)):
        for fn in sorted(files):
            p = os.path.join(root, fn)
            print(f"{os.path.relpath(p, OUT_ROOT):52s} {os.path.getsize(p):8d}  {sha256(p)}")


if __name__ == "__main__":
    sys.exit(main())
