extends GdUnitTestSuite

var _board: BoardGrid

func before() -> void:
	_board = BoardGrid.new()
	_board.init(20, 15, Vector2i(0, 0), Vector2i(19, 14))

func after() -> void:
	_board.free()

func test_init_creates_correct_dimensions() -> void:
	assert_bool(_board.is_valid_position(0, 0)).is_true()
	assert_bool(_board.is_valid_position(19, 14)).is_true()
	assert_bool(_board.is_valid_position(-1, 0)).is_false()
	assert_bool(_board.is_valid_position(0, -1)).is_false()
	assert_bool(_board.is_valid_position(20, 0)).is_false()
	assert_bool(_board.is_valid_position(0, 15)).is_false()
	# All cells except entrance/exit are EMPTY
	assert_int(_board.get_cell_state(10, 7) as int).is_equal(BoardGrid.CellState.EMPTY as int)
	assert_int(_board.get_cell_state(5, 3) as int).is_equal(BoardGrid.CellState.EMPTY as int)

func test_init_entrance_exit_positions() -> void:
	assert_int(_board.get_cell_state(0, 0) as int).is_equal(BoardGrid.CellState.ENTRANCE as int)
	assert_int(_board.get_cell_state(19, 14) as int).is_equal(BoardGrid.CellState.EXIT as int)

func test_init_rejects_same_entrance_exit() -> void:
	var board2 := BoardGrid.new()
	var ok := board2.init(20, 15, Vector2i(5, 5), Vector2i(5, 5))
	assert_bool(ok).is_false()
	board2.free()

func test_valid_transitions() -> void:
	# EMPTY → BLOCK
	assert_bool(_board.set_cell_state(5, 3, BoardGrid.CellState.BLOCK)).is_true()
	assert_int(_board.get_cell_state(5, 3) as int).is_equal(BoardGrid.CellState.BLOCK as int)
	# BLOCK → EMPTY
	assert_bool(_board.set_cell_state(5, 3, BoardGrid.CellState.EMPTY)).is_true()
	assert_int(_board.get_cell_state(5, 3) as int).is_equal(BoardGrid.CellState.EMPTY as int)
	# EMPTY → TOWER
	assert_bool(_board.set_cell_state(8, 8, BoardGrid.CellState.TOWER)).is_true()
	assert_int(_board.get_cell_state(8, 8) as int).is_equal(BoardGrid.CellState.TOWER as int)
	# TOWER → EMPTY (sell)
	assert_bool(_board.set_cell_state(8, 8, BoardGrid.CellState.EMPTY)).is_true()
	# Idempotent: EMPTY → EMPTY returns false
	assert_bool(_board.set_cell_state(10, 7, BoardGrid.CellState.EMPTY)).is_false()
	# BLOCK → TOWER is illegal (must remove first)
	_board.set_cell_state(5, 3, BoardGrid.CellState.BLOCK)
	assert_bool(_board.set_cell_state(5, 3, BoardGrid.CellState.TOWER)).is_false()

func test_entrance_exit_immutability() -> void:
	assert_bool(_board.set_cell_state(0, 0, BoardGrid.CellState.BLOCK)).is_false()
	assert_bool(_board.set_cell_state(0, 0, BoardGrid.CellState.TOWER)).is_false()
	assert_bool(_board.set_cell_state(0, 0, BoardGrid.CellState.EMPTY)).is_false()
	assert_int(_board.get_cell_state(0, 0) as int).is_equal(BoardGrid.CellState.ENTRANCE as int)

	assert_bool(_board.set_cell_state(19, 14, BoardGrid.CellState.BLOCK)).is_false()
	assert_bool(_board.set_cell_state(19, 14, BoardGrid.CellState.EMPTY)).is_false()
	assert_int(_board.get_cell_state(19, 14) as int).is_equal(BoardGrid.CellState.EXIT as int)

func test_tower_merge_atomicity() -> void:
	_board.set_cell_state(8, 8, BoardGrid.CellState.TOWER)
	# Merge: TOWER → TOWER — atomic, signal sees TOWER→TOWER, no EMPTY
	var signal_old := -1
	var signal_new := -1
	_board.cell_state_changed.connect(func(c, r, o, n): signal_old = o; signal_new = n)

	assert_bool(_board.set_cell_state(8, 8, BoardGrid.CellState.TOWER)).is_true()
	assert_int(signal_old).is_equal(BoardGrid.CellState.TOWER as int)
	assert_int(signal_new).is_equal(BoardGrid.CellState.TOWER as int)
	# State should still be TOWER (not EMPTY at any point)
	assert_int(_board.get_cell_state(8, 8) as int).is_equal(BoardGrid.CellState.TOWER as int)
