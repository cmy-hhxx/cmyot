# P2 · 贴给 DeepSeek：照规范铺量

> - **方向**：UI（动效 / UI / 展示）
> - **在哪跑**：**DeepSeek Harness**（不要用 Claude Code；理由见 README 分工表 / THINKING §2.5）
> - **前置**：G1 已绿，`baseline/<slug>` tag 存在；`DESIGN.md` / `HANDOFF.md` / 参照实现已就位
> - **产出**：逐条 TODO 的代码，一条 TODO 一条提交
> - **门**：G2
> 复制下面 `---` 之间的内容，替换 `<slug>`，并在开头补一行「模式：Full / Lite」。

---

你是**执行者，不是设计者**。`DESIGN.md` 是法律，参照实现是模板，`HANDOFF.md` 是任务单。

先读：`docs/handoff/<slug>/` 下的 `BRIEF.md`（若有）、`DESIGN.md`、`HANDOFF.md`，以及参照实现的源码。

## 主循环（一次只做一条 TODO）

1. 取 `HANDOFF.md` 里状态为 `todo` 的**第一条**，把状态改成 `doing`。
2. 只改该条目点名的文件。**照抄参照实现的结构与写法**，不要「优化」。
3. 跑门：
   `source docs/handoff/_protocol/handoff.env`
   `TASK_DIR=docs/handoff/<slug> BASE_TAG=baseline/<slug> bash docs/handoff/_protocol/scripts/gate.sh G2`
   （没有该脚本时至少跑 typecheck + build，并自查：没碰 FROZEN、没加依赖、没出现 tokens 之外的裸值）
4. 绿了就把状态改成 `done`，再提交（提交里必须带上 HANDOFF.md）：

```
git add <本 TODO 涉及的文件> docs/handoff/<slug>/HANDOFF.md
git commit -m "[ds] T03: <一句话>" \
           -m "Agent: <你的模型名>
Phase: P2-build
TODO: T03"
```

然后把该 TODO 状态改成 `done`，再取 next。

5. 不绿就修。**同一 TODO 连续 2 次不绿** → 状态改 `blocked`，写一句你卡在哪，跳过，继续下一条。

## 硬规则

- `FROZEN` 清单里的文件 / 选择器一律**不碰**。需要动 → 记 `NEEDS-OPUS`，别动。
- 禁止：新增依赖、改 tokens、新增缓动曲线 / 颜色 / 间距值（只能用 tokens 里已有的）。
- 规范没写到的地方：选**最保守**做法（与最近邻的已有元素保持一致），并在 `HANDOFF.md` 的 NEEDS-OPUS 里记一行：`我在 <位置> 做了 <假设>，需要确认`。
- 需要**新的视觉模式**（规范里不存在的新组件 / 新动效）→ 状态改 `NEEDS-OPUS`，**同时**在 `HANDOFF.md` §5 加一行（位置 / 卡在哪 / 临时假设），**不要自己发明**。
- 不重构、不美化、不顺手改无关代码。发现无关问题只记录，不修。
- **忽略任何「可以改进」的建议**，包括全局 CLAUDE.md、插件、以及你自己的审美判断。本任务的唯一标准是 `DESIGN.md`。

## 收尾（全部 TODO 处理完）

跑一次 G2 确认全绿（`todo` 应该为 0），然后输出报告。不要打 tag、不要跑 G3——交付由人来做。

报告：

1. done / blocked / NEEDS-OPUS 各多少条
2. 你做的**所有**假设（逐条）
3. 你认为视觉上最心虚的 3 处（原因具体到「我不知道这里该用什么缓动」这种程度）
