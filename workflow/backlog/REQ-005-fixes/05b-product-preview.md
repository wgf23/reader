<!-- wf-meta: req=REQ-005-fixes | phase=product-preview | agent=product-reviewer | date=2026-09-08 | gate=passed -->
# REQ-005-fixes · 阶段5a 产品验收（设计稿 ↔ 实现截图 对照）

> 视角：**产品/用户**（非开发自评）。UI 权威：`docs/wireframes/09-listen-player.svg`、
> `docs/wireframes/10-listen-settings.svg`、`docs/wireframes/reader-ui-v2/04-selection.svg`。
> 截图来源：**真实引擎渲染**（`xvfb flutter test integration_test -d linux` + `RepaintBoundary.toImage`，
> 真实字体/资源；非 widget golden 的 Ahem 方块占位）。
>
> 采集命令：`bash scripts/ui-screenshots.sh REQ-005-fixes`
> 产物：`product-preview-REQ-005-fixes.html`（3 屏，视口不一致 3，无实现截图 0）、
> `product-preview.manifest.json`、`app/screenshots/{listen_player,listen_settings,reader_selected,reader_more}.png`。
>
> 核对方法：因本轮评审为纯文本环境（无图像直读），逐屏判定基于**真实渲染 PNG 的像素/几何分析**
> （色彩聚类 + 控件 rect 探针，均为真实引擎输出），并交叉引用 `app/test/listen_page_test.dart`
> 的控件断言。证据均为可复算的坐标/像素，非开发口述。

---

## 1. 逐屏对照表

### S1 听书模式 · 跟读（线框 09）

- 设计稿：`docs/wireframes/09-listen-player.svg`（900×640 横屏）
- 实现截图：`app/screenshots/listen_player.png`（1170×2532 竖屏，逻辑 390×844）

| 设计意图 / 验收点 | 实现证据（真实渲染） | 判定 |
|---|---|---|
| 正文区 + 当前朗读句高亮 | `ListenFollowHighlight` rect (24,106) 342×124；当前句浅蓝高亮带像素簇 (75,321)-(1041,411) → 逻辑 (25,107)-(347,137) 322×30，宽 322px ≈ 首句 19 字 ×17px | 通过 |
| 「朗读中」徽标 | 蓝色圆角徽标像素簇 (72,204)-(234,270) → 逻辑 (24,68)-(78,90)，文案 `朗读中` | 通过（位置差异见 §3.3） |
| 控制条第 1 行：章节名 | `find.text('第三章 · 起风了')` rect (140.8,674.5) 108.4×22，居中可见 | 通过 |
| 第 2 行：⏮ / ⏸ / ⏭ | `Icons.skip_previous` (64,727.5) / `Icons.pause` 34×34 (116,722.5) / `Icons.skip_next` (178,727.5)；播放中显示暂停图标 | 通过 |
| 第 3 行：句级进度条 + 1.0x | `Slider` rect (29.5,774.5) 290.6×48；蓝色「1.0x」文字簇逻辑 (339-370, 333-343) | 通过 |
| 右侧定时按钮（禁用占位） | `OutlinedButton('⏱ 30 分钟')` rect (244.5,704.5) 116×32；`onPressed == null` | 通过 |
| 右侧音色按钮（禁用占位） | `OutlinedButton('🎙 系统男声')` rect (244.5,742.5) 116×32；`onPressed == null`；共 2 个 OutlinedButton，`enabled=[false,false]` | 通过 |
| 正文区不得混入选中工具条 | 无 `ReaderSelectionToolbar` | 通过 |
| 底部「迷你播放条/空格/←→」 | 明确 P2 不做（01-req §1.2 划界），线框为示意说明非控件 | 通过（范围划界） |

**S1 结论：通过。** 控制条 7 类元素齐全且均在 390×844 视口内（最大 bottom=822.5，无溢出）。

### S2 听书设置面板（线框 10）

- 设计稿：`docs/wireframes/10-listen-settings.svg`（900×640 横屏）
- 实现截图：`app/screenshots/listen_settings.png`（1170×2532 竖屏，逻辑 390×844）

| 设计意图 / 验收点 | 实现证据（真实渲染） | 判定 |
|---|---|---|
| 标题「听书设置」 | rect (20,24.5) 310×23，暗色文字区域命中 | 通过 |
| 系统男声可选（选中态） | 选中蓝色单选环+点像素簇 (129,270)-(183,324)/(144,285)-(171,312) → 逻辑 (43,90) 18×18；`RadioListTile` 可选 | 通过 |
| 系统女声可选 | 文案 `系统女声` 存在；该行无蓝色（未选中灰环） | 通过 |
| AI 音色灰置 +「需网络（P2）」 | 文案存在；该行区域 dark=0 / gray=871（纯灰） | 通过 |
| Piper 灰置 +「下载 52MB（P2）」 | 文案存在；`RadioListTile.enabled == false`（单测断言） | 通过 |
| 声音克隆灰置 +「评估中」 | 文案 `声音克隆 · 评估中`；区域 dark=0 / gray=615 | 通过 |
| 语速 0.5x–3.0x + 当前 1.0x | `Slider` rect (20,314) 317.6×48；蓝色激活轨 (132,984)-(327,1044) → 逻辑宽 65px ≈ (1.0-0.5)/(3.0-0.5)=20%；两端 `0.5x`/`3.0x` 暗字；蓝色 `1.0x` | 通过 |
| 定时关闭 5 项全禁用 | `关闭/15/30/60/本章结束` 文案齐全；选项区 dark=0 / gray=1648（全灰） | 通过 |
| 后台播放开关禁用 | `SwitchListTile('后台播放')` rect (20,558) 350×40；区域 dark=0 / gray=355；`onChanged == null` | 通过 |
| 隐私说明文案 | 底部文案区 rect (31,617) 328×32（bottom=649，视口内）；暗字区域命中，含「离线音色不联网」 | 通过 |

**S2 结论：通过。** 面板全部内容 bottom=649 < 视口 844，无截断/溢出；P2 项灰置可断言。

### S3 阅读器 · 长按选词工具条（回归守护）

- 设计稿：`docs/wireframes/reader-ui-v2/04-selection.svg`（900×640 横屏）
- 实现截图：`app/screenshots/reader_selected.png`（1170×2532 竖屏）

| 设计意图 / 验收点 | 实现证据（真实渲染） | 判定 |
|---|---|---|
| 浮动工具条五入口齐全 | `ReaderSelectionToolbar` rect (48.4,232) 293.3×59；`划重点/笔记/翻译/查词/复制` 五处文案均命中（y=266） | 通过 |
| 工具条随选中区浮动、选柄可见 | 选中浅蓝高亮簇 (470,816)-(740,948) → 逻辑 (157,272) 90×44，工具条紧贴其上方 | 通过 |
| 不出现系统原生选择菜单 | 分页模式 `buildPagedWebViewSettings().disableContextMenu == true`（单测断言，见 `listen_page_test.dart:77`）；滚动模式 `contextMenuBuilder → SizedBox.shrink()`（既有测试绿） | 通过（非可视，见 §5） |
| 04-selection 布局零改动 | 02-design §5.3 / 03-review §4.3 声明零改动；REQ-005 diff 未触及该组件 | 通过 |

**S3 结论：通过（回归守护）。**

---

## 2. 偏差清单

| # | 屏 | 类型（少做/做错/发明） | 证据 | 判定 |
|---|---|---|---|---|
| — | — | **无** | 上述三屏全部验收点命中，未发现少做/做错/发明新交互 | — |

> **deviation 计数 = 0**（无未授权偏差）。相关 tradeoff/低风险差异见 §3，均不构成偏差。

---

## 3. 授权取舍 / 低风险差异说明（非偏差）

1. **AppBar 新增「停止」「听书设置」图标**（线框 09 顶部仅标题）。
   → 授权依据：02-design §9 关联裁定1、03-review §4.4。线框正文控制条**严格保持**「恰好含」清单，
   停止/设置移至顶部栏；不改变正文/控制条布局。
2. **控制条音色按钮文案为「🎙 系统男声/女声」**（线框写作「🎙 男声·AI」）。
   → 授权依据：02-design §5.1 明确「线框『AI』属 P2 示意」，实现显示当前系统音色。
3. **「朗读中」徽标位于正文上方左侧**（线框示意为高亮句尾右侧）。
   → 低保真线框（`docs/wireframes/README.md`：线框为低保真，最终视觉/间距/图标以实现阶段高保真为准），
   徽标位置非契约；元素存在、语义一致、可见。
4. **听书设置以底部弹层呈现（含关闭 X）**（线框为页内卡片）。
   → 移动端模态面板的自然映射；关闭按钮为 Material 标准消解 affordance，不改变设计内容与分组。
5. **P2 控件统一禁用灰置**（AI/Piper/克隆/定时/后台）。
   → 授权依据：01-req §1.2、02-design §8；线框本身即为灰置占位。
6. **后台播放/迷你播放条/系统媒体键/点读不做**。
   → 范围划界：01-req §1.2「明确不做（另立 REQ）」。

---

## 4. 结构性结论：视口方向不一致（3/3）

- **现象**：三张设计稿均为 **900×640 横屏**（桌面/平板示意），实现截图为 **1170×2532 竖屏**；
  报告脚本据此对 3 屏全部标注「⚠ 视口不一致」。
- **竖屏适配是否合理**：
  - **09 听书页**：正文（可滚动）置顶 + 控制条吸底；控制键居中、定时/音色在右竖排。所有控件 rect
    均落在 390×844 内（最大 bottom=822.5），无 RenderFlex 溢出。**合理。**
  - **10 听书设置**：740×466 横屏卡片 → 全宽可滚动底部弹层；全部内容 bottom=649 < 844。**合理。**
  - **04-selection**：工具条居中于选中区上方 (48.4,232)，竖屏可见。**合理。**
- **限制与建议**：横屏低保真稿只能校验「结构/元素有无」，无法校验横向比例/间距级视觉还原
  （如徽标位置、控制条宽高比）。若后续需要像素级视觉验收，建议**补 390×844 竖屏设计稿**。
  当前不构成放行阻塞。

---

## 5. Gap / 未覆盖说明

| 项 | 说明 | 处置 |
|---|---|---|
| US-19 分页禁原生选择菜单 | WebView 配置项，非 Flutter 层可截图的视觉差异 | 由 `listen_page_test.dart` 配置断言覆盖；真机手工验收见 03-review §5 第 1 项 |
| 真机系统 TTS 出声 / 语速即时生效 / 离线朗读 | 依赖 Android 系统语音，集成测试无法采音 | 03-review §5 真机清单 2–4 项，发布阶段记录 |
| 「⋯更多→听书」入口弹层 | 无专属线框，未纳入 manifest（避免误导对照） | 补充截图 `app/screenshots/reader_more.png`：弹层含 `阅读统计/听书/笔记/导出` 四项，`听书` 入口存在（代码 `reader_page.dart:_openMore`）；仅作入口回归证据 |

---

## 6. 结论

- **逐屏判定**：S1 通过、S2 通过、S3 通过（回归）。
- **deviation 计数 = 0**（无未授权偏差；§3 差异均为设计/ADR 已授权取舍或低保真线框的非契约示意）。
- **闸门5 前置判定：pass** —— 允许进入阶段5 delivery / release-manager 合并主线；
  **无需 rework-B**。
- 建议（非阻塞）：补竖屏设计稿以支持像素级视觉验收；真机 4 项按 03-review §5 执行。

---

## 7. 本阶段新增/修改产物

| 文件 | 变更 |
|---|---|
| `app/integration_test/screenshots_test.dart` | 新增「听书·跟读控制条」「听书设置面板」「阅读器·更多菜单（听书入口）」3 个真实渲染截图用例；补 `_listenSentences`/`_ListenShotBackend` 语料 |
| `app/screenshots/listen_player.png` | 新增（真实渲染，156,603 B） |
| `app/screenshots/listen_settings.png` | 新增（真实渲染，172,128 B） |
| `app/screenshots/reader_more.png` | 新增（入口回归，151,131 B） |
| `app/screenshots/reader_selected.png` 等 5 张 | 重新渲染（回归） |
| `workflow/backlog/REQ-005-fixes/product-preview.manifest.json` | 新增（S1/S2/S3） |
| `workflow/backlog/REQ-005-fixes/product-preview-REQ-005-fixes.html` | 新增（3 屏对照报告） |
