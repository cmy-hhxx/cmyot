# QUICKSTART · 共享准备

> 这是**两条轨道共用**的准备手册。具体任务流程看轨道 runbook：
> **UI 轨道** → [TRACK-UI.md](TRACK-UI.md)　|　**ARCH 轨道** → [TRACK-ARCH.md](TRACK-ARCH.md)
> 规则和原理：[PROTOCOL.md](PROTOCOL.md) / [THINKING.md](THINKING.md)。

---

## 0. 开工前先定两件事

1. **方向**：UI（动效/UI/展示）还是 ARCH（架构/bug/性能）？——决定用哪份 runbook、哪套 prompt、哪套门。
2. **模式**：
   - UI：**Full**（P0→P3）/ **Lite**（P1→P2）
   - ARCH：**体检**（P0→P1 只出 AUDIT）/ **闭环**（P0→P3）/ **单点**（P1→P2）

判断标准见 [README](README.md) 第 1~3 节。

---

## 1. 一次性准备（每个仓库一次，约 15 分钟）

### 1.1 安装协议 [都要]

```bash
# 把 /Users/cmy/Desktop/ds_claude_handoff 换成你本机这个仓库的位置，~/Desktop/TAAS 换成目标仓库
bash /Users/cmy/Desktop/ds_claude_handoff/scripts/install.sh ~/Desktop/TAAS
```

期望输出：

```
✓ 已安装到 /Users/cmy/Desktop/TAAS/docs/handoff/_protocol/
```

### 1.2 填门命令 [都要]

```bash
cd ~/Desktop/TAAS
cp docs/handoff/_protocol/scripts/handoff.env.example docs/handoff/_protocol/handoff.env
$EDITOR docs/handoff/_protocol/handoff.env
```

`handoff.env` 里要填的（monorepo 记得加 `-F <包名>`）：

```bash
# UI 轨道
export TYPECHECK_CMD="pnpm -s typecheck"
export BUILD_CMD="pnpm -s build"
export DEV_URL="http://localhost:5173"
export STILLS_URL="$DEV_URL"
export TOKEN_HINTS="tokens|theme|tailwind"

# ARCH 轨道（测试必填，其余可选）
export TEST_CMD="pnpm -s test --run"
export ARCH_CHECK_CMD=""
export API_CHECK_CMD=""
```

验证（这一步就是 **G0**）：

```bash
source docs/handoff/_protocol/handoff.env
eval "$TYPECHECK_CMD" && eval "$BUILD_CMD"
[ -z "$TEST_CMD" ] || eval "$TEST_CMD"     # ARCH 轨道必须能跑通
```

期望：全部退出 0。有一条不过，先修仓库，别往下走。

> **ARCH 轨道特别注意**：`TEST_CMD` 可能「静默通过」——比如仓库没有 test 脚本时，`pnpm -s test` 会退出 0 但一个测试都没跑。
> 验证时必须**看到真实的测试数量**（例如 `Tests 128 passed`）。输出为空 / 0 个测试 = 这个仓库没有测试 → ARCH 轨道只能做「体检」。

### 1.3 UI 轨道：装截图依赖

```bash
pnpm add -D playwright && npx playwright install chromium
```

不装的话 gate 会跳过截图门（只警告）。代价：「主视觉真的在动」这条没人替你验。

### 1.4 UI 轨道：让动画可定格

`stills.mjs` 用 `?still=0` 和 `?still=800` 各截一帧，要求两张图不同。这依赖页面加载 `still-pause.js`（把 CSS Animation / Transition / WAAPI 暂停到指定时刻）。

安装（三选一，原文见 `scripts/still-pause.js` 文件头）：

1. 复制到 `public/`，`<head>` 末尾加 `<script src="/still-pause.js" defer></script>`
2. 把 IIFE 粘进 dev 入口（仅 dev）
3. 写成 vite 插件注入

**rAF / GSAP / Framer Motion 它覆盖不了**，项目要自己实现 `window.__seek(ms)`：

```js
if (import.meta.env.DEV) window.__seek = (t) => { gsap.globalTimeline.time(t / 1000); };
```

不做这一步，两帧大概率相同 → `stills.mjs` 判为「疑未在动」，G1 直接红。

### 1.5 ARCH 轨道：确认测试基线 + 架构检查

**测试**：`TEST_CMD` 必须能跑，并记下基线数字（总数 / 通过数 / 耗时）。没有测试的区域，P1 要先补 characterization tests，否则禁止重构。

**架构检查**（依赖方向 / 无环 / 边界），任选一种落成命令写进 `ARCH_CHECK_CMD`：

```bash
# TypeScript：dependency-cruiser
pnpm add -D dependency-cruiser && npx depcruise --init
# 然后 handoff.env: ARCH_CHECK_CMD="npx depcruise src --config .dependency-cruiser.js"

# TypeScript：madge（只查循环依赖，最轻）
# ARCH_CHECK_CMD="npx madge --circular --extensions ts,tsx src"

# Python：import-linter
# ARCH_CHECK_CMD="lint-imports"
```

公共 API 兼容性检查（可选，写进 `API_CHECK_CMD`）：api-extractor、knip、或 `tsc --declaration` 后对比 `.d.ts`。

### 1.6 提交 [都要]

```bash
git add docs/handoff && git commit -m "chore: 安装 Opus→DeepSeek 接力协议"
```

---

## 2. 走哪条 runbook

| 方向 | 打开这个 | 用哪套 prompt |
|---|---|---|
| UI | [TRACK-UI.md](TRACK-UI.md) | `prompts/P0~P3-ui-*.md` |
| ARCH | [TRACK-ARCH.md](TRACK-ARCH.md) | `prompts/P0~P3-arch-*.md` |

---

## 3. 门速查

**UI 轨道**

| 门 | 什么时候跑 | 查什么 | 失败怎么办 |
|---|---|---|---|
| **G0** | 安装时（1.2） | 仓库能装 + typecheck / build 通过 | 修仓库，别往下走 |
| **G1** | P1 结束 | 零 console error · 3 视口不塌 · 主视效在动 · reduced-motion 截图产出（人工看） · typecheck · build | **禁止交接**；修 3 轮不绿就拆任务 |
| **G2** | 每条 TODO | G1 + 没碰 FROZEN + 没加依赖 | 修，或 `git revert` 单条 |
| **G3** | 交付前 | G2 + `todo` / `doing` / `blocked` / `NEEDS-OPUS` 清零 | 回 P3 裁决，再回 P2 执行 |

**ARCH 轨道**

| 门 | 什么时候跑 | 查什么 | 失败怎么办 |
|---|---|---|---|
| **G0** | P0 结束 | 测试命令能跑，基线数字已记录 | 修仓库 / 先补测试 |
| **G1** | P1 结束 | 全量测试绿 · `ARCH_CHECK_CMD` 绿 · 公共 API 无破坏 · 参照重构完成 | **禁止交接**；修 3 轮不绿就拆任务 |
| **G2** | 每条任务 | 测试绿 + 架构检查绿 + 没碰 FROZEN + 没加依赖 + 没改公共 API | 修，或 `git revert` 单条 |
| **G3** | 交付前 | 全量测试 + 架构检查 + `todo` / `doing` / `blocked` / `NEEDS-OPUS` 清零 | 回 P3 裁决，再回 P2 执行 |

> G0 不是 `gate.sh` 的一档，就是 1.2 里那条 `eval` 验证。

---

## 4. 故障排查（按症状查）

| 症状 | 原因 | 处理 |
|---|---|---|
| `需要设置 TASK_DIR` | 忘了带变量 | `TASK_DIR=docs/handoff/<slug> bash ...` |
| `需要 BASE_TAG 且该 tag 存在` | 没打 tag / tag 名拼错 | `git tag` 看现有 tag；`git tag baseline/<slug>` |
| gate 说「没有设置门命令」 | 忘了 `source handoff.env` | `source docs/handoff/_protocol/handoff.env` |
| UI：截图门被跳过 | 没装 playwright / 没设 STILLS_URL | 见 1.3 / 1.4 |
| UI：裸值警告刷屏 | 存量文件本来就有裸值 | 只看本次 `git diff` 的新增行 |
| FROZEN 误报 | FROZEN 写了目录或过短前缀，gate 是子串匹配 | FROZEN 写到具体文件；选择器 / 接口项只能人工查 |
| TODO 计数不对 | 状态列没写 `todo/doing/done/blocked/NEEDS-OPUS/dropped` | 检查表格格式 |
| ARCH：`ARCH 轨道必须设置 TEST_CMD` | 没填测试命令 | 填 `TEST_CMD`；没有测试就先补 |
| ARCH：`ARCH_CHECK_CMD` 警告 | 架构规则没落成命令 | 见 1.5；先用 madge 查循环也行 |
| monorepo 里命令跑错包 | 门命令没带 `-F` | 改 `handoff.env` |

---

## 5. 成本与度量

**记账来源**：CC Switch 用量面板（本地库 `~/.cc-switch/cc-switch.db` 的 `proxy_request_logs` / `usage_daily_rollups`，都有美元数）。
**不要用 `/cost`**：relay 下它按 Anthropic 牌价估算，不是你实际付的钱。

经验区间（按任务复杂度浮动）：

| 阶段 | 谁 | 占 token 比例 |
|---|---|---|
| P0 | DeepSeek | ~5% |
| P1 | Opus | 25~35% |
| P2 | DeepSeek | 50~65% |
| P3 | Opus | ≤15% |

**唯一诚实的验收**：同一需求做两版（Opus 全量 vs 接力），盲对比。

---

## 6. 三个必须人手看一眼的检查点

1. **P1 交接**：参照实现 / 参照重构的质感 = 整件事的上限。不满意就停在 P1。
2. **P2 中途**：抽查 2 个提交，看有没有偷偷「优化」参照实现。
3. **P3 结束**：UI 看 3 视口截图；ARCH 看 diff + 测试覆盖。

---

## 7. 一页检查单（复制粘贴）

```bash
# 开任务
git switch -c feat/<slug>
mkdir -p docs/handoff/<slug>
source docs/handoff/_protocol/handoff.env

# UI 轨道：拷这三份
cp docs/handoff/_protocol/templates/{BRIEF,DESIGN,HANDOFF}.md docs/handoff/<slug>/
# ARCH 轨道：拷这四份
# cp docs/handoff/_protocol/templates/{CODEBASE,AUDIT,ARCH,REFACTOR}.md docs/handoff/<slug>/

# UI：P0（Full）→ BRIEF；P1 → G1 → tag baseline；P2 → G2/条；P3（Full）→ POLISH；G3 → tag handoff
# ARCH：P0 → CODEBASE；P1 → AUDIT/ARCH/REFACTOR + 参照重构 → G1 → tag baseline；P2 → G2/条；P3 → G3 → tag handoff
```
