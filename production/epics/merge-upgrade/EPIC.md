# Epic: Merge Upgrade System (合星升级)

> **Layer**: Feature | **GDD**: design/gdd/merge-upgrade.md | **Status**: Ready
> **Architecture Module**: MergeSystem (Feature)
> **Stories**: 1 story — Logic — **COMPLETE** (2026-06-02)

## Stories
| # | Story | Type | Status | Files | Tests |
|---|-------|------|--------|-------|-------|
| 001 | Merge System | Logic | Complete | merge_system.gd (425 lines) | 777 lines of tests |

## Overview

实现拖拽合星的核心交互：InputHandler 路由拖拽事件 → MergeSystem 验证合星资格（同 tower_id + 同 star_level + star<3）→ 原子合星操作（销毁两源塔→创建新高星塔在目标位置）→ 数据驱动星级属性 → 合星失败弹回动画。双操作模式：拖拽（主）+ 右键菜单（辅——桌面端无障碍）。

## Governing ADRs

| ADR | Decision | Risk |
|-----|----------|------|
| ADR-0001 | `merge_completed` / `merge_failed` 通过 SignalBus | LOW |
| ADR-0002 | 合星结果属性从 TowerData 读取（非计算） | LOW |
| ADR-0006 | PREP 阶段门控 | LOW |
| ADR-0007 | 拖拽状态机 + 双模式（拖拽/右键菜单） | LOW |

## GDD Requirements (12 TRs)

全部覆盖。

## Definition of Done

- 拖拽合星 + 右键菜单合星双模式
- 合星资格验证（同 tower_id + 同 star_level + star<3）
- 原子合星操作（destroy×2 → create×1）
- 新塔属性从 TowerData.tres 读取
- EconomyConfig.merge_cost 扣费
- 合星失败 → 弹回动画（~0.3s elastic）
- 5 阶段合星成功动画（~0.6-0.8s）协调
- PREP 阶段独占
