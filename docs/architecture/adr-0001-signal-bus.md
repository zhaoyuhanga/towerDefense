# ADR-0001: 事件/信号架构 — SignalBus Autoload

## Status
Accepted

## Date
2026-06-01

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — Godot signal system stable, within LLM training data |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | ADR-0002 (数据配置), ADR-0003 (AStarGrid2D), ADR-0004 (对象池), ADR-0005 (TileMapLayer), ADR-0006 (阶段状态机), ADR-0007 (拖拽合星) |
| **Blocks** | 所有 Core 和 Feature 层的实现——通信基础设施必须先就位 |
| **Ordering Note** | 必须在任何 Core 层代码编写前 Accepted |

## Context

### Problem Statement

18 个系统分布在 5 个架构层中，需要一个统一的跨系统通信机制。直接让每个系统持有其他系统的引用会导致网状依赖——18 个系统中任何两个都可能需要通信，如果采用直接连接，修改一个系统会影响多个系统。

架构文档规定了两类通信：
- **同步查询**（Foundation → 上层）：`get_cell_state()`, `can_afford()`, `get_active_monsters()` 等——这些是数据查询，需要即时返回值，保持直接方法调用
- **事件通知**（一对多广播）：`cell_state_changed`, `monster_died`, `wave_started`, `gold_changed` 等——这些是状态变更通知，可能有多个消费者

本 ADR 解决事件通知层的架构。

### Constraints
- MVP 18 个系统，不允许网状依赖
- 事件消费者可能是多个系统（如 `monster_died` 被经济、视觉反馈、HUD 同时订阅）
- Godot 原生信号系统满足需求——不需要第三方消息队列
- 性能：信号发射/接收 < 0.1ms

### Requirements
- 系统 A 发射事件时不需要知道系统 B、C、D 是否在监听
- 新系统可以订阅已有事件而不修改事件发射方
- 信号的签名在项目初期定义好——运行时不变

## Decision

使用 **SignalBus Autoload 单例** 管理所有跨系统事件通信。

### 架构

```
┌─────────────────────────────────────────────┐
│              SignalBus (Autoload)            │
│                                              │
│  signal cell_state_changed(col, row, old, new)│
│  signal monster_died(id, pos, reward)        │
│  signal monster_breached(pos, path)          │
│  signal damage_dealt(target, amount, type)   │
│  signal wave_started(wave_number)            │
│  signal wave_ended(wave, killed, breached)   │
│  signal merge_completed(from_star, to_star, pos)│
│  signal merge_failed(reason)                 │
│  signal gold_changed(current)                │
│  signal phase_changed(old_phase, new_phase)  │
│  signal path_updated(new_path)               │
│  signal path_blocked()                       │
│  signal skill_activated(skill_id)            │
│  signal block_count_changed(remaining)       │
└──────────────┬──────────────────────────────┘
               │  emit / connect
     ┌─────────┴──────────┐
     │   All Systems       │
     │   (emit & subscribe)│
     └────────────────────┘
```

### 通信分流规则

| 通信类型 | 机制 | 示例 |
|---------|------|------|
| **同步数据查询** | 直接方法调用 | `board.get_cell_state()`, `economy.can_afford()` |
| **事件广播（一对多）** | SignalBus 信号 | `monster_died`, `wave_started` |
| **命令（一对一）** | 直接方法调用 | `monster.take_damage()`, `economy.spend_gold()` |

**简单规则**：需要返回值 → 直接调。不需要返回值 + 可能有多个监听者 → SignalBus。

### SignalBus 实现

```gdscript
# autoload/signal_bus.gd
extends Node

## 棋盘状态变更
signal cell_state_changed(col: int, row: int, old_state: int, new_state: int)

## 怪物生命周期
signal monster_died(monster_id: String, position: Vector2, reward_gold: int)
signal monster_breached(position: Vector2, path: Array)

## 战斗
signal damage_dealt(target_id: String, amount: float, damage_type: String)

## 波次
signal wave_started(wave_number: int)
signal wave_ended(wave_number: int, enemies_killed: int, enemies_breached: int)

## 合星
signal merge_completed(from_star: int, to_star: int, position: Vector2i)
signal merge_failed(reason: String)

## 经济
signal gold_changed(current_gold: int)

## 阶段
signal phase_changed(old_phase: int, new_phase: int)

## 寻路
signal path_updated(new_path: Array)
signal path_blocked()

## 技能
signal skill_activated(skill_id: String)

## 方块
signal block_count_changed(remaining: int)
```

### 使用模式

```gdscript
# 发射事件（任何系统）
SignalBus.cell_state_changed.emit(col, row, old, new)

# 订阅事件（任何系统）
func _ready():
    SignalBus.monster_died.connect(_on_monster_died)

func _on_monster_died(id: String, pos: Vector2, reward: int):
    # 处理金币奖励、播放动画等
```

### 命名约定
- 信号名：`snake_case` 过去式（`monster_died`, `wave_started`）
- 参数：有类型的显式参数——不用 Dictionary 传参
- 每个信号在 SignalBus 中只定义一次——语义全局唯一

## Alternatives Considered

### Alternative 1: 直接信号连接
- **Description**: 每个系统持有需要通信的系统的引用，直接 `node.signal.connect()`
- **Pros**: 简单直接，无需额外 autoload；Godot 编辑器可视化连接
- **Cons**: 18 个系统形成网状依赖；修改系统 A 需要知道谁连了它的信号；新系统加入需要修改发射方
- **Rejection Reason**: 网状依赖与架构原则 #2（信号解耦）冲突。18 系统的规模下维护成本不可接受

### Alternative 2: 纯查询模式（无事件）
- **Description**: 所有通信通过 Foundation 接口轮询——每帧检查状态变化
- **Pros**: 零事件复杂度；所有交互路径显式可见
- **Cons**: 每帧轮询 300 格的棋盘状态、所有怪物血量、所有金币变化——性能灾难；违反"事件驱动"的架构原则
- **Rejection Reason**: 性能不可接受。18 个系统轮询 → 16.6ms 预算消耗殆尽

## Consequences

### Positive
- 系统 A 发射事件时零耦合——不知道谁在监听
- 新消费者可以随时 `connect()` 而不修改任何现有代码
- 所有事件签名集中在一个文件中——容易审计和发现"谁发射了什么"
- Godot 原生信号——零额外依赖，性能 < 0.1ms/emit

### Negative
- SignalBus 会随着系统增加而膨胀——需要纪律约束：只放跨系统事件，系统内部信号不放进来
- 信号签名变更会影响所有订阅者——GDScript 静态类型检查可以发现不匹配
- 调试时信号链路不如直接调用直观——需要用 Godot 编辑器的 Signal 面板追踪

### Risks
- **SignalBus 膨胀成"万能总线"**：开发者把所有信号都往里扔。缓解：代码审查规则——SignalBus 只接受被 ≥2 个系统订阅的信号。系统内部信号用 `signal` 关键字在各自类中定义
- **信号级联**：A 发射 → B 响应 → B 又发射 → C 响应 → 无限循环。缓解：禁止在处理信号时同步发射同名信号（加 guard `_processing_event = true`）

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| board-grid.md | `cell_state_changed` 信号——任何格子变更需通知寻路和视觉 | SignalBus 统一管理——寻路和视觉各自订阅 |
| monster-system.md | `monster_died`, `monster_breached` 信号——通知经济和视觉 | SignalBus 统一管理——经济、视觉、HUD 订阅 |
| combat-damage.md | `damage_dealt` 信号——通知视觉反馈 | SignalBus 统一管理 |
| wave-spawner.md | `wave_started`, `wave_ended` 信号——通知 HUD 和阶段切换 | SignalBus 统一管理 |
| merge-upgrade.md | `merge_completed`, `merge_failed` 信号——通知视觉 | SignalBus 统一管理 |
| economy.md | `gold_changed` 信号——通知 HUD 更新 | SignalBus 统一管理 |
| prep-phase.md | `phase_changed` 信号——通知所有系统门控操作 | SignalBus 统一管理 |
| pathfinding.md | `path_updated`, `path_blocked` 信号——通知怪物和视觉 | SignalBus 统一管理 |
| emergency-skills.md | `skill_activated` 信号——通知视觉 | SignalBus 统一管理 |
| obstacle-block.md | `block_count_changed` 信号——通知 HUD 更新 | SignalBus 统一管理 |

## Performance Implications
- **CPU**: 每个信号发射 < 0.1ms。最坏情况（一帧内所有 14 个信号各发射一次）< 1.4ms——在 16.6ms 预算中占比 < 9%
- **Memory**: SignalBus 单例 ~1KB。每个 connect 增加 ~100 bytes——18 系统 × 平均 3 订阅 ≈ 5.4KB
- **Load Time**: 零额外开销——SignalBus 是 autoload，随场景加载

## Migration Plan
N/A — 新项目，无现有代码需要迁移。

## Validation Criteria
- 所有 GDD 定义的信号在 SignalBus 中有对应声明
- 所有跨系统事件通过 SignalBus 发射——代码审查验证无直接 node.signal.connect() 跨模块
- 信号级联保护测试：发射 `cell_state_changed` → 寻路响应 → `path_updated` → 这不算级联（合法因果链）。需要的是防止循环

## Related Decisions
- ADR-0002: 数据配置 Resource 系统
- ADR-0003: AStarGrid2D 集成与 Godot 4.6 兼容
- `docs/architecture/architecture.md` — Master Architecture (v1.0)
