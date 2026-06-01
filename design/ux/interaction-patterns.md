# Interaction Pattern Library

> **Status**: Draft
> **Created**: 2026-06-01
> **Input Methods**: Keyboard/Mouse (primary: Mouse)
> **Platform**: Windows / macOS Desktop
> **Gamepad**: None | **Touch**: None

## Overview

本库定义了迷宫建造型塔防游戏中的所有标准交互模式。每个模式指定触发方式、视觉反馈、输入映射和可访问性要求。所有 UX spec 引用此库中的模式名称——不在各 spec 中重复定义交互细节。

## Pattern Catalog

| # | Pattern | Category | Used In |
|---|---------|----------|---------|
| 1 | Click-to-Place | Input / Grid | Tower placement, Block placement |
| 2 | Drag-to-Merge | Input / Merge | Tower merge upgrade |
| 3 | Right-Click Context | Input / Context Menu | Block removal, Tower sell, Merge alternative |
| 4 | Hover Preview | Feedback / Grid | Placement ghost for towers and blocks |
| 5 | Drag Ghost | Feedback / Merge | Semi-transparent tower follows cursor during merge |
| 6 | Phase-Gated Input | State / Input Routing | All grid interactions (PREP vs BATTLE) |
| 7 | Button Click | Input / UI | Start wave, Skills, Menu navigation |
| 8 | Tooltip-on-Hover | Feedback / Info | Tower stats, Monster info |

---

## Patterns

### Pattern 1: Click-to-Place

**Category**: Input / Grid
**Used In**: Tower placement, Block placement, Tower selection

**Description**: 玩家左键点击棋盘上的 EMPTY 格来放置当前选中的塔或方块。点击 TOWER 格则选中该塔。这是游戏中最频繁的交互——每次筑城阶段可能发生数十次。

**Specification**:
- **触发**: 左键在棋盘格上释放，且鼠标移动 < 3px（非拖拽）
- **输入映射**: `MOUSE_BUTTON_LEFT` + `pressed=false` + `distance < DRAG_THRESHOLD`
- **视觉反馈**: 放置成功 → 塔/方块立即出现在格子上 + 短暂缩放弹入 (~0.1s)；放置失败 → 预览变红 + 拒绝音效
- **音频反馈**: 放置确认音效（短促点击声）
- **可访问性**: 纯鼠标操作——无键盘替代。听觉反馈仅为辅助，关键信息（放置成功/失败）通过视觉传达

**When to Use**: 任何将物品放置到棋盘格上的操作
**When NOT to Use**: 需要拖拽合并的操作 → 用 Pattern 2 (Drag-to-Merge)

---

### Pattern 2: Drag-to-Merge

**Category**: Input / Merge
**Used In**: Tower merge upgrade

**Description**: 玩家在 PREP 阶段左键按住一座塔，拖拽到另一座同类型同星级的塔上释放，触发合星升级。这是 Pillar 3（低星不废高星不无敌）的核心交互载体。

**Specification**:
- **触发**: 左键在 TOWER 格上按下 → 移动 > 3px → 进入拖拽状态 → 在另一 TOWER 格上释放
- **输入映射**: `MOUSE_BUTTON_LEFT` + drag state machine (IDLE→PRESSING→DRAGGING→RELEASING)
- **视觉反馈**: 
  - 拖拽开始: 原塔变暗 + 幽灵塔出现在光标位置 (modulate.a = 0.6)
  - 拖拽中: 幽灵塔跟随鼠标 (每帧 `_process` 更新 position)
  - 合星成功: 5 阶段动画 (~0.6-0.8s) → converge → flash → reveal → star-confirm → settle
  - 合星失败: 两塔弹回原位 (~0.3s elastic ease-out)
- **音频反馈**: 合星成功 → 合成音效 (上升音阶); 合星失败 → 拒绝音效 (低沉短音)
- **可访问性**: 右键菜单合星 (Pattern 3) 作为拖拽的替代方案——不需要精确拖拽操作即可完成合星

**When to Use**: 两个同类型同星级塔的合并操作
**When NOT to Use**: 放置新塔 → 用 Pattern 1 (Click-to-Place)

---

### Pattern 3: Right-Click Context

**Category**: Input / Context Menu
**Used In**: Block removal, Tower sell, Merge alternative (右键菜单合星)

**Description**: 右键点击棋盘格触发上下文相关操作。右键 BLOCK = 移除方块。右键 TOWER = 出售塔或（若相邻有可合星目标）弹出合星菜单。右键空地 = 取消当前选择。

**Specification**:
- **触发**: `MOUSE_BUTTON_RIGHT` + `pressed`（不是 released——右键即时响应）
- **输入映射**: 右键在 BLOCK/TOWER/EMPTY 格上按下
- **视觉反馈**: 
  - 移除方块: 方块消失 + 金币飘出动画
  - 出售塔: 塔消失 + 金币飘出
  - 合星菜单: 小型弹出菜单（列出相邻可合星目标）
  - 取消选择: 高亮边框消失
- **音频反馈**: 出售/移除 → 金币音效; 取消 → 轻微点击音
- **可访问性**: 右键菜单合星是 Drag-to-Merge 的无障碍替代方案——纯点击，无需拖拽精度

**When to Use**: 需要上下文相关操作的辅助动作
**When NOT to Use**: 主要正向操作 → 用左键 (Pattern 1 或 2)

---

### Pattern 4: Hover Preview

**Category**: Feedback / Grid
**Used In**: Tower placement preview, Block placement preview

**Description**: 鼠标悬停在棋盘 EMPTY 格上时，显示半透明的放置预览——塔的轮廓或方块的形状。预览颜色指示放置合法性：绿色 = 可放置，红色 = 不可放置（金币不足/路径阻断）。

**Specification**:
- **触发**: 鼠标移动到棋盘格上（每帧 `world_to_grid(get_global_mouse_position())`）
- **视觉反馈**: 半透明精灵 (modulate.a ≈ 0.5) 覆盖在目标格上。绿色 `#4CAF50` = 合法; 红色 `#F44336` = 非法
- **更新频率**: 每帧——随鼠标移动即时刷新
- **可访问性**: 颜色不是唯一指示器——合法放置显示 ✓ 图标，非法显示 ✗ 图标（形状区分）。确保色觉障碍玩家可辨识

**When to Use**: 任何放置操作前的预可视化
**When NOT to Use**: 拖拽合星的幽灵预览 → 用 Pattern 5 (Drag Ghost)

---

### Pattern 5: Drag Ghost

**Category**: Feedback / Merge
**Used In**: Tower drag merge

**Description**: 拖拽合星时，被拖拽的塔在光标位置渲染为半透明版本 (modulate.a = 0.6)。幽灵塔不参与游戏逻辑——纯视觉反馈。

**Specification**:
- **触发**: Drag state machine 进入 DRAGGING 状态
- **视觉反馈**: 塔精灵图半透明 + 跟随 `get_global_mouse_position()`（每帧 `_process` 更新）。原塔在原位变暗 (modulate.a ≈ 0.3)
- **消失条件**: 释放鼠标（合星成功/失败）或 拖拽取消（右键/越界/阶段切换）
- **性能**: 只设 `global_position` + `modulate.a`——无动画无粒子。目标 < 0.1ms/帧
- **可访问性**: 幽灵塔透明度 0.6——在大多数背景下清晰可见

**When to Use**: 拖拽操作中需要显示"正在拖拽什么"的视觉反馈
**When NOT to Use**: 非拖拽的放置预览 → 用 Pattern 4 (Hover Preview)

---

### Pattern 6: Phase-Gated Input

**Category**: State / Input Routing
**Used In**: All grid interactions (placement, removal, merge, selection)

**Description**: 游戏有两个阶段——PREP（筑城）和 BATTLE（战斗观战）。每个阶段有不同的输入许可集。此模式确保玩家在错误阶段的输入被静默忽略，而非执行意外操作。

**Specification**:
- **状态源**: `PhaseManager.current_phase` (ADR-0006)，通过 `SignalBus.phase_changed` 同步
- **PREP 允许**: 放置塔/方块、拖拽合星、右键出售/移除、选择塔、查看信息
- **BATTLE 允许**: 应急技能按钮、右键取消选择、鼠标移动更新光标
- **BATTLE 禁止**: 所有棋盘左键操作——静默忽略（无错误提示）
- **阶段切换期间**: 所有进行中的拖拽强制取消——输入丢弃，不排队
- **可访问性**: 阶段切换时 UI 按钮显隐变化——视觉传达当前可用操作集

**When to Use**: 任何受游戏阶段门控的输入
**When NOT to Use**: 全局 UI 按钮（主菜单、暂停——始终可用）

---

### Pattern 7: Button Click

**Category**: Input / UI
**Used In**: Start Wave button, Skill buttons, Menu buttons, Settlement overlay buttons

**Description**: 标准的 UI 按钮交互——点击触发单一动作。按钮有多个视觉状态：默认、hover、按下、禁用、选中。

**Specification**:
- **触发**: 左键点击 UI 按钮（`Control` 节点优先拦截——不穿透到棋盘）
- **输入映射**: Godot `Button.pressed` 信号（或 `_gui_input` 手动处理）
- **视觉状态**:
  - Default: 标准配色
  - Hover: 轻微亮起 / 边框高亮
  - Pressed: 按下缩放 (~95%)
  - Disabled: 灰色 (modulate = gray, interactable = false)
  - Selected: 金色边框 (Art Bible §7 调色板)
- **技能按钮额外状态**: Cooldown 中（灰色 + 倒计时数字）、Depleted（灰色 + "0"）、Hidden（错误阶段）
- **可访问性**: 按钮最小点击区域 44×44px（桌面端足够）。Hover 和 Focus 状态视觉区分明显

**When to Use**: 所有标准 UI 按钮
**When NOT to Use**: 棋盘格上的点击（非 UI 控件）→ 用 Pattern 1

---

### Pattern 8: Tooltip-on-Hover

**Category**: Feedback / Info
**Used In**: Tower stats display, Monster info, Merge preview

**Description**: 鼠标悬停在游戏实体上超过短暂延迟 (~0.3s) 后，显示包含详细信息的浮层面板。移开鼠标时面板消失。

**Specification**:
- **触发**: 鼠标在塔/怪物上停留 > 0.3s（避免快速扫过时频繁弹出）
- **视觉反馈**: 浮层面板出现在实体旁边（优先右侧，空间不足时左侧或上方）。包含：名称、星级、攻击力、范围、特殊效果
- **合星预览变体**: 拖拽合星时——目标格上显示合星结果预览（下一星级的属性面板）
- **消失**: 鼠标移出实体区域 → 立即隐藏
- **可访问性**: 面板文字 ≥ 12px，与背景对比度 ≥ 4.5:1

**When to Use**: 需要显示实体详细信息但不占用常驻屏幕空间
**When NOT to Use**: 战斗中需要即时可见的关键数据 → 应在 HUD 中常驻显示

---

## Gaps & Patterns Needed

- **Keyboard shortcut pattern**: 当前 MVP 无键盘快捷键，但 V1.0 可能需要（数字键选塔、空格开始波次）。预留此模式。
- **Drag-to-reposition pattern**: 如果未来允许拖拽移动已放置的塔（而非仅合星），需要单独的模式。

## Open Questions

- 合星预览 (Merge Preview) 的浮层内容——显示目标星的属性差异（delta）还是绝对数值？
- 塔 tooltip 是否需要显示"可合星目标"提示（当相邻有同类型同星塔时）？
