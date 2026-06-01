# Epic: Board Grid System (棋盘网格)

> **Layer**: Foundation | **GDD**: design/gdd/board-grid.md | **Status**: Ready
> **Architecture Module**: BoardGrid (Foundation → Core API)
> **Stories**: 4 stories — 2 Logic, 1 Integration, 1 UI

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | Core Data Layer | Logic | Ready | — |
| 002 | Coordinate System | Logic | Ready | ADR-0002 |
| 003 | Signal Integration | Integration | Ready | ADR-0001 |
| 004 | Visual Rendering | UI | Ready | ADR-0005 |

## Overview

实现 20×15 棋盘网格的数据层——维护 5 种 CellState（EMPTY/BLOCK/TOWER/ENTRANCE/EXIT），提供坐标转换和状态查询 API。BoardGrid 是 Foundation 层最重要的系统——5 个下游系统（Pathfinding、ObstacleBlock、Monster、Tower、SceneManagement）都依赖它。

## Governing ADRs

| ADR | Decision | Risk |
|-----|----------|------|
| ADR-0002 | GridConfig.tres 数据驱动——COL/ROW/CELL_SIZE 外部配置 | LOW |
| ADR-0005 | TileMapLayer 渲染——单 atlas source，Nearest filter | MEDIUM |

## GDD Requirements (13 TRs)

All 13 TR-grid-* requirements have ADR coverage or are pure API contracts. No untraced requirements.

## Definition of Done

- 20×15 网格初始化和状态读写
- `grid_to_world()` / `world_to_grid()` 坐标转换
- `cell_state_changed` 信号通过 SignalBus 发射
- ENTRANCE/EXIT 格不可变验证
- 窗口 resize 时 GRID_ORIGIN 自动重算
- GridRenderer (TileMapLayer) 正确渲染 5 种 CellState
- 阶段透明度切换 (modulate.a PREP=0.8 / BATTLE=0.6)
- 单元测试覆盖所有状态转换合法/非法路径
