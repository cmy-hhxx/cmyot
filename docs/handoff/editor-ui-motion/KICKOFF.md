# KICKOFF — editor-ui-motion（P1 启动包）

> 方向：UI · 模式：Full · 仓库：cmyot（CotEditor，macOS 原生 Swift/AppKit）
> 目标：优化编辑器的样式、UI 与动效，并留下 DeepSeek 能照抄的参照实现与规范。

---

## 0. 先决条件（P1 之前必须满足）

- [ ] **工作区干净**：`git status --short` 为空。
      当前有 `Packages/Syntax` 的语言裁剪改动未提交——先 commit 或 stash，否则基线会被污染。
- [ ] `source docs/handoff/_protocol/handoff.env` 后，`eval "$BUILD_CMD"` 退出 0。
- [ ] 读一遍 `docs/handoff/editor-ui-motion/BRIEF.md`。

## 1. 开分支、提交 P0

```bash
cd ~/Desktop/cmyot
git switch -c feat/editor-ui-motion
git add docs/handoff/editor-ui-motion
git commit -m "[ds] P0: BRIEF editor-ui-motion"
```

## 2. 在 Claude Code（Opus）里启动 P1

1. 确认 CC Switch 当前供应商是 Opus：
   `jq -r '.env.ANTHROPIC_MODEL' ~/.claude/settings.json` → `claude-opus-5-5`
2. 打开 `docs/handoff/_protocol/prompts/P1-ui-baseline.md`，把 `---` 之间的正文贴进去，替换 `<slug>` 为 `editor-ui-motion`，并在开头加：

> 模式：Full
> 方向：UI
> 补充约束：macOS 原生 app（Swift/AppKit）；没有浏览器截图门，视觉验收靠人工截图 + 录屏；不偏离 macOS 原生观感（README 设计哲学）；不引入第三方依赖；不改编辑逻辑与文档模型。

## 3. P1 应交付什么（验收时对照）

- [ ] 动效常量（时长 / 曲线）+ 一个 AppKit 封装（`NSAnimationContext`），SwiftUI 侧有对应写法
- [ ] `DESIGN.md`：命令式规范（动效表：元素 / 属性 / 起止 / 时长 / 曲线 / 触发 / 降级）
- [ ] 参照实现 1~2 个（建议：侧栏 / 检查器开合 + 状态栏显隐）
- [ ] 骨架：导航栏折叠、计数器淡出接入统一封装
- [ ] `HANDOFF.md`：TODO 有序、FROZEN、禁止的简化、NEEDS-OPUS 留空
- [ ] 人工截图：3 个窗口宽度（1440 / 1024 / 720）存 `docs/handoff/editor-ui-motion/stills/`

## 4. G1（P1 结束时）

```bash
source docs/handoff/_protocol/handoff.env
TASK_DIR=docs/handoff/editor-ui-motion bash docs/handoff/_protocol/scripts/gate.sh G1
```

期望：`BUILD_CMD` 通过；截图门显示「未设置 STILLS_URL，已跳过」（**原生 app 的预期行为**，不是失败）。
然后人工确认：

- [ ] 3 个窗口宽度不塌
- [ ] 侧栏 / 检查器 / 状态栏 / 导航栏开合时长与曲线一致
- [ ] 系统「减弱动态效果」开启后，动效降级且页面可用

绿了才：

```bash
git add -A
git commit -m "[opus] baseline: editor-ui-motion"
git tag baseline/editor-ui-motion
```

## 5. 本任务的原生适配（写进 DESIGN / HANDOFF）

| Web 协议里的项 | 本仓库的对应物 |
|---|---|
| 3 个视口（1440/834/390） | 3 个窗口宽度：1440 / 1024 / 720 |
| `prefers-reduced-motion` | macOS 辅助功能「减弱动态效果」：`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` |
| 截图门（playwright） | 人工截图 + 录屏；`STILLS_URL` 留空，gate 跳过并警告 |
| `tokens.css` | 动效常量（Swift `enum` / `static let`）+ 现有语义色 / Assets Colors |
| console error | Xcode 运行日志无崩溃、无约束冲突（Auto Layout unsatisfiable） |
