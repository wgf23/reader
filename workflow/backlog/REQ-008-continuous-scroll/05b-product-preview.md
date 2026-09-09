<!-- wf-meta: req=REQ-008-continuous-scroll | phase=product-preview | agent=product-reviewer | date=2026-09-09 | gate=passed -->
# REQ-008-continuous-scroll · 阶段5a 产品验收（设计稿 ↔ 真实渲染截图 对照）

> **视角**：产品/用户（非开发自评）。UI 权威：`docs/wireframes/reader-ui-v2/01-immersive.svg`、
> `reader-ui-v2/02-menus.svg`（900×640 横屏低保真）。
> **截图来源**：**真实引擎渲染**（`xvfb-run flutter test integration_test/screenshots_test.dart -d linux`
> + `RepaintBoundary.toImage(pixelRatio:3.0)`，真实字体/真实 `ReaderPage`），**未使用**
> `app/test/goldens/*.png`（widget 测试 Ahem 方块占位，不可作实现效果）。
>
> **采集命令**：`bash scripts/ui-screenshots.sh REQ-008`
> **采集结果**：**退出码 0**；`screenshots_test.dart` **13 passed / 0 failed**（13 张真实截图）；
> 报告 `product-preview-REQ-008-continuous-scroll.html`（3 屏，1,235,079 B；总屏数 3 / 视口不一致 3 /
> 无实现截图 0；内嵌 3 张 SVG + 3 张 base64 PNG）。
>
> **判定方法说明**：本轮评审为纯文本环境（无法直读图像），故逐屏判定基于**真实渲染 PNG 的像素/几何
> 分析**（行/列墨迹聚类、文本行高与行距、色彩饱和度统计、全宽控件簇），证据均为可复算坐标；
> 并交叉引用真实集成测试（本阶段独立复跑）与 `reader_chrome.dart` 对 `main` 的零 diff。
> 所有证据来自真实引擎输出，非开发口述。

---

## 0. 独立复核命令（本阶段实跑）

| # | 命令 | 结果 |
|---|---|---|
| 1 | `bash scripts/ui-screenshots.sh REQ-008` | **退出码 0**；cargo build → 集成截图 → 报告生成；13 张截图；报告 3 屏 |
| 2 | `xvfb-run -a flutter test integration_test/reader_continuous_scroll_test.dart -d linux` | **5 passed / 0 failed**（US-1/2/3/4/8，真实 `ReaderPage`+真实 `drag`/`fling`） |
| 3 | `flutter test test/no_synthetic_chrome_test.dart` | **1 passed**（`integration_test/*.dart` 禁合成 `ReaderTopBar(`/`ReaderBottomBar(`） |
| 4 | `git diff --stat main -- app/lib/widgets/reader_chrome.dart` | **空**（顶/底栏零改动） |
| 5 | `git diff --stat main -- app/lib/` | 仅 `continuous_scroll_policy.dart`(+228)、`progress_saver.dart`(+65)、`reader_page.dart`(±359) 三个文件 |

截图文件（本阶段重渲染）：`reader_immersive.png` 133,890 B / `reader_chrome.png` 151,409 B /
`reader_continuous_scroll_chapter2.png` 627,089 B；尺寸均 **1170×2532**（逻辑 390×844，DPR 3.0）。

---

## 1. 逐屏对照表

### S1 阅读器 · 沉浸态（连续流）—— 线框 `01-immersive.svg`

- 设计稿：`reader-ui-v2/01-immersive.svg`（900×640 横屏）
- 实现截图：`app/screenshots/reader_immersive.png`（1170×2532 竖屏，真实 `ReaderPage` 首屏）

| 设计意图 / 验收点 | 实现证据（真实渲染像素分析） | 判定 |
|---|---|---|
| 沉浸态**无任何常驻 Chrome**（无 AppBar/底栏） | 全图无 `reader_chrome` 式顶/底全宽控件簇；文本行从 y=84 直接开始，底部无控件带 | 通过 |
| 正文全屏铺满视口，单章排版与改版前一致 | 9 个文本行带；章标题 1 带 + 正文 8 带；左右墨迹边界 L=73 / R=116（逻辑 ≈24px 页边距，与 `SliverPadding(24,…)` 一致）；正文按段落自然换行（`\n\n` 处行距 150 vs 普通 44 device px） | 通过 |
| **无新增控件/颜色/字号**（连续流不引入新视觉元素） | 全图 **colorful（饱和度>30）像素 = 0**；仅深灰文字 `rgb(32,33,36)` + 白底（95.45%）；无按钮/图标/色块 | 通过 |
| 中部 1/3 点击 / 左右 15% 边缘 / 长按选中语义保留 | 热区为不可见命中区（线框虚线为标注非控件）；`body_tap_policy.dart` 零改动（git diff 未触及），`SelectionArea` 外层仍在 | 通过 |
| 单章 golden 零 diff | 03-review §3 #8：`screenshot_golden_test.dart` 5 passed，4 张既有 golden **零 diff**（未更新） | 通过 |

**S1 结论：通过。** 沉浸态无 Chrome、无新增视觉元素、单章排版不变。

---

### S2 阅读器 · 呼出顶底栏 —— 线框 `02-menus.svg`

- 设计稿：`reader-ui-v2/02-menus.svg`（900×640 横屏）
- 实现截图：`app/screenshots/reader_chrome.png`（真实点击正文文字 center 呼出，非合成页）

| 设计意图 / 验收点 | 实现证据（真实渲染像素分析） | 判定 |
|---|---|---|
| 顶栏：← 返回 / 书名·章节名 / ⋯ 更多 | 顶栏带 y=33..99，3 个墨迹簇：x=37..83（返回图标）/ x=516..650（书名+章节，居中）/ x=1086..1133（更多图标） | 通过 |
| 底栏：上一章 · ☰目录 · 可拖进度条 · 书签 · Aa · 下一章 | 底栏带 y=2421..2474，7 个墨迹簇自左至右：x=49..172（上一章）/ 238..303（目录图标）/ 384..422（进度条滑块，progress=0 居左）/ 615..668（0% 文本）/ 710..751（书签描边图标）/ 844..902（Aa）/ 996..1119（下一章）——**与 `reader_chrome.dart` 的 7 个元素逐一对齐** | 通过 |
| 章节名/进度条反映当前可见章 | 单章语料（`_LongFakeBackend`，1 章）→ 顶栏章节名 = 该章、进度 0%；跨章切换由 widget US-5 与集成 US-1/US-3 断言（本 REQ 集成 5/5 绿） | 通过 |
| **布局零改动**（控件集合/位置/尺寸不变） | `git diff --stat main -- app/lib/widgets/reader_chrome.dart` **为空**；控件集合/顺序/尺寸由页面传入数据驱动 | 通过 |
| 无自创布局 | 无超出线框清单的控件；无新面板/新入口 | 通过 |

> 说明：本截图语料仅 1 章，故底栏「上一章/下一章」呈**禁用态**（`chapterIndex>0` / `chapterIndex<count-1`
> 不满足，`onPressed==null`）——这是既有语义的正确表现，非缺陷；两按钮仍按线框位置常驻可见。

**S2 结论：通过。** 顶底栏控件齐全、位置/尺寸零改动，仅数据随可见章刷新。

---

### S3 阅读器 · 连续滚动到第二章（**REQ-008 核心**）—— 线框 `01-immersive.svg`

- 设计稿：`reader-ui-v2/01-immersive.svg`（连续滚动沿用同一正文排版）
- 实现截图：`app/screenshots/reader_continuous_scroll_chapter2.png`（真实 `ReaderPage` + 真实 `drag`
  连续滚过第一章后截取；**未点击「下一章」**，`screenshots_test.dart:195-206`）

| 设计意图 / 验收点 | 实现证据（真实渲染像素分析） | 判定 |
|---|---|---|
| 第一章**正文/底部**与第二章**标题/正文**处于**同一连续滚动流** | 见 §2 行带表：y=0..1974 共 21 个正文行带（第一章尾部，顶部被视口裁切）→ **章间距** → y=2106..2158 标题带 → y=2242..2485 共 3 个正文行带（第二章正文） | 通过 |
| 第二章标题随滚动进入视口，**无需点「下一章」** | 标题带 y=2106..2158（逻辑 702..719）落在 390×844 视口内；截图过程仅 `tester.drag`，无任何 tap；集成 US-1 断言 `find.text('第二章')`+正文 `findsOneWidget` 且 `find.text('返回书架') findsNothing`（Chrome 仍隐藏，证明非按钮触发） | 通过 |
| 章间距 32px（唯一行为性增量） | 章间墨迹空隙 = 131 device px（逻辑 ≈43.7px），普通行距空隙 = 44 device px（逻辑 ≈14.7px），**章间比普通行距多 ≈29 逻辑 px**，与 `Padding(bottom: 32)`（02-design §5 / ADR 关联裁定1）一致（差额由标题行盒 leading 解释） | 通过 |
| **无新增控件/颜色/字号** | 全图 **colorful 像素 = 0**；文字色 `rgb(32,33,36)` 与 S1 一致；无按钮/图标/色块/进度条；页边距 L=72（逻辑 24）与 S1 一致 | 通过 |
| 连续滚动由**真实集成测试**验证（非合成页） | `no_synthetic_chrome_test` 1 passed；本阶段独立复跑 `reader_continuous_scroll_test` **5/5 passed**（US-1 真实 drag 到第二章；US-2 末章不越界；US-3 可见章 href/progression；US-4 跨章恢复；US-8 听书返回） | 通过 |
| 末章自然停止 / 恢复位置 / 听读同进度 | 集成 US-2（`pixels==maxScrollExtent` 容差、`takeException()==null`、无第 4 章）、US-4（重开落到第二章区间）、US-8（听书写入后定位一致）均 passed | 通过 |

**S3 结论：通过（本 REQ 核心验收达成）。**

---

## 2. S3 证据强度专项（核心：是否足以证明「连续无缝」）

**结论：足以证明「连续无缝」，而非仅证明「第二章已构建」。** 依据是同一视口内同时出现
**第一章正文尾部 + 第二章标题 + 第二章正文**，且三者间只有章间距、无分页/新控件/新面板。

真实渲染行带表（device px / ÷3 = 逻辑 px；视口 1170×2532）：

| 行带 | device y | 逻辑 y | 归属（结构推断） | 行距空隙 |
|---|---|---|---|---|
| band00–19 | 0..1879 | 0..626 | **第一章正文尾部**（顶部被裁切，连续 20 行，行距 44） | 普通 44 |
| band20 | 1924..1974 | 641..658 | 第一章**最后一行**（墨迹 4926，短行） | 44 |
| band21 | 2106..2158 | **702..719** | **第二章标题**（墨迹 5615；前空隙 131=章间距，后空隙 83=标题后 `SizedBox(16)`） | 131（章间距） |
| band22–24 | 2242..2485 | 747..828 | **第二章正文**（3 行；`_continuousCh2` 49 字 ÷ ≈19 字/行 ≈ 3 行，吻合） | 83 / 44 / 44 |

- **连续性**：band00–20 与 band21–24 属同一滚动列表、同一视口，中间只有 131 device px（章间距），
  无整屏空白/分页符/新控件带 → 第一章末与第二章首在同一连续流中。
- **非合成页**：`screenshots_test.dart` 使用真实 `ReaderPage` + `_ContinuousScrollShotBackend`（2 章语料），
  仅 `tester.drag` 滚到标题可见，无 `ReaderTopBar(`/`ReaderBottomBar(` 构造（守卫绿）。
- **非点击「下一章」**：全程无 tap；集成 US-1 额外断言 Chrome 隐藏（`返回书架` findsNothing）。
- **章节结构吻合**：第二章正文仅 3 行，与短文本语料一致；若为「合成/占位页」不会出现第一章 21 行尾随正文。
- **补充证据要求（非阻塞）**：S3 是**第二章入口瞬间**的静态帧，不能单独证明「末章停止/恢复位置/听读同进度」；
  这三项由集成 US-2/US-4/US-8（本阶段 5/5 复跑通过）+ 真机 US-13 承担，报告不将静态帧当唯一证据。

---

## 3. 偏差清单

| # | 屏 | 类型（少做 / 做错 / 发明） | 证据 | 判定 |
|---|---|---|---|---|
| — | — | **无** | S1/S2/S3 全部验收点命中；无少做、无做错、无发明新交互/新控件/新颜色/新字号 | — |

> **deviation 计数 = 0**（无未授权偏差）。相关差异均为设计/ADR 已授权取舍或既有基线，见 §4。

---

## 4. 授权取舍 / 低风险差异说明（**非偏差，不计入 deviation**）

1. **视口方向不一致（3/3）**：设计稿 **900×640 横屏**（桌面/平板低保真示意），实现 **390×844 竖屏**
   真机。→ **授权依据**：REQ-004/005/006/007 已沿用的既有 tradeoff（`02-design §12`/ADR 降级线口径），
   且本 REQ `02-design §5` 明确「零新增控件/颜色/字号」；报告脚本自动标注「⚠ 视口不一致」，不构成放行阻塞。
2. **章间距 32px**：连续多章的排版必然结果，复用正文留白节奏，**非新增 UI 元素**。→ 授权依据：
   `02-design §5`、`02-adr 关联裁定1`；本报告按「无新增控件/颜色/字号、控件集合与 02-menus 一致」判定。
3. **顶底栏强调色为 Material 3 紫 `rgb(103,80,164)`**（S2 中 1031 colorful px），线框示意为蓝 `#1A73E8`。
   → 既有 App 主题（`reader_chrome.dart` 对 `main` **零 diff**，REQ-004 起即如此），**非本 REQ 引入**；
   不属 REQ-008 偏差。竖屏真机下控件集合/位置与线框一致。
4. **S2 底栏「上一章/下一章」禁用态**：截图语料仅 1 章，两按钮按既有语义置灰（`onPressed==null`），
   位置常驻。→ 非缺陷，跨章启用由集成 US-2/US-7 覆盖。
5. **行距重排的 Flutter 框架 debug 断言**（03-review §4.5）：`SelectionArea` + `CustomScrollView` +
   `RenderParagraph.getBoxesForSelection` 的框架级交互，仅 debug 断言、release 不受影响；已由
   「改主题」等价路径 + 真机 US-13⑥ 兜底。→ 非本 REQ 产品级缺陷，登记为真机确认项。

---

## 5. 结构性结论：视口方向不一致（3/3）

- **现象**：3 张设计稿均为 900×640 横屏，实现截图为 1170×2532 竖屏；脚本对 3 屏全部标注「⚠ 视口不一致」。
- **竖屏适配是否合理**：
  - **01-immersive**：正文全屏 + 不可见热区，竖屏下页边距 24px、行距正常，控件为 0 个。**合理。**
  - **02-menus**：顶栏 3 元素、底栏 7 元素全部落在 390 宽内（最右簇逻辑 332..373 < 386），无溢出。**合理。**
  - **01-immersive（S3 连续流）**：章标题/正文在竖屏同一列流中自然衔接，无横向挤压。**合理。**
- **限制与建议**：横屏低保真稿只能校验「结构/元素有无/行为」，无法校验横向比例/间距级视觉还原。
  若后续需像素级视觉验收，建议补 **390×844 竖屏设计稿**。当前**不构成放行阻塞**。

---

## 6. Gap / 未覆盖说明

| 项 | 说明 | 处置 |
|---|---|---|
| 末章停止 / 跨章恢复 / 听读同进度 | 静态帧无法覆盖动态行为 | 集成 US-2/US-4/US-8（本阶段 5/5 复跑绿）+ 真机 US-13①–④ |
| 分页模式章末续章 | `flutter_inappwebview` 无 Linux 实现，集成不可跑 | widget 回归 US-9 + 真机 US-13⑤（REQ-007 已交付，本 REQ 仅守） |
| 字号/行距/主题重排后锚定 | debug 断言见 §4.5 | 真机 US-13⑥ 人工确认 |
| 真机字体/系统渲染差异 | 集成渲染为 Linux 桌面真实字体，非 Android 系统字体 | 真机 US-13 人工清单 |

---

## 7. 结论

- **逐屏判定**：S1 **通过**、S2 **通过**、S3 **通过**（本 REQ 核心）。
- **deviation 计数 = 0**（无未授权偏差；§4 差异均为设计/ADR 已授权取舍或既有基线）。
- **S3 证据强度**：真实渲染帧同时呈现「第一章正文尾部 + 第二章标题 + 第二章正文」，中间仅 32px 章间距，
  0 colorful 像素、无新增控件 → **足以证明连续无缝**（非仅「第二章已构建」）；动态边界由集成 5/5 + 真机兜底。
- **闸门5 前置判定：pass** —— 允许进入阶段5b delivery / release-manager 合并主线；**无需 rework-B**。
- 建议（非阻塞）：补 390×844 竖屏设计稿以支持像素级视觉验收；真机按 `03-review §5` US-13 清单执行。

---

## 8. 本阶段产物

| 文件 | 变更 |
|---|---|
| `workflow/backlog/REQ-008-continuous-scroll/05b-product-preview.md` | 新增（本报告） |
| `workflow/backlog/REQ-008-continuous-scroll/product-preview-REQ-008-continuous-scroll.html` | 重新生成（`ui-screenshots.sh REQ-008`，3 屏，1,235,079 B） |
| `app/screenshots/{reader_immersive,reader_chrome,reader_continuous_scroll_chapter2}.png` | 重新真实渲染（构建产物） |

> 未改动代码 / `STATE.md` / `01-04` 产物 / `product-preview.manifest.json`（清单沿用开发阶段 T-008）。
