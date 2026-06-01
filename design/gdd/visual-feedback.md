# 视觉反馈系统 (Visual Feedback System)

> **Status**: In Design | **Implements Pillar**: 全部——所有支柱的视觉落地

## Overview

视觉反馈系统是所有非 UI 视觉效果的统一管理者。它接收其他系统的事件（怪物死亡、合星完成、波次切换、路径更新、危机触发），按照美术圣经定义的视觉规范播放对应的动画和粒子效果。纯逻辑系统通过信号发射事件——视觉反馈系统是信号的"观众"。

## Detailed Design

### 反馈事件表

| 事件 | 视觉反馈 | 美术圣经参考 |
|------|---------|------------|
| 怪物死亡 | 有机碎片飞散 + 暖色微光 | Section 5.5.1 |
| 防线突破 | 路径红色伤疤 + UI 边框红闪 | Section 5.5.2 |
| 合星成功 | 5 阶段动画（聚合→闪光→显形→星级确认→就位） | Section 5.4 |
| 合星失败 | 两塔弹回原位 + 光标红色 X | Section 5.4 |
| 波次开始 | 波次数字跳动 + UI 边框变色过渡 | Section 4.3 |
| 波次胜利 | 路线确认光 + 暗角聚拢 | Section 2.4a |
| 危机（<30% 防线）| UI 边框脉动红闪 | Section 4.3 |
| 方块放置 | 方块淡入 0.15s | Section 8 |
| 路径更新 | 路径线重绘 | 原则 1 |
| 伤害数字 | 白色/金色/青色弹出 | Section 5 |

### 系统架构

视觉反馈系统是一个**纯信号消费者**——它订阅所有其他系统的信号，不向任何系统写入数据。

## Dependencies

| 上游（订阅的信号） | 来源系统 |
|----------|---------|
| `monster_died`, `monster_breached` | 怪物系统 |
| `damage_dealt` | 战斗/伤害 |
| `merge_completed`, `merge_failed` | 合星升级 |
| `wave_started`, `wave_ended` | 波次生成 |
| `cell_state_changed` | 棋盘网格 |
| `skill_activated` | 应急技能 |
| `path_blocked`, `path_updated` | 怪物寻路 |

## Acceptance Criteria

- **GIVEN** 怪物死亡，**WHEN** `monster_died` 信号发射，**THEN** 有机碎片粒子效果在怪物位置播放