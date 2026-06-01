# 防御塔系统 (Tower System)

> **Status**: In Design
> **Author**: user + game-designer
> **Last Updated**: 2026-06-01
> **Implements Pillar**: Pillar 3 — 低星不废高星不无敌

## Overview

防御塔系统管理玩家在棋盘上放置的所有防御塔。3 种塔（炮塔/冰塔/箭塔）× 3 个星级 = 9 种塔变体，每种从 TowerData 资源加载属性。塔在建造阶段被放置在 EMPTY 格上，战斗阶段自动攻击范围内的怪物。塔的星级通过合星升级系统提升——但高星不等于全面碾压（Pillar 3）：不同星级和类型的塔在攻击力、范围、特殊效果上有各自不可替代的角色。

## Player Fantasy

玩家感受的是**"我的防线在替我战斗"**。塔不是由你手动操作的——你放下它们，它们在战斗阶段自行攻击。你的成就感来自"我选对了位置、我合对了星、我的防线完美运转"。

- **炮塔（方）**：可靠、不炫耀——AOE 爆炸清小怪，沉默的守护者
- **冰塔（圆）**：保护的结界——范围减速让怪物走得更慢，给其他塔更多输出时间
- **箭塔（三角）**：锐利的狙击——单体高伤专打精英/Boss

## Detailed Design

### Core Rules

1. **放置**：建造阶段，左键选中塔类型 → 点击 EMPTY 格放置。扣减 TowerData.cost 金币。塔占格后该格变为 TOWER 状态。
2. **自动攻击**：战斗阶段，每座塔以 `attack_interval = 1.0 / attack_speed` 秒的间隔自动攻击（`attack_speed` = 每秒攻击次数）。攻击时调用 `combat.process_attack(self, target)`——塔不直接操作怪物，所有伤害/减速/穿透逻辑统一由战斗系统处理。目标选择：**优先打路径上最远的怪物**（waypoint_index 最大——离 EXIT 最近）。平局时选 health 最低的（最快击杀 = 最多减威胁）。
3. **三种塔的独特机制**：

| 塔 | 主色 | 形状 | 攻击模式 | 特殊效果 |
|----|------|------|---------|---------|
| 炮塔 Cannon | 霜钢蓝 | 方 | 范围爆炸（AOE） | 对目标周围 3×3 区域造成 `special_value`% 溅射伤害 |
| 冰塔 Ice | 冰川青 | 圆 | 单体攻击 | 命中附加减速 `special_value`%，持续 1 秒 |
| 箭塔 Arrow | 翠绿 | 三角 | 单体攻击 | 30% 概率穿透——攻击弹射到下一个怪物（`special_value`≤3次） |

4. **星级差异（Pillar 3 核心）**：

| 星级 | 攻击力 | 范围 | 特殊效果强化 |
|------|--------|------|------------|
| 1 星 | 基准 | 基准 | 基准 |
| 2 星 | ×2.0 | +15% | 效果提升（溅射范围+1格 / 减速+20% / 穿透次数+1） |
| 3 星 | ×4.0 | +30% | 效果大幅提升（溅射5×5 / 减速翻倍 / 穿透次数+2） |

5. **出售**：右键点击塔 → 返还 TowerData.sell_value 金币 → 塔被移除 → 格恢复 EMPTY。
6. **数据驱动**：所有数值（attack/range/speed/cost）从 TowerData 读取，不在代码中硬编码。

### States

塔是**无状态**的——它们要么在棋盘上（TOWER），要么不在。攻击行为由战斗阶段定时器驱动。

### Interactions

| 接口 | 签名 | 调用者 |
|------|------|--------|
| 放置塔 | `place_tower(tower_id: String, star: int, col: int, row: int) -> bool` | 输入处理 |
| 出售塔 | `sell_tower(col: int, row: int) -> int` | 输入处理 |
| 获取塔 | `get_tower(col: int, row: int) -> Tower` | 合星升级、HUD/UI |
| 攻击循环 | `_on_attack_tick()` (Timer) | 内部——每 `1/attack_speed` 秒触发 |
| 寻找目标 | `find_target(tower: Tower) -> Monster` | 内部——从 `get_active_monsters()` 中选择 |

## Formulas

### 目标选择

`target = closest_to_exit(monsters_in_range(tower))`

优先攻击路径上进度最远的怪物（`waypoint_index` 最大的）。

### 伤害计算

`actual_damage = TowerData.attack`（MVP 无护甲/抗性——所有伤害为真实伤害）

### 溅射伤害（炮塔）

`aoe_damage = actual_damage * special_value / 100`（对范围内的非主目标）

### 减速效果（冰塔）

`monster.speed *= (1 - special_value / 100)`，持续 `effect_duration` 秒（从 TowerData 读取，冰塔默认 1.0 秒）

### 穿透概率（箭塔）

`if randf() < 0.3: bounce_to_next_target()`（最多 `special_value` 次）

## Edge Cases

- **范围内无怪物**：塔不攻击——等待下一次 attack tick
- **目标在攻击动画中死亡**：立即切换目标——不浪费一次攻击
- **塔在战斗阶段被出售**：不允许——输入处理 GDD 禁止战斗阶段右键出售。此操作仅在建造阶段有效
- **多塔同时攻击同一怪物**：各自独立计算伤害——无"过量击杀保护"（overskill 是玩家布局效率问题）
- **冰塔减速叠加**：同一怪物被多个冰塔命中 → 减速效果取最大值（不叠加，防止无限减速）

## Dependencies

| 上游 | 关系 | 接口 |
|------|------|------|
| 棋盘网格 | Hard | `get_cell_state()`, `set_cell_state()` |
| 怪物系统 | Hard | `get_active_monsters()` |
| 数据配置 | Hard | TowerData 资源文件 |
| 经济系统 | Hard | `spend_gold()`, `add_gold()` |

| 下游 | 关系 | 提供的接口 |
|------|------|----------|
| 合星升级 | Hard | `get_tower()` |
| 战斗/伤害 | Hard | 攻击触发 → 调用 `monster.take_damage()` |
| 准备阶段 | Soft | 塔的放置/出售被建造阶段时间窗口门控 |
| HUD/UI | Hard | 塔信息浮层数据 |

## Tuning Knobs

所有 Knob 在 TowerData 文件中。关键交互：

- **attack vs MonsterData.health**：攻防比决定"几下打死一个怪"
- **attack_speed vs MonsterData.speed**：怪物穿过火力区的时间内塔能攻击几次
- **range vs CELL_SIZE**：范围/56 = 覆盖几格——决定塔的最佳放置位置

## Acceptance Criteria

- **GIVEN** 建造阶段+EMPTY 格+足够金币，**WHEN** 放置 1 星炮塔，**THEN** 塔出现在该格，金币扣减，格状态变为 TOWER
- **GIVEN** 战斗阶段+炮塔范围内有怪物，**WHEN** attack tick 触发，**THEN** 怪物 `take_damage(attack)` 被调用
- **GIVEN** 炮塔攻击，**WHEN** 周围有其他怪物在 3×3 范围内，**THEN** 副目标受到 AOE 溅射伤害
- **GIVEN** 冰塔命中怪物，**WHEN** 减速效果施加，**THEN** 怪物速度降低 `special_value`%，持续 1 秒
- **GIVEN** 箭塔攻击，**WHEN** 穿透触发（30%概率），**THEN** 攻击弹射到下一个怪物
- **GIVEN** 右键点击塔，**WHEN** `sell_tower()` 被调用，**THEN** 塔被移除，sell_value 加入金币

## Open Questions

1. **塔攻击优先级策略**："最近出口" vs "最弱" vs "最强"——当前默认最近出口（平局选最弱）。V1.0 可添加玩家可选的目标优先级
2. **塔升级动画**：升星时是否需要短暂的"离线"时间（塔在合星动画期间不攻击）？→ 需要——合星的 ~0.8s 期间旧塔已移除、新塔尚未就位
3. **箭塔穿透的随机性 vs 确定性**：当前 30% 概率随机穿透——削弱了 Pillar 4 "你观"的可预见性。V1.0 考虑改为确定性节奏（如"每第 3 次攻击必定穿透"）