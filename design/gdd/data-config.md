# 数据配置系统 (Data Configuration System)

> **Status**: In Design
> **Author**: user + game-designer
> **Last Updated**: 2026-06-01
> **Implements Pillar**: 全部支柱 — 所有数值必须支持 Pillar 1-4 的游戏体验

## Overview

数据配置系统是游戏中所有数值的**唯一数据源（Single Source of Truth）**。它将塔属性、怪物属性、波次生成规则、经济数值、技能参数、棋盘常量等所有可调数值外部化到 Godot Custom Resource（`.tres`）文件中，任何系统需要数值时都从数据配置读取——不硬编码任何一个数字。

玩家不与此系统交互。但每个玩家能感受到的数值——塔打一下多少伤害、怪物有多少血、升级花多少钱——都来自这里。数据配置系统的设计质量直接决定数值调整的效率和平衡迭代的速度。

## Player Fantasy

玩家不直接感受数据配置。他们感受的是**"数值是对的"**——塔的伤害让人觉得值回票价、怪物的血量让人觉得有挑战但不恶心、升级的代价让人觉得是明智的投资。

- **间接服务于所有四大支柱**：每个支柱的落地都依赖正确的数值——路线的价值由怪物速度和经济成本定义（P1）、考试的难度由波次曲线定义（P2）、低星塔的价值由功能性数值定义（P3）、造和观的节奏由经济约束定义（P4）
- **参考体验**：Factorio 的配方面板、Civilization 的科技树数值——数据本身不提供情感，但正确的数据是情感的前提

## Detailed Design

### Core Rules

1. **唯一数据源**：游戏中所有可调数值必须存在于一个 `.tres` 文件中。代码中裸数字（`0`、`100`、`1.5`）不被允许——所有数值通过 `load()` 从资源文件读取。
2. **每实体一文件**：一个 `.tres` = 一个游戏实体的完整数值。
3. **各系统自加载**：塔系统加载塔数据，怪物系统加载怪物数据。没有中央 DataManager autoload。
4. **只读**：运行时数据不可写——`.tres` 文件在构建时确定，运行时只读取。

### 数据分类与文件结构

```
assets/resources/data/
├── grid_config.tres
├── towers/          # 9 × TowerData
├── monsters/        # N × MonsterData
├── waves/           # WaveRules
├── economy.tres     # EconomyConfig
└── skills/          # 2 × SkillConfig
```

### Godot Resource 类定义

**TowerData**：`tower_id: String, star_level: int, display_name: String, attack: float, attack_speed: float（每秒攻击次数）, range: float, cost: int, sell_value: int, special_effect: String, special_value: float, effect_duration: float（冰塔减速持续秒数，其余塔=0）`

**MonsterData**：`monster_id: String, display_name: String, health: float, speed: float, reward_gold: int, tier: String, has_affix: bool, size_ratio: float`

**WaveRules**：`spawn_rules: Array[SpawnRule]` — 每条 SpawnRule 含 `wave_range: Vector2i, monster_pool: Array[String], monster_count: int, spawn_interval: float, affix_pool: Array[String]`

**EconomyConfig**：`starting_gold: int, kill_reward_multiplier: float, block_cost: int, block_sell_value: int, merge_cost: int`

**SkillConfig**：`skill_id: String, max_uses: int, duration: float, cooldown: float, effect_amount: float`

**GridConfig**（引用棋盘 GDD 的常量）：`grid_cols: int, grid_rows: int, cell_size: int, origin_x: int, origin_y: int`

### 加载模式

每个系统在 `_ready()` 中用 `DirAccess` 遍历自己的数据目录，`load()` 每个 `.tres` 到 Dictionary。Key = `"[id]_[variant]"`。

### States

数据配置系统无运行时状态——启动时加载，此后只读。

## Formulas

数据配置系统没有数学公式——但定义了每个字段的合法范围（校验公式）：

| Resource | 字段 | 合法范围 | 校验规则 |
|----------|------|---------|---------|
| TowerData | `attack` | 1.0–999.0 | 同类型内 1 星 < 2 星 < 3 星 |
| TowerData | `range` | 32–256 | 冰塔 range ≥ 炮塔 range |
| TowerData | `cost` | 10–9999 | 高星 > 低星，不能为负 |
| MonsterData | `health` | 1.0–99999.0 | Boss > Elite > Standard |
| MonsterData | `speed` | 20.0–200.0 | Fast > Basic > Tank |
| WaveRules | `monster_count` | 1–50 | 随波次递增 |
| EconomyConfig | `starting_gold` | 50–500 | 够买 2-3 个塔 |

## Edge Cases

- **资源文件缺失**：`load()` 返回 null → 系统打印错误并启用 fallback 默认值。游戏不崩溃
- **字段值 ≤ 0**：经济/伤害相关字段不允许 0 或负数。加载时校验——若 ≤0，打印警告使用默认值
- **重复 tower_id + star_level**：后加载覆盖先加载，打印警告
- **SpawnRule 引用不存在的 monster_id**：波次生成时跳过该 ID 并打印警告。空波比崩溃好
- **.tres 类型不匹配**：`as` 转换返回 null → 跳过该文件，打印错误。不阻塞游戏启动

## Dependencies

零上游依赖。所有依赖都是下游：

| 下游系统 | 关系 | 使用的数据 |
|----------|------|----------|
| 怪物系统 | Hard | MonsterData——speed/health/tier |
| 防御塔系统 | Hard | TowerData——cost/attack/range/speed |
| 战斗/伤害 | Hard | TowerData.attack + MonsterData.health |
| 经济系统 | Hard | EconomyConfig + TowerData.cost + MonsterData.reward_gold |
| 波次生成 | Hard | WaveRules.spawn_rules |
| HUD/UI | Hard | 所有 display_name + 经济数值显示 |
| 存档 | Hard | GridConfig 引用确保格子常量一致 |
| 棋盘网格 | Soft | GridConfig 引用 CELL_SIZE/GRID_COLS/GRID_ROWS

## Tuning Knobs

每个 `@export` 字段都是 Tuning Knob。以下是关键交互关系：

| Knob 群 | 改太高 | 改太低 | 交互 |
|---------|--------|--------|------|
| TowerData.attack | 秒杀一切——无聊 | 打不动——挫败 | 必须和 MonsterData.health 成比例 |
| MonsterData.health | 肉盾墙——放弃 | 秒杀——Pillar 2 失效 | 同上 |
| EconomyConfig.starting_gold | 满屏塔——Pillar 1 失效 | 买不起——卡死 | 和 TowerData.cost 联动 |
| TowerData.range | 全屏覆盖——不需要布局 | 贴脸——Mazing 无意义 | 和 CELL_SIZE、网格尺寸联动 |
| MonsterData.speed | 闪现——反应不及 | 蜗牛——Pillar 2 失效 | 和 CELL_SIZE、路径长度联动 |

## Acceptance Criteria

- **GIVEN** 游戏启动，**WHEN** 塔系统加载 `towers/` 目录，**THEN** 成功加载 9 个 TowerData 文件（3 塔 × 3 星），无警告
- **GIVEN** 游戏启动，**WHEN** 怪物系统加载 `monsters/` 目录，**THEN** 至少加载 3 个 MonsterData 文件
- **GIVEN** 加载完成的 TowerData，**WHEN** 比较同类型星级数据，**THEN** 3 星 attack > 2 星 > 1 星
- **GIVEN** 某个 `.tres` 文件被删除，**WHEN** 系统尝试 `load()`，**THEN** 游戏不崩溃，打印错误，使用 fallback 默认值
- **GIVEN** EconomyConfig.starting_gold = 200，**WHEN** 新游戏开始，**THEN** 玩家金币 = 200
- **GIVEN** WaveRules 定义波次 1 生成 5 个 basic 怪物，**WHEN** 波次 1 开始，**THEN** 恰好生成 5 个 basic 怪物

## Visual/Audio Requirements

不适用。数据配置是纯数据层——没有视觉表现或音频输出。

## UI Requirements

不适用。没有独立的 UI 界面。以下 UI 元素依赖数据配置的值：

| UI 元素 | 依赖的数据 |
|---------|----------|
| 金币显示 | EconomyConfig.starting_gold |
| 塔购买按钮价格 | TowerData.cost |
| 波次计数 | WaveRules（波次总数信息） |
| 塔信息浮层 | TowerData（攻击力/范围/特殊效果） |

## Open Questions

1. **编辑器内编辑 vs 代码生成**：`.tres` 可手动编辑也可脚本批量生成。MVP 阶段手动创建 ~15 个文件足够。后期数量膨胀后是否需要生成工具？
2. **Fallback 默认值**：Edge Cases 中提到的 fallback 默认值定义在代码中还是单独的 `defaults.tres`？→ 实现阶段建 ADR
3. **热重载**：编辑器中修改 `.tres` 后运行中的游戏是否反映新值？Godot 导出构建后不支持——但编辑器内运行可以。MVP 不需要运行时热重载
