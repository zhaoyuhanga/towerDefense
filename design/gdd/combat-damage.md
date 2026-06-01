# 战斗/伤害系统 (Combat & Damage System)

> **Status**: In Design
> **Author**: user + game-designer
> **Last Updated**: 2026-06-01
> **Implements Pillar**: Pillar 2 — 每一波都是考卷（战斗是"考试"的执行过程）

## Overview

战斗/伤害系统是塔攻击和怪物承受伤害之间的桥梁。它接收防御塔的攻击事件，根据攻击类型（普通/AOE/减速/穿透）计算实际伤害和目标效果，将伤害施加到怪物，并在怪物死亡时触发经济奖励和视觉反馈。MVP 阶段伤害公式极简——真实伤害，无护甲/抗性/暴击。

## Player Fantasy

玩家不直接操作战斗——他们通过布局决定战斗的结果。战斗系统的价值在于**让塔的攻击看起来和感觉正确**：数字跳出来干净利落、AOE 溅射有视觉冲击、怪物在火力网中倒下——这些瞬间让玩家确信"我布的防线在生效"。

## Detailed Design

### Core Rules

1. **伤害流水线**：塔系统调用 `process_attack(tower, target)` → 确定攻击类型（普通/AOE/减速/穿透）→ 计算伤害量 → 调用 `monster.take_damage()` → 发射 `damage_dealt` 信号。塔不直接操作怪物——战斗系统是所有伤害的唯一入口。
2. **无护甲/抗性**（MVP）：所有伤害为真实伤害。`actual_damage = TowerData.attack`。
3. **AOE 溅射**（炮塔）：主目标受到 100% 伤害。3×3 范围内的其他怪物受到 `special_value%` 溅射伤害。
4. **减速**（冰塔）：主目标受到 100% 伤害 + 减速效果。减速不可叠加——取最大值。
5. **穿透**（箭塔）：主目标受到 100% 伤害。30% 概率弹射到范围内下一个怪物——每次弹射伤害衰减 20%。
6. **伤害数字显示**：每次伤害事件 → 在怪物上方弹出伤害数字（白色=普通，金色=穿透，青色=减速附加），由视觉反馈系统渲染。

### Interactions

| 接口 | 签名 | 调用者 |
|------|------|--------|
| 处理攻击 | `process_attack(tower: Tower, target: Monster)` | 防御塔 |
| 伤害事件信号 | `damage_dealt(target, amount, type)` | 视觉反馈、HUD |

## Formulas

### 普通伤害

`actual_damage = tower.attack`

无护甲/抗性削减。

### 溅射伤害

`aoe_damage = tower.attack * tower.special_value / 100`

### 穿透弹射

`bounce_damage[n] = tower.attack * (0.8 ^ n)`（n=弹射次数，第 0 次=主目标=100%）

### 减速效果

`new_speed = monster.base_speed * (1 - tower.special_value / 100)`

| 变量 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `tower.attack` | float | 1–999 | 从 TowerData 读取 |
| `tower.special_value` | float | 10–100 | 溅射%/减速%/穿透次数 |

## Edge Cases

- **目标在攻击飞行中死亡**：伤害不施加——寻找下一个目标
- **AOE 范围内无其他怪物**：仅主目标受伤——无额外效果
- **穿透无可弹射目标**：弹射链终止——即使次数未用完
- **怪物同时被多塔击杀**：各自独立计算——过量伤害可能浪费（鼓励玩家分散火力）

## Dependencies

| 上游 | 关系 |
|------|------|
| 防御塔 | Hard — 接收攻击事件 |
| 怪物系统 | Hard — 调用 `take_damage()`, `apply_effect()` |
| 数据配置 | Hard — TowerData 数值 |

| 下游 | 关系 |
|------|------|
| 视觉反馈 | Hard — `damage_dealt` 信号 |
| 经济系统 | Soft — 怪物死亡触发金币奖励 |

## Tuning Knobs

无独立 Knob。伤害行为完全由 TowerData 和 MonsterData 决定。

## Acceptance Criteria

- **GIVEN** 炮塔攻击怪物，**WHEN** 伤害计算完成，**THEN** 怪物 health 扣减 TowerData.attack
- **GIVEN** 炮塔攻击+周围有其他怪物，**WHEN** AOE 触发，**THEN** 副目标受到溅射伤害
- **GIVEN** 冰塔命中怪物，**WHEN** 减速施加，**THEN** 怪物 speed 降低
- **GIVEN** 怪物 health ≤ 0，**WHEN** 伤害处理后，**THEN** `monster_died` 信号发射
- **GIVEN** 箭塔攻击+穿透触发+有弹射目标，**WHEN** 弹射，**THEN** 弹射伤害为前一次的 80%

## Open Questions

1. **伤害数字的累积合并**：如果多塔同时攻击同一怪物——显示一个合并数字还是分别弹出？→ 分别弹（视觉更丰富）
2. **V1.0 战斗深度**：是否需要护甲/魔抗/暴击系统？→ 取决于 MVP 测试反馈