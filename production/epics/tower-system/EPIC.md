# Epic: Tower System (防御塔)

> **Layer**: Core | **GDD**: design/gdd/tower-system.md | **Status**: Ready
> **Architecture Module**: TowerSystem (Core)
> **Stories**: 2 stories — Logic — **COMPLETE** (2026-06-02)

## Stories
| # | Story | Type | Status | Files | Tests |
|---|-------|------|--------|-------|-------|
| 001 | Tower Class | Logic | Complete | tower.gd | 7 tests |
| 002 | Tower System | Logic | Complete | tower_system.gd (attack dispatch bridge) | 23 tests |

## Overview

实现防御塔的完整行为：Timer 驱动的攻击循环（`1.0/attack_speed` 秒间隔）、基于优先级的索敌（最高 waypoint_index → 最低 health）、三种攻击模式（Cannon AOE/Ice slow/Arrow pierce）、数据驱动的星级缩放、PREP 阶段出售。塔绝不直接调用 `monster.take_damage()`——始终通过 Combat 系统。

## Governing ADRs

| ADR | Decision | Risk |
|-----|----------|------|
| ADR-0002 | TowerData.tres — 星级缩放数据驱动 | LOW |
| ADR-0006 | 出售操作 PREP 阶段门控 | LOW |

## GDD Requirements (10 TRs)

TR-tower-002 (Combat intermediary) 在 architecture.md API boundary 中定义。其余由上述 ADR 覆盖。

## Definition of Done

- Timer 驱动的攻击循环 + 优先级索敌
- Cannon (AOE 3×3) / Ice (slow) / Arrow (pierce+bounce) 三种攻击模式
- 数据驱动星级缩放 (1s=baseline, 2s=×2.0 range+15%, 3s=×4.0 range+30%)
- PREP 阶段出售——退 TowerData.sell_value → EMPTY
- 目标中途死亡 → 下一 tick 重新索敌
- 合星动画 gap 期间不攻击
- Ice slow 不堆叠（只最高值生效）
- 多塔同时攻击同一目标——独立计算伤害
