# ADR-0005: TileMapLayer 网格渲染

## Status
Accepted

## Date
2026-06-01

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Rendering |
| **Knowledge Risk** | MEDIUM — TileMap→TileMapLayer 迁移（4.3）在 LLM 训练截止边界；TileMapLayer 在 4.6 中已稳定 |
| **References Consulted** | `docs/engine-reference/godot/modules/rendering.md`, `docs/engine-reference/godot/deprecated-apis.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/current-best-practices.md` |
| **Post-Cutoff APIs Used** | `TileMapLayer` (4.3+ replaces deprecated `TileMap`) |
| **Verification Required** | Compatibility (OpenGL 3.3) 渲染器下 300 格棋盘无锯齿、无接缝验证；全量初始化 + 100 次 set_cell() 性能基准 |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (SignalBus — `cell_state_changed` 和 `phase_changed` 信号触发重绘和透明度切换) |
| **Enables** | BoardGrid 系统的视觉实现；视觉反馈系统（路径线、塔范围指示器的坐标参考）；HUD 的鼠标→网格坐标反馈 |
| **Blocks** | None directly |
| **Ordering Note** | 棋盘网格的 API 契约已通过 GDD 定义。本 ADR 仅决定渲染层——在 BoardGrid 实现前 Accepted 即可。注意：ADR-0003 (AStarGrid2D) 和 ADR-0005 (TileMapLayer) 都订阅 `cell_state_changed`——两者是独立消费者，执行顺序不保证且不应依赖。 |

## Context

### Problem Statement

BoardGrid GDD 定义了 20×15 = 300 格的棋盘。网格需要渲染两类视觉元素：
1. **网格线**：1-2px 正交直线，实线无虚线无圆角，石板灰配色（`#4A6078`），PREP 阶段 70-80% 可见度，BATTLE 阶段 ~60% 可见度
2. **单元格底色**：区分 EMPTY / BLOCK / TOWER / ENTRANCE / EXIT 五种状态

Godot 4.3+ 废弃了 `TileMap` 节点（改用 `TileMapLayer`），同时 `_draw()` 自定义绘制也完全可以胜任 300 格的规模。需要在这两种渲染路径之间做出选择。

项目使用 **Compatibility 渲染器**（OpenGL 3.3）——渲染后端选择（D3D12/Vulkan）仅适用于 Forward+ 和 Mobile 渲染器，对本 2D 项目无影响。所有验证基于 Compatibility 渲染路径。

### Constraints
- 必须响应 `SignalBus.cell_state_changed` 信号——单个格子的状态变更后，只重绘该格（不是全量重绘 300 格）
- 支持 PREP/BATTLE 两阶段的网格透明度不同（通过 `SignalBus.phase_changed` 触发）
- 网格线不能被战斗特效遮挡（美术圣经：特效透明度 ≤40%，网格线始终可见度 ≥60%）
- 棋盘底色 `#263040` + 网格线 `#4A6078` 必须精确匹配美术圣经规定的配色
- MVP 目标——方案应尽量简单，不引入不必要的资产管线复杂度

### Requirements
- 单个 `cell_state_changed` → 单格重绘延迟 < 0.1ms
- 棋盘初始化 300 格全量渲染 < 0.5ms
- 阶段切换（PREP↔BATTLE）的网格透明度切换 < 0.1ms
- 网格线在 56×56px 单元格尺寸下视觉均匀（无断裂、无锯齿）
- 对齐 ADR-0002 的数据驱动原则——棋盘尺寸等配置参数应可导出/可配置

## Decision

采用 **纯 TileMapLayer 方案**：单元格底色和网格线都通过 TileMapLayer + TileSet 渲染。不使用 `_draw()`。

### 架构

```
┌─────────────────────────────────────────────────┐
│              BoardGrid (Node2D)                  │
│  — 数据层（grid_data: Array[CellState]）          │
│  — API: get/set_cell_state(), grid_to_world()   │
│                                                   │
│  ┌──────────────────────────────────────────┐   │
│  │  GridRenderer (TileMapLayer)              │   │
│  │  — TileSet: grid_tiles.tres              │   │
│  │  — 单 atlas source，5 个 tile             │   │
│  │  — modulate.a 控制阶段透明度              │   │
│  │  — 物理层: 完全禁用                       │   │
│  │  — texture_filter: Nearest（避免接缝模糊） │   │
│  └──────────────────────────────────────────┘   │
│                                                   │
│  ┌──────────────────────────────────────────┐   │
│  │  GridOverlay (Node2D, 可选 — V1.0)       │   │
│  │  — _draw() 用于路径线/塔范围叠加          │   │
│  │  — 需要像素精度的 overlay 效果             │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘

信号流:
  BoardGrid.set_cell_state()
    → grid_data 更新
    → GridRenderer.set_cell()  (同步——单元格视觉更新)
    → SignalBus.cell_state_changed.emit()  (其他系统响应)
  
  注意：GridRenderer 和 AStarGrid2D (ADR-0003) 都订阅 cell_state_changed。
  两者是独立消费者——执行顺序不保证，且不应依赖对方先/后执行。

阶段切换:
  SignalBus.phase_changed
    → GridRenderer → modulate.a = PREP ? 0.8 : 0.6
```

### TileSet Source Organization

采用 **单个 TileSetAtlasSource** 方案——5 个 tile 在同一 atlas 纹理的不同坐标位置，通过 `source_id = 0` + 不同的 `atlas_coords` 区分：

| `atlas_coords` | CellState | 底色 | 边框 |
|----------------|-----------|------|------|
| `(0, 0)` | EMPTY | `#263040` 石板灰 | `#4A6078` 1-2px |
| `(1, 0)` | BLOCK | 比 EMPTY 略亮 | `#4A6078` 1-2px |
| `(2, 0)` | TOWER | 塔专用底色 | `#4A6078` 1-2px |
| `(3, 0)` | ENTRANCE | 入口标记色 | `#4A6078` 1-2px |
| `(4, 0)` | EXIT | 出口标记色 | `#4A6078` 1-2px |

所有 tile 尺寸 56×56px。网格线由相邻 tile 的边框拼合而成——不需要单独画线。

**为什么单 atlas 而非多 source？**
- 单 atlas 是 Godot 4 的标准 TileMapLayer 模式——一个 tileset 通常对应一个 atlas 纹理
- 简化纹理管理——只需一张 atlas 图（或 5 个纯色 tile 在 TileSet 编辑器中直接绘制）
- `set_cell()` 调用更直观：`set_cell(Vector2i(col, row), 0, Vector2i(state_id, 0))`——`state_id` 就是 `CellState` 枚举值到 atlas X 坐标的映射

### TileSet 渲染参数

| 参数 | 值 | 原因 |
|------|-----|------|
| `texture_filter` | **Nearest** | 防止 tile 接缝处的边框像素渗色/模糊。Linear 过滤在非整数缩放时会采样相邻像素，导致 1-2px 网格线在接缝处变粗 |
| `tile_size` | `Vector2i(56, 56)` | 匹配 GDD 的 `CELL_SIZE` |

### 物理层：完全禁用

网格渲染不需要碰撞检测——碰撞由 BoardGrid 数据层管理（`get_cell_state()` 查询即可）。不为 TileMapLayer 配置任何 PhysicsLayer。由于物理层完全禁用，`physics_quadrant_size` 设置无实际影响——TileMapLayer 下无物理体可被分块。

### 阶段透明度

```gdscript
func _on_phase_changed(_old: int, new: int) -> void:
    modulate.a = 0.8 if new == Phase.PREP else 0.6
```

`modulate.a` 作用于整个 TileMapLayer 的所有 quad——一次属性修改即可完成 300 格的透明度切换，零 CPU 开销。注意：`modulate.a` 会继承到 GridRenderer 的所有子节点。如需在 GridRenderer 下添加不受阶段透明度影响的子节点（如调试标签），该子节点需在 `_ready()` 中显式设置 `modulate.a = 1.0` 覆盖继承值。

### Key Interfaces

```gdscript
## GridRenderer — 棋盘网格的 TileMapLayer 渲染器
## 作为 BoardGrid 的子节点，负责将所有 CellState 变更同步到视觉层
class_name GridRenderer extends TileMapLayer

## TileSet 资源引用——单 atlas source，5 个 tile（EMPTY/BLOCK/TOWER/ENTRANCE/EXIT）
@export var grid_tileset: TileSet

## 棋盘尺寸（可通过导出参数或 GridConfig Resource 调整——对齐 ADR-0002 数据驱动原则）
@export var cols: int = 20
@export var rows: int = 15

## CellState 枚举值 → TileSet atlas X 坐标的映射
## EMPTY=0, BLOCK=1, TOWER=2, ENTRANCE=3, EXIT=4 → atlas_coords = (state, 0)
static func _atlas_coords_for_state(state: int) -> Vector2i:
    return Vector2i(state, 0)

## 初始化：遍历 BoardGrid 数据，全量 set_cell 建立初始视觉
## source_id 固定为 0（单 atlas source），atlas_coords 按 CellState 映射
func initialize(board_data: Array) -> void:
    for row in rows:
        for col in cols:
            var state: int = board_data[row][col]
            set_cell(Vector2i(col, row), 0, _atlas_coords_for_state(state))

## 响应 SignalBus.cell_state_changed——仅更新单个格子的 tile
func _on_cell_state_changed(col: int, row: int, _old: int, new: int) -> void:
    set_cell(Vector2i(col, row), 0, _atlas_coords_for_state(new))

## 响应 SignalBus.phase_changed——调整整个网格的透明度
func _on_phase_changed(_old: int, new: int) -> void:
    modulate.a = 0.8 if new == Phase.PREP else 0.6
```

## Alternatives Considered

### Alternative 1: 纯 _draw() 自定义绘制

- **Description**: 在 Node2D 子类的 `_draw()` 中通过 `draw_rect()` 逐个绘制 300 格的底色和网格线。`queue_redraw()` 触发全量重绘。
- **Pros**: 像素级控制——线宽、颜色、间距可纯代码调整，无需 tileset 资产。无外部资产依赖，所有视觉逻辑在代码中。
- **Cons**: 单个 `cell_state_changed` 触发全量 300 格重绘（`queue_redraw()` 无增量更新能力）；网格线不在编辑器中预览；后续叠加路径线和塔范围需要用额外的 Node2D 层管理
- **Rejection Reason**: 300 格的全量重绘性能可接受，但随着波次推进（路径线、伤害数字、技能特效等多个 overlay），多个 `_draw()` 层的管理复杂度会上升。TileMapLayer 的每格增量更新 + GPU 批处理更适合有大量动态叠加层的场景。

### Alternative 2: 混合方案——TileMapLayer 底色 + _draw() 网格线

- **Description**: TileMapLayer 只渲染单元格底色（无边框），网格线由另一个 Node2D 的 `_draw()` 单独绘制（20 条横线 + 15 条竖线 = 35 条线）。两个节点分离，互不干扰。
- **Pros**: 底色更新走 TileMapLayer 增量（高效），网格线纯代码控制（灵活）。网格线层的 `queue_redraw()` 只在棋盘初始化时调用一次——因为网格线是静态的。
- **Cons**: 两个节点维护同一网格的视觉——增加节点层级。网格线的 `_draw()` 层和 TileMapLayer 底色层需要精确对齐。
- **Rejection Reason**: 对 MVP 来说多了一个不必要的节点。所有 tile 自带边框就自然形成网格线——单独画线层是在解决 TileMapLayer 自己就能解决的问题。

## Consequences

### Positive
- 单格增量更新——`set_cell()` 只重建 GPU 端一个 quad，不触碰其他 299 格
- 阶段透明度切换零开销——`modulate.a` 一次属性写入，GPU 端自动应用于所有 quad
- 编辑器内可见——设计师可在 Godot 编辑器中直接看到棋盘布局，无需运行游戏
- TileSet 是单一资产文件（.tres）——与 ADR-0002（Resource 系统）的资产管线一致
- 网格线与底色是同一个 tile 的组成部分——永不脱节、永不偏移
- 单 atlas source 模式——set_cell 调用简洁，纹理管理简单

### Negative
- 网格线颜色和线宽变更需要修改 tileset 纹理资产——不能纯代码调整
- 若未来需要非正交网格线（如斜线、曲线、动画线），TileMapLayer 不适合——需要用其他方案
- TileMapLayer 自带功能（物理、导航、occlusion）大多不需要——需要显式禁用以免意外性能开销
- `modulate.a` 作用于整个 TileMapLayer——不能对不同 CellState 使用不同透明度。若未来有此类需求，需拆分多个 TileMapLayer。同时 `modulate.a` 会继承到所有子节点——子节点需显式覆盖
- `@export var cols/rows` 仅在编辑器中可调——运行时仍需与 BoardGrid 数据层同步。若两者不一致，GridRenderer 的 `initialize()` 会越界或漏格

### Risks
- **TileSet 资产管线耦合**: 修改配色需要重新编辑 TileSet → 可能引入视觉不一致。**缓解措施**: MVP 阶段 tileset 纹理极简（5 个纯色方块 + 边框），用 Godot 内置的 TileSet 编辑器即可创建——不需要外部图像编辑器。Nearest 过滤确保边框像素无模糊
- **TileMapLayer 重叠管理**: 若视觉反馈系统未来添加覆盖层（路径线）也用 TileMapLayer，两个 TileMapLayer 的 Z 顺序需要管理。**缓解措施**: 在 architecture.md 中规定渲染层级顺序——GridRenderer 在最底层，覆盖层在上
- **canvas_items 非整数缩放**: `expand` 模式下窗口缩放可能导致非整数 scale factor → tile 边框落在亚像素位置 → 网格线粗细不均。**缓解措施**: 开启 `rendering/2d/snap/snap_2d_transforms_to_pixel` 项目设置，将 transform 吸附到整像素。若问题仍存，限制窗口尺寸为基准分辨率的整数倍
- **cols/rows 不同步**: 若 GridRenderer 的 `@export cols/rows` 与 BoardGrid 数据层不一致 → 渲染越界。**缓解措施**: `initialize()` 接受 board_data 参数，实际尺寸由数据层决定——`@export` 值只作为编辑器预览的默认值

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| board-grid.md | 网格线 1-2px 正交直线，`#4A6078`，PREP 70-80% / BATTLE ~60% 可见度 | TileSet tile 自带边框形成网格线；`modulate.a` 控制阶段透明度 |
| board-grid.md | 5 种 CellState 视觉区分 | 单 atlas source，5 个 tile 按 atlas_coords (0,0)~(4,0) 映射 |
| board-grid.md | 单元格尺寸 56×56px，20×15 总 300 格 | TileMapLayer cell_size = (56, 56)；`@export cols/rows` 可调 |
| board-grid.md | `cell_state_changed` → 单格增量重绘 | `_on_cell_state_changed()` → `set_cell()` 单格更新 |
| art-bible.md | 网格底色 `#263040`，网格线不被特效遮挡 | TileMapLayer 在最底渲染层；Nearest 过滤保证接缝无模糊 |
| art-bible.md | Section 3.2 网格线 / Section 4.1 配色 | TileSet tile 底色+边框精确匹配配色值 |

## Performance Implications
- **CPU**: 单格 `set_cell()` < 0.1ms。全量初始化 300 格 < 0.5ms。阶段透明度切换零 CPU——`modulate.a` 是 GPU 端属性
- **Memory**: TileSet 资源 ~2KB（5 个 56×56 纯色 tile）。TileMapLayer 运行内存 ~12KB（300 个 quad × 40 bytes）——可忽略
- **Load Time**: TileSet .tres 加载 < 1ms。无额外纹理文件 I/O（tile 在 TileSet 编辑器内绘制）
- **Network**: 不适用（离线游戏）

## Migration Plan
不适用——新项目，无现有代码迁移。BoardGrid 系统的渲染层直接从 TileMapLayer 开始实现。

## Validation Criteria
1. **视觉验证**: Compatibility (OpenGL 3.3) 渲染器下 300 格棋盘——网格线均匀（1-2px），五色 CellState 清晰可辨，无断裂、无锯齿、tile 接缝处无边框模糊
2. **性能**: 全量初始化（300×set_cell）+ 100 次随机 `set_cell()` 更新总耗时 < 2ms
3. **透明度**: PREP→BATTLE 切换时 `modulate.a` 正确变为 0.8→0.6，帧时间无可见尖峰
4. **物理隔离**: GridRenderer 不参与任何碰撞检测——raycast/overlap 都不会命中网格层
5. **Nearest 过滤**: tile 接缝处用放大镜验证——无像素渗色、无边框重影
6. **缩放完整性**: canvas_items expand 模式下，窗口在 1080p / 1440p / 4K 下网格线粗细均匀

## Related Decisions
- ADR-0001: SignalBus — `cell_state_changed` 和 `phase_changed` 信号的发射和订阅
- ADR-0002: 数据配置 Resource 系统 — `@export` 参数对齐数据驱动原则
- ADR-0003: AStarGrid2D 集成 — 共享 `cell_state_changed` 订阅（独立消费者，顺序不保证）
- `design/gdd/board-grid.md` — BoardGrid API 契约 + 视觉规格
- `design/art/art-bible.md` — Section 3.2（网格线）、Section 4.1（配色）
- `docs/architecture/architecture.md` — Master Architecture（BoardGrid 模块在 Foundation 层）
