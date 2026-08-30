# 05 · 测试设计

> 阅读器设计文档集 · v1.0
> 目标：**核心逻辑（Rust）高覆盖、格式兼容有黄金语料背书、性能有硬门槛、跨平台矩阵不回归**。

---

## 1. 测试策略（金字塔）

```
        ┌──────────┐
        │ E2E 冒烟  │  桌面集成测试：导入→阅读→笔记→翻译→导出 全链路（每平台）
        ├──────────┤
        │ 集成测试   │  core+桥接+UI 服务层；黄金语料驱动
        ├──────────┤
        │ Widget/Golden│  页面结构与交互、关键屏截图对比
        ├──────────┤
        │ Rust 单元测试│  解析器/转换器/定位器/领域服务/存储（占比最大）
        └──────────┘
```

- **策略要点**：核心逻辑全部在 Rust 侧 → 单元测试可做到最高性价比覆盖；格式兼容用**黄金语料**做回归；性能用**基准测试**设门槛；UI 用 Widget + Golden 防回归；真机/真桌面只做冒烟与体验项。

---

## 2. 测试层级详述

### 2.1 Rust 单元测试（core）

| 模块 | 覆盖重点 | 典型用例 |
|---|---|---|
| format/epub | 容器解析、OPF/NCX/nav、资源路径、容错 | 坏 zip、缺 mimetype、相对路径穿越 |
| format/mobi | PDB 头、PalmDOC/HUFF-CDIC 解压、EXTH、INDX | 各压缩分支、0 记录书、封面偏移越界 |
| format/azw3 | KF8 内嵌 EPUB 提取、MOBI 回退段 | 混合结构书 |
| format/txt | 编码探测（UTF-8/GBK/Big5）、章节切分 | 无 BOM GBK、混合编码行 |
| convert | 规范化输出正确性（spine/toc/资源重写） | 图片路径、内联字体、多卷拆分 |
| locator | 锚定生成/重定位/降级链 | 换字号后重定位、snippet 容错、章节更名 |
| notes | CRUD、导出格式、级联删除 | Markdown/JSON 转义、空笔记 |
| dict/translate | StarDict 解析、缓存命中、Provider 路由 | 大词库、dz 压缩、超长文本 |
| search | FTS 索引与查询、范围过滤 | CJK 分词、特殊字符 |
| store | 迁移、WAL、崩溃恢复 | schema 从 v1 升 v2、损坏 DB 检测 |

### 2.2 黄金语料测试（格式兼容回归）

- **语料库**：`core/tests/corpus/` 下放**真实公版书**（版权安全，如古登堡计划、公版中文本）+ **构造样例**。每类格式至少：

| 格式 | 真实书 | 构造样例 |
|---|---|---|
| EPUB | 2 本（含图片/内联 CSS/多级目录） | 超大单章、空 spine、相对路径穿越 |
| PDF | 文本型 1 本 + 扫描版 1 本 | 加密标记 PDF、损坏 xref |
| MOBI | 2 本（MOBI7 / 带索引） | 各压缩分支、0 字节 |
| AZW3 | 1 本 | 缺回退段 |
| TXT | 2 本（UTF-8 / GBK） | 大文件 20MB、空行怪癖 |
| FB2 / CBZ | 各 1 本 | 缺文件项 |

- **断言方式**：解析结果快照（章节数/目录结构/元数据/图片数）+ 渲染冒烟（能生成规范 EPUB 并打开到第 N 页不崩溃）。
- **快照测试**（insta/自写）：语料输出与 golden 快照比对，防无意识变更。

### 2.3 集成测试（core + bridge + services）

- Rust 侧：拉起完整 `reader_core`，走"导入→打开→建笔记→翻译（mock provider）→搜索→导出"真实链路（用临时目录 + 内存/临时 DB）。
- Flutter 侧（`integration_test` 桌面）：真实 app 进程，验证 FFI 桥接：调用 `library_import_files` 后书架出现书、笔记面板出现条目。

### 2.4 Widget / Golden 测试（UI）

- Widget：书架空态、导入进度列表、笔记面板渲染、设置表单、翻译卡片状态（加载/成功/失败）。
- Golden：关键屏（书架、阅读器、笔记面板、设置）截图基线，CI 上跑（桌面 3 平台分别建基线，尺寸差异容忍）。

### 2.5 端到端冒烟（每平台）

- 脚本化 E2E（Flutter integration_test / 桌面驱动）：
  1. 导入 3 本不同格式 → 书架可见；
  2. 打开 EPUB → 翻 3 页 → 恢复进度验证；
  3. 选中文本 → 高亮 + 批注 → 面板可见 → 跳转回原文；
  4. 查词 + 选句翻译（mock 网络）；
  5. 导出 Markdown 成功。
- 在 **Windows / macOS / Linux**（CI 虚拟机）+ 移动端阶段 Android 模拟器 / iOS 模拟器各跑一遍。

---

## 3. 测试语料管理

- 语料入库规则：只收**无版权争议**文件；README 注明来源与许可；体积控制（单文件 < 30MB）。
- 语料不打包进发布产物；CI 从仓库 `core/tests/corpus` 直接读取。
- 语料变更需评审（影响快照与基准）。

---

## 4. 性能基准与回归门槛（CI 硬性）

| 基准 | 门槛（桌面 CI 机） | 失败即 PR 阻塞 |
|---|---|---|
| 打开 10MB EPUB → 首屏 | < 500ms | ✓ |
| 解析 5MB MOBI | < 200ms | ✓ |
| 全书搜索（100MB 文本索引） | < 100ms | ✓ |
| 翻页（模拟 100 次） | 平均帧 < 16.7ms | ✓（软门槛，P95） |
| 导入 100 本小书（后台） | < 20s | 软门槛 |
| 内存峰值（20MB 书） | < 300MB | ✓ |

- 工具：`criterion`（Rust bench）+ Flutter `timeline` 采集；基准结果存档，趋势图比对（防慢速退化）。

---

## 5. 模糊测试（解析器健壮性）

- `cargo-fuzz`：对 `format::parse`（epub/mobi/azw3/txt）喂随机字节与**变异语料**（以黄金语料为种子）：
  - 断言：不 panic、不泄漏（miri/ASAN 模式下跑）、返回 `Err` 而非崩溃；
  - 运行时长：CI 每次 10 分钟；nightly 全量 1 小时。
- 模糊测试发现的崩溃点先修后合入。

---

## 6. 兼容性矩阵

| 平台 | WebView 版本 | 特性验证 |
|---|---|---|
| Windows 10/11 | WebView2 | 分页/笔记锚定/深色/快捷键 |
| macOS 12+ | WKWebView | 同上 + 触控板手势 |
| Linux（Ubuntu 22.04/24.04） | WebKitGTK | 分页降级路径（滚动模式） |
| Android 8+（二期） | 系统 WebView | 手势/文件导入/后台恢复 |
| iOS 15+（二期） | WKWebView | 同上 |

- 降级路径测试：Linux WebKitGTK 分页异常 → 自动滚动模式不崩溃（专项用例）。

---

## 7. CI 设计（GitHub Actions）

```
workflow: ci
  job lint-rust / lint-dart          # clippy, fmt, analyzer
  job test-rust                      # cargo test（含黄金语料）+ criterion bench
  job fuzz-smoke                     # cargo-fuzz 10min（x86_64-linux）
  job test-flutter(widget+golden)    # 每 OS 一 job，缓存 pub/cargo
  job e2e                            # 桌面 3 平台 integration_test 冒烟
  job build-artifacts                # 打包，产物上传 artifact
  job bench-report                   # 基准结果 comment 到 PR
```

- 并行策略：矩阵并行 + cargo/pub 缓存；golden 变更需人工确认（`--update-goldens` 显式提交）。
- 发布流水线（tag 触发）：构建 → 签名/公证 → 上传产物 → 生成更新清单（P2 自更新用）。

---

## 8. 覆盖率目标

- Rust 核心（`cargo llvm-cov`）：语句覆盖率 **≥ 85%**，关键模块（format/convert/locator）**≥ 90%**。
- Flutter：页面级 Widget 覆盖 ≥ 70%（重点：笔记与翻译交互路径）。
- 覆盖率作为 PR 报告，不硬阻塞（硬阻塞用基准门槛）。

---

## 9. 手工验收清单（每版本发布前）

- [ ] Windows / macOS / Linux 各装包安装、首次启动、导入 3 格式、全流程冒烟；
- [ ] 深色主题下 EPUB 与 PDF 观感、对比度；
- [ ] 中文/英文书籍排版（CJK 换行、两端对齐、连字）；
- [ ] 断网环境：阅读/查词/笔记/搜索全部可用；在线翻译给出明确失败提示；
- [ ] 超大书（50MB+）打开与翻页不卡死；
- [ ] 异常文件（损坏/加密）提示文案清晰、不崩溃；
- [ ] 崩溃恢复：强杀进程后笔记不丢、下次启动正常；
- [ ] 键盘全操作（桌面）；字号最大档可读性；
- [ ] 无障碍抽查（屏幕阅读器朗读关键控件标签）。

---

## 10. 听书（TTS）测试

### 10.1 单元测试（Rust `tts/`）

- **句切分**：中文标点（。！？；…）、对话引号（"……"）、书名号、数字/日期、英文缩写（e.g.）、超长无标点句、混合中英、段落边界；
- **句 ↔ Locator 双向一致**：切句 → 用 `locator_for_sentence` 得 Locator → `sentence_index_at` 定位回**同一句**（重排/换字号后同样成立）。

### 10.2 集成测试

- **听读进度同步**：模拟播放 N 句 → 退出 → 阅读位置 = 第 N 句（同一 Locator）；
- 听书进度条拖动 = 更新阅读进度；章节连播切章后 Locator 正确；
- 定时到 → Stopped 且进度停在定时句；单句失败跳过、连续失败停止。

### 10.3 Widget / E2E（Flutter）

- 听书入口显隐、控制条状态（播放中/暂停）、迷你播放条跨页面常驻、跟读高亮渲染；
- 桌面 E2E：切后台继续播放 + 系统媒体键（播放/暂停/下一首）控制（Windows / macOS 各跑）；
- TtsEngine 用 **fake 实现**（立即完成/延迟/失败）驱动链路测试；`audio_service` 走平台集成测试真跑。

### 10.4 语料与基准

- 语料：`core/tests/corpus` 增加"复杂标点中文段落"文本样例（含对话/引号/数字）；
- 基准（CI 硬门槛）：10 万字切句 < 50ms；首句出声：系统 TTS < 300ms、在线 < 1s（P95）；句间停顿 < 200ms（预取生效）。

### 10.5 手工验收

- 系统缺中文语音的平台（Windows/Linux）出现安装引导；
- 定时到轻提示、可取消；切换音色/语速即刻生效；
- （P2 移动端）来电中断恢复、锁屏控制。
