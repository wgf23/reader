<!-- wf-meta: req=REQ-007-reader-interaction-fixes | phase=product-preview | agent=product-reviewer | date=2026-09-09 | gate=passed -->
# REQ-007 · 阶段5a 产品验收（设计稿 ↔ 实现截图 逐屏对照）

> 视角：**产品/用户**（非开发自评）。UI 权威：`docs/wireframes/reader-ui-v2/01-immersive.svg`、
> `reader-ui-v2/02-menus.svg`、`reader-ui-v2/04-selection.svg`、`docs/wireframes/08-translation.svg`、
> `docs/wireframes/03-settings.svg`。
> 截图来源：**真实引擎渲染**（`bash scripts/ui-screenshots.sh REQ-007` →
> `xvfb-run flutter test integration_test/screenshots_test.dart -d linux` + `RepaintBoundary.toImage`，
> 真实字体/资源；**非** `app/test/goldens` 的 widget Ahem 方块占位）。
> 报告：`product-preview-REQ-007-reader-interaction-fixes.html`（5 屏 · 视口不一致 5 · 无实现截图 0）。
>
> **核对方法**：本轮为纯文本环境（模型无图像直读），逐屏判定基于**真实渲染 PNG 的像素/几何分析**
> （纯 PIL：颜色聚类 + 颜色 bbox + 行/列带探针，均为真实引擎输出），并交叉引用真实渲染集成测试与
> widget/单测断言（`reader_interaction_test.dart`、`screenshots_test.dart`、`no_synthetic_chrome_test.dart`、
> `translate_reader_test.dart`、`reader_page_test.dart`）。证据均为可复算坐标/像素，非开发口述。

---

## 1. 对照方法

1. **真实截图**：`bash scripts/ui-screenshots.sh REQ-007` **退出码 0**，12 张截图全部更新
   （`SAVED_SCREENSHOT` 12 次，`All tests passed!`）。本 REQ 取 5 屏对照。
2. **像素/几何证据**：对每张 PNG 做行带非白检测、颜色 bbox 探针，定位顶/底栏、进度条滑块、
   工具条色点、卡片分带、来源标签/回退提示、设置页控件。
3. **行为型验收交叉引用**：中部点击呼出/隐藏、下一章、去设置跳转等由**真实 `ReaderPage` + 真实
   `tapAt`/`longPress`/`drag`** 的集成测试断言，非截图静态观感。
4. **判定口径**：设计意图/验收点命中 → 通过；**设计已授权取舍**（02-design §5/§8、ADR 降级线）→
   记 tradeoff，不计偏差；少做 / 做错 / 发明新交互 → 偏差 → rework-B。

---

## 2. 逐屏对照表

### S1 阅读器 · 沉浸态（线框 `reader-ui-v2/01-immersive.svg`）

- 设计稿：900×640 横屏；实现截图：`app/screenshots/reader_immersive.png`（1170×2532 竖屏，逻辑 390×844）

| 设计意图 / 验收点 | 实现证据（真实渲染像素/几何） | 判定 |
|---|---|---|
| 沉浸态无常驻顶/底栏 | 全图行带**非白检测为空**（`non-white bands = []`）：无 52px 顶栏带、无 56px 底栏带；主色像素 `#6750A4 = 0` | 通过 |
| 正文全屏铺满 | 全高（逻辑 0–844）近白底 + 深色文字带贯穿，无 chrome 遮挡 | 通过 |
| 中部点击（含点在正文文字上）可呼出 | 截图本身为沉浸态；呼出由 S2 截图 + 集成测试 US-1 断言（真实 `tapAt(getCenter(find.text(正文)))`） | 通过 |
| 左右 15% 边缘热区语义保留 | 由 `reader_page_test.dart:352-375`（注入 fake controls，左/右边缘点击翻页且 `返回书架` findsNothing）覆盖 | 通过 |
| 长按选中仍出工具条 | 见 S3 | 通过 |

**S1 结论：通过。** 沉浸态真实无 Chrome，正文全屏。

### S2 阅读器 · 呼出顶底栏（线框 `reader-ui-v2/02-menus.svg`）—— REQ-007 核心修复

- 设计稿：900×640 横屏；实现截图：`app/screenshots/reader_chrome.png`（1170×2532 竖屏）

| 设计意图 / 验收点 | 实现证据（真实渲染像素/几何） | 判定 |
|---|---|---|
| **真实点击正文文字呼出（非合成页）** | `screenshots_test.dart:149-155`：真实 `ReaderPage` + `tester.tapAt(tester.getCenter(find.text(_readerText)))`；`no_synthetic_chrome_test.dart` 静态守卫 `integration_test/*.dart` 禁 `ReaderTopBar(`/`ReaderBottomBar(`。像素证据：顶栏带逻辑 y0–52、底栏带逻辑 y788–844 均出现（沉浸态 S1 无此二带） | 通过 |
| 顶栏：← 返回 / 书名·章节 / ⋯ 更多 | 顶栏非白带物理 y0–155（逻辑 y0–52，恰为 `ReaderTopBar` height 52，底色 `#ECEEF1`）；暗字分布 逻辑 x0–43（返回箭头）、x173–216（居中书名/章节）、x346–390（右侧更多图标） | 通过 |
| 底栏：上一章 / ☰目录 / 可拖进度条 / 书签 / Aa / 下一章 | 底栏非白带物理 y2364–2531（逻辑 y788–844，底色 `#ECEEF1`）；进度条滑块主色 bbox 逻辑 (128,810,140,822)；暗字分布 逻辑 x43–130（上一章+目录）、x173–216（百分比）、x216–303（书签+Aa 粗体） | 通过 |
| **底栏『下一章』存在** | 底栏最右逻辑 x303–390 检出 894 个非底色像素（物理 x996–1119，逻辑 332–373），为 `下一章` 文本簇；同一 harness 集成测试 US-1 断言 `find.text('下一章')` findsOneWidget | 通过 |
| **底栏『下一章』可用** | `reader_interaction_test.dart:148-161`（US-4）：真实 `ReaderPage` 两章 backend，点文字呼出 → `tap(find.text('下一章'))` → `find.text(_ch2Text)` findsOneWidget 且 `backend.saved?.href == 'chapter_0002.xhtml'` | 通过（见 §4 fixture 说明） |
| 无自创布局（控件集合与线框一致） | 顶/底栏控件集合与 `02-menus.svg` 逐项对应；`reader_chrome.dart` 布局零改动（03-review §1.4） | 通过 |

**S2 结论：通过。** 顶底栏由真实点击正文文字呼出，控件齐全，下一章能力由集成测试证实。

### S3 阅读器 · 长按选词工具条（线框 `reader-ui-v2/04-selection.svg`）

- 设计稿：900×640 横屏；实现截图：`app/screenshots/reader_selected.png`（1170×2532 竖屏）

| 设计意图 / 验收点 | 实现证据（真实渲染像素/几何） | 判定 |
|---|---|---|
| 自定义工具条出现且**五入口齐全** | 检出「笔记」按钮独有的 4 个色点：黄 `#FBC02D` / 蓝 `#1A73E8` / 绿 `#43A047` / 粉 `#E91E63`，各 ~160 px，bbox 逻辑 y272–277、x145–174 连排 → 工具条已渲染；`selection_toolbar.dart:26-30` 恰为 `划重点/笔记/翻译/查词/复制` 5 项 | 通过 |
| 无系统原生 ActionMode/工具条 | REQ-005 既有配置断言（分页 `disableContextMenu`、滚动 `contextMenuBuilder → SizedBox.shrink()`）回归绿；集成测试 `find.byType(ReaderSelectionToolbar)` findsOneWidget | 通过 |
| 选中文本有高亮 | 截图检出选中浅蓝覆盖带（物理 y873–880 为主带）；`longPressAt(200,300)` 真实长按手势产生 | 通过 |
| 翻译/查词入口仍可复用（REQ-003 通路零回退） | 工具条 5 入口零改动；`translate_reader_test.dart` 翻译/查词用例全绿 | 通过 |

**S3 结论：通过（工具条零改动回归）。**

### S4 翻译浮层 · 译文卡片来源标签（线框 `08-translation.svg`）

- 设计稿：900×640 横屏；实现截图：`app/screenshots/translation_cards.png`（1170×2532 竖屏，同屏 4 卡）

| 设计意图 / 验收点 | 实现证据（真实渲染像素/几何） | 判定 |
|---|---|---|
| 『在线』+ provider=deepl | 4 张卡片分带 逻辑 y20–140 / 146–266 / 272–396 / 402–544；卡片 1 provider 名主色簇（见下）；`translate_reader_test.dart:342-364` 断言 `在线`+`deepl` | 通过 |
| 『离线』+ provider=offline | 卡片 2 provider 名主色簇；`translate_reader_test.dart:230-234` 断言 `离线`+`offline` 且 `在线` findsNothing | 通过 |
| 『缓存』标签（fromCache=true） | 检出 `secondaryContainer` 缓存徽标底 `#E8DEF8`（物理 n≈18894，覆盖卡片 3 标签位）；`translate_reader_test.dart:238-240` 断言 `缓存`+`deepl` | 通过 |
| provider 名正确（deepl / offline） | 主色 `#6750A4` provider 名簇 n=2220，bbox 逻辑 x321–357、y35–426，右对齐贯穿 4 卡（4 处 provider 名） | 通过 |
| 回退提示『在线失败，已回退离线』 | 错误色 `#B3261E` 文本簇 n=1727，bbox 逻辑 (33,517)–(146,527) ＝ 卡片 4 回退提示行 | 通过 |
| 译文正文 + 标签行布局不变 | `translation_popup.dart` 标签映射逻辑未动（REQ-006 已实现）；本 REQ 仅 core 文案追加 | 通过 |

**S4 结论：通过。** 在线/离线/缓存三标签 + provider 名 + 回退提示均在真实渲染中命中。

### S5 设置页 · 词典与翻译（线框 `03-settings.svg`）——『去设置』目标页

- 设计稿：900×640 横屏；实现截图：`app/screenshots/settings_translate.png`（1170×2532 竖屏）

| 设计意图 / 验收点 | 实现证据（真实渲染像素/几何） | 判定 |
|---|---|---|
| 『翻译策略』下拉可见 | `screenshots_test.dart:330` 断言 `find.text('翻译策略')` findsOneWidget；截图检出主色控件簇 n=65602，bbox 逻辑 (16,112)–(374,368) | 通过 |
| 当前策略『自动（在线优先）』 | `screenshots_test.dart:331` 断言 `find.text('自动（在线优先）')` findsOneWidget | 通过 |
| 『DeepL API Key』输入框可见 | 设置页「词典与翻译」区块既有控件（REQ-006）；`settings_page_test.dart` 覆盖 | 通过 |
| 已配置 key 时掩码回填（无明文） | `settings_page_test.dart:84-91,135` 断言 `controller.text == '••••••••'`；`getConfig` 只回传掩码 | 通过 |
| 无新增页面 / 未改导航（页面零改动） | `SettingsPage` 本 REQ 零改动；作为 `去设置` push 目标被复用 | 通过 |

**S5 结论：通过。** 设置页零改动，作为『去设置』目标页可达（R3-3 入口打通）。

---

## 3. 偏差清单

| # | 屏 | 类型（少做/做错/发明） | 证据 | 判定 |
|---|---|---|---|---|
| — | — | **无** | 上述 5 屏全部验收点命中；未发现少做 / 做错 / 发明新交互 | — |

> **deviation 计数 = 0**（无未授权偏差）。相关 tradeoff / 结构性差异见 §4、§5，均不构成偏差。

---

## 4. REQ-007 专属产品核验

| 核验项 | 结论 | 证据 |
|---|---|---|
| `reader_chrome.png` 是否为**真实点击正文文字**呼出（非合成页） | **是** | `screenshots_test.dart:154` 真实 `tapAt(getCenter(find.text(_readerText)))`；`no_synthetic_chrome_test.dart` 静态守卫禁合成 `ReaderTopBar(`/`ReaderBottomBar(`；像素证据见 S2 |
| 底栏『下一章』存在且可用 | **是** | 存在：S2 像素检出最右文本簇 + US-1 断言；可用：US-4 集成测试真实点击 → 第二章文本 + `saved.href='chapter_0002.xhtml'` |
| `reader_selected.png` 工具条 **5 入口齐全** | **是** | 「笔记」色点签名（4 色点）像素检出；`selection_toolbar.dart:26-30` 5 项；集成测试 US-2 |
| `translation_cards.png` 来源标签 + provider 名正确 | **是** | 在线/deepl、离线/offline、缓存徽标、回退提示像素检出；widget 测试 US-18/US-13 断言 |
| 错误浮层『去设置』**仅在翻译未配置时出现** | **是** | `translate_reader_test.dart:280-315`：翻译失败 → `find.text('去设置')` findsOneWidget + 点击进 `SettingsPage` 且透传同一 backend；`:318-339` 查词失败 → `find.text('去设置')` findsNothing；集成测试 US-12 真实长按→翻译→去设置全绿 |

**fixture 说明（非偏差）**：`reader_chrome.png` 所用截图 backend `_LongFakeBackend` 只含 **1 章**，
故该图中『下一章』按钮呈禁用灰（`chapterIndex < chapterCount-1` 为 false）。这是**截图数据 fixture
限制**，不是功能缺陷：同一交互在 US-4 用两章 backend 验证了按钮启用并成功切章。已在 S2 验收点区分
「存在（截图）」与「可用（集成测试）」。

---

## 5. 授权取舍 / 结构性差异（非偏差）

1. **视口方向不一致（5/5）**：设计稿全为 **900×640 横屏**（桌面/平板示意），实现截图为
   **1170×2532 竖屏**（逻辑 390×844）；报告脚本对 5 屏全标注「⚠ 视口不一致」。REQ-007 **不改布局**
   （仅修手势可达性 + 错误浮层新增一个按钮），横屏稿在竖屏下逐项映射为：沉浸态正文全屏、
   顶/底栏吸顶/吸底、工具条浮动于选区上方、翻译卡片纵向堆叠、设置页单列。**属 REQ-004/005/006 已确认
   并授权沿用的结构性取舍，不重复计偏差。**
2. **错误浮层『去设置』按钮（唯一 UI 增量）**：02-design §5/§8 + ADR 关联裁定明确授权——仅在翻译
   未配置时渲染，查词/网络错误不渲染；未改变工具条/卡片/顶底栏/设置页布局。**授权取舍，不计偏差。**
3. **截图 harness 用默认 M3 主题（主色 `#6750A4`）**：`integration_test._pack` 自建 `MaterialApp`，
   不加载 `main.dart` 的 indigo 种子色。仅影响强调色相，不影响布局/控件/文案；为既有截图 harness
   已知限制（REQ-005/006 同款）。**非实现偏差。**
4. **分页路径 Linux 不可实跑**：`flutter_inappwebview` 无 Linux 实现，分页重载/JS 解析/翻页决策由
   单测（US-6/7/8）+ widget（US-5/9）覆盖，真机由 US-17 清单兜底（03-review §5）。**平台约束，非偏差。**

---

## 6. Gap / 未覆盖说明

| 项 | 说明 | 处置 |
|---|---|---|
| 错误浮层『去设置』态截图 | 5 屏清单聚焦布局与来源标签；错误态未单截图 | 由 `translate_reader_test.dart:280-315`（去设置出现/跳转/透传）+ `:318-339`（查词无去设置）+ 集成 US-12 覆盖，非 gap |
| Android 分页翻页/切章/去设置 | 依赖真机 WebView，CI 不可自动化 | `03-review.md §4` 真机手工清单 ①–⑤，发布阶段执行 |
| 分页禁原生选择菜单 | WebView 配置项，Flutter 层不可截图 | REQ-005 既有配置断言覆盖 |

> 5 屏均有真实实现截图，**gap = 0**（报告「无实现截图 0」）。

---

## 7. 结论

- **逐屏判定**：S1 通过、S2 通过、S3 通过、S4 通过、S5 通过。
- **deviation 计数 = 0**（无未授权偏差；§5 差异均为设计/ADR 已授权取舍、既有 harness/平台约束或
  视口适配的结构性差异）。
- **闸门5 前置判定：pass** —— 允许进入阶段5 delivery / release-manager 合并主线；**无需 rework-B**。
- 建议（非阻塞）：补 390×844 竖屏设计稿以支持像素级视觉验收；真机清单 ①–⑤ 按 `03-review.md §4` 执行。

---

## 8. 本阶段产物

| 文件 | 变更 |
|---|---|
| `workflow/backlog/REQ-007-reader-interaction-fixes/product-preview.manifest.json` | 新增（S1–S5，impl 指向真实渲染截图） |
| `workflow/backlog/REQ-007-reader-interaction-fixes/product-preview-REQ-007-reader-interaction-fixes.html` | 新增（5 屏对照报告，视口不一致 5，gap 0） |
| `app/screenshots/*.png` | 由 `ui-screenshots.sh REQ-007` 重新渲染（12 张，真实引擎输出） |
| `workflow/backlog/REQ-007-reader-interaction-fixes/05b-product-preview.md` | 本文件 |
