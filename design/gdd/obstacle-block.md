# 障碍方块系统 (Obstacle Block System)

> **Status**: In Design
> **Author**: user + game-designer
> **Last Updated**: 2026-06-01
> **Implements Pillar**: Pillar 1 — 路线即武器（方块是操控路线的唯一手段）

## Overview

障碍方块系统是 Pillar 1 "路线即武器"的物理载体。玩家在建造阶段花费金币将障碍方块放置在棋盘的空格上，方块使该格变为不可穿越——从而强制怪物寻路系统绕行。每一块方块的放置都是一次对路线的重新设计：怪物原本走直线，你放一块方块，它们就得绕路，多走的路程就是额外的火力覆盖时间。

方块可以被右键移除（返还部分金币），但移除只能在建造阶段进行——战斗一旦开始，你的设计就要接受检验。方块的购买成本和数量限制共同构成了 Mazing 策略的资源约束：你不能无限制地扭曲路线，每一块方块都是一次投资决策。

## Player Fantasy

玩家感受的是**"路线听我的"**——每次方块放下去、路线立刻拐弯、怪物被迫绕远路，那种"你的命运是我设计的"的掌控感。方块是玩家意志在棋盘上的物理延伸。

- **直接服务于 Pillar 1（路线即武器）**：方块是武器本身——不是塔，是方块
- **间接服务于 Pillar 4（你造你观你调）**：方块的放置是筑城阶段最核心的操作
- **参考体验**：Gemcraft 的宝石墙——每放一块，路线就变，即时反馈

## Detailed Design

### Core Rules

1. **放置条件**：方块只能放在 EMPTY 格上。不能覆盖 ENTRANCE/EXIT/TOWER/已有 BLOCK。
2. **路径保护**：放置前通过 `is_path_reachable()` 预检查——如果该方块会堵死 ENTRANCE→EXIT 的所有路径，放置被拒绝。
3. **建造阶段独占**：方块只能在建造阶段放置和移除。战斗阶段不可操作。
4. **成本与返利**：每块方块花费 `BLOCK_COST`（来自 EconomyConfig）。右键移除此方块返还 `BLOCK_SELL_VALUE`（< 原价，形成"投资不可完全撤回"的压力）。
5. **数量上限**：每局游戏可持有的方块总数有上限（`MAX_BLOCKS`），初始为 10。可通过经济系统扩容。
6. **即时生效**：方块放置后立即更新棋盘网格状态 → 触发寻路重算 → 怪物路径即时更新。

### States

方块本身无状态——它要么在棋盘上（BLOCK），要么被移除（EMPTY）。状态的流转由棋盘网格系统管理。

### Interactions

| 接口 | 签名 | 调用者 |
|------|------|--------|
| 放置方块 | `place_block(col, row) -> bool` | 输入处理 |
| 移除方块 | `remove_block(col, row) -> bool` | 输入处理 |
| 查询剩余数量 | `get_remaining_blocks() -> int` | HUD/UI |
| 方块数量变更信号 | `block_count_changed(remaining: int)` | HUD/UI |

## Formulas

### 放置成本

`place_cost = BLOCK_COST`

- 从 EconomyConfig 读取（默认 25 金币）
- 放置成功后从金币余额扣除

### 移除返利

`sell_value = BLOCK_SELL_VALUE`

- 从 EconomyConfig 读取（默认 10 金币）
- 移除后加入金币余额

### 路径预检查

```
can_place(col, row) =
    get_cell_state(col, row) == EMPTY
    AND get_remaining_blocks() > 0
    AND player_gold >= BLOCK_COST
    AND is_path_still_reachable_if_blocked(col, row)
```

| 变量 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `BLOCK_COST` | int | 10–100 | 每块方块的价格 |
| `BLOCK_SELL_VALUE` | int | 5–50 | 移除返利 |
| `MAX_BLOCKS` | int | 5–30 | 每局最大方块数 |

## Edge Cases

- **放置方块会堵死路径**：`is_path_reachable()` 预检查返回 false → 放置拒绝，预览方块显示红色 X
- **金币不够**：放置按钮/预览显示不可用状态——不是"点了才说不够"
- **方块数量已达上限**：同金币不够——预览不可用
- **右键移除入口/出口旁的方块导致路径消失**：不可能——移除方块只会增加可行走区域，不会减少。只有放置方块才可能堵死路
- **快速连续放置**：每次放置独立处理——前一次放置触发的寻路重算在放置下一块前必须完成。如果寻路未完成，新放置排队等待

## Dependencies

| 上游 | 关系 | 接口 |
|------|------|------|
| 棋盘网格 | Hard | `get_cell_state()`, `set_cell_state()` |
| 怪物寻路 | Hard | `is_path_reachable()` |
| 经济系统 | Hard | `spend_gold()`, `add_gold()`, `get_gold()` |
| 数据配置 | Hard | EconomyConfig（`BLOCK_COST`, `BLOCK_SELL_VALUE`, `MAX_BLOCKS`） |

| 下游 | 关系 | 提供的接口 |
|------|------|----------|
| 准备阶段 | Hard | 方块放置/移除操作被准备阶段的时间窗口门控 |
| HUD/UI | Hard | `get_remaining_blocks()`, `block_count_changed` |
| 视觉反馈 | Soft | 方块放置/移除事件触发视觉更新 |

## Tuning Knobs

| Knob | 默认值 | 安全范围 | 改太高 | 改太低 |
|------|--------|----------|--------|--------|
| `BLOCK_COST` | 25 | 10–100 | 买不起→Mazing 无法开始 | 满屏方块→Pillar 2 失效 |
| `BLOCK_SELL_VALUE` | 10 | 0–BLOCK_COST | 无成本试错→无策略压力 | 移不起→不敢放 |
| `MAX_BLOCKS` | 10 | 5–30 | 路线扭曲到极端→无聊 | 不足以做有意义的 Mazing |

## Visual/Audio Requirements

从美术圣经引用：

- **方块外观**：完美正方形（56×56px），填满单元格，锐利 90° 边角，石板灰纯色 + 1px 深色边线 + 1px 投影（Section 3.2）
- **放置动画**：方块从透明度 50%→100%（0.15s ease-out）——简洁不拖沓
- **移除动画**：方块透明度 100%→0%（0.15s ease-out）+ 微小缩放 100%→80%
- **放置预览**：半透明方块跟随光标——有效=霜钢蓝 50%，无效=猩红 50%+X 斜线（Section 4.2）
- **音效**：放置=短促低音"咚"，移除=轻快的"咔"

## UI Requirements

方块操作通过以下 UI 元素进行：

| UI 元素 | 功能 |
|---------|------|
| 底部栏方块按钮 | 切换当前工具为"方块模式"——选中后点击棋盘放置 |
| 剩余数量显示 | 方块按钮上显示 `剩余/上限` |
| 放置预览 | 光标跟随的半透明方块（视觉反馈系统渲染） |

> **📌 UX Flag — 障碍方块**：放置预览的 1:1 光标跟随 + 路径可达性实时预览（有效=蓝/无效=红）直接影响操作手感。在 `/ux-design` 阶段验证放置预览的响应延迟。

## Acceptance Criteria

- **GIVEN** 建造阶段+EMPTY 格(5,3)+足够金币+足够剩余方块，**WHEN** `place_block(5, 3)` 被调用，**THEN** 返回 true，该格变为 BLOCK，金币扣减，主路径更新
- **GIVEN** 放置方块会堵死所有路径，**WHEN** `place_block()` 预检查执行，**THEN** 返回 false，方块未放置，金币未扣
- **GIVEN** (5,3) 是 BLOCK，**WHEN** `remove_block(5, 3)` 被调用，**THEN** 该格变为 EMPTY，BLOCK_SELL_VALUE 加入金币
- **GIVEN** 金币 < BLOCK_COST，**WHEN** 尝试放置，**THEN** 放置被拒绝
- **GIVEN** 剩余方块 = 0，**WHEN** 尝试放置，**THEN** 放置被拒绝
- **GIVEN** 战斗阶段，**WHEN** 尝试放置或移除方块，**THEN** 操作被拒绝

## Open Questions

1. **方块扩容**：能否花金币增加 MAX_BLOCKS？→ V1.0 考虑，MVP 固定 10 块
2. **方块类型**：未来是否有不同类型的方块（如"荆棘方块"对怪物造成伤害）？→ 远期，MVP 只有一种
3. **方块旋转**：方块是正方形且占 1 格——不需要旋转。如果未来引入长方形方块才需要考虑