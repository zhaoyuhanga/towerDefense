# Epic: Input Handling System (输入处理)

> **Layer**: Foundation | **GDD**: design/gdd/input-handling.md | **Status**: Ready
> **Architecture Module**: InputHandler (Foundation → Core/Feature routing)
> **Stories**: 1 story — Logic — **COMPLETE** (2026-06-02)

## Stories

| # | Story | Type | Status | Files | Tests |
|---|-------|------|--------|-------|-------|
| 001 | Input Handler | Logic | Complete | input_handler.gd (358 lines) | 43 tests (20 drag + 23 phase) |

## Overview

实现所有鼠标输入的翻译和路由层。包含 4 态拖拽状态机（IDLE→PRESSING→DRAGGING→RELEASING）、阶段门控输入分派（PREP vs BATTLE）、优先级链（UI>Tower>Block>Empty>Void）、拖拽检测阈值 3px。InputHandler 不渲染任何预览——只调用目标系统的方法。

## Governing ADRs

| ADR | Decision | Risk |
|-----|----------|------|
| ADR-0001 | 输入不直接 emit SignalBus——通过目标系统间接通信 | LOW |
| ADR-0006 | PhaseManager 阶段门控——BATTLE 阶段屏蔽建造输入 | LOW |
| ADR-0007 | 混合路由架构——InputHandler 集中路由 + 拖拽状态机 | LOW |

## GDD Requirements (8 TRs)

All 8 TR-input-* requirements covered by ADR-0007. No untraced requirements.

## Definition of Done

- 4 态拖拽状态机实现
- 优先级链路由（UI>Tower>Block>Empty>Void）
- PREP/BATTLE 阶段门控分派表
- 拖拽中右键/越界/阶段切换 → 强制取消
- 阶段切换动画期间的输入丢弃
- 为键盘快捷键预留扩展点（MVP 鼠标独占）
