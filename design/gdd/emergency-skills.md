# 应急技能系统 (Emergency Skill System)

> **Status**: In Design | **Implements Pillar**: Pillar 4 — 你造你观你调（"调"的有限干预）

## Overview

应急技能系统管理战斗阶段的有限干预能力。两种技能：冰冻（冻结所有怪物 2 秒）和维修（恢复防线生命值）。每种技能每局有使用次数上限，次数在准备阶段通过特定方式积累（如每波+1 次）。技能是 Pillar 4 "你调"的体现——不是推翻你的布局，而是在紧急时刻给你一次修正机会。

## Detailed Design

### Core Rules

1. **冰冻技能**：点击 → 所有活跃怪物被施加 `freeze` 效果——`speed = 0`，持续 `duration` 秒。冷却 `cooldown` 秒。
2. **维修技能**：点击 → 防线生命值恢复 `effect_amount` 点。
3. **次数限制**：每局 `max_uses` 次（从 SkillConfig 读取）。次数用完后按钮变灰。
4. **战斗阶段独占**：技能按钮仅在战斗阶段可用。准备阶段不显示/不可用。
5. **即时生效**：点击后立即生效——无施法动画延迟。

### Interactions

| 接口 | 签名 | 调用者 |
|------|------|--------|
| 激活技能 | `activate_skill(skill_id: String) -> bool` | 输入处理 |
| 技能激活信号 | `skill_activated(skill_id)` | 视觉反馈 |

## Dependencies

| 上游 | 关系 | 下游 | 关系 |
|------|------|------|------|
| 怪物系统 | Hard — `apply_effect()` | 视觉反馈 | Hard — 技能 VFX |
| 数据配置 | Hard — SkillConfig | HUD/UI | Hard — 按钮状态 |
| 准备阶段 | Hard — 次数补充 | | |

## Acceptance Criteria

- **GIVEN** 冰冻技能可用+怪物正在移动，**WHEN** 技能激活，**THEN** 所有怪物停止移动 2 秒
- **GIVEN** 冰冻次数=0，**WHEN** 按钮点击，**THEN** 无响应（按钮灰色）

## Tuning Knobs

所有参数在 SkillConfig 中。关键交互：冰冻 duration 太长=无聊（变相时间停止），太短=无用。