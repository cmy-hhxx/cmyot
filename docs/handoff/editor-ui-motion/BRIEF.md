# BRIEF — editor-ui-motion

> 由 DeepSeek 撰写（P0，UI 轨道，Full 模式）。事实必须可验证：命令是真跑过的，路径是真存在的。总长 ≤200 行。

- 方向：UI（动效 / UI / 展示）
- 模式：Full
- 任务：优化 CotEditor 编辑器的样式、UI 与动效
- 时间盒：P1 ≤ 90 分钟

## 1. 这个仓库是什么（≤10 行）

CotEditor 是一个 macOS 原生纯文本编辑器：Swift + AppKit 的文档型 app（NSTextView / TextKit），设置面板与部分视图用 SwiftUI。
设计哲学（README）：**融入 macOS 原生观感，不做自定义窗口 chrome，Less is more**。要求 macOS 15+，本机 Xcode 26.6。

## 2. 技术栈与真实命令（实测）

| 用途 | 命令 | 实测结果 |
|---|---|---|
| 构建 | `xcodebuild -project CotEditor.xcodeproj -scheme CotEditor -configuration Debug -derivedDataPath /tmp/cmyot-dd build -skipPackagePluginValidation -skipMacroValidation` | ✅ BUILD SUCCEEDED |
| 启动 | `open /tmp/cmyot-dd/Build/Products/Debug/CotEditor.app` | 命令正确；P1 时实际启动验证 |
| 测试 | `xcodebuild -project CotEditor.xcodeproj -scheme CotEditor -destination 'platform=macOS' -derivedDataPath /tmp/cmyot-dd test -skipPackagePluginValidation -skipMacroValidation` | ❌ 跑不通：ad-hoc 配置缺 `CotEditor/Tests-AdHoc.entitlements` |
| lint | SwiftLintBuildToolPlugin（构建时自动） | ✅ |

> **坑 1**：不加 `-skipPackagePluginValidation` 会失败在 `Validate plug-in "SwiftLintBuildToolPlugin"`。
> **坑 2**：首次构建要拉 SPM 依赖（约 2GB，数分钟）；之后增量构建约 30~60 秒。

## 3. 目录与关键文件

| 路径 | 职责 | 备注 |
|---|---|---|
| `CotEditor/Sources/Document Window/` | 文档窗口主体 | 本次任务主战场 |
| `…/WindowContentViewController.swift` | 侧栏 / 检查器 / 状态栏 / 分屏装配（445 行） | 动画集中点 |
| `…/Content View/EditorViewController.swift` | 每个编辑窗格：导航栏 + 文本视图（265 行） | `navigationBarItem.animator()` |
| `…/Content View/EditorTextViewController.swift` | 编辑器视图（636 行） | 计数器淡出动画 |
| `…/Content View/StatusBar.swift` | 状态栏（SwiftUI，472 行） | 显隐动画 |
| `…/Text View/LineNumberView.swift` | 行号视图（538 行） | 纯绘制，无动画 |
| `…/Text View/EditorTextView.swift` | 文本视图（NSTextView 子类） | 当前行高亮 / 选区 |
| `…/Sidebar/FileBrowserViewController.swift` | 文件浏览器（1550 行） | 展开/折叠动画 |
| `…/Inspector/InspectorViewController.swift` | 检查器（204 行） | 与侧栏同构 |
| `CotEditor/Sources/Models/Theme.swift` | 语法主题模型 | 颜色唯一真相（用户可换主题） |
| `CotEditor/Sources/Utilities/AppKit/NSColor+NamedColors.swift` | 语义颜色扩展 | 可复用 |
| `CotEditor/Resources/Assets.xcassets/Colors` | 命名颜色资产 | 可复用 |
| `CotEditor/Resources/Themes/*.cottheme` | 内置语法主题 | 不要改内置主题 |
| `CotEditor/Sources/Settings Window/` | SwiftUI 设置面板 | `isLiquidGlass ? a : b` 条件密集 |

## 4. 现有设计系统（必须复用）

- **颜色**：AppKit 语义色（`NSColor.labelColor` 等）+ Assets Colors + `Theme`（语法高亮）。**不要新建颜色体系**。
- **间距 / 圆角**：没有集中令牌；散落在 SwiftUI 视图里，且大量 `isLiquidGlass ? a : b` 条件。
- **动效**：21 处 `animator()` / `NSAnimationContext`，**没有统一的时长 / 曲线常量**，多数是默认时长。
- **字体**：系统字体；编辑器字体来自用户设置（不要写死）。

## 5. 现有约定（可照做的规则）

- **原生优先**：用系统控件 / 材质（`NSVisualEffectView`、`.ultraThinMaterial`）；不自定义标题栏。
- **macOS 26 双路径**：全局常量 `isLiquidGlass`（`AppDelegate.swift:38`）+ `if #available(macOS 26, *)`。
- **本地化**：46 个 `.xcstrings`，所有用户可见文案必须走本地化。
- **无障碍**：`accessibilityLabel` / `accessibilityLabeledPair` 已有先例。
- **代码风格**：`.swiftlint.yml` + `.editorconfig`；文件头保留 license。
- **动画**：优先 `animator()`；需要精确控制时 `NSAnimationContext`。

## 6. 本任务要做什么 / 明确不做什么

**做**

- Document Window 的动效统一：侧栏 / 检查器开合、状态栏显隐、导航栏折叠、计数器淡出。
- 编辑器主界面视觉细节：当前行高亮、行号、选区、状态栏排版。
- 建立可复用的动效封装（时长 / 曲线常量 + 一个 AppKit helper），SwiftUI 侧给对应写法。

**不做**

- 不改编辑逻辑、文档模型、语法解析。
- 不引入第三方依赖。
- 不重做设置面板 / 查找面板的布局（除非为一致性所需，且要单列 TODO）。
- 不偏离 macOS 原生观感（README 的设计哲学）。

## 7. 已知坑

- 构建必须带 `-skipPackagePluginValidation -skipMacroValidation`。
- **测试当前跑不通**：AdHoc xcconfig 给 Tests target 也套了 `$(PRODUCT_NAME)-AdHoc.entitlements`，但仓库里没有 `CotEditor/Tests-AdHoc.entitlements`。这是既有配置问题，UI 轨道不依赖测试；要跑测试需单独修这个配置。
- **双路径**：状态栏在 macOS 26 用 `bottomAlignedAccessoryViewControllers` + `animator().isHidden`，macOS 15 用 `splitViewItems` + `animator().isCollapsed`。
- `NSSplitViewItem` 的 `animator().isCollapsed` **时长不可控**；要统一时长必须用 `NSAnimationContext` 包裹。
- `animator()` 默认时长约 0.25s，SwiftUI `.animation` 默认约 0.35s——两者不一致，是"动效不统一"的主要来源。
- 原生 app 没有浏览器截图：视觉验收改为人工（见 §8）。
- **当前工作区有未提交改动**（`Packages/Syntax` 语言裁剪）。P1 开始前必须先提交或 stash，否则基线会被污染。

## 8. 验证方式（原生 app 适配）

- **构建**：§2 的 BUILD_CMD，退出 0。
- **启动**：`open /tmp/cmyot-dd/Build/Products/Debug/CotEditor.app`。
- **视觉**：3 个窗口宽度（1440 / 1024 / 720）人工截图，存 `docs/handoff/editor-ui-motion/stills/`。
- **动效**：录屏，或同一操作前后两帧截图；人工确认时长 / 曲线一致。
- **gate.sh**：`STILLS_URL` 留空 → 截图门跳过（预期）；G1 的视觉项由人确认，不假装机器验过。

## 9. 给 Opus 的 3 个必须由人 / Opus 决定的问题

1. **动效语言**：继续用 `animator()` 默认时长，还是引入 `NSAnimationContext` 封装（时长 / 曲线常量）？后者可控，但要同时覆盖 `NSSplitViewItem` 和 SwiftUI 两套。
2. **视觉边界**：是否引入一层 AppKit 设计令牌（间距 / 圆角 / 时长）？会碰很多文件；不引入就继续让 `isLiquidGlass` 条件散落。
3. **范围**：本轮只做 Document Window（编辑器 + 侧栏 + 检查器 + 状态栏），还是也包含设置面板 / 查找面板？
