# Epic: Preparation Phase System (准备阶段)

> **Layer**: Feature | **GDD**: design/gdd/prep-phase.md | **Status**: Ready
> **Architecture Module**: PrepPhase + PhaseManager (Feature)
> **Stories**: 1 story — Logic — **COMPLETE** (2026-06-02)

## Stories
| # | Story | Type | Status | Files | Tests |
|---|-------|------|--------|-------|-------|
| 001 | Phase Manager + Prep Phase | Logic | Complete | prep_phase.gd (224 lines) | 23 tests |

## Overview

实现 PREP↔BATTLE 阶段状态机和准备阶段的流程编排。PhaseManager 持有单一真相来源的 `current_phase`，通过 SignalBus 广播变更。PREP 阶段允许建造操作，BATTLE 阶段只允许应急技能。包含下一波预览数据暴露和阶段切换输入门控。

> **注**: PhaseManager 核心逻辑在 ADR-0006 中已定义。此 Epic 聚焦于准备阶段的流程编排和 HUD 集成。

## Governing ADRs

| ADR | Decision | Risk |
|-----|----------|------|
| ADR-0001 | `phase_changed` 通过 SignalBus | LOW |
| ADR-0006 | PhaseManager 场景节点 + get_tree().paused for PAUSED | LOW |
| ADR-0007 | 阶段门控输入分派 | LOW |

## GDD Requirements (8 TRs)

全部覆盖。

## Definition of Done

- PhaseManager 实现 (PREP↔BATTLE)
- `phase_changed` SignalBus 广播
- 下一波预览数据在 PREP 阶段可查询
- 阶段切换输入丢弃（不排队）
- 游戏初始化默认 PREP
- PAUSED 预留（V1.0）
