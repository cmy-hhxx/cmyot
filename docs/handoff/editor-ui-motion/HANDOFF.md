# HANDOFF — editor-ui-motion

> **谁改哪一节**：§1 §2 §3 §6 由 Opus（P1）写；§4 的状态列和 §5 由 DeepSeek（P2）改；§5 的「Opus 裁决」列由 Opus（P3）填。

## 1. 状态（Opus 写，P2 / P3 更新门状态）

- 模式：Full
- 当前阶段：P2 完成（待 P3 短审）
- 下一步是谁：Opus（P3）
- baseline tag：`baseline/editor-ui-motion`
- 门状态：G1 ✅（build ✅ · DESIGN.md ✅ · HANDOFF.md ✅）；截图 / console error / 两帧差 / reduced-motion 由 gate 跳过（STILLS_URL 为空，原生 app），**需人工截图 + 录屏确认**
- 门状态：G2 ✅（10/10 TODO done · build ✅ · FROZEN 未被触碰 · 无新依赖 · 无裸值 · 工作区干净；截图门同 G1 仍跳过）
- 已跑通命令：`xcodebuild -project CotEditor.xcodeproj -scheme CotEditor -configuration Debug -derivedDataPath /tmp/cmyot-dd build -quiet -skipPackagePluginValidation -skipMacroValidation`
- Opus 花费：（待从 CC Switch 用量面板读取）

## 2. 已完成的决定（不要推翻）

| 决定 | 为什么 | 推翻的代价 |
|---|---|---|
| 动效统一用 `AnimationConstants` 而非裸值 | 统一时长 + prefers-reduced-motion 降级 | 全部动效重写，且失去无障碍支持 |
| AppKit 侧用 `NSAnimationContext.withStandardTiming` 包裹 | `animator()` 默认时长不可控；包裹后统一 250ms | 21 处 animator() 调用都要改回去 |
| SwiftUI 侧用 `.cotAnimation` helper | 自动处理 reduced-motion 降级 | 失去无障碍支持 |
| macOS 26 vs 15 双路径保留 | 状态栏实现不同（`isHidden` vs `isCollapsed`） | 破坏兼容性 |

## 3. FROZEN（DeepSeek 不得修改）

| 路径 / 选择器 | 为什么不能动 |
|---|---|
| `CotEditor/Sources/Utilities/AppKit/AnimationConstants.swift` | 令牌唯一真相；改一个值全站动效漂移 |
| `CotEditor/Sources/Utilities/AppKit/NSAnimationContext+Timing.swift` | 参照实现；DeepSeek 照抄这个模式到其他 animator() 调用 |
| `CotEditor/Sources/Utilities/SwiftUI/AnimationConstants+SwiftUI.swift` | 参照实现；DeepSeek 照抄这个模式到其他 SwiftUI 动画 |
| `WindowContentViewController.swift:210~226` 的 macOS 26 vs 15 分支 | 两个系统 API 不同，不能合并 |
| `AnimationConstants` 里的五个时长值（0.0 / 0.15 / 0.25 / 0.35 / 0.5） | 匹配系统默认时长，改了会和原生动效不协调 |
| `AnimationConstants.reorderAnimation` 的 `dampingFraction: 0.8` | 再低会过度弹跳，偏离 macOS 原生观感 |

## 4. TODO（有序，一次一条）

| ID | 目标 | 文件 | 验收 | 预估 | 状态 |
|---|---|---|---|---|---|
| T01 | 迁移 FindPanelContentViewController 的动画 | `Text Finder/Views/FindPanelContentViewController.swift:202` | animator() 包在 withStandardTiming 里 | S | done |
| T02 | 迁移 SynchronizedScrollView 的三处 magnification 动画 | `Text Finder/Text View/SynchronizedScrollView.swift:100,109,118` | 同上 | S | done |
| T03 | 迁移 FileBrowserViewController 的 collapse/expand 动画 | `Sidebar/FileBrowserViewController.swift:653,655` | 同上 | S | done |
| T04 | 迁移 FileBrowserViewController 的 separator alpha 动画 | `Sidebar/FileBrowserViewController.swift:944` | 用 withTiming(duration: .fast, easeOut) | S | done |
| T05 | 迁移 AboutView 的 Picker 动画 | `Panels/AboutView.swift:93` | `.cotAnimation(.cotStandard)` | S | done |
| T06 | 迁移 WhatsNewView 的延迟淡入动画 | `Panels/WhatsNewView.swift:269` | `.cotAnimation(.cotFast)` + delay 0.1s | S | done |
| T07 | 迁移 DonationSettingsView 的数量动画 | `Settings Window/Panes/DonationSettingsView.swift:303` | `.cotAnimation(.cotStandard)` | S | done |
| T08 | 迁移 EncodingListView 的列表动画 | `Settings Window/Other Views/EncodingListView.swift:103` | `.cotAnimation(.cotSlow)` | S | done |
| T09 | 迁移 PatternSortView 的 Picker 动画 | `Accessory Views/PatternSortView.swift:98` | `.cotAnimation(.cotStandard)` | S | done |
| T10 | 迁移 CharacterCountOptionsView 的 Picker 动画 | `Accessory Views/Advanced Character Count/CharacterCountOptionsView.swift:83` | `.cotAnimation(.cotStandard)` | S | done |

**预估**：S = Small（1 处修改，≤5 分钟） | M = Medium（2~5 处修改，≤15 分钟） | L = Large（>5 处或需重构，≤30 分钟）

## 5. NEEDS-OPUS（不要自己去猜）

| 位置 | 我卡在 | DeepSeek 的假设 | Opus 裁决 |
|---|---|---|---|
| `Panels/AboutView.swift:93`（T05） | `$pane.animation()` 是 Binding 动画，DESIGN 点名的 `.cotAnimation(.cotStandard)` 是 View modifier，两者语义不同 | 改用 `$pane.animation(.cotStandard)`：保留 binding 动画，只把默认曲线换成令牌 | — |
| `Accessory Views/PatternSortView.swift:98`（T09） | 同上（`$sortKey.animation()`） | 同上，改用 `$sortKey.animation(.cotStandard)` | — |
| `Accessory Views/Advanced Character Count/CharacterCountOptionsView.swift:83`（T10） | 同上（`$unit.animation()`） | 同上，改用 `$unit.animation(.cotStandard)` | — |

## 6. 禁止的简化（含原因）

- **不要去掉 `NSAnimationContext.withStandardTiming` 的包裹，直接用 `animator()`** — `animator()` 默认时长不可控，且不同 macOS 版本可能有差异；包裹是为了统一时长并支持 reduced-motion 降级。
- **不要把 SwiftUI 的 `.cotAnimation(.cotFast, value:)` 改成 `.animation(.easeOut(duration: 0.15), value:)`** — `.cotAnimation` 内部处理 reduced-motion 降级；裸 `.animation` 不处理。
- **不要合并 macOS 26 和 macOS 15 的状态栏动画分支**（`WindowContentViewController.swift:210~226`）— 两个分支操作不同的对象（`isHidden` vs `isCollapsed`），强行合并会破坏类型安全。

**DeepSeek 最可能做错的 3 个地方**（Opus 预判）：
1. **直接用 `.animation(.default)` 而不用 `.cotAnimation`** — `.default` 不处理 reduced-motion，且时长不受控。必须用 `.cotStandard` / `.cotFast` / `.cotSlow` 或 `.cotAnimation` helper。
2. **忘记包 `NSAnimationContext.withStandardTiming`** — 看到 `animator()` 就以为已经在动画了，实际上时长还是默认的不可控值。每个 `animator()` 调用都必须包在 `with{Standard}Timing` 里。
3. **修改 `AnimationConstants` 里的数值**（如把 0.25 改成 0.3）— 这些值匹配系统默认时长，改了会让新动效和系统原生动效不协调。要改时长必须先在 §5 提 NEEDS-OPUS。

## 7. 度量（任务结束后由人补一行）

| 日期 | Opus 花费 | Opus 代码占比 | NEEDS-OPUS 数 | POLISH 条数 | 首轮通过 |
|---|---|---|---|---|---|
| — | — | — | — | — | — |
