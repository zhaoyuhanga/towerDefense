# 波次生成系统 (Wave Spawner System)

> **Status**: In Design | **Implements Pillar**: Pillar 2 — 每一波都是考卷

## Overview

波次生成系统负责无限波次模式的怪物生成调度。它从 WaveRules 数据中读取每波应生成什么怪物、多少只、什么间隔，按时间节奏从入口逐个生成怪物。难度随波次递增——从线性增长到引入词缀到极端数值——确保"每一波都是考卷"永不过期。

## Detailed Design

### Core Rules

1. **波次定义**：每波由 WaveRules.SpawnRule 数组定义。每条规则指定：适用波次范围、怪物池、数量、生成间隔、可选词缀池。
2. **生成节奏**：怪物从 ENTRANCE 逐个生成（非同时），间隔 = `spawn_interval` 秒。
3. **波次推进**：当前波所有怪物被击杀或突破后 → 短暂停顿（~3 秒）→ 自动进入下一波的准备阶段。
4. **难度递增**：波 1-10 线性增长（`health *= 1 + wave * 0.1`）；波 11-25 加速增长（`health *= 1 + wave * 0.2`）；波 26+ 词缀激活 + 数值继续增长。
5. **无限循环**：没有最后一波——游戏持续到玩家防线被突破。波次计数器持续递增。

### Interactions

| 接口 | 签名 |
|------|------|
| 开始波次 | `start_wave(wave_number: int)` |
| 波次结束信号 | `wave_ended(wave_number, enemies_killed, enemies_breached)` |
| 波次开始信号 | `wave_started(wave_number)` |

## Dependencies

| 上游 | 关系 | 下游 | 关系 |
|------|------|------|------|
| 怪物系统 | Hard — `spawn_monster()` | 准备阶段 | Hard — 波次门控 |
| 数据配置 | Hard — WaveRules | HUD/UI | Hard — 波次计数 |
| | | 视觉反馈 | Hard — 波次转换效果 |

## Edge Cases

- 所有怪物在生成前被击杀 → 等待生成间隔结束 → 波次正常结束
- SpawnRule 引用不存在的怪物 ID → 跳过该 ID（数据配置 GDD 已定义此行为）

## Acceptance Criteria

- **GIVEN** 波次 1 开始，**WHEN** WaveRules 规定 5 只 basic 怪间隔 1s 生成，**THEN** 恰好生成 5 只，每只间隔 1s
- **GIVEN** 波次内所有怪物被击杀，**WHEN** 最后一只死亡，**THEN** `wave_ended` 信号在 3s 后发射

## Tuning Knobs

所有参数在 WaveRules 中——系统本身无额外 Knob。