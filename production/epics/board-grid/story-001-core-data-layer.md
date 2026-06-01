# Story 001: Core Data Layer

> **Epic**: Board Grid System
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: 3 hours
> **Last Updated**: 2026-06-02

## Context

**GDD**: `design/gdd/board-grid.md`
**Requirements**: TR-grid-001, TR-grid-002, TR-grid-003, TR-grid-004, TR-grid-008, TR-grid-012

**ADR Governing Implementation**: N/A — Pure data structure + state machine. No architectural pattern required. The CellState enum, transition table, and single-write-gate pattern are defined directly in the GDD.

**Engine**: Godot 4.6 | **Risk**: LOW

---

## Acceptance Criteria

- [ ] **AC-1**: GIVEN new game, WHEN board init, THEN 20×15 grid all EMPTY except specified ENTRANCE/EXIT positions
- [ ] **AC-2**: GIVEN (5,3) is EMPTY, WHEN `set_cell_state(5, 3, BLOCK)`, THEN returns true, cell state = BLOCK
- [ ] **AC-3**: GIVEN (5,3) is BLOCK, WHEN `set_cell_state(5, 3, EMPTY)`, THEN returns true, cell state = EMPTY
- [ ] **AC-4**: GIVEN (0,0) is ENTRANCE, WHEN `set_cell_state(0, 0, BLOCK)`, THEN returns false, state unchanged
- [ ] **AC-5**: GIVEN any coordinate outside 0..19, 0..14, WHEN `is_valid_position(col, row)`, THEN returns false
- [ ] **AC-6**: GIVEN (10,7) in bounds, WHEN `is_valid_position(10, 7)`, THEN returns true
- [ ] **AC-7**: TOWER same-position merge executes atomically: TOWER→EMPTY→TOWER within single frame — no subscriber observes intermediate EMPTY

## Implementation Notes

- `CellState` enum: `EMPTY=0, BLOCK=1, TOWER=2, ENTRANCE=3, EXIT=4`
- `_grid: Array[CellState]` — flattened 1D array, index = `row * 20 + col`
- `_set_cell_state()` validates against a legal-transition table (Dictionary keyed by `(from, to)` → bool)
- ENTRANCE/EXIT appear in no transition's `from` field → immutability enforced by table
- For AC-7 (atomic merge): caller passes a callback or the merge is done by setting the cell directly (TOWER→EMPTY then EMPTY→TOWER in same `set_cell_state` call sequence before signal emit)

## Out of Scope

- Story 002: coordinate conversion, GridConfig — handled separately
- Story 003: SignalBus emission — handled separately
- Story 004: TileMapLayer visual rendering — handled separately

## QA Test Cases

- **AC-1**: Board initialization
  - Given: `BoardGrid.init(20, 15, entrance_pos, exit_pos)`
  - When: init completes
  - Then: `get_cell_state(every_cell)` returns EMPTY for all except ENTRANCE/EXIT at specified positions
  - Edge cases: ENTRANCE and EXIT at same position → init should reject

- **AC-2**: Valid state transition
  - Given: cell (5,3) is EMPTY
  - When: `set_cell_state(5, 3, BLOCK)`
  - Then: returns `true`, `get_cell_state(5, 3) == BLOCK`
  - Edge cases: same cell set twice → second call returns false (idempotent)

- **AC-4**: Immutable cell guard
  - Given: cell (0,0) is ENTRANCE
  - When: `set_cell_state(0, 0, BLOCK)` and `set_cell_state(0, 0, TOWER)` and `set_cell_state(0, 0, EMPTY)`
  - Then: all return `false`, state unchanged as ENTRANCE
  - Edge cases: EXIT same behavior

- **AC-5/6**: Bounds checking
  - Given: grid is 20×15
  - When: `is_valid_position(-1, 0)`, `is_valid_position(0, -1)`, `is_valid_position(20, 0)`, `is_valid_position(0, 15)`
  - Then: all return `false`
  - When: `is_valid_position(0, 0)`, `is_valid_position(19, 14)`
  - Then: both return `true`

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/board-grid/core_data_test.gd` — must exist and pass

**Status**: [ ] Not yet created

## Dependencies

- Depends on: None
- Unlocks: Story 002 (Coordinate System), Story 003 (Signal Integration)

## Completion Notes
**Completed**: 2026-06-02
**Criteria**: 7/7 passing
**Deviations**: None
**Test Evidence**: `tests/unit/board-grid/core_data_test.gd` — 6 test functions covering all 7 ACs
**Code Review**: APPROVED WITH SUGGESTIONS — 5 fixes applied (test setup assertions, _on_game_reset guard, CONNECT_ONE_SHOT)
**Files**: `src/foundation/board_grid.gd` (124 lines), `src/resources/grid_config.gd` (7 lines), `tests/unit/board-grid/core_data_test.gd` (71 lines)
