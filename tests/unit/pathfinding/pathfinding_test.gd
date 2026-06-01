extends GdUnitTestSuite
## Pathfinding unit tests — AStarGrid2D shortest path from ENTRANCE to EXIT.
## Covers: empty board, blocked path, detour, reroute, 4.6 solid-point guard,
## L-shaped corridor, signal emission, and is_path_reachable() tracking.
##
## Each test gets a fresh BoardGrid + Pathfinding. BoardGrid is added as a child
## so _ready() fires (building the transition table required for set_cell_state).

const COLS := 20
const ROWS := 15
const ENTRANCE := Vector2i(0, 7)
const EXIT := Vector2i(19, 7)

var _board: BoardGrid
var _pathfinding: Pathfinding

# Signal capture flags for emit-verification tests
var _path_blocked_received: bool = false
var _path_updated_received: bool = false
var _received_path: Array = []


func before() -> void:
	_board = BoardGrid.new()
	_board.init(COLS, ROWS, ENTRANCE, EXIT)
	add_child(_board)  # Triggers _ready() → builds _transition_table for set_cell_state()

	_pathfinding = Pathfinding.new()
	_pathfinding.init(_board)

	# Reset signal capture state
	_path_blocked_received = false
	_path_updated_received = false
	_received_path.clear()


func after() -> void:
	if _pathfinding != null:
		_pathfinding.free()
		_pathfinding = null
	if _board != null:
		remove_child(_board)
		_board.free()
		_board = null


# ── Signal capture helpers ─────────────────────────────────────────────────────

func _on_path_blocked() -> void:
	_path_blocked_received = true


func _on_path_updated(new_path: Array) -> void:
	_path_updated_received = true
	_received_path = new_path


# ── Helper: place a vertical wall of blocks at a given column ──────────────────

func _place_vertical_wall(col: int) -> void:
	for row in range(ROWS):
		_board.set_cell_state(col, row, BoardGrid.CellState.BLOCK)


# ── Helper: clear all blocks/towers (restore EMPTY) ────────────────────────────

func _clear_all_blocks() -> void:
	for row in range(ROWS):
		for col in range(COLS):
			var state := _board.get_cell_state(col, row)
			if state == BoardGrid.CellState.BLOCK or state == BoardGrid.CellState.TOWER:
				_board.set_cell_state(col, row, BoardGrid.CellState.EMPTY)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 1: Empty board returns straight-line path
# ═══════════════════════════════════════════════════════════════════════════════

func test_pathfinding_empty_board_returns_straight_line_path() -> void:
	# Arrange: fresh board — ENTRANCE (0,7), EXIT (19,7), all other cells EMPTY

	# Act
	var path := _pathfinding.get_main_path()

	# Assert
	assert_bool(_pathfinding.is_path_reachable()).is_true()
	assert_int(path.size()).is_equal(20)  # Straight line: 20 cells
	assert_int(_pathfinding.get_path_length()).is_equal(20)

	# Verify all waypoints are on row 7 (straight horizontal)
	for i in range(path.size()):
		var wp: Vector2i = path[i]
		assert_int(wp.y).is_equal(7)
	# Verify monotonic column progression
	assert_int(path[0].x).is_equal(0)
	assert_int(path[19].x).is_equal(19)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 2: Full vertical barrier blocks path completely
# ═══════════════════════════════════════════════════════════════════════════════

func test_pathfinding_full_barrier_returns_empty_path() -> void:
	# Arrange: place a vertical wall at col=10 spanning all rows
	# This cuts the board in half — no path from left to right
	_pathfinding.path_blocked.connect(_on_path_blocked)
	_place_vertical_wall(10)

	# Act
	var path := _pathfinding.get_main_path()

	# Assert
	assert_array(path).is_empty()
	assert_int(_pathfinding.get_path_length()).is_equal(0)
	assert_bool(_pathfinding.is_path_reachable()).is_false()
	assert_bool(_path_blocked_received).is_true()


# ═══════════════════════════════════════════════════════════════════════════════
# Test 3: Single block on straight line forces detour
# ═══════════════════════════════════════════════════════════════════════════════

func test_pathfinding_single_block_causes_detour() -> void:
	# Arrange: place a block directly on the straight-line path at (10, 7)
	_board.set_cell_state(10, 7, BoardGrid.CellState.BLOCK)

	# Act
	var path := _pathfinding.get_main_path()

	# Assert: path exists but is longer than 20 (detoured around the block)
	assert_bool(_pathfinding.is_path_reachable()).is_true()
	assert_bool(path.size() > 20).is_true()

	# The block at (10, 7) must NOT be in the path
	var blocked_pos := Vector2i(10, 7)
	for wp in path:
		assert_bool(wp != blocked_pos).is_true()

	# Path must start at entrance and end at exit
	assert_int((path[0] as Vector2i).x).is_equal(ENTRANCE.x)
	assert_int((path[0] as Vector2i).y).is_equal(ENTRANCE.y)
	assert_int((path[path.size() - 1] as Vector2i).x).is_equal(EXIT.x)
	assert_int((path[path.size() - 1] as Vector2i).y).is_equal(EXIT.y)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 4: Godot 4.6 solid-point guard — entrance solid → graceful empty return
# ═══════════════════════════════════════════════════════════════════════════════

func test_pathfinding_solid_entrance_guard_returns_empty() -> void:
	# Arrange: normal board has a valid path
	assert_bool(_pathfinding.is_path_reachable()).is_true()

	# Manually corrupt AStarGrid2D: set entrance solid (simulates 4.6 edge case)
	_pathfinding.path_blocked.connect(_on_path_blocked)
	_pathfinding._astar.set_point_solid(ENTRANCE, true)

	# Act: rebuild forces path recomputation
	_pathfinding.rebuild()
	var path := _pathfinding.get_main_path()

	# Assert: guard catches solid entrance, returns empty without crashing
	assert_array(path).is_empty()
	assert_bool(_pathfinding.is_path_reachable()).is_false()
	assert_bool(_path_blocked_received).is_true()


# ═══════════════════════════════════════════════════════════════════════════════
# Test 5: L-shaped corridor — path navigates a single right-angle turn
# ═══════════════════════════════════════════════════════════════════════════════

func test_pathfinding_l_shaped_corridor_path_succeeds() -> void:
	# Arrange: create a board with opposite-corner entrance/exit
	# Entrance at bottom-left (0,14), Exit at top-right (19,0)
	# Block everything except column 0 (vertical leg) and row 0 (horizontal leg)
	var board := BoardGrid.new()
	board.init(COLS, ROWS, Vector2i(0, 14), Vector2i(19, 0))
	add_child(board)

	# Block all cells outside the L-shaped corridor
	for col in range(COLS):
		for row in range(ROWS):
			if col == 0 or row == 0:
				continue  # L corridor: keep open
			board.set_cell_state(col, row, BoardGrid.CellState.BLOCK)

	var pf := Pathfinding.new()
	pf.init(board)

	# Act
	var path := pf.get_main_path()

	# Assert: L-shaped path exists: 14 steps up + 19 steps right = 33 cells
	assert_bool(pf.is_path_reachable()).is_true()
	assert_int(path.size()).is_equal(33)

	# First waypoint is entrance (0, 14)
	assert_int((path[0] as Vector2i).x).is_equal(0)
	assert_int((path[0] as Vector2i).y).is_equal(14)
	# Last waypoint is exit (19, 0)
	assert_int((path[path.size() - 1] as Vector2i).x).is_equal(19)
	assert_int((path[path.size() - 1] as Vector2i).y).is_equal(0)

	# Cleanup
	pf.free()
	remove_child(board)
	board.free()


# ═══════════════════════════════════════════════════════════════════════════════
# Test 6: path_updated signal emits with correct path after block placement
# ═══════════════════════════════════════════════════════════════════════════════

func test_pathfinding_path_updated_signal_emits_on_change() -> void:
	# Arrange: start with a valid straight-line path
	assert_int(_pathfinding.get_path_length()).is_equal(20)
	_pathfinding.path_updated.connect(_on_path_updated)

	# Act: place a block to force path recalculation
	_board.set_cell_state(10, 7, BoardGrid.CellState.BLOCK)

	# Assert: signal fired with new path
	assert_bool(_path_updated_received).is_true()
	assert_bool(_received_path.size() > 20).is_true()  # Detour = longer path

	# Received path must start and end correctly
	assert_int((_received_path[0] as Vector2i).x).is_equal(ENTRANCE.x)
	assert_int((_received_path[_received_path.size() - 1] as Vector2i).x).is_equal(EXIT.x)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 7: path_blocked signal emits when last route is closed
# ═══════════════════════════════════════════════════════════════════════════════

func test_pathfinding_path_blocked_signal_emits_when_route_sealed() -> void:
	# Arrange: block most cells, leave only a 1-wide corridor at row 14
	_pathfinding.path_blocked.connect(_on_path_blocked)

	# Close all rows except row 14 from col=1 to col=18
	for col in range(1, 19):
		for row in range(ROWS):
			if row == 14:
				continue
			_board.set_cell_state(col, row, BoardGrid.CellState.BLOCK)

	# Path should still exist (via row 14 corridor)
	assert_bool(_pathfinding.is_path_reachable()).is_true()
	assert_bool(_path_blocked_received).is_false()

	# Act: seal the last row at the entrance side
	_board.set_cell_state(1, 14, BoardGrid.CellState.BLOCK)
	# Now the path from (0,7) to (19,7) is completely sealed

	# Assert
	assert_bool(_path_blocked_received).is_true()
	assert_bool(_pathfinding.is_path_reachable()).is_false()


# ═══════════════════════════════════════════════════════════════════════════════
# Test 8: is_path_reachable() tracks reachability across state changes
# ═══════════════════════════════════════════════════════════════════════════════

func test_pathfinding_is_path_reachable_tracks_state() -> void:
	# Phase 1: empty board → reachable
	assert_bool(_pathfinding.is_path_reachable()).is_true()

	# Phase 2: full vertical barrier → unreachable
	_place_vertical_wall(10)
	assert_bool(_pathfinding.is_path_reachable()).is_false()

	# Phase 3: remove wall → reachable again
	_clear_all_blocks()
	assert_bool(_pathfinding.is_path_reachable()).is_true()
	assert_int(_pathfinding.get_path_length()).is_equal(20)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 9: Removing a block restores a shorter path
# ═══════════════════════════════════════════════════════════════════════════════

func test_pathfinding_remove_block_restores_shorter_path() -> void:
	# Arrange: place a block at (10, 7) to force detour
	_board.set_cell_state(10, 7, BoardGrid.CellState.BLOCK)
	var detour_length := _pathfinding.get_path_length()
	assert_bool(detour_length > 20).is_true()

	# Act: remove the block
	_board.set_cell_state(10, 7, BoardGrid.CellState.EMPTY)

	# Assert: path returns to straight line (20 steps)
	assert_int(_pathfinding.get_path_length()).is_equal(20)
	var path := _pathfinding.get_main_path()
	for i in range(path.size()):
		var wp: Vector2i = path[i]
		assert_int(wp.y).is_equal(7)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 10: Multiple blocks create a winding path (snake corridor)
# ═══════════════════════════════════════════════════════════════════════════════

func test_pathfinding_multiple_blocks_winding_path() -> void:
	# Arrange: create a snake-like corridor.
	# Entrance (0,7), Exit (19,7). Force path to zigzag:
	#   → right to col 5, down to row 10, right to col 15, up to row 7, right to exit
	#
	# Block everything above row 7 from col=0..5 (force down at col=5)
	for col in range(0, 6):
		for row in range(0, 7):
			_board.set_cell_state(col, row, BoardGrid.CellState.BLOCK)
	# Block everything below row 7 from col=0..4 (keep col=5 open for the turn)
	for col in range(0, 5):
		for row in range(8, ROWS):
			_board.set_cell_state(col, row, BoardGrid.CellState.BLOCK)

	# Block rows 7-9 from col=6..14 (force path down to row 10)
	for col in range(6, 15):
		for row in range(7, 10):
			if row == 10:
				continue
			_board.set_cell_state(col, row, BoardGrid.CellState.BLOCK)

	# Block rows 8-14 from col=15..18 (force path up at col=15)
	for col in range(15, 19):
		for row in range(8, ROWS):
			_board.set_cell_state(col, row, BoardGrid.CellState.BLOCK)

	# Act
	var path := _pathfinding.get_main_path()

	# Assert: path exists and is longer than straight line
	assert_bool(_pathfinding.is_path_reachable()).is_true()
	assert_bool(path.size() > 20).is_true()

	# Path must start at entrance and end at exit
	assert_int((path[0] as Vector2i).x).is_equal(ENTRANCE.x)
	assert_int((path[0] as Vector2i).y).is_equal(ENTRANCE.y)
	assert_int((path[path.size() - 1] as Vector2i).x).is_equal(EXIT.x)
	assert_int((path[path.size() - 1] as Vector2i).y).is_equal(EXIT.y)

	# Verify path contains turns: there should be waypoints that change both x and y
	# between consecutive steps (indicating a zigzag, not pure straight)
	var turn_count := 0
	for i in range(1, path.size()):
		var prev: Vector2i = path[i - 1]
		var curr: Vector2i = path[i]
		if prev.y != curr.y:
			turn_count += 1
	assert_bool(turn_count >= 4).is_true()  # At least 4 vertical transitions in the snake
