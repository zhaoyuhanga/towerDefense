# 音频系统 (Audio System)

> **Status**: In Design — V1.0 | **Implements Pillar**: 全部——音频是氛围和反馈的最后一块

## Overview

音频系统管理所有游戏音效和背景音乐。MVP 阶段仅需最基础的声音——如果没有音频资源，游戏仍然完全可玩（静默模式）。V1.0 才正式投入音频制作。本 GDD 定义了"音频事件"清单——待 V1.0 时按此清单制作音效。

## Detailed Design

### 音频事件清单

| 事件 | 类型 | 优先级 | 触发信号 |
|------|------|--------|---------|
| 塔射击 | SFX | 高 | 防御塔攻击 |
| 怪物死亡 | SFX | 高 | `monster_died` |
| 合星成功 | SFX | 高 | `merge_completed` |
| 合星失败 | SFX | 中 | `merge_failed` |
| 方块放置 | SFX | 中 | 方块 `place_block` |
| 方块移除 | SFX | 中 | 方块 `remove_block` |
| UI 按钮点击 | SFX | 低 | UI 交互 |
| 波次开始 | SFX | 中 | `wave_started` |
| 波次胜利 | SFX | 中 | `wave_ended` |
| 防线突破 | SFX | 高 | `monster_breached` |
| 技能激活 | SFX | 中 | `skill_activated` |
| 背景音乐 | Music | 低 | 游戏运行中循环 |

### V1.0 范围

- 音效文件（.ogg 格式）放置在 `assets/audio/sfx/` 和 `assets/audio/music/`
- 使用 Godot AudioStreamPlayer 节点
- 音量控制由存档系统的 settings 管理

## Dependencies

音频系统是一个纯信号消费者——订阅所有系统的事件信号，不写入数据。MVP 阶段此系统可完全不存在——静默模式降级。

## Acceptance Criteria (V1.0)

- **GIVEN** 塔攻击怪物，**WHEN** 攻击事件触发，**THEN** 射击音效播放
- **GIVEN** settings.sfx_volume=0，**WHEN** 任何音效应播放，**THEN** 静默