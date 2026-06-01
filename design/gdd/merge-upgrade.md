# 合星升级系统 (Merge Upgrade System)

> **Status**: In Design | **Implements Pillar**: Pillar 3 — 低星不废高星不无敌

## Overview

合星升级系统管理拖拽合星的核心交互。玩家在建造阶段将一座塔拖拽到另一座同类型同星级的塔上 → 两塔消失 → 高一级的新塔在原位置出现。合星动画序列见美术圣经 Section 5.4（0.6-0.8s）。合星是提升塔攻击力（和特殊效果）的唯一手段——不是花钱升级而是"合并两座塔"。

## Detailed Design

### Core Rules

1. **合星条件**：两塔的 `tower_id` 相同 且 `star_level` 相同 且 `star_level < 3`（3 星是最高——不可再合）。
2. **合星结果**：生成 `tower_id` 相同、`star_level + 1` 的新塔，放在**被拖拽目标塔的位置**。
3. **属性来源**：新塔的属性从对应的 TowerData 文件加载（不是两塔属性的简单相加——每星级有独立的数值设计）。
4. **合星成本**：如 EconomyConfig.merge_cost > 0 → 消耗金币。默认 0（免费合星）。
5. **失败回弹**：拖拽到非同类型/不同星/已是 3 星 → 两塔弹回原位（~0.3s 弹性缓出）。
6. **建造阶段独占**：战斗阶段不能拖拽合星。

### Interactions

| 接口 | 签名 | 调用者 |
|------|------|--------|
| 执行合星 | `try_merge(from_col, from_row, to_col, to_row) -> bool` | 输入处理 |
| 合星成功信号 | `merge_completed(from_star, to_star, position)` | 视觉反馈 |
| 合星失败信号 | `merge_failed(reason)` | 视觉反馈 |

## Dependencies

| 上游 | 关系 | 下游 | 关系 |
|------|------|------|------|
| 防御塔 | Hard — 获取/移除/创建塔 | 视觉反馈 | Hard — 合星动画事件 |
| 经济系统 | Hard — merge_cost 扣费 | | |
| 棋盘网格 | Hard — 更新格状态 | | |
| 数据配置 | Hard — 新星级 TowerData | | |

## Edge Cases

- 拖拽 1 星塔到 3 星塔 → 失败——星级必须相同
- 合星后新塔位置已有其他塔 → 不可能——目标塔在原位被消耗，位置恰好空出
- 金币不够合星费 → 失败，弹回

## Acceptance Criteria

- **GIVEN** 两个 1 星炮塔相邻，**WHEN** 拖拽一座到另一座上，**THEN** 两塔消失，一座 2 星炮塔出现在目标位置
- **GIVEN** 1 星炮塔拖到 1 星冰塔，**WHEN** 拖拽完成，**THEN** 两塔弹回原位（失败）
- **GIVEN** 3 星炮塔拖到 3 星炮塔，**WHEN** 拖拽完成，**THEN** 弹回（3 星最高）

## Tuning Knobs

| Knob | 默认 | 说明 |
|------|------|------|
| `MERGE_COST` | 0 | 合星是否收费 |