# TRACK-ARCH · 架构 / bug / 性能轨道

> 共享准备（安装、`handoff.env`、测试基线、`ARCH_CHECK_CMD`）见 [QUICKSTART.md](QUICKSTART.md)。
> 本文件只写 ARCH 轨道从开任务到交付的每一步：**谁 · 在哪 · 做什么 · 命令 · 期望输出 · 失败怎么办**。

**用哪套 prompt**：`docs/handoff/_protocol/prompts/P0~P3-arch-*.md`
**用哪套模板**：`templates/CODEBASE.md` · `AUDIT.md` · `ARCH.md` · `REFACTOR.md`

---

## 0. 三种用法（先选一个）

| 用法 | 阶段 | 产出 | 什么时候用 |
|---|---|---|---|
| **体检** | P0 → P1（只出 AUDIT） | `AUDIT.md`：问题清单 + 严重度 | 先让 Opus 指出问题，你决定修哪些；不写代码 |
| **闭环** | P0 → P1 → P2 → P3 | AUDIT + ARCH + REFACTOR + 参照重构 + 铺量 | 要真正改完一部分，且改动跨 ≥3 个模块 / ≥10 个文件 |
| **单点** | P1 → P2 | 根因 + 失败测试 + 一条任务 | 单个 bug / 单个性能问题（同样写 AUDIT / ARCH / REFACTOR，只是都很短：AUDIT 写根因，ARCH 写一句话目标 + 相关不变量，REFACTOR 只有一条任务） |

> **没有测试的仓库只能做「体检」。** 重构的安全网是测试，不是模型自觉。

---

## Step 0 · 开分支、建任务目录

```bash
cd ~/Desktop/TAAS
git switch -c feat/<slug>            # slug 例：order-idempotency
mkdir -p docs/handoff/<slug>
cp docs/handoff/_protocol/templates/{CODEBASE,AUDIT,ARCH,REFACTOR}.md docs/handoff/<slug>/
source docs/handoff/_protocol/handoff.env
```

期望：四份文件都在；`TEST_CMD` 能跑通，并且**输出里有真实测试数量**（如 `Tests 128 passed`）。
如果命令静默通过、没有任何测试输出 → 这个仓库没有测试，只能做「体检」，不能进 P2。

---

## Step 1 · P0 测绘代码库 [闭环 / 体检]

| 项目 | 内容 |
|---|---|
| 谁 | DeepSeek |
| 在哪 | DeepSeek Harness |
| 输入 | 仓库本身 |
| 产出 | `docs/handoff/<slug>/CODEBASE.md` |
| 门 | **G0**：测试命令能跑，基线数字已记录 |

贴 `docs/handoff/_protocol/prompts/P0-arch-codebase.md` 的正文，替换 `<slug>` 和一句话目标。

**你验收 3 件事**：

1. 每条结论都带 `file:line` 或命令输出（没有证据的写「未验证」）。
2. 测试基线有具体数字（总数 / 通过数 / 耗时 / 已知 flaky）。
3. 「运行时拓扑与多实例」那一节不是空的——进程内状态、定时任务、锁、幂等都要标出来。

---

## Step 2 · P1 审计 + 目标设计 + 参照重构 + 护栏 [都要]

| 项目 | 内容 |
|---|---|
| 谁 | **Opus** |
| 在哪 | **Claude Code** |
| 输入 | `CODEBASE.md` + 仓库（时间盒 ≤15 个文件） |
| 产出 | `AUDIT.md` · `ARCH.md` · `REFACTOR.md` · 1~2 个参照重构 · 可执行的依赖规则 |
| 门 | **G1（不绿禁止交接）** |

贴 `docs/handoff/_protocol/prompts/P1-arch-design.md` 的正文，替换 `<slug>`，并补一行「模式：体检 / 闭环 / 单点」。

**这一步是整套流程的核心**：Opus 要做的不是「把代码改好」，而是四件事：

1. **指出问题**（`AUDIT.md`）：≤20 条，每条带 `file:line` + 后果 + 严重度。
2. **定目标结构**（`ARCH.md`）：模块边界、接口契约、依赖方向、**可检查的不变量**（多实例 / 服务化）。
3. **亲自闭环最难的一段**（参照重构）：选 1~2 个最难的接缝，Opus 亲手改完 + 补测试，作为 DeepSeek 的模板。
4. **留下护栏**：把依赖规则落成 `ARCH_CHECK_CMD`，公共 API 检查落成 `API_CHECK_CMD`。

**交接前必须做完这 3 件：**

1. **你本人看一眼参照重构。** 它是不是真的做到了「边界清晰、行为不变、测试覆盖」？这是 DeepSeek 的天花板。
2. 跑 G1：

```bash
TASK_DIR=docs/handoff/<slug> TRACK=arch bash docs/handoff/_protocol/scripts/gate.sh G1
```

期望最后一行 `== 结果: ✓ 全绿 ==`，退出码 0。
`ARCH_CHECK_CMD` 未设置会警告——**警告不等于通过**，架构规则没落地就别进 P2。

3. 绿了才提交 + 打 tag：

```bash
git add -A
git commit -m "[opus] baseline: <slug> — 审计+目标结构+参照重构+护栏" \
  -m "Agent: claude-opus-5-5
Phase: P1-arch-baseline
Opus-cost: \$X.XX（CC Switch 用量面板）"
git tag baseline/<slug>
```

**G1 不绿怎么办：**

1. 让 Opus 继续修，最多 3 轮。
2. 3 轮仍红 → **不要交接**。把任务拆成两个更小的（按模块 / 按依赖方向），重开 slug。
3. 没有测试覆盖的区域，**先补 characterization tests**，不许硬改。

---

## Step 3 · P2 机械重构 [闭环 / 单点]

| 项目 | 内容 |
|---|---|
| 谁 | DeepSeek |
| 在哪 | **DeepSeek Harness** |
| 输入 | `ARCH.md` · `REFACTOR.md` · 参照重构源码 |
| 产出 | 逐条任务的代码，一条任务一条提交 |
| 门 | **G2**（测试必须绿） |

贴 `docs/handoff/_protocol/prompts/P2-arch-refactor.md` 的正文，替换 `<slug>`。

**它的循环**：取第一条 `todo` → 只改点名文件 → 跑 G2 → 绿了提交 → `done` → 下一条。

**你只需要做一件事**：每 2~3 条任务抽查一次 diff，确认它没有「顺手重命名 / 顺手格式化 / 顺手改行为」。

G2 命令：

```bash
TASK_DIR=docs/handoff/<slug> BASE_TAG=baseline/<slug> TRACK=arch \
  bash docs/handoff/_protocol/scripts/gate.sh G2
```

**G2 红了怎么办：**

| 症状 | 处理 |
|---|---|
| 测试失败 | `git revert <那一条提交>`；让 DeepSeek 重做，不许改测试来迁就实现 |
| `FROZEN 被修改` | revert；确实要动就记 NEEDS-OPUS，等 P3 裁决 |
| `有依赖变动` | revert；除非你显式授权 |
| `ARCH_CHECK_CMD` 失败 | 说明它绕过了边界（常见：用 `any` / 深路径 import）；revert 并写进「禁止的简化」 |
| 同一任务连续 2 次红 | 标 `blocked` 跳过，不要死磕 |

---

## Step 4 · P3 复审 [闭环]

| 项目 | 内容 |
|---|---|
| 谁 | **Opus** |
| 在哪 | **Claude Code** |
| 输入 | diff + 测试/架构检查输出 + NEEDS-OPUS 队列 |
| 产出 | NEEDS-OPUS 裁决 + `POLISH.md`（≤10 条机械修改）+ 下一轮补哪条不变量 |
| 预算 | ≤ 整个任务 Opus 用量的 15% |

贴 `docs/handoff/_protocol/prompts/P3-arch-review.md` 的正文，替换 `<slug>`。

然后把 `POLISH.md` 贴给 DeepSeek 执行（每条一提交），最后：

```bash
TASK_DIR=docs/handoff/<slug> BASE_TAG=baseline/<slug> TRACK=arch \
  bash docs/handoff/_protocol/scripts/gate.sh G3
git tag handoff/<slug>
```

G3 硬性要求：`todo` / `doing` / `blocked` / `NEEDS-OPUS` 全部清零（裁决后改 `done`，不做改 `dropped`）。

---

## Step 5 · 收尾与记账 [5 分钟]

1. 在 `REFACTOR.md` 第 7 节记一行：日期 / Opus 花费 / AUDIT 条数 / 修了几条 / NEEDS-OPUS / POLISH / 首轮是否通过。
2. **把 `ARCH.md` 的不变量和代码对齐**：这一轮实际落地了哪几条，哪几条只是写在纸上。
3. 按 [PROTOCOL.md](PROTOCOL.md) 的「度量与调参」判断下一轮是把 Opus 切点上移还是下移。
4. 合并分支。

---

## 任务类型规则（写 REFACTOR 时按这个）

| 类型 | 允许行为变化 | 必须有的验收 | 禁止 |
|---|---|---|---|
| `refactor` | **不允许** | 全量测试绿 + 架构检查绿 | 顺手改行为 / 顺手重命名 |
| `bugfix` | 只允许修 bug 本身 | **先有失败测试**，修完全绿 | 修完顺手重构 |
| `perf` | 只允许性能特征变化 | 改前/改后基准数字 + 测试绿 | 用「看起来更快」代替数字 |
| `seam` | 允许改公共 API | 单独迁移任务 + 调用方全部更新 + `API_CHECK_CMD` | 和其他任务合并提交 |

---

## 架构不变量清单（多机 / 服务化）

> 这是「任何地方都很合理、松耦合、无潜藏隐患」的落地版。写进 `ARCH.md` 第 5 节，每条都要写**检查方式**；写不出检查方式的，降级为 code review 条目。

**边界与依赖**
- domain 不依赖 infra / 框架；跨模块只依赖接口，不依赖实现
- 无循环依赖；依赖方向单向
- 模块只通过公开入口被引用（禁止深路径 import）

**状态与多实例**
- 请求处理不依赖进程内可变状态（内存缓存 / 全局单例）
- 写操作幂等（幂等键 / 唯一约束），重试安全
- 定时任务多实例安全（选主 / 分布式锁）
- 本地文件、内存队列不承载「必须持久」的数据

**失败与重试**
- 所有跨进程调用有超时
- 重试只用于幂等操作；重试有上限和退避
- 失败可隔离：一个下游挂了不拖垮整条链路（熔断 / 降级）

**数据一致性**
- 事务边界明确且最小；不在事务里做网络调用
- 跨服务要么 outbox / saga，要么明写「最终一致」和补偿方式

**可观测性**
- 关键路径有结构化日志 + traceId
- 关键失败有指标 / 告警

**可测试性**
- 核心逻辑不依赖 IO / 框架，可单测
- 模块边界有契约测试

---

## 禁止清单（P2 期间）

1. 改公共 API 签名（除任务点名）
2. 顺手重命名 / 重新格式化 / 删「看起来没用」的代码
3. 用 `any` / 类型断言 / 深路径 import 绕过边界检查
4. 改测试来迁就实现（测试是契约）
5. 把两条任务合并提交
6. 新增依赖
