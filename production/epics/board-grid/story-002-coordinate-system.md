# Story 002: Coordinate System

> **Epic**: Board Grid System
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: 2 hours
> **Last Updated**: 2026-06-02

## Context

**GDD**: `design/gdd/board-grid.md`
**Requirements**: TR-grid-006, TR-grid-007, TR-grid-009, TR-grid-013

**ADR Governing Implementation**: ADR-0002: Data Resource System
**ADR Decision Summary**: All tunable values live in .tres Custom Resource files. GridConfig.tres defines CELL_SIZE, GRID_COLS, GRID_ROWS, GRID_ORIGIN_X, GRID_ORIGIN_Y. No hardcoded constants in source.

**Engine**: Godot 4.6 | **Risk**: LOW

---

## Acceptance Criteria

- [ ] **AC-1**: GIVEN mouse position on screen, WHEN `world_to_grid(mouse_pos)`, THEN returns correct `Vector2i(col, row)`
- [ ] **AC-2**: GIVEN grid coord (10, 7), WHEN `grid_to_world(10, 7)`, THEN returns pixel center of that cell: `Vector2(ORIGIN_X + 10*56 + 28, ORIGIN_Y + 7*56 + 28)`
- [ ] **AC-3**: GIVEN (10, 7) in center of board, WHEN `get_neighbors(10, 7)`, THEN returns exactly 4 coords: `[(9,7), (11,7), (10,6), (10,8)]`
- [ ] **AC-4**: GIVEN (0, 0) at corner, WHEN `get_neighbors(0, 0)`, THEN returns 2 coords: `[(1,0), (0,1)]` (out-of-bounds filtered)
- [ ] **AC-5**: GIVEN window resize event, WHEN resize occurs, THEN GRID_ORIGIN_X/Y recalculated to keep board centered
- [ ] **AC-6**: GridConfig.tres exists and is loaded at `_ready()` — CELL_SIZE, GRID_COLS, GRID_ROWS read from config, not hardcoded

## Implementation Notes

- Formulas from GDD §D.1–D.4:
  - `CELL_SIZE = GridConfig.cell_size` (default 56)
  - `grid_to_world(col, row)` = `Vector2(ORIGIN_X + col * CELL_SIZE + CELL_SIZE/2, ORIGIN_Y + row * CELL_SIZE + CELL_SIZE/2)`
  - `world_to_grid(screen_pos)` = `Vector2i(floori((screen_pos.x - ORIGIN_X) / CELL_SIZE), floori((screen_pos.y - ORIGIN_Y) / CELL_SIZE))`
  - `get_neighbors()` = 4-directional offsets filtered by `is_valid_position()`
- `world_to_grid()` does NOT clamp — caller must validate with `is_valid_position()`
- GRID_ORIGIN_X = `(window_width - GRID_COLS * CELL_SIZE) / 2`; GRID_ORIGIN_Y = 64 (top bar)
- GridConfig.tres must be loaded before these functions are called
- Use `@export var grid_config: GridConfig` for editor assignment; fallback to `load("res://resources/grid_config.tres")`

## Out of Scope

- Story 001: CellState, set_cell_state() — already implemented
- Story 003: SignalBus — handled separately

## QA Test Cases

- **AC-1**: Screen → Grid conversion
  - Given: GRID_ORIGIN = (400, 64), CELL_SIZE = 56
  - When: `world_to_grid(Vector2(400 + 5*56 + 28, 64 + 3*56 + 28))`  (center of cell 5,3)
  - Then: returns `Vector2i(5, 3)`
  - Edge cases: screen_pos outside board → returns out-of-bounds Vector2i (no clamp)

- **AC-3**: Neighbors — center cell
  - Given: 20×15 grid
  - When: `get_neighbors(10, 7)`
  - Then: returns `[(9,7), (11,7), (10,6), (10,8)]` (order-independent)

- **AC-4**: Neighbors — corner cell
  - Given: 20×15 grid
  - When: `get_neighbors(0, 0)`
  - Then: returns `[(1,0), (0,1)]` (only in-bounds neighbors)

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/board-grid/coordinate_test.gd` — must exist and pass

**Status**: [ ] Not yet created

## Dependencies

- Depends on: Story 001 (Core Data Layer) — `is_valid_position()` must exist
- Unlocks: Story 003 (Signal Integration)

## Completion Notes
**Completed**: 2026-06-02
**Criteria**: 6/6 passing
**Deviations**: world_to_grid uses (-1,-1) sentinel (vs GDD "no clamp" — functionally equivalent, safer); origin_y aligned to 64px GDD D.1 (was centered — fixed)
**Test Evidence**: `tests/unit/board-grid/coordinate_test.gd` — 17 test functions
**Code Review**: APPROVED — cell_size 56 fix + origin_y 64px fix applied
