<!-- wf-meta: req=REQ-006 | phase=product-preview | agent=product-reviewer | date=2026-09-09 | gate=passed -->
# REQ-006 · 阶段5a 产品验收（设计稿 ↔ 实现截图 对照）

> 视角：**产品/用户**（非开发自评）。UI 权威：`docs/wireframes/09-listen-player.svg`、
> `docs/wireframes/10-listen-settings.svg`、`docs/wireframes/08-translation.svg`、
> `docs/wireframes/03-settings.svg`、`docs/wireframes/reader-ui-v2/04-selection.svg`。
> 截图来源：**真实引擎渲染**（`xvfb-run flutter test integration_test/screenshots_test.dart -d linux`
> + `RepaintBoundary.toImage`，真实字体/资源；**非** widget golden 的 Ahem 方块占位）。
>
> 采集命令：`bash scripts/ui-screenshots.sh REQ-006`（cargo build → 集成测试截图 → 生成报告）。
> 产物：`product-preview-REQ-006-tts-online-translate.html`（5 屏，视口不一致 5，无实现截图 0）、
> `product-preview.manifest.json`、`app/screenshots/{listen_follow_scroll,listen_settings_fallback,translation_cards,settings_translate,reader_selected}.png`。
>
> **核对方法**：本轮评审为纯文本环境（模型无图像直读），逐屏判定基于**真实渲染 PNG 的像素/几何分析**
> （色彩聚类 + 颜色 bbox/行带探针，均为真实引擎输出），并交叉引用真实渲染集成测试断言与既有 widget 单测
> （`translate_reader_test.dart` US-18、`settings_page_test.dart` US-15、`listen_page_test.dart` US-21）。
> 证据均为可复算的坐标/像素，非开发口述。

---

## 1. 对照方法

1. **真实渲染截图**：扩展 `app/integration_test/screenshots_test.dart`（**仅新增测试用例/harness，零生产代码改动**），
   新增 4 个 REQ-006 用例，覆盖 S1/S2/S3/S4 新 UI；S5 复用既有 `reader_selected` 截图（重跑后字节一致）。
2. **S1 自动滚动为行为型验收**：用 30 句长章节（每句约 28 字，正文远超一屏）+ `FakeTtsEngine.emitStarted(20)`
   把当前句切到第 21 句，集成测试断言 `ScrollableState.position.pixels > 0`（自动滚动代理），再截图。
3. **像素/几何证据**：对每张 PNG 做颜色聚类与颜色 bbox/行带分析（见各屏证据列），定位高亮带、徽标、
   控制条、标签、掩码 key、回退提示等的真实位置与颜色。
4. **判定口径**：设计意图/验收点命中 → 通过；**设计已授权取舍**（02-design §9）→ 记 tradeoff，不计偏差；
   少做 / 做错 / 发明新交互 → 偏差 → rework-B。

---

## 2. 逐屏对照表

### S1 听书模式 · 跟读（线框 09）—— 关键新行为：自动滚动进视口

- 设计稿：`docs/wireframes/09-listen-player.svg`（900×640 横屏）
- 实现截图：`app/screenshots/listen_follow_scroll.png`（1170×2532 竖屏，逻辑 390×844）

| 设计意图 / 验收点 | 实现证据（真实渲染像素/几何） | 判定 |
|---|---|---|
| 当前朗读句蓝色半透明高亮 | 高亮色 `(197,214,249)`（≈`0x401A73E8` 叠加白底）行带 **y656–940**（逻辑 219–313），横向 x72–1090（逻辑 24–363，满宽换行）；当前句为第 21/30 句 | 通过 |
| **自动滚动进视口**（关键新行为） | 高亮句落在逻辑 y219–313（视口 0–844 内）；其上方仍有 5 行正文（逻辑 y102–212），**证明非首屏第 0 句、已滚动**；集成测试断言 `position.pixels > 0` 通过 | 通过 |
| 「朗读中」徽标 | 蓝色 `(26,115,232)` 簇 **y204–268**（逻辑 68–89），位于正文上方 | 通过 |
| 控制条第 1 行：章节名 | 控制条白底 `(255,255,255)` 124330 px；章节名暗字带逻辑 **y679–692**（控制条顶部，居中） | 通过 |
| 第 2 行：⏮ / ⏸ / ⏭ | 播放/暂停按钮 `IconButton.filled` 主色 `(103,80,164)` 簇 **y2144–2292**（逻辑 715–764）；左右 `skip_previous/skip_next` 图标为 onSurface 文本带 | 通过 |
| 第 3 行：句级进度条 + 1.0x | Slider 激活轨主色簇 **y2366–2424**（逻辑 789–808）；蓝色 `1.0x` 文本 `(26,115,232)` 簇 **y2380–2408**（逻辑 793–802） | 通过 |
| 右侧定时按钮（禁用占位） | `onTimer: null`（`listen_page.dart:408`）→ OutlinedButton 禁用灰置；REQ-005 既有截图 `listen_player.png` 重跑后字节一致（156603 B） | 通过 |
| 右侧音色按钮（禁用占位） | `onVoice: null`（`listen_page.dart:409`）→ OutlinedButton 禁用灰置；文案「🎙 系统男声」（线框「男声·AI」为 P2 示意，见 §4 tradeoff 6） | 通过 |
| 正文区不得混入选中工具条 | 无 `ReaderSelectionToolbar`（未 import/未构建） | 通过 |

**S1 结论：通过。** 自动滚动这一关键新行为在真实渲染中可见（高亮句进视口 + 上方有正文 + offset>0 断言）。

### S2 听书设置面板（线框 10）—— 新增：无匹配音色回退提示

- 设计稿：`docs/wireframes/10-listen-settings.svg`（900×640 横屏）
- 实现截图：`app/screenshots/listen_settings_fallback.png`（1170×2532 竖屏；`voiceFallback: true`）

| 设计意图 / 验收点 | 实现证据（真实渲染像素/几何） | 判定 |
|---|---|---|
| **无匹配音色显示「系统默认音色」**（US-21 P1） | 红色 `(183,28,28)` 文本带 **y260–292**（逻辑 87–97），x66–696（逻辑 22–232）＝「当前：系统默认音色（未找到所选音色）」；`listen_page_test.dart:776` 另断言控制条显示「🎙 系统默认音色」 | 通过 |
| 系统男声可选（选中态） | 选中态主色 `(103,80,164)` 簇 **y334–386**（逻辑 111–129） | 通过 |
| 系统女声可选 | `RadioListTile('系统女声')` 可点（`listen_settings_sheet.dart:93`）；REQ-005 既有截图回归绿 | 通过 |
| AI 音色灰置 +「需网络（P2）」 | `RadioListTile(enabled:false)`（`listen_settings_sheet.dart:99`）；文案命中 | 通过 |
| Piper 灰置 +「下载 52MB（P2）」 | `enabled:false`（`:106`）；文案命中 | 通过 |
| 声音克隆灰置 +「评估中」 | `ListTile(enabled:false)`（`:113`）；文案命中 | 通过 |
| 语速 0.5x–3.0x + 当前 1.0x | Slider 主色簇 **y1048–1106**（逻辑 349–369）；蓝色 `1.0x` `(26,115,232)` **y1062–1090**（逻辑 354–363） | 通过 |
| 定时关闭 5 项全禁用 | `RadioListTile(enabled:false)` ×5（`:168`）；REQ-005 截图回归绿 | 通过 |
| 后台播放开关禁用 | `SwitchListTile(onChanged:null)`（`:181`） | 通过 |
| 隐私文案含「离线音色不联网」 | `listen_settings_sheet.dart:197` 文案；REQ-005 截图回归绿 | 通过 |

**S2 结论：通过。** REQ-006 新增的回退提示在真实渲染中可见，其余 P2 禁用项与线框一致。

### S3 翻译浮层 · 译文卡片来源标签（线框 08）

- 设计稿：`docs/wireframes/08-translation.svg`（900×640 横屏）
- 实现截图：`app/screenshots/translation_cards.png`（1170×2532 竖屏；同屏堆叠 4 张卡片）

| 设计意图 / 验收点 | 实现证据（真实渲染像素/几何） | 判定 |
|---|---|---|
| 「在线」标签（provider=deepl，未缓存） | 4 张卡片表面 `(247,242,250)` 行带 y60–420 / 438–798 / 816–1188 / 1206–1632（逻辑 20–140 / 146–266 / 272–396 / 402–544）；卡片 1 主色 provider 名簇 y106–138 | 通过 |
| 「离线」标签（provider=offline） | 卡片 2 provider 名簇 y484–508；`translate_reader_test.dart:230-234` 断言「离线」+「offline」且「在线」为 0 | 通过 |
| 「缓存」标签（fromCache=true） | 卡片 3 出现 `secondaryContainer` 徽标底 `(232,222,248)` **y852–910**（逻辑 284–303），provider 名簇 y868–900 | 通过 |
| provider 名可见 | 4 张卡片各 1 处主色 `(103,80,164)` provider 名（deepl/offline/deepl/offline） | 通过 |
| 回退提示「在线失败，已回退离线」 | 卡片 4 红色 `(179,38,30)` 文本带 **y1552–1580**（逻辑 517–527），x100–436（逻辑 33–145） | 通过 |
| 译文正文 + 标签行布局不变 | `translation_popup.dart` 仅改标签映射 + 追加提示行；卡片/浮层骨架未动 | 通过 |

**S3 结论：通过。** 三种来源标签 + provider 名 + 回退提示均按 02-design §2.3 渲染。

### S4 设置页 · 翻译策略与掩码 key（线框 03）

- 设计稿：`docs/wireframes/03-settings.svg`（900×640 横屏）
- 实现截图：`app/screenshots/settings_translate.png`（1170×2532 竖屏；`getConfig` 返回 `provider='auto'`、`hasDeeplKey=true`、`deeplKeyMasked='••••••••'`）

| 设计意图 / 验收点 | 实现证据（真实渲染像素/几何） | 判定 |
|---|---|---|
| 既有「词典与翻译」区块内新增「翻译策略」下拉 | 区块标题 onSurface 文本带逻辑 y76–91；下拉浮标「翻译策略」暗字带逻辑 y215–225 | 通过 |
| 当前策略显示「自动（在线优先）」 | 下拉值暗字带逻辑 y232–247（x35–149，宽 ~114 逻辑 ≈ 8 字），右侧下拉箭头 x~1050；集成测试 `find.text('翻译策略')`/`find.text('自动（在线优先）')` 断言通过 | 通过 |
| 「DeepL API Key」输入框可见 | 输入框浮标暗字带逻辑 y289–299（x33–122）；边框描边 `(121,116,126)` 行带逻辑 y278–331 | 通过 |
| 已配置 key 时掩码回填（不回填明文） | 输入区暗字带逻辑 **y310–314，x35–108（宽 ~73 逻辑）** ＝ 8 个掩码圆点；`settings_page_test.dart:84-91,135` 断言 `controller.text == '••••••••'`；`getConfig` DTO 只回传掩码、绝无明文（`translate_backend.dart:59-73`） | 通过 |
| 仍在「词典与翻译」区块内，无新增页面 | 单页 `ListView`；未新增路由/页面 | 通过 |
| 导入词库 / 清空翻译缓存等既有控件保留 | 「导入词库（.ifo）」主色按钮簇逻辑 y112–143；「保存」主色按钮簇逻辑 y296–327；「清空翻译缓存」主色描边按钮文本带逻辑 y352–367 | 通过 |

**S4 结论：通过。** 策略下拉 + 掩码回填（8 圆点、无明文）在真实渲染中可见，未新增页面/改导航。

### S5 阅读器 · 长按选词工具条（04-selection，回归守护）

- 设计稿：`docs/wireframes/reader-ui-v2/04-selection.svg`（900×640 横屏）
- 实现截图：`app/screenshots/reader_selected.png`（1170×2532 竖屏）

| 设计意图 / 验收点 | 实现证据 | 判定 |
|---|---|---|
| 自定义工具条五入口齐全 | `selection_toolbar.dart:26-30` 恰好 `划重点/笔记/翻译/查词/复制` 五项；截图命中 | 通过 |
| 无系统原生 ActionMode/工具条 | REQ-005 既有配置断言（分页 `disableContextMenu`、滚动 `contextMenuBuilder → SizedBox.shrink()`）回归绿 | 通过 |
| 选中文本有高亮 | 选中浅蓝高亮簇可见（REQ-005 已核） | 通过 |
| **零改动守护** | `reader_selected.png` 重跑后字节 **143735 B，与 REQ-005 完全一致**；本 REQ diff 未触及 `selection_toolbar.dart` / 选中链路 | 通过 |

**S5 结论：通过（零改动回归守护）。**

---

## 3. 偏差清单

| # | 屏 | 类型（少做/做错/发明） | 证据 | 判定 |
|---|---|---|---|---|
| — | — | **无** | 上述 5 屏全部验收点命中，未发现少做/做错/发明新交互 | — |

> **deviation 计数 = 0**（无未授权偏差）。相关 tradeoff/结构性差异见 §4，均不构成偏差。

---

## 4. 授权取舍 / 低风险差异说明（非偏差）

对照 `02-design.md §9` 的 13 条授权取舍，本 REQ UI 相关者逐条说明：

1. **取舍 9 · 自动滚动用 `TextPainter` 计算 offset**（非 span `ensureVisible`）：S1 实现即此方案，
   验收代理为「offset 单调 / 锚点可见」，本 REQ 断言 offset>0 + 高亮进视口，**符合授权**。
2. **取舍 11 · 音色无匹配显示「系统默认音色」**，男女声切换在缺音色设备上名存实亡：S2 已按此显示，**授权接受**。
3. **取舍 12 · P1 项延后**（US-5/US-18/US-21）：本 REQ 已全部落地（onStart 高亮/滚动、来源标签、音色回退提示），
   超出下限，**不构成偏差**。
4. **取舍 5 · key 仅掩码回填**：S4 显示 8 圆点、不回填明文，**符合授权**。
5. **取舍 4 · 空 key 保存=清除**、**取舍 13 · key 明文存 settings**：属设置页语义/安全取舍，
   本期授权范围（加密/钥匙串留后续 REQ），UI 上不可见差异。
6. **线框 09 音色按钮文案「🎙 男声·AI」→ 实现「🎙 系统男声」**：沿用 REQ-005 02-design §5.1
   「线框 AI 属 P2 示意」，实现显示当前系统音色，**授权取舍**。
7. **S4 移动端无左侧导航**：线框 03 为 900×640 横屏（含左侧导航栏），实现为 390×844 竖屏单列设置页。
   此为 REQ-003 既有形态、REQ-006 §6 明确「不改左侧导航」，**非本 REQ 引入**；属下述视口适配结构性差异。
8. **截图 harness 使用默认 M3 主题（主色紫 `#6750A4`）而非生产 indigo 种子色**：
   `integration_test` 的 `_pack` 自建 `MaterialApp`，不加载 `main.dart` 的 `colorSchemeSeed: Colors.indigo`。
   仅影响强调色相，**不影响布局/控件/文案**；为既有截图 harness 的已知限制（REQ-005 同款），**非实现偏差**。

---

## 5. 结构性结论：视口方向不一致（5/5）

- **现象**：5 张设计稿均为 **900×640 横屏**（桌面/平板示意，含侧边导航/边缘热区），实现截图为
  **1170×2532 竖屏**（逻辑 390×844）；报告脚本对 5 屏全部标注「⚠ 视口不一致」。
- **竖屏适配是否合理**：
  - **09 听书页**：正文（可滚动）置顶 + 控制条吸底；高亮句在自动滚动后落在视口内（逻辑 y219–313）。**合理。**
  - **10 听书设置**：横屏 740×466 卡片 → 全宽可滚动底部弹层；新增回退提示在逻辑 y87–97，未溢出。**合理。**
  - **08 翻译浮层**：横屏左右分栏（正文/译文卡）→ 竖屏纵向堆叠 4 张卡片；标签/正文/提示齐全。**合理。**
  - **03 设置页**：横屏左导航 + 右表单 → 竖屏单列设置页（导航折叠）；「词典与翻译」区块内策略下拉 +
    掩码 key 可见。**合理**（左导航折叠属既有移动端适配，非本 REQ 引入）。
  - **04-selection**：工具条居中于选中区上方，竖屏可见。**合理。**
- **限制与建议**：横屏低保真稿只能校验「结构/元素/行为有无」，无法校验横向比例/间距级视觉还原。
  若后续需要像素级视觉验收，建议**补 390×844 竖屏设计稿**。当前不构成放行阻塞。

---

## 6. Gap / 未覆盖说明

| 项 | 说明 | 处置 |
|---|---|---|
| 真机系统 TTS 真正出声 / 中文语言 / 音频焦点 / release 联网 / 真实 DeepL | 依赖 Android 系统语音与用户 key，集成测试无法采音/联网 | `03-review.md §4` 真机手工清单 1–8 项，发布阶段记录 |
| 无匹配音色的控制条「🎙 系统默认音色」 | 本次 S2 截图展示的是设置面板提示；控制条变体未单截图 | 由 `listen_page_test.dart:776-790` 断言覆盖（`find.text('🎙 系统默认音色')`），非 gap |
| 分页禁原生选择菜单 | WebView 配置项，非 Flutter 层可截图 | REQ-005 既有配置断言覆盖；真机清单 |

> 5 屏均有真实实现截图，**gap = 0**（报告「无实现截图 0」）。

---

## 7. 结论

- **逐屏判定**：S1 通过、S2 通过、S3 通过、S4 通过、S5 通过（回归）。
- **deviation 计数 = 0**（无未授权偏差；§4 差异均为设计/ADR 已授权取舍或既有 harness/视口适配的非契约差异）。
- **闸门5 前置判定：pass** —— 允许进入阶段5 delivery / release-manager 合并主线；**无需 rework-B**。
- 建议（非阻塞）：补 390×844 竖屏设计稿以支持像素级视觉验收；真机 8 项按 `03-review.md §4` 执行。

---

## 8. 本阶段新增/修改产物

| 文件 | 变更 |
|---|---|
| `app/integration_test/screenshots_test.dart` | 新增 4 个 REQ-006 真实渲染截图用例（S1 自动滚动含 offset>0 断言、S2 音色回退提示、S3 四种译文卡片、S4 策略+掩码 key）+ 30 句长章节语料/后端；**零生产代码改动** |
| `app/screenshots/listen_follow_scroll.png` | 新增（真实渲染，542853 B） |
| `app/screenshots/listen_settings_fallback.png` | 新增（真实渲染，190078 B） |
| `app/screenshots/translation_cards.png` | 新增（真实渲染，292177 B） |
| `app/screenshots/settings_translate.png` | 新增（真实渲染，129492 B） |
| `app/screenshots/{listen_player,listen_settings,reader_selected,...}.png` | 重新渲染（字节一致，回归） |
| `workflow/backlog/REQ-006-tts-online-translate/product-preview.manifest.json` | 新增（S1–S5，impl 指向真实渲染截图） |
| `workflow/backlog/REQ-006-tts-online-translate/product-preview-REQ-006-tts-online-translate.html` | 新增（5 屏对照报告，视口不一致 5，gap 0） |
| `workflow/backlog/REQ-006-tts-online-translate/05b-product-preview.md` | 本文件 |
