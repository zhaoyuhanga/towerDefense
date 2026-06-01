class_name BoardGrid
extends Node
## BoardGrid — 20×15 grid data layer. Foundation layer, zero upstream deps.
## Single write gate set_cell_state() with transition validation.
## Local signal cell_state_changed — Story 003 bridges to SignalBus.

enum CellState { EMPTY = 0, BLOCK = 1, TOWER = 2, ENTRANCE = 3, EXIT = 4 }

## Grid dimensions (from GridConfig or init())
var cols: int = 20
var rows: int = 15

## GridConfig resource controlling visual layout (cell_size, screen margins)
@export var grid_config: GridConfig = null

## Pixel size of each grid cell (from GridConfig or default 56 per GDD D.1)
var cell_size: int = 56

## Top-left pixel origin of the grid (calculated to center on screen)
var origin: Vector2 = Vector2.ZERO

## Flattened 1D grid: index = row * cols + col
var _grid: Array[CellState] = []

## Immutable cell positions
var _entrance_pos: Vector2i = Vector2i(-1, -1)
var _exit_pos: Vector2i = Vector2i(-1, -1)

## Emitted on every successful state transition.
## Parameters use int to match SignalBus convention (ADR-0001).
signal cell_state_changed(col: int, row: int, old_state: int, new_state: int)

# Transition table: packed key (from << 4 | to) → valid
# Only true entries stored; missing key = illegal transition
var _transition_table: Dictionary = {}

func _ready() -> void:
	_build_transition_table()
	# Load cell_size from exported GridConfig resource (fallback to default 56 per GDD D.1)
	if grid_config != null:
		cell_size = grid_config.cell_size
	# Origin is set explicitly by bootstrap._ready() — see game_bootstrap.gd
	# Subscribe to window resize for responsive grid centering
	get_tree().root.size_changed.connect(_on_window_resize)
	# Subscribe to game reset (ADR-0008)
	if has_node("/root/SignalBus"):
		self.cell_state_changed.connect(_on_cell_state_changed)
		SignalBus.game_reset_requested.connect(_on_game_reset, CONNECT_ONE_SHOT)


func _build_transition_table() -> void:
	var valid_pairs := [
		[CellState.EMPTY, CellState.BLOCK],
		[CellState.EMPTY, CellState.TOWER],
		[CellState.BLOCK, CellState.EMPTY],
		[CellState.TOWER, CellState.EMPTY],
		[CellState.TOWER, CellState.TOWER],  # merge upgrade
	]
	for pair in valid_pairs:
		var key: int = (pair[0] as int) << 4 | (pair[1] as int)
		_transition_table[key] = true


## Initialize the grid with dimensions and ENTRANCE/EXIT positions.
## Returns false if entrance and exit are at the same position (rejected).
func init(p_cols: int, p_rows: int, entrance_pos: Vector2i, exit_pos: Vector2i) -> bool:
	if entrance_pos == exit_pos:
		push_error("BoardGrid.init: entrance and exit must be different positions")
		return false

	cols = p_cols
	rows = p_rows
	_entrance_pos = entrance_pos
	_exit_pos = exit_pos

	_grid.clear()
	_grid.resize(cols * rows)
	for i in range(_grid.size()):
		_grid[i] = CellState.EMPTY

	# Place immutable cells directly (bypass set_cell_state to avoid signal)
	_grid[_index(entrance_pos.x, entrance_pos.y)] = CellState.ENTRANCE
	_grid[_index(exit_pos.x, exit_pos.y)] = CellState.EXIT

	return true


## Single write gate. Validates transition against legal table.
## Returns true if state changed, false if illegal, out-of-bounds, or idempotent.
func set_cell_state(col: int, row: int, new_state: CellState) -> bool:
	if not is_valid_position(col, row):
		return false

	var old_state: CellState = get_cell_state(col, row)

	# Idempotent: setting to same state is a no-op → return false
	if old_state == new_state:
		return false

	# Check transition legality
	var key: int = (old_state as int) << 4 | (new_state as int)
	if not _transition_table.has(key):
		return false

	# TOWER merge: atomic in-frame — no intermediate EMPTY signal
	if old_state == CellState.TOWER and new_state == CellState.TOWER:
		_grid[_index(col, row)] = CellState.TOWER  # same value, but transition IS legal
		cell_state_changed.emit(col, row, CellState.TOWER as int, CellState.TOWER as int)
		return true

	# Normal transition
	_grid[_index(col, row)] = new_state
	cell_state_changed.emit(col, row, old_state as int, new_state as int)
	return true


## Read current cell state. Returns EMPTY for out-of-bounds.
func get_cell_state(col: int, row: int) -> CellState:
	if not is_valid_position(col, row):
		return CellState.EMPTY
	return _grid[_index(col, row)]


## Return a copy of the raw grid data array for initialisation purposes.
func get_grid_data() -> Array[CellState]:
	return _grid.duplicate()


## Single bounds-check authority. All systems route through this.
func is_valid_position(col: int, row: int) -> bool:
	return col >= 0 and col < cols and row >= 0 and row < rows


## Game reset handler (ADR-0008). Clears all cells to EMPTY, restores ENTRANCE/EXIT.
func _on_game_reset() -> void:
	if _grid.is_empty():
		return
	for i in range(_grid.size()):
		var current: CellState = _grid[i]
		if current == CellState.ENTRANCE or current == CellState.EXIT:
			continue  # Immutable cells — never changed
		if current != CellState.EMPTY:
			var col: int = i % cols
			var row: int = i / cols
			_grid[i] = CellState.EMPTY
			cell_state_changed.emit(col, row, current as int, CellState.EMPTY as int)


## Bridge local cell_state_changed to SignalBus for cross-system consumers (Story 003).
func _on_cell_state_changed(col: int, row: int, old_state: int, new_state: int) -> void:
	if has_node("/root/SignalBus"):
		SignalBus.cell_state_changed.emit(col, row, old_state, new_state)


## Flat array index from 2D coordinates (internal use)
func _index(col: int, row: int) -> int:
	return row * cols + col


## Recalculate grid origin. origin_x centers grid horizontally.
## origin_y is fixed at 64px (top bar height per GDD D.1).
func _recalculate_origin() -> void:
	var viewport_size: Vector2 = get_tree().root.size
	var grid_pixel_width: float = float(cols * cell_size)
	origin = Vector2(
		(viewport_size.x - grid_pixel_width) / 2.0,
		64.0
	)


## Window resize handler — recenters grid on viewport size change.
func _on_window_resize() -> void:
	_recalculate_origin()


## Convert grid coordinates to world pixel position (center of cell).
func grid_to_world(col: int, row: int) -> Vector2:
	var center_offset: float = float(cell_size) / 2.0
	return Vector2(
		origin.x + float(col * cell_size) + center_offset,
		origin.y + float(row * cell_size) + center_offset
	)


## Convert world pixel position to grid coordinates.
## Returns Vector2i(-1, -1) for positions outside the grid bounds.
func world_to_grid(world_pos: Vector2) -> Vector2i:
	var local_x: float = world_pos.x - origin.x
	var local_y: float = world_pos.y - origin.y
	var col: int = int(local_x / float(cell_size))
	var row: int = int(local_y / float(cell_size))
	if not is_valid_position(col, row):
		return Vector2i(-1, -1)
	return Vector2i(col, row)


## Return 4-directional neighbor positions (N/S/E/W) that are within grid bounds.
## Order: north, south, east, west.
func get_neighbors(col: int, row: int) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var directions := [
		Vector2i(0, -1),  # N
		Vector2i(0, 1),   # S
		Vector2i(1, 0),   # E
		Vector2i(-1, 0),  # W
	]
	for dir in directions:
		var nc: int = col + dir.x
		var nr: int = row + dir.y
		if is_valid_position(nc, nr):
			neighbors.append(Vector2i(nc, nr))
	return neighbors
