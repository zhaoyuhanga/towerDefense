extends GdUnitTestSuite
## Coordinate system tests: grid_to_world, world_to_grid, get_neighbors
## Tests pure math — does not require _ready() or viewport. Origin and
## cell_size are injected directly for deterministic results.

var _board: BoardGrid


func before() -> void:
	_board = BoardGrid.new()
	_board.cell_size = 64
	_board.origin = Vector2(100.0, 50.0)
	_board.init(20, 15, Vector2i(0, 0), Vector2i(19, 14))


func after() -> void:
	_board.free()


# ── grid_to_world ────────────────────────────────────────────────────────────

func test_grid_to_world_origin_cell_returns_center() -> void:
	# Arrange: origin (100, 50), cell_size 64
	# Cell (0,0) center = (100 + 0*64 + 32, 50 + 0*64 + 32) = (132, 82)
	var expected := Vector2(132.0, 82.0)

	# Act
	var result := _board.grid_to_world(0, 0)

	# Assert
	assert_float(result.x).is_equal(expected.x)
	assert_float(result.y).is_equal(expected.y)


func test_grid_to_world_far_cell_returns_correct_center() -> void:
	# Arrange: cell (19, 14) → (100 + 19*64 + 32, 50 + 14*64 + 32) = (1348, 978)
	var expected := Vector2(1348.0, 978.0)

	# Act
	var result := _board.grid_to_world(19, 14)

	# Assert
	assert_float(result.x).is_equal(expected.x)
	assert_float(result.y).is_equal(expected.y)


func test_grid_to_world_mid_cell_returns_center() -> void:
	# Arrange: cell (10, 7) → (100 + 10*64 + 32, 50 + 7*64 + 32) = (772, 530)
	var expected := Vector2(772.0, 530.0)

	# Act
	var result := _board.grid_to_world(10, 7)

	# Assert
	assert_float(result.x).is_equal(expected.x)
	assert_float(result.y).is_equal(expected.y)


# ── world_to_grid ────────────────────────────────────────────────────────────

func test_world_to_grid_returns_correct_cell() -> void:
	# Arrange: center of cell (5, 5) → (100 + 5*64 + 32, 50 + 5*64 + 32) = (452, 402)
	var world_pos := Vector2(452.0, 402.0)

	# Act
	var result := _board.world_to_grid(world_pos)

	# Assert
	assert_int(result.x).is_equal(5)
	assert_int(result.y).is_equal(5)


func test_world_to_grid_top_left_corner_of_cell_still_that_cell() -> void:
	# Arrange: top-left corner of cell (5, 5) → (100 + 5*64, 50 + 5*64) = (420, 370)
	var world_pos := Vector2(420.0, 370.0)

	# Act
	var result := _board.world_to_grid(world_pos)

	# Assert: int(floor(320/64)) = int(5.0) = 5
	assert_int(result.x).is_equal(5)
	assert_int(result.y).is_equal(5)


func test_world_to_grid_bottom_right_edge_maps_to_cell() -> void:
	# Arrange: just inside bottom-right of cell (5, 5)
	# bottom-right pixel of cell (5, 5) exclusive would be (100+6*64, 50+6*64) = (484, 434)
	# One pixel inside = (483, 433) → col=floor(383/64)=5, row=floor(383/64)=5
	var world_pos := Vector2(483.0, 433.0)

	# Act
	var result := _board.world_to_grid(world_pos)

	# Assert
	assert_int(result.x).is_equal(5)
	assert_int(result.y).is_equal(5)


func test_world_to_grid_out_of_bounds_negative_returns_negative() -> void:
	var result := _board.world_to_grid(Vector2(-100.0, -100.0))
	assert_int(result.x).is_equal(-1)
	assert_int(result.y).is_equal(-1)


func test_world_to_grid_beyond_positive_bounds_returns_negative() -> void:
	var result := _board.world_to_grid(Vector2(9999.0, 9999.0))
	assert_int(result.x).is_equal(-1)
	assert_int(result.y).is_equal(-1)


# ── get_neighbors ────────────────────────────────────────────────────────────

func test_get_neighbors_top_left_corner_returns_two() -> void:
	var neighbors := _board.get_neighbors(0, 0)
	assert_int(neighbors.size()).is_equal(2)
	# Should be (1, 0) and (0, 1) — east and south
	var has_east := false
	var has_south := false
	for n in neighbors:
		if n == Vector2i(1, 0):
			has_east = true
		if n == Vector2i(0, 1):
			has_south = true
	assert_bool(has_east).is_true()
	assert_bool(has_south).is_true()


func test_get_neighbors_bottom_right_corner_returns_two() -> void:
	var neighbors := _board.get_neighbors(19, 14)
	assert_int(neighbors.size()).is_equal(2)
	# Should be (18, 14) and (19, 13) — west and north
	var has_west := false
	var has_north := false
	for n in neighbors:
		if n == Vector2i(18, 14):
			has_west = true
		if n == Vector2i(19, 13):
			has_north = true
	assert_bool(has_west).is_true()
	assert_bool(has_north).is_true()


func test_get_neighbors_interior_cell_returns_four() -> void:
	var neighbors := _board.get_neighbors(10, 7)
	assert_int(neighbors.size()).is_equal(4)
	# Verify all four directions present
	var dirs_found := 0
	for n in neighbors:
		if n == Vector2i(10, 6) or n == Vector2i(10, 8) or n == Vector2i(11, 7) or n == Vector2i(9, 7):
			dirs_found += 1
	assert_int(dirs_found).is_equal(4)


func test_get_neighbors_top_edge_returns_three_and_no_north() -> void:
	var neighbors := _board.get_neighbors(10, 0)
	assert_int(neighbors.size()).is_equal(3)
	var has_north := false
	for n in neighbors:
		if n == Vector2i(10, -1):
			has_north = true
	assert_bool(has_north).is_false()


func test_get_neighbors_bottom_edge_returns_three_and_no_south() -> void:
	var neighbors := _board.get_neighbors(10, 14)
	assert_int(neighbors.size()).is_equal(3)
	var has_south := false
	for n in neighbors:
		if n == Vector2i(10, 15):
			has_south = true
	assert_bool(has_south).is_false()


func test_get_neighbors_left_edge_returns_three_and_no_west() -> void:
	var neighbors := _board.get_neighbors(0, 7)
	assert_int(neighbors.size()).is_equal(3)
	var has_west := false
	for n in neighbors:
		if n == Vector2i(-1, 7):
			has_west = true
	assert_bool(has_west).is_false()


func test_get_neighbors_right_edge_returns_three_and_no_east() -> void:
	var neighbors := _board.get_neighbors(19, 7)
	assert_int(neighbors.size()).is_equal(3)
	var has_east := false
	for n in neighbors:
		if n == Vector2i(20, 7):
			has_east = true
	assert_bool(has_east).is_false()


# ── roundtrip ────────────────────────────────────────────────────────────────

func test_grid_to_world_to_grid_roundtrip() -> void:
	# grid → world → grid should recover original grid coordinates
	var original_col := 7
	var original_row := 3
	var world := _board.grid_to_world(original_col, original_row)
	var grid := _board.world_to_grid(world)
	assert_int(grid.x).is_equal(original_col)
	assert_int(grid.y).is_equal(original_row)


func test_grid_to_world_to_grid_roundtrip_multiple_cells() -> void:
	var test_cells := [
		Vector2i(0, 0),
		Vector2i(19, 14),
		Vector2i(10, 7),
		Vector2i(0, 14),
		Vector2i(19, 0),
	]
	for cell in test_cells:
		var world := _board.grid_to_world(cell.x, cell.y)
		var grid := _board.world_to_grid(world)
		assert_int(grid.x).is_equal(cell.x)
		assert_int(grid.y).is_equal(cell.y)
