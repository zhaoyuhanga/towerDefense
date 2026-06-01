# Epic: Data Configuration System (数据配置)

> **Layer**: Foundation | **GDD**: design/gdd/data-config.md | **Status**: Ready
> **Architecture Module**: DataConfig (Foundation)
> **Stories**: 3 stories — 1 Config/Data, 1 Logic, 1 Config/Data — **ALL COMPLETE** (2026-06-02)

## Stories

| # | Story | Type | Status | Files |
|---|-------|------|--------|-------|
| 001 | Resource Classes | Config/Data | Complete | 5 .gd Resource class files |
| 002 | Data Loader | Logic | Complete | data_loader.gd + 3 validate functions |
| 003 | Default Config Files | Config/Data | Complete | 13 .tres files (9 towers + 3 monsters + economy) |

## Overview

建立基于 Godot Resource (.tres) 的数据驱动配置管线。定义 6 个 Resource 类（TowerData、MonsterData、WaveRules、EconomyConfig、SkillConfig、GridConfig），每个系统通过 DirAccess 自加载自己的数据目录。包含 fail-safe 加载、数据完整性验证和 fallback 默认值。

## Governing ADRs

| ADR | Decision | Risk |
|-----|----------|------|
| ADR-0002 | .tres Resource 类 + DirAccess 自加载 + fail-safe 验证 | LOW |

## GDD Requirements (9 TRs)

All 9 TR-config-* requirements covered by ADR-0002. No untraced requirements.

## Definition of Done

- 6 个 Resource 类定义（TowerData/MonsterData/WaveRules/EconomyConfig/SkillConfig/GridConfig）
- 每个系统 `_ready()` 中自加载 .tres 文件
- 数据完整性验证在加载时运行
- 缺失/损坏 .tres → 错误日志 + fallback 默认值
- 验证攻击力单调递增、血量 Boss>Elite>Standard、cost≥0
- 重复 key 拒绝 + 警告
- 数据加载在所有 gameplay 查询之前完成
