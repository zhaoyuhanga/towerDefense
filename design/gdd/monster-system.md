# 怪物系统 (Monster System)

> **Status**: In Design
> **Author**: user + game-designer
> **Last Updated**: 2026-06-01
> **Implements Pillar**: Pillar 2 — 每一波都是考卷（怪物是"考题"的载体）

## Overview

怪物系统管理所有敌方单位的完整生命周期：从波次生成系统在入口处创建怪物，到怪物沿寻路系统提供的主路径逐格移动，到接收伤害、血量归零死亡、或抵达出口突破防线。它是"考题"的物理载体——每一只怪物都是对玩家布局的一次测试。

怪物系统被 5 个下游系统依赖（塔/战斗/波次/技能/视觉），是整个 Core 层交互最密集的系统。它的接口设计决定了所有与"敌人"相关的系统如何协作。

## Player Fantasy

玩家不直接控制怪物——他们通过布局来"应对"怪物。怪物的视觉设计和移动模式塑造了"威胁感"：纯有机曲线的外形提醒玩家"这是不属于这里的东西"（美术圣经 Section 3），沿路径蠕动的运动模式让玩家有时间评估威胁（Pillar 4）。

- **直接服务于 Pillar 2（每一波都是考卷）**：怪物是考题——它们的类型组合、数量、速度定义了考试的难度
- **间接服务于 Pillar 1（路线即武器）**：怪物沿路线行进——路线越长，火力覆盖时间越多，怪物的威胁越低
- **参考体验**：Bloons TD 6 的气球——不同颜色=不同血量/速度，清晰可辨

## Detailed Design

### Core Rules

1. **路径跟随**：怪物从入口生成后，沿主路径逐 waypoint 移动。每帧移动距离 = `speed * delta`。到达一个 waypoint 后瞄准下一个。到达最后一个 waypoint（EXIT）→ 防线突破。
2. **血量管理**：怪物持有 `current_health`，初始值 = MonsterData.health。收到伤害时扣减，≤0 时死亡。
3. **死亡触发**：死亡时 → 发射 `monster_died` 信号（携带 monster_id + 位置 + reward_gold）→ 经济系统获得金币 → 视觉反馈系统播放死亡动画。
4. **突破触发**：怪物到达 EXIT → 发射 `monster_breached` 信号 → 防线生命扣减 → 视觉反馈显示路径伤疤。
5. **数据驱动**：所有怪物属性（health/speed/reward/tier/size_ratio）从 MonsterData 资源文件加载——不硬编码。
6. **对象池**：怪物频繁创建/销毁——使用对象池避免 GC 抖动。池大小 = 屏幕上同时存在的最大怪物数（≈50）。

### States

```
SPAWNING → MOVING → [DYING | BREACHED]
                 ↑        ↓
                 └──(take_damage while health > 0)
```

| 状态 | 含义 | 动画/视觉 |
|------|------|----------|
| `SPAWNING` | 从入口浮现（~0.3s） | 淡入 + 微小缩放 |
| `MOVING` | 沿路径移动 | 有机蠕动动画 |
| `STUNNED` | 被冰冻技能暂停 | 青色覆盖 + 静止 |
| `DYING` | 血量归零，播放死亡动画 | 有机碎片飞散（Section 5.5.1） |
| `BREACHED` | 抵达出口，突破防线 | 路径伤疤（Section 5.5.2） |

### Interactions

| 接口 | 签名 | 调用者 |
|------|------|--------|
| 生成怪物 | `spawn_monster(monster_id: String) -> Monster` | 波次生成 |
| 承受伤害 | `take_damage(monster: Monster, amount: float)` | 战斗/伤害 |
| 施加效果 | `apply_effect(monster: Monster, effect: String, duration: float, value: float)` | 应急技能 |
| 怪物死亡信号 | `monster_died(monster_id, position, reward)` | 经济、视觉反馈 |
| 怪物突破信号 | `monster_breached(position, path)` | 视觉反馈、准备阶段 |
| 获取活跃怪物 | `get_active_monsters() -> Array[Monster]` | 防御塔（寻找目标） |
| 怪物位置 | `monster.get_position() -> Vector2` | 防御塔、视觉反馈 |

## Formulas

### 移动计算

`new_position = current_position + direction * speed * delta`

| 变量 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `speed` | float | 20–200 px/s | 从 MonsterData 读取 |
| `direction` | Vector2 | 单位向量 | 指向下一 waypoint |

### 血量计算

`current_health -= damage_amount`

无护甲/抗性（MVP 简化）。所有伤害为真实伤害。

## Edge Cases

- **怪物生成时路径为空**：寻路返回空路径 → 怪物不生成，波次生成系统收到警告
- **多只怪物在同一格**：怪物之间无碰撞——可以重叠。视觉上通过小幅随机偏移区分
- **怪物在冻结算期间死亡**：冰冻效果立即终止，死亡动画正常播放
- **Boss 怪物的特殊处理**：Boss 在 `tier == "boss"` 时——更高的 health、更大的 size_ratio、死亡时额外金色光点特效

## Dependencies

| 上游 | 关系 | 接口 |
|------|------|------|
| 棋盘网格 | Hard | `grid_to_world()` 坐标转换 |
| 怪物寻路 | Hard | `get_main_path()`, `path_updated` 信号 |
| 数据配置 | Hard | MonsterData 资源文件 |

| 下游 | 关系 | 提供的接口 |
|------|------|----------|
| 防御塔 | Hard | `get_active_monsters()` |
| 战斗/伤害 | Hard | `take_damage()` |
| 波次生成 | Hard | `spawn_monster()` |
| 应急技能 | Hard | `apply_effect()` |
| 视觉反馈 | Hard | `monster_died`, `monster_breached` 信号 |
| 经济系统 | Hard | `monster_died.reward_gold` |

## Tuning Knobs

怪物系统的所有数值在 MonsterData 文件中。系统本身无额外 Knob——行为参数（对象池大小 = 50）在代码中，非设计可调。

## Visual/Audio Requirements

- **视觉**：纯有机曲线剪影（美术圣经 Section 3.2），尺寸比例按 `size_ratio`。普通/精英/Boss 的视觉区分见美术圣经 Section 5.3
- **移动动画**：有机蠕动——通过 shader 或精灵帧动画实现沿路径方向的轻微形变
- **死亡 VFX**：有机碎片飞散（Section 5.5.1），碎片数量 = 6-16（按 tier）
- **音效**：受伤=短促"嘶"，死亡=闷响"噗"，突破=低频警报

## UI Requirements

怪物本身不渲染 UI。以下 UI 元素依赖怪物数据：

| UI 元素 | 数据来源 |
|---------|---------|
| 怪物血条（悬停在怪物上方） | `monster.current_health / MonsterData.health` |
| 怪物信息浮层（悬停时） | MonsterData |

> **📌 UX Flag**：怪物血条使用微圆角（美术圣经 Section 3.3 唯一例外——附着在有机实体上的 UI 元素）。

## Acceptance Criteria

- **GIVEN** 波次生成调用 `spawn_monster("basic")`，**WHEN** 怪物在 ENTRANCE 生成，**THEN** 怪物沿主路径向 EXIT 移动
- **GIVEN** 怪物 health=100，**WHEN** `take_damage(30)` 被调用，**THEN** current_health=70
- **GIVEN** 怪物 current_health=10，**WHEN** `take_damage(20)` 被调用，**THEN** current_health=0，`monster_died` 信号发射
- **GIVEN** 怪物到达 EXIT，**WHEN** 抵达最后一个 waypoint，**THEN** `monster_breached` 信号发射
- **GIVEN** 10 只活跃怪物，**WHEN** `get_active_monsters()` 被调用，**THEN** 返回恰好 10 个 Monster 实例
- **GIVEN** 怪物被冰冻技能命中，**WHEN** `apply_effect(monster, "freeze", 3.0, 0.5)`，**THEN** 怪物静止 3 秒，速度降低 50%

## Open Questions

1. **怪物碰撞**：当前设计无怪物间碰撞。V1.0 是否需要→取决于测试反馈
2. **护甲/抗性系统**：MVP 不做。V1.0 是否需要→取决于是否有足够多的伤害类型
3. **怪物逃跑/恐惧行为**：被冰冻外是否需要其他行为修改→远期