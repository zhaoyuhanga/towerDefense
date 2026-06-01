# Control Manifest

**Manifest Version**: 2026-06-02
**Generated from**: 8 Accepted ADRs
**Engine**: Godot 4.6

## Foundation Layer Rules

### Required Patterns
- **SignalBus (ADR-0001)**: All cross-system events go through `SignalBus` Autoload. System-local signals stay in class.
- **Data-Driven (ADR-0002)**: All gameplay values in `.tres` Resource files. No hardcoded numeric literals in source.
- **Single Write Gate**: State mutations through one validated entry point (`set_cell_state`, `spend_gold`, `process_attack`).

### Forbidden Patterns
- **Direct `instantiate()`/`queue_free()` on Monsters (ADR-0004)**: Must use `MonsterPool.spawn()`/`despawn()`.
- **`_ready()` for pool-reusable state (ADR-0004)**: Pooled nodes must use `setup()`/`reset()`. `_ready()` only fires once.
- **Deprecated `TileMap` (ADR-0005)**: Use `TileMapLayer` exclusively.
- **Direct `phase_changed` emit (ADR-0006)**: Must go through `PhaseManager._set_phase()`.
- **Bypassing InputHandler priority chain (ADR-0007)**: All mouse input routes through InputHandler.

### Performance Guardrails
- Spawn < 0.5ms, Despawn < 0.1ms (ADR-0004)
- Grid full init < 0.5ms, single `set_cell()` < 0.1ms (ADR-0005)
- Pathfinding full recalc < 1ms (ADR-0003)
- Frame budget: 16.6ms at 60 FPS

## Core Layer Rules

### Required Patterns
- **Timer-driven attack loop (ADR-0002)**: Towers use Timer, not `_process()` polling.
- **Combat intermediary**: Tower → Combat → Monster. Tower never calls `monster.take_damage()` directly.
- **Object pooling (ADR-0004)**: Monster nodes recycled via pool, not created/destroyed per wave.

### Forbidden Patterns
- **Hardcoded star scaling**: All tower stats from TowerData.tres per star level.
- **Direct cross-system state mutation**: Systems own their state. Others read via API or subscribe to signals.

## Feature Layer Rules

### Required Patterns
- **Phase-gated operations (ADR-0006)**: PREP and BATTLE phase checks before any state mutation.
- **Signal-driven wave lifecycle (ADR-0001)**: `wave_started`/`wave_ended` via SignalBus.
- **Data-driven merge (ADR-0002)**: Merge result from TowerData, not computed from source towers.

## Presentation Layer Rules

### Required Patterns
- **Read-only signal consumers**: HUD and VisualFeedback subscribe to signals, never write game state.
- **Programmatic UI**: All Control nodes created in code. No `.tscn` dependencies for UI elements.

## ADR Status

| ADR | Status |
|-----|--------|
| ADR-0001: SignalBus | Accepted |
| ADR-0002: Data Resources | Accepted |
| ADR-0003: AStarGrid2D | Accepted |
| ADR-0004: Monster Pool | Accepted |
| ADR-0005: TileMapLayer | Accepted |
| ADR-0006: Phase State Machine | Accepted |
| ADR-0007: Drag Merge Input | Accepted |
| ADR-0008: State Reset Protocol | Accepted |
