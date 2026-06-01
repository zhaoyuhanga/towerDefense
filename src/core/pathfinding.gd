class_name Pathfinding
extends Node
## Pathfinding system — computes the shortest 4-directional path from ENTRANCE to EXIT
## using AStarGrid2D. Listens to BoardGrid.cell_state_changed for automatic full rebuilds.
##
## Configuration: 20×15 grid, DIAGONAL_MODE_NEVER, HEURISTIC_MANHATTAN.
## All 300 cells are resynced from BoardGrid on each rebuild() call.
##
## Godot 4.6 guard: is_point_solid() is checked before every get_id_path() call
## to prevent crashes or undefined behavior if entrance/exit become solid.
##
## @tutorial: https://docs.godotengine.org/en/stable/classes/class_astargrid2d.html

## Emitted after path recomputation completes. Array[Vector2i] in grid coordinates.
signal path_updated(new_path: Array)

## Emitted when no walkable path exists from ENTRANCE to EXIT.
## Calls to get_main_path() will return an empty array.
signal path_blocked()

## BoardGrid reference for cell state queries. Set via init().
var _board: BoardGrid = null

## AStarGrid2D instance handling shortest-path computation.
## Created and configured in _create_astar().
var _astar: AStarGrid2D = null

## Cached main path from ENTRANCE to EXIT (grid coordinates).
## Updated by rebuild(). Empty if no path exists.
var _main_path: Array[Vector2i] = []

## Grid entrance position, located by scanning BoardGrid during init().
var _entrance_pos: Vector2i = Vector2i(-1, -1)

## Grid exit position, located by scanning BoardGrid during init().
var _exit_pos: Vector2i = Vector2i(-1, -1)

## Grid column count, synced from BoardGrid during init().
var _cols: int = 20

## Grid row count, synced from BoardGrid during init().
var _rows: int = 15


## Initialize the pathfinding system with a BoardGrid reference.
## Scans the board to locate ENTRANCE and EXIT positions, creates the AStarGrid2D,
## subscribes to cell_state_changed for automatic rebuilds, and bridges signals to
## SignalBus (if available). Performs an initial path computation.
func init(board: BoardGrid) -> void:
	_board = board
	_cols = board.cols
	_rows = board.rows

	_scan_endpoints()
	_create_astar()
	rebuild()

	# Subscribe to grid changes for automatic rebuild
	if not _board.cell_state_changed.is_connected(_on_cell_state_changed):
		_board.cell_state_changed.connect(_on_cell_state_changed)

	# Bridge local signals to SignalBus (has_node guard for test safety)
	_bridge_to_signal_bus()


## Full rebuild: sync every cell from BoardGrid into AStarGrid2D, then recompute
## the shortest path. Emits path_updated or path_blocked based on result.
## Called automatically on cell_state_changed. Safe to call externally.
func rebuild() -> void:
	_sync_all_cells()
	_compute_path()


## Returns a copy of the cached main path (grid coordinates from ENTRANCE to EXIT).
## Returns an empty array if no path exists.
##
## Usage:
##   var path := pathfinding.get_main_path()
##   for waypoint in path:
##       monster.move_to(waypoint)
func get_main_path() -> Array[Vector2i]:
	return _main_path.duplicate()


## Returns the number of steps from ENTRANCE to EXIT along the main path.
## Returns 0 if no path exists.
##
## Usage:
##   var steps := pathfinding.get_path_length()
##   hud.update_path_display(steps)
func get_path_length() -> int:
	return _main_path.size()


## Returns true if a valid path exists from ENTRANCE to EXIT.
## Used by BlockSystem for placement pre-checks (prevent dead-ending the board).
##
## Usage:
##   if not pathfinding.is_path_reachable():
##       block_placement.reject("Would block the only path!")
func is_path_reachable() -> bool:
	return not _main_path.is_empty()


## Hypothetical check: would a path still exist if [param blocked_pos] were solid?
## Temporarily sets the cell solid in AStarGrid2D, queries get_id_path(),
## then restores the original solid state. Does NOT modify _main_path or emit signals.
##
## Returns false if blocked_pos is ENTRANCE, EXIT, out-of-bounds, or if either
## endpoint is currently solid (4.6 guard).
##
## Usage:
##   if not pathfinding.would_path_be_reachable(Vector2i(10, 7)):
##       print("Cannot place block here — would dead-end the board")
func would_path_be_reachable(blocked_pos: Vector2i) -> bool:
	# Guard: invalid position
	if _board == null or not _board.is_valid_position(blocked_pos.x, blocked_pos.y):
		return false

	# Cannot block entrance or exit
	if blocked_pos == _entrance_pos or blocked_pos == _exit_pos:
		return false

	# Guard: missing endpoints (should never happen after successful init)
	if _entrance_pos == Vector2i(-1, -1) or _exit_pos == Vector2i(-1, -1):
		return false

	# Godot 4.6 guard: endpoints must not already be solid
	if _astar.is_point_solid(_entrance_pos) or _astar.is_point_solid(_exit_pos):
		return false

	# Save current solid state, temporarily set to solid
	var was_solid: bool = _astar.is_point_solid(blocked_pos)
	_astar.set_point_solid(blocked_pos, true)

	# Query path directly — bypass _compute_path() to avoid signal emission
	var raw_path: PackedVector2Array = _astar.get_id_path(_entrance_pos, _exit_pos)

	# Restore original solid state
	_astar.set_point_solid(blocked_pos, was_solid)

	return not raw_path.is_empty()


# ── Internal: AStarGrid2D Setup ────────────────────────────────────────────────

## Scan the BoardGrid to locate ENTRANCE and EXIT cell positions.
## Caches them in _entrance_pos / _exit_pos.
## Logs errors if either is missing (should never happen after BoardGrid.init()).
func _scan_endpoints() -> void:
	_entrance_pos = Vector2i(-1, -1)
	_exit_pos = Vector2i(-1, -1)

	for row in range(_rows):
		for col in range(_cols):
			var state: BoardGrid.CellState = _board.get_cell_state(col, row)
			match state:
				BoardGrid.CellState.ENTRANCE:
					_entrance_pos = Vector2i(col, row)
				BoardGrid.CellState.EXIT:
					_exit_pos = Vector2i(col, row)

	if _entrance_pos == Vector2i(-1, -1):
		push_error("Pathfinding._scan_endpoints: No ENTRANCE cell found on board")
	if _exit_pos == Vector2i(-1, -1):
		push_error("Pathfinding._scan_endpoints: No EXIT cell found on board")


## Create and configure the AStarGrid2D instance.
## Region: 20×15, no diagonal movement, Manhattan heuristic.
## Calls update() after initial configuration to force internal data structure build.
func _create_astar() -> void:
	if _astar != null:
		_astar.free()

	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, _cols, _rows)
	_astar.cell_size = Vector2i(1, 1)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()


# ── Internal: Cell Sync ────────────────────────────────────────────────────────

## Iterate all 300 cells and set solid/walkable in AStarGrid2D based on BoardGrid state.
## BLOCK and TOWER cells are solid (impassable). EMPTY, ENTRANCE, and EXIT are walkable.
func _sync_all_cells() -> void:
	for row in range(_rows):
		for col in range(_cols):
			var state: BoardGrid.CellState = _board.get_cell_state(col, row)
			var is_solid := (state == BoardGrid.CellState.BLOCK or state == BoardGrid.CellState.TOWER)
			_astar.set_point_solid(Vector2i(col, row), is_solid)


# ── Internal: Path Computation ─────────────────────────────────────────────────

## Compute the shortest path from ENTRANCE to EXIT using AStarGrid2D.
## Godot 4.6 guard: checks is_point_solid() on both endpoints before calling
## get_id_path() to prevent crashes or undefined behavior.
##
## Updates _main_path and emits path_updated or path_blocked.
func _compute_path() -> void:
	# Guard: missing endpoints (should never happen after successful init)
	if _entrance_pos == Vector2i(-1, -1) or _exit_pos == Vector2i(-1, -1):
		_set_path_empty()
		return

	# Godot 4.6 guard: is_point_solid() before get_id_path()
	# Prevents crash/undefined behavior if endpoints are solid
	if _astar.is_point_solid(_entrance_pos) or _astar.is_point_solid(_exit_pos):
		_set_path_empty()
		return

	var raw_path: PackedVector2Array = _astar.get_id_path(_entrance_pos, _exit_pos)

	# Convert PackedVector2Array (Vector2) → Array[Vector2i]
	var converted: Array[Vector2i] = []
	converted.resize(raw_path.size())
	for i in range(raw_path.size()):
		converted[i] = Vector2i(int(raw_path[i].x), int(raw_path[i].y))

	_main_path = converted

	# AStarGrid2D returns empty PackedVector2Array when no path exists
	if _main_path.is_empty():
		_emit_path_blocked()
	else:
		_emit_path_updated()


## Set path to empty and emit path_blocked. Used for all failure paths.
func _set_path_empty() -> void:
	_main_path.clear()
	_emit_path_blocked()


# ── Internal: Signal Emission ──────────────────────────────────────────────────

## Emit path_updated locally. Bridge method forwards to SignalBus.
func _emit_path_updated() -> void:
	path_updated.emit(_main_path)


## Emit path_blocked locally. Bridge method forwards to SignalBus.
func _emit_path_blocked() -> void:
	path_blocked.emit()


# ── Internal: BoardGrid Event Handler ──────────────────────────────────────────

## React to BoardGrid cell state changes by triggering a full rebuild.
## Parameters use int (matching BoardGrid.cell_state_changed signature).
func _on_cell_state_changed(_col: int, _row: int, _old_state: int, _new_state: int) -> void:
	rebuild()


# ── Internal: SignalBus Bridge (ADR-0001) ──────────────────────────────────────

## Connect local signals to SignalBus for cross-system consumers (MonsterSystem,
## BlockSystem, HUD). Uses has_node guard for test safety — SignalBus may not
## exist in unit test environments.
func _bridge_to_signal_bus() -> void:
	if not has_node("/root/SignalBus"):
		return
	path_updated.connect(_on_path_updated_bridge)
	path_blocked.connect(_on_path_blocked_bridge)


func _on_path_updated_bridge(new_path: Array) -> void:
	if has_node("/root/SignalBus"):
		SignalBus.path_updated.emit(new_path)


func _on_path_blocked_bridge() -> void:
	if has_node("/root/SignalBus"):
		SignalBus.path_blocked.emit()
