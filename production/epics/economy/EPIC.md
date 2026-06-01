# Epic: Economy System (经济)

> **Layer**: Core | **GDD**: design/gdd/economy.md | **Status**: Ready
> **Architecture Module**: Economy (Core)
> **Stories**: 1 story — Logic — **COMPLETE** (2026-06-02)

## Stories
| # | Story | Type | Status | Files | Tests |
|---|-------|------|--------|-------|-------|
| 001 | Economy | Logic | Complete | economy.gd (154 lines) | 9 tests |

## Overview

管理单一金币货币（int32）。`spend_gold()` 原子 check-then-deduct（余额永不为负）。`add_gold()` 来源：怪物击杀、塔出售、方块移除。`can_afford()` 是所有购买路径的单一预检入口。所有经济常量来自 EconomyConfig.tres。

## Governing ADRs

| ADR | Decision | Risk |
|-----|----------|------|
| ADR-0001 | `gold_changed` 通过 SignalBus 广播——HUD 订阅 | LOW |
| ADR-0002 | EconomyConfig.tres — starting_gold/COST/SELL_VALUE/MERGE_COST | LOW |

## GDD Requirements (8 TRs)

全部由 ADR-0002 + ADR-0001 覆盖。

## Definition of Done

- `spend_gold(amount) → bool` — check-then-deduct, 原子
- `add_gold(amount)` — 入账 + emit `gold_changed`
- `can_afford(amount) → bool` — 所有购买路径的预检
- 余额永不为负
- 无余额上限（int32 范围足够）
- MVP 无被动收入
- 所有常量来自 EconomyConfig.tres
