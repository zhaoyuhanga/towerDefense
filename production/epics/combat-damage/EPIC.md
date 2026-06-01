# Epic: Combat & Damage System (战斗/伤害)

> **Layer**: Core | **GDD**: design/gdd/combat-damage.md | **Status**: Ready
> **Architecture Module**: Combat (Core)
> **Stories**: Not yet created — run `/create-stories combat-damage`

## Overview

实现 Tower → Monster 的伤害管道。`process_attack()` 是全部伤害的唯一入口。按塔类型分派（NORMAL/AOE/SLOW/PIERCE）。所有伤害为 true damage（MVP 无护甲/抗性/暴击——架构不排除后续添加）。每伤害实例 emit `damage_dealt` 供 VFX 浮动数字。

## Governing ADRs

| ADR | Decision | Risk |
|-----|----------|------|
| ADR-0001 | `damage_dealt` 通过 SignalBus 广播 | LOW |

## GDD Requirements (8 TRs)

architecture.md 定义了 Combat 的 API boundary。TR-combat-001/002/004/005 为纯游戏逻辑。

## Definition of Done

- `process_attack(tower, target)` 单入口实现
- 按类型分派：NORMAL(flat) / AOE(3×3 splash) / SLOW(speed-) / PIERCE(0.8^n bounce)
- AOE 对 3×3 区域内的怪物施加 splash 伤害
- Pierce 弹跳链——`bounce_damage[n] = attack * (0.8^n)`，无目标时终止
- `damage_dealt` 每伤害实例独立发射
- 目标死亡时攻击被浪费（不 retarget）
- Overkill 允许——同 tick 多塔独立计算
