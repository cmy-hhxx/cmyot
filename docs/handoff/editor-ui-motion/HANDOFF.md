# HANDOFF — <任务名>

> **谁改哪一节**：§1 §2 §3 §6 由 Opus（P1）写；§4 的状态列和 §5 由 DeepSeek（P2）改；§5 的「Opus 裁决」列由 Opus（P3）填。
> 除了这些，谁都不许改这份文件。

## 1. 状态（Opus 写，P2 / P3 更新门状态）

- 模式：Full / Lite
- 当前阶段：P1 / P2 / P3 / 交付
- 下一步是谁：Opus / DeepSeek / 人
- baseline tag：`baseline/<slug>`
- 门状态：G0 ✅ / G1 ✅（零 console error · 3 视口 ✅ · 主视效两帧有差 ✅ · reduced-motion ✅）
- 已跑通命令：`<install / dev / build / typecheck>`
- Opus 花费：`$X.XX`（来源：CC Switch 用量面板）

## 2. 已完成的决定（不要推翻）

| 决定 | 为什么 | 推翻的代价 |
|---|---|---|
| <例：动效用 CSS transition 而非 GSAP> | <体积 / 依赖> | 全部动效重写 |
| | | |

## 3. FROZEN（DeepSeek 不得修改）

> 明确到文件或选择器，**每一项都要写为什么**。需要动就记 NEEDS-OPUS。

| 路径 / 选择器 | 为什么不能动 |
|---|---|
| `src/styles/tokens.css` | 令牌是唯一真相，改一个值全站漂移 |
| `src/components/HeroCard.tsx` 的 svg 内部结构 | 内部两个 group 分别做 0.3x / 1x 视差 |
| `#parallax-bg` 的 transform 层级 | 与滚动 hook 耦合，改了视差断 |

## 4. TODO（有序，一次一条）

> 状态只能由 DeepSeek 改：`todo` → `doing` → `done` / `blocked` / `NEEDS-OPUS` / `dropped`。
> 同一时刻只允许一条是 `doing`。DeepSeek 只做第一条 `todo`。
> 标 `NEEDS-OPUS` 时，必须在 §5 加一行；P3 裁决后执行：做了改 `done`，不做改 `dropped`。
> 交付（G3）前不允许有 `doing`。

| ID | 目标 | 文件 | 验收 | 预估 | 状态 |
|---|---|---|---|---|---|
| T01 | 按 HeroCard 复制出 StatTile | `src/components/StatTile.tsx` | 1450 视口截图三列排布正确 | S | todo |
| T02 | 列表入场交错 | `src/pages/List.tsx` | 截图两帧字节不同 + 交错 60ms | M | todo |
| T03 | 移动端断点收敛 | `src/styles/responsive.css` | 390 视口无横向滚动 | S | todo |

## 5. NEEDS-OPUS（不要自己去猜）

> DeepSeek 只填前三列（第 3 列写你临时采用的假设）；「Opus 裁决」由 P3 填，要给出**具体值**，不要给方向。

| 位置 | 我卡在 | DeepSeek 的假设 | Opus 裁决 |
|---|---|---|---|
| | | | |

## 6. 禁止的简化（含原因）

- <同 DESIGN.md 第 7 节，交接时强调一遍>

## 7. 度量（任务结束后由人补一行）

| 日期 | Opus 花费 | Opus 代码占比 | NEEDS-OPUS 数 | POLISH 条数 | 首轮通过 |
|---|---|---|---|---|---|
| | | | | | |
