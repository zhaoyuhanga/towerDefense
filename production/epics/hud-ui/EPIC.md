# Epic: HUD / UI System

> **Layer**: Presentation | **GDD**: design/gdd/hud-ui.md | **Status**: Ready
> **Architecture Module**: HUD (Presentation — read-only)
> **Stories**: 1 story — UI — **COMPLETE** (2026-06-02)

## Stories
| # | Story | Type | Status | Files |
|---|-------|------|--------|-------|
| 001 | HUD | UI | Complete | hud.gd (849 lines) |

## Overview

实现游戏内 HUD——12+ 实时数据绑定组件（波数、金币、HP 条、塔按钮、方块按钮、技能按钮、开始按钮、合星预览、结算弹窗、塔 tooltip、放置预览）。纯信号消费者——只读不写。固定布局：上栏 48px、下栏 64px、中央棋盘区域。纯几何图标渲染（7 色调色板）。

## Governing ADRs

| ADR | Decision | Risk |
|-----|----------|------|
| ADR-0001 | 所有数据通过 SignalBus 信号更新（不轮询） | LOW |
| ADR-0006 | 阶段依赖按钮显隐/可交互性 | LOW |

## GDD Requirements (12 TRs)

TR-hud-003 (read-only) 由 architecture.md 规定。TR-hud-011 (geometric icons) 由 Art Bible 规定。

## Definition of Done

- 12+ HUD 组件实时数据绑定
- 信号驱动的可变更新频率（不帧轮询）
- 按钮选择状态（金色边框）
- 合星预览弹窗
- 塔信息 tooltip（hover > 0.3s）
- 放置预览（半透明 ghost）
- 结算弹窗（wave_ended 时）
- 阶段依赖可见性
- 固定布局 zone（上 48px / 下 64px / 中 board）
- 几何图标渲染
