# [待命名] — Master Architecture

## Document Status
- **Version**: 1.0
- **Last Updated**: 2026-06-01
- **Engine**: Godot 4.6 + GDScript
- **GDDs Covered**: 18 (board-grid through audio)
- **ADRs Referenced**: None yet — 7 required (see §Required ADRs)
- **Technical Director Sign-Off**: Lean mode — self-review
- **Lead Programmer Feasibility**: Lean mode — skipped

## Engine Knowledge Gap Summary

| Domain | Risk | Impact |
|--------|------|--------|
| AStarGrid2D | HIGH | 4.6: `get_id_path()` returns empty on solid point → must check `is_point_solid()` first |
| TileMap→TileMapLayer | MEDIUM | TileMap deprecated since 4.3 → always use TileMapLayer |
| GDScript @abstract | LOW | 4.5 enhancement — use for base classes |

---

## System Layer Map

```
┌──────────────────────────────────────────────────────┐
│  PRESENTATION   HUD/UI    视觉反馈    Audio(V1.0)    │
├──────────────────────────────────────────────────────┤
│  FEATURE        波次生成   合星升级   准备阶段  应急技能│
├──────────────────────────────────────────────────────┤
│  CORE           怪物系统  防御塔   战斗/伤害  经济     │
│                 障碍方块  怪物寻路                    │
├──────────────────────────────────────────────────────┤
│  FOUNDATION     棋盘网格  数据配置  输入处理           │
│                 场景管理  存档系统                    │
├──────────────────────────────────────────────────────┤
│  PLATFORM       Godot 4.6 (TileMapLayer · AStarGrid2D │
│                 · Resources · Input · SceneTree)      │
└──────────────────────────────────────────────────────┘
```

**通信规则**：
1. 上层可调用下层接口（Core → Foundation 通过 GDD 定义的公共方法）
2. 同层通过信号解耦（`cell_state_changed`, `monster_died`, `wave_ended`）
3. 跨层禁止直接调用（Feature 不直接调 Platform）
4. Presentation 层是纯消费者——只读数据 + 订阅信号，不写入任何游戏状态

---

## Module Ownership

### Foundation Layer

| Module | Owns | Exposes | Engine APIs |
|--------|------|---------|-------------|
| **棋盘网格** | 20×15 网格状态、坐标转换 | `get/set_cell_state()`, `grid_to_world()`, `world_to_grid()`, `cell_state_changed` | TileMapLayer (MEDIUM) |
| **数据配置** | 所有 .tres 资源文件和 Resource 类定义 | TowerData, MonsterData, WaveRules, EconomyConfig, SkillConfig | Resource (LOW) |
| **输入处理** | 原始 InputEvent → 游戏动作的翻译 | 动作路由到各 Core/Feature 系统 | InputEventMouse (LOW) |
| **场景管理** | 场景加载/卸载 + 游戏状态重置 | `load_scene()`, `reset_game()` | SceneTree (LOW) |
| **存档** | 最高波数 + 设置持久化 | `load_save()`, `save()`, `get_high_score()` | ConfigFile (LOW) |

### Core Layer

| Module | Owns | Exposes | Engine APIs |
|--------|------|---------|-------------|
| **怪物寻路** | AStarGrid2D 实例 + 主路径缓存 | `get_main_path()`, `is_path_reachable()`, `path_updated` | AStarGrid2D (HIGH) |
| **障碍方块** | 方块放置/移除逻辑 + 数量管理 | `place_block()`, `remove_block()`, `block_count_changed` | — |
| **怪物系统** | 所有 Monster 实例 + 对象池 | `spawn_monster()`, `get_active_monsters()`, `take_damage()`, `monster_died` | Node2D (LOW) |
| **防御塔** | 所有 Tower 实例 + 攻击定时器 | `place_tower()`, `sell_tower()`, `get_tower()` | Timer (LOW) |
| **战斗/伤害** | 伤害计算 + 效果施加 | `process_attack()`, `damage_dealt` | — |
| **经济** | 金币余额 + 交易验证 | `spend_gold()`, `add_gold()`, `can_afford()`, `gold_changed` | — |

### Feature Layer

| Module | Owns | Exposes | Engine APIs |
|--------|------|---------|-------------|
| **波次生成** | 波次状态机 + 生成调度 | `start_wave()`, `wave_started`, `wave_ended` | Timer (LOW) |
| **合星升级** | 拖拽合星逻辑 + 动画序列 | `try_merge()`, `merge_completed`, `merge_failed` | Tween (LOW) |
| **准备阶段** | 阶段状态机 (PREP/BATTLE) | `set_phase()`, `phase_changed` | — |
| **应急技能** | 技能次数 + 冷却管理 | `activate_skill()`, `skill_activated` | Timer (LOW) |

### Presentation Layer

| Module | Owns | Exposes | Engine APIs |
|--------|------|---------|-------------|
| **HUD/UI** | 所有 CanvasLayer UI 控件 | 无（纯消费者） | Control, Label, Button (MEDIUM) |
| **视觉反馈** | 粒子效果 + 动画 + 伤害数字 | 无（纯消费者） | GPUParticles2D, Tween (LOW) |

---

## Data Flow — Key Scenarios

### 1. 方块放置 → 路径重算
```
Input处理 → ObstacleBlock.place_block()
  → BoardGrid.set_cell_state(BLOCK)    [同步]
  → cell_state_changed 信号发射
  → Pathfinding 收到信号 → 全量重算 AStarGrid2D
  → path_updated 信号发射
  → MonsterSystem: 所有活跃怪物更新路径缓存
  → VisualFeedback: 重绘路径线
```

### 2. 塔攻击 → 怪物死亡
```
Tower._on_attack_tick()  [Timer 驱动]
  → Combat.process_attack(self, target)  [同步]
  → Monster.take_damage(amount)          [同步]
  → if health ≤ 0:
      → monster_died 信号发射
      → Economy.add_gold(reward)         [同步]
      → VisualFeedback: 播放死亡动画     [信号]
```

### 3. 初始化顺序
```
1. 存档.加载设置()
2. 数据配置.加载所有 .tres → Dictionary
3. 棋盘网格.初始化(20, 15) → TileMapLayer ready
4. 怪物寻路.初始化(棋盘网格) → AStarGrid2D ready
5. 场景管理 → 显示主菜单 / 进入游戏
6. 经济.重置(starting_gold) → 准备阶段.进入(PREP)
```

---

## API Boundaries — Key Contracts

### BoardGrid (Foundation → Core)
```gdscript
func get_cell_state(col: int, row: int) -> CellState
func set_cell_state(col: int, row: int, state: CellState) -> bool
func grid_to_world(col: int, row: int) -> Vector2
func world_to_grid(world: Vector2) -> Vector2i
func is_valid_position(col: int, row: int) -> bool
signal cell_state_changed(col: int, row: int, old: CellState, new: CellState)
```

### MonsterSystem (Core → all)
```gdscript
func spawn_monster(monster_id: String) -> Monster
func get_active_monsters() -> Array[Monster]
func take_damage(monster: Monster, amount: float)
func apply_effect(monster: Monster, effect: String, duration: float, value: float)
signal monster_died(monster_id: String, position: Vector2, reward: int)
signal monster_breached(position: Vector2, path: Array)
```

### Combat (Tower → Monster bridge)
```gdscript
func process_attack(tower: Tower, target: Monster) -> void
signal damage_dealt(target: Monster, amount: float, type: String)
```

### Economy (all spending modules)
```gdscript
func spend_gold(amount: int) -> bool
func add_gold(amount: int)
func can_afford(amount: int) -> bool
signal gold_changed(current: int)
```

---

## Architecture Principles

1. **数据驱动**：所有数值在 .tres 文件中——代码中无硬编码数字
2. **信号解耦**：Core 层系统通过信号通信，不直接持有对方引用（除 Foundation 查询接口外）
3. **Foundation 不依赖 Core**：棋盘/数据/输入/场景/存档——这些系统不 import 任何 Core 模块
4. **Presentation 是只读层**：UI 和 VFX 订阅信号+查询数据，永远不直接修改游戏状态
5. **每一帧可预算**：所有系统在 16.6ms 预算内运行。寻路重算 < 1ms，怪物更新 + 塔攻击 < 10ms

---

## Required ADRs

以下架构决策需在实现前通过 `/architecture-decision` 记录。按优先级排列：

### Foundation Layer (实现前必须)
| # | ADR 标题 | 覆盖 TR | 说明 |
|---|---------|---------|------|
| 1 | **事件/信号架构** | TR-grid-001, TR-path-001 | Autoload SignalBus vs 直接 connect——定义信号命名和路由模式 |
| 2 | **数据配置 Resource 系统** | TR-data-001~005 | .tres vs JSON vs CSV——确定 Resource 类继承体系和加载模式 |
| 3 | **AStarGrid2D 集成策略** | TR-path-001~003 | Godot 4.6 兼容性处理——solid point 行为变更、性能验证 |

### Core Layer (对应系统实现前)
| # | ADR 标题 | 覆盖 TR | 说明 |
|---|---------|---------|------|
| 4 | **怪物对象池** | TR-monster-001 | 池大小、预分配策略、Node 复用 vs 新建 |
| 5 | **TileMapLayer 网格渲染** | TR-grid-002 | TileMapLayer vs _draw()——确定网格线绘制方案 |
| 6 | **阶段状态机** | TR-prep-001 | PREP/BATTLE/PAUSED 状态转换——在哪里管理状态、如何通知所有系统 |
| 7 | **拖拽合星输入** | TR-merge-001, TR-input-001 | 拖拽检测阈值、视觉反馈链、输入优先级 |

---

## Open Questions

| ID | Summary | Resolution |
|----|---------|------------|
| QQ-01 | SignalBus Autoload vs 直接信号连接？ | ADR-001 |
| QQ-02 | TileMapLayer 性能 vs _draw() 灵活性？ | ADR-005 |
| QQ-03 | 怪物对象池预分配多少？ | ADR-004 |
