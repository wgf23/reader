# 02 · 技术文档

> 阅读器设计文档集 · v1.0
> 范围：平台（PC 优先：Windows/macOS/Linux → 后续 Android/iOS）、格式（EPUB/PDF/MOBI/AZW3/TXT/FB2/CBZ）、约束（性能、体积、离线优先）。

---

## 1. 设计目标回顾

- **性能**：10MB EPUB 打开 < 500ms（桌面）/ < 1.5s（移动）；翻页 60fps；全文搜索 < 100ms。
- **体积**：桌面安装包 < 40MB；移动端每 ABI < 25MB；不内置浏览器引擎。
- **功能重心**：笔记（高亮/批注）与翻译（离线词典 + 在线翻译）。
- **离线优先**：无网络时阅读、查词、笔记、书库全部可用。

---

## 2. 技术选型总表

| 组件 | 选择 | 理由 | 备选 |
|---|---|---|---|
| UI 框架 | **Flutter** | 一套代码覆盖 Win/macOS/Linux/Android/iOS；Skia/Impeller 原生渲染快；桌面端已稳定 | KMP+Compose（桌面导航器弱）、Tauri（移动端年轻）、Electron（体积超标） |
| 核心层 | **Rust** | 解析/转换/检索性能最佳；静态链接体积小；内存安全（崩溃/模糊测试友好） | C++（无内存安全）、Dart 直写（性能与库生态弱） |
| 桥接 | **flutter_rust_bridge** | 成熟代码生成、类型安全、支持异步与流 | 手写 FFI（成本高） |
| Reflow 排版 | **系统 WebView + 分页脚本**（Win: WebView2 / macOS: WKWebView / Linux: WebKitGTK / Android·iOS: 系统 WebView） | 排版质量由 CSS 保证（与 Readium 同模式）；不内置浏览器省 100MB+ | 自研轻量排版引擎（远期替换点，见 §9） |
| PDF | **PDFium**（`pdfium-render` 绑定） | Chrome 同源、稳定、中文支持好 | MuPDF（可顺带 DJVU/XPS，与 e-ink 移植同栈） |
| 存储 | **SQLite**（Rust: `rusqlite`，WAL 模式） | 笔记/进度/缓存/搜索（FTS5）一库搞定 | 自建文件格式（无索引/搜索） |
| 词典 | **StarDict 离线词库**（.ifo/.idx/.dict(.dz)） | KOReader 生态词库量大免费、离线可用 | 内置小词库（首发兜底） |
| 在线翻译 | Provider 接口 + DeepL/Google/有道/OpenAI 适配器（可选） | 可插拔、按用户选择启用 | 单一厂商（锁死） |
| 日志/崩溃 | 本地滚动日志文件（可选 Sentry 上报，默认关闭） | 排障 + 隐私默认 | — |

**选型对照**（为什么不是其他方案）：

| 维度 | Flutter + Rust（采用） | KMP + Compose + Readium | Tauri 2 + Readium-js | Electron + Readium |
|---|---|---|---|---|
| 桌面三平台 | 成熟稳定 | JVM 可用，但渲染导航器弱 | 小（5–10MB） | 大（>100MB，违背体积约束） |
| 移动端 | 同一套代码 | UI 两套、导航器需 kotlin+swift 双实现 | 支持但生态年轻、文件访问受限 | 体积不可接受 |
| 解析性能 | Rust 原生最快 | JVM 够用 | JS 较慢 | JS 慢 |
| 体积 | 桌面 20–40MB | 中等 | 最小 | 最大 |
| 生态参考 | Readest（同架构先例） | Readium 官方 | Thorium 思路 | Thorium |

---

## 3. 格式支持方案

### 3.1 两条渲染管线

```
            规范化 (canonicalize)
      ┌───────────┴───────────┐
 reflow 管线（文字流排版）       page 管线（固定页面）
 EPUB(原生)                   PDF
 MOBI ─┐                     CBZ / CBR
 AZW3 ─┼─ 转换 ─▶ 规范 EPUB ──▶ HTML/CSS 排版 + 分页
 TXT ──┘                     
 FB2 ──┘                    ──▶ PDFium 页面光栅化 + 文本层
```

### 3.2 规范 EPUB（我们定义的"最小子集"）

所有 reflow 书转换后的统一中间格式，**只保留我们渲染所需子集**：

- `mimetype` + `META-INF/container.xml`（标准 EPUB 容器）
- 单 OPF：`metadata`（title/creator/language/identifier）、`manifest`、`spine`（章节顺序）
- 章节 XHTML：**限制 CSS 子集**（见 §4.1），资源（图片/字体）内联路径重写
- 导航：EPUB3 `nav.xhtml` + 兼容 NCX
- 规范 EPUB 以**缓存文件**形式落盘（键 = 源文件内容 hash），二次打开秒开

### 3.3 MOBI / AZW3 转换（算法步骤）

1. 解析 PDB 容器：头 + 记录表 → 定位 PalmDOC 记录；
2. 解压内容流：PalmDOC LZ77 或 HUFF/CDIC（用 Rust `mobi`/`palmdoc`/`mobi-rs` crate，缺的压缩分支自补）；
3. 读 EXTH 元数据：书名/作者/语言/ASIN/封面偏移/页码映射；
4. 内容为大 HTML：按 `<mbp:pagebreak>`、标题层级、INDX 索引**拆分为章节**；
5. 抽图片（RECORD 0 内联图 + image 记录），重建资源路径；
6. 生成规范 EPUB（含 TOC 层级，尽量还原原书目录）。

> AZW3/KF8 = PDB 内嵌一套完整 EPUB 结构 + 旧 MOBI 回退段，解出后按 3.2 直接规范化。
> 参考算法实现：[KindleUnpack](https://github.com/kevinhendricks/KindleUnpack)。

### 3.4 其他格式

- **TXT**：编码探测（UTF-8/GBK/Big5 优先级启发式）→ 按空行/章节标题模式自动切章 → 包成规范 EPUB；编码可手动指定（设置）。
- **FB2**：XML 遍历 → 规范 EPUB（段落/图片/注释映射）。
- **CBZ/CBR**：zip/rar 内图片序列 → 固定页管线（按文件名排序，支持单页/双页扫描模式）。
- **PDF**：不进规范 EPUB，直接走 PDFium；文本型 PDF 保留文本层（选择/搜索/笔记锚定），扫描版仅图像。

### 3.5 明确不支持的格式

- **KFX**（亚马逊专有，未文档化）：不做。用户无 Kindle 需求（本期已排除）。
- **DRM 加密文件**：不做破解；解析时识别加密标记并给出明确提示。

---

## 4. 渲染方案

### 4.1 Reflow：WebView 分页（Readium Navigator 模式）

- 每个章节（spine 中的一个资源）加载进隐藏 WebView，注入分页脚本：
  1. 用 **CSS multi-column**（`column-width` 按视口计算）把章节排版成等宽列；
  2. JS 测量每列页断点，得到"页 → 列偏移"映射表；
  3. 翻页 = 平移 WebView 视口到目标列（零重排，60fps）；
  4. 滚动模式 = 直接整章滚动（WebView 原生滚动）。
- 同一时刻只加载当前章节 + 预取相邻章节，**资源懒加载**控制内存。
- CSS 子集策略：转换时把书的 CSS 白名单化（保留 font/color/line-height/text-align/margin 等排版属性，剥离脚本/外部资源/危险属性），兼顾"原书排版"与"可预测分页"。
- 主题/字号：不改书 CSS，改 WebView 根样式注入（字号缩放、夜间反色滤镜），保证锚定稳定。

### 4.2 各平台 WebView 依赖

| 平台 | 组件 | 最低要求 |
|---|---|---|
| Windows | WebView2 Runtime | Win10/11 预装，Win7/8 需装运行时（安装包带检测提示） |
| macOS | WKWebView | 系统内置 |
| Linux | WebKitGTK | 发行版包依赖（deb/rpm/AppImage 打包时声明） |
| Android | 系统 WebView（Chromium） | Android 5+ |
| iOS | WKWebView | 系统内置 |

### 4.3 PDF 渲染

- 按需渲染可见页为位图（缓存 LRU 最近 N 页）；缩放/裁剪重渲染；深色主题用反色渲染；
- 文本型 PDF：PDFium 文本层用于选中/搜索/笔记锚定（页 + 矩形 + 文本片段）；
- 目录：PDF outline 提取；连续滚动 + 单页模式。

---

## 5. 数据与存储

- 单库文件 `library.db`（SQLite，WAL）：表结构见模块设计文档 §5。
- 目录布局：`<数据目录>/library.db`、`cache/`（规范 EPUB、封面缩略图、翻译缓存）、`fonts/`（用户字体）、`dicts/`（StarDict 词库）、`logs/`。
- 数据目录按平台规范（Windows `%APPDATA%`、macOS `~/Library/Application Support`、Linux `~/.local/share`）。

---

## 6. 性能设计（预算 + 手段）

| 指标 | 预算 | 实现手段 |
|---|---|---|
| 打开 10MB EPUB（桌面） | < 500ms | Rust 解压+解析在主线程外（线程池）；只建索引不渲染全书；分页懒加载 |
| 打开 10MB EPUB（移动） | < 1.5s | 同上 + 启动预热的 WebView 复用 |
| 解析 5MB MOBI | < 200ms | Rust 原生 + 转换结果缓存（二次打开 ≈ 纯 IO） |
| 翻页 | 60fps | 列映射翻页零重排；动画走合成器 |
| 全文搜索 | < 100ms | FTS5 索引入库时构建，后台增量 |
| 内存峰值（读 20MB 书） | < 300MB | 只加载当前章节；PDF 页位图 LRU |
| 导入 100 本书 | 后台并行，不卡 UI | 任务队列 + 可取消 |

---

## 7. 体积设计（预算 + 手段）

| 目标 | 手段 |
|---|---|
| 桌面安装包 < 40MB | 不内置浏览器（省 100MB+）；Rust 核 `#![no_std]` 不必要则裁剪 feature（去调试符号、LTO、strip）；图标/字体资源压缩；按平台打包（Win: MSIX/NSIS，macOS: dmg，Linux: AppImage/deb） |
| Android 每 ABI < 25MB | APK 按 ABI 拆分；`--obfuscate` + 资源收缩；只带 arm64 + x64 |
| iOS < 30MB | 同上思路；PDFium 只编 arm64 |
| 首包安装后更新 | 桌面 P2 支持增量更新（差分） |

---

## 8. 依赖清单（初版）

**Rust crates**：`mobi`（MOBI/AZW3 解析）、`palmdoc`（PalmDOC 解压）、`zip`、`quick-xml` / `roxmltree`（XML）、`flate2`（zlib）、`rusqlite`（SQLite + FTS5）、`serde`/`serde_json`、`sha2`（内容指纹）、`encoding_rs`（GBK/Big5）、`pdfium-render`（PDF）、`thiserror`/`anyhow`、`log`/`tracing`。转换与词库解析中 `stardict` 类 crate 若缺失则自写（~200 行）。

**Flutter packages**：`flutter_rust_bridge`、`webview`（可选 `flutter_inappwebview`）、`provider`/`riverpod`（状态）、`go_router`（路由）、`window_manager`（桌面窗口）、`file_picker`、`drag_and_drop`、`path_provider`、`shared_preferences`（轻设置；重设置进 SQLite）。听书（P1，见 §11）：`flutter_tts`、`just_audio`、`audio_service`；移动端加 `audio_session`（P2）。

**系统依赖**：WebView2 Runtime（Win）、WebKitGTK（Linux）、无其他。

---

## 9. 可扩展点（预留）

1. **渲染引擎替换点**：WebView 分页封装为 `ReflowEngine` 接口；远期可换自研轻量排版引擎（Flutter Text 直接重排，KOReader/FBReader 路线）而 UI 不动。
2. **同步后端接入点**：笔记/进度读写走 `AnnotationRepository`/`ProgressRepository` 接口，P2 可插入 WebDAV/自建后端。
3. **TTS/朗读**：听书方案见 §11（P1 起）；Locator 模型已提供"位置→文本"能力，句级切分与进度映射在核心 `tts/` 模块。
4. **更多格式**：DJVU（MuPDF）、漫画增强，仅扩展 canonicalize/渲染管线。

---

## 10. 非功能设计要点

- **错误降级链**：解析失败 → 结构化错误（含原因分类：损坏/加密/未知格式）→ UI 友好提示；永不崩溃、永不白屏（有兜底页）。
- **隐私**：默认零上报；在线翻译与在线 AI 音色仅发送选中文本；翻译/音频缓存可一键清空。
- **国际化**：UI 文案走 arb（Flutter i18n），首版中/英；排版引擎天然支持 CJK/RTL。
- **可访问性**：字号放大上限、对比度、键盘全操作（桌面）。

---

## 11. 听书（TTS）方案

> 参考番茄小说听书形态：AI 朗读、多音色、语速调节、定时关闭、后台播放、章节连播、听读进度一体。
> 总体设计：**合成（TTS）与播放分离**；句级切分与进度映射放 Rust 核心，合成与播放走 Flutter 插件（音频生命周期天然在 UI 侧）。

### 11.1 TTS 引擎分层（默认离线，可选增强）

| 层 | 引擎 | 安装体积 | 离线 | 音质 | 说明 |
|---|---|---|---|---|---|
| **系统 TTS（默认）** | `flutter_tts` 封装：Windows SAPI / macOS AVSpeechSynthesizer / Linux speech-dispatcher / Android TextToSpeech / iOS AVSpeechSynthesizer | 0（系统自带） | ✅ | 一般（Windows 中文需系统语音包） | 首版默认，零体积零成本 |
| 本地神经音色（可选） | Piper（onnx，中文 `zh_CN-huayan-medium` 约 50MB 级，端侧运行） | 按需下载到**用户数据目录**，不进安装包 | ✅ | 好 | P2 增强 |
| 在线 AI 音色（可选） | 火山引擎 / Azure TTS（番茄同款路线） | 0 | ❌（需网络+费用） | 最好 | P2 增强，显式授权 |

### 11.2 播放与后台

- 播放：`just_audio`（或 `audioplayers`）播放合成音频；系统 TTS 可流式直播，Piper/在线产出去重音频流。
- 后台播放与系统媒体控制：`audio_service` 统一接入 —— Windows SMTC/媒体键、macOS Now Playing、Android 前台服务+通知栏（P2）、iOS 后台音频会话（P2）。

### 11.3 句级切分与听读进度（关键设计）

- Rust 核心新增 `tts/` 模块：对章文本按中文标点（`。！？；…`）与段落边界**切句**，输出：
  `SentenceChunk { text, char_range, locator }`；
- 播放逐句推进，**当前句 ↔ Locator 双向映射** → 听书进度与阅读进度是**同一个 Locator**（复用 `reading_progress` 表，无新表）；
- 听书 = "带音频播放的阅读会话"：进入听书不改变阅读位置，退出听书回到阅读同位置（番茄小说式无缝切换）。

### 11.4 性能预算

- 10 万字章节切句 < 50ms（Rust）；
- 首句合成到出声：系统 TTS < 300ms、在线 < 1s（P95）；
- 预取下一句（流式合成/缓存），句间停顿 < 200ms。

### 11.5 平台注意

- Windows：中文朗读依赖系统语音包，设置页提供检测与安装引导；
- Linux：speech-dispatcher 音质一般，听书设置中引导用户启用 Piper（P2）；
- macOS / 移动端：系统语音直接可用。

### 11.6 依赖更新

- Flutter（P1）：`flutter_tts`、`just_audio`、`audio_service`；移动端加 `audio_session`（P2）。
- Rust：无新增（切句用现有文本处理能力）；P2 可选 `piper-rs`（本地神经音色）。
