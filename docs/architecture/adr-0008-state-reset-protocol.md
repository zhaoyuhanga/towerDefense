# ADR-0008: 状态重置协议 (State Reset Protocol)

## Status
Accepted

## Date
2026-06-01

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — 纯 GDScript 信号 + 节点生命周期管理 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | "再来一局" 10 次循环无状态泄漏；所有 18 系统重置后行为与首次启动一致 |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (SignalBus), ADR-0004 (MonsterPool — pool state must be cleared), ADR-0006 (PhaseManager — phase must reset to PREP) |
| **Enables** | SceneManagement (TR-scene-002/006 — "Play Again" in-place reset), SaveSystem |
| **Blocks** | None |
| **Ordering Note** | 必须在任何需要"再来一局"功能的系统之前 Accepted。建议在 Foundation 层实现之后、Feature 层开始之前完成 |

## Context

### Problem Statement

玩家结束一局游戏后点击"再来一局"——游戏需要在**不重新加载场景**的前提下，将 18 个系统全部恢复到初始状态。每个系统有自己需要清理的状态：MonsterPool 需要销毁所有活跃怪物并清空池，Economy 需要重置金币，BoardGrid 需要清空棋盘，WaveSpawner 需要重置波数计数器。如果各系统自行实现重置逻辑而不遵循统一协议，会出现三种故障模式：

1. **顺序依赖**：Economy 在 BoardGrid 之前重置 → BoardGrid 重置时尝试设置初始格状态 → 触发 `cell_state_changed` → Economy 收到信号但已经"重置过了" → 状态不同步
2. **遗漏**：某系统忘记实现重置 → 第二局开始时带着上一局的状态（如技能剩余次数、波数计数）
3. **双重重置**：系统 A 的重置触发了系统 B 的重置（通过信号级联），但系统 B 也独立响应了 `game_reset` → 双重初始化

需要一个统一的、有序的、幂等的状态重置协议。

### Constraints
- 不重新加载场景（`TR-scene-002` 要求）——`change_scene()` 太慢，且会断开所有信号连接
- 18 个系统分布在 5 个架构层——Foundation 最后重置（它是新状态的"画布"），Feature 最先重置（它依赖 Core）
- 必须与现有 SignalBus 模式一致（ADR-0001）
- 重置期间禁止任何游戏逻辑（塔攻击、怪物移动、UI 更新）——PhaseManager 应先设 PAUSED 或中间态

### Requirements
- 单信号触发——"再来一局"按钮只需 emit 一个信号
- 每个系统只注册一次重置处理器
- 重复调用 `game_reset` 是安全的（幂等——已在重置状态的系统不会再次重置）
- 重置总耗时 < 1 帧（16.6ms）——纯数据操作，不涉及场景加载
- 重置后 PhaseManager 回到 PREP 状态

## Decision

采用 **SignalBus 单信号 + 系统自注册** 模式。新增 `SignalBus.game_reset_requested` 信号。每个需要重置的系统在 `_ready()` 中连接自己的 `_on_game_reset()` 处理器。重置按约定的销毁顺序执行：先销毁实体（怪物、塔、特效），再清空数据（棋盘、经济、波数），最后重置阶段。

### 重置顺序（销毁→数据→阶段）

```
Phase 1: DESTROY（销毁所有运行时实体）
  1. MonsterPool.destroy_all()        — 清空 _active + _pools，queue_free 所有节点
  2. TowerSystem.destroy_all()        — 移除所有塔实例
  3. VisualFeedback.clear_all()       — 清除所有粒子/浮动文字/路径线
  4. MergeSystem.cancel_all()         — 取消进行中的拖拽/合星动画

Phase 2: CLEAR（清空数据状态）
  5. BoardGrid.clear()                — 所有格 → EMPTY，恢复 ENTRANCE/EXIT
  6. Economy.reset()                  — gold = starting_gold
  7. WaveSpawner.reset()              — wave_number = 1
  8. EmergencySkills.reset()          — 技能次数恢复满
  9. ObstacleBlock.reset()            — 方块计数恢复满
  10. InputHandler.reset()            — 取消选择、清空拖拽状态

Phase 3: INITIALIZE（重建初始状态）
  11. DataConfig.load_all()           — 重新加载所有 .tres（确保数据一致）
  12. Pathfinding.rebuild()           — 基于清空后的棋盘重建 AStarGrid2D
  13. PhaseManager.reset_to_prep()    — current_phase = PREP，emit phase_changed
  14. HUD.refresh_all()               — 刷新所有 UI 元素到初始值
```

### 信号流

```
[Play Again Button]
    │
    ▼
PhaseManager → 短暂 PAUSED（门控所有 _process）
    │
    ▼
SignalBus.game_reset_requested.emit()
    │
    ├─→ MonsterPool._on_game_reset()
    ├─→ TowerSystem._on_game_reset()
    ├─→ VisualFeedback._on_game_reset()
    ├─→ MergeSystem._on_game_reset()
    ├─→ BoardGrid._on_game_reset()
    ├─→ Economy._on_game_reset()
    ├─→ WaveSpawner._on_game_reset()
    ├─→ EmergencySkills._on_game_reset()
    ├─→ ObstacleBlock._on_game_reset()
    ├─→ InputHandler._on_game_reset()
    ├─→ DataConfig._on_game_reset()
    ├─→ Pathfinding._on_game_reset()
    ├─→ PhaseManager._on_game_reset()
    └─→ HUD._on_game_reset()
    │
    ▼
PhaseManager → PREP（门控解除）
```

### 为什么不是集中式 ResetManager？

集中式 ResetManager 需要知道所有 18 个系统的重置方法签名——这违反了 ADR-0001 的去中心化原则。SignalBus 方案让每个系统自己注册重置处理器，ResetManager 不需要存在——PhaseManager 或 SceneManager 只需 emit 一个信号。新增系统只需 connect 信号——不需要修改任何现有代码。

### 为什么销毁先于清空？

如果先清空 BoardGrid（所有格→EMPTY），再销毁 TowerSystem 的塔——TowerSystem 销毁塔时会调用 `board.set_cell_state(tower_pos, EMPTY)`，触发 `cell_state_changed`。但 BoardGrid 刚刚已经把所有格设为 EMPTY 了——这个信号是冗余的，且可能触发路径重算。先销毁实体，再清空数据，避免了信号级联中的冗余操作。

### 幂等性保证

每个系统的 `_on_game_reset()` 必须幂等——重复调用不应产生副作用：

```gdscript
func _on_game_reset() -> void:
    if _is_resetting:
        return  # 已在重置中——防止信号级联导致的重复调用
    _is_resetting = true
    
    # ... 重置逻辑 ...
    
    _is_resetting = false
```

### Key Interfaces

```gdscript
# SignalBus (ADR-0001) — 新增信号
signal game_reset_requested()
```

```gdscript
# 每个需要重置的系统
func _ready() -> void:
    SignalBus.game_reset_requested.connect(_on_game_reset)

func _on_game_reset() -> void:
    # 1. Guard: if _is_resetting → return
    # 2. _is_resetting = true
    # 3. Execute reset logic (per Phase 1/2/3 role)
    # 4. _is_resetting = false
```

```gdscript
# SceneManager / HUD — "再来一局"按钮的响应
func _on_play_again_pressed() -> void:
    SignalBus.game_reset_requested.emit()
    # PhaseManager._on_game_reset() 会在所有系统之后执行，
    # 最终将 phase 设为 PREP —— 游戏重新开始
```

### 与现有 ADR 的整合

- **ADR-0004 (MonsterPool)**: MonsterPool 的 `_on_game_reset()` 遍历 `_active + _pools`，所有节点 `queue_free()`，清空两个数组。不走 `despawn()`（不 emit `monster_died`——重置不需要发放金币）
- **ADR-0006 (PhaseManager)**: `_on_game_reset()` 在最后执行——先设 PAUSED（门控），所有重置完成后设 PREP 并 emit `phase_changed`
- **ADR-0001 (SignalBus)**: 所有系统通过同一个 SignalBus 信号协调——不引入新的 Autoload 或 Manager 节点

## Alternatives Considered

### Alternative 1: 集中式 ResetManager

- **Description**: 一个 ResetManager 节点持有所有 18 个系统的引用，在 `reset()` 中按顺序调用每个系统的重置方法。
- **Pros**: 重置顺序显式可控；类型安全的编译期检查。
- **Cons**: ResetManager 必须知道每个系统的重置 API——新增系统需修改 ResetManager。违反了 SignalBus 的去中心化原则。18 个系统引用 → ResetManager 成为耦合枢纽。
- **Rejection Reason**: 与 ADR-0001 的去中心化通信模式冲突。SignalBus 方案新增系统无需修改任何现有代码。

### Alternative 2: 场景重载 (change_scene)

- **Description**: "再来一局"直接调用 `get_tree().change_scene_to_file("res://scenes/game.tscn")`——完全销毁旧场景，加载新场景。
- **Pros**: 零重置逻辑——Godot 引擎保证干净状态。最简单的实现。
- **Cons**: 违反 `TR-scene-002`（要求原地重置）。`change_scene()` 涉及文件 I/O、资源加载、场景树重建——耗时远超 1 帧。信号连接全部断开——需重新 connect。
- **Rejection Reason**: TR-scene-002 明确要求原地重置——场景重载不能满足性能目标（< 1 帧）。

## Consequences

### Positive
- 单信号触发——"再来一局"按钮只需一行代码：`SignalBus.game_reset_requested.emit()`
- 去中心化——新系统只需 connect 信号，不修改任何现有代码
- 幂等性 guard 防止信号级联导致的重复重置
- 重置顺序通过文档约定管理——不需要在代码中强制排序
- 与现有 SignalBus 模式完全一致（ADR-0001）

### Negative
- 重置顺序依赖约定而非代码强制——如果开发者错将"数据的 _on_game_reset()"放在"销毁的 _on_game_reset()"之前，可能出现冗余信号
- SignalBus 增加第 15 个信号——随着系统增加，总信号数会继续增长
- 没有编译期或运行时的"你忘记实现 _on_game_reset() 了吗？"检查——遗漏重置的系统会在第二局表现出"脏状态"
- 18 个系统全部同步响应同一个信号——在同一帧内依次执行。若未来某个系统的重置逻辑变重（如重新生成 300 格棋盘纹理），可能超过 16.6ms

### Risks
- **遗漏重置**: 新增系统时开发者忘记 connect `game_reset_requested` → 第二局带着脏数据。**缓解措施**: 在编码规范中规定——每个系统的 `_ready()` 必须有 `SignalBus.game_reset_requested.connect(_on_game_reset)` 或显式注释"本系统不需要重置（无状态）"。在 `/architecture-review` 中增加检查项——新 ADR 是否涉及状态？如果是，是否覆盖了重置？
- **重置顺序错误**: 数据层在销毁层之前重置 → 销毁操作触发冗余信号。**缓解措施**: 在每个系统的 `_on_game_reset()` 文档注释中写明它属于 Phase 1/2/3——代码审查时检查顺序
- **SignalBus 信号膨胀**: 第 15 个跨系统信号——但 `game_reset_requested` 是 MVP 阶段最后一个新增信号，后续新增信号需经代码审查

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| scene-management.md | TR-scene-002: "Play Again" in-place reset without change_scene/reload | SignalBus.game_reset_requested — 18 系统协调原地重置 |
| scene-management.md | TR-scene-006: Full state reset — clear grids, reset economy/wave/skills, destroy entities | 三阶段重置顺序：Destroy → Clear → Initialize |
| economy.md | Gold must reset to starting_gold on new game | Economy._on_game_reset() — Phase 2 |
| wave-spawner.md | Wave counter must reset to 1 on new game | WaveSpawner._on_game_reset() — Phase 2 |
| board-grid.md | All cells must return to EMPTY (except ENTRANCE/EXIT) on reset | BoardGrid.clear() — Phase 2 |
| monster-system.md | All active and pooled monsters must be destroyed on reset | MonsterPool.destroy_all() — Phase 1 |

## Performance Implications
- **CPU**: 18 个 `_on_game_reset()` 处理器依次执行——全部为纯数据操作（数组 clear、变量赋值、节点 queue_free）。预估总耗时 < 2ms（在 16.6ms 预算中占 12%）
- **Memory**: 重置后内存恢复到初始水平——MonsterPool 清空释放所有池化节点。无额外常驻内存
- **Load Time**: 不涉及场景重载——零文件 I/O
- **Network**: 不适用

## Migration Plan
不适用——新项目。所有系统从初始实现就包含 `_on_game_reset()`。

## Validation Criteria
1. **循环稳定性**: 10 次"再来一局"——每次的 BoardGrid 状态、Economy 余额、WaveSpawner 波数、MonsterPool.active 数量与首次启动完全一致
2. **信号幂等**: 在同一帧内连续 emit 2 次 `game_reset_requested` → 第 2 次被所有系统的 `_is_resetting` guard 拦截——无副作用
3. **Phase 正确**: 重置完成后 PhaseManager.current_phase == PREP
4. **性能**: 单次 `game_reset_requested.emit()` → 所有处理器执行完毕 < 2ms
5. **无泄漏**: MonsterPool._pools + _active 数组在重置后长度为 0

## Related Decisions
- ADR-0001: SignalBus — `game_reset_requested` 是第 15 个跨系统信号
- ADR-0004: MonsterPool — `destroy_all()` 在重置时的行为（跳过 despawn 流程）
- ADR-0006: PhaseManager — `reset_to_prep()` 作为重置的最后一步
- `design/gdd/scene-management.md` — TR-scene-002/006 的场景重置需求
- `docs/architecture/architecture-review-2026-06-01.md` — Gap 2 (MEDIUM) 的解决方案
