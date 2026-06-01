# HUD Design

> **Status**: Implemented
> **Source**: `src/presentation/hud.gd` (849 lines)
> **Last Updated**: 2026-06-02

## HUD Philosophy

**Minimal but present** — only critical decision-relevant data always visible. The HUD serves the player's need to understand game state at a glance (wave, gold, defense HP) and access build actions during PREP phase. Information density adapts to phase: build tools visible in PREP, combat tools visible in BATTLE.

## Layout Zones

```
┌─────────────────────────────────────────────────────┐
│  TOP BAR (48px)                                      │
│  [Wave: 5]  [Gold: 350]  [HP ████████░░ 80%]  [Menu]│
├─────────────────────────────────────────────────────┤
│                                                       │
│                    BOARD AREA                          │
│                  (20 × 15 grid)                        │
│                                                       │
├─────────────────────────────────────────────────────┤
│  BOTTOM BAR (64px)                                    │
│  [Cannon] [Ice] [Arrow]  [Block×10]  [Freeze] [Repair]│
│  [◀── Tower Selection ──▶]            [Start Wave ▶] │
└─────────────────────────────────────────────────────┘
```

## HUD Elements

| Element | Zone | Category | Data Source |
|---------|------|----------|-------------|
| Wave counter | Top Bar | Must Show | SignalBus.wave_started |
| Gold display | Top Bar | Must Show | SignalBus.gold_changed |
| Defense HP bar | Top Bar | Must Show | Manual update (defense system) |
| Menu button | Top Bar | Contextual | SceneManager.go_to_menu() |
| Tower buttons (×3) | Bottom Bar | Must Show (PREP) | TowerData config |
| Block button | Bottom Bar | Must Show (PREP) | SignalBus.block_count_changed |
| Skill buttons (×2) | Bottom Bar | Must Show (BATTLE) | EmergencySkills state |
| Start Wave button | Bottom Bar | Must Show (PREP) | PhaseManager |
| Settlement overlay | Center | On Demand | SignalBus.wave_ended |

## Phase-Dependent Visibility

| Element | PREP | BATTLE |
|---------|------|--------|
| Tower buttons | ✅ Visible | ❌ Hidden |
| Block button | ✅ Visible | ❌ Hidden |
| Start Wave button | ✅ Visible | ❌ Hidden |
| Skill buttons | ❌ Hidden | ✅ Visible |

## Dynamic Behaviors

- **Defense HP bar**: Green (>60%), Yellow (30-60%), Red (<30% crisis)
- **Gold display**: Gold-colored text, pulses on change
- **Skill cooldowns**: Greyed out + countdown timer display during cooldown
- **Tower selection**: Gold border on selected tower button (radio-style)

## Accessibility

- Core HUD text: 18px minimum
- Button labels: 14px minimum
- Minimum button size: 56×44px (exceeds 44×44px standard)
- Color-independent: defense HP bar uses shape (fill level) + text percentage, not color alone
- Silent-mode compatible: all critical information conveyed visually
