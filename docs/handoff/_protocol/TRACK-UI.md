# TRACK-UI · 动效 / UI / 展示轨道

> 共享准备（安装、`handoff.env`、playwright、`still-pause.js`）见 [QUICKSTART.md](QUICKSTART.md)。
> 本文件只写 UI 轨道从开任务到交付的每一步：**谁 · 在哪 · 做什么 · 命令 · 期望输出 · 失败怎么办**。

**用哪套 prompt**：`docs/handoff/_protocol/prompts/P0~P3-ui-*.md`
**用哪套模板**：`templates/BRIEF.md` · `DESIGN.md` · `HANDOFF.md`

---

## Step 0 · 开分支、建任务目录

```bash
cd ~/Desktop/TAAS
git switch -c feat/<slug>            # slug 例：hero-motion
mkdir -p docs/handoff/<slug>
cp docs/handoff/_protocol/templates/{BRIEF,DESIGN,HANDOFF}.md docs/handoff/<slug>/
source docs/handoff/_protocol/handoff.env

# Lite 模式用不上 BRIEF，删掉它，免得 P1 去读一个空模板
rm -f docs/handoff/<slug>/BRIEF.md   # 仅 Lite
```

期望：`docs/handoff/<slug>/` 下有 `DESIGN.md` `HANDOFF.md`（Full 还有 `BRIEF.md`）。

---

## Step 1 · P0 写背景 [仅 Full]

| 项目 | 内容 |
|---|---|
| 谁 | DeepSeek |
| 在哪 | DeepSeek Harness |
| 输入 | 仓库本身 |
| 产出 | `docs/handoff/<slug>/BRIEF.md` |
| 门 | **G0**：仓库能装、typecheck / build 通过（dev 在 P1 起服务时验证） |

贴 `docs/handoff/_protocol/prompts/P0-ui-brief.md` 的正文，再补一句：

> 任务名 `<slug>`；要做的功能：`<一句话>`；模式 Full。

**你验收 3 件事**（不满足就让它重跑）：

1. `BRIEF.md` 里每条命令都是它亲手跑过的原文（有真实输出）。
2. 「现有设计系统」列出的是真存在的路径。
3. 最后一节有「3 个必须由人 / Opus 决定的问题」。

---

## Step 2 · P1 定调

| 项目 | 内容 |
|---|---|
| 谁 | **Opus** |
| 在哪 | **Claude Code**。先确认 CC Switch 当前 Claude 供应商是 Opus（`cmy` → gengxi.ai，模型 `claude-opus-5-5`） |
| 输入 | `BRIEF.md`；Lite 模式没有 BRIEF，让它直接读仓库，时间盒 ≤10 个文件 |
| 产出 | 令牌文件 · `DESIGN.md` · 1~2 个参照实现 · 全屏骨架 · `HANDOFF.md` |
| 门 | **G1（不绿禁止交接）** |

贴 `docs/handoff/_protocol/prompts/P1-ui-baseline.md` 的正文，替换 `<slug>`，并在开头加一行「模式：Full / Lite」。

开工前先确认当前 Claude Code 真的指向 Opus：

```bash
jq -r '.env.ANTHROPIC_BASE_URL + "  " + .env.ANTHROPIC_MODEL' ~/.claude/settings.json
# 期望：https://gengxi.ai  claude-opus-5-5
```

**交接前必须做完这 3 件：**

1. **你本人看一眼参照实现。** 它的质感就是整件事的天花板。不满意就让 Opus 继续改参照实现，别往下走。
2. 起 dev server（截图门要访问页面），再跑 G1：

```bash
pnpm dev &        # 或另开一个终端；地址要和 handoff.env 的 STILLS_URL 一致
TASK_DIR=docs/handoff/<slug> bash docs/handoff/_protocol/scripts/gate.sh G1
```

期望最后一行是 `== 结果: ✓ 全绿 ==`，退出码 0。
Full 模式还要 `STILLS_URL` 已设置且 playwright 已装，否则截图门会被跳过（只警告）。

3. 绿了才提交 + 打 tag：

```bash
git add -A
git commit -m "[opus] baseline: <slug>" \
  -m "Agent: claude-opus-5-5
Phase: P1-baseline
Opus-cost: \$X.XX（从 CC Switch 用量面板抄，不要用 /cost）"
git tag baseline/<slug>
```

**G1 不绿怎么办：**

1. 让 Opus 继续修，最多 3 轮。
2. 3 轮仍红 → **不要交接**。把任务拆成两个更小的（按屏 / 按组件），重开一个 slug，从 P1 再来。
3. 永远不要带着红的基线进 P2 —— 这是整套流程最贵的失败模式。

---

## Step 3 · P2 铺量

| 项目 | 内容 |
|---|---|
| 谁 | DeepSeek |
| 在哪 | **DeepSeek Harness**（不要用 Claude Code） |
| 输入 | `DESIGN.md` · `HANDOFF.md` · 参照实现源码；Full 还有 `BRIEF.md` |
| 产出 | 代码主体，每条 TODO 一条提交 |
| 门 | **G2** |

贴 `docs/handoff/_protocol/prompts/P2-ui-build.md` 的正文，替换 `<slug>`。

**它的循环**（知道就行）：取第一条 `todo` → 只改点名的文件 → 跑 G2 → 绿了提交 → 状态改 `done` → 下一条。

**你只需要做一件事**：每 2~3 条 TODO 抽查一次 diff，确认它没有「顺手优化」参照实现。

G2 命令：

```bash
TASK_DIR=docs/handoff/<slug> BASE_TAG=baseline/<slug> \
  bash docs/handoff/_protocol/scripts/gate.sh G2
```

**G2 红了怎么办：**

| 症状 | 处理 |
|---|---|
| `FROZEN 被修改` | `git revert <那一条提交>`；确实需要动就记进 NEEDS-OPUS，等 P3 裁决 |
| `有依赖变动` | 同上；除非你显式授权 |
| 裸色值 / `transition:all` 警告 | 默认只警告。看到就让它改；想变硬门，把 `gate.sh` 第 3.5 / 4 节的 `warn` 改成 `bad` |
| 同一 TODO 连续 2 次红 | 让它标 `blocked` 跳过，继续下一条，不要死磕 |

---

## Step 4 · P3 终审 [仅 Full，可整段跳过]

> Lite 模式跳过本节，但**要做最后一步**：P2 全部完成后跑一次 G3（查 TODO 清零），然后 `git tag handoff/<slug>`。
> 如果 Lite 里出现 `blocked` / `NEEDS-OPUS`：由你（或花 10 分钟问一次 Opus）裁决，改成 `done` / `dropped`，再跑 G3。

| 项目 | 内容 |
|---|---|
| 谁 | **Opus** |
| 在哪 | **Claude Code** |
| 输入 | `git diff baseline/<slug>..HEAD --stat` + 关键 diff + stills 截图 + NEEDS-OPUS 队列 |
| 产出 | NEEDS-OPUS 逐条裁决 + `POLISH.md`（≤10 条机械修改） |
| 预算 | ≤ 整个任务 Opus 用量的 15% |

贴 `docs/handoff/_protocol/prompts/P3-ui-polish.md` 的正文，替换 `<slug>`。

然后把 `POLISH.md` 贴给 DeepSeek 执行（每条一提交）。**P3 对 DESIGN / 令牌的修改也要提交**，最后：

```bash
git add -A && git commit -m "[opus] polish: <slug>"   # 若 P3 改过规范/令牌
git status --short                                      # 应为空
```

再跑 G3、打 tag：

```bash
TASK_DIR=docs/handoff/<slug> BASE_TAG=baseline/<slug> \
  bash docs/handoff/_protocol/scripts/gate.sh G3
git tag handoff/<slug>
```

G3 硬性要求：`todo` / `doing` / `blocked` / `NEEDS-OPUS` 四种状态全部清零（裁决后改成 `done`，决定不做则改 `dropped`）。

---

## Step 5 · 收尾与记账 [5 分钟]

1. 在 `HANDOFF.md` 第 7 节记一行：日期 / Opus 花费 / Opus 代码占比 / NEEDS-OPUS 数 / POLISH 条数 / 首轮是否通过。
2. 截图归档到 `docs/handoff/<slug>/stills/`。
3. 按 [PROTOCOL.md](PROTOCOL.md) 的「度量与调参」一节判断下轮切点上移还是下移。
4. 合并分支。
