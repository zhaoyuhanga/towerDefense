extends GdUnitTestSuite
## Integration test: BoardGrid signal bridging to SignalBus (Story 003).
##
## Verifies:
##   1. cell_state_changed from BoardGrid propagates to SignalBus
##   2. game_reset emits cell_state_changed for each changed cell
##   3. ENTRANCE/EXIT cells are preserved during reset — no signals emitted for them
##   4. Already-EMPTY cells do not emit spurious signals during reset


var _board: BoardGrid


func before() -> void:
	_board = BoardGrid.new()
	# Must be in scene tree for _ready() to fire — this establishes the
	# SignalBus bridge connection and the game_reset subscription.
	add_child(_board)
	_board.init(20, 15, Vector2i(0, 0), Vector2i(19, 14))


func after() -> void:
	_board.free()


# ── Signal Bridging ────────────────────────────────────────────────────────────

func test_signal_bridge_cell_state_changed_propagates_to_signal_bus() -> void:
	# Arrange
	var received := []
	if not has_node("/root/SignalBus"):
		# SignalBus autoload unavailable — skip (headless without project.godot)
		return
	var conn_key := SignalBus.cell_state_changed.connect(
		func(c: int, r: int, o: int, n: int) -> void:
			received.append([c, r, o, n])
	)

	# Act
	var ok := _board.set_cell_state(5, 3, BoardGrid.CellState.BLOCK)

	# Assert
	assert_bool(ok).is_true()
	assert_int(received.size()).is_equal(1)
	assert_int(received[0][0]).is_equal(5)  # col
	assert_int(received[0][1]).is_equal(3)  # row
	assert_int(received[0][2]).is_equal(BoardGrid.CellState.EMPTY as int)  # old
	assert_int(received[0][3]).is_equal(BoardGrid.CellState.BLOCK as int)  # new

	# Cleanup
	SignalBus.cell_state_changed.disconnect(conn_key)


func test_signal_bridge_multiple_transitions_propagate_independently() -> void:
	# Arrange
	var received := []
	if not has_node("/root/SignalBus"):
		return
	var conn_key := SignalBus.cell_state_changed.connect(
		func(c: int, r: int, o: int, n: int) -> void:
			received.append([c, r, o, n])
	)

	# Act: place two blocks in different cells
	_board.set_cell_state(1, 1, BoardGrid.CellState.BLOCK)  # EMPTY → BLOCK
	_board.set_cell_state(2, 2, BoardGrid.CellState.TOWER)  # EMPTY → TOWER
	_board.set_cell_state(1, 1, BoardGrid.CellState.EMPTY)  # BLOCK → EMPTY (removal)

	# Assert: three transitions emitted
	assert_int(received.size()).is_equal(3)
	# First: EMPTY→BLOCK at (1,1)
	assert_int(received[0][0]).is_equal(1)
	assert_int(received[0][1]).is_equal(1)
	assert_int(received[0][2]).is_equal(BoardGrid.CellState.EMPTY as int)
	assert_int(received[0][3]).is_equal(BoardGrid.CellState.BLOCK as int)
	# Second: EMPTY→TOWER at (2,2)
	assert_int(received[1][0]).is_equal(2)
	assert_int(received[1][1]).is_equal(2)
	assert_int(received[1][2]).is_equal(BoardGrid.CellState.EMPTY as int)
	assert_int(received[1][3]).is_equal(BoardGrid.CellState.TOWER as int)
	# Third: BLOCK→EMPTY at (1,1)
	assert_int(received[2][0]).is_equal(1)
	assert_int(received[2][1]).is_equal(1)
	assert_int(received[2][2]).is_equal(BoardGrid.CellState.BLOCK as int)
	assert_int(received[2][3]).is_equal(BoardGrid.CellState.EMPTY as int)

	# Cleanup
	SignalBus.cell_state_changed.disconnect(conn_key)


# ── Game Reset Signal Emission ─────────────────────────────────────────────────

func test_game_reset_emits_signal_for_each_non_empty_cell() -> void:
	# Arrange: place blocks and towers on distinct cells
	_board.set_cell_state(1, 1, BoardGrid.CellState.BLOCK)
	_board.set_cell_state(2, 2, BoardGrid.CellState.TOWER)
	# (10, 10) stays EMPTY — should not emit on reset

	var signals_received := []
	_board.cell_state_changed.connect(
		func(c: int, r: int, o: int, n: int) -> void:
			signals_received.append([c, r, o, n])
	)

	# Act
	_board._on_game_reset()

	# Assert: exactly 2 signals — one for the BLOCK, one for the TOWER
	assert_int(signals_received.size()).is_equal(2)
	# All signals must transition to EMPTY
	for s in signals_received:
		assert_int(s[3]).is_equal(BoardGrid.CellState.EMPTY as int)


func test_game_reset_preserves_entrance_and_exit_no_signal() -> void:
	# Arrange: place blocks adjacent to entrance and exit
	_board.set_cell_state(1, 0, BoardGrid.CellState.BLOCK)
	_board.set_cell_state(18, 14, BoardGrid.CellState.TOWER)

	var signals_received := []
	_board.cell_state_changed.connect(
		func(c: int, r: int, o: int, n: int) -> void:
			signals_received.append([c, r, o, n])
	)

	# Act
	_board._on_game_reset()

	# Assert: ENTRANCE and EXIT unchanged — no transition signal for them
	for s in signals_received:
		var col: int = s[0]
		var row: int = s[1]
		assert_bool(col == 0 and row == 0).is_false()  # ENTRANCE
		assert_bool(col == 19 and row == 14).is_false()  # EXIT

	# State on grid is preserved
	assert_int(_board.get_cell_state(0, 0) as int).is_equal(BoardGrid.CellState.ENTRANCE as int)
	assert_int(_board.get_cell_state(19, 14) as int).is_equal(BoardGrid.CellState.EXIT as int)
	# Adjacent cells are cleared
	assert_int(_board.get_cell_state(1, 0) as int).is_equal(BoardGrid.CellState.EMPTY as int)
	assert_int(_board.get_cell_state(18, 14) as int).is_equal(BoardGrid.CellState.EMPTY as int)


func test_game_reset_does_not_emit_for_already_empty_cells() -> void:
	# Arrange: after init, all cells except (0,0) and (19,14) are EMPTY.
	# No blocks/towers have been placed.
	var signals_received := []
	_board.cell_state_changed.connect(
		func(c: int, r: int, o: int, n: int) -> void:
			signals_received.append([c, r, o, n])
	)

	# Act: reset when nothing has been placed
	_board._on_game_reset()

	# Assert: zero signals — nothing to clear
	assert_int(signals_received.size()).is_equal(0)


func test_game_reset_emits_correct_old_state_before_clear() -> void:
	# Arrange: place a BLOCK and a TOWER at known positions
	_board.set_cell_state(3, 3, BoardGrid.CellState.BLOCK)
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)

	var signals_received := []
	_board.cell_state_changed.connect(
		func(c: int, r: int, o: int, n: int) -> void:
			signals_received.append([c, r, o, n])
	)

	# Act
	_board._on_game_reset()

	# Assert: two signals, old_state correctly identifies what was there
	assert_int(signals_received.size()).is_equal(2)

	# Sort by old_state so assertions are deterministic regardless of iteration order
	signals_received.sort_custom(func(a, b): return a[2] < b[2])

	# First signal: BLOCK→EMPTY
	assert_int(signals_received[0][0]).is_equal(3)
	assert_int(signals_received[0][1]).is_equal(3)
	assert_int(signals_received[0][2]).is_equal(BoardGrid.CellState.BLOCK as int)
	assert_int(signals_received[0][3]).is_equal(BoardGrid.CellState.EMPTY as int)

	# Second signal: TOWER→EMPTY
	assert_int(signals_received[1][0]).is_equal(5)
	assert_int(signals_received[1][1]).is_equal(5)
	assert_int(signals_received[1][2]).is_equal(BoardGrid.CellState.TOWER as int)
	assert_int(signals_received[1][3]).is_equal(BoardGrid.CellState.EMPTY as int)


func test_game_reset_clears_grid_state_correctly() -> void:
	# Arrange: populate several cells
	_board.set_cell_state(1, 1, BoardGrid.CellState.BLOCK)
	_board.set_cell_state(2, 2, BoardGrid.CellState.TOWER)
	_board.set_cell_state(10, 5, BoardGrid.CellState.BLOCK)

	# Act
	_board._on_game_reset()

	# Assert: all placed cells are now EMPTY
	assert_int(_board.get_cell_state(1, 1) as int).is_equal(BoardGrid.CellState.EMPTY as int)
	assert_int(_board.get_cell_state(2, 2) as int).is_equal(BoardGrid.CellState.EMPTY as int)
	assert_int(_board.get_cell_state(10, 5) as int).is_equal(BoardGrid.CellState.EMPTY as int)
	# Immutable cells preserved
	assert_int(_board.get_cell_state(0, 0) as int).is_equal(BoardGrid.CellState.ENTRANCE as int)
	assert_int(_board.get_cell_state(19, 14) as int).is_equal(BoardGrid.CellState.EXIT as int)


# ── Idempotent Transitions (no signal) ─────────────────────────────────────────

func test_signal_bridge_idempotent_transition_does_not_emit() -> void:
	# Arrange
	var received := []
	if not has_node("/root/SignalBus"):
		return
	var conn_key := SignalBus.cell_state_changed.connect(
		func(c: int, r: int, o: int, n: int) -> void:
			received.append([c, r, o, n])
	)

	# Act: EMPTY→EMPTY is idempotent (returns false, no signal)
	var ok := _board.set_cell_state(5, 5, BoardGrid.CellState.EMPTY)

	# Assert
	assert_bool(ok).is_false()
	assert_int(received.size()).is_equal(0)

	# Cleanup
	SignalBus.cell_state_changed.disconnect(conn_key)
