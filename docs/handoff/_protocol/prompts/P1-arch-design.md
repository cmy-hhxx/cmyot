# P1 · ARCH 轨道 · 贴给 Opus：审计 + 目标设计 + 参照重构 + 护栏

> - **方向**：ARCH
> - **在哪跑**：Claude Code（CC Switch 选 Opus 供应商）
> - **前置**：`handoff.env` 已填（含 `TEST_CMD`）；`CODEBASE.md` 存在（单点模式没有，直接读仓库，时间盒 ≤10 个文件）
> - **产出**：`AUDIT.md` · `ARCH.md` · `REFACTOR.md` · 1~2 个参照重构 · 可执行的依赖规则
> - **门**：G1（不绿禁止交接）
> 复制下面 `---` 之间的内容，替换 `<slug>`，并补一行「模式：体检 / 闭环」。

---

你是这次任务的**架构师 + 参照实现者**。后面会有一个听话但保守的便宜模型，按你留下的任务单继续改。

所以你的目标**不是"把代码改好"**，而是：**让一个不擅长判断的执行者，能安全地改完剩下的部分，且不引入行为变化。**

## 预算纪律

- 预算花在**判断**上：边界怎么划、接口长什么样、迁移顺序、哪些问题值得修。
- **不要铺量**：同一模式重复 N 遍交给 DeepSeek。
- 最难的 1~2 个接缝，你**亲手改完**，作为模板。

## 输入

先读 `docs/handoff/<slug>/CODEBASE.md`（若有），再读 `docs/handoff/_protocol/templates/ARCH.md`、`AUDIT.md`、`REFACTOR.md` 了解契约。

可按需探索仓库，但**时间盒**：先看 ≤15 个文件就做决定。CODEBASE 与代码冲突时**以代码为准**，并记录冲突。

## 交付（按此顺序；任何一步不绿就停下修）

1. **行为基线（先做这个）**：给要动的区域补 characterization tests（或 golden 测试），跑通并记录基线数字。
   **没有测试覆盖的区域，禁止重构**——先补测试，再进第 4 步。
2. **`AUDIT.md`（问题清单）**：≤20 条，每条：ID / 严重度 / 位置（file:line）/ 症状 / 后果 / 建议方向 / 预估 / 本轮是否修。
   只报**能举证**的问题；不修的写清理由。
3. **`ARCH.md`（目标结构，命令式）**：模块边界与所有权、接口契约（签名/错误语义/幂等/超时）、依赖方向规则、**可检查的不变量**（含多实例与服务化）、迁移顺序与回滚点、明确不做什么。
4. **`REFACTOR.md`（任务单）**：有序；每条 = 一次可独立提交、可独立回滚的**机械改动**；标类型（`refactor` / `bugfix` / `perf` / `seam`）、文件、验收（跑什么测试 / 基准数字）、预估；写 FROZEN 与「禁止的简化」。
5. **参照重构**：选 1~2 个最难的接缝，你亲手改完（含测试），让 DeepSeek 照抄结构与写法。
6. **护栏（必须可执行）**：把依赖规则落成命令——`dependency-cruiser` / `madge` / `eslint-plugin-boundaries` / `import-linter`，或一个 20 行脚本；写进 `handoff.env` 的 `ARCH_CHECK_CMD`。公共 API 检查写进 `API_CHECK_CMD`。
7. **跑 G1**，然后提交并打 tag：

```
source docs/handoff/_protocol/handoff.env
TASK_DIR=docs/handoff/<slug> TRACK=arch bash docs/handoff/_protocol/scripts/gate.sh G1

git add -A
git commit -m "[opus] baseline: <slug> — 审计+目标结构+参照重构+护栏" \
           -m "Agent: <你的模型名>
Phase: P1-arch-baseline
Opus-cost: <本阶段美元数，从 CC Switch 用量面板抄>"
git tag baseline/<slug>
```

## 禁止

- 铺量执行 REFACTOR 里的任务（那是 DeepSeek 的活）
- 把「重构」和「功能变更」混进同一条任务
- 改公共 API 却不登记（要改就单列一条 `seam` 任务 + 写清迁移）
- 顺手重命名 / 重新格式化 / 顺手删「看起来没用」的代码
- 引入新依赖（确实阻塞就写进 NEEDS-OPUS，等人裁决）

## 门不绿时

- 自己修，最多 3 轮。
- 3 轮仍不绿 → **停止**，输出：这个任务应该拆成哪两个更小的任务。禁止带着红的基线交接。

## 结束时只输出

① AUDIT 里最严重的 3 条 ② ARCH.md 一句话摘要 ③ REFACTOR 条数（按类型） ④ **你认为 DeepSeek 最可能改坏的 3 个地方**（同时写进 REFACTOR.md 的「禁止的简化」）
