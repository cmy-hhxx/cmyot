# DESIGN — editor-ui-motion

> 令牌文件：`CotEditor/Sources/Utilities/AppKit/AnimationConstants.swift`
> 
> 本文档是命令，不是描述。DeepSeek 会逐条执行；任何感觉类形容词都会被翻译成自由发挥。所有数值来自令牌文件。

## 1. 视觉意图

macOS 原生编辑器，不创新设计语言。参照物：系统设置、邮件、备忘录——标准控件、零自定义 chrome、平滑的系统默认动效。信息密度高，多窗格排布，侧栏 / 编辑器 / 检查器三栏结构。

## 2. 令牌（唯一真相）

令牌文件：`CotEditor/Sources/Utilities/AppKit/AnimationConstants.swift`

| 类别 | 常量 | 值 | 用途限制 |
|---|---|---|---|
| 时长 | `AnimationConstants.instant` | `0.0` | 无障碍 reduced-motion 降级 |
| 时长 | `AnimationConstants.fast` | `0.15` | hover 态、计数器淡出 |
| 时长 | `AnimationConstants.standard` | `0.25` | 侧栏 / 检查器 / 状态栏开合、导航栏折叠（AppKit animator 默认时长） |
| 时长 | `AnimationConstants.slow` | `0.35` | 列表重排版（SwiftUI .animation 默认时长） |
| 时长 | `AnimationConstants.slower` | `0.5` | 高亮闪烁淡出 |
| 缓动 | `AnimationConstants.easeInOut` | `CAMediaTimingFunctionName.easeInEaseOut` | 大部分过渡 |
| 缓动 | `AnimationConstants.easeOut` | `CAMediaTimingFunctionName.easeOut` | 元素进入屏幕、淡出 |
| 缓动 | `AnimationConstants.easeIn` | `CAMediaTimingFunctionName.easeIn` | 元素离开屏幕 |
| 缓动 | `AnimationConstants.linear` | `CAMediaTimingFunctionName.linear` | 连续或循环动画 |

**SwiftUI 侧对应：**

| 常量 | 值 | 用途 |
|---|---|---|
| `Animation.cotStandard` | `easeInOut(duration: 0.25)` | 标准过渡 |
| `Animation.cotFast` | `easeOut(duration: 0.15)` | 微交互 |
| `Animation.cotSlow` | `easeInOut(duration: 0.35)` | 大型布局过渡 |
| `Animation.cotReorder` | `spring(response: 0.35, dampingFraction: 0.8)` | 拖拽排序（damping ≥ 0.8 防止过度弹跳） |

**允许的缓动曲线只此五条**：`easeInOut` / `easeOut` / `easeIn` / `linear` / `spring(response: 0.35, dampingFraction: 0.8)`。新增需登记。

## 3. 布局与网格

— （无变更；现有布局由 Auto Layout / NSSplitView 控制）

## 4. 组件清单

| 组件 | 文件 | 状态 | 说明 |
|---|---|---|---|
| NSAnimationContext 封装 | `Utilities/AppKit/NSAnimationContext+Timing.swift` | 参照实现 | 被所有 AppKit 侧动效复制 |
| SwiftUI 封装 | `Utilities/SwiftUI/AnimationConstants+SwiftUI.swift` | 参照实现 | 被所有 SwiftUI 侧动效复制 |
| 侧栏 / 检查器开合 | `WindowContentViewController.swift:322~332, 355~367` | 参照实现 | `.withStandardTiming` 包裹 |
| 状态栏显隐 | `WindowContentViewController.swift:210~226` | 参照实现 | macOS 26 vs 15 双路径，都用 `.withStandardTiming` |
| 导航栏折叠 | `EditorViewController.swift:159~165` | 参照实现 | 条件动画，animated = true 时用 `.withStandardTiming` |
| 计数器淡出 | `EditorTextViewController.swift:473~482` | 参照实现 | `.fast` 时长 + `.easeOut` 曲线 |
| StatusBar 编辑态图标 | `StatusBar.swift:237` | 参照实现 | SwiftUI `.cotAnimation(.cotFast)` |
| 其他动效 | 全仓库 21 处 `animator()` | 静态骨架 | 暂未迁移（P2 铺量） |

## 5. 动效表

| ID | 元素 | 属性 | 起 → 止 | 时长 | 缓动 | 触发 | 备注 |
|---|---|---|---|---|---|---|---|
| M01 | 侧栏 / 检查器 | `isCollapsed` | `true` → `false` | 250ms | easeInOut | 点击工具栏按钮或快捷键 | `NSSplitViewItem.animator()` 包在 `NSAnimationContext.withStandardTiming` 里 |
| M02 | 状态栏（macOS 26） | `isHidden` | `true` ↔ `false` | 250ms | easeInOut | UserDefaults 变更 | 同上 |
| M03 | 状态栏（macOS 15） | `isCollapsed` | `true` ↔ `false` | 250ms | easeInOut | UserDefaults 变更 | 同上 |
| M04 | 导航栏 | `isCollapsed` | 根据内容 | 250ms | easeInOut | 窗格变更或用户设置 | 同上；`animated` 参数为 false 时瞬间切换 |
| M05 | 计数器视图 | `alphaValue` | `1.0` → `0.0` | 150ms | easeOut | 用户关闭 | `NSAnimationContext.withTiming(duration: .fast, easeOut)` |
| M06 | StatusBar 不可编辑图标 | opacity | `0` ↔ `1` | 150ms | easeOut | 文档 `isEditable` 变更 | SwiftUI `.cotAnimation(.cotFast, value: isEditable)` |

**无障碍降级（prefers-reduced-motion）：**
所有动效降级为瞬间完成（`duration = 0.0`）。`AnimationConstants.isReducedMotionEnabled` 读 `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`；AppKit 封装自动降级；SwiftUI 侧用 `.cotAnimation` helper 自动降级。

## 6. 不变量（Must / Never）

**Must**
- 所有动效时长 / 缓动来自 `AnimationConstants`，禁止裸值（如直接写 `0.3`）
- 所有 `animator()` / `NSAnimationContext.runAnimationGroup` 调用必须包在 `NSAnimationContext.withStandardTiming` 或 `.withTiming` 里，除非该动效被明确标记为"不动画"（如 `animated` 参数为 false 的分支）
- SwiftUI 侧用 `.cotAnimation` 或 `.cotStandard` / `.cotFast` 等命名动画，不用裸 `.easeInOut(duration:)`
- `prefers-reduced-motion` 降级必须工作：AppKit 封装自动处理；SwiftUI 用 `.cotAnimation` helper
- 所有可交互元素有焦点环（系统自动提供）

**Never**
- 不引入第五条缓动曲线（只能用 `easeInOut` / `easeOut` / `easeIn` / `linear` / `spring`）
- 不用 `animator()` 的裸调用（必须包在 `NSAnimationContext.with{Standard}Timing` 里）
- 不在 SwiftUI 里用 `.animation(.default)`（必须用 `.cotStandard` / `.cotFast` 等命名动画）
- 不自定义窗口 chrome（README 设计哲学）
- 不改编辑逻辑、文档模型、语法解析
- 不引入第三方依赖

## 7. 禁止的简化（含原因）

- **不要去掉 `NSAnimationContext.withStandardTiming` 的包裹，直接用 `animator()`** — `animator()` 默认时长不可控，且不同 macOS 版本可能有差异；包裹是为了统一时长并支持 reduced-motion 降级
- **不要把 SwiftUI 的 `.cotAnimation(.cotFast, value:)` 改成 `.animation(.easeOut(duration: 0.15), value:)`** — `.cotAnimation` 内部处理 reduced-motion 降级；裸 `.animation` 不处理
- **不要合并 macOS 26 和 macOS 15 的状态栏动画分支** — 两个分支操作不同的对象（`isHidden` vs `isCollapsed`），强行合并会破坏类型安全
- **不要修改 `AnimationConstants` 里的数值（如把 `standard = 0.25` 改成 `0.3`）** — 这些值匹配 AppKit 和 SwiftUI 的系统默认时长，改了会让新动效和系统原生动效不协调
- **不要把 spring 的 `dampingFraction` 从 0.8 降到 0.6** — 弹跳过度会偏离 macOS 原生观感

## 8. 响应式与降级

— （无响应式断点；macOS 窗口大小由用户拖拽调整，布局由 Auto Layout / NSSplitView 自适应）

**降级：**
- `prefers-reduced-motion`：见 §6 不变量。
- 低端设备：无特殊处理（macOS 系统动画引擎自动调节帧率）。
