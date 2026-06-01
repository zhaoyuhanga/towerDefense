# Epic: Monster System (怪物系统)

> **Layer**: Core | **GDD**: design/gdd/monster-system.md | **Status**: Ready
> **Architecture Module**: MonsterSystem + MonsterPool (Core)
> **Stories**: 2 stories — Logic — **COMPLETE** (2026-06-02)

## Stories
| # | Story | Type | Status | Files | Tests |
|---|-------|------|--------|-------|-------|
| 001 | Monster Base Class | Logic | Complete | monster.gd | 7 tests |
| 002 | Monster Pool | Logic | Complete | monster_pool.gd (full impl) | 2 tests |

## Overview

实现怪物实体的完整生命周期：对象池管理（MonsterPool Autoload）、基于路径点的每帧移动、有限状态机（SPAWNING→MOVING→DYING|BREACHED + STUNNED overlay）、伤害和效果的统一入口。所有怪物属性来自 MonsterData.tres 资源。

## Governing ADRs

| ADR | Decision | Risk |
|-----|----------|------|
| ADR-0001 | `monster_died` / `monster_breached` 通过 SignalBus 广播 | LOW |
| ADR-0002 | MonsterData.tres — 属性完全数据驱动 | LOW |
| ADR-0003 | 路径缓存 + `path_updated` 时更新 | HIGH |
| ADR-0004 | 对象池——spawn/despawn/warmup 三接口，离树回收，SignalBus emit | HIGH |

## GDD Requirements (10 TRs)

全部由 ADR-0004 + ADR-0002 + ADR-0001 覆盖。

## Definition of Done

- MonsterPool.spawn() / despawn() / warmup() 实现
- Monster 基类 (@abstract) — setup(data) / reset() 契约
- 每帧路径点移动 + waypoint 推进
- FSM: SPAWNING(fade-in)→MOVING→DYING|BREACHED + STUNNED overlay
- `get_active_monsters()` 供塔索敌查询
- `take_damage()` / `apply_effect()` 单入口
- 冻结死亡 → 消除冻结效果后播放死亡动画
- 空路径 guard（no spawn + warn wave system）
- 无怪物间碰撞
