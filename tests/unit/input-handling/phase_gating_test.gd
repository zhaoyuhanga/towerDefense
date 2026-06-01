extends GdUnitTestSuite
## Phase gating unit tests for InputHandler.
##
## Verifies that board interactions are permitted during PREP and blocked
## during BATTLE/PAUSED. The InputHandler must enforce phase-appropriate
## input filtering before any drag state machine processing.
##
## Coverage targets:
##   - AC: 建造阶段左键点击 EMPTY 格 → 放置当前选中物
##   - AC: 战斗阶段左键点击棋盘格 → 无游戏动作发生
##   - AC: 战斗阶段左键点击可用应急技能按钮 → 技能被激活 (UI pass-through)
##   - AC: 建造阶段右键点击 BLOCK 格 → 方块被移除
##   - ADR-0007: 拖拽中阶段切换 → 强制取消
##   - ADR-0006: PREP ↔ BATTLE 门控


var _handler: InputHandler
var _board: BoardGrid


func before() -> void:
	_board = BoardGrid.new()
	_board.init(20, 15, Vector2i(0, 0), Vector2i(19, 14))
	_handler = InputHandler.new()
	_handler.set_board_grid(_board)


func after() -> void:
	_handler.free()
	_board.free()


# ============================================================
# PREP Phase — Allowed Actions
# ============================================================

func test_prep_allows_left_press_on_tower_enters_pressing() -> void:
	# Arrange
	_handler._current_phase = InputHandler.PHASE_PREP
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var world_pos := _board.grid_to_world(5, 5)

	# Act
	_handler.handle_left_press(world_pos)

	# Assert
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.PRESSING as int)


func test_prep_allows_left_release_for_click_on_tower() -> void:
	# Arrange
	_handler._current_phase = InputHandler.PHASE_PREP
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var world_pos := _board.grid_to_world(5, 5)
	_handler.handle_left_press(world_pos)

	var clicked_col := -1
	var clicked_row := -1
	_handler.grid_clicked.connect(func(c: int, r: int) -> void:
		clicked_col = c
		clicked_row = r
	)

	# Act: release without moving (click)
	_handler.handle_left_release(world_pos)

	# Assert: grid_clicked signal fires with correct cell
	assert_int(clicked_col).is_equal(5)
	assert_int(clicked_row).is_equal(5)


func test_prep_allows_right_press_on_block_emits_grid_right_clicked() -> void:
	# Arrange
	_handler._current_phase = InputHandler.PHASE_PREP
	_board.set_cell_state(8, 8, BoardGrid.CellState.BLOCK)
	var world_pos := _board.grid_to_world(8, 8)

	var rc_col := -1
	var rc_row := -1
	_handler.grid_right_clicked.connect(func(c: int, r: int) -> void:
		rc_col = c
		rc_row = r
	)

	# Act
	_handler.handle_right_press(world_pos)

	# Assert
	assert_int(rc_col).is_equal(8)
	assert_int(rc_row).is_equal(8)


func test_prep_allows_right_press_on_tower_emits_grid_right_clicked() -> void:
	# Arrange
	_handler._current_phase = InputHandler.PHASE_PREP
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var world_pos := _board.grid_to_world(5, 5)

	var rc_col := -1
	var rc_row := -1
	_handler.grid_right_clicked.connect(func(c: int, r: int) -> void:
		rc_col = c
		rc_row = r
	)

	# Act
	_handler.handle_right_press(world_pos)

	# Assert
	assert_int(rc_col).is_equal(5)
	assert_int(rc_row).is_equal(5)


func test_prep_allows_full_drag_cycle_tower_to_tower() -> void:
	# Arrange
	_handler._current_phase = InputHandler.PHASE_PREP
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	_board.set_cell_state(10, 7, BoardGrid.CellState.TOWER)

	var press_pos := _board.grid_to_world(5, 5)
	_handler.handle_left_press(press_pos)
	_handler.handle_mouse_motion(press_pos + Vector2(4.0, 0.0))

	var ended_tc := -1
	var ended_tr := -1
	_handler.drag_ended.connect(func(_sc: int, _sr: int, tc: int, tr: int) -> void:
		ended_tc = tc
		ended_tr = tr
	)

	# Act: drag and release over target
	var release_pos := _board.grid_to_world(10, 7)
	_handler.handle_left_release(release_pos)

	# Assert
	assert_int(ended_tc).is_equal(10)
	assert_int(ended_tr).is_equal(7)


# ============================================================
# BATTLE Phase — Blocked Actions
# ============================================================

func test_battle_blocks_left_press_on_tower() -> void:
	# Arrange
	_handler._current_phase = InputHandler.PHASE_BATTLE
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var world_pos := _board.grid_to_world(5, 5)

	# Act
	_handler.handle_left_press(world_pos)

	# Assert: stays IDLE — BATTLE blocks all board interaction
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)


func test_battle_blocks_left_press_on_empty() -> void:
	# Arrange
	_handler._current_phase = InputHandler.PHASE_BATTLE
	var world_pos := _board.grid_to_world(10, 7)  # EMPTY cell

	# Track whether any left-press processing occurred beyond the phase gate
	var clicked := false
	_handler.grid_clicked.connect(func(_c: int, _r: int) -> void:
		clicked = true
	)

	# Act
	_handler.handle_left_press(world_pos)

	# Assert: no state change, no signal emitted
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)
	assert_bool(clicked).is_false()


func test_battle_blocks_right_press_on_block() -> void:
	# Arrange
	_handler._current_phase = InputHandler.PHASE_BATTLE
	_board.set_cell_state(8, 8, BoardGrid.CellState.BLOCK)
	var world_pos := _board.grid_to_world(8, 8)

	var right_clicked := false
	_handler.grid_right_clicked.connect(func(_c: int, _r: int) -> void:
		right_clicked = true
	)

	# Act
	_handler.handle_right_press(world_pos)

	# Assert: signal NOT emitted — BATTLE blocks
	assert_bool(right_clicked).is_false()


func test_battle_blocks_right_press_on_tower() -> void:
	# Arrange
	_handler._current_phase = InputHandler.PHASE_BATTLE
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var world_pos := _board.grid_to_world(5, 5)

	var right_clicked := false
	_handler.grid_right_clicked.connect(func(_c: int, _r: int) -> void:
		right_clicked = true
	)

	# Act
	_handler.handle_right_press(world_pos)

	# Assert: sell/remove not possible in BATTLE
	assert_bool(right_clicked).is_false()


func test_battle_blocks_left_press_on_block() -> void:
	# Arrange
	_handler._current_phase = InputHandler.PHASE_BATTLE
	_board.set_cell_state(3, 3, BoardGrid.CellState.BLOCK)
	var world_pos := _board.grid_to_world(3, 3)

	var clicked := false
	_handler.grid_clicked.connect(func(_c: int, _r: int) -> void:
		clicked = true
	)

	# Act
	_handler.handle_left_press(world_pos)
	# Even though BLOCK doesn't start drag, release could still emit grid_clicked
	_handler.handle_left_release(world_pos)

	# Assert: no click signal — phase gate blocks before cell-type check
	assert_bool(clicked).is_false()


# ============================================================
# PAUSED Phase — Blocked Actions
# ============================================================

func test_paused_blocks_left_press_on_tower() -> void:
	# Arrange
	_handler._current_phase = InputHandler.PHASE_PAUSED
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var world_pos := _board.grid_to_world(5, 5)

	# Act
	_handler.handle_left_press(world_pos)

	# Assert
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)


func test_paused_blocks_right_press_on_block() -> void:
	# Arrange
	_handler._current_phase = InputHandler.PHASE_PAUSED
	_board.set_cell_state(8, 8, BoardGrid.CellState.BLOCK)
	var world_pos := _board.grid_to_world(8, 8)

	var right_clicked := false
	_handler.grid_right_clicked.connect(func(_c: int, _r: int) -> void:
		right_clicked = true
	)

	# Act
	_handler.handle_right_press(world_pos)

	# Assert
	assert_bool(right_clicked).is_false()


# ============================================================
# Phase Transitions — Re-enable and Cancel
# ============================================================

func test_phase_switch_battle_to_prep_re_enables_input() -> void:
	# Arrange: start in BATTLE — input blocked
	_handler._current_phase = InputHandler.PHASE_BATTLE
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var world_pos := _board.grid_to_world(5, 5)

	_handler.handle_left_press(world_pos)
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)

	# Act: phase switches to PREP (wave ends)
	_handler._on_phase_changed(InputHandler.PHASE_BATTLE, InputHandler.PHASE_PREP)

	# Now input should work
	_handler.handle_left_press(world_pos)

	# Assert
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.PRESSING as int)


func test_phase_switch_prep_to_battle_disables_input() -> void:
	# Arrange: start in PREP — input works
	_handler._current_phase = InputHandler.PHASE_PREP
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var world_pos := _board.grid_to_world(5, 5)

	_handler.handle_left_press(world_pos)
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.PRESSING as int)

	# Reset for clean test
	_handler.drag_state = InputHandler.DragState.IDLE

	# Act: phase switches to BATTLE (wave starts)
	_handler._on_phase_changed(InputHandler.PHASE_PREP, InputHandler.PHASE_BATTLE)

	# Now input should be blocked
	_handler.handle_left_press(world_pos)

	# Assert
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)


func test_phase_switch_to_battle_cancels_active_drag() -> void:
	# Arrange: drag in progress during PREP
	_handler._current_phase = InputHandler.PHASE_PREP
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var press_pos := _board.grid_to_world(5, 5)

	_handler.handle_left_press(press_pos)
	_handler.handle_mouse_motion(press_pos + Vector2(10.0, 0.0))
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.DRAGGING as int)

	var cancelled := false
	_handler.drag_cancelled.connect(func() -> void:
		cancelled = true
	)

	# Act: phase switches to BATTLE mid-drag
	_handler._on_phase_changed(InputHandler.PHASE_PREP, InputHandler.PHASE_BATTLE)

	# Assert: drag cancelled, state reset
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)
	assert_bool(cancelled).is_true()


func test_phase_switch_to_paused_cancels_active_drag() -> void:
	# Arrange
	_handler._current_phase = InputHandler.PHASE_PREP
	_board.set_cell_state(5, 5, BoardGrid.CellState.TOWER)
	var press_pos := _board.grid_to_world(5, 5)

	_handler.handle_left_press(press_pos)
	_handler.handle_mouse_motion(press_pos + Vector2(10.0, 0.0))
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.DRAGGING as int)

	var cancelled := false
	_handler.drag_cancelled.connect(func() -> void:
		cancelled = true
	)

	# Act: phase switches to PAUSED mid-drag
	_handler._on_phase_changed(InputHandler.PHASE_PREP, InputHandler.PHASE_PAUSED)

	# Assert
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)
	assert_bool(cancelled).is_true()


# ============================================================
# Initial State
# ============================================================

func test_default_phase_is_prep() -> void:
	assert_int(_handler.get_current_phase()).is_equal(InputHandler.PHASE_PREP)


func test_default_drag_state_is_idle() -> void:
	assert_int(_handler.drag_state as int).is_equal(InputHandler.DragState.IDLE as int)
	assert_bool(_handler.is_dragging()).is_false()


# ============================================================
# Right-Press Edge Cases
# ============================================================

func test_prep_right_press_outside_grid_emits_negative_one() -> void:
	# Arrange
	_handler._current_phase = InputHandler.PHASE_PREP

	var rc_col := 0
	var rc_row := 0
	_handler.grid_right_clicked.connect(func(c: int, r: int) -> void:
		rc_col = c
		rc_row = r
	)

	# Act: click way outside the grid
	_handler.handle_right_press(Vector2(-500.0, -500.0))

	# Assert: (-1, -1) signals "cancel selection"
	assert_int(rc_col).is_equal(-1)
	assert_int(rc_row).is_equal(-1)


func test_prep_right_press_on_empty_cell_emits_negative_one() -> void:
	# Arrange: EMPTY cell → right-click = cancel selection
	_handler._current_phase = InputHandler.PHASE_PREP
	var world_pos := _board.grid_to_world(10, 7)  # EMPTY

	var rc_col := 0
	var rc_row := 0
	_handler.grid_right_clicked.connect(func(c: int, r: int) -> void:
		rc_col = c
		rc_row = r
	)

	# Act
	_handler.handle_right_press(world_pos)

	# Assert: EMPTY right-click = cancel selection
	assert_int(rc_col).is_equal(-1)
	assert_int(rc_row).is_equal(-1)


func test_prep_right_press_on_entrance_emits_negative_one() -> void:
	# Arrange: ENTRANCE at (0, 0) — immutable, right-click = cancel selection
	_handler._current_phase = InputHandler.PHASE_PREP
	var world_pos := _board.grid_to_world(0, 0)

	var rc_col := 0
	var rc_row := 0
	_handler.grid_right_clicked.connect(func(c: int, r: int) -> void:
		rc_col = c
		rc_row = r
	)

	# Act
	_handler.handle_right_press(world_pos)

	# Assert
	assert_int(rc_col).is_equal(-1)
	assert_int(rc_row).is_equal(-1)


# ============================================================
# get_current_phase Reflection
# ============================================================

func test_get_current_phase_reflects_last_phase_change() -> void:
	_handler._on_phase_changed(InputHandler.PHASE_PREP, InputHandler.PHASE_BATTLE)
	assert_int(_handler.get_current_phase()).is_equal(InputHandler.PHASE_BATTLE)

	_handler._on_phase_changed(InputHandler.PHASE_BATTLE, InputHandler.PHASE_PREP)
	assert_int(_handler.get_current_phase()).is_equal(InputHandler.PHASE_PREP)
