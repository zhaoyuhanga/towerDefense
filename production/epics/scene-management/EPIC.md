# Epic: Scene Management System (场景管理)

> **Layer**: Foundation | **GDD**: design/gdd/scene-management.md | **Status**: Ready
> **Architecture Module**: SceneManager (Foundation)
> **Stories**: 1 story — Logic — **COMPLETE** (2026-06-02)

## Stories

| # | Story | Type | Status | Files | Tests |
|---|-------|------|--------|-------|-------|
| 001 | Scene Manager | Logic | Complete | scene_manager.gd | 7 tests |

## Overview

管理两个场景（menu.tscn / game.tscn）之间的切换，以及"再来一局"的原地状态重置。场景切换要求在 1 帧内完成。状态重置通过 ADR-0008 的 `game_reset_requested` 信号协调 18 个系统。

## Governing ADRs

| ADR | Decision | Risk |
|-----|----------|------|
| ADR-0006 | PhaseManager 初始化阶段为 PREP | LOW |
| ADR-0008 | 三阶段重置协议 (Destroy→Clear→Initialize) | LOW |

## GDD Requirements (8 TRs)

All covered. TR-scene-002/006 由 ADR-0008 覆盖。TR-scene-001/004 为标准 Godot API 使用。

## Definition of Done

- menu.tscn ↔ game.tscn 切换
- "Play Again" 原地重置（不重新加载场景）
- Settlement overlay 在 game.tscn 内（非独立场景）
- 场景切换 < 1 帧
- 场景销毁时干净拆解（信号断开、timer 停止、节点释放）
- game.tscn 加载时触发完整初始化序列（BoardGrid → Pathfinding → PhaseManager → ...）
