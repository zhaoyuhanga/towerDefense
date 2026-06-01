# Epic: Pathfinding System (怪物寻路)

> **Layer**: Core | **GDD**: design/gdd/pathfinding.md | **Status**: Ready
> **Architecture Module**: Pathfinding (Core)
> **Stories**: 1 story — Logic — **COMPLETE** (2026-06-02)

## Stories

| # | Story | Type | Status | Files | Tests |
|---|-------|------|--------|-------|-------|
| 001 | Pathfinding System | Logic | Complete | pathfinding.gd | 10 tests |

## Overview

集成 Godot AStarGrid2D 实现 20×15 网格寻路。每次 `cell_state_changed` 触发全量 A* 重算（目标 < 1ms）。包含 Godot 4.6 行为变更 guard（`is_point_solid()` 预检）。提供 `is_path_reachable()` 同步预检供方块放置前使用。曼哈顿距离启发、统一代价、无对角线。

## Governing ADRs

| ADR | Decision | Risk |
|-----|----------|------|
| ADR-0001 | `path_updated` / `path_blocked` 通过 SignalBus 广播 | LOW |
| ADR-0003 | AStarGrid2D + Godot 4.6 solid-point guard + 全量重算 < 1ms | HIGH |

## GDD Requirements (8 TRs)

全部由 ADR-0003 覆盖。TR-path-008 (zero tuning knobs) 是设计约束，非架构需求。

## Definition of Done

- AStarGrid2D 20×15 实例，walkable=EMPTY/ENTRANCE/EXIT, solid=BLOCK/TOWER
- `cell_state_changed` → 全量重算，< 1ms
- `is_point_solid()` guard（4.6 兼容）
- `is_path_reachable()` 同步预检
- `path_updated` / `path_blocked` SignalBus 广播
- 走廊、L 型弯、内部环路的正确最短路径
- 每个怪物缓存自己的路径副本，`path_updated` 时更新
