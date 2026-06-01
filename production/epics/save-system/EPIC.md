# Epic: Save System (存档)

> **Layer**: Foundation | **GDD**: design/gdd/save-system.md | **Status**: Ready
> **Architecture Module**: SaveSystem (Foundation)
> **Stories**: 1 story — Logic — **COMPLETE** (2026-06-02)

## Stories

| # | Story | Type | Status | Files | Tests |
|---|-------|------|--------|-------|-------|
| 001 | Save System | Logic | Complete | save_system.gd (368 lines) | 23 tests |

## Overview

使用 Godot ConfigFile (INI) 持久化最高波数和设置（音量、全屏）。MVP 仅存储 high_score + settings——不存 mid-wave 游戏状态。包含 first-run 默认值、损坏文件恢复、即时写入（设置变更时立写不延迟）。

## Governing ADRs

None directly — ConfigFile 是标准 Godot API，架构足够简单，不需要独立 ADR。

## GDD Requirements (8 TRs)

TR-save-001 至 008。全部为标准 ConfigFile 使用模式——无 untraced requirement 需要额外 ADR。

## Definition of Done

- `user://save_data.cfg` 读写
- Game-over 时自动保存最高波数
- 音量/全屏设置即时持久化
- First-run 默认值（high_score=0, volumes=1.0, fullscreen=true）
- 损坏文件检测 + 恢复 + 警告日志
- menu.tscn 显示 high_score
