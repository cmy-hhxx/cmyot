# REFACTOR — <任务名>

> **谁改哪一节**：§1 §2 §3 §6 由 Opus（P1）写；§4 的状态列和 §5 由 DeepSeek（P2）改；§5 的「Opus 裁决」列由 Opus（P3）填。
> 除了这些，谁都不许改这份文件。

## 1. 状态（Opus 写，P2 / P3 更新）

- 方向：ARCH
- 模式：体检 / 闭环
- 当前阶段：P1 / P2 / P3 / 交付
- 下一步是谁：Opus / DeepSeek / 人
- baseline tag：`baseline/<slug>`
- 门状态：G0 ✅（测试基线 128/128） / G1 ✅（测试 ✅ · 架构检查 ✅ · 公共 API ✅ · 参照重构 ✅）
- 已跑通命令：`<test / typecheck / build / ARCH_CHECK_CMD>`
- Opus 花费：`$X.XX`（来源：CC Switch 用量面板）

## 2. 已完成的决定（不要推翻）

| 决定 | 为什么 | 推翻的代价 |
|---|---|---|
| <例：OrderRepository 接口放 domain> | <依赖方向> | 全部实现重写 |
| | | |

## 3. FROZEN（DeepSeek 不得修改）

> 明确到文件或接口，**每一项都要写为什么**。需要动就记 NEEDS-OPUS。

| 路径 / 接口 | 为什么不能动 |
|---|---|
| `src/domain/order/stateMachine.ts` | 状态机是行为基线，改了所有测试失效 |
| `OrderRepository` 接口签名 | 调用方多，签名变动必须单开 seam 任务 |

## 4. 任务单（有序，一次一条）

> 状态只能由 DeepSeek 改：`todo` → `doing` → `done` / `blocked` / `NEEDS-OPUS` / `dropped`。
> 同一时刻只允许一条 `doing`；交付（G3）前不允许有 `doing`。
> 标 `NEEDS-OPUS` 时必须在 §5 加一行；P3 裁决后执行：做了改 `done`，不做改 `dropped`。

| ID | 类型 | 目标 | 文件 | 验收 | 预估 | 状态 |
|---|---|---|---|---|---|---|
| R01 | refactor | 抽 `OrderRepository` 接口（不改行为） | `src/domain/order/repo.ts` | 全量测试绿 + ARCH_CHECK_CMD 绿 | M | todo |
| R02 | refactor | infra 实现迁到 `PgOrderRepo` | `src/infra/order-repo.ts` | 同上 + 契约测试 | M | todo |
| R03 | bugfix | 修 A01 幂等失效 | `src/app/order/handler.ts` | 先有失败测试，修完全绿 | S | todo |
| R04 | perf | 订单列表 N+1 查询 | `src/infra/order-repo.ts` | 基准从 820ms 降到 ≤300ms | M | todo |

类型取值：`refactor`（行为不变）/ `bugfix`（先失败测试）/ `perf`（先基准）/ `seam`（改公共 API，需单独迁移任务）

## 5. NEEDS-OPUS（不要自己去猜）

| 位置 | 我卡在 | DeepSeek 的假设 | Opus 裁决 |
|---|---|---|---|
| | | | |

## 6. 禁止的简化（含原因）

- <例：不要为了过依赖检查，把 domain 对 infra 的依赖换成 `any`——那等于没有边界>
- <例：不要顺手重命名，重命名会让 diff 无法审>

## 7. 度量（任务结束后由人补一行）

| 日期 | Opus 花费 | AUDIT 条数 | 修了几条 | NEEDS-OPUS 数 | POLISH 条数 | 首轮通过 |
|---|---|---|---|---|---|---|
| | | | | | | |
