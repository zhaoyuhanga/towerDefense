# 棋盘网格系统 (Board Grid System)

> **Status**: In Design
> **Author**: user + game-designer
> **Last Updated**: 2026-06-01
> **Implements Pillar**: Pillar 1 — 路线即武器

## Overview

棋盘网格系统是整个游戏的空间数据层。它管理一张 **20 列 × 15 行**的矩形棋盘，维护每个单元格的占用状态（空 / 方块 / 防御塔 / 怪物入口 / 怪物出口），提供坐标-屏幕位置转换，并向所有上层系统（寻路、方块、塔、怪物、场景）暴露统一的空间查询接口。

玩家不直接与棋盘网格交互——他们通过放置方块和塔来间接改变网格状态。但棋盘网格的 API 约束定义了整个游戏的空间规则：什么能放在哪里、每个格子的状态如何影响寻路、棋盘边界在哪里。

没有棋盘网格，就没有坐标系统、没有单元格概念、没有"能不能放在这里"的判断——它就是游戏世界的物理法则。

## Player Fantasy

玩家不直接感受棋盘网格。他们感受的是**"在棋盘上布局"**——方块放下去路线就变了、塔放下去火力就覆盖了。棋盘网格是这种掌控感的沉默载体：它不抢戏，但没有它，玩家的每一次布局决策都无处安放。

- **间接服务于 Pillar 1（路线即武器）**：网格是路线的载体——没有网格就没有路线，没有路线就没有武器
- **间接服务于 Pillar 4（你造你观你调）**：网格是"筑城"的画布——玩家在网格上规划、网格在战斗中验证
- **参考体验**：国际象棋棋盘——你不对棋盘本身产生情感，但棋盘上发生的一切都因它而成为可能

## Detailed Design

### Core Rules

1. **棋盘尺寸**：20 列 × 15 行，总 300 个单元格。
2. **坐标系**：`Vector2i(col, row)`，`(0,0)` 在左上角。col 向右增长（0→19），row 向下增长（0→14）。与 Godot 2D 屏幕坐标系一致。
3. **单元格互斥**：每个单元格在同一时刻只有一种状态。一个格子不能同时放方块和塔。
4. **边界不可穿越**：棋盘四条边是硬边界。寻路系统不会走出棋盘范围。

**细胞状态定义**：

| 状态 | 含义 | 可被覆盖？ | 对寻路的意义 |
|------|------|----------|------------|
| `EMPTY` | 空格——可放置塔或方块 | 可被塔/方块覆盖 | 可行走 |
| `BLOCK` | 障碍方块——不可穿越 | 不可 | 不可行走（solid） |
| `TOWER` | 防御塔占位——不可穿越 | 可被更高星塔替换（同类型同位置） | 不可行走（solid） |
| `ENTRANCE` | 怪物入口——怪物生成点 | 不可 | 起点，可行走 |
| `EXIT` | 怪物出口——怪物目标/消失点 | 不可 | 终点，可行走 |

5. **ENTRANCE/EXIT 固定**：入口和出口位置在游戏开始时设定，一局内不变。至少各有 1 个。入口在棋盘边缘一侧，出口在对面侧。

### States and Transitions

```
EMPTY ──放置方块──▶ BLOCK
EMPTY ──放置塔────▶ TOWER
BLOCK ──移除方块──▶ EMPTY
TOWER ──卖掉塔────▶ EMPTY
TOWER ──合星升级──▶ TOWER（同位置，高星塔替换低星塔）
ENTRANCE ──────────▶（不变——整局不变）
EXIT ──────────────▶（不变——整局不变）
```

- **不可逆**：ENTRANCE/EXIT → 任何其他状态 ❌
- **幂等**：同一个 BLOCK 上再次放方块 → 无效果
- **TOWER 同位替换**：合星后新塔放在原塔位置——先移除旧塔（TOWER→EMPTY），立即放置新塔（TOWER→EMPTY），在同一帧内完成

### Interactions with Other Systems

棋盘网格通过以下接口向外部系统暴露数据：

| 接口 | 签名 | 调用者 | 说明 |
|------|------|--------|------|
| **查询状态** | `get_cell_state(col, row) -> CellState` | 寻路、方块、塔、怪物、UI | 最频繁的调用 |
| **修改状态** | `set_cell_state(col, row, state) -> bool` | 方块、塔、场景管理 | 唯一写入入口。返回 false 如果转换不合法 |
| **坐标转换** | `grid_to_world(col, row) -> Vector2` | 渲染、怪物移动、特效 | 网格坐标 → 屏幕像素中心点 |
| **反向转换** | `world_to_grid(world_pos) -> Vector2i` | 输入处理 | 鼠标位置 → 网格坐标 |
| **邻居查询** | `get_neighbors(col, row) -> Array[Vector2i]` | 寻路 | 返回四方向相邻格坐标（忽略边界外） |
| **边界检查** | `is_valid_position(col, row) -> bool` | 所有放置操作 | 坐标是否在棋盘范围内 |
| **状态变更信号** | `cell_state_changed(col, row, old, new)` | 寻路、视觉反馈 | 任何状态变更都发射此信号 |

**所有权规则**：棋盘网格只管"格子里放了什么"。塔的属性、怪物的路径、方块合法性——分别由各自系统管理。网格只提供空间真相。

## Formulas

### D.1 单元格尺寸计算

基于 1080p 基准分辨率（1920×1080），顶部栏 48px + 底部栏 64px + 呼吸间距 32px：

`CELL_SIZE = floor((1080 - 48 - 64 - 32) / 15) = floor(936 / 15) = 62px → 取 56px`

| 变量 | 类型 | 值 | 说明 |
|------|------|-----|------|
| `CELL_SIZE` | int | 56 | 单元格像素边长（1x 等级） |
| `GRID_COLS` | int | 20 | 棋盘列数 |
| `GRID_ROWS` | int | 15 | 棋盘行数 |
| `GRID_ORIGIN_X` | int | 400 | 棋盘左上角 X 偏移（(1920 - 20×56) / 2） |
| `GRID_ORIGIN_Y` | int | 64 | 棋盘左上角 Y 偏移（顶部栏之下） |

### D.2 网格 → 屏幕坐标

`grid_to_world(col, row) = Vector2(GRID_ORIGIN_X + col * CELL_SIZE + CELL_SIZE / 2, GRID_ORIGIN_Y + row * CELL_SIZE + CELL_SIZE / 2)`

| 变量 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `col` | int | 0–19 | 网格列号 |
| `row` | int | 0–14 | 网格行号 |

输出：单元格中心点的屏幕像素坐标。+ CELL_SIZE/2 确保返回格子**中心**。

### D.3 屏幕 → 网格坐标

`world_to_grid(screen_pos) = Vector2i(floori((screen_pos.x - GRID_ORIGIN_X) / CELL_SIZE), floori((screen_pos.y - GRID_ORIGIN_Y) / CELL_SIZE))`

输出可能超出棋盘范围——调用方必须用 `is_valid_position()` 验证。

### D.4 邻居查询

`get_neighbors(col, row) = [Vector2i(col-1,row), Vector2i(col+1,row), Vector2i(col,row-1), Vector2i(col,row+1)].filter(is_valid_position)`

四方向无对角线——寻路使用曼哈顿距离，怪物只走正交方向。

## Edge Cases

- **放置到非空格**：`set_cell_state()` 返回 false。方块系统/塔系统需自行处理"不能放这里"的反馈（预览变红）
- **坐标越界**：`world_to_grid()` 可能返回越界坐标。所有调用方必须先用 `is_valid_position()` 验证——网格本身不对越界坐标做 clamp
- **覆盖 ENTRANCE/EXIT**：`set_cell_state(entrance_col, entrance_row, BLOCK)` → 返回 false。入口和出口是不可变格
- **棋盘全满**：若所有 300 格被方块/塔占满且无可通行路径——寻路系统返回空路径。准备阶段系统应阻止堵死路径的最后一个方块（但由方块+寻路系统联合判断，网格只管状态）
- **分辨率变化**：`GRID_ORIGIN_X` 和 `GRID_ORIGIN_Y` 在窗口 resize 时重新计算。`CELL_SIZE` 保持不变（`canvas_items` + `integer` scale mode）

## Dependencies

棋盘网格是 Foundation 层，**零上游依赖**。所有依赖都是下游的：

| 下游系统 | 关系 | 接口 |
|----------|------|------|
| 怪物寻路 | Hard — 需要网格状态构建 AStarGrid2D | `get_cell_state()`, `get_neighbors()`, `is_valid_position()`, `cell_state_changed` |
| 障碍方块 | Hard — 通过 `set_cell_state()` 放置/移除方块 | `set_cell_state()`, `is_valid_position()`, `get_cell_state()` |
| 防御塔 | Hard — 塔只能放在 EMPTY 格上 | `set_cell_state()`, `get_cell_state()`, `grid_to_world()` |
| 怪物系统 | Hard — 怪物在网格坐标上移动 | `grid_to_world()`, `get_cell_state()` |
| 场景管理 | Hard — 初始化棋盘、设置入口/出口 | `set_cell_state()`（初始化时） |

## Tuning Knobs

| Knob | 默认值 | 安全范围 | 说明 |
|------|--------|----------|------|
| `CELL_SIZE` | 56 | 48–64（1x） | 改变需要重新导出所有精灵图 |
| `GRID_COLS` | 20 | 15–25 | 改变列数影响游戏平衡——更多列=更容易防守 |
| `GRID_ROWS` | 15 | 10–20 | 同上。改变需要重新计算 GRID_ORIGIN_Y |
| `GRID_ORIGIN_X` | 计算值 | 自动 | `(SCREEN_WIDTH - GRID_COLS × CELL_SIZE) / 2` |
| `GRID_ORIGIN_Y` | 64 | 48–80 | 顶部栏高度的函数 |

## Acceptance Criteria

- **GIVEN** 新游戏开始，**WHEN** 棋盘初始化完成，**THEN** 20×15 网格全部为 EMPTY，除指定的 ENTRANCE 和 EXIT 位置
- **GIVEN** (5, 3) 是 EMPTY，**WHEN** `set_cell_state(5, 3, BLOCK)` 被调用，**THEN** 返回 true，该格状态变为 BLOCK，`cell_state_changed(5, 3, EMPTY, BLOCK)` 信号发射
- **GIVEN** (5, 3) 是 BLOCK，**WHEN** `set_cell_state(5, 3, EMPTY)` 被调用，**THEN** 返回 true，该格恢复为 EMPTY
- **GIVEN** (0, 0) 是 ENTRANCE，**WHEN** `set_cell_state(0, 0, BLOCK)` 被调用，**THEN** 返回 false，状态不变
- **GIVEN** 鼠标位置在屏幕上，**WHEN** `world_to_grid(mouse_pos)` 被调用，**THEN** 返回正确的网格坐标
- **GIVEN** 网格坐标 (10, 7)，**WHEN** `grid_to_world(10, 7)` 被调用，**THEN** 返回该格中心点的像素坐标
- **GIVEN** 坐标 (-1, 20)，**WHEN** `is_valid_position(-1, 20)` 被调用，**THEN** 返回 false
- **GIVEN** 坐标 (10, 7) 在棋盘内，**WHEN** `get_neighbors(10, 7)` 被调用，**THEN** 返回恰好 4 个坐标：(9,7), (11,7), (10,6), (10,8)

## Visual/Audio Requirements

- **视觉参考**：美术圣经 Section 3.2（棋盘网格线）和 Section 4.1（石板灰 `#4A6078`）
- **网格线**：正交直线，1-2px 均匀线宽，实线无虚线无渐变，转角严格 90° 无圆角
- **网格底色**：石板灰深色变体 `#263040`（棋盘底），极微弱蓝图网格纹理（透明度 3-5%）可选
- **建造阶段**：网格线 ~70-80% 可见度
- **战斗阶段**：网格线 ~60% 可见度（特效层透明度 ≤40% 保证网格不被遮挡）
- **音频**：无——棋盘网格是静默的数据层
- **渲染方式**：使用 Godot TileMapLayer 渲染网格线和单元格底色

## UI Requirements

棋盘网格没有独立的 UI 界面。以下 UI 元素依赖网格的坐标转换能力：

| UI 元素 | 使用的接口 | 所属系统 |
|---------|----------|---------|
| 放置预览方块（跟随光标） | `world_to_grid()` | 障碍方块系统 |
| 塔放置预览 | `world_to_grid()` | 防御塔系统 |
| 怪物路径显示 | `grid_to_world()` | 视觉反馈系统 |
| 塔攻击范围指示器 | `grid_to_world()` | 防御塔 / 视觉反馈系统 |

> **📌 UX Flag — 棋盘网格**：`world_to_grid()` 的精度和延迟直接影响放置预览的响应手感。在 `/ux-design` 阶段验证鼠标→预览的 1:1 跟随延迟。

## Open Questions

1. **TileMapLayer vs 自定义绘制**：网格线用 Godot 内置 TileMapLayer 渲染还是用 `_draw()` 自定义绘制？TileMapLayer 方便但灵活性低，`_draw()` 灵活但需性能验证。→ 实现阶段建 ADR
2. **蓝图纹理**：美术圣经 Section 6.3 允许 3-5% 透明度的蓝图网格纹理——MVP 需要吗？还是纯色底色够用？
3. **分辨率缩放**：在非 1080p 分辨率下（如 1366×768 笔记本），棋盘是否需要缩放还是裁剪？`canvas_items` + `expand` 模式的具体表现需要测试
