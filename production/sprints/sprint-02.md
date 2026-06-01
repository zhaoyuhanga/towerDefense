# Sprint 2 — 2026-06-03 to 2026-06-10

## Sprint Goal
完成游戏的可发布 MVP：HUD 恢复、视觉特效补充、QA 测试、场景管理联调、数值平衡。

## Capacity
- Total days: 6
- Buffer (20%): 1 day
- Available: 5 days (solo dev)

## Tasks

### Must Have (Critical Path)
| ID | Task | Est. Days | Deps | Acceptance |
|----|------|-----------|------|-----------|
| 2-1 | HUD 恢复——波数/金币/HP 实时显示 + mouse_filter 修复 | 0.5 | — | 按 Space 开始波次后 HUD 同步更新 |
| 2-2 | 视觉特效——怪物死亡粒子、伤害浮动数字 | 1.0 | 2-1 | 怪物被塔击杀时显示粒子+数字 |
| 2-3 | 合星动画——5 阶段 merge 视觉 | 0.5 | — | 拖拽合星成功时播放动画序列 |
| 2-4 | 自测脚本——全系统集成测试 | 0.5 | — | F1 一键跑通 5 项测试 |
| 2-5 | 代码审查——核心路径文件 | 0.5 | — | 无阻塞性 bug、命名规范合规 |
| 2-6 | 数值平衡——塔攻击/怪物血量/波次曲线初调 | 0.5 | — | 前 3 波可通关，难度递增合理 |
| 2-7 | 场景管理——menu.tscn + Play Again | 0.5 | — | 主菜单↔游戏场景切换正常 |
| 2-8 | 存档联调——high_score 持久化验证 | 0.5 | 2-7 | 最高波数在菜单显示 |

### Should Have
| ID | Task | Est. Days | Deps | Acceptance |
|----|------|-----------|------|-----------|
| 2-9 | 音效 stub 验证——AudioManager 信号通路 | 0.25 | — | 所有信号触发 push_warning 正常 |
| 2-10 | 无障碍验收——色盲模拟+静音通关 | 0.25 | — | accessibility-requirements.md checklist |

### Nice to Have
| ID | Task | Est. Days | Deps | Acceptance |
|----|------|-----------|------|-----------|
| 2-11 | Mono 游戏图标替换 | 0.1 | — | 非默认 Godot 图标 |
| 2-12 | 难度曲线文档 | 0.5 | 2-6 | design/difficulty-curve.md |

## Risks
| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| HUD CanvasLayer 拦截点击 | Medium | Low | 已知修复方案——上下面板 MOUSE_FILTER_IGNORE |
| TowerSystem 信号签名不匹配 | Low | Medium | 已修过一次.bind(tower)，类似问题 grep 检查 |
| 合星动画与 MergeSystem 时序冲突 | Low | Medium | 先做简单版（缩放弹入），避免复杂时序 |

## Definition of Done for this Sprint
- [ ] All Must Have tasks completed
- [ ] F1 自测全部通过
- [ ] Smoke check 通过
- [ ] 所有 Logic 系统有对应测试文件
