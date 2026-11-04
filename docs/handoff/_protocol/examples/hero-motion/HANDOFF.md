# HANDOFF — hero-motion（示例）

> 演示 P2 期间的状态长什么样。真实使用时，P1 结束时这份文件由 Opus 写好，P2 由 DeepSeek 逐条更新。

## 1. 状态

- 模式：Full
- 当前阶段：P2
- 下一步是谁：DeepSeek（做完 T03~T06 后交 Opus 做 P3）
- baseline tag：`baseline/hero-motion`
- 门状态：G0 ✅ / G1 ✅（零 console error · 1440/834/390 截图 ✅ · M01+M03 两帧有差 ✅ · reduced-motion ✅）
- 已跑通命令：`pnpm i` / `pnpm dev` → :5173 / `pnpm build` / `pnpm typecheck`
- Opus 花费：`$1.94`（P1，含 3 次自我修正；来源：CC Switch 用量面板）

## 2. 已完成的决定（不要推翻）

| 决定 | 为什么 | 推翻的代价 |
|---|---|---|
| 动效用 CSS transition，只有 M02 用 rAF | 依赖为零；数字滚动 CSS 做不了 | M02 重写 + 引入依赖审查 |
| 柱状图用纯 CSS `scaleY`，不用 SVG path 动画 | 可被 GPU 合成层加速，且好维护 | MiniBars 全部重写 |
| 深色主题不提供浅色版 | 本任务范围外 | 全部颜色重做 |

## 3. FROZEN（DeepSeek 不得修改）

| 路径 / 选择器 | 为什么不能动 |
|---|---|
| `src/styles/tokens.css` | 令牌是唯一真相，改一个值全站漂移 |
| `src/components/HeroStat.tsx` 的 svg 内部结构 | 内部两个 group 分别做 0.3x / 1x 视差 |
| `#bg-glow` 与 `#fg-grid` 的 transform 层级与速率 | 与滚动 hook 耦合，改了视差断 |
| `src/pages/Dashboard.tsx` 里的视差滚动 hook | 同上 |

## 4. TODO（有序，一次一条）

| ID | 目标 | 文件 | 验收 | 预估 | 状态 |
|---|---|---|---|---|---|
| T01 | 照抄 HeroStat 做出 StatTile（无数字滚动） | `src/components/StatTile.tsx` | 1440 视口 4 列对齐，截图与 HeroStat 同质感 | M | done |
| T02 | 照抄 M01 的入场交错到 4 张 StatTile | `src/pages/Dashboard.tsx` | 交错 80ms，截图两帧有差 | S | done |
| T03 | MiniBars 接到 3 个次级面板 | `src/components/MiniBars.tsx` | 柱高比例正确，40ms 交错 | M | doing |
| T04 | Toolbar 下拉（M06） | `src/components/Toolbar.tsx` | 打开/关闭时长分别为 240/120ms | S | todo |
| T05 | ≤390 断点收敛 | `src/styles/responsive.css` | 390 视口无横向滚动，间距 --space-5 | S | todo |
| T06 | reduced-motion 降级 | `src/styles/reduced.css` | 系统开启减少动效后，位移消失、数字瞬时到位 | S | todo |

## 5. NEEDS-OPUS（不要自己去猜）

| 位置 | 我卡在 | DeepSeek 的假设 | Opus 裁决 |
|---|---|---|---|
| T03 | 次级面板的 MiniBars 柱数不一致（3/5/8 根），交错总时长差很多，是否该按比例压缩每柱间隔？ | 暂按「总时长固定 480ms，间隔 = 480/柱数」实现，需确认 | 待裁决 |
| T04 | 下拉在 390 断点是否需要全屏抽屉？规范没写 | 暂按普通下拉实现，不改成抽屉 | 待裁决 |

## 6. 禁止的简化（含原因）

- 不要合并 `#bg-glow` 与 `#fg-grid`（0.3x / 1x 视差）
- 不要给 MiniBars 加 `transition`（CSS 动画已在驱动，会双重插值）
- 不要把 M01 交错合并成整体淡入（节奏即设计）
- 不要把 `--ease-spring` 换成 `--ease-out`（数字落位的过冲是标识）

## 7. 度量（任务结束后由人补一行）

| 日期 | Opus 花费 | Opus 代码占比 | NEEDS-OPUS 数 | POLISH 条数 | 首轮通过 |
|---|---|---|---|---|---|
| 2026-11-04 | $1.94 + $0.27 = $2.21 | 34% | 2 | 6 | 否（POLISH 改了 6 处） |
