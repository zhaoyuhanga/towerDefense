# QA Plan: Sprint 2 — MVP 收官
**Date**: 2026-06-02
**Scope**: 8 Must Have tasks across 4 areas
**Engine**: Godot 4.6

## Test Summary

| ID | Task | Type | Test |
|----|------|------|------|
| 2-1 | HUD 恢复 | UI | Manual — 验证波数/金币/HP 实时更新 |
| 2-2 | 视觉特效 | Visual/Feel | Manual — 截图+目视确认 |
| 2-3 | 合星动画 | Visual/Feel | Manual — 拖拽合星观察动画 |
| 2-4 | 自测脚本 | Logic | F1 一键运行 5 项 assert |
| 2-5 | 代码审查 | Logic | `/code-review` 核心文件 |
| 2-6 | 数值平衡 | Config/Data | 手动跑前3波验证难度 |
| 2-7 | 场景管理 | Integration | 菜单↔游戏切换+Play Again |
| 2-8 | 存档联调 | Integration | high_score 读写验证 |

## Automated Tests Required

### 2-4: 自测脚本
- **Test file**: 内嵌于 `game_bootstrap.gd`（F1 触发）
- **覆盖**: 方块放置→路径变化→塔放置→波次生成→塔攻击
- **断言**: 每步 assert 成功/失败计数
- **Edge cases**: 重复放置拒绝、金币不足拒绝、空波次规则

### 2-7: 场景管理
- **Test file**: `tests/integration/scene-management/scene_switch_test.gd`
- **覆盖**: menu→game 切换、game→menu 返回、Play Again 重置所有系统
- **断言**: 切换后 BoardGrid 状态干净、Economy 重置、WaveSpawner 重置

### 2-8: 存档联调
- **Test file**: `tests/integration/save-system/save_integration_test.gd`
- **覆盖**: high_score 写入→游戏结束→菜单读取→显示正确
- **断言**: score 正确持久化、Corrupted file 恢复、默认值 fallback

## Manual QA Checklist

### 2-1: HUD 恢复
- [ ] 波数显示随 wave_started 更新
- [ ] 金币显示随 gold_changed 更新（放方块扣费、杀怪入账）
- [ ] HP 条在 monster_breached 时减少
- [ ] 塔按钮在 PREP 可见、BATTLE 隐藏
- [ ] 技能按钮在 BATTLE 可见、PREP 隐藏
- [ ] 点击棋盘区域不被 HUD 拦截

### 2-2: 视觉特效
- [ ] 怪物死亡时显示粒子效果
- [ ] 塔攻击命中时显示浮动伤害数字
- [ ] 伤害数字颜色区分伤害类型

### 2-3: 合星动画
- [ ] 拖拽同类型同星塔→播放合星动画
- [ ] 合星成功后新塔出现在目标位置
- [ ] 合星失败塔弹回原位

### 2-6: 数值平衡
- [ ] 第 1 波：3 只 Standard goblin，1-2 座塔可全灭
- [ ] 第 2 波：怪物数量或血量增加
- [ ] 第 3 波：引入 Elite，需要 3-4 座塔
- [ ] 方块价格合理（25g/个）

## Smoke Test Scope

1. 游戏启动→棋盘显示→默认 PREP 阶段
2. 放方块→路径绕行→右键移除→路径恢复
3. 按 1/2/3 选塔→点击放塔→拖拽合星
4. 按 Space→波次开始→怪物沿路径移动→塔自动攻击
5. 波次结束→自动回 PREP→可进行下一波
6. Play Again→所有状态重置→可重新开始

## Definition of Done — This Sprint

- [ ] 所有 8 项 Must Have 完成
- [ ] F1 自测全部通过
- [ ] Smoke check 全部通过
- [ ] 无 S1/S2 级 bug
