# GridRenderer — TileMapLayer visual grid renderer (ADR-0005)
# Renders the 20x15 board grid. Subscribes to SignalBus for
# per-cell incremental updates and phase-driven opacity changes.
# All public methods have doc comments per coding-standards.
class_name GridRenderer
extends TileMapLayer

## Local phase tracking — mirrors PhaseManager.Phase but avoids
## cross-layer dependency (ADR-0006). PREP=0, BATTLE=1.
enum Phase { PREP = 0, BATTLE = 1 }

## Tile appearance configuration (colors, cell size, phase opacities)
@export var tileset_config: GridTileset

## Flat 1D array of CellState int values — mirrors BoardGrid._grid layout.
## Index: row * cols + col. Updated via SignalBus.cell_state_changed.
var board_data: Array = []

## Grid column count — set by initialize() from board data dimensions.
var cols: int = 20

## Grid row count — set by initialize() from board data dimensions.
var rows: int = 15

## Immutable ENTRANCE cell position (restored on game reset).
var _entrance_pos: Vector2i = Vector2i(-1, -1)

## Immutable EXIT cell position (restored on game reset).
var _exit_pos: Vector2i = Vector2i(-1, -1)

## Current phase — local cache updated via SignalBus.phase_changed (ADR-0006).
var _phase: Phase = Phase.PREP

## Cell size in pixels. Set before add_child() to override the default 56.
var cell_size: int = 56

## Runtime-generated TileSet with procedural atlas texture.
var _runtime_tileset: TileSet = null

## Runtime-generated ImageTexture for the tile atlas (5 tiles x cell_size wide).
var _atlas_texture: ImageTexture = null


func _ready() -> void:
	# Physics are disabled by default on TileMapLayer (no collision properties).
	# Grid collision is handled by BoardGrid data layer per ADR-0005.

	# Use nearest-neighbor filtering to prevent tile-border bleed at seams.
	texture_filter = TEXTURE_FILTER_NEAREST

	# Load config defaults if tileset_config is set.
	if tileset_config != null:
		pass  # Config consumed in _build_runtime_tileset()

	# Build procedural TileSet from GridTileset config.
	_build_runtime_tileset()
	# Origin is set explicitly by bootstrap — see game_bootstrap.gd

	# Position TileMapLayer at the calculated grid origin.
	position = _origin

	# Set initial phase opacity.
	_apply_phase_opacity()

	# Subscribe to cross-system signals with has_node guard (ADR-0001).
	if has_node("/root/SignalBus"):
		SignalBus.cell_state_changed.connect(_on_cell_state_changed)
		SignalBus.phase_changed.connect(_on_phase_changed)
		SignalBus.game_reset_requested.connect(_on_game_reset)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Initialize the grid renderer with full board data.
## board_data is a flat Array[int] matching BoardGrid._grid layout.
## Scans for ENTRANCE/EXIT positions and performs full 300-cell set_cell().
func initialize(p_board_data: Array) -> void:
	board_data = p_board_data.duplicate()
	_scan_immutable_cells()
	for row in range(rows):
		for col in range(cols):
			var idx: int = row * cols + col
			var state: int = board_data[idx] if idx < board_data.size() else 0
			_paint_cell(col, row, state)


## Return the current grid origin in world-pixel coordinates.
## Recalculated on window resize to keep grid centered.
func get_origin() -> Vector2:
	return _origin


## Override the grid origin. Called by bootstrap to sync with BoardGrid.
func set_origin(new_origin: Vector2) -> void:
	_origin = new_origin


# ---------------------------------------------------------------------------
# SignalBus handlers
# ---------------------------------------------------------------------------

## Handle single-cell state change from SignalBus.
## Updates only the affected tile — incremental, not full redraw (AC-5).
func _on_cell_state_changed(col: int, row: int, _old: int, new: int) -> void:
	if col < 0 or col >= cols or row < 0 or row >= rows:
		return
	var idx: int = row * cols + col
	if idx < board_data.size():
		board_data[idx] = new
	_paint_cell(col, row, new)


## Handle phase transition from SignalBus.
## Adjusts modulate.a to PREP (0.8) or BATTLE (0.6) per ADR-0005.
func _on_phase_changed(_old: int, new: int) -> void:
	_phase = new as Phase
	_apply_phase_opacity()


## Handle game reset from SignalBus.
## Full re-initialize: clears all cells, restores ENTRANCE and EXIT.
func _on_game_reset() -> void:
	# Clear all tiles to EMPTY.
	for row in range(rows):
		for col in range(cols):
			_paint_cell(col, row, 0)  # 0 = CellState.EMPTY

	# Reset board_data to all EMPTY.
	board_data.clear()
	board_data.resize(cols * rows)
	for i in range(board_data.size()):
		board_data[i] = 0

	# Restore immutable ENTRANCE and EXIT cells.
	if _entrance_pos.x >= 0:
		var idx: int = _entrance_pos.y * cols + _entrance_pos.x
		board_data[idx] = 3  # CellState.ENTRANCE
		_paint_cell(_entrance_pos.x, _entrance_pos.y, 3)
	if _exit_pos.x >= 0:
		var idx: int = _exit_pos.y * cols + _exit_pos.x
		board_data[idx] = 4  # CellState.EXIT
		_paint_cell(_exit_pos.x, _exit_pos.y, 4)


# ---------------------------------------------------------------------------
# Internal — TileSet generation
# ---------------------------------------------------------------------------

## Build a procedural TileSet from GridTileset config.
## Generates a 5-tile atlas texture at runtime so no external image files are needed.
## The atlas is laid out horizontally: tile [0..4] at x = state * cell_size.
func _build_runtime_tileset() -> void:
	var cs: int = cell_size
	var lc: Color = tileset_config.grid_line_color if tileset_config != null else Color("8899AA")
	var lw: int = tileset_config.grid_line_width if tileset_config != null else 2
	var fills: PackedColorArray = tileset_config.cell_fills if tileset_config != null else _default_fills()

	var atlas_width: int = cs * 5
	var atlas_height: int = cs

	# Create atlas image.
	var image: Image = Image.create(atlas_width, atlas_height, false, Image.FORMAT_RGBA8)

	for i in range(5):
		var x0: int = i * cs
		var fill: Color = fills[i] if i < fills.size() else Color("263040")

		# Fill cell background.
		image.fill_rect(Rect2i(x0, 0, cs, cs), fill)

		# Draw 1px border on all four sides — adjacent tile borders merge into grid lines.
		image.fill_rect(Rect2i(x0, 0, cs, lw), lc)             # top
		image.fill_rect(Rect2i(x0, cs - lw, cs, lw), lc)       # bottom
		image.fill_rect(Rect2i(x0, 0, lw, cs), lc)             # left
		image.fill_rect(Rect2i(x0 + cs - lw, 0, lw, cs), lc)   # right

	# Create texture from image.
	_atlas_texture = ImageTexture.create_from_image(image)

	# Create TileSetAtlasSource with the generated texture.
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = _atlas_texture
	source.texture_region_size = Vector2i(cs, cs)

	# Define 5 tiles at atlas coordinates (0,0) through (4,0).
	for i in range(5):
		source.create_tile(Vector2i(i, 0))

	# Create TileSet and add the source.
	_runtime_tileset = TileSet.new()
	_runtime_tileset.add_source(source, 0)

	# Assign to TileMapLayer.
	tile_set = _runtime_tileset


# ---------------------------------------------------------------------------
# Internal — helpers
# ---------------------------------------------------------------------------

## Paint a single cell at grid coordinates with the given CellState int value.
## Maps state to atlas_coords via (state, 0) — single atlas source convention.
func _paint_cell(col: int, row: int, state: int) -> void:
	set_cell(Vector2i(col, row), 0, Vector2i(state, 0))


## Scan board_data for ENTRANCE (3) and EXIT (4) positions.
## Stores them so _on_game_reset() can restore immutable cells.
func _scan_immutable_cells() -> void:
	_entrance_pos = Vector2i(-1, -1)
	_exit_pos = Vector2i(-1, -1)
	for row in range(rows):
		for col in range(cols):
			var idx: int = row * cols + col
			if idx >= board_data.size():
				continue
			var state: int = board_data[idx]
			if state == 3:  # CellState.ENTRANCE
				_entrance_pos = Vector2i(col, row)
			elif state == 4:  # CellState.EXIT
				_exit_pos = Vector2i(col, row)


## Recalculate grid origin — centers horizontally, 64px top margin (GDD D.1).
func _recalculate_origin() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var cs: int = cell_size
	var grid_pixel_width: float = float(cols * cs)
	_origin = Vector2(
		(viewport_size.x - grid_pixel_width) / 2.0,
		64.0
	)


## Apply phase-dependent opacity via modulate.a (ADR-0005).
func _apply_phase_opacity() -> void:
	if tileset_config != null:
		modulate.a = tileset_config.prep_opacity if _phase == Phase.PREP else tileset_config.battle_opacity
	else:
		modulate.a = 0.8 if _phase == Phase.PREP else 0.6


## Default fallback cell fills when no GridTileset is assigned.
func _default_fills() -> PackedColorArray:
	return PackedColorArray([
		Color("1a2330"),  # EMPTY — dark board background
		Color("4A6A80"),  # BLOCK — visible blue-gray
		Color("6A8AAA"),  # TOWER — lighter blue
		Color("2D8A2D"),  # ENTRANCE — green
		Color("AA3A3A"),  # EXIT — red
	])


# ---------------------------------------------------------------------------
# Grid origin (read-only from outside)
# ---------------------------------------------------------------------------
var _origin: Vector2 = Vector2.ZERO
