# Epic: Obstacle Block System (障碍方块)

> **Layer**: Core | **GDD**: design/gdd/obstacle-block.md | **Status**: Ready
> **Architecture Module**: ObstacleBlock (Core)
> **Stories**: 1 story — Logic — **COMPLETE** (2026-06-02)

## Stories

| # | Story | Type | Status | Files | Tests |
|---|-------|------|--------|-------|-------|
| 001 | Obstacle Block | Logic | Complete | obstacle_block.gd (+ pathfinding edit, economy_config edit) | 21 tests |

## Overview

实现障碍方块的放置/移除逻辑。`can_place()` 四条件检查（EMPTY+计数>0+金币≥cost+路径可达）。`place_block()` 原子执行（扣金币→设 BLOCK→减计数→发信号）。`remove_block()` 恢复金币和计数。所有操作受 PREP 阶段门控。

## Governing ADRs

| ADR | Decision | Risk |
|-----|----------|------|
| ADR-0001 | `block_count_changed` 通过 SignalBus 广播 | LOW |
| ADR-0002 | BLOCK_COST/SELL_VALUE/MAX_BLOCKS 来自 EconomyConfig.tres | LOW |
| ADR-0006 | 阶段门控——BATTLE 阶段拒绝操作 | LOW |

## GDD Requirements (7 TRs)

全部覆盖。TR-block-003 (rapid placement queue) 是性能优化——MVP 可先做简单版。

## Definition of Done

- `can_place()` 四条件检查（order: EMPTY→count→gold→path）
- `place_block()` 原子执行（gold→grid→count→signal）
- `remove_block()` 退款+恢复计数
- PREP 阶段门控
- `block_count_changed` 信号发射
- 快速连续放置的基本排队（路径重算完成前不开始下一次放置）
