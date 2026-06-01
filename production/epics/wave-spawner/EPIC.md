# Epic: Wave Spawner System (波次生成)

> **Layer**: Feature | **GDD**: design/gdd/wave-spawner.md | **Status**: Ready
> **Architecture Module**: WaveSpawner (Feature)
> **Stories**: 1 story — Logic — **COMPLETE** (2026-06-02)

## Stories
| # | Story | Type | Status | Files | Tests |
|---|-------|------|--------|-------|-------|
| 001 | Wave Spawner | Logic | Complete | wave_spawner.gd (492 lines) | 18 tests |

## Overview

实现无限波次生成器：WaveRules 数据驱动、间隔式顺序生成（`spawn_interval` 秒一个）、波次结束检测（全部怪物死亡/越界）、波间自动过渡（~3s 延迟）、按波数缩放属性（`health *= 1 + wave * multiplier`）、26 波后词缀激活。`wave_started` / `wave_ended` 通过 SignalBus 广播。

## Governing ADRs

| ADR | Decision | Risk |
|-----|----------|------|
| ADR-0001 | `wave_started` / `wave_ended` 通过 SignalBus | LOW |
| ADR-0002 | WaveRules.tres + SpawnRule 数据驱动 | LOW |
| ADR-0004 | 通过 MonsterPool.spawn() 实例化怪物 | HIGH |
| ADR-0006 | 波次结束 → PREP，玩家开始 → BATTLE | LOW |

## GDD Requirements (10 TRs)

全部覆盖。

## Definition of Done

- WaveRules 数据驱动的生成调度
- ENTRANCE 位置间隔式顺序生成
- 波次结束检测（全部 killed or breached）
- 波间 ~3s 自动过渡
- 按波数缩放属性（linear→exponential→affix）
- 26 波+ 词缀激活
- 无限循环（无终波）
- 无效 monster_id 跳过+日志
