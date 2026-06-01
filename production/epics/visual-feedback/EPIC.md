# Epic: Visual Feedback System (视觉反馈)

> **Layer**: Presentation | **GDD**: design/gdd/visual-feedback.md | **Status**: Ready
> **Architecture Module**: VisualFeedback (Presentation — read-only)
> **Stories**: 1 story — Visual/Feel — **COMPLETE** (2026-06-02)

## Stories
| # | Story | Type | Status | Files |
|---|-------|------|--------|-------|
| 001 | Visual Feedback | Visual/Feel | Complete | visual_feedback.gd (468 lines) |

## Overview

实现只读视觉反馈层——订阅 7+ 游戏信号，渲染粒子效果、动画、浮动伤害数字。绝不写入游戏状态。包含：怪物死亡粒子、路径伤痕 overlay、5 阶段合星动画、合星失败弹回、波次过渡效果、危机红闪（HP<30%）、方块放置渐入、浮动伤害数字（颜色编码）。

## Governing ADRs

| ADR | Decision | Risk |
|-----|----------|------|
| ADR-0001 | 纯信号消费者——订阅 7+ 信号，写零游戏状态 | LOW |
| ADR-0005 | 路径线 overlay 坐标基于 BoardGrid 网格 | MEDIUM |

## GDD Requirements (11 TRs)

TR-vfx-004 合星动画协调涉及 MergeSystem↔VFX 时序——architecture.md 通过信号解耦。

## Definition of Done

- 怪物死亡粒子效果
- 路径伤痕 overlay (monster_breached)
- 5 阶段合星动画 (~0.6-0.8s)
- 合星失败弹回 + 红色 X
- 波次过渡效果
- 危机红闪 (HP < 30%)
- 方块放置渐入 (0→100% over 0.15s)
- 路径线重绘 (path_updated/path_blocked)
- 浮动伤害数字（颜色编码，同时多个不裁剪）
- 信号订阅生命周期管理
