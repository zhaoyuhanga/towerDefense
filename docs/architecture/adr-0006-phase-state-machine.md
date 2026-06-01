# ADR-0006: 阶段状态机 (Phase State Machine)

## Status
Accepted

## Date
2026-06-01

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — 纯 GDScript enum + 信号，无 post-cutoff API 变更 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | 状态转换测试：所有合法/非法转换路径覆盖；100 次 PREP↔BATTLE 循环无状态漂移 |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001（SignalBus — `phase_changed` 信号已定义） |
| **Enables** | 所有系统的阶段门控逻辑——InputHandler（输入过滤）、WaveSpawner（波次触发）、HUD/UI（界面切换）、MonsterSystem（怪物行为）、Tower（攻击许可） |
| **Blocks** | 准备阶段系统（prep-phase）、波次生成系统（wave-spawner）的实现 |
| **Ordering Note** | `phase_changed` 信号必须在 PhaseManager 实现之前已在 SignalBus 中声明 |

## Context

### Problem Statement

游戏在两个主要阶段之间交替——PREP（筑城时间）和 BATTLE（战斗观战）。每个系统都需要知道当前阶段来门控自己的操作：InputHandler 在 BATTLE 阶段屏蔽建造输入，Tower 只在 BATTLE 阶段攻击，Merge 只在 PREP 阶段允许拖拽合成。阶段状态是横切关注点——18 个系统中有 8+ 个需要感知它。

核心问题：**阶段状态由谁持有？系统如何获取当前阶段？** 这个选择直接影响 Foundation 层（InputHandler）能否在不依赖 Feature 层的前提下门控输入。

### Constraints
- Foundation 层系统（InputHandler）不能依赖 Feature 层模块——但需要知道当前阶段来过滤输入
- 阶段变更必须通知多个系统（HUD、输入、波次、塔、视觉）——一对多广播
- 转换必须是确定性的——非法转换（如 BATTLE→BATTLE）必须被拒绝
- MVP 阶段只需要 PREP 和 BATTLE——但状态机设计应为 PAUSED 预留位置

### Requirements
- 任何系统都可以获取当前阶段（查询），无需持有 PhaseManager 引用
- 阶段变更通过 SignalBus 自动广播给所有订阅系统
- 非法状态转换被拒绝并记录警告
- 状态转换本身 < 0.1ms（纯 enum 赋值 + 信号发射）

## Decision

采用 **场景节点 PhaseManager + SignalBus 广播** 方案。PhaseManager 是 LevelScene 下的一个节点，持有唯一的 `current_phase` 状态。状态变更通过 `SignalBus.phase_changed` 广播——所有系统订阅此信号来缓存本地阶段副本，无需持有 PhaseManager 引用。

不使用 Autoload（避免全局单例膨胀）也不使用纯去中心化（需要一个明确的真相来源来做转换验证）。

### 状态定义

```gdscript
enum Phase {
    PREP = 0,    # 筑城阶段——玩家放置方块、购买/合成塔
    BATTLE = 1,  # 战斗阶段——怪物行进、塔自动攻击
    PAUSED = 2,  # 暂停（V1.0）——ESC 触发，所有游戏逻辑冻结
}
```

### 状态转换图

```
        ┌──────────────────────────┐
        │                          │
        ▼                          │
     ┌──────┐   start_wave()   ┌────────┐
     │ PREP │ ────────────────▶ │ BATTLE │
     │      │ ◄──────────────── │        │
     └──────┘   wave_ended()    └────────┘
        │          (所有怪物死亡/越界)     │
        │                                │
        │  pause()    ┌─────────┐  pause()
        ├───────────▶ │ PAUSED  │ ◄────────┘
        │  resume()   │         │  resume()
        ▼              └─────────┘
      (V1.0 特性——MVP 中 pause() 为空操作)
```

| 转换 | 触发方 | 调用 | 条件 |
|------|--------|------|------|
| PREP → BATTLE | InputHandler | `PhaseManager.start_wave()` | 玩家点击"开始"按钮 |
| BATTLE → PREP | WaveSpawner | `PhaseManager.on_wave_ended()` | 所有怪物死亡或越界 |
| PREP → PAUSED | InputHandler | `PhaseManager.pause()` | ESC 键（V1.0） |
| BATTLE → PAUSED | InputHandler | `PhaseManager.pause()` | ESC 键（V1.0） |
| PAUSED → PREP | InputHandler | `PhaseManager.resume()` | ESC 键或继续按钮（V1.0） |
| PAUSED → BATTLE | InputHandler | `PhaseManager.resume()` | ESC 键或继续按钮（V1.0） |

### PAUSED 实现方式（V1.0）

PAUSED 阶段使用 Godot 引擎级暂停——**不是**纯逻辑标记：

```gdscript
func pause() -> void:
    if current_phase == Phase.PAUSED:
        return
    _previous_phase = current_phase
    get_tree().paused = true  # 冻结所有 _process/_physics_process/Timer/Tween
    _set_phase(Phase.PAUSED)

func resume() -> void:
    if current_phase != Phase.PAUSED:
        return
    get_tree().paused = false
    _set_phase(_previous_phase)
```

选择 `get_tree().paused` 的原因：
- 自动冻结所有 `_process()` 和 `_physics_process()`——无需每个系统手动检查
- SceneTreeTimer 和 Tween 同步暂停——动画不会"漂移"
- 输入事件默认在暂停时禁用——ESC 菜单外的点击不会穿透

**UI 要求**：暂停菜单的 UI 节点必须设置 `process_mode = PROCESS_MODE_ALWAYS`，以在 `get_tree().paused = true` 下继续接收输入（响应 ESC 恢复 / 继续按钮点击）。

### 信号参数：int vs enum 的取舍

SignalBus 的信号声明为：

```gdscript
signal phase_changed(old_phase: int, new_phase: int)
```

参数用 `int` 而非 `PhaseManager.Phase` 枚举类型。原因：SignalBus (Autoload) 不应依赖 PhaseManager（场景节点）——这会造成 Autoload→场景节点的反向耦合。代价是失去了编译期类型安全——`_set_phase()` 是唯一的 `emit` 点，在运行时保证参数始终是合法的 `Phase` 枚举值。订阅者通过 `new as Phase` 安全转换。

### 系统获取当前阶段的方式

**方式 1：SignalBus 订阅 + 本地缓存（推荐——无引用依赖）**

```gdscript
# 任何系统——包括 Foundation 层的 InputHandler
var _current_phase: Phase = Phase.PREP  # 初始默认值——与 PhaseManager 启动状态一致

func _ready() -> void:
    SignalBus.phase_changed.connect(_on_phase_changed)

func _on_phase_changed(_old: int, new: int) -> void:
    _current_phase = new as Phase

func _input(event: InputEvent) -> void:
    if _current_phase != Phase.PREP:
        return  # BATTLE/PAUSED 阶段门控建造输入
```

**初始阶段说明**：各系统的 `_current_phase` 本地缓存默认值为 `Phase.PREP`，与 PhaseManager 的启动状态一致。PhaseManager 在 `_ready()` 中**不**主动 emit 初始状态——因为其他系统的 `_ready()` 执行顺序不保证，emit 可能在订阅者连接之前。此隐式约定假设初始阶段始终是 `PREP`——若未来改为其他初始值，所有订阅者的默认值需同步更新（无编译期检查）。

**方式 2：直接引用查询（场景树查找——用于需要主动查询的系统）**

```gdscript
# 仅用于需要主动查询初始状态的系统（如 HUD 在 _ready 时确认初始 UI）
@onready var phase_manager: PhaseManager = %PhaseManager  # Unique Name — 比绝对路径更健壮

func _ready() -> void:
    # 已有 SignalBus 订阅来处理变更——这里是获取初始值
    update_ui(phase_manager.current_phase)
```

使用 `%PhaseManager`（场景 Unique Name）而非绝对路径 `"/root/LevelScene/PhaseManager"`——Godot 4.1+ 支持此语法，且不受场景结构重构影响。

**推荐约定**：所有系统优先使用方式 1（SignalBus + 本地缓存）。方式 2 仅用于需要主动查询初始状态的场景。这确保 Foundation 层永远不需要持有 Feature 层模块的引用。

### 架构

```
┌──────────────────────────────────────────────────┐
│                 LevelScene                         │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │  PhaseManager (Node)                        │   │
│  │  — current_phase: Phase (单一真相来源)       │   │
│  │  — _previous_phase: Phase (PAUSED 恢复用)   │   │
│  │  — start_wave() → _set_phase(BATTLE)        │   │
│  │  — on_wave_ended() → _set_phase(PREP)       │   │
│  │  — pause() / resume() (V1.0)                │   │
│  │  — _set_phase() 内部: 验证 → 赋值 → 广播     │   │
│  └──────────────────┬─────────────────────────┘   │
│                     │                              │
│                     │ SignalBus.phase_changed      │
│                     │ .emit(old, new)              │
│                     ▼                              │
│  ┌──────────────────────────────────────────┐     │
│  │  所有订阅系统（本地缓存 current_phase）    │     │
│  │  InputHandler │ Tower │ WaveSpawner       │     │
│  │  Merge │ HUD │ GridRenderer │ ...         │     │
│  └──────────────────────────────────────────┘     │
└──────────────────────────────────────────────────┘
```

### Key Interfaces

```gdscript
## PhaseManager — 阶段状态机，LevelScene 的子节点
## 持有游戏阶段的唯一真相来源。状态变更通过 SignalBus 广播。
class_name PhaseManager extends Node

## 当前游戏阶段。只读——外部通过 SignalBus.phase_changed 获取变更。
var current_phase: Phase = Phase.PREP

## PAUSED 前所处的阶段——用于 resume() 恢复（V1.0）
var _previous_phase: Phase = Phase.PREP

## 请求开始波次。PREP → BATTLE。
## 由 InputHandler 在玩家点击"开始"按钮时调用。
func start_wave() -> void:
    pass  # → _set_phase(Phase.BATTLE)

## 波次结束回调。BATTLE → PREP。
## 由 WaveSpawner 在所有怪物死亡或越界后调用。
func on_wave_ended() -> void:
    pass  # → _set_phase(Phase.PREP)

## 暂停游戏（V1.0）。PREP/BATTLE → PAUSED。
## 使用 get_tree().paused = true 冻结所有处理逻辑。
## 暂停菜单 UI 需 PROCESS_MODE_ALWAYS。
func pause() -> void:
    pass  # → _previous_phase = current_phase → get_tree().paused = true → _set_phase(Phase.PAUSED)

## 恢复游戏（V1.0）。PAUSED → 之前的阶段。
func resume() -> void:
    pass  # → get_tree().paused = false → _set_phase(_previous_phase)

## 内部方法——验证 + 执行状态转换。所有公开方法最终调用此方法。
## 非法转换（相同阶段重复设置）被拒绝并打印警告。
func _set_phase(new_phase: Phase) -> void:
    if new_phase == current_phase:
        push_warning("PhaseManager: 重复设置相同阶段 %s" % Phase.find_key(new_phase))
        return
    
    var old_phase := current_phase
    current_phase = new_phase
    SignalBus.phase_changed.emit(old_phase as int, new_phase as int)
```

## Alternatives Considered

### Alternative 1: Autoload PhaseManager

- **Description**: PhaseManager 注册为 Autoload 单例。任何系统通过 `PhaseManager.current_phase` 直接查询，通过 `PhaseManager.set_phase()` 直接切换。
- **Pros**: 全局可访问——零查找开销。不需要 SignalBus 订阅或本地缓存。API 最简单。
- **Cons**: 添加第三个 Autoload（SignalBus + MonsterPool + PhaseManager）。全局可变状态——任何系统都可以调用 `set_phase()`，增加了非法转换的风险。单元测试中 Autoload 的拆解更复杂。
- **Rejection Reason**: Autoload 的数量应保持最小——SignalBus（通信基础设施）和 MonsterPool（节点生命周期管理）有充分理由作为全局单例。PhaseManager 的状态变更已经通过 SignalBus 广播——额外给它 Autoload 地位是过度特权。此外，PhaseManager 的生命周期与 LevelScene 一致——场景结束 = 状态机销毁——作为场景节点是自然选择。

### Alternative 2: 纯 SignalBus 去中心化（无 PhaseManager）

- **Description**: 无中心化的阶段状态持有者。每个系统通过订阅 `SignalBus.phase_changed` 自行维护 `_current_phase` 本地缓存。阶段切换由约定协调——InputHandler 检测到"开始"按钮点击时，自己切换本地状态并发射 `phase_changed`。
- **Pros**: 零额外节点开销。无全局状态——每个系统自治。
- **Cons**: 无转换验证——没有 PhaseManager 来拒绝 `BATTLE → BATTLE` 或 `BATTLE → PREP` 的非法调用。谁有权发射 `phase_changed`？没有明确的"阶段所有者"。调试困难——如果两个系统对当前阶段有不一致的本地缓存，行为会出现"幽灵 bug"。
- **Rejection Reason**: 18 个系统各自维护阶段缓存——缺乏单一真相来源使得非法转换无法被集中拦截。一个系统缓存了 `PREP` 而另一个缓存了 `BATTLE` 的情况是灾难性的调试场景。

## Consequences

### Positive
- 单一真相来源——`PhaseManager.current_phase` 是所有人查询的权威值
- 转换验证集中——非法转换在 `_set_phase()` 中被拦截并记录警告（`Phase.find_key()` 输出可读的枚举名称）
- Foundation 层零依赖——InputHandler 通过 SignalBus 订阅获取阶段，不需要 Feature 层引用
- 场景生命周期绑定——PhaseManager 随 LevelScene 销毁，无全局状态泄漏
- 为 PAUSED 预留——状态枚举和 API 已就绪，V1.0 使用 `get_tree().paused` 实现引擎级暂停
- 信号参数用 `int` 而非强类型枚举——避免 SignalBus Autoload 反向依赖 PhaseManager 场景节点

### Negative
- 比 Autoload 方案多一步：Foundation 系统需要本地缓存 + SignalBus 订阅（~5 行代码）
- 需要访问 PhaseManager 主动查询的系统（如 HUD 初始化）需要通过场景 Unique Name（`%PhaseManager`）查找——若忘记在场景中设置唯一名称则会断裂
- 不是 Autoload——如果用 `change_scene_to_file()` 切换场景，PhaseManager 会和旧 LevelScene 一起销毁（但这正是期望行为——新游戏 = 新 PhaseManager）
- 信号的 `int` 参数失去了编译期类型安全——但 `_set_phase()` 是唯一 emit 点，运行时保证合法

### Risks
- **信号 vs 查询的同步竞争**: 系统 A 在 `_on_phase_changed()` 中执行操作时，系统 B 的 `_on_phase_changed()` 可能尚未执行——如果系统 A 依赖系统 B 的"阶段已切换"副作用，会出现顺序依赖。**缓解措施**: 文档规定——`phase_changed` 的订阅者不应依赖其他订阅者的执行顺序。需要"切换后初始化"的系统应在 `_on_phase_changed()` 中自理
- **场景 Unique Name 未设置**: `%PhaseManager` 依赖在场景编辑器中给 PhaseManager 节点设置 "Unique Name" 属性——忘记设置会导致运行时 `null` 引用。**缓解措施**: 在 BoardGrid / LevelScene 的预置场景中预设此属性；代码审查检查清单包含 "所有 % 引用节点确认 Unique Name"
- **PAUSED 恢复目标**: V1.0 实现 pause/resume 后，需要记住"PAUSED 之前是 PREP 还是 BATTLE"。**缓解措施**: `_previous_phase: Phase` 私有字段——在 `_set_phase()` 进入 PAUSED 前记录
- **初始阶段变更的隐性成本**: 若未来将初始阶段从 PREP 改为其他值（如 INTRO），所有系统的 `_current_phase` 默认值必须同步更新——无编译期检查。**缓解措施**: 在 PhaseManager 的类文档中注释 "初始阶段 = PREP——变更需 grep 所有 `Phase.PREP` 默认赋值"

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| prep-phase.md | PREP ↔ BATTLE 阶段切换——玩家点击"开始"和波次自动结束 | PhaseManager.start_wave() 和 on_wave_ended() 管理这两条转换路径 |
| prep-phase.md | 阶段变更通知所有系统——`phase_changed` 信号 | SignalBus.phase_changed.emit()——所有系统通过订阅获取 |
| prep-phase.md | 可用操作门控——PREP 可建造/BATTLE 只观战 | 各系统通过本地 phase 缓存门控操作——PhaseManager 不干预具体门控逻辑 |
| input-handling.md | BATTLE 阶段屏蔽建造输入 | InputHandler 订阅 SignalBus.phase_changed——本地缓存当前阶段 |
| wave-spawner.md | 波次结束 → PREP，点击开始 → BATTLE | WaveSpawner 调用 on_wave_ended()；InputHandler 调用 start_wave() |
| hud-ui.md | 阶段切换时 UI 状态变更 | HUD 订阅 SignalBus.phase_changed，切换准备/战斗界面 |

## Performance Implications
- **CPU**: `_set_phase()` < 0.1ms（enum 赋值 + 一个 SignalBus emit）。阶段切换频率很低（每 1-3 分钟一次）——性能完全不是问题
- **Memory**: PhaseManager 节点 ~500 bytes。每个系统的本地 `_current_phase` 缓存 ~1 byte——可忽略
- **Load Time**: 零影响——PhaseManager 是 LevelScene 的一个普通子节点
- **Network**: 不适用

## Migration Plan
不适用——新项目。

## Validation Criteria
1. **合法转换**: PREP→BATTLE→PREP 完整循环——`phase_changed` 信号各触发一次，参数正确
2. **非法转换拒绝**: BATTLE→BATTLE、PREP→PREP——控制台警告输出（含枚举名称），状态不变
3. **系统同步**: 5 个订阅系统（InputHandler, Tower, HUD, WaveSpawner, GridRenderer）在 `phase_changed` 发射后本地缓存全部更新——无漏网系统
4. **初始状态**: PhaseManager 初始化为 PREP——所有系统在 `_ready()` 中订阅前默认也是 PREP
5. **循环稳定性**: 100 次 PREP↔BATTLE 循环——`current_phase` 值与循环次数一致，无状态漂移
6. **V1.0 PAUSED**: `get_tree().paused = true` 冻结所有 _process；UI（PROCESS_MODE_ALWAYS）仍可响应输入

## Related Decisions
- ADR-0001: SignalBus — `phase_changed` 信号定义和使用
- ADR-0005: TileMapLayer — GridRenderer 订阅 `phase_changed` 切换网格透明度
- `design/gdd/prep-phase.md` — 准备阶段系统设计
- `design/gdd/input-handling.md` — 输入门控需求
- `design/gdd/wave-spawner.md` — 波次结束 → PREP 转换
- `docs/architecture/architecture.md` — 准备阶段模块定义在 Feature 层
