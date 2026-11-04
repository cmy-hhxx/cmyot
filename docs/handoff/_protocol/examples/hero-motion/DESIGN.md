# DESIGN — hero-motion（示例，演示"命令式规范"长什么样）

> 本文件是命令，不是描述。所有数值来自令牌文件 `src/styles/tokens.css`。
> 这个示例来自一个假想的数据看板项目，用来对照模板填空。

## 1. 视觉意图（≤3 句）

参考 Linear 深色面板的克制感 + Vercel 的排版留白。低饱和、高对比、**慢动效**（不像消费级产品那样弹）。主视觉只有一个焦点：首屏数字卡片，其余全部退后一层。

## 2. 令牌

| 类别 | 变量 | 值 | 用途限制 |
|---|---|---|---|
| 底色 | `--c-bg` | `#0e1013` | 页面背景 |
| 面板 | `--c-surface` | `#16191e` | 卡片 |
| 主文 | `--c-fg` | `#e8eaed` | 正文 |
| 次文 | `--c-fg-dim` | `#9aa0a6` | 标签 |
| 强调 | `--c-accent` | `#5b8def` | 仅用于关键数字 / 选中态 |
| 间距 | `--space-1..8` | `4/8/12/16/24/32/48/64px` | 所有内外间距 |
| 时长 | `--dur-1/2/3/4` | `120 / 240 / 480 / 900ms` | 微交互 / 状态 / 入场 / 数字滚动 |
| 缓动 | `--ease-out` | `cubic-bezier(.2,.8,.3,1)` | 位移、缩放 |
| 缓动 | `--ease-in-out` | `cubic-bezier(.4,0,.2,1)` | 透明度、颜色 |
| 缓动 | `--ease-spring` | `cubic-bezier(.34,1.4,.64,1)` | **只允许**用于数字弹跳 |

允许的缓动**只有这三条**，新增需登记。

## 3. 布局与网格

- 容器：max-width 1200px，左右 padding `--space-6`
- 栅格：12 列，gutter `--space-4`；≤834px 降 6 列；≤390px 单列
- 垂直节奏：区块之间一律 `--space-7`

## 4. 组件清单

| 组件 | 文件 | 状态 | 说明 |
|---|---|---|---|
| `HeroStat`（数字 + 单位 + 趋势） | `src/components/HeroStat.tsx` | **参照实现（完整）** | 被复制 N 次 |
| `MiniBars`（迷你柱状图） | `src/components/MiniBars.tsx` | 参照实现（完整） | CSS scaleY 驱动 |
| `StatTile` | `src/components/StatTile.tsx` | 静态骨架 → 照抄 HeroStat | 无数字滚动 |
| `Toolbar` / `Legend` / `FootNote` | `src/components/*.tsx` | 静态骨架 | 只求能渲染 |

## 5. 动效表

| ID | 元素 | 属性 | 起 → 止 | 时长 | 缓动 | 触发 | 交错 | 备注 |
|---|---|---|---|---|---|---|---|---|
| M01 | HeroStat 卡片 | `translateY` + `opacity` | `16px,0` → `0,1` | `--dur-3` | `--ease-out` | 首次进入 | 每卡 80ms | 只播一次 |
| M02 | HeroStat 数字 | 数值 0 → 目标 | `0` → n | `--dur-4` | `--ease-out` | M01 结束后 120ms | — | JS rAF，非 CSS；需 `window.__seek` |
| M03 | MiniBars 柱 | `scaleY` | `0` → `1` | `--dur-2` | `--ease-out` | 进入视口 | 每柱 40ms | `transform-origin: bottom` |
| M04 | 卡片 hover | `translateY` | `0` → `-2px` | `--dur-1` | `--ease-out` | `pointerenter` | — | **离开瞬间回位**，无回弹 |
| M05 | 数值更新（轮询） | 颜色 | `--c-fg` → `--c-accent` → `--c-fg` | `--dur-2` | `--ease-in-out` | 值变化 | — | 只闪一次 |
| M06 | Toolbar 下拉 | `opacity` + `scale(.98→1)` | — | `--dur-2` | `--ease-out` | 打开 | — | 关闭用 `--dur-1` |

## 6. 不变量

**Must**
- 颜色 / 间距 / 时长全部来自令牌，禁止裸值
- 所有可交互元素 `:focus-visible` 且焦点环对比度 ≥ 3:1
- 首屏内容延迟 ≤ 200ms；数字动画不得阻塞首帧
- `prefers-reduced-motion: reduce` → 位移类降为 opacity 交叉淡入（≤120ms），数字直接显示终值

**Never**
- 不引入第四条缓动曲线
- 不用 `transition: all`
- 不用 `!important`
- 不在 scroll 回调里同步读布局（`offsetHeight` / `getBoundingClientRect`）
- 除 M05 外不做颜色过渡动画

## 7. 禁止的简化（含原因）

- 不要合并 `#bg-glow` 与 `#fg-grid` 两层——它们以 0.3x / 1x 速率做视差，合并后视差消失。
- 不要把 M01 的交错改成一个整体淡入——80ms 的交错是"逐个点亮"的节奏，是设计的一部分。
- 不要把 `--ease-spring` 换成 `--ease-out`——M02 数字落位的轻微过冲就是这个动效的标识。
- 不要给 `MiniBars` 加过渡——它由 CSS 动画驱动，加 `transition` 会双重插值，出现抖动。

## 8. 响应式与降级

| 断点 | 变化 |
|---|---|
| ≥1440 | 4 列 HeroStat |
| 834~1439 | 2 列 |
| ≤390 | 1 列，区块间距降到 `--space-5`，动效时长 ×0.7 |

- `prefers-reduced-motion`：见不变量
- `@media (update: slow)`：关闭视差（`#bg-glow` 停在 0.3x 位置）
