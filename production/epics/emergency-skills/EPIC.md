# Epic: Emergency Skills System (应急技能)

> **Layer**: Feature | **GDD**: design/gdd/emergency-skills.md | **Status**: Ready
> **Architecture Module**: EmergencySkills (Feature)
> **Stories**: 1 story — Logic — **COMPLETE** (2026-06-02)

## Stories
| # | Story | Type | Status | Files | Tests |
|---|-------|------|--------|-------|-------|
| 001 | Emergency Skills | Logic | Complete | emergency_skills.gd (366 lines) | 28 tests |

## Overview

实现两种应急技能：Freeze（冻结全部怪物 `speed=0`）+ Repair（恢复防御线 HP）。每技能有独立使用次数上限和冷却计时器。每波次开始时补充使用次数。技能按钮具有四态 UI（可用/冷却中/已耗尽/隐藏）。BATTLE 阶段独占。

## Governing ADRs

| ADR | Decision | Risk |
|-----|----------|------|
| ADR-0001 | `skill_activated` 通过 SignalBus | LOW |
| ADR-0002 | SkillConfig.tres 数据驱动 | LOW |
| ADR-0006 | BATTLE 阶段门控 | LOW |

## GDD Requirements (11 TRs)

全部覆盖。

## Definition of Done

- Freeze 技能——全部怪物 `speed=0`，可配置 duration
- Repair 技能——防御线 HP +effect_amount，clamp 到 max
- 使用次数计数器 + 每波补充
- 冷却计时器
- BATTLE 阶段独占
- 即时生效（同帧）
- 四态 UI 按钮
