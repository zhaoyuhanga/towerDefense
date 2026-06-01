extends GdUnitTestSuite
## ObstacleBlock unit tests — placement, removal, gold tracking, block limits,
## phase gating, path validation, config override, and signal emission.
##
## Each test gets a fresh BoardGrid (added as child so _ready() fires and
## builds the transition table), Pathfinding, and ObstacleBlock.
##
## Dependencies: BoardGrid, Pathfinding, EconomyConfig, SignalBus (optional).

const COLS := 20
const ROWS := 15
const ENTRANCE := Vector2i(0, 7)
const EXIT := Vector2i(19, 7)
const STARTING_GOLD := 200

var _board: BoardGrid
var _pathfinding: Pathfinding
var _obstacle: ObstacleBlock

# Signal capture state
var _gold_changed_received: bool = false
var _received_gold: int = 0
var _block_count_changed_received: bool = false
var _received_remaining: int = 0


func before() -> void:
	# Create and initialize BoardGrid (add_child triggers _ready() for transition table)
	_board = BoardGrid.new()
	_board.init(COLS, ROWS, ENTRANCE, EXIT)
	add_child(_board)

	# Create and initialize Pathfinding
	_pathfinding = Pathfinding.new()
	_pathfinding.init(_board)

	# Create and initialize ObstacleBlock
	_obstacle = ObstacleBlock.new()
	_obstacle.initialize(_board, _pathfinding, STARTING_GOLD)

	# Reset signal capture state
	_gold_changed_received = false
	_received_gold = 0
	_block_count_changed_received = false
	_received_remaining = 0


func after() -> void:
	if _obstacle != null:
		_obstacle.free()
		_obstacle = null
	if _pathfinding != null:
		_pathfinding.free()
		_pathfinding = null
	if _board != null:
		remove_child(_board)
		_board.free()
		_board = null


# ── Signal capture helpers ─────────────────────────────────────────────────────

func _on_gold_changed(current_gold: int) -> void:
	_gold_changed_received = true
	_received_gold = current_gold


func _on_block_count_changed(remaining: int) -> void:
	_block_count_changed_received = true
	_received_remaining = remaining


# ═══════════════════════════════════════════════════════════════════════════════
# Test 1: Place block on empty cell succeeds
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_place_block_on_empty_cell_succeeds() -> void:
	# Arrange: cell (10, 7) is EMPTY on a fresh board with a straight-line path

	# Act
	var result := _obstacle.place_block(10, 7)

	# Assert
	assert_bool(result).is_true()
	assert_int(_board.get_cell_state(10, 7) as int).is_equal(BoardGrid.CellState.BLOCK as int)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 2: Place block deducts gold
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_place_block_deducts_gold() -> void:
	# Arrange
	var starting := _obstacle.get_gold()

	# Act
	_obstacle.place_block(10, 7)

	# Assert
	assert_int(_obstacle.get_gold()).is_equal(starting - _obstacle.BLOCK_COST)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 3: Place block increments block count
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_place_block_increments_block_count() -> void:
	# Arrange
	assert_int(_obstacle.get_block_count()).is_equal(0)

	# Act
	_obstacle.place_block(10, 7)

	# Assert
	assert_int(_obstacle.get_block_count()).is_equal(1)
	assert_int(_obstacle.get_remaining_blocks()).is_equal(_obstacle.MAX_BLOCKS - 1)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 4: Remove block restores cell to EMPTY
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_remove_block_restores_cell_to_empty() -> void:
	# Arrange
	_obstacle.place_block(10, 7)
	assert_int(_board.get_cell_state(10, 7) as int).is_equal(BoardGrid.CellState.BLOCK as int)

	# Act
	var result := _obstacle.remove_block(10, 7)

	# Assert
	assert_bool(result).is_true()
	assert_int(_board.get_cell_state(10, 7) as int).is_equal(BoardGrid.CellState.EMPTY as int)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 5: Remove block refunds sell value
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_remove_block_refunds_sell_value() -> void:
	# Arrange
	_obstacle.place_block(10, 7)
	var gold_after_place := _obstacle.get_gold()

	# Act
	_obstacle.remove_block(10, 7)

	# Assert
	assert_int(_obstacle.get_gold()).is_equal(gold_after_place + _obstacle.BLOCK_SELL_VALUE)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 6: Place block at max blocks fails
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_place_block_at_max_blocks_fails() -> void:
	# Arrange: fill to MAX_BLOCKS (GDD default = 10) on row 7, cols 1-10
	for col in range(1, _obstacle.MAX_BLOCKS + 1):
		_obstacle.place_block(col, 7)
	assert_int(_obstacle.get_block_count()).is_equal(_obstacle.MAX_BLOCKS)

	# Act: try one more
	var result := _obstacle.place_block(11, 7)

	# Assert
	assert_bool(result).is_false()
	assert_int(_obstacle.get_block_count()).is_equal(_obstacle.MAX_BLOCKS)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 7: Place block with insufficient gold fails
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_place_block_with_insufficient_gold_fails() -> void:
	# Arrange: set gold below BLOCK_COST
	_obstacle.set_gold(_obstacle.BLOCK_COST - 1)

	# Act
	var result := _obstacle.place_block(10, 7)

	# Assert
	assert_bool(result).is_false()
	assert_int(_board.get_cell_state(10, 7) as int).is_equal(BoardGrid.CellState.EMPTY as int)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 8: Place block on occupied cell fails
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_place_block_on_occupied_cell_fails() -> void:
	# Arrange: already placed a block
	_obstacle.place_block(10, 7)
	assert_int(_board.get_cell_state(10, 7) as int).is_equal(BoardGrid.CellState.BLOCK as int)

	# Act: try to place on same cell
	var result := _obstacle.place_block(10, 7)

	# Assert
	assert_bool(result).is_false()


# ═══════════════════════════════════════════════════════════════════════════════
# Test 9: Place block that would dead-end the board fails
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_place_block_that_would_block_path_fails() -> void:
	# Arrange: place blocks to create a 1-wide corridor at row 7, col 10
	# Block all of row 7 from col=1 to col=9 except the straight path
	# Actually, block all cells in column 10 except (10, 7) — the straight path
	# Then block everything above and below to narrow to a single cell
	# Wait, let me think more carefully.

	# Strategy: block rows 0-6 and 8-14 at column 10,
	# leaving only (10, 7) as the sole passage through column 10.
	# Then trying to block (10, 7) would dead-end the board.
	for row in range(ROWS):
		if row == 7:
			continue  # Keep the passage open at (10, 7)
		_board.set_cell_state(10, row, BoardGrid.CellState.BLOCK)

	# Also seal column 9 and 11 vertically to ensure no bypass
	for row in range(ROWS):
		if row == 7:
			continue
		_board.set_cell_state(9, row, BoardGrid.CellState.BLOCK)
		_board.set_cell_state(11, row, BoardGrid.CellState.BLOCK)

	# Now (10, 7) is the critical chokepoint — blocking it should fail
	var result := _obstacle.place_block(10, 7)

	# Assert: placement rejected because it would dead-end the board
	assert_bool(result).is_false()
	assert_int(_board.get_cell_state(10, 7) as int).is_equal(BoardGrid.CellState.EMPTY as int)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 10: Place block during BATTLE phase fails
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_place_block_during_battle_fails() -> void:
	# Arrange: switch to BATTLE phase
	_obstacle._current_phase = ObstacleBlock.PHASE_BATTLE

	# Act
	var result := _obstacle.place_block(10, 7)

	# Assert
	assert_bool(result).is_false()
	assert_int(_board.get_cell_state(10, 7) as int).is_equal(BoardGrid.CellState.EMPTY as int)

	# Restore
	_obstacle._current_phase = ObstacleBlock.PHASE_PREP


# ═══════════════════════════════════════════════════════════════════════════════
# Test 11: Remove block during BATTLE phase fails
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_remove_block_during_battle_fails() -> void:
	# Arrange: place a block during PREP
	_obstacle.place_block(10, 7)
	assert_int(_board.get_cell_state(10, 7) as int).is_equal(BoardGrid.CellState.BLOCK as int)

	# Switch to BATTLE phase
	_obstacle._current_phase = ObstacleBlock.PHASE_BATTLE

	# Act: try to remove
	var result := _obstacle.remove_block(10, 7)

	# Assert: removal rejected, block still there
	assert_bool(result).is_false()
	assert_int(_board.get_cell_state(10, 7) as int).is_equal(BoardGrid.CellState.BLOCK as int)

	# Restore
	_obstacle._current_phase = ObstacleBlock.PHASE_PREP


# ═══════════════════════════════════════════════════════════════════════════════
# Test 12: EconomyConfig overrides GDD defaults
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_economy_config_overrides_defaults() -> void:
	# Arrange: create config with custom values
	var config := EconomyConfig.new()
	config.BLOCK_COST = 50
	config.BLOCK_SELL_VALUE = 25
	config.MAX_BLOCKS = 5

	var obstacle := ObstacleBlock.new()
	obstacle.initialize(_board, _pathfinding, STARTING_GOLD, config)

	# Assert: defaults are overridden
	assert_int(obstacle.BLOCK_COST).is_equal(50)
	assert_int(obstacle.BLOCK_SELL_VALUE).is_equal(25)
	assert_int(obstacle.MAX_BLOCKS).is_equal(5)

	# Verify override is effective: place one block at custom cost
	var starting := obstacle.get_gold()
	obstacle.place_block(10, 7)
	assert_int(obstacle.get_gold()).is_equal(starting - 50)

	# Cleanup
	obstacle.free()


# ═══════════════════════════════════════════════════════════════════════════════
# Test 13: Defaults used when no EconomyConfig provided
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_defaults_used_when_no_config_provided() -> void:
	# Assert: GDD-authoritative defaults are active
	assert_int(_obstacle.BLOCK_COST).is_equal(25)
	assert_int(_obstacle.BLOCK_SELL_VALUE).is_equal(10)
	assert_int(_obstacle.MAX_BLOCKS).is_equal(10)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 14: Place block on ENTRANCE position fails
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_place_block_on_entrance_fails() -> void:
	# ENTRANCE is at (0, 7) — not EMPTY, so EMPTY guard should reject
	var result := _obstacle.place_block(ENTRANCE.x, ENTRANCE.y)
	assert_bool(result).is_false()


# ═══════════════════════════════════════════════════════════════════════════════
# Test 15: Place block on EXIT position fails
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_place_block_on_exit_fails() -> void:
	# EXIT is at (19, 7) — not EMPTY, so EMPTY guard should reject
	var result := _obstacle.place_block(EXIT.x, EXIT.y)
	assert_bool(result).is_false()


# ═══════════════════════════════════════════════════════════════════════════════
# Test 16: Remove block from non-block cell fails
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_remove_block_from_non_block_cell_fails() -> void:
	# Arrange: cell is EMPTY
	assert_int(_board.get_cell_state(10, 7) as int).is_equal(BoardGrid.CellState.EMPTY as int)

	# Act
	var result := _obstacle.remove_block(10, 7)

	# Assert
	assert_bool(result).is_false()


# ═══════════════════════════════════════════════════════════════════════════════
# Test 17: Remove block decrements block count
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_remove_block_decrements_block_count() -> void:
	# Arrange: place two blocks
	_obstacle.place_block(10, 7)
	_obstacle.place_block(11, 7)
	assert_int(_obstacle.get_block_count()).is_equal(2)

	# Act: remove one
	_obstacle.remove_block(10, 7)

	# Assert
	assert_int(_obstacle.get_block_count()).is_equal(1)
	assert_int(_obstacle.get_remaining_blocks()).is_equal(_obstacle.MAX_BLOCKS - 1)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 18: Place block out of bounds fails
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_place_block_out_of_bounds_fails() -> void:
	var result := _obstacle.place_block(-1, 7)
	assert_bool(result).is_false()

	result = _obstacle.place_block(COLS, 7)
	assert_bool(result).is_false()

	result = _obstacle.place_block(10, -1)
	assert_bool(result).is_false()

	result = _obstacle.place_block(10, ROWS)
	assert_bool(result).is_false()


# ═══════════════════════════════════════════════════════════════════════════════
# Test 19: Multiple place-remove cycles maintain correct state
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_multiple_place_remove_cycles_maintain_state() -> void:
	var starting_gold := _obstacle.get_gold()

	# Place 3 blocks
	_obstacle.place_block(10, 7)
	_obstacle.place_block(11, 7)
	_obstacle.place_block(12, 7)
	assert_int(_obstacle.get_block_count()).is_equal(3)
	assert_int(_obstacle.get_gold()).is_equal(starting_gold - 3 * _obstacle.BLOCK_COST)

	# Remove 2 blocks
	_obstacle.remove_block(10, 7)
	_obstacle.remove_block(11, 7)
	assert_int(_obstacle.get_block_count()).is_equal(1)
	assert_int(_obstacle.get_gold()).is_equal(
		starting_gold - 3 * _obstacle.BLOCK_COST + 2 * _obstacle.BLOCK_SELL_VALUE
	)

	# Place 1 more
	_obstacle.place_block(13, 7)
	assert_int(_obstacle.get_block_count()).is_equal(2)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 20: set_gold clamps to zero
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_set_gold_clamps_to_zero() -> void:
	_obstacle.set_gold(-50)
	assert_int(_obstacle.get_gold()).is_equal(0)

	_obstacle.set_gold(100)
	assert_int(_obstacle.get_gold()).is_equal(100)


# ═══════════════════════════════════════════════════════════════════════════════
# Test 21: Cannot lose gold by removing block that was never placed
# ═══════════════════════════════════════════════════════════════════════════════

func test_obstacle_block_block_count_never_goes_negative() -> void:
	# Attempt to remove from EMPTY — should fail
	var result := _obstacle.remove_block(10, 7)
	assert_bool(result).is_false()

	# Block count should still be 0
	# NOTE: block_count is not decremented on failed removal,
	# but if a bug causes decrement, this catches it
	assert_int(_obstacle.get_block_count()).is_equal(0)
