# ADR-0003: AStarGrid2D 集成与 Godot 4.6 兼容

## Status
Accepted

## Date
2026-06-01

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Navigation |
| **Knowledge Risk** | **HIGH** — AStarGrid2D 行为在 4.6 中变更：`get_id_path()` 在起点为 solid 时返回空数组 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/current-best-practices.md` |
| **Post-Cutoff APIs Used** | `AStarGrid2D.get_id_path()` (behavior changed in 4.6), `AStarGrid2D.is_point_solid()` |
| **Verification Required** | 300 格全量重算性能基准测试（目标 < 1ms）；solid point 行为验证 |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | ADR-0005 (TileMapLayer)，障碍方块系统，怪物系统 |
| **Blocks** | 障碍方块系统（路径可达性检查）、怪物系统（路径跟随） |
| **Ordering Note** | 必须在障碍方块和怪物系统实现前 Accepted |

## Context

### Problem Statement

Mazing 塔防的核心机制依赖寻路：每次方块放置/移除后必须即时重算路径。Godot 4.6 的 AStarGrid2D 是自然选择——但 4.6 引入了关键行为变更：`get_id_path()` 和 `get_point_path()` 在 `from_id` 为 disabled/solid 点时返回空数组（而非 4.5 的部分结果）。这意味着每次寻路前必须显式检查 `is_point_solid()`，否则寻路会静默失败。

此外需要决定：20×15=300 格的棋盘，每次变更全量重算 A* 是否满足 60fps 预算。

### Constraints
- Godot 4.6 引擎
- 20×15=300 格棋盘
- 每次方块放置/移除/塔放置/塔出售都触发寻路重算
- 60fps (16.6ms 帧预算)，寻路重算必须在 < 2ms 内完成

### Requirements
- ENTRANCE→EXIT 最短路径在每次棋盘变更后自动重算
- 性能必须满足 60fps——最坏情况（满方块）不能卡帧
- `is_path_reachable()` 预检查必须可靠——不能漏掉"堵死路"的情况

## Decision

使用 **Godot AStarGrid2D + 全量重算 + 预检查 guard**。

### 核心策略

1. **全量重算**：每次 `cell_state_changed` 信号 → 更新对应点的 `solid` 状态 → `AStarGrid2D.update()` → 全量 `get_id_path()`。300 格 A* 预计 < 1ms，MVP 不实现增量更新。
2. **Solid Point Guard**：所有寻路调用前检查 `is_point_solid(from_id)`。ENTRANCE 和 EXIT 格在初始化时设为非 solid。
3. **性能验证**：实现后立即用 Godot 性能分析器测试——如果 > 2ms，切换到增量更新策略（仅更新受影响区域）。

### 实现伪代码

```gdscript
extends Node

var astar: AStarGrid2D
var grid_size := Vector2i(20, 15)
var entrance_pos: Vector2i
var exit_pos: Vector2i
var main_path: Array[Vector2i] = []

func _ready():
    astar = AStarGrid2D.new()
    astar.region = Rect2i(Vector2i.ZERO, grid_size)
    astar.cell_size = Vector2i(1, 1)
    astar.update()
    SignalBus.cell_state_changed.connect(_on_cell_state_changed)

func _on_cell_state_changed(col: int, row: int, old: int, new: int):
    var pos := Vector2i(col, row)
    astar.set_point_solid(pos, new == CELL_BLOCK or new == CELL_TOWER)
    _recalculate_path()

func _recalculate_path():
    if astar.is_point_solid(entrance_pos):  # ⚠️ 4.6 GUARD
        main_path = []
        SignalBus.path_blocked.emit()
        return
    main_path = astar.get_id_path(entrance_pos, exit_pos)
    if main_path.is_empty():
        SignalBus.path_blocked.emit()
    else:
        SignalBus.path_updated.emit(main_path)

func is_path_reachable() -> bool:
    if astar.is_point_solid(entrance_pos):
        return false
    var test := astar.get_id_path(entrance_pos, exit_pos)
    return not test.is_empty()
```

### `is_path_reachable()` 实现

障碍方块放置前的预检查——先暂设目标格为 solid → 跑寻路 → 检查结果 → 恢复：

```gdscript
func would_path_be_reachable(block_pos: Vector2i) -> bool:
    var was_solid := astar.is_point_solid(block_pos)
    astar.set_point_solid(block_pos, true)
    astar.update()
    var reachable := not astar.get_id_path(entrance_pos, exit_pos).is_empty()
    astar.set_point_solid(block_pos, was_solid)  # 恢复
    astar.update()
    return reachable
```

## Alternatives Considered

### Alternative 1: 自定义 A* 实现
- **Pros**: 完全控制算法细节；可针对 Mazing 优化（如缓存路径段）
- **Cons**: 开发成本高——A* 实现 + 调试 + 优化 ≈ 2-3 天。Godot 内置方案已够用
- **Rejection Reason**: MVP 时间有限——300 格 AStarGrid2D 性能充分，自定义实现的收益不抵成本

### Alternative 2: 增量更新（仅重算受影响区域）
- **Pros**: 理论上更高效——只更新方块周围的路径段
- **Cons**: 实现复杂——需要检测"受影响区域"、处理多路径、验证正确性
- **Rejection Reason**: MVP 阶段不需要——全量重算足够快。如果性能测试显示 > 2ms 才考虑

## Consequences

### Positive
- AStarGrid2D 是 Godot 原生——零额外代码，4.6 原生支持
- 全量重算逻辑极简——`set_point_solid()` + `update()` + `get_id_path()`，3 行
- `is_point_solid()` guard 防御了 4.6 行为变更——不会出现"静默空路径"

### Negative
- 全量重算每次跑完整的 300 格 A*——即使是只放了一块方块
- 性能未经验证——理论 < 1ms，实际需在 Godot 4.6 中测量

### Risks
- **性能不达标**（实际 > 2ms）：缓解——切换到增量更新。触发条件：性能测试 > 2ms
- **AStarGrid2D 在极端填充下退化**（290/300 格被占）：A* 在接近阻塞时可能遍历几乎所有剩余格。缓解——性能测试覆盖极端场景

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| pathfinding.md | 单一主路径 + 全量重算 + 不可达处理 | AStarGrid2D 实现 + `path_blocked` 信号 |
| pathfinding.md | `is_path_reachable()` 放置前预检查 | `would_path_be_reachable()` 暂设-测试-恢复 |
| pathfinding.md | Godot 4.6 兼容——solid point 返回空路径 | `is_point_solid()` guard 在每次寻路前 |
| pathfinding.md | 性能验证 < 1ms 理论值 | 性能基准测试要求 |
| obstacle-block.md | 放置方块前预检查路径 | `is_path_reachable()` |

## Performance Implications
- **CPU**: 预估 < 1ms/重算。最坏（290/300 格被占）预估 < 5ms。需实测
- **Memory**: AStarGrid2D 内部数据结构 ~300 × ~50 bytes ≈ 15KB
- **Load Time**: 零——AStarGrid2D 在棋盘初始化时创建

## Validation Criteria
- 空棋盘上 ENTRANCE(0,7)→EXIT(19,7) 返回 20 步直线路径
- (10,7) 设为 BLOCK 后路径绕行且长度 > 20
- 所有路径堵死后 `get_id_path()` 返回空数组
- 性能：300 格全量重算 < 2ms（Godot 4.6 Profiler 测量）
- `is_point_solid(entrance)` guard 在入口被意外设为 solid 时正确返回空路径

## Related Decisions
- ADR-0001: SignalBus — `path_updated` 和 `path_blocked` 通过 SignalBus 发射
- ADR-0005: TileMapLayer — 网格渲染与寻路数据分离
- `design/gdd/pathfinding.md` — 寻路系统 GDD
