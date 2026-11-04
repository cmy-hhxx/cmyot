# P1 · 贴给 Opus：定调 + 参照实现 + 绿着交接

> - **方向**：UI（动效 / UI / 展示）
> - **在哪跑**：Claude Code（CC Switch 选 Opus 供应商，如 `cmy` → gengxi.ai / `claude-opus-5-5`）
> - **前置**：`BRIEF.md` 存在（Lite 模式没有 BRIEF，直接读仓库，时间盒 ≤10 个文件）；`handoff.env` 已填
> - **产出**：令牌文件 · `DESIGN.md` · 1~2 个参照实现 · 全屏骨架 · `HANDOFF.md`
> - **门**：G1（不绿禁止交接）
> 复制下面 `---` 之间的内容，替换 `<slug>`，并在开头补一行「模式：Full / Lite」。

---

你是这次任务的**视觉与动效定调者 + 参照实现者**。后面会有一个便宜模型照着你留下的东西铺量。

所以你的目标**不是「做完这个功能」**，而是：**让一个听话但不聪明的执行者，能把剩下的部分做对。**

## 预算纪律

- 预算优先花在**设计与参照实现**上。
- **不要铺量**：除主屏外，其他屏只做「能渲染、能截图」的静态骨架。
- 不要为了「完整性」把同一模式重复 N 遍，那是浪费。

## 输入

先读 `docs/handoff/<slug>/BRIEF.md`（若有），再读 `docs/handoff/_protocol/templates/DESIGN.md`、`docs/handoff/_protocol/templates/HANDOFF.md` 了解契约。

可按需探索仓库，但**时间盒**：先看 ≤10 个文件就做决定，不要读全仓。
BRIEF 与代码冲突时**以代码为准**，并在 HANDOFF 里记一条冲突说明。

## 交付（按此顺序；任何一步不绿就停下修，禁止带着不可运行的状态交接）

1. **令牌单一真相**：颜色 / 字号 / 间距 / 圆角 / 阴影 / 时长 / 缓动，落成代码文件（`tokens.css` / `theme.ts` 之类）。已有设计系统就复用，只加 delta。`DESIGN.md` 里所有值必须引用它。
2. **`DESIGN.md`（命令式规范，不是散文）**：视觉意图（≤3 句，含一个具体参照物）、布局网格、组件清单、**动效表**（每个动效一行，含数值）、不变量（Must / Never）、禁止的简化（含原因）、响应式断点与 `prefers-reduced-motion` 降级。
3. **参照实现**：选 1~2 个最难 / 最能代表风格的组件或动效，写**完整可运行**版本。DeepSeek 会照抄它，所以它必须代表你想要的最终质量。
4. **全屏静态骨架**：每条路由 / 每个屏都有一份可渲染、可截图的实现（文案占位无所谓，但要能看出布局）。主屏可以做得较完整。
5. **跑 G1 门**（先确认 dev server 在 `STILLS_URL` 上跑着）：
   `source docs/handoff/_protocol/handoff.env`
   `TASK_DIR=docs/handoff/<slug> bash docs/handoff/_protocol/scripts/gate.sh G1`
   查：零 console error / 3 个视口（1440·834·390）截图不塌 / 主视觉动效两帧截图字节不同（证明在动）/ `prefers-reduced-motion: reduce` 下可用 / typecheck 与 build 通过。
6. **写 `HANDOFF.md`**：按模板。TODO 必须**有序**，每条带目标文件、验收标准、预估量；`FROZEN` 明确到文件或选择器并写清「为什么不能动」；「禁止的简化」写清原因；NEEDS-OPUS 留空待 P2 填。
7. **提交并打 tag**：

```
git add -A
git commit -m "[opus] baseline: <slug> — 规范+参照实现+全屏骨架" \
           -m "Agent: <你的模型名>
Phase: P1-baseline
Opus-cost: <本阶段美元数，从 CC Switch 用量面板抄；不要用 /cost，relay 下不准>"
git tag baseline/<slug>
```

## 禁止

- 实现 HANDOFF 里列为铺量性质的 TODO（那是 DeepSeek 的活）
- 重构既有代码
- 引入新依赖（确实阻塞就写进 HANDOFF 的 NEEDS-OPUS，等人工裁决）
- 在规范里使用「高级感 / 呼吸感 / 流畅 / 有质感」等**不可执行**的词——每个形容词都会变成执行者的一次自由发挥

## 门不绿时

- 自己修，最多 3 轮。
- 3 轮仍不绿 → **停止**，输出：这个任务应该拆成哪两个更小的任务（按屏 / 按组件）。不要带着红的基线交接。

## 结束时只输出

① `DESIGN.md` 的 3 句话摘要 ② 当前门状态（G1 逐条） ③ TODO 条数 ④ **你认为 DeepSeek 最可能做错的 3 个地方**（这 3 条请同时写进 HANDOFF.md 的「禁止的简化」）
