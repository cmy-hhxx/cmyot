# P3 · 贴给 Opus：短审 + 改规范 + 给 POLISH 清单（仅 Full 模式）

> - **方向**：UI（动效 / UI / 展示）
> - **在哪跑**：Claude Code（Opus 供应商）
> - **前置**：G2 已绿；NEEDS-OPUS 队列已收集；stills 截图已生成
> - **产出**：NEEDS-OPUS 逐条裁决 + `docs/handoff/<slug>/POLISH.md`（≤10 条机械修改）
> - **预算**：≤ 整个任务 Opus 用量的 15%
> 复制下面 `---` 之间的内容，替换 `<slug>`。

---

你是**终审**。便宜模型已经铺完量，现在只做判断，不做重写。

## 预算纪律

- 本次 pass 的 token 不得超过整个任务 Opus 用量的 15%。超了就是流程问题，不是任务问题。
- **不要逐个文件修它的产出**。优先改 `DESIGN.md` 的条文 / tokens / 参照实现——规范改对了，下一轮它自己就对。
- 不看全仓，只看我这轮提供的东西 + 必要的 3~5 个文件。

## 输入

- `source docs/handoff/_protocol/handoff.env`（跑门用）
- `git diff baseline/<slug>..HEAD --stat` 和关键文件的 diff
- `docs/handoff/<slug>/stills/` 下的 3 视口截图（若没有，让我去跑）
- `HANDOFF.md` 里的 NEEDS-OPUS 队列与 blocked 项
- 本阶段成本（我从 CC Switch 用量面板抄给你）

## 任务

1. **逐条裁决 NEEDS-OPUS**：每条一句话决定 + 具体写法/数值（不要给方向，要给值）。填进 `HANDOFF.md` §5 的「Opus 裁决」列。裁决后由 DeepSeek 执行：做了 → 状态改 `done`；决定不做 → 改 `dropped`。
2. **最小必要手改**：只改规范、tokens、参照实现；只有当某处是「复制粘贴错误级」的问题才直接改代码。
3. **写 `docs/handoff/<slug>/POLISH.md`**：按优先级排 ≤10 条给 DeepSeek 的**机械修改**，每条格式：

```
- [P1] <文件或选择器>：把 <现状> 改成 <目标>。验收：<可截图/可 grep 的判断>
```

4. 不要重构，不要扩大范围，不要重写已经能跑的部分。

## 结束时只输出

① 这次退化最严重的 3 处 ② 下一轮该给 DeepSeek 补哪**一条**规范（一句话，可直接贴进 DESIGN.md） ③ POLISH 条数
