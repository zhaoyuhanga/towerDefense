# 经济系统 (Economy System)

> **Status**: In Design
> **Author**: user + game-designer
> **Last Updated**: 2026-06-01
> **Implements Pillar**: Pillar 1, 3, 4 — 经济约束定义路线的代价、星级升级的成本、筑城和观战之间的资源节奏

## Overview

经济系统管理游戏内所有金币的流入流出。金币是唯一的资源货币——玩家通过击杀怪物获得金币，花费金币购买塔/方块/合星。经济系统的核心职责是：确保玩家在每一波之间面临有意义的资源约束——"够买这个塔，还是留着合星？"——这种资源紧张度是所有策略决策的基础。

## Player Fantasy

玩家不直接感受经济系统——他们感受的是**"钱够不够"的紧张感**。金币刚好够买一座塔的时候、卖塔凑钱合星的时候、看着击杀奖励飘起来的数字觉得"值了"的时候——这些瞬间是经济系统在起效。

- **服务于所有四大支柱**：经济是策略决策的硬约束——没有金币约束，玩家会满屏放满塔和方块，所有支柱一起崩塌

## Detailed Design

### Core Rules

1. **金币是唯一货币**：无宝石/道具/多币种。MVP 经济模型极简——赚金币→花金币。
2. **收入来源**：击杀怪物 = MonsterData.reward_gold。出售塔 = TowerData.sell_value。移除方块 = BLOCK_SELL_VALUE。
3. **支出去向**：购买塔 = TowerData.cost。购买方块 = BLOCK_COST。合星（如收费）= MERGE_COST。
4. **起始金币**：EconomyConfig.starting_gold（默认 200）。
5. **金币非负**：余额不能低于 0——购买前必须检查 `can_afford(amount)`。
6. **经济信号**：`gold_changed(new_amount)` 在每次余额变更后发射——HUD/UI 订阅。

### Interactions

| 接口 | 签名 | 调用者 |
|------|------|--------|
| 消费 | `spend_gold(amount: int) -> bool` | 塔、方块、合星 |
| 收入 | `add_gold(amount: int)` | 怪物死亡、出售 |
| 查询 | `can_afford(amount: int) -> bool` | 所有购买前检查 |
| 余额信号 | `gold_changed(current: int)` | HUD/UI |

### Formulas

`new_balance = current_gold + income - expense`

### States

| 状态 | 触发条件 |
|------|---------|
| `INSUFFICIENT` | `can_afford()` 返回 false → 购买按钮/预览变灰 |

## Edge Cases

- **金币为 0 时尝试购买**：`can_afford()` → false，操作拒绝，无额外反馈（预览已显示不可用）
- **金币溢出**：int 上限 ~21 亿——塔防经济不可能触及。不做上限
- **出售价格高于买入价格**（bug）：TowerData.sell_value 必须 ≤ TowerData.cost。数据校验在数据配置 GDD Section D 中保证

## Dependencies

| 上游 | 关系 |
|------|------|
| 数据配置 | Hard — EconomyConfig + TowerData.cost/sell + MonsterData.reward + BLOCK_COST |
| 怪物系统 | Hard — `monster_died` 信号（reward_gold） |

| 下游 | 关系 |
|------|------|
| 障碍方块 | Hard — `spend_gold()`, `can_afford()` |
| 防御塔 | Hard — `spend_gold()`, `can_afford()` |
| 合星升级 | Hard — `spend_gold()` |
| 准备阶段 | Hard — `add_gold()` 出售返还 |
| HUD/UI | Hard — `gold_changed` 信号 |

## Tuning Knobs

| Knob | 默认 | 范围 | 改太高 | 改太低 |
|------|------|------|--------|--------|
| `starting_gold` | 200 | 50–500 | 开局满屏塔——Pillar 1 失效 | 买不起——卡死 |
| `kill_reward_multiplier` | 1.0 | 0.5–3.0 | 钱太多——无资源紧张 | 钱太少——无策略选择 |
| `BLOCK_COST` | 25 | 10–100 | Mazing 无法开始 | 满屏方块 |
| `MERGE_COST` | 0 | 0–200 | 合星变奢侈——Pillar 3 弱化 | — |

## Acceptance Criteria

- **GIVEN** 新游戏开始，**WHEN** 初始化完成，**THEN** `current_gold = EconomyConfig.starting_gold`
- **GIVEN** current_gold=200，**WHEN** `spend_gold(50)` 被调用，**THEN** 返回 true，current_gold=150
- **GIVEN** current_gold=30，**WHEN** `spend_gold(50)` 被调用，**THEN** 返回 false，current_gold 不变
- **GIVEN** 怪物被击杀，**WHEN** `monster_died(reward_gold=10)` 信号发射，**THEN** current_gold 增加 10
- **GIVEN** 金币变更，**WHEN** 任何增减后，**THEN** `gold_changed` 信号发射

## Open Questions

1. **利息/被动收入**：波次之间是否获得被动金币？→ MVP 不做——纯击杀驱动
2. **波次通关奖励**：每波通关后额外奖励？→ 不需要——波次内的击杀奖励已足够