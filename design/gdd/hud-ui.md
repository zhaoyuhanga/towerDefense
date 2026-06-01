# HUD/UI 系统 (HUD/UI System)

> **Status**: In Design | **Implements Pillar**: Pillar 4 — 你造你观你调（UI 是"观"的仪表盘）

## Overview

HUD/UI 系统管理所有屏幕上的用户界面元素。它渲染顶部信息栏（波次/金币/防线）、底部操作栏（塔选择/方块/技能/开始按钮）、以及弹窗（结算/合星预览/塔信息浮层）。UI 视觉规范来自美术圣经 Section 7——纯几何图标、尖角矩形、7 色板延伸。

## Detailed Design

### 屏幕布局

```
┌─ 顶部栏 48px ────────────────────────────┐
│ 波次 12  金币 450  防线 ████░░  菜单 ☰   │
├──────────────────────────────────────────┤
│              棋盘区域                     │
├──────────────────────────────────────────┤
│ [炮塔] [冰塔] [箭塔] [方块]   [❄] [🔧]  [开始] │
└─ 底部栏 64px ────────────────────────────┘
```

### HUD 元素（12 个）

| 元素 | 数据来源 | 更新频率 |
|------|---------|---------|
| 波次计数 | WaveSpawner.wave_number | 每波 |
| 金币显示 | Economy.current_gold | 每次交易 |
| 防线状态条 | 准备阶段.lives_remaining | 每次突破 |
| 塔选择按钮 ×3 | 静态 | — |
| 方块按钮 | ObstacleBlock.remaining | 每次放置/移除 |
| 技能按钮 ×2 | EmergencySkill.uses_remaining | 每次使用 |
| 开始按钮 | PrepPhase | 阶段切换 |
| 合星预览弹窗 | MergeUpgrade | 拖拽时 |
| 结算弹窗 | WaveSpawner.wave_ended | 每波结束 |
| 塔信息浮层 | TowerData | 悬停时 |
| 放置预览 | 输入处理 | 鼠标移动时 |

## Dependencies

所有上游系统通过信号/查询提供数据。HUD 只读不写。

## Acceptance Criteria

- **GIVEN** 游戏运行中，**WHEN** 金币变化，**THEN** 顶部栏金币数字即时更新
- **GIVEN** 建造阶段，**WHEN** 点击塔按钮，**THEN** 该按钮显示选中态（金色轮廓）