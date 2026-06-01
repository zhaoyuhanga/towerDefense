# Systems Index: [待命名]

> **Status**: Draft
> **Created**: 2026-06-01
> **Last Updated**: 2026-06-01
> **Source Concept**: design/gdd/game-concept.md

---

## Overview

本游戏是一款迷宫建造型塔防游戏（Mazing TD），玩家用障碍方块设计怪物行进路线，用拖拽合星培养防御塔，在无限波次中验证布局智慧。系统架构围绕四个游戏支柱展开：路线即武器、每波是考卷、低星不废高星不无敌、造→观→调。

18 个系统分五层：Foundation（棋盘+数据+输入）→ Core（寻路+方块+塔+怪+战斗+经济）→ Feature（波次+合星+准备+技能）→ Presentation（HUD+视觉）→ Polish（存档+音频+场景）。MVP 需要 17 个系统（15 完整 + 2 基础版），V1.0 补齐音频和完整 UI/视觉。

---

## Systems Enumeration

| # | System | Category | Priority | Status | Design Doc | Depends On |
|---|--------|----------|----------|--------|------------|------------|
| 1 | 棋盘网格系统 | Foundation | MVP | Designed | design/gdd/board-grid.md | — |
| 2 | 数据配置系统 | Foundation | MVP | Designed | design/gdd/data-config.md | — |
| 3 | 输入处理系统 | Foundation | MVP | Designed | design/gdd/input-handling.md | — |
| 4 | 怪物寻路系统 | Core | MVP | Approved | design/gdd/pathfinding.md | 1 |
| 5 | 障碍方块系统 | Core | MVP | Designed | design/gdd/obstacle-block.md | 1, 4 |
| 6 | 怪物系统 | Core | MVP | Designed | design/gdd/monster-system.md | 1, 4, 2 |
| 7 | 防御塔系统 | Core | MVP | Approved | design/gdd/tower-system.md | 1, 2, 6 |
| 8 | 战斗/伤害系统 | Core | MVP | Designed | design/gdd/combat-damage.md | 7, 6, 2 |
| 9 | 经济系统 | Core | MVP | Designed | design/gdd/economy.md | 8, 2 |
| 10 | 波次生成系统 | Feature | MVP | Designed | design/gdd/wave-spawner.md | 6, 2 |
| 11 | 合星升级系统 | Feature | MVP | Designed | design/gdd/merge-upgrade.md | 7, 9, 3 |
| 12 | 准备阶段系统 | Feature | MVP | Designed | design/gdd/prep-phase.md | 3, 5, 7, 11, 9 |
| 13 | 应急技能系统 | Feature | MVP | Designed | design/gdd/emergency-skills.md | 6, 8 |
| 14 | HUD/UI 系统 | Presentation | MVP (基础) | Designed | design/gdd/hud-ui.md | 9, 10, 13, 12, 11, 7 |
| 15 | 视觉反馈系统 | Presentation | MVP (基础) | Designed | design/gdd/visual-feedback.md | 8, 11, 6, 10 |
| 16 | 存档系统 | Polish | MVP (基础) | Designed | design/gdd/save-system.md | 10, 2 |
| 17 | 音频系统 | Polish | V1.0 | Designed | design/gdd/audio.md | 8, 11, 10 |
| 18 | 场景管理系统 | Polish | MVP | Designed | design/gdd/scene-management.md | 1, 16 |

---

## Categories

| Category | Description | Systems |
|----------|-------------|---------|
| **Foundation** | 所有系统的技术底座——零业务依赖，必须最先设计 | 棋盘网格、数据配置、输入处理 |
| **Core** | 核心玩法逻辑——游戏的"物理法则" | 怪物寻路、障碍方块、怪物、防御塔、战斗/伤害、经济 |
| **Feature** | 建立在 Core 之上的复合系统——规则组合和流程编排 | 波次生成、合星升级、准备阶段、应急技能 |
| **Presentation** | 玩家看到和听到的一切——依赖所有下层系统 | HUD/UI、视觉反馈 |
| **Polish** | 横切关注点——不影响核心循环但影响产品质量 | 存档、音频、场景管理 |

---

## Dependency Map

```
Layer 1 — Foundation (零依赖)
  ① 棋盘网格
  ② 数据配置
  ③ 输入处理

Layer 2 — Core (依赖 Foundation)
  ④ 怪物寻路          ← ①
  ⑤ 障碍方块          ← ① ④
  ⑥ 怪物系统          ← ① ④ ②
  ⑦ 防御塔系统        ← ① ② ⑥
  ⑧ 战斗/伤害         ← ⑦ ⑥ ②
  ⑨ 经济系统          ← ⑧ ②

Layer 3 — Feature (依赖 Core)
  ⑩ 波次生成          ← ⑥ ②
  ⑪ 合星升级          ← ⑦ ⑨ ③
  ⑫ 准备阶段          ← ③ ⑤ ⑦ ⑪ ⑨
  ⑬ 应急技能          ← ⑥ ⑧

Layer 4 — Presentation
  ⑭ HUD/UI           ← ⑨ ⑩ ⑬ ⑫ ⑪ ⑦
  ⑮ 视觉反馈          ← ⑧ ⑪ ⑥ ⑩

Layer 5 — Polish
  ⑯ 存档              ← ⑩ ②
  ⑰ 音频              ← ⑧ ⑪ ⑩
  ⑱ 场景管理          ← ① ⑯
```

## Bottleneck Systems

| System | Dependents | Risk | Mitigation |
|--------|-----------|------|------------|
| **棋盘网格** | 5 (寻路、方块、怪物、塔、场景) | 🔴 高 | API 先定义接口契约再实现——`get_cell()`, `set_cell()`, `is_walkable()` 等核心方法不变 |
| **数据配置** | 5 (怪物、塔、战斗、经济、波次) | 🔴 高 | 使用 `.tres` 资源文件——Godot 原生序列化，字段可随时扩展 |
| **怪物系统** | 5 (塔、战斗、波次、视觉、技能) | 🟡 中 | 怪物基类定义 `health`, `speed`, `take_damage()`, `get_position()` ——接口先锁 |

无循环依赖。

---

## Recommended Design Order

按照"依赖排序 + MVP 优先"原则：

| 顺序 | System | 为什么这个顺序 |
|------|--------|---------------|
| **1** | 棋盘网格系统 | 一切的空间载体。没棋盘什么都放不了——所有坐标、寻路、放置都基于它。先定 API |
| **2** | 数据配置系统 | 塔属性/怪物属性/波次规则的数据结构——所有数值的源头。和棋盘并行做 |
| **3** | 怪物寻路系统 | Mazing 的技术核心——AStarGrid2D 集成。方块系统依赖它 |
| **4** | 怪物系统 | 塔需要目标、波次需要产出物。先有"敌人是什么"才能设计"怎么打敌人" |
| **5** | 防御塔系统 | 玩家的主要火力输出。塔的攻击范围/目标选择/升级路线 |
| **6** | 战斗/伤害系统 | 塔打怪→伤害计算→怪物死亡。核心反馈链的数学 |
| **7** | 经济系统 | 杀怪得金币→花金币买塔/方块。策略的资源约束 |
| **8** | 障碍方块系统 | Pillar 1 的载体。依赖寻路+棋盘——放在 Core 最后因为它需要前面所有系统稳定 |
| **9** | 输入处理系统 | 鼠标→命令的翻译层。放在 Foundation 设计但在塔/方块/合星都定好后再写——知道要处理什么输入 |
| **10** | 波次生成系统 | 无限波次的生成规则。怪物系统+数据配置就绪后自然产出 |
| **11** | 合星升级系统 | Pillar 3 的载体。拖拽合成——塔+经济+输入就位后实现 |
| **12** | 准备阶段系统 | 筑城时间的流程编排。把方块/塔/合星/经济串成"一回合" |
| **13** | 应急技能系统 | Pillar 4 的"微调"。怪物+战斗就绪后加入 |
| **14** | HUD/UI 系统 | 所有下层系统的显示层——波次/金币/技能/合星/塔信息 |
| **15** | 视觉反馈系统 | 合星动画/死亡碎片/路径残影——美术圣经落地 |
| **16** | 场景管理系统 | 菜单↔游戏↔结算的切换 |
| **17** | 存档系统 | 最高波数+设置保存 |
| **18** | 音频系统 | V1.0——所有音效和背景音乐 |

---

## MVP Boundary

**MVP 包含**: Systems 1-16（15 个完整 + HUD/UI 和视觉反馈的基础版 + 存档仅最高波数）
**MVP 不包含**: 音频系统（#17）、HUD/UI 完整版（结算面板/塔浮层/菜单样式）、视觉反馈完整版（危机红闪/虚空压缩/胜利确认光）

**MVP 核心假设**: 17 个系统实现后，玩家能完成"开局→筑城→战斗→合星→结算→再来一局"的完整循环。MVP 验证的是"核心循环是否好玩"。

---

## Progress Tracker

| System | Status | GDD | Implemented |
|--------|--------|-----|-------------|
| ① 棋盘网格 | Not Started | — | — |
| ② 数据配置 | Not Started | — | — |
| ③ 输入处理 | Not Started | — | — |
| ④ 怪物寻路 | Not Started | — | — |
| ⑤ 障碍方块 | Not Started | — | — |
| ⑥ 怪物系统 | Not Started | — | — |
| ⑦ 防御塔系统 | Not Started | — | — |
| ⑧ 战斗/伤害 | Not Started | — | — |
| ⑨ 经济系统 | Not Started | — | — |
| ⑩ 波次生成 | Not Started | — | — |
| ⑪ 合星升级 | Not Started | — | — |
| ⑫ 准备阶段 | Not Started | — | — |
| ⑬ 应急技能 | Not Started | — | — |
| ⑭ HUD/UI | Not Started | — | — |
| ⑮ 视觉反馈 | Not Started | — | — |
| ⑯ 存档 | Not Started | — | — |
| ⑰ 音频 | Not Started (V1.0) | — | — |
| ⑱ 场景管理 | Not Started | — | — |

---

## High-Risk Systems

| System | Risk | Reason | Mitigation |
|--------|------|--------|------------|
| 怪物寻路 | 🔴 技术 | AStarGrid2D 在 4.6 的行为变更——solid point 返回空路径。每帧数十个怪物寻路性能 | 先做 20×20 寻路性能原型；缓存路径段增量更新 |
| 合星升级 | 🟡 交互 | 桌面端拖拽手感——鼠标拖拽合星没有触屏自然 | 双操作模式：拖拽 + 右键菜单。原型测试 5 人 |
| 波次生成 | 🟡 设计 | 难度曲线——太陡挫败、太缓无聊。无限=没有终点 | 分阶段递增：线性→指数→词缀。每 25 波引入新变量 |
| 棋盘网格 | 🟡 架构 | 18 个系统的空间载体——API 一旦定了就很难改 | 先定义接口契约，后实现 |

---

> **Director Notes**: CD-SYSTEMS 和 TD-SYSTEM-BOUNDARY 在 Lean 模式下跳过。PR-SCOPE 跳过。
> 全部 18 个系统枚举、依赖映射和设计顺序已经过用户确认。
