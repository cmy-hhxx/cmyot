# ds_claude_handoff · Opus → DeepSeek 接力协议（双轨道）

**花 DeepSeek 的钱，拿 Opus 80~90% 的产出。** 两个方向：

- **UI 轨道**：动效、UI、展示 → 拿「视觉产出」。
- **ARCH 轨道**：代码架构、bug 修复、有难度的逻辑/性能优化 → 拿「架构质量」。

做法不变：**贵模型只做「判断」和「示范」，便宜模型只做「复制」**，用 git 把每个决定固化成下一个模型能继承的文件。

---

## 1. 先选方向（每个任务开始时由你指定）

| | **UI 轨道** | **ARCH 轨道** |
|---|---|---|
| 用来做 | 动效 / UI / 展示 / 视觉重构 | 架构审计 / 重构 / bug 修复 / 性能优化 |
| 典型任务 | 一套卡片动效铺 8 个页面 | 把 order 模块的幂等和状态机从 handler 里抽出来 |
| 交付物 | 令牌 + DESIGN + 参照实现 + 骨架 | AUDIT + ARCH + REFACTOR + 参照重构 + 护栏 |
| 门 | 截图门（3 视口 / 在动 / console） | 测试门（全绿 / 依赖规则 / 公共 API） |
| 省钱逻辑 | 复制段 = 同构组件 | 复制段 = 同一种机械改动的 N 个调用点 |
| Runbook | [TRACK-UI.md](TRACK-UI.md) | [TRACK-ARCH.md](TRACK-ARCH.md) |

**两个方向都不要用的任务**：一次性创意页面（没有复制段）、纯数据/文案改动（没有判断）。

## 2. 30 秒判断：这个任务该不该用

**UI 轨道**：

```
问题 1  需要审美判断吗？（配色定调 / 动效曲线 / 布局取舍）
        └ 否 → 别用这套。
问题 2  有长尾复制吗？（≥6 个同构组件 / ≥3 屏 / 同一套动效铺多处）
        ├ 是 → Full 模式
        └ 否 → 问题 3
问题 3  你愿意为验收多花 20~40 分钟吗？
        ├ 是 → Lite 模式（只有 P1 + P2）
        └ 否 → 别用这套，Opus 一把做完。
```

**ARCH 轨道**：

```
问题 1  这个问题需要「判断」吗？（边界怎么划 / 接口长什么样 / 先改哪）
        └ 否 → 直接让 DeepSeek 改，不用这套。
问题 2  有测试能证明「改完行为没变」吗？
        ├ 有 → 闭环模式
        └ 没有 → 体检模式先审计；重构前必须先补 characterization tests
问题 3  改动会跨 ≥3 个模块 / ≥10 个文件吗？
        ├ 是 → 闭环模式（Opus 定边界 + 参照重构，DeepSeek 铺量）
        └ 否 → 单点模式（Opus 出根因 + 失败测试 + 方案，DeepSeek 实施）
```

## 3. 两种轨道的模式

| 方向 | 模式 | 阶段 | 适用 |
|---|---|---|---|
| UI | **Full** | P0 → P1 → P2 → P3 | ≥6 个同构元素 / ≥3 屏 / 需新建设计系统 |
| UI | **Lite** | P1 → P2 | 1~2 屏 / <6 个同构元素 / 复用现有设计系统 |
| ARCH | **体检（Audit）** | P0 → P1（只出 AUDIT） | 先让 Opus 指出问题，你决定修哪些 |
| ARCH | **闭环（Fix）** | P0 → P1 → P2 → P3 | 审计 + 参照重构 + 铺量 + 复审 |
| ARCH | **单点（Hotfix）** | P1 → P2（P3 可选） | 单个 bug / 单个性能问题 |

两种方向共用同一套 **P0→P3 骨架** 和 git 纪律，只是交付物和门不同。

## 4. 谁在哪干活（固定分工，不要混）

| 阶段 | 客户端 | 模型 | 为什么是它 |
|---|---|---|---|
| P0 测绘 / 写背景 | DeepSeek Harness | DeepSeek | 只读不写代码，最便宜 |
| P1 定调 / 审计 / 参照实现 | **Claude Code**（CC Switch 选 Opus 供应商） | Opus | 要判断，还要能跑测试 / build / git tag |
| P2 铺量 / 机械重构 | DeepSeek Harness | DeepSeek | 干净壳：没有 Claude 插件和全局 CLAUDE.md 来「顺手优化」 |
| P3 终审 | **Claude Code** | Opus | 只做判断，预算 ≤15% |

> **不要用 Claude Code 跑 P2。** 全局 `CLAUDE.md` 和 `frontend-design` / `code-simplifier` 插件会持续建议「改进」，跟 P2 唯一的纪律「照抄，不优化」直接冲突。

## 5. 装一次（每个仓库一次，约 15 分钟）

```bash
# 把 /Users/cmy/Desktop/ds_claude_handoff 换成你本机这个仓库的位置
bash /Users/cmy/Desktop/ds_claude_handoff/scripts/install.sh ~/Desktop/TAAS
cd ~/Desktop/TAAS

# 1) 填本仓库的门命令（每个仓库填一次）
cp docs/handoff/_protocol/scripts/handoff.env.example docs/handoff/_protocol/handoff.env
$EDITOR docs/handoff/_protocol/handoff.env

# 2) 提交
git add docs/handoff && git commit -m "chore: 安装 Opus→DeepSeek 接力协议"
```

装完得到 `docs/handoff/_protocol/`：README / QUICKSTART / TRACK-UI / TRACK-ARCH / PROTOCOL / THINKING、P0~P3 两套 prompt、七个模板、gate 脚本、门命令模板、示例。

## 6. 每个任务（两条轨道各 4 行）

**UI 轨道**

```
P0  DeepSeek Harness  → BRIEF.md                          验收：命令都能跑
P1  Claude Code/Opus  → DESIGN + 令牌 + 参照实现 + 骨架     G1 绿 → tag baseline/<slug>
P2  DeepSeek Harness  → 逐条 TODO 铺量，一条一提交          G2 绿（Full 进 P3；Lite 直接 G3 → tag handoff/<slug>）
P3  Claude Code/Opus  → POLISH.md（可跳过）                 DeepSeek 执行 → G3 绿
```

**ARCH 轨道**

```
P0  DeepSeek Harness  → CODEBASE.md                        验收：测试基线数字
P1  Claude Code/Opus  → AUDIT + ARCH + REFACTOR + 参照重构   G1 绿 → tag baseline/<slug>
P2  DeepSeek Harness  → 逐条任务机械重构，一条一提交        G2 绿（测试必须绿）
P3  Claude Code/Opus  → 裁决 + POLISH.md（闭环模式）         DeepSeek 执行 → G3 绿 → tag handoff/<slug>
```

## 7. 文档地图

| 文件 | 什么时候读 | 花多久 |
|---|---|---|
| README.md | 现在 | 3 分钟 |
| QUICKSTART.md | 每次开工（共享准备） | 边做边看 |
| TRACK-UI.md | UI 任务 | 边做边看 |
| TRACK-ARCH.md | ARCH 任务 | 边做边看 |
| PROTOCOL.md | 第一次用 / 想改规则 | 10 分钟 |
| THINKING.md | 想不通为什么这么卡时 | 按需 |
| prompts/P0~P3-ui-*.md | UI 每个阶段开始 | 直接粘贴 |
| prompts/P0~P3-arch-*.md | ARCH 每个阶段开始 | 直接粘贴 |
| templates/ | 新建任务时 | 复制即用 |
| examples/hero-motion/ | 第一次填 DESIGN / HANDOFF | 对照填空 |

## 8. 目录

| 路径 | 内容 |
|---|---|
| `QUICKSTART.md` | 共享准备：安装、门命令、门速查、故障排查、成本度量 |
| `TRACK-UI.md` / `TRACK-ARCH.md` | 两条轨道的完整 runbook |
| `PROTOCOL.md` | 规则：方向/模式 + 阶段与门 + 防退化机制 + 失败处置 + 调参 + 反模式 |
| `THINKING.md` | 为什么这样设计 |
| `prompts/` | UI 与 ARCH 各四份可直接粘贴的 prompt |
| `templates/` | UI：BRIEF / DESIGN / HANDOFF；ARCH：CODEBASE / AUDIT / ARCH / REFACTOR |
| `scripts/` | `gate.sh` 验收门（双轨道） · `install.sh` · `handoff.env.example` · `stills.mjs` · `still-pause.js` |
| `examples/hero-motion/` | 填好的 DESIGN + HANDOFF，演示「命令式规范」长什么样 |

## 9. 纪律

**通用三条**

1. **绿着交接**：P1 交出的基线必须能跑、能验证。一个跑不起来的基线是最贵的失败模式。
2. **规范是命令，不是散文**：写数值、写规则、写检查方式，不写「高级感 / 呼吸感 / 更优雅」。
3. **不要逐文件修便宜模型的产出**：去改规范 / 参照实现 / 护栏，下一轮它自己就对。

**ARCH 轨道加三条**

4. **没有测试不重构**：测试是唯一能证明「行为没变」的东西。
5. **一条任务一次提交**：不允许「一条大提交改完所有」，否则无法回滚、无法审。
6. **规则要可执行**：写不进 `ARCH_CHECK_CMD` 的「松耦合」都是口号。

## 10. 已知限制（诚实清单）

- **没在你的真实仓库跑过**。第一次大概率要改 `handoff.env` 里的门命令、FROZEN 粒度、架构检查命令。
- **gate.sh 已验证的部分**：沙盒里 G1 全绿；G2 能抓「改 FROZEN」（含未提交的新文件）；G3 会拦 `todo` / `doing` / `blocked` / `NEEDS-OPUS` 残留。裸值 / `transition:all` 默认只是**警告不拦截**。
- **`stills.mjs` 没在真实浏览器跑过**；rAF / GSAP / Framer Motion 驱动的动画需要项目自己暴露 `window.__seek(ms)`。
- **FROZEN 是路径子串匹配**（`grep -F`），不是 glob；选择器 / 接口级冻结脚本查不到，靠纪律 + 人工抽查。
- **ARCH 轨道高度依赖测试**。没有测试的仓库只能先做「体检」，不能进 P2 重构。注意 `TEST_CMD` 可能静默通过（没有 test 脚本时 `pnpm -s test` 也退出 0），必须在安装时人工确认看到了真实测试数量。
- **架构不变量只能部分机器验证**。「多实例安全」「最终一致」这类需要压测 / 故障注入 / 线上证据，脚本只能查静态规则。
- **relay 的 Opus 是否满血没验证过**。整套流程的上限完全取决于 P1 的质量。
- **「80~90% 效果」没有客观指标**。唯一诚实的验收是盲对比。
- **单人流程**。多人协作时 NEEDS-OPUS 队列要加 owner 字段。
