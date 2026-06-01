extends GdUnitTestSuite
## Drag state machine unit tests for InputHandler.
##
## Verifies all state transitions of the drag detection state machine:
##   IDLE → PRESSING → DRAGGING → IDLE
##
## Tests the 3px drag threshold boundary (GDD §Formulas):
##   - Movement <= 3px → click (grid_clicked signal)
##   - Movement > 3px  → drag (drag_started signal)
##
## Also verifies drag cancellation by right-click and phase change.
##
## Coverage targets:
##   - AC: 拖拽检测阈值 3px (移动 2px = 点击, 移动 4px = 拖拽)
##   - AC: 拖拽中途右键取消


var _handler: InputHandler
var _board: BoardGrid


func before() -> void:
	_board = BoardGrid.new()
	_board.init(20, 15, Vector2i(0, 0), Vector2i(19, 14))
	_handler = InputHandler.new()
	_handler.set_board_grid(_board)
	# Set phase to PREP so all board interactions are allowed
	_handler._current_phase = InputHandler.PHASE_PREP


func after() -> void:
	_handler.free()
	_board.free()


# ============================================================
# State Transitions
# ============================================================

func test_drag_state_idle_to_pressing_on_tower_left_press() -> void:
	# Arrange
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var world_pos := _board.grid_to_world(5, 5)

	# Act
	_handler.handle_left_press(world_pos)

	# Assert
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.PRESSING as int)
	assert_int(_handler.drag_source_grid.x).is_equal(5)
	assert_int(_handler.drag_source_grid.y).is_equal(5)
	assert_float(_handler.drag_start_pos.x).is_equal(world_pos.x)
	assert_float(_handler.drag_start_pos.y).is_equal(world_pos.y)


func test_drag_state_pressing_to_idle_on_release_below_threshold_is_click() -> void:
	# Arrange
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var world_pos := _board.grid_to_world(5, 5)
	_handler.handle_left_press(world_pos)

	var clicked_col := -1
	var clicked_row := -1
	_handler.grid_clicked.connect(func(c: int, r: int) -> void:
		clicked_col = c
		clicked_row = r
	)

	# Act: release at same position (0px movement < 3px threshold)
	_handler.handle_left_release(world_pos)

	# Assert
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)
	assert_int(clicked_col).is_equal(5)
	assert_int(clicked_row).is_equal(5)


func test_drag_state_pressing_to_dragging_on_move_exceeding_threshold() -> void:
	# Arrange
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var press_pos := _board.grid_to_world(5, 5)
	_handler.handle_left_press(press_pos)

	var drag_started_col := -1
	var drag_started_row := -1
	_handler.drag_started.connect(func(c: int, r: int) -> void:
		drag_started_col = c
		drag_started_row = r
	)

	# Act: move 4px right (> 3px threshold)
	_handler.handle_mouse_motion(press_pos + Vector2(4.0, 0.0))

	# Assert
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.DRAGGING as int)
	assert_int(drag_started_col).is_equal(5)
	assert_int(drag_started_row).is_equal(5)


func test_drag_state_pressing_stays_pressing_on_subthreshold_move() -> void:
	# Arrange
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var press_pos := _board.grid_to_world(5, 5)
	_handler.handle_left_press(press_pos)

	var drag_started := false
	_handler.drag_started.connect(func(_c: int, _r: int) -> void:
		drag_started = true
	)

	# Act: move 2px right (< 3px threshold)
	_handler.handle_mouse_motion(press_pos + Vector2(2.0, 0.0))

	# Assert: still PRESSING, no drag_started fired
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.PRESSING as int)
	assert_bool(drag_started).is_false()


func test_drag_state_dragging_to_idle_on_release_emits_drag_ended() -> void:
	# Arrange
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	_board.set_cell_state(10, 7, BoardGrid.CellState.TOWER)
	var press_pos := _board.grid_to_world(5, 5)
	_handler.handle_left_press(press_pos)
	_handler.handle_mouse_motion(press_pos + Vector2(4.0, 0.0))

	var ended_sc := -1
	var ended_sr := -1
	var ended_tc := -1
	var ended_tr := -1
	_handler.drag_ended.connect(func(sc: int, sr: int, tc: int, tr: int) -> void:
		ended_sc = sc
		ended_sr = sr
		ended_tc = tc
		ended_tr = tr
	)

	# Act: release over target cell (10, 7)
	var release_pos := _board.grid_to_world(10, 7)
	_handler.handle_left_release(release_pos)

	# Assert
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)
	assert_int(ended_sc).is_equal(5)
	assert_int(ended_sr).is_equal(5)
	assert_int(ended_tc).is_equal(10)
	assert_int(ended_tr).is_equal(7)


func test_drag_ended_target_outside_grid_is_negative_one() -> void:
	# Arrange
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var press_pos := _board.grid_to_world(5, 5)
	_handler.handle_left_press(press_pos)
	_handler.handle_mouse_motion(press_pos + Vector2(4.0, 0.0))

	var ended_tc := 0
	var ended_tr := 0
	_handler.drag_ended.connect(func(_sc: int, _sr: int, tc: int, tr: int) -> void:
		ended_tc = tc
		ended_tr = tr
	)

	# Act: release outside grid (way off-screen)
	_handler.handle_left_release(Vector2(-1000.0, -1000.0))

	# Assert: target is (-1, -1) indicating out of bounds
	assert_int(ended_tc).is_equal(-1)
	assert_int(ended_tr).is_equal(-1)


# ============================================================
# Drag Cancellation
# ============================================================

func test_drag_cancelled_via_right_click_during_dragging() -> void:
	# Arrange
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var press_pos := _board.grid_to_world(5, 5)
	_handler.handle_left_press(press_pos)
	_handler.handle_mouse_motion(press_pos + Vector2(10.0, 0.0))
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.DRAGGING as int)

	var cancelled := false
	_handler.drag_cancelled.connect(func() -> void:
		cancelled = true
	)

	# Act: right-click during drag
	_handler.handle_right_press(press_pos + Vector2(10.0, 0.0))

	# Assert
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)
	assert_bool(cancelled).is_true()


func test_drag_cancelled_via_right_click_during_pressing() -> void:
	# Arrange
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var press_pos := _board.grid_to_world(5, 5)
	_handler.handle_left_press(press_pos)
	# Still in PRESSING (no motion yet)

	var cancelled := false
	_handler.drag_cancelled.connect(func() -> void:
		cancelled = true
	)

	# Act: right-click during PRESSING (before drag confirmed)
	_handler.handle_right_press(press_pos)

	# Assert
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)
	assert_bool(cancelled).is_true()


func test_drag_cancelled_via_phase_change_to_battle() -> void:
	# Arrange
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var press_pos := _board.grid_to_world(5, 5)
	_handler.handle_left_press(press_pos)
	_handler.handle_mouse_motion(press_pos + Vector2(10.0, 0.0))
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.DRAGGING as int)

	var cancelled := false
	_handler.drag_cancelled.connect(func() -> void:
		cancelled = true
	)

	# Act: phase switches to BATTLE (wave starts) during drag
	_handler._on_phase_changed(InputHandler.PHASE_PREP, InputHandler.PHASE_BATTLE)

	# Assert
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)
	assert_bool(cancelled).is_true()


func test_drag_cancelled_via_phase_change_to_paused() -> void:
	# Arrange
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var press_pos := _board.grid_to_world(5, 5)
	_handler.handle_left_press(press_pos)
	_handler.handle_mouse_motion(press_pos + Vector2(10.0, 0.0))
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.DRAGGING as int)

	var cancelled := false
	_handler.drag_cancelled.connect(func() -> void:
		cancelled = true
	)

	# Act: phase switches to PAUSED during drag
	_handler._on_phase_changed(InputHandler.PHASE_PREP, InputHandler.PHASE_PAUSED)

	# Assert
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)
	assert_bool(cancelled).is_true()


# ============================================================
# Drag Threshold Boundary
# ============================================================

func test_drag_threshold_boundary_exactly_3px_is_still_click() -> void:
	# Arrange: the threshold check uses `>` not `>=`, so exactly 3px = click
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var press_pos := _board.grid_to_world(5, 5)
	_handler.handle_left_press(press_pos)

	# Act: move exactly 3px (threshold is 3.0, check is distance > threshold)
	_handler.handle_mouse_motion(press_pos + Vector2(3.0, 0.0))

	# Assert: 3.0 > 3.0 is false → stays PRESSING
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.PRESSING as int)


func test_drag_threshold_boundary_3_01px_is_drag() -> void:
	# Arrange
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var press_pos := _board.grid_to_world(5, 5)
	_handler.handle_left_press(press_pos)

	# Act: move 3.01px (just over threshold)
	_handler.handle_mouse_motion(press_pos + Vector2(3.01, 0.0))

	# Assert: 3.01 > 3.0 is true → DRAGGING
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.DRAGGING as int)


func test_drag_threshold_measured_2d_diagonal() -> void:
	# Arrange: threshold is Euclidean distance, not just horizontal
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var press_pos := _board.grid_to_world(5, 5)
	_handler.handle_left_press(press_pos)

	# Act: move diagonally — dx=2.2, dy=2.2 → distance = sqrt(2.2^2+2.2^2) ≈ 3.11 > 3.0
	_handler.handle_mouse_motion(press_pos + Vector2(2.2, 2.2))

	# Assert: diagonal distance exceeds threshold → DRAGGING
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.DRAGGING as int)


# ============================================================
# Non-draggable Cells
# ============================================================

func test_left_press_on_empty_cell_does_not_start_drag() -> void:
	var world_pos := _board.grid_to_world(10, 7)  # EMPTY cell
	_handler.handle_left_press(world_pos)
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)


func test_left_press_on_block_cell_does_not_start_drag() -> void:
	_board.set_cell_state(3, 3, BoardGrid.CellState.BLOCK)
	var world_pos := _board.grid_to_world(3, 3)
	_handler.handle_left_press(world_pos)
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)


func test_left_press_on_entrance_cell_does_not_start_drag() -> void:
	# (0, 0) is ENTRANCE from init()
	var world_pos := _board.grid_to_world(0, 0)
	_handler.handle_left_press(world_pos)
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)


func test_left_press_on_exit_cell_does_not_start_drag() -> void:
	# (19, 14) is EXIT from init()
	var world_pos := _board.grid_to_world(19, 14)
	_handler.handle_left_press(world_pos)
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)


func test_left_press_outside_grid_does_not_start_drag() -> void:
	_handler.handle_left_press(Vector2(-100.0, -100.0))
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)


# ============================================================
# Signal Integrity
# ============================================================

func test_grid_clicked_not_emitted_when_drag_is_confirmed() -> void:
	# When drag_threshold is exceeded, grid_clicked must NOT fire on release
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var press_pos := _board.grid_to_world(5, 5)
	_handler.handle_left_press(press_pos)
	_handler.handle_mouse_motion(press_pos + Vector2(10.0, 0.0))

	var clicked := false
	_handler.grid_clicked.connect(func(_c: int, _r: int) -> void:
		clicked = true
	)

	# Act: release after drag
	_handler.handle_left_release(press_pos + Vector2(10.0, 0.0))

	# Assert: grid_clicked NOT emitted — drag_ended was emitted instead
	assert_bool(clicked).is_false()


func test_drag_moved_emitted_during_drag() -> void:
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var press_pos := _board.grid_to_world(5, 5)
	_handler.handle_left_press(press_pos)
	_handler.handle_mouse_motion(press_pos + Vector2(4.0, 0.0))

	var moved_pos := Vector2.ZERO
	_handler.drag_moved.connect(func(pos: Vector2) -> void:
		moved_pos = pos
	)

	# Act: move further during drag
	var new_pos := press_pos + Vector2(15.0, 5.0)
	_handler.handle_mouse_motion(new_pos)

	# Assert
	assert_float(moved_pos.x).is_equal(new_pos.x)
	assert_float(moved_pos.y).is_equal(new_pos.y)


func test_drag_reset_clears_source_grid_to_negative_one() -> void:
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var press_pos := _board.grid_to_world(5, 5)
	_handler.handle_left_press(press_pos)
	_handler.handle_mouse_motion(press_pos + Vector2(10.0, 0.0))
	_handler.handle_left_release(press_pos + Vector2(10.0, 0.0))

	# After full drag cycle, source grid should be reset
	assert_int(_handler.drag_source_grid.x).is_equal(-1)
	assert_int(_handler.drag_source_grid.y).is_equal(-1)
	assert_float(_handler.drag_start_pos.x).is_equal(0.0)
	assert_float(_handler.drag_start_pos.y).is_equal(0.0)
