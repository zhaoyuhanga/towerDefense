# ADR-0002: 数据配置 Resource 系统

## Status
Accepted

## Date
2026-06-01

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — Resource 系统稳定，`.tres` 格式无 post-cutoff 变化 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | 所有需要加载数值的系统（怪物、塔、战斗、经济、波次、技能） |
| **Blocks** | None directly — 但数据结构的定义是所有 Core 实现的先决条件 |
| **Ordering Note** | Resource 类必须在任何加载它们的系统之前定义 |

## Context

### Problem Statement

18 个系统中有 7 个需要从外部数据加载数值：塔属性（9 变体）、怪物属性（N 种）、波次规则、经济数值、技能参数、棋盘常量。如果数值硬编码在 GDScript 中，每次平衡调整需要改代码、重编译、重新测试——阻碍快速迭代。需要一个外部化、编辑器可编辑、类型安全的数据存储方案。

### Constraints
- Godot 4.6 引擎
- 单人开发，需要快速调整数值
- MVP 规模：~15-20 个数据文件
- 必须类型安全——字段名错误应在编辑器中捕获，而非运行时崩溃

### Requirements
- 数值在 Godot 编辑器中可直接查看和编辑
- 支持多种数据类型（int, float, String, Array, Resource 嵌套）
- 加载失败时不崩溃（fallback 默认值）
- 每个实体独立文件——改炮塔不影响冰塔

## Decision

使用 **Godot Custom Resource（`.tres` 文件）** 作为唯一数据配置方案。

### 架构

```
assets/resources/data/
├── grid_config.tres          ← GridConfig
├── towers/                   ← TowerData × 9
├── monsters/                 ← MonsterData × N  
├── waves/wave_rules.tres     ← WaveRules
├── economy.tres              ← EconomyConfig
└── skills/                   ← SkillConfig × 2
```

### Resource 类层次

```gdscript
# 每个数据类别一个 class_name Resource 脚本
class_name TowerData extends Resource
@export var tower_id: String
@export var star_level: int
@export var attack: float
# ... (完整字段见 data-config GDD)

class_name MonsterData extends Resource
@export var monster_id: String
@export var health: float
# ...
```

### 加载模式

每个系统在 `_ready()` 中通过 `DirAccess` 遍历自己的数据目录，`load()` 每个 `.tres` 到 Dictionary：

```gdscript
var tower_data: Dictionary = {}
func _ready():
    for file in DirAccess.get_files_at("res://assets/resources/data/towers/"):
        if file.ends_with(".tres"):
            var data := load(path + file) as TowerData
            tower_data[data.tower_id + "_" + str(data.star_level)] = data
```

### Fallback 策略

`load()` 返回 null 或 `as` 转换失败 → 打印错误 → 使用代码中定义的 fallback 默认值。游戏不崩溃。

## Alternatives Considered

### Alternative 1: JSON 文件
- **Pros**: 纯文本,git diff 友好,任何编辑器都能编辑
- **Cons**: 无类型检查——字段名拼错在运行时才暴露。Godot 编辑器内不可直接编辑。需要手写 JSON 解析器。嵌套结构不如 Resource 自然
- **Rejection Reason**: 失去类型安全——对单人项目来说，Godot 编辑器的 Inspector 编辑 + @export 类型检查是生产力优势

### Alternative 2: CSV 表格
- **Pros**: 一个文件看所有数据,Excel 编辑,批量修改方便
- **Cons**: Godot 导入为 Translation 资源（非通用数据）。CSV 无嵌套结构——Array[SpawnRule] 等复杂类型无法表达。字段顺序是隐式的
- **Rejection Reason**: 数据结构太复杂——WaveRules 含嵌套 SpawnRule 数组，CSV 无法自然表达

## Consequences

### Positive
- Godot 编辑器 Inspector 中可直接编辑所有数值——所见即所得
- `@export` 提供编译期类型检查——字段拼错在保存时捕获
- `.tres` 是 Godot 原生格式——零额外解析代码，`load()` 一行搞定
- 每实体一文件——改炮塔不影响冰塔，git merge 冲突最小化
- 支持嵌套 Resource——WaveRules 含 `Array[SpawnRule]` 完全可行

### Negative
- `.tres` 是 Godot 专有格式——非 Godot 工具无法读取
- 二进制`.res` 不可 diff——但 `.tres` 是文本格式，支持 git diff
- Resource 类定义在 GDScript 中——字段增删需要改脚本

### Risks
- `.tres` 文件数量膨胀——MVP ~15 个，V1.0 可能 30+。缓解：用 `DirAccess` 批量加载，不依赖文件名硬编码
- `@export` 字段重命名会丢失已有数据——Godot 编辑器不会自动迁移。缓解：不重命名——只新增字段

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| data-config.md | 所有数值外部化——不硬编码 | `.tres` Custom Resource 提供编辑器可编辑的外部化存储 |
| data-config.md | 每实体一文件 | `towers/cannon_1star.tres` 等独立文件 |
| data-config.md | 各系统自加载 | `DirAccess` + `load()` 在每个系统的 `_ready()` 中 |
| data-config.md | Fallback 默认值 | `load()` null → fallback 常量 |
| tower-system.md | 9 种塔变体从 TowerData 读取 | `TowerData` Resource 类 + 9 个 `.tres` 文件 |
| monster-system.md | 怪物属性从 MonsterData 读取 | `MonsterData` Resource 类 + 每怪物一个 `.tres` |

## Performance Implications
- **CPU**: `load()` 在 `_ready()` 中执行——每个文件 < 1ms。15 文件 < 15ms 启动开销
- **Memory**: 每个 `.tres` 加载后在内存中常驻。15 个 Resource 对象 ≈ 15-30KB
- **Load Time**: 所有数据在场景加载时一次性加载——不增加运行时开销

## Validation Criteria
- 所有 7 个数据消费系统通过 `load()` 获取数值——代码审查无硬编码数字
- `.tres` 文件缺失时游戏启动不崩溃——显示 fallback 值并打印警告
- Godot 编辑器中可双击 `.tres` 在 Inspector 中编辑

## Related Decisions
- ADR-0001: SignalBus — 数据配置不发射信号（纯查询接口）
- `design/gdd/data-config.md` — 数据配置 GDD（Resource 类字段定义）
