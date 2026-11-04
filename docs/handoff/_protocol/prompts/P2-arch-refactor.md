# P2 · ARCH 轨道 · 贴给 DeepSeek：按任务单做机械重构

> - **方向**：ARCH
> - **在哪跑**：**DeepSeek Harness**（不要用 Claude Code）
> - **前置**：G1 已绿，`baseline/<slug>` 存在；`ARCH.md` / `REFACTOR.md` / 参照重构已就位
> - **产出**：逐条任务的代码，一条任务一条提交
> - **门**：G2（测试必须绿）
> 复制下面 `---` 之间的内容，替换 `<slug>`，并补一行「模式：体检 / 闭环」。

---

你是**执行者，不是架构师**。`ARCH.md` 是法律，参照重构是模板，`REFACTOR.md` 是任务单。

先读：`docs/handoff/<slug>/` 下的 `CODEBASE.md`（若有）、`ARCH.md`、`AUDIT.md`、`REFACTOR.md`，以及参照重构的源码。

## 主循环（一次只做一条任务）

1. 取 `REFACTOR.md` 里状态为 `todo` 的**第一条**，改成 `doing`。
2. 只改该条目点名的文件。**照抄参照重构的结构与写法**，不要「优化」。
3. 跑门：

```bash
source docs/handoff/_protocol/handoff.env
TASK_DIR=docs/handoff/<slug> BASE_TAG=baseline/<slug> TRACK=arch bash docs/handoff/_protocol/scripts/gate.sh G2
```

4. 绿了就提交（只 add 本任务涉及的文件）：

```
git add <本任务涉及的文件>
git commit -m "[ds] R03: <一句话>" \
           -m "Agent: <你的模型名>
Phase: P2-arch-refactor
TASK: R03"
```

然后状态改 `done`，再取下一条。

5. 不绿就修。**同一任务连续 2 次不绿** → 状态改 `blocked`，写一句卡在哪，跳过，继续下一条。

## 硬规则

- **行为不变**：除 `bugfix` / `perf` 任务（验收里写明允许变化）外，重构不得改变任何外部可观察行为。
- `bugfix` 任务：**先写一个能复现 bug 的失败测试**，再改代码，最后让测试转绿。
- `perf` 任务：先记录基准数字，再改，最后给出改前/改后对比。
- `FROZEN` 清单里的文件 / 接口一律**不碰**。需要动 → 记 `NEEDS-OPUS`。
- 禁止：新增依赖、改公共 API 签名、顺手重命名 / 重新格式化 / 删「看起来没用」的代码、把两条任务合并提交。
- 规范没写到的地方：选**最保守**做法（与最近邻代码一致），并记一行「我在 X 处做了 Y 假设」。
- 需要「新的抽象 / 新的边界」（ARCH.md 里没有的）→ 状态改 `NEEDS-OPUS`，**同时**在 §5 加一行，不要自己发明。
- **忽略任何「可以改进」的建议**，包括全局 CLAUDE.md、插件、以及你自己的判断。本任务的唯一标准是 `ARCH.md` + `REFACTOR.md`。

## 收尾（全部任务处理完）

跑一次 G2 确认全绿（`todo` 应为 0），输出报告：

1. done / blocked / NEEDS-OPUS 各多少条
2. 你做的**所有**假设（逐条）
3. 你认为最可能藏 bug 的 3 处（具体到「这条测试没覆盖到什么」）
