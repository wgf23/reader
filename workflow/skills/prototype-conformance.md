# Skill · prototype-conformance（UI 原型一致性）

## 目的
涉及 UI 的 REQ，实现必须与**交互原型图**逐屏一致。原型图（`docs/wireframes/**`）是 UI 交互的**权威规范**，禁止自创布局。

## 步骤
1. 从 `01-req.md` / `02-design.md` 找出该 REQ 绑定的原型图（`docs/wireframes/**` 下，如 `reader-ui-v2/01-immersive.svg`…）。
2. orchestrator **逐屏对照**：每个原型图的布局/热区/控件/交互 与产物实现比对。
3. 列**偏差清单**（少做 / 做错 / 发明新交互），每项判定：
   - 是**设计已授权取舍**（02-design §12 / ADR 降级线）→ 记 tradeoff，不算偏差；
   - 否则 → **rework-B**（回架构/UI 设计修正设计或原型）。
4. 复用 golden 截图（`app/test/goldens/*.png`，手机尺寸）辅助核对布局。

## 验收
`deviation = 0`（无未授权偏差）；涉及 UI 的 REQ 才强制本 skill。

## 已固化教训
> REQ-001 曾违反自己产出的线框。因此凡页面 REQ，前置审查必须逐屏对照原型图，禁止自由发挥。
