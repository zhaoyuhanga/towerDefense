# ADR-0004: 怪物对象池 (Monster Object Pool)

## Status
Accepted

## Date
2026-06-01

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | HIGH — post-LLM-cutoff |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md`, `docs/engine-reference/godot/current-best-practices.md` |
| **Post-Cutoff APIs Used** | `@abstract` (4.5+), typed `Array[Monster]`, `PackedScene.instantiate()` (replaces deprecated `instance()`), `call_deferred()` |
| **Verification Required** | 压力测试：200+ 怪物同时激活时帧率保持 60 FPS；spawn/despawn 循环 10,000 次无内存泄漏 |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (SignalBus — monster_died 信号通过 SignalBus 发射)；ADR-0002 (数据配置 — MonsterData Resource 类) |
| **Enables** | 怪物系统 (Monster System)、战斗/伤害系统 (Combat)、波次生成系统 (Wave Spawner) |
| **Blocks** | None |
| **Ordering Note** | 必须在任何创建/销毁怪物节点的系统之前实施。ADR-0001 (SignalBus) 必须先 Accepted——MonsterPool 依赖 SignalBus 发射 `monster_died`。 |

## Context

### Problem Statement
怪物是游戏中数量最多的实体类型。在无限波次模式下，同时存在的怪物可达 100-300+ 只。Godot 的 `PackedScene.instantiate()` 会在堆上分配新节点，`queue_free()` 触发引用计数检查和终结器。每秒数十次这样的调用会造成可测量的帧时间尖峰和 GC 压力。对象池通过在怪物死亡时不销毁、而是在生成新怪物时重置并复用节点来解决此问题。

### Constraints
- 必须与 Godot 4.6 的场景树和节点生命周期模型兼容
- 2D 项目——所有怪物均为 `Node2D` 子类（若后续玩法需要物理碰撞，可改为 `CharacterBody2D` 或 `Area2D`——MonsterPool 的接口不受影响）
- 离线桌面游戏——无需网络复制
- 怪物类型可能有不同的场景/资源（如 "goblin"、"orc"），但共享相同的 `Monster` 基类
- 池必须支持未来扩展（新怪物类型无需重写池逻辑）
- **通信约束**：跨系统事件必须通过 SignalBus (ADR-0001) 发射，不得直接连接其他系统的信号

### Requirements
- 支持同一怪物类型的预分配（warm-up）和按需懒加载
- spawn 延迟 < 0.5ms（不含 `call_deferred` 的实际 `add_child` 时间）
- despawn（回池）延迟 < 0.1ms
- 内存上限可配置——超出上限时销毁而非回池
- 提供池状态查询（活跃数、池化数）用于调试和 HUD
- despawn 时通过 `SignalBus.monster_died` 发射事件，通知经济、视觉反馈、HUD 等系统

## Decision

采用 **类型化 Array[Monster] 对象池**，通过 `MonsterPool` Autoload 类封装。每种怪物类型按需懒加载实例并回池复用。跨系统通信通过 SignalBus (ADR-0001) 完成。

核心机制：
- **按类型分池**：每个 `MonsterType` 枚举值对应一个独立的池（`Dictionary[MonsterType, Array[Monster]]`），避免不同场景的怪物混用
- **懒加载**：首次请求某类型时 `instantiate()` 第一个实例；后续请求优先从池中取出
- **回池复用**：怪物死亡/离开时，Combat 系统调用 `despawn(monster)`→`monster.reset()`→从父节点 `remove_child()`→回收到池数组→通过 `SignalBus.monster_died.emit()` 广播
- **上限保护**：池大小超过 `max_pooled_per_type` 时，先从 `_active` 数组移除引用，再调用 `monster.queue_free()` 销毁（而非回收），防止延迟销毁期间外部访问僵尸节点

### Scene Tree Integration

怪物不直接挂载到 MonsterPool Autoload 节点下——这会导致 `global_position` 坐标系混乱。改为由调用方指定父节点：

- `spawn()` 接受 `parent: Node` 参数，由调用方（如 WaveSpawner）将怪物添加到正确的场景子树中（如 `LevelScene/Monsters` 容器节点）
- 回收时调用 `monster.get_parent().remove_child(monster)`，将怪物移出场景树
- 池化节点在**离树状态**下不执行 `_process()` / `_physics_process()`，无需手动禁用
- **不使用** `visible = false` 隐藏方案——离树更干净，且自动暂停处理回调

### _ready() 生命周期约束

Godot 在节点重新 `add_child()` 到场景树时触发 `_enter_tree()`，但**不会**再次触发 `_ready()`（除非显式调用 `request_ready()`）。因此：

> **强制规则**：Monster 子类的所有初始化逻辑（包括首次创建和后续复用）必须放在 `setup()` 中。`_ready()` 只能用于与场景树结构相关的初始化（如获取同级节点引用），且这些操作必须在 `setup()` 中通过 `is_inside_tree()` 检查后也能执行。禁止在 `_ready()` 中设置任何依赖复用前清理的状态。

### call_deferred() 安全策略

若 `spawn()` 或 `despawn()` 在物理处理、信号发射、或其他节点的 `_ready()`/`_enter_tree()` 回调期间被调用，直接操作 `add_child()` / `remove_child()` 可能触发 "Parent node is busy setting up children" 错误。因此：

- `spawn()` 内部通过 `parent.call_deferred("add_child", monster)` 添加到场景树
- `despawn()` 的 `remove_child()` 同样建议在安全上下文中调用，或由调用方通过 `call_deferred()` 包装
- 在 `spawn()` 和 `despawn()` 的文档注释中注明调用安全约束

### 信号通信（与 ADR-0001 对齐）

MonsterPool 本身**不定义自定义信号**——所有跨系统通知通过 SignalBus (ADR-0001)：

```gdscript
# despawn 内部——通过 SignalBus 广播
SignalBus.monster_died.emit(monster_id, position, reward_gold)
```

| 场景 | 信号（SignalBus） | 发射方 | 订阅方 |
|------|-------------------|--------|--------|
| 怪物死亡回池 | `monster_died(id, pos, reward)` | MonsterPool.despawn() | Economy (加金币), VisualFeedback (死亡动画), HUD (击杀计数) |
| 怪物突破防线 | `monster_breached(pos, path)` | Monster 或 WaveSpawner | HUD (显示漏怪), VisualFeedback |

注意：`monster_died` 信号的 `reward_gold` 由 Monster 的 `MonsterData.reward` 提供——MonsterPool 不计算奖励，只读取配置值并传入信号。

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    SignalBus (ADR-0001)                   │
│  monster_died(id, pos, reward)  ← MonsterPool 发射        │
│  monster_breached(pos, path)                              │
└──────┬──────────────┬──────────────┬─────────────────────┘
       │ subscribe    │ subscribe    │ subscribe
       ▼              ▼              ▼
┌──────────┐  ┌──────────┐  ┌──────────────┐
│ Economy  │  │  Visual  │  │     HUD      │
└──────────┘  └──────────┘  └──────────────┘
       ▲
       │ emit monster_died
       │
┌─────────────────────────────────────────────────┐
│                  MonsterPool                      │
│  (Autoload — 全局单例，不持有怪物子节点)              │
│                                                   │
│  _pools: Dictionary[MonsterType, Array[Monster]]  │
│  _scenes: Dictionary[MonsterType, PackedScene]    │
│  _active: Array[Monster]                          │
│  max_pooled_per_type: int = 50                    │
│                                                   │
│  spawn(type, parent, position, data) → Monster    │
│  despawn(monster) → void                          │
│  warmup(type, count) → void                       │
│  get_active_count() → int                         │
│  get_pooled_count(type) → int                     │
└────────────────────┬──────────────────────────────┘
                     │ spawn 返回 monster 节点
                     │ 由调用方 call_deferred("add_child", parent)
                     ▼
┌─────────────────────────────────────────────────┐
│              游戏场景 (LevelScene)                  │
│  ┌──────────────────────────────────────────┐   │
│  │  Monsters (Node2D — 怪物容器节点)          │   │
│  │  ├─ Goblin (active)                       │   │
│  │  ├─ Goblin (active)                       │   │
│  │  ├─ Orc (active)                          │   │
│  │  └─ ...                                   │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
                     ▲
                     │ Monster 实例
                     ▼
┌─────────────────────────────────────────────────┐
│              Monster (基类, @abstract)             │
│                                                   │
│  setup(data: MonsterData) → void   (初始化状态)    │
│  reset() → void                    (回池前清理)    │
│  is_active: bool                                   │
│  data: MonsterData   (怪物属性——含 reward)          │
└─────────────────────────────────────────────────┘
```

### Key Interfaces

```gdscript
## MonsterPool — Autoload 单例，管理所有怪物节点的生命周期。
## 注意：MonsterPool 不直接持有怪物作为场景树子节点。
## 怪物由调用方（WaveSpawner）挂载到正确的场景子树下。
## 跨系统通信通过 SignalBus (ADR-0001) —— MonsterPool 不定义自己的跨系统信号。
class_name MonsterPool extends Node

## 从池中获取或创建一只怪物。优先返回已池化的实例。
## type: 怪物类型枚举，决定使用哪个 PackedScene
## parent: 怪物在场景树中的父节点（如 LevelScene/Monsters 容器）
## position: 怪物在世界中的生成位置
## data: 该实例的怪物属性配置（源自 ADR-0002 MonsterData Resource）
## 返回：一个已就绪的 Monster 节点（调用方通过 call_deferred("add_child", parent) 挂载）
func spawn(type: MonsterType, parent: Node, position: Vector2, data: MonsterData) -> Monster:
    pass

## 将怪物归还到池中。由 Combat 系统在判定 health ≤ 0 后调用。
## 1. 若 is_active 已为 false（重复 despawn）→ no-op，直接返回
## 2. 若 monster 在场景树中 → remove_child
## 3. 调用 monster.reset() 清理所有状态
## 4. 若池未满 → 加入池数组；若池已满 → 从 _active 移除引用 → queue_free
## 5. 通过 SignalBus.monster_died.emit(id, position, monster.data.reward) 广播
func despawn(monster: Monster) -> void:
    pass

## 预分配指定数量的某类型怪物到池中（用于吸收首次实例化开销）。
## 预分配节点处于离树状态，不挂载到任何父节点下。
func warmup(type: MonsterType, count: int) -> void:
    pass

## 返回当前活跃（已 spawn 但未 despawn）的怪物总数
func get_active_count() -> int:
    pass

## 返回指定类型在当前池中的待用怪物数
func get_pooled_count(type: MonsterType) -> int:
    pass
```

```gdscript
## Monster — 所有怪物实体的抽象基类。
## 重要：子类禁止在 _ready() 中设置任何依赖 reset() 清理的状态。
## 所有初始化逻辑必须走 setup()，以确保首次创建和池化复用行为一致。
@abstract
class_name Monster extends Node2D

## 该怪物的类型枚举（在 setup() 中设置）
var type: MonsterType

## 是否已被 spawn 且尚未 despawn
var is_active: bool = false

## 怪物属性数据引用（源自 ADR-0002 MonsterData Resource）
## 包含 health, speed, reward_gold 等——setup() 中赋值
var data: MonsterData

## 使用数据初始化怪物。由 MonsterPool.spawn() 调用。
## 子类应通过 super.setup(data) 调用链处理共享状态。
## 此方法在首次创建和每次池化复用时均会被调用——必须幂等。
@abstract
func setup(data: MonsterData) -> void:
    pass

## 将怪物重置为干净的池化状态。由 MonsterPool.despawn() 调用。
## 必须将 is_active 设为 false，并完整清理：
##   - 所有活跃的 Tween（tween.kill()）
##   - 所有 Timer（timer.stop()）——loop timer 离树后仍会继续运行
##   - 在 setup() 中连接到 SignalBus 的信号（断开以避免重复订阅）
##   - 动态添加的子节点（血条、状态特效等——queue_free 清理）
##   - set_process(false) / set_physics_process(false)（双保险，与 remove_child 互补）
@abstract
func reset() -> void:
    pass
```

### 典型调用流

```
[WaveSpawner]                                   [Combat]
     │                                              │
     │ spawn(type, parent, pos, data)               │
     ▼                                              │
[MonsterPool] ──→ Monster.setup(data)               │
     │                                              │
     │ 返回 monster 节点                             │
     ▼                                              │
[WaveSpawner] call_deferred("add_child", parent)    │
     │                                              │
     │ ... 战斗进行 ...                              │
     │                                              │
     │                              take_damage() → health ≤ 0
     │                                              │
     │                              despawn(monster) │
     │                                    │         │
     ▼                                    ▼         │
[MonsterPool.despawn()]                           │
     │                                              │
     ├─ monster.get_parent().remove_child(monster)
     ├─ monster.reset()
     ├─ _active.erase(monster)
     ├─ _pools[type].append(monster)   (or queue_free if full)
     └─ SignalBus.monster_died.emit(id, pos, reward)
          │
          ├─→ Economy.add_gold(reward)
          ├─→ VisualFeedback.play_death(pos)
          └─→ HUD.update_kill_count()
```

## Alternatives Considered

### Alternative 1: 不池化——直接 Instantiate / queue_free
- **Description**: 怪物在需要时直接 `instantiate()`，死亡时直接 `queue_free()`。完全无池化开销。
- **Pros**: 代码最简单，心智负担最低，无需管理节点生命周期。适合怪物数量 < 20 的项目。
- **Cons**: 在 100+ 怪物场景下每波次都会造成 GC 尖峰和帧时间波动。`instantiate()` 涉及场景资源加载/复制，开销很大。
- **Rejection Reason**: Godot 官方最佳实践和社区测试均表明，在实体 > 50 时，直接分配会造成可见的性能下降。本项目预计单波次 100-300 只怪物，此方案不适用。

### Alternative 2: 基于 Resource 的预配置池
- **Description**: 每种怪物类型对应一个 `MonsterPoolConfig` Resource（.tres 文件），在其中配置 PackedScene、初始容量、最大容量。`MonsterPool` 在 `_ready()` 中加载所有配置并依此初始化池。
- **Pros**: 配置高度数据驱动，设计师可在编辑器中直接调整池参数。类型与容量一目了然。
- **Cons**: 在仅有少量怪物类型的项目中，每个类型单独建 .tres 引入了不必要的文件和间接层。Resource 加载本身也会在启动时产生开销。对于 MVP 阶段来说过度设计。
- **Rejection Reason**: 当前项目 MVP 阶段怪物类型有限，池参数通过代码常量即可管理。后续若怪物类型 > 20 且参数频繁调整，可迁移到 Resource 方案（届时创建新 ADR 取代本决策）。

## Consequences

### Positive
- 消除了 `instantiate()`/`queue_free()` 造成的帧时间波动——首次 warmup 后，spawn 仅涉及字段赋值和 `add_child`
- 懒加载意味着未使用的怪物类型不会预先分配内存
- `MonsterPool` Autoload 提供自然的全局接入点，调试和性能监控方便
- `@abstract` 基类确保所有怪物子类遵循相同的 `setup()`/`reset()` 契约
- `remove_child()` 离树方案确保池化节点不消耗 `_process()` 帧预算
- 通过 SignalBus 发射事件——与其他 ADR-0001 订阅方（Economy, VisualFeedback, HUD）完全解耦

### Negative
- Autoload 单例给 `MonsterPool` 引入了全局可变状态——单元测试需要额外拆解
- 每种怪物类型需要仔细实现 `reset()` 以避免状态泄漏（上一个生命的状态残留到下一个生命）
- `max_pooled_per_type` 上限意味着在极端波次中，超过此限的怪物仍会走 `queue_free`/`instantiate` 路径
- 调试时需区分"池化的僵尸怪物"与"活跃怪物"——`is_active` 标志是强制约束
- `call_deferred()` 延迟添加意味着 spawn 后不能立即访问 `monster.global_position`——调用方需注意此异步性

### Risks
- **状态泄漏**: `reset()` 未正确清理以下子系统，导致怪物行为异常：
  1. **Tween** — 必须 `tween.kill()`；否则动画在离树状态下继续修改属性
  2. **Timer** — 必须 `timer.stop()`；loop timer 离树后仍会继续触发 timeout 回调
  3. **SignalBus 连接** — 在 `setup()` 中 `SignalBus.xxx.connect()` 的连接必须在 `reset()` 中断开，防止重复订阅导致一个事件触发多次回调
  4. **动态子节点** — `setup()` 中添加的血条、状态特效等必须 `queue_free()` 清理
  5. **process 回调** — `set_process(false)` / `set_physics_process(false)` 作为 `remove_child()` 的双保险
  - **缓解措施**: 编写 `reset()` 五步检查清单作为编码规范；为每种怪物类型编写 spawn→despawn→spawn 循环单元测试；在 CI pipeline 中加入循环测试。
- **池内存膨胀**: `warmup()` 预分配过多，或 `max_pooled_per_type` 设置过高，造成内存浪费。**缓解措施**: 默认 `max_pooled_per_type = 50`，通过玩法测试调优。后续可增加 `trim(type, count)` 方法手动缩减。
- **Autoload 初始化顺序**: `MonsterPool` 依赖场景加载后才能 `warmup()`。**缓解措施**: `warmup()` 不是自动在 `_ready()` 中执行的，而是由场景显式调用。场景加载完毕→注册 PackedScene→调用 warmup。
- **queue_free 延迟销毁**: 超出上限被 `queue_free()` 的怪物在当前帧结束前仍然存活。**缓解措施**: 先 `_active.erase(monster)` 移除引用，再 `queue_free()`，确保外部迭代 `_active` 时不会访问到将被销毁的节点。

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| monster-system.md | 怪物实例的创建和销毁管理——spawn/despawn 生命周期 | MonsterPool 统一管理全部怪物节点的 spawn/despawn |
| monster-system.md | `monster_died` 信号——怪物死亡时通知经济、视觉、HUD | despawn() 通过 SignalBus.monster_died.emit() 广播 |
| combat-damage.md | 怪物 health ≤ 0 后的处理流程——despawn + 发放奖励 | Combat 调用 despawn()→SignalBus→Economy.add_gold() |
| wave-spawner.md | 波次开始时批量生成怪物——spawn 接口 | WaveSpawner 调用 MonsterPool.spawn() 批量创建 |
| economy.md | 击杀怪物获得金币——金额来自 MonsterData.reward | despawn 时从 monster.data.reward 读取并传入 monster_died 信号 |

## Performance Implications
- **CPU**: 每次 spawn < 0.5ms（从池中取出 + `setup()` 赋值，不含 `call_deferred` 的实际 `add_child` 时间）；每次 despawn < 0.1ms（`reset()` + `remove_child()` + 数组操作 + SignalBus emit）。首次实例化约 2-5ms（取决于场景复杂度），通过 `warmup()` 在加载画面中吸收。
- **Memory**: 每种怪物类型，`max_pooled_per_type × sizeof(Monster)`。默认上限 50 × 类型数。按 5 种类型、每节点 ~2KB 计算，峰值 ~500KB——可忽略。
- **Load Time**: 如果使用 `warmup()` 预分配，加载画面时间会增加。建议在过渡画面中异步执行 warmup，或限制每帧预分配数量。
- **Network**: 不适用（离线游戏）。

## Migration Plan
不适用——这是首个实现，无现有代码需要迁移。

## Validation Criteria
1. **压力测试**: 200 只怪物同时激活，维持 60 FPS，spawn 帧时间 < 16.6ms
2. **循环测试**: 10,000 次 spawn→despawn→spawn 循环无内存泄漏、无累积状态错误；重复 despawn 为 no-op
3. **信号验证**: 每次 despawn 触发一次且仅一次 `SignalBus.monster_died` 发射；Economy 收到正确的 reward 值
4. **单元测试**: 每种怪物类型的 `reset()` 完整清理状态（`is_active == false`，tween/timer/SignalBus 连接/动态子节点全部清理），`setup()` 幂等
5. **池上限**: 池大小 ≤ `max_pooled_per_type`，超出时先清除 `_active` 引用再 `queue_free`
6. **离树验证**: despawn 后的怪物节点不在场景树中（`is_inside_tree() == false`）

## Related Decisions
- ADR-0001: 事件/信号架构 — SignalBus Autoload（MonsterPool 通过 SignalBus 发射 monster_died）
- ADR-0002: 数据配置 Resource 系统（MonsterData Resource 定义怪物属性——含 reward_gold）
- ADR-0003: AStarGrid2D 集成（怪物寻路依赖 AStarGrid2D——路径跟随在 Monster 子类中实现）
- `docs/architecture/architecture.md` — Master Architecture (v1.0)
