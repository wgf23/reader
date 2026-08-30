# 跨平台电子书阅读器 —— 技术设计文档

> 版本：v1.0 ｜ 状态：设计稿（**已由同目录 [00-README.md](00-README.md) 正式设计文档集取代**，本文保留作早期草案与选型讨论记录）
> 一句话定位：**PC 优先、后续覆盖 Android/iOS 与 Kindle 的离线优先阅读器**，核心卖点是**笔记**与**翻译**，约束是**好性能 + 小体积**。

---

## 0. 需求澄清与术语

- 你说的 "aws" 我理解为 **azw（Amazon Kindle 格式族，主要指 azw3 / KF8）**。本设计按此处理，文中的 "MOBI/AZW3" 均指 Kindle 体系格式。
- "Kindle 也可以用" 是**远期目标**，本设计给出了务实的分阶段路径（见 §6），不承诺在 Kindle 上跑我们的 App（Kindle 是封闭 Linux 系统，代价极大），而是先通过"导出/推送"让用户手里的 Kindle 直接用起来。
- 明确边界：**不支持 DRM 加密书的破解**（合规风险），只处理无 DRM 书籍；用户自己的去 DRM 副本不受影响。

---

## 1. 目标与约束

| 约束 | 具体要求 |
|---|---|
| 平台 | 首期 Windows / macOS / Linux 桌面；二期 Android / iOS；远期 Kindle |
| 格式 | EPUB、PDF、MOBI、AZW3 必做；TXT、FB2、CBZ 低成本顺带；KFX 不做 |
| 性能 | 10MB EPUB 打开 < 500ms（桌面）/ < 1.5s（移动）；翻页 60fps；全文搜索 < 100ms |
| 体积 | 桌面安装包 < 40MB，移动端每 ABI < 25MB，不内置浏览器引擎 |
| 功能优先级 | **笔记（高亮/批注）＞ 翻译/词典 ＞ 图书库/搜索 ＞ 同步** |
| 其他 | 离线优先（无网可读、可查离线词典）、尊重版权 |

---

## 2. 格式支持策略（最核心的决策）

### 2.1 两条渲染管线，不做"一格式一引擎"

```
                ┌──────────────────────────────────────────┐
                │            规范化 (canonicalize)          │
                └──────────────────────────────────────────┘
                     │                              │
        reflow 管线（文字流式排版）        page 管线（固定页面）
   EPUB(原生) / MOBI / AZW3 / TXT /   PDF / CBZ / CBR / (DJVU)
   FB2 ──转换──▶ 内部规范 EPUB ──▶
                     │                 ──▶ PDFium/MuPDF 页面渲染
            HTML/CSS 排版引擎 + 分页     （缩放、裁剪、文本层选择）
```

- **Reflow 管线**：MOBI/AZW3/TXT/FB2 全部**转换成内部规范 EPUB**（内存或缓存目录），统一走 HTML/CSS 排版。理由：EPUB 的排版工具链最成熟（CSS 分页、字体、连字），一本书的排版质量由 CSS 决定；我们不需要为每个格式各写一个排版引擎。
- **Page 管线**：PDF 是固定页面格式、无法重排，独立走 PDF 引擎；CBZ/CBR 本质是图片序列，按页渲染即可。

### 2.2 MOBI / AZW3 的转换原理（技术上完全可行）

MOBI/AZW3 本质是 **PDB 容器 + PalmDOC/HUFF-CDIC 压缩 + EXTH 元数据 + 一个(或拆分的)HTML 内容**：

1. 解 PDB 记录表，按 PalmDOC LZ77 或 HUFF/CDIC 解压出内容流；
2. 从 EXTH 头取元数据（书名、作者、ASIN、封面偏移）；
3. 内容是一个大 HTML，按 `<mbp:pagebreak>` / 标题层级 / INDX 索引拆分成章节；
4. 抽出内嵌图片（RECORD 0 与 image 记录），重排资源路径；
5. 输出为规范 EPUB（OPF + spine + NCX/EPUB3 nav）。

> 这就是 [kindleunpack](https://github.com/kevinhendricks/KindleUnpack) 的算法，Rust 生态已有可用实现：
> - [`mobi` crate](https://docs.rs/mobi)（解析 MOBI/AZW3，提取元数据与内容流）
> - [`mobi-rs`](https://github.com/vv9k/mobi-rs)、`palmdoc`、`kindling-mobi`（压缩/结构层）
> - 拆章与重组由我们自己写（约几百行，可参考 kindleunpack 逻辑）
>
> AZW3/KF8 是 PDB 里嵌了一套 EPUB 结构 + 旧版 MOBI 回退段，解出来更规整。

### 2.3 明确不做的

- **KFX**：亚马逊专有、未文档化、只为 Kindle 设备优化。我们的 Kindle 策略（§6）让设备端/服务器去转，不需要自己生成。
- **DRM 破解**：见 §0。
- 目标格式本身（MOBI/AZW3/EPUB/PDF 的无 DRM 版本）全覆盖。

---

## 3. 总体架构：Flutter 壳 + Rust 核 + WebView 排版

```
┌─────────────────────────────────────────────────────────┐
│ UI 层（Flutter，一套代码：Win/macOS/Linux/Android/iOS）    │
│   书架 / 阅读器外壳 / 笔记面板 / 词典浮层 / 设置 / 导入      │
├─────────────────────────────────────────────────────────┤
│ 渲染层                                                    │
│   • Reflow：系统 WebView + 分页脚本（Readium navigator 模式）│
│   • PDF/CBZ：PDFium(或 MuPDF) 页面光栅化 + 文本层           │
├─────────────────────────────────────────────────────────┤
│ 核心服务层（Rust，flutter_rust_bridge 桥接）                │
│   解析器(EPUB/MOBI/AZW3/TXT/FB2) ｜ 转换器→规范EPUB         │
│   定位器 Locator ｜ 笔记存储 ｜ 词典/翻译 Provider ｜ 搜索     │
├─────────────────────────────────────────────────────────┤
│ 存储层：SQLite（书籍元数据、笔记、进度、翻译缓存、FTS5 索引）   │
└─────────────────────────────────────────────────────────┘
```

### 为什么是 Flutter + Rust（对照）

| 维度 | Flutter + Rust（推荐） | Kotlin/Compose + Readium | Tauri 2 + Readium-js | Electron |
|---|---|---|---|---|
| 桌面三平台 | 成熟稳定 | 桌面 JVM 可用但导航器弱 | 小（5–10MB） | 大（100MB+，违背体积目标） |
| Android/iOS | 同一套代码 | 逻辑共享，UI 两套（Compose/iOS 仍需 alpha） | 支持但生态年轻、文件访问受限 | 移动端体积灾难 |
| 渲染 EPUB | WebView 分页（与 Readium 同模式） | 需 readium-kotlin(Android) + readium-swift(iOS) 两套导航器 | 天然 webview，最顺 | 顺但重 |
| 解析性能 | Rust 原生，最快 | JVM，够用 | JS 解析较慢，MOBI 需插件 | JS 慢 |
| 体积 | 桌面 20–40MB，移动 <25MB/ABI | 中等（JVM 运行时大） | 最小 | 最大 |
| 生态参考 | **Readest**（同架构先例） | Readium 官方 | Thorium 思路 | Thorium |

**结论**：Flutter 一套 UI 覆盖全部 6 个目标平台，Rust 核负责性能敏感部分（解析/转换/检索）且未来可被 Kindle 移植复用（KOReader 就是 Rust 同源思路的 MuPDF + Lua 壳），系统 WebView 保证排版质量且不增加安装体积。

**先例佐证**：开源阅读器 [Readest](https://github.com/readest/readest) 就是 Flutter + Rust 架构，支持 epub/mobi/azw3/pdf/txt/fb2/cbz，带笔记与翻译，跨 Win/macOS/Linux/Android/iOS —— 与我们的目标几乎重合，可作直接参照与代码借鉴对象（注意其开源许可）。

---

## 4. 技术选型明细

| 组件 | 选择 | 理由 / 备选 |
|---|---|---|
| UI 框架 | Flutter | 一套代码六平台；Skia/Impeller 渲染快；无 JS 运行时开销 |
| 核心语言 | Rust | 解析/转换/检索性能；静态链接体积小；`cargo` 生态有 mobi/epub 库 |
| 桥接 | flutter_rust_bridge | 成熟代码生成，类型安全 |
| Reflow 排版 | 系统 WebView（Win: WebView2 / macOS: WKWebView / Linux: WebKitGTK / Android/iOS: 系统 WebView）+ 分页 JS | 排版质量由 CSS 保证；不内置浏览器省 100MB+；分页采用 CSS columns + JS 计算页断点（Readium 模式） |
| PDF | PDFium（`pdfium-render` 绑定）或 MuPDF | PDFium 与 Chrome 同源、稳；MuPDF 可顺带支持 DJVU/XPS，与未来 Kindle 移植同栈 |
| 存储 | SQLite（Rust: rusqlite；Flutter 侧只走桥接） | WAL 模式，笔记与搜索都靠它；FTS5 全文搜索 |
| 词典 | StarDict 离线词库解析（idx/dict/ifo + dz 压缩） | KOReader 同款词库生态，免费词库量大，离线可用 |
| 在线翻译 | Provider 接口 + DeepL/Google/有道/OpenAI 适配器（可选启用） | 见 §5.5 |
| 同步（后期） | WebDAV（自托管友好）或自建轻后端 | 先本地，后同步 |

### 体积预算（发布构建，粗略，以实测为准）

- 桌面安装包：Flutter release ≈ 20–30MB + Rust 核 ≈ 3–5MB → **< 40MB**
- Android：按 ABI 拆分 APK ≈ 15–25MB；iOS ≈ 25MB 上下
- 对比：Electron 阅读器普遍 100MB+，我们小一个数量级

### 性能预算

- 打开 10MB EPUB：桌面 < 500ms（Rust 解压+XML 解析+索引，分页懒加载）；移动 < 1.5s
- 解析 5MB MOBI：< 200ms（Rust 原生）
- 翻页：只排版当前资源 + 相邻页，60fps
- 全文搜索：FTS5 索引，< 100ms

---

## 5. 核心模块设计

### 5.1 解析与规范化（Rust core）

- 输入 → 输出统一为**规范 EPUB**（我们自己定义的"最小 EPUB 子集"：OPF + spine + 章节 XHTML + 资源 + EPUB3 nav），转换结果缓存到 `cache/`（按源文件 hash 命名），二次打开秒开。
- 统一元数据结构：`BookMeta { id, title, authors, cover, language, toc[], spine[], created_at }`。
- TXT：编码探测（UTF-8/GBK/Big5）+ 自动按空行/章节号切章，包成规范 EPUB。
- FB2：XML → 规范 EPUB（XSLT 思路，Rust 直接遍历）。
- 健壮性：解析失败不崩溃 → 返回结构化错误并降级（如"此文件可能受 DRM 保护"）。

### 5.2 渲染与翻页

- **Reflow**：每个资源（章节）加载进 WebView，用 CSS `columns` 分页（Readium navigator 同款思路）：JS 测量列数/页断点，滚动或切页只滑动视口；支持单页/双页、字号、行距、主题（浅色/深色/护眼）、对齐、连字、字体族。进度 = 章节内位置 → 全书 progression（0–1）。
- **PDF**：按需渲染可见页为位图（缩放/裁剪/夜间反色），保留文本层用于选择与搜索；目录从 PDF outline 提取。
- 滚动模式 vs 分页模式都提供（读者习惯差异）。

### 5.3 定位器 Locator（笔记/进度/同步的统一基石）

统一锚定模型（借鉴 Readium Locator）：

```jsonc
{
  "href": "chapter3.xhtml",          // 资源路径
  "progression": 0.42,               // 章内进度 0..1
  "totalProgression": 0.61,          // 全书进度 0..1（跨设备同步用）
  "text": { "snippet": "起风了，唯有努力生存", "start": 123, "end": 145 },
  "cfi": "epubcfi(...)"              // EPUB CFI，可选冗余锚
}
```

- **文本片段锚（snippet + 字符偏移）最稳**：重排/换字号/换主题都不失效（按片段模糊匹配重新定位）；CFI 作精确冗余。
- PDF 用 `{ page, rect, text_snippet }`；进度用 `{ page, totalPageProgress }`。
- 所有笔记、书签、阅读进度、翻译缓存都挂在这个模型上 → 同步天然统一。

### 5.4 笔记系统（第一优先级功能）

- 类型：**高亮（多色）/ 下划线 / 批注 / 书签 / 阅读进度**。
- 交互：选中文本 → 浮动工具条（复制/高亮/批注/**翻译**）；批注面板按章节分组、点击跳回原文；支持笔记内标签。
- 存储（SQLite）：

```sql
CREATE TABLE annotations (
  id          TEXT PRIMARY KEY,          -- uuid
  book_id     TEXT NOT NULL,
  locator     TEXT NOT NULL,             -- §5.3 JSON
  type        TEXT NOT NULL,             -- highlight|underline|note|bookmark
  color       TEXT,
  snippet     TEXT,                      -- 冗余存一段原文，列表展示/导出用
  note_text   TEXT,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  sync_status TEXT DEFAULT 'dirty'       -- dirty|synced|conflict
);
CREATE INDEX idx_ann_book ON annotations(book_id);
```

- 导出：**Markdown / JSON / Kindle 的 My Clippings.txt 格式**（后两者直接喂给 Kindle 或 Readwise）。
- 阅读进度单独存 `reading_progress(book_id, locator, updated_at)`。

### 5.5 翻译与词典（第一优先级功能）

- **Provider 接口**（Rust trait，桥接到 UI）：

```rust
trait TranslationProvider {
    fn lookup(&self, word: &str) -> Option<DictEntry>;          // 词典：离线
    async fn translate(&self, text: &str, from: Lang, to: Lang)
        -> Result<Translation>;                                  // 在线
}
```

- **离线词典**：StarDict（.ifo/.idx/.dict(.dz)），KOReader 生态词库直接可用；长按单词弹出释义浮层（带音标/词性/例句），无网可用 —— 这是"离线优先"的兑现。
- **在线翻译**：整句/整段翻译，DeepL / Google / 有道 / OpenAI 任选，接口统一；**结果按 (原文, 语言对, provider) 缓存进 SQLite**，命中不联网、不计费。
- **生词本**：翻译动作可一键"加入生词本"（又是笔记体系的延伸）。
- 交互：选中文本 → 工具栏"翻译"；长按单词 → 词典浮层；可在侧栏看全文翻译对照。

### 5.6 图书库

- 导入：拖拽 / 文件夹扫描 / 文件选择器；自动识别格式并规范化入库（后台任务，不阻塞 UI）。
- 书架：封面墙 + 元数据 + 进度百分比；排序/筛选/标签。
- 全文搜索：入库时建 FTS5 索引（正文文本提取），跨书搜索。
- 增量更新：文件夹监控（桌面端）。

### 5.7 同步（二期）

- 目标：笔记/进度/书库跨设备一致；书籍文件本身不同步（体积大，用户自己管理）。
- 后端：**WebDAV**（坚果云/自建，隐私友好）或自建轻 API；同步对象 = annotations + progress + 书库元数据。
- 状态机：`dirty → synced`，冲突用 LWW（updated_at）+ 冲突标记人工合并；同步是后台任务，断网静默重试。

---

## 6. Kindle 策略（务实三阶段）

Kindle 是封闭 Linux + e-ink，**跑不了 Flutter/iOS 应用**，任何"Kindle 原生 App"都是另一个项目。分阶段：

| 阶段 | 做法 | 成本 | 效果 |
|---|---|---|---|
| **近期（随 PC 版交付）** | **Send to Kindle**：应用内一键把书（EPUB/MOBI/PDF）推送到用户 Kindle——邮箱推送 / 官方 Send to Kindle 应用 / 社区 API 客户端（如 [stkclient](https://github.com/maxdjohnson/stkclient)、Rust 的 `send-to-kindle` crate）；或本地转 AZW3/KFX 后 USB 拷贝（Rust 有 [`boko`](https://github.com/zacharydenton/boko)：EPUB→KFX/AZW3/MOBI 转换器） | 低，一周内 | 用户 Kindle **立即能用**，服务器端自动转换，我们甚至不用碰 KFX |
| **中期** | **笔记回流**：我们的笔记导出为 Kindle 可读/可同步的格式（Clippings、推送带标注）；阅读进度双向对齐（靠 Kindle 原生同步） | 低 | 桌面笔记 ⇄ Kindle 阅读形成闭环 |
| **远期（评估项）** | **KOReader 式移植**：Kindle 上跑第三方阅读器（KUAL + framebuffer/SDL）。我们 Rust 核 + MuPDF 与 KOReader 架构同源，未来核心逻辑可复用；但需要 e-ink 图形栈、物理翻页键适配，是独立项目 | 高，建议在核心成熟后单独立项评估 | 极致体验，但别一开始就押注 |

**推荐**：首期做"推送 + Clippings 导出"，让 Kindle 用户零门槛受益；KOReader 式移植留到路线图末端再评估。

---

## 7. 仓库结构（建议）

```
reader/
├── app/            # Flutter UI（全部平台的壳与页面）
├── core/           # Rust core crate（解析/转换/定位器/笔记/词典/搜索）
│   ├── src/
│   │   ├── format/     # epub / mobi / azw3 / txt / fb2 解析器
│   │   ├── convert/    # → 规范 EPUB
│   │   ├── locator/    # §5.3 锚定模型与重定位
│   │   ├── notes/      # 笔记 + SQLite
│   │   ├── dict/       # StarDict + 在线 Provider 接口
│   │   └── search/     # FTS5
│   └── tests/          # 格式解析黄金样例测试（拿真实公版书做回归）
├── bridge/         # flutter_rust_bridge 生成代码
├── assets/         # 图标、默认字体、内置词典示例
└── docs/           # 设计文档与格式调研
```

---

## 8. 路线图

| 阶段 | 周期 | 交付物 | 验收标准 |
|---|---|---|---|
| **P0 骨架** | 2–3 周 | Flutter 壳 + Rust 核桥接打通；EPUB 解析与 WebView 分页渲染；TXT 支持；翻页/字号/主题/目录 | 10MB EPUB 打开 <500ms，翻页流畅 |
| **P1 核心体验** | 4–6 周 | PDF 管线；MOBI/AZW3 转换；**笔记全功能**；**离线词典 + 在线翻译（先 DeepL/有道）**；书库/搜索 | 三种格式都能读；笔记增删改查、跳转；选句翻译 <1s |
| **P2 打磨与同步** | 4 周 | WebDAV 同步；导出（Markdown/JSON/Clippings）；FB2/CBZ；FTS 搜索；生词本 | 断网全功能可用；同步冲突不丢笔记 |
| **P3 移动端** | 6–8 周 | Android/iOS 发布（手势、触控优化、文件 App 导入）；**Send to Kindle** 推送 | 双端应用商店可下载，体验对齐桌面 |
| **P4 远期** | 持续 | e-ink 适配评估；KOReader 式 Kindle 移植评估；TTS；排版精调（两端对齐/连字/注音）；自建同步后端 | 按评估结果立项 |

---

## 9. 风险与备选

| 风险 | 影响 | 缓解/备选 |
|---|---|---|
| WebView 分页在 Linux（WebKitGTK）等平台表现不一 | 桌面 Linux 体验参差 | 用 Readium 分页模式 + 按平台降级（Linux 可退回滚动模式）；**远期备选**：自研轻量排版引擎（Flutter Text 直接重排，KOReader/FBReader 路线），彻底摆脱 WebView —— 这是"性能优先"路线的终极形态 |
| MOBI 变体多、老书脏数据多 | 个别书转换失败 | 解析失败降级（按原始 HTML 直读）；用真实公版书建黄金测试集回归 |
| KFX / DRM | 部分用户书籍读不了 | 明确不承诺；走 Send to Kindle 让官方服务转换 |
| 在线翻译有网络/费用 | 翻译不可用 | 离线 StarDict 兜底 + 结果缓存；翻译列为可选配置 |
| Rust + Flutter 学习曲线 | 团队上手慢 | P0 只做最小闭环，Rust 核先用 `mobi`/`epub` 现成库，避免从零造轮子 |
| 体积超标 | 违背约束 | 不内置浏览器、按 ABI 拆分、压缩资源、必要时 Rust 核裁剪 feature |

---

## 10. 参考项目与资料

- [Readest](https://github.com/readest/readest) —— Flutter + Rust，格式集与功能几乎同款，最强先例（注意开源许可再借鉴代码）
- [Readium Toolkit](https://readium.org)（[kotlin-toolkit](https://readium.org/kotlin-toolkit/) / [swift-toolkit](https://github.com/readium/swift-toolkit)）—— 定位器/Locator 模型、导航器分页模式的业界标准
- [KOReader](https://github.com/koreader/koreader) —— Kindle 移植 + 全格式 + StarDict 词典的最佳参考
- [KindleUnpack](https://github.com/kevinhendricks/KindleUnpack) —— MOBI/AZW3 → EPUB 转换算法参考
- Rust crates：`mobi`、`mobi-rs`、`palmdoc`、`kindling-mobi`（解析层）、`boko`（EPUB→KFX/AZW3）、`ebook-rs`（EPUB+CFI）
- [stkclient](https://github.com/maxdjohnson/stkclient) / Rust `send-to-kindle` —— Send to Kindle 社区客户端

---

*下一步建议：先按 P0 搭骨架（Flutter 空壳 + Rust 最小解析 + 一个 EPUB 渲染通），用 1–2 本真实公版书验证管线，再决定是否深入。*
