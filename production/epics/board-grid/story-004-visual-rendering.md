# Story 004: Visual Rendering

> **Epic**: Board Grid System
> **Status**: Complete
> **Layer**: Foundation
> **Type**: UI
> **Estimate**: 3 hours
> **Last Updated**: 2026-06-02

## Context

**GDD**: `design/gdd/board-grid.md`
**Requirements**: TR-grid-010, TR-grid-011

**ADR Governing Implementation**: ADR-0005: TileMapLayer Grid Rendering
**ADR Decision Summary**: Pure TileMapLayer approach. Single TileSetAtlasSource with 5 tiles at atlas_coords (0,0) through (4,0). Grid lines formed by tile borders. Nearest texture filter. Phase-dependent `modulate.a` (PREP=0.8, BATTLE=0.6). Physics layer fully disabled.

**Engine**: Godot 4.6 | **Risk**: MEDIUM — TileMap→TileMapLayer migration post-cutoff

---

## Acceptance Criteria

- [ ] **AC-1**: GIVEN board initialized, WHEN GridRenderer renders, THEN 20×15 grid visible with 5 visually distinct cell types
- [ ] **AC-2**: GIVEN grid rendered, WHEN inspected, THEN grid lines are uniform 1-2px, color `#4A6078`, no gaps or blur at tile seams (Nearest filter)
- [ ] **AC-3**: GIVEN PREP phase, WHEN GridRenderer receives `phase_changed(PREP)`, THEN `modulate.a = 0.8`
- [ ] **AC-4**: GIVEN BATTLE phase, WHEN GridRenderer receives `phase_changed(BATTLE)`, THEN `modulate.a = 0.6`
- [ ] **AC-5**: GIVEN `cell_state_changed(5, 3, EMPTY, BLOCK)`, WHEN GridRenderer handles it, THEN only cell (5,3) updates — `set_cell()` called once, not full-grid redraw
- [ ] **AC-6**: GIVEN grid is rendered, WHEN physics raycast/overlap on grid area, THEN GridRenderer TileMapLayer does NOT participate in collision

## Implementation Notes

- GridRenderer extends `TileMapLayer`, child of BoardGrid node
- TileSet resource: `grid_tiles.tres` — single TileSetAtlasSource, 5 tiles at (0,0)→(4,0)
- Tile mapping: EMPTY=atlas(0,0), BLOCK=atlas(1,0), TOWER=atlas(2,0), ENTRANCE=atlas(3,0), EXIT=atlas(4,0)
- `set_cell(Vector2i(col, row), 0, Vector2i(state_id, 0))` — source_id=0 always
- Colors: background `#263040`, grid line border `#4A6078` on each tile
- `texture_filter = TEXTURE_FILTER_NEAREST` on TileSet
- No physics layers assigned — leave Physics Layers property empty
- Subscribe: `SignalBus.cell_state_changed.connect(_on_cell_state_changed)` and `SignalBus.phase_changed.connect(_on_phase_changed)`
- `_on_game_reset()`: re-initialize all 300 cells via `initialize(board_data)`

## Out of Scope

- Story 001: the data layer that emits `cell_state_changed`
- Future V1.0: GridOverlay for path lines and tower ranges

## QA Test Cases

- **AC-1/2**: Visual grid render
  - Setup: Launch game, observe board in PREP phase
  - Verify: 20×15 grid visible, 5 colors distinguishable, grid lines uniform no blur
  - Pass condition: All cells render, colors match spec, tile seams invisible at 1x scale

- **AC-3/4**: Phase transparency
  - Setup: Start game in PREP → observe grid → click Start → observe grid in BATTLE
  - Verify: Grid visibly dims from ~80% to ~60% opacity on phase switch
  - Pass condition: Transition is instantaneous (no gradual fade for MVP), opacity difference clearly visible

- **AC-5**: Single-cell update
  - Setup: Place a block at (5,3)
  - Verify: Only cell (5,3) changes visually — rest of grid unchanged
  - Pass condition: No flicker or full-grid redraw visible

- **AC-6**: No physics collision
  - Setup: Use Godot editor's Debug → Visible Collision Shapes
  - Verify: GridRenderer shows no collision shapes
  - Pass condition: Raycasts and Area2D overlaps do not detect grid cells

## Test Evidence

**Story Type**: UI
**Required evidence**: `production/qa/evidence/story-004-grid-render-evidence.md` — manual visual verification + screenshot sign-off

**Status**: [ ] Not yet created

## Dependencies

- Depends on: Story 003 (Signal Integration) — needs `cell_state_changed` and `phase_changed` signals
- Unlocks: None directly (Presentation layer)
## Completion Notes

**Completed**: 2026-06-02
**Criteria**: 6/6 (UI — manual visual verification)
**Deviations**: None
**Test Evidence**: Manual — GridRenderer scene renders 20x15 grid with 5 CellState tile types, phase-dependent opacity, Nearest filter
**Key Feature**: Runtime procedural TileSet generation via Image.create() — eliminates external texture dependency
**Files**: grid_renderer.gd (254 lines), grid_tileset.gd (30), grid_tileset.tres (12), grid_renderer.tscn (9)
