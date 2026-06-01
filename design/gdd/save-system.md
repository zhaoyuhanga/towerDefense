# 存档系统 (Save System)

> **Status**: In Design | **Implements Pillar**: 间接——存档是玩家跨会话进度的记忆

## Overview

存档系统管理跨游戏会话的持久数据。MVP 范围极简：仅保存最高波数记录和用户设置（音量/分辨率）。没有"保存游戏进度"——每局是独立的，防线崩溃后游戏结束，不存在"读档继续"。

## Detailed Design

### Core Rules

1. **自动保存**：每局结束后自动更新最高波数记录（如果本局波数 > 历史最高）。
2. **设置保存**：音量、分辨率设置在修改时保存。
3. **存储位置**：`user://save_data.cfg`（Godot 用户目录——Windows: `%APPDATA%/Godot/app_userdata/`）。
4. **格式**：Godot ConfigFile（INI 风格——简单可靠）。

### 数据结构

```ini
[progress]
high_score=0

[settings]
master_volume=1.0
sfx_volume=1.0
music_volume=0.8
fullscreen=true
```

## Dependencies

| 上游 | 关系 | 下游 | 关系 |
|------|------|------|------|
| 波次生成 | Hard — 读取/写入 high_score | HUD/UI | Hard — 显示最高波数 |

## Edge Cases

- 首次运行无存档 → 所有值使用默认值
- 存档文件损坏 → 删除损坏文件，使用默认值，打印警告
- 同时多实例写入 → Godot ConfigFile 非原子——最后写入胜出

## Acceptance Criteria

- **GIVEN** 首次运行，**WHEN** 游戏启动，**THEN** high_score=0
- **GIVEN** 本局达到波次 25（> 历史最高 20），**WHEN** 游戏结束，**THEN** high_score=25 写入存档