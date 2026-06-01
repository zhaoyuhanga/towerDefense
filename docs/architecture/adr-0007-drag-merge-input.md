# ADR-0007: 拖拽合星输入架构

## Status
Accepted

## Date
2026-06-01

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Input |
| **Knowledge Risk** | LOW — 标准 `InputEventMouse` 处理，无 post-cutoff API 变更 |
| **References Consulted** | `docs/engine-reference/godot/modules/input.md`, `docs/engine-reference/godot/VERSION.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | 拖拽阈值测试（2px 移动 = 点击，4px 移动 = 拖拽）；100 次拖拽合星无事件丢失；阶段切换强制取消拖拽 |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001（SignalBus — `cell_state_changed` 等信号）；ADR-0006（PhaseManager — 阶段门控） |
| **Enables** | 合星升级系统（merge-upgrade）、防御塔系统（tower placement）、障碍方块系统（block placement）、应急技能系统（skill activation） |
| **Blocks** | None directly |
| **Ordering Note** | 输入路由是 Foundation 层——必须在任何 Core/Feature 系统实现前 Accepted。ADR-0006（阶段门控）应先就位 |

## Context

### Problem Statement

玩家通过鼠标与游戏世界交互——点击放塔、拖拽合星、右键出售、点击按钮。这些原始 `InputEvent` 需要被翻译成语义明确的游戏动作并路由到正确的目标系统。核心挑战：

1. **路由歧义**：一次鼠标点击可能对应多个系统——塔系统（选择塔）、方块系统（放置方块）、UI（点击按钮）。谁决定路由？
2. **拖拽 vs 点击**：同一次鼠标按下+释放，移动 2px 是点击（选中塔），移动 10px 是拖拽（合星）。阈值和状态机由谁管理？
3. **预览归属**：拖拽时塔跟随鼠标的"幽灵预览"——由 InputHandler 渲染还是合星系统渲染？
4. **阶段门控**：BATTLE 阶段棋盘上的点击应被忽略——谁负责过滤？

### Constraints
- 鼠标独占——MVP 无键盘快捷键（但代码结构应为未来键盘输入预留扩展点）
- 阶段门控——PREP 和 BATTLE 有不同的输入许可集
- UI 优先——落在 UI 按钮上的点击不穿透到棋盘
- 每个原始事件最多产生一个游戏动作（单路由原则）

### Requirements
- 拖拽检测阈值 3px（GDD 定义）
- 点击 vs 拖拽判定在一帧内完成
- 拖拽中阶段切换 → 强制取消拖拽，预览消失
- 右键取消拖拽 → 塔弹回原位
- 合星预览（被拖拽的塔）跟随鼠标，半透明

## Decision

采用 **混合路由架构**：InputHandler 作为集中式路由器 + 拖拽状态机。各目标系统自行渲染预览。输入路由通过阶段门控的优先级链决定目标。

### 架构

```
┌──────────────────────────────────────────────────────────┐
│                     InputHandler (Node)                    │
│  作为 LevelScene 的子节点——所有鼠标输入的唯一入口             │
│                                                           │
│  ┌─────────────────────────────────────────────────┐     │
│  │  Drag State Machine (内嵌)                        │     │
│  │  IDLE → PRESSING → DRAGGING → RELEASING → IDLE  │     │
│  │  — drag_start_pos: Vector2                       │     │
│  │  — dragged_tower: Tower                          │     │
│  │  — drag_threshold: float = 3.0                   │     │
│  └─────────────────────────────────────────────────┘     │
│                                                           │
│  _input(event) → 阶段门控 → 优先级路由 → 目标系统调用        │
│                                                           │
│  优先级链:  UI 按钮 > TOWER > BLOCK > EMPTY > 虚空         │
└────────────┬─────────────────────────────────────────────┘
             │ 调用目标系统的方法
             ▼
┌──────────────────────────────────────────────────────────┐
│  各系统自行管理预览渲染                                     │
│                                                           │
│  MergeSystem:  拖拽幽灵塔（semi-transparent tower sprite）  │
│  TowerSystem:  放置预览（绿色/红色高亮目标格）               │
│  BlockSystem:  放置预览方块（半透明跟随鼠标）                │
│  SkillSystem:  技能按钮 hover/active 状态                  │
└──────────────────────────────────────────────────────────┘
```

### 拖拽状态机

```
                    mouse_pressed                moved > threshold
    IDLE ────────────────────▶ PRESSING ──────────────────────────▶ DRAGGING
     ▲                            │                                      │
     │                            │ moved < threshold + released          │ released
     │                            ▼                                      ▼
     │                      (emit grid_clicked)                   RELEASING ──▶ IDLE
     │                                                                      │
     └──────────────────────────────────────────────────────────────────────┘
```

| 状态 | 含义 | 允许的操作 |
|------|------|-----------|
| `IDLE` | 无按下 | 等待 `InputEventMouseButton.pressed` |
| `PRESSING` | 鼠标按下但尚未判定 | 跟踪鼠标移动；若 `distance > 3px` → DRAGGING；若 `released` → grid_clicked |
| `DRAGGING` | 确认拖拽中 | 鼠标移动更新预览位置；若 `released` → RELEASING |
| `RELEASING` | 拖拽释放 | 判定释放目标格 → 调用目标系统；若目标无效 → 弹回 |

**阶段切换中断**：当 `SignalBus.phase_changed` 在 DRAGGING 状态中被发射 → 强制回 IDLE，丢弃当前拖拽。

### 输入优先级链

InputHandler 在 `_input()` 中对鼠标事件按以下优先级路由：

```
1. UI 按钮命中测试           → Control 节点命中检测。若命中 → 传递给 UI，不继续
2. TOWER 格（左键拖拽）      → world_to_grid() → 若为 TOWER → 进拖拽状态机
3. TOWER 格（左键点击）      → 若为 TOWER → 选中该塔
4. TOWER 格（右键点击）      → 若为 TOWER → 出售确认
5. BLOCK 格（右键点击）      → 若为 BLOCK → 移除方块
6. EMPTY 格（左键点击）      → 放置当前选中物（塔或方块）
7. EMPTY 格（左键拖拽释放）   → 取消拖拽（无效目标）
8. 虚空 / 棋盘外             → 取消选择 / 取消拖拽
```

每个步骤先通过 PhaseManager 做阶段门控——步骤 2-7 在 BATTLE 阶段全部跳过。

### 预览渲染：各系统自行管理

InputHandler **不渲染任何预览**。它只调用目标系统的方法：

| 预览类型 | 负责系统 | 渲染方式 |
|----------|---------|---------|
| 拖拽幽灵塔 | MergeSystem | `_process()` 中设 `global_position = get_global_mouse_position()`；`modulate.a = 0.6` |
| 放置预览（绿/红高亮） | TowerSystem / BlockSystem | 目标格上半透明精灵——绿色 = 可放置，红色 = 不可放置 |
| 塔攻击范围指示器 | TowerSystem | 选中塔时显示攻击范围圆环 |

### 双操作模式（桌面端补偿）

| 模式 | 触发方式 | 适用场景 |
|------|---------|---------|
| **拖拽合星**（主） | 左键按住塔 → 拖到同类型同星塔上释放 | 快速、直观 |
| **右键菜单合星**（辅） | 右键点击已选中塔 → 弹出菜单 → "合星到相邻塔" | 精确、不需拖拽 |

### 输入撤销/缓冲策略

- **拖拽中右键**：`cancel_drag()` → 塔弹回原位
- **拖拽中阶段切换**：`SignalBus.phase_changed` → `cancel_drag()` → 不排队不缓冲
- **阶段切换动画期间的点击**：丢弃（切换动画 0.5-0.8s 期间的输入不缓冲）
- **快速连续点击**：每次独立处理——选中新目标，取消旧选择

### Key Interfaces

```gdscript
## InputHandler — 鼠标输入的单一入口 + 路由层
class_name InputHandler extends Node

@export var drag_threshold: float = 3.0

enum DragState { IDLE, PRESSING, DRAGGING, RELEASING }
var drag_state: DragState = DragState.IDLE
var drag_start_pos: Vector2
var drag_target: Tower
var _current_phase: int = 0  # Phase.PREP，通过 SignalBus 同步

func _ready() -> void:
    SignalBus.phase_changed.connect(_on_phase_changed)

func _input(event: InputEvent) -> void:
    # 1. UI 优先——Control 节点命中测试
    # 2. 阶段门控
    # 3. world_to_grid()
    # 4. 优先级链路由
    # 5. 调用目标系统方法
    pass
```

```gdscript
## MergeSystem 暴露给 InputHandler 的拖拽接口
class_name MergeSystem extends Node

func start_drag(tower: Tower) -> void:       # 开始拖拽——创建幽灵预览
func update_drag_preview() -> void:          # 更新幽灵位置
func try_merge(from_col, from_row, to_col, to_row) -> bool:  # 尝试合星
func cancel_drag() -> void:                  # 取消拖拽——弹回
```

## Alternatives Considered

### Alternative 1: 集中式 InputHandler（含预览渲染）
- **Description**: InputHandler 拥有所有拖拽状态 + 也渲染所有预览。
- **Rejection Reason**: Foundation 层不应包含渲染逻辑——违反架构分层原则。

### Alternative 2: 纯分布式信号路由
- **Description**: InputHandler 只发射语义信号，各系统自行订阅处理。
- **Rejection Reason**: 多系统可能同时响应同一事件——单路由原则需要一个集中仲裁者。

## Consequences

### Positive
- 优先级链在一个地方强制执行，不依赖各系统的自觉
- 拖拽状态机集中管理——阶段切换中断、右键取消、阈值判定
- 预览分散到各系统——改幽灵塔透明度不影响放置预览
- 双操作模式解决桌面端拖拽手感问题
- 为键盘快捷键预留扩展点

### Negative
- InputHandler 需要调用 5+ 个目标系统——每个新系统需注册路由规则（但复杂度线性，非 N×N）
- 右键菜单合星需要 MergeSystem 额外暴露"查询相邻可合星目标"接口
- 预览视觉一致性无集中管控——各系统需遵循美术圣经自行约束

### Risks
- **InputHandler 膨胀**: 系统增加时优先级链变长。缓解：提取 `_route_prep_input()` / `_route_battle_input()`；系统 > 10 时考虑注册表模式
- **幽灵预览性能**: 拖拽时每帧更新幽灵位置。缓解：只设 `global_position` + `modulate.a`——无动画无粒子，< 0.1ms
- **拖拽释放判定精度**: 快速拖拽释放时鼠标跨格。缓解：使用释放瞬间的 `world_to_grid()` 作为目标格，不回溯路径

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| input-handling.md | 阶段门控——PREP/BATTLE 不同输入许可 | InputHandler 在路由前检查 `_current_phase` |
| input-handling.md | 拖拽检测阈值 3px | `drag_threshold = 3.0` 在状态机中 |
| input-handling.md | 冲突优先级：UI > Tower > Block > Empty > Void | 集中式优先级链 |
| input-handling.md | 拖拽中阶段切换 → 强制取消 | `SignalBus.phase_changed` → `cancel_drag()` |
| input-handling.md | 右键取消拖拽 | DRAGGING 状态下右键 → `cancel_drag()` |
| merge-upgrade.md | 拖拽合星——同类型同星级 | InputHandler 判定 → `MergeSystem.try_merge()` |
| merge-upgrade.md | 合星失败弹回 | `try_merge()` 返回 false → 弹回动画由 MergeSystem 处理 |
| merge-upgrade.md | 建造阶段独占 | BATTLE 阶段不进入 PRESSING 状态 |

## Performance Implications
- **CPU**: `_input()` 每次鼠标事件 < 0.1ms。拖拽中 `_process()` 幽灵预览 < 0.1ms
- **Memory**: InputHandler ~1KB + 拖拽状态机 4 字段 ~32 bytes
- **Load Time**: 零影响
- **Network**: 不适用

## Migration Plan
不适用——新项目。

## Validation Criteria
1. **拖拽阈值**: 移动 2px → 释放 = 点击；移动 4px → 进入 DRAGGING
2. **优先级链**: UI 按钮不穿透到棋盘；TOWER 格拖拽优先于 EMPTY 格点击
3. **阶段门控**: BATTLE 阶段棋盘无响应；技能按钮仍可点击
4. **拖拽取消**: 右键中断 + 阶段切换中断 → 幽灵消失，塔在原位
5. **合星路由**: 同类型同星 → `try_merge()`；不同类型 → 弹回
6. **双模式**: 右键菜单合星可用
7. **无事件丢失**: 100 次快速拖拽合星——无一丢失或路由错误

## Related Decisions
- ADR-0001: SignalBus — `cell_state_changed`, `phase_changed` 等信号
- ADR-0006: PhaseManager — 阶段门控
- `design/gdd/input-handling.md` — 输入动作映射表
- `design/gdd/merge-upgrade.md` — 合星条件 + `try_merge()` 接口
- `docs/architecture/architecture.md` — InputHandler 和 MergeSystem 的模块定义
