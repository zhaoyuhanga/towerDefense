# 怪物寻路系统 (Pathfinding System)

> **Status**: In Design
> **Author**: user + game-designer
> **Last Updated**: 2026-06-01
> **Implements Pillar**: Pillar 1 — 路线即武器（寻路定义了"路线"的物理含义）

## Overview

怪物寻路系统是 Mazing 塔防的技术引擎。它在每次方块放置/移除后基于 AStarGrid2D 重新计算从入口到出口的最短可行路径，并将路径以坐标数组的形式提供给怪物系统。所有怪物沿同一条路径行进——这条路径正是玩家通过方块操控的"路线"。

玩家不直接使用寻路——他们通过放置障碍方块来**间接操控它**。当玩家放下一块方块、发现怪物的路线变长了三倍、沿途的塔开始收割——那个瞬间，"路线即武器"从抽象概念变成了可看见的物理事实。

没有寻路系统，方块只是一堆装饰品，Mazing 不再是 Mazing。

## Player Fantasy

玩家不感受寻路算法本身。他们感受的是**路线的即时反馈**——方块放下去、路线立刻变了、怪物开始绕远路。这个"立刻"是寻路系统最重要的用户体验：如果放方块后路线延迟了半秒才更新，"即点即得"的掌控感就崩塌了。

- **直接服务于 Pillar 1（路线即武器）**：寻路是路线成为武器的物理法则
- **间接服务于 Pillar 2（每一波都是考卷）**：怪物按路线行进——路线的长度和形状决定考试的难度
- **参考体验**：Gemcraft 的方块放置——放下去瞬间路线就改变，没有延迟

## Detailed Design

### Core Rules

1. **单一主路径**：棋盘上始终存在一条从 ENTRANCE 到 EXIT 的"主路径"，所有怪物沿此路径行进。主路径在每次棋盘状态变更后重算。
2. **AStarGrid2D 驱动**：使用 Godot 原生 `AStarGrid2D`，20×15 网格。EMPTY/ENTRANCE/EXIT = 可行走；BLOCK/TOWER = solid。
3. **全量重算**：监听 `cell_state_changed` 信号 → 更新 AStarGrid2D 对应点的 solid 状态 → 全量重算路径。300 格 A* < 1ms，MVP 无需增量优化。
4. **不可达处理**：ENTRANCE→EXIT 无可行路径 → 返回空路径，发射 `path_blocked` 信号。
5. **怪物路径缓存**：每个怪物持有 `Array[Vector2i]` 路径副本。主路径更新时通过 `path_updated` 信号同步。

### States

| 状态 | 含义 |
|------|------|
| `PATH_VALID` | 存在可行路径 |
| `PATH_BLOCKED` | 无可行路径——怪物停在当前位置 |

### Interactions

| 接口 | 签名 | 调用者 |
|------|------|--------|
| 获取主路径 | `get_main_path() -> Array[Vector2i]` | 怪物系统 |
| 路径长度 | `get_path_length() -> int` | HUD/UI、障碍方块 |
| 可达检查 | `is_path_reachable() -> bool` | 障碍方块（放置前预检查） |
| 路径更新信号 | `path_updated(new_path)` | 怪物系统 |
| 路径阻塞信号 | `path_blocked()` | 视觉反馈 |

## Formulas

AStarGrid2D 默认使用曼哈顿距离（四方向移动）：

`h(col, row) = |col - exit_col| + |row - exit_row|`

每一步基础代价为 1。所有可行走格子代价相同。

`f(node) = g(node) + h(node)`

| 变量 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `entrance_pos` | Vector2i | 0–19, 0–14 | 入口坐标 |
| `exit_pos` | Vector2i | 0–19, 0–14 | 出口坐标 |

## Edge Cases

- **无可行路径**：`get_main_path()` 返回空数组。`path_blocked` 信号发射。方块系统通过 `is_path_reachable()` 预检查阻止堵死
- **入口/出口被覆盖**：棋盘网格 GDD 已禁止——不需要本系统处理
- **所有格子被填满只剩单格通道**：AStarGrid2D 正确处理 1 格宽通道

## Dependencies

| 上游 | 关系 | 使用的接口 |
|------|------|----------|
| 棋盘网格 | Hard | `get_cell_state()`, `get_neighbors()`, `cell_state_changed` 信号 |

| 下游 | 关系 | 提供的接口 |
|------|------|----------|
| 怪物系统 | Hard | `get_main_path()`, `path_updated` 信号 |
| 障碍方块 | Hard | `is_path_reachable()` 放置前预检查 |
| HUD/UI | Soft | `get_path_length()` |

## Tuning Knobs

寻路系统没有可调参数——启发式权重固定为 1。路径行为完全由棋盘状态（方块/塔位置）决定。

## Visual/Audio Requirements

不适用。以下效果由其他系统基于寻路数据触发：

| 效果 | 数据来源 | 触发系统 |
|------|---------|---------|
| 怪物路径线显示 | `get_main_path()` | 视觉反馈系统 |
| 路径阻断警告 | `path_blocked` 信号 | 视觉反馈 |
| 放置预览变红 | `is_path_reachable() == false` | 障碍方块 |

## UI Requirements

不适用。`get_path_length()` 可被 HUD 用于显示路线长度——但显示由 HUD/UI 系统负责。

## Acceptance Criteria

- **GIVEN** 空棋盘+入口(0,7)+出口(19,7)，**WHEN** `get_main_path()` 被调用，**THEN** 返回直线最短路径（20 步）
- **GIVEN** (10,7) 被 BLOCK 占据，**WHEN** 路径重算，**THEN** 新路径绕开 (10,7)，长度 > 20
- **GIVEN** 所有路径被完全堵死，**WHEN** 最后一块方块放下，**THEN** `get_main_path()` 返回空数组，`path_blocked` 信号发射
- **GIVEN** 10 只怪物正在行进，**WHEN** `path_updated` 信号发射，**THEN** 所有怪物更新路径
- **GIVEN** 放置方块会堵死路，**WHEN** `is_path_reachable()` 返回 false，**THEN** 方块系统阻止放置

## Open Questions

1. **多入口支持**：未来是否允许多个怪物入口？当前假设 1 ENTRANCE + 1 EXIT
2. **路径平滑**：AStarGrid2D 返回网格坐标序列——怪物逐格走。是否需要曲线平滑？→ MVP 不需要，逐格走符合棋盘美学
3. **性能验证**：300 格 A* < 1ms 是理论值——需要在 Godot 4.6 中实测
