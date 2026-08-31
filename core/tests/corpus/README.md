# 黄金语料（corpus）

| 文件 | 内容 | 来源 | sha256 |
|---|---|---|---|
| `src/hongloumeng.epub` | 《紅樓夢》中文 EPUB3（lang: zh，13 spine 项，含目录） | Project Gutenberg #24264（公有领域） | `b053027b975d96c17a3d650c867e7f445e9b22bbccf18078c111f5da269452e1` |
| `src/pride-and-prejudice.epub` | 《傲慢与偏见》英文 EPUB3（61 章，含图片，24MB） | Project Gutenberg #1342（公有领域） | `4c2dadd1a2135fdb9904eaffd8f5115c331569eda5df9fbd859729756bc7def9` |
| `src/pride-and-prejudice.txt` | 同上书的 UTF-8 TXT | Project Gutenberg #1342 | `70603ec2589cfae0e7b6bd0cc5afea039301404cfff993818a2583fffd7a52dd` |
| `src/hongloumeng.mobi` | 《紅樓夢》MOBI7（PalmDOC LZ77，EXTH 元数据：title=紅樓夢/author=Xueqin Cao/language=zh，**34 个 `<mbp:pagebreak/>` 分章点**，2 张 JPEG，INDX 记录 ×2；UTF-8） | Project Gutenberg #24264 `pg24264.mobi`（公有领域；实测 MOBI7：MOBI 头 type=2，无 KF8 标记） | `2e8d3c4491715c03653e14b2d01e6688207e6edd496de83a0405c8c2cac36e7e` |
| `src/hongloumeng-images.mobi` | 《紅樓夢》MOBI7 插图版（PalmDOC，无 pagebreak、无标题层级 → 单章兜底路径；INDX 记录 ×6（KindleGen "IDXT" 变体）；2 张 JPEG（封面等）） | Project Gutenberg #24264 `pg24264-images-kf8.mobi`（公有领域；URL 名为 "kf8" 但**实测为 MOBI7**：type=2、PalmDoc、无 RESC/BOUNDARY） | `557ae48f9dc9caa1cc41fef30a9d76508ce471aef514c6121dfc5fd4f2ffa925` |
| `src/pride-and-prejudice.mobi` | 《傲慢与偏见》MOBI7 插图版（PalmDOC，**66 个 h2 标题**（标题层级拆章路径），**165 张 JPEG**（`kindle:embed:` 十六进制引用）；正文含 "It is a truth universally acknowledged"） | Project Gutenberg #1342 `pg1342-images-kf8.mobi`（公有领域；同上，URL 名为 "kf8" 但**实测为 MOBI7**） | `de1cc41cb8f8cba12caf3e4cccc7e1c1cc4e1169e9cddb818daa51ac85c74ff5` |
| `src/bad-mobi-truncated.mobi` | 构造坏文件：`hongloumeng.mobi` 截断至 5966 字节（PDB 头+记录表完整、内容流被切断，多数记录偏移越界） | 构造（python 从真实语料派生，见下） | `4c5b8f3237b2e0abba220454443f481fed8043dab2bc536e7150a1172d57cec0` |
| `src/bad-mobi-garbage.mobi` | 构造坏文件：`BOOKMOBI` 魔数 + 2048 字节随机垃圾 | 构造（python `os.urandom`） | `7699499088eeacab758a17ace4e0d7c9efa86e16002daf4bd4da4a6a1d7d60dd` |
| `src/bad-mobi-drm.mobi` | 构造坏文件：`hongloumeng.mobi` 的 PalmDOC `encryption` 字段（record 0 +12）置 2（MobiPocket）→ DRM/加密标记 | 构造（python 从真实语料派生） | `d34192a863e960dc3ef95fbacb115185e5fe8270dc0f50e122cd304fc307a9f5` |

坏文件构造命令（可复现）：
```bash
# 截断：PDB 头(78) + 记录表(8*661) + 600 字节记录 0 内容
head -c $((78 + 8*661 + 600)) hongloumeng.mobi > bad-mobi-truncated.mobi
# 垃圾
python3 -c "import os,sys; sys.stdout.buffer.write(b'BOOKMOBI'+os.urandom(2048))" > bad-mobi-garbage.mobi
# DRM 标记（PalmDOC encryption 字段置 2）——见 python 脚本，patch bytes[rec0+12:rec0+14] = 0x0002
```

规则（docs/05 §3）：
- 只收**无版权争议**文件（Gutenberg 公有领域 / 构造样例）；单文件 < 30MB；来源与许可记录于上表。
- 语料不打包进发布产物；变更需评审（影响快照与基准）。

**已知缺口（登记）**：真实 KF8/AZW3 语料（both 与 KF8-only）需 calibre 生成
（`ebook-convert x.epub out.azw3 --mobi-file-type=both|new`）；本环境无 calibre，且
Gutenberg "kf8" 下载实测均为 MOBI7 → 真实 AZW3 语料**留待开发机生成后补录**（来源/生成命令记录于此表）。
AZW3 路径当前由「.mobi 语料复制为 .azw3 扩展名的分发测试 + 合成 KF8 rawml 单测 + detect_format 构造头单测」覆盖。

P1 待补充：FB2 / CBZ / KF8-only AZW3 / GBK 中文 MOBI（真实来源）。
