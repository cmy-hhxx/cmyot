# Opus → DeepSeek 接力协议（UI / ARCH 双轨道）

> **目标**：花 DeepSeek 的钱，拿 Opus 80~90% 的产出——UI 轨道拿视觉，ARCH 轨道拿架构质量。
> **形态**：一套可拷进任意 git 仓库的流程 + 文件契约，不依赖特定工具链。
> **怎么操作**：UI 看 [TRACK-UI.md](TRACK-UI.md)，ARCH 看 [TRACK-ARCH.md](TRACK-ARCH.md)；共享准备看 [QUICKSTART.md](QUICKSTART.md)。
> **为什么这样设计**：见 [THINKING.md](THINKING.md)。

---

## 0. 核心原则：按「判断」切，不按百分比切

> **凡是有判断的，Opus 做；凡是照抄判断的，DeepSeek 做。**

两个方向都成立，只是「判断」和「复制」的内容不同：

| | 判断（Opus） | 复制（DeepSeek） |
|---|---|---|
| **UI** | 配色定调、动效曲线、布局取舍 | 第 2~20 个同构组件、断点收敛、补 hover 态 |
| **ARCH** | 边界怎么划、接口长什么样、先改哪、哪些问题值得修 | 同一种机械改动的 N 个调用点、拆文件、改 import、补测试 |

按这条线切完，「Opus 占了百分之多少」是自动算出来的。硬按代码量切会撞上同一个结构性错误：**最需要判断的「最后那一段是否忠于原意图」，恰恰留给了最便宜的模型**。

所以形状不是「Opus 写 70% → DeepSeek 收尾」，而是：

```
Opus 定调（规范 / 边界 / 参照实现 / 护栏）      ← 判断，贵，但不铺量
        ↓  tag baseline/<slug>，状态必须绿
DeepSeek 铺量（照抄，逐条任务，一提交一条）      ← 机械，便宜，占工作量的大头
        ↓
Opus 短审（裁决批量问题 + 改规则 + POLISH）      ← 判断，预算上限 15%
        ↓
DeepSeek 执行 POLISH（纯机械修改）
        ↓  G3 全绿后：tag handoff/<slug>
```

**如果 Opus 的预算只够做三件事**：砍掉骨架 / 减少参照实现数量，但**规范、单一真相、至少一个参照实现必须全做**。它们才是可被复制的「标准」。

### 0.1 两个方向（每个任务开始时由人指定）

| | UI 轨道 | ARCH 轨道 |
|---|---|---|
| 用来做 | 动效 / UI / 展示 | 架构审计 / 重构 / bug / 性能 |
| 门 | 截图门（3 视口 / 在动 / console） | 测试门（全绿 / 依赖规则 / 公共 API） |
| Runbook | [TRACK-UI.md](TRACK-UI.md) | [TRACK-ARCH.md](TRACK-ARCH.md) |
| Prompts | `prompts/P0~P3-ui-*.md` | `prompts/P0~P3-arch-*.md` |
| 模板 | BRIEF / DESIGN / HANDOFF | CODEBASE / AUDIT / ARCH / REFACTOR |

**两个方向都不适用**：一次性创意页面（没有复制段）、纯数据/文案改动（没有判断）。

### 0.2 模式

| 方向 | 模式 | 阶段 | 触发条件 |
|---|---|---|---|
| UI | **Full** | P0 → P1 → P2 → P3 | ≥6 个同构元素 / ≥3 屏 / 需新建设计系统 |
| UI | **Lite** | P1 → P2 | 1~2 屏 / <6 个同构元素 / 复用现有设计系统 |
| ARCH | **体检** | P0 → P1（只出 AUDIT） | 只想先知道问题在哪；或仓库没有测试 |
| ARCH | **闭环** | P0 → P1 → P2 → P3 | 要真改，且跨 ≥3 个模块 / ≥10 个文件 |
| ARCH | **单点** | P1 → P2（P3 可选） | 单个 bug / 单个性能问题 |

### 0.3 术语

| 术语 | 含义 |
|---|---|
| **参照实现 / 参照重构** | Opus 亲手做的 1~2 个「达到最终质量」的样例，是 DeepSeek 唯一能照抄的品味/质量载体 |
| **单一真相** | UI：令牌文件；ARCH：接口契约 + 不变量清单。执行者只能引用，不能另起一套 |
| **FROZEN** | DeepSeek 禁止修改的文件 / 选择器 / 接口，每项都要写「为什么」 |
| **NEEDS-OPUS** | DeepSeek 遇到需要判断的地方时记的问题队列，攒 3~5 条批量问 |
| **门（G0~G3）** | 可执行的验收检查，不绿不许进下一阶段 |
| **基线（baseline tag）** | Opus 交接点的 git tag，之后所有改动都能拿它做 diff 和回滚 |
| **行为基线** | 重构前必须存在的测试，用来证明「改完行为没变」 |

### 0.4 客户端分工（固定，不要混）

| 阶段 | 客户端 | 模型 | 理由 |
|---|---|---|---|
| P0 | DeepSeek Harness | DeepSeek | 只读不写代码，最便宜 |
| P1 | Claude Code（CC Switch 选 Opus 供应商） | Opus | 需要判断，还要能跑测试 / build / git tag |
| P2 | DeepSeek Harness | DeepSeek | 干净壳：没有 Claude 插件和全局 CLAUDE.md 的「顺手优化」 |
| P3 | Claude Code | Opus | 只做判断，预算 ≤15% |

> **P2 不要放在 Claude Code 里跑。** 全局 `CLAUDE.md` 和 `frontend-design` / `code-simplifier` 插件会持续建议「改进」，跟 P2 唯一的纪律「照抄，不优化」直接冲突。详见 [THINKING.md](THINKING.md)。

---

## 1. 目录约定

协议文件装在仓库里，跟着代码走、可 diff、可回滚：

```
<repo>/
└── docs/handoff/
    ├── _protocol/          ← 本协议（一次性安装，随仓库演进）
    │   ├── README.md
    │   ├── QUICKSTART.md
    │   ├── TRACK-UI.md
    │   ├── TRACK-ARCH.md
    │   ├── PROTOCOL.md
    │   ├── THINKING.md
    │   ├── handoff.env     ← 本仓库的门命令（从 scripts/handoff.env.example 复制）
    │   ├── prompts/        ← UI / ARCH 各四份 prompt
    │   ├── templates/      ← UI 三份 + ARCH 四份
    │   ├── scripts/        ← gate.sh · handoff.env.example · stills.mjs · still-pause.js
    │   └── examples/       ← 填好的示例
    └── <slug>/             ← 每个任务一个目录
        │  ── UI 轨道 ──
        ├── BRIEF.md        ← P0（仅 Full）
        ├── DESIGN.md       ← P1
        ├── HANDOFF.md      ← P1 写，P2 更新状态，P3 裁决
        ├── POLISH.md       ← P3
        ├── stills/         ← 3 视口截图
        │  ── ARCH 轨道 ──
        ├── CODEBASE.md     ← P0（闭环 / 体检）
        ├── AUDIT.md        ← P1 问题清单
        ├── ARCH.md         ← P1 目标结构 + 不变量
        ├── REFACTOR.md     ← P1 任务单，P2 更新状态，P3 裁决
        └── POLISH.md       ← P3
```

**谁改哪份文件**：

| 文件 | 写的人 | 其他角色 |
|---|---|---|
| `BRIEF.md` / `CODEBASE.md` | DeepSeek（P0） | 只读 |
| `DESIGN.md` / `ARCH.md` / 令牌 / 参照实现 | Opus（P1） | DeepSeek 只读；P3 可改规则 |
| `HANDOFF.md` / `REFACTOR.md` §1 §2 §3 §6 | Opus（P1） | P2 更新门状态 |
| `HANDOFF.md` / `REFACTOR.md` §4 状态列、§5 假设 | DeepSeek（P2） | — |
| §5 裁决列、`POLISH.md` | Opus（P3） | DeepSeek 执行 POLISH |

---

## 2. Git 约定（没有这个就没法度量、没法回滚）

- 分支：`feat/<slug>`
- 提交前缀：`[opus]` / `[ds]`，**一条任务一提交**（这是回滚粒度的下限）
- 提交 trailer 固定三行：

```
[ds] R03: 修订单幂等失效
Agent: deepseek-v4.1
Phase: P2-arch-refactor
TASK: R03
```

- 两个 tag：`baseline/<slug>`（Opus 交接点）、`handoff/<slug>`（交付点）
- 成本记账：**从 CC Switch 用量面板抄美元数**（本地库 `~/.cc-switch/cc-switch.db` 的 `proxy_request_logs` / `usage_daily_rollups`）。**不要用 Claude Code 的 `/cost`**——relay 下它按 Anthropic 牌价估算，不是你实际付的钱。

---

## 3. UI 轨道：四个阶段与门

### P0 — DeepSeek 出 `BRIEF.md`（仅 Full）

**目的**：让 Opus 不用花贵 token 读代码。要求**先跑再说**。

- 产出：`BRIEF.md`（≤200 行，按 `templates/BRIEF.md`）
- 门 **G0**：仓库能装、typecheck / build 通过（dev 在 P1 起服务时验证）
- 禁止：做设计决策、提改进建议、改代码

### P1 — Opus 定调（贵，必须绿着交接）

按 A/B/C/D 顺序交付：

| # | 交付物 | 为什么必须是它 |
|---|---|---|
| A | **令牌文件**（tokens.css / theme.ts） | 文档里写值会被忽略，代码里引用会被继承 |
| B | `DESIGN.md`：**命令式**规范 | 散文式设计文档不可执行 |
| C | **参照实现**：1~2 个最难/最代表风格的组件或动效，完整可运行 | DeepSeek 只会照抄它看得见的东西 |
| D | **全屏静态骨架**：每屏都能渲染、能截图 | 防止 DeepSeek 自己发明页面结构 |

- **门 G1**：零 console error · 3 视口不塌 · 主视效确实在动 · reduced-motion 截图产出（人工看） · typecheck / build 通过
- 提交 + `git tag baseline/<slug>`
- **禁止**：铺量、重构既有代码、引入新依赖
- **G1 连续 3 轮不绿**：拆任务，禁止带红基线进 P2

### P2 — DeepSeek 铺量

一次一条 TODO：取 `todo` → 只改点名的文件 → 跑 G2 → 绿了提交 → `done`。

**硬规则**：`DESIGN.md` 是法律；照抄不优化；FROZEN 不碰；禁新增依赖/裸值；需要新视觉模式 → `NEEDS-OPUS`；同一 TODO 2 次红 → `blocked`。

- 门 **G2**：G1 的全部 + 未触碰 FROZEN + 无新依赖（含未提交的新文件）

### P3 — Opus 短审（仅 Full，≤15%）

- 输入：diff、截图、NEEDS-OPUS 队列
- 产出：NEEDS-OPUS 逐条裁决 + `POLISH.md`（≤10 条机械修改）
- 收尾：DeepSeek 执行 POLISH → G3 → `handoff/<slug>`

---

## 4. ARCH 轨道：四个阶段与门

### P0 — DeepSeek 测绘 `CODEBASE.md`（体检 / 闭环）

**目的**：让 Opus 不用读全仓就能审计。**每条结论带 `file:line`**。

- 产出：`CODEBASE.md`（≤250 行，按 `templates/CODEBASE.md`）
- 必须包含：真实命令与测试基线数字、模块地图、依赖关系、**运行时拓扑与多实例**、现有约定、风险候选 ≤10
- 门 **G0**：测试命令能跑，基线数字已记录
- 禁止：做设计决策、提方案、改代码

### P1 — Opus 审计 + 目标设计 + 参照重构 + 护栏（核心）

| 交付物 | 内容 | 为什么必须是它 |
|---|---|---|
| `AUDIT.md` | ≤20 条问题：位置 / 症状 / 后果 / 严重度 / 建议方向 / 本轮修不修 | 「指出问题」是这轮的核心价值 |
| `ARCH.md` | 模块边界、接口契约、依赖方向规则、**可检查的不变量**（多实例 / 服务化）、迁移顺序与回滚点 | 把「松耦合」翻译成可执行规则 |
| `REFACTOR.md` | 有序任务单：一条任务 = 一次可独立提交、可回滚的机械改动；标类型 | DeepSeek 的施工图 |
| **参照重构** | Opus 亲手改完 1~2 个最难的接缝 + 补测试 | DeepSeek 唯一能照抄的质量载体 |
| **护栏** | `ARCH_CHECK_CMD`（依赖方向 / 无环 / 边界）+ `API_CHECK_CMD` | 没有机器检查的「松耦合」都是口号 |

- **门 G1**：全量测试绿 · 架构检查绿 · 公共 API 无破坏 · 参照重构完成 · typecheck / build 通过
- 提交 + `git tag baseline/<slug>`
- **禁止**：铺量、把重构和功能变更混在一条任务、改公共 API 不登记、顺手重命名、引入新依赖
- **前置硬条件**：要动的区域必须有测试；没有就先补 characterization tests

### P2 — DeepSeek 机械重构

一次一条任务：取 `todo` → 只改点名的文件 → 跑 G2 → 绿了提交 → `done`。

**硬规则**：
1. 行为不变（`bugfix` / `perf` 任务除外，验收里写明允许变化）
2. `bugfix` 先写失败测试；`perf` 先记基准
3. FROZEN 不碰；禁改公共 API；禁新增依赖
4. 不顺手重命名 / 格式化 / 删「看起来没用」的代码
5. 需要新抽象 / 新边界 → `NEEDS-OPUS`，不要自己发明
6. 同一任务 2 次红 → `blocked`

- 门 **G2**：测试绿 + 架构检查绿 + 未触碰 FROZEN + 无新依赖 + 无未登记的公共 API 变更

### P3 — Opus 复审（闭环，≤15%）

- 输入：diff、测试/检查输出、NEEDS-OPUS 队列
- 任务：裁决 NEEDS-OPUS；检查 `ARCH.md` 与代码是否一致；检查「假松耦合」；写 `POLISH.md`
- 收尾：DeepSeek 执行 POLISH → G3 → `handoff/<slug>`

---

## 5. 防退化机制

**通用（两轨道）**

1. **规则命令式**：写数值、写接口签名、写检查命令，不写「优雅 / 松耦合 / 有呼吸感」。
2. **单一真相**：UI 是令牌文件；ARCH 是接口契约 + 不变量清单。执行者只能引用。
3. **冻结清单**：明确到文件 / 选择器 / 接口，写清「为什么不能动」。
4. **参照实现**：Opus 必须亲手做一个达到最终质量的样例。
5. **提交记账**：trailer + tag，事后能算「每个模型花了多少、退回几次」。
6. **人工检查点**：P1 交接、P2 中途、P3 结束。

**UI 专属**

7. **截图门**：固定视口 + 固定动画时刻，退化必须看得见。
8. **禁止的简化**：写清「为什么这里看起来能合并但不能合并」。

**ARCH 专属**

9. **行为基线**：重构前必须有测试；测试是唯一能证明「行为没变」的东西。
10. **护栏命令**：依赖方向 / 无环 / 公共 API 必须落成可执行检查。
11. **一条任务一次提交**：不允许一条大提交改完所有，否则无法回滚、无法审。
12. **任务类型约束**：`refactor` 不改行为；`bugfix` 先失败测试；`perf` 先基准；`seam` 单独迁移。

---

## 6. 失败处置

| 情况 | 动作 |
|---|---|
| 基线不绿就想交接 | **禁止**。宁可再给 Opus 一段预算把 G1 跑绿 |
| G1 修 3 轮仍不绿 | 任务太大。按屏 / 按模块拆成两个任务，重开 slug |
| 某条任务做坏 | `git revert <那一条提交>`，不要 `git reset` |
| DeepSeek 顺手重构 / 美化 | `git reset --hard baseline/<slug>`，换干净壳（DSH）重跑 P2 |
| 需要回退整个 P2 | `git reset --hard baseline/<slug>`（P2 之前没有人类审过的改动） |
| 要升级回 Opus | 同一任务连续 2 次失败 / 需要新视觉模式或新边界 / 主观判断。**批量攒 3~5 条一次问** |
| ARCH：没有测试就想重构 | **禁止**。先做体检，或先补 characterization tests |
| ARCH：DeepSeek 改了测试来迁就实现 | revert + 写进「禁止的简化」；测试是契约 |
| 中途发现该用 Lite / 体检 | 砍掉 P3，P2 后直接 G3 收尾（UI Lite） / 停在 P1 交付 AUDIT（ARCH 体检） |

---

## 7. 度量与调参

每个任务在 `HANDOFF.md` / `REFACTOR.md` 末尾记一行。

**UI**：日期 / Opus 花费 / Opus 代码占比 / NEEDS-OPUS / POLISH 条数 / 首轮是否通过
**ARCH**：日期 / Opus 花费 / AUDIT 条数 / 修了几条 / NEEDS-OPUS / POLISH 条数 / 首轮是否通过

调参规则：

- **NEEDS-OPUS > 8 或 POLISH > 20** → 规范 / 参照实现 / 规则不够。切点上移
- **NEEDS-OPUS ≤ 2 且 POLISH ≤ 5** → 切点可下移
- **首轮 POLISH 就通过** → 执行者已能守规则，把更多任务交给它
- **Opus 花费超过总量 40%** → P1 范围失控（或在用重流程跑小任务），下轮降档
- **ARCH 专项**：`AUDIT` 里 P0/P1 问题多但本轮没修 → 下一轮先修 P0/P1，别加新功能
- **ARCH 专项**：`ARCH_CHECK_CMD` 规则被反复绕过 → 不是执行者的问题，是规则没写成可执行检查

「80~90% 效果」的验收：同一需求做两版（Opus 全量 vs 接力），盲对比。UI 看截图，ARCH 看测试覆盖 + diff 质量 + 架构检查结果。

---

## 8. 反模式清单

**通用**

1. 让 Opus 写全量、再让 DeepSeek「优化」——最贵，且优化必破坏
2. 散文式规范——不可执行，等于没写
3. 交接时状态不绿
4. 一条一条问 Opus——上下文重建成本 >> 答案价值
5. 用聊天记录传意图——不可审计、不可 diff、不可回滚
6. 用 Full / 闭环模式跑一次性小任务——没有复制段，纯亏

**UI**

7. DeepSeek 顺手重构 / 美化 / 统一风格
8. 没有截图门——退化发生在你看不到的地方
9. 规范里出现「高级感 / 呼吸感 / 流畅」——每个形容词都是一次自由发挥
10. 在 Claude Code 里跑 P2——插件会把「照抄」变成「顺手改进」

**ARCH**

11. **没有测试就重构**——没有任何东西能证明行为没变
12. **只审计不闭环**——问题清单越写越长，代码越来越烂
13. **一次大提交改完**——无法回滚、无法审
14. **用 `any` / 深路径 import 绕过边界**——等于没有边界
15. **改测试来迁就实现**——测试是契约，不是装饰
16. **把「松耦合」写成口号**——写不进 `ARCH_CHECK_CMD` 的规则都不算数
17. **把重构和功能变更混在一条任务**——出问题时无法判断是谁的锅

---

## 9. FAQ

**Q：这套能全自动吗？**
先手工跑 2 个任务，摸清你自己的失败模式，再自动化。自动化会把模糊指令放大。

**Q：Opus 的基线要「精致」到什么程度？**
UI：规范完整、令牌完整、至少一个参照实现达到最终质量、每屏能渲染。
ARCH：AUDIT 有证据、ARCH 规则可检查、至少一个参照重构完成、行为基线存在。

**Q：仓库已有设计系统 / 已有架构怎么办？**
只做增量：UI 复用现有 tokens，ARCH 复用现有边界与接口，**禁止新建体系**；文档只写 delta。

**Q：ARCH 轨道没有测试怎么办？**
只能做「体检」。要闭环，先让 Opus 在 P1 给要动的区域补 characterization tests——补测试本身也可以是一条任务，但必须在重构之前完成。

**Q：ARCH 的「多实例安全」「最终一致」能自动验证吗？**
不能完全。脚本只能查静态规则（依赖方向、循环、API）；多实例安全需要压测 / 故障注入 / 线上证据。所以 `ARCH.md` 里每条不变量都要写「检查方式」，写不出的降级为人工检查项。

**Q：bugfix 也要走这套吗？**
单个 bug 走「单点」：P1 出根因 + 失败测试 + 方案，P2 实施，P3 可选（做就是一次 10 分钟复审）。核心纪律只有一条：**先有失败测试**。

**Q：性能优化怎么验收？**
`perf` 任务必须先记录基准数字（命令 + 改前值），改完给出改后值 + 测试绿。不接受「看起来更快」。

**Q：用第三方 relay 的 Opus 行不行？**
行。前提：(1) 先做能力体检，整套流程的上限由 P1 决定；(2) 成本从 CC Switch 用量面板读，不要信 `/cost`；(3) 代码会过第三方，公司仓库谨慎。

**Q：P2 能不能也在 Claude Code 里跑（切 DeepSeek 供应商）？**
能跑，但不建议：全局 `CLAUDE.md` 和插件会持续建议「改进」，与 P2 的「照抄不优化」冲突。真要这么做，先关掉 `frontend-design` / `code-simplifier`，并在 prompt 开头声明「忽略全局 CLAUDE.md 的改进建议」。
