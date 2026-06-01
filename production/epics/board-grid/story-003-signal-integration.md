# Story 003: Signal Integration

> **Epic**: Board Grid System
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Integration
> **Estimate**: 1.5 hours
> **Last Updated**: 2026-06-02

## Context

**GDD**: `design/gdd/board-grid.md`
**Requirement**: TR-grid-005

**ADR Governing Implementation**: ADR-0001: SignalBus Autoload
**ADR Decision Summary**: All cross-system events go through SignalBus. `cell_state_changed(col, row, old_state, new_state)` is emitted on every successful state transition. Downstream systems (Pathfinding, VisualFeedback) subscribe to this single signal.

**Engine**: Godot 4.6 | **Risk**: LOW

---

## Acceptance Criteria

- [ ] **AC-1**: GIVEN a successful `set_cell_state(5, 3, BLOCK)`, WHEN transition completes, THEN `SignalBus.cell_state_changed.emit(5, 3, EMPTY, BLOCK)` is called exactly once
- [ ] **AC-2**: GIVEN a failed `set_cell_state(0, 0, BLOCK)` (ENTRANCE immutable), WHEN transition rejected, THEN NO signal emitted
- [ ] **AC-3**: GIVEN `game_reset_requested` emitted, WHEN BoardGrid receives it, THEN all cells → EMPTY, ENTRANCE/EXIT restored, `cell_state_changed` emitted for each changed cell
- [ ] **AC-4**: GIVEN a downstream system (Pathfinding) connected to `cell_state_changed`, WHEN signal emitted, THEN downstream receives correct (col, row, old, new) values

## Implementation Notes

- Connect in `_ready()`: `SignalBus.cell_state_changed` is emitted, not connected — BoardGrid is the emitter
- `_on_game_reset()` per ADR-0008: Phase 2 (CLEAR) — all cells → EMPTY, restore ENTRANCE/EXIT positions
- Signal only fires on SUCCESSFUL transitions — guard inside `set_cell_state()` before return
- Signal parameter types match SignalBus declaration: `int` for old_state/new_state (CellState enum cast to int per ADR-0006 pattern)

## Out of Scope

- Story 001: `set_cell_state()` logic itself
- Story 004: visual rendering that responds to `cell_state_changed`

## QA Test Cases

- **AC-1**: Signal on valid transition
  - Given: cell (5,3) is EMPTY
  - When: `set_cell_state(5, 3, BLOCK)`
  - Then: `SignalBus.cell_state_changed` emitted with args `(5, 3, 0, 1)` (EMPTY=0, BLOCK=1)
  - Edge cases: rapid sequential calls → each successful transition emits exactly one signal

- **AC-2**: No signal on invalid transition
  - Given: cell (0,0) is ENTRANCE
  - When: `set_cell_state(0, 0, BLOCK)` returns false
  - Then: `SignalBus.cell_state_changed` not emitted

- **AC-3**: Game reset
  - Given: board has BLOCK at (5,3), TOWER at (8,8)
  - When: `SignalBus.game_reset_requested.emit()`
  - Then: all cells EMPTY, ENTRANCE/EXIT at original positions
  - And: `cell_state_changed` emitted for (5,3) and (8,8) and ENTRANCE/EXIT restoration

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/board-grid/signal_test.gd` — test that SignalBus receives correct emissions from BoardGrid

**Status**: [ ] Not yet created

## Dependencies

- Depends on: Story 001 (Core Data Layer)
- Unlocks: Story 004 (Visual Rendering — GridRenderer subscribes to `cell_state_changed`)

## Completion Notes
**Completed**: 2026-06-02
**Criteria**: 6/6 passing
**Deviations**: None
**Test Evidence**: `tests/integration/board-grid/signal_test.gd` — 8 integration tests
