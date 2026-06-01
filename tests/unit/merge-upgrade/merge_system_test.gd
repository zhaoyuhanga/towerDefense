extends GdUnitTestSuite
## Unit tests for MergeSystem.
## Implements acceptance criteria from design/gdd/merge-upgrade.md.
## Architecture: docs/architecture/adr-0007-drag-merge-input.md
##
## Covers:
##   - try_merge validation (same type/star, star < 3, missing towers, self-merge)
##   - merge cost deduction and affordability gating
##   - Phase gating (only PREP phase allows merge)
##   - can_merge query (pure validation, no side effects)
##   - Drag state lifecycle (start_drag → update_drag_preview → cancel_drag)
##   - Drag cancellation on phase switch (PREP → BATTLE)
##   - Game reset (cancel_all + phase reset per ADR-0008)
##   - Signal emissions (merge_completed + merge_failed via SignalBus)


# ── Test Fixtures ────────────────────────────────────────────────────────────────

var _merge_system: MergeSystem
var _tower_system: TowerSystem
var _board: BoardGrid
var _economy: EconomySystem
var _config: EconomyConfig

## Signal tracking arrays
var _merge_completed_signals: Array = []   # [{from_star, to_star, position}]
var _merge_failed_signals: Array = []      # [reason_string, ...]
var _phase_changed_signals: Array = []     # [{old, new}]


# ── Test Data: TowerData resources (in-memory, no file I/O) ──────────────────────

## Pre-built TowerData for cannon_1, cannon_2, cannon_3, ice_1, ice_2, ice_3
var _td_cannon_1: TowerData
var _td_cannon_2: TowerData
var _td_cannon_3: TowerData
var _td_ice_1: TowerData
var _td_ice_2: TowerData
var _td_ice_3: TowerData


func before() -> void:
	# ── Create TowerData resources ────────────────────────────────────────────
	_td_cannon_1 = _build_tower_data("cannon", 1, 20.0, 10, 5)
	_td_cannon_2 = _build_tower_data("cannon", 2, 40.0, 0, 0)
	_td_cannon_3 = _build_tower_data("cannon", 3, 80.0, 0, 0)
	_td_ice_1    = _build_tower_data("ice", 1, 15.0, 10, 5)
	_td_ice_2    = _build_tower_data("ice", 2, 30.0, 0, 0)
	_td_ice_3    = _build_tower_data("ice", 3, 60.0, 0, 0)

	# ── BoardGrid ─────────────────────────────────────────────────────────────
	_board = BoardGrid.new()
	_board.init(20, 15, Vector2i(0, 0), Vector2i(19, 14))

	# ── TowerSystem (MonsterPool not needed for merge tests — pass null) ──────
	_tower_system = TowerSystem.new()
	_tower_system.init(_board, null)

	# Pre-populate tower data cache to avoid file I/O in place_tower()
	_tower_system._tower_data_cache["cannon_1"] = _td_cannon_1
	_tower_system._tower_data_cache["cannon_2"] = _td_cannon_2
	_tower_system._tower_data_cache["cannon_3"] = _td_cannon_3
	_tower_system._tower_data_cache["ice_1"]    = _td_ice_1
	_tower_system._tower_data_cache["ice_2"]    = _td_ice_2
	_tower_system._tower_data_cache["ice_3"]    = _td_ice_3

	# ── EconomySystem + EconomyConfig ─────────────────────────────────────────
	_config = EconomyConfig.new()
	_config.starting_gold = 200
	_config.MERGE_COST = 0
	_config.BLOCK_COST = 10
	_config.BLOCK_SELL_VALUE = 5
	_config.kill_reward_multiplier = 1.0

	_economy = EconomySystem.new()
	_economy.init(_config)

	# ── MergeSystem ───────────────────────────────────────────────────────────
	_merge_system = MergeSystem.new()
	_merge_system.init(_tower_system, _board, _economy, _config)

	# ── Signal Tracking ───────────────────────────────────────────────────────
	_merge_completed_signals.clear()
	_merge_failed_signals.clear()
	_phase_changed_signals.clear()

	if has_node("/root/SignalBus"):
		if not SignalBus.merge_completed.is_connected(_track_merge_completed):
			SignalBus.merge_completed.connect(_track_merge_completed)
		if not SignalBus.merge_failed.is_connected(_track_merge_failed):
			SignalBus.merge_failed.connect(_track_merge_failed)
		if not SignalBus.phase_changed.is_connected(_track_phase_changed):
			SignalBus.phase_changed.connect(_track_phase_changed)


func after() -> void:
	# Disconnect signal trackers
	if has_node("/root/SignalBus"):
		if SignalBus.merge_completed.is_connected(_track_merge_completed):
			SignalBus.merge_completed.disconnect(_track_merge_completed)
		if SignalBus.merge_failed.is_connected(_track_merge_failed):
			SignalBus.merge_failed.disconnect(_track_merge_failed)
		if SignalBus.phase_changed.is_connected(_track_phase_changed):
			SignalBus.phase_changed.disconnect(_track_phase_changed)

	# Disconnect MergeSystem from SignalBus
	if has_node("/root/SignalBus"):
		if SignalBus.phase_changed.is_connected(_merge_system._on_phase_changed):
			SignalBus.phase_changed.disconnect(_merge_system._on_phase_changed)
		if SignalBus.game_reset_requested.is_connected(_merge_system._on_game_reset):
			SignalBus.game_reset_requested.disconnect(_merge_system._on_game_reset)

	# Disconnect EconomySystem from SignalBus
	if has_node("/root/SignalBus"):
		if SignalBus.monster_died.is_connected(_economy._on_monster_died):
			SignalBus.monster_died.disconnect(_economy._on_monster_died)
		if SignalBus.game_reset_requested.is_connected(_economy._on_game_reset):
			SignalBus.game_reset_requested.disconnect(_economy._on_game_reset)

	# Free resources
	if is_instance_valid(_merge_system):
		_merge_system.free()
	if is_instance_valid(_tower_system):
		_tower_system.free()
	if is_instance_valid(_board):
		_board.free()
	if is_instance_valid(_economy):
		_economy.free()
	if is_instance_valid(_config):
		_config.free()

	# Clear signal tracking
	_merge_completed_signals.clear()
	_merge_failed_signals.clear()
	_phase_changed_signals.clear()


# ── Helpers ──────────────────────────────────────────────────────────────────────


## Build a TowerData resource with specified values.
## Fields not essential for merge tests use sensible defaults.
func _build_tower_data(p_tower_id: String, p_star: int, p_attack: float, p_cost: int, p_sell_value: int) -> TowerData:
	var td := TowerData.new()
	td.tower_id = p_tower_id
	td.tower_name = p_tower_id.capitalize() + " Tower"
	td.star_level = p_star
	td.attack = p_attack
	td.attack_speed = 1.0
	td.range = 150.0
	td.special_value = 0.0
	td.effect_duration = 0.0
	td.cost = p_cost
	td.sell_value = p_sell_value
	td.attack_type = "normal"
	td.description = "Test tower"
	return td


## Place a tower on the board. Returns true on success.
## Shortcut that hides the full place_tower() signature for common test usage.
func _place_tower(p_id: String, p_star: int, p_col: int, p_row: int) -> bool:
	return _tower_system.place_tower(p_id, p_star, p_col, p_row)


## Get the tower at a grid position. Returns null if none.
func _get_tower(p_col: int, p_row: int) -> Tower:
	return _tower_system.get_tower(p_col, p_row)


## Verify a tower exists at the given position with the expected tower_id and star_level.
func _assert_tower(id: String, star: int, col: int, row: int) -> void:
	var t: Tower = _get_tower(col, row)
	assert_bool(t != null, "Expected tower at (%d, %d)" % [col, row]).is_true()
	if t != null:
		assert_str(t.tower_data.tower_id).is_equal(id)
		assert_int(t.tower_data.star_level).is_equal(star)


## Verify no tower exists at the given position.
func _assert_no_tower(col: int, row: int) -> void:
	assert_bool(_get_tower(col, row) == null).is_true()


## Simulate a phase change by emitting phase_changed via SignalBus.
func _simulate_phase_change(new_phase: int) -> void:
	if has_node("/root/SignalBus"):
		SignalBus.phase_changed.emit(_merge_system._current_phase, new_phase)


## Assert the most recent merge_failed signal contained the given substring.
func _assert_merge_failed_contains(substring: String) -> void:
	assert_bool(_merge_failed_signals.size() > 0,
		"merge_failed should have been emitted at least once").is_true()
	if _merge_failed_signals.size() > 0:
		var last_reason: String = _merge_failed_signals.back()
		assert_bool(last_reason.contains(substring),
			"merge_failed reason '%s' should contain '%s'" % [last_reason, substring]).is_true()


# ── Signal Trackers ──────────────────────────────────────────────────────────────


func _track_merge_completed(from_star: int, to_star: int, position: Vector2i) -> void:
	_merge_completed_signals.append({
		"from_star": from_star,
		"to_star": to_star,
		"pos_col": position.x,
		"pos_row": position.y,
	})


func _track_merge_failed(reason: String) -> void:
	_merge_failed_signals.append(reason)


func _track_phase_changed(old_phase: int, new_phase: int) -> void:
	_phase_changed_signals.append({"old": old_phase, "new": new_phase})


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 1: Init sets merge cost from config
# GDD tuning knob: MERGE_COST loaded from EconomyConfig
# ═══════════════════════════════════════════════════════════════════════════════════

func test_merge_system_init_sets_merge_cost_from_config() -> void:
	# Arrange: _config.MERGE_COST = 0 (set in before)
	# Act: init already called in before() — verify field was cached
	# Assert
	assert_int(_merge_system._merge_cost).is_equal(0)

	# Arrange: change config and re-init
	var config2 := EconomyConfig.new()
	config2.starting_gold = 100
	config2.MERGE_COST = 50
	config2.kill_reward_multiplier = 1.0
	var merge2 := MergeSystem.new()
	merge2.init(_tower_system, _board, _economy, config2)

	# Assert: merge_cost = 50 from config
	assert_int(merge2._merge_cost).is_equal(50)

	# Cleanup
	merge2.free()
	config2.free()


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 2: try_merge succeeds — two 1-star cannons → one 2-star cannon
# GDD AC: GIVEN two 1-star cannons adjacent,
#         WHEN drag one onto the other,
#         THEN both disappear, a 2-star cannon appears at target position
# ═══════════════════════════════════════════════════════════════════════════════════

func test_try_merge_succeeds_two_1star_cannons_becomes_2star() -> void:
	# Arrange: place two 1-star cannons at (5,3) and (6,3)
	assert_bool(_place_tower("cannon", 1, 5, 3), "Place cannon_1 at (5,3)").is_true()
	assert_bool(_place_tower("cannon", 1, 6, 3), "Place cannon_1 at (6,3)").is_true()
	_assert_tower("cannon", 1, 5, 3)
	_assert_tower("cannon", 1, 6, 3)
	var tower_count_before := _tower_system.get_tower_count()

	# Act: merge (5,3) → (6,3)
	var ok := _merge_system.try_merge(5, 3, 6, 3)

	# Assert
	assert_bool(ok, "try_merge should succeed").is_true()

	# Source tower gone
	_assert_no_tower(5, 3)
	# Target position now has 2-star cannon
	_assert_tower("cannon", 2, 6, 3)
	# Total tower count decreased by 1 (2 → 1)
	assert_int(_tower_system.get_tower_count()).is_equal(tower_count_before - 1)

	# Signal: merge_completed emitted
	assert_int(_merge_completed_signals.size()).is_equal(1)
	assert_int(_merge_completed_signals.back().from_star).is_equal(1)
	assert_int(_merge_completed_signals.back().to_star).is_equal(2)
	assert_int(_merge_completed_signals.back().pos_col).is_equal(6)
	assert_int(_merge_completed_signals.back().pos_row).is_equal(3)

	# Gold unchanged (MERGE_COST = 0)
	assert_int(_economy.current_gold).is_equal(200)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 3: try_merge fails — different tower types
# GDD AC: GIVEN 1-star cannon dragged onto 1-star ice tower,
#         WHEN released, THEN both bounce back (merge_failed)
# ═══════════════════════════════════════════════════════════════════════════════════

func test_try_merge_fails_different_tower_type() -> void:
	# Arrange
	_place_tower("cannon", 1, 5, 3)
	_place_tower("ice", 1, 6, 3)
	_assert_tower("cannon", 1, 5, 3)
	_assert_tower("ice", 1, 6, 3)

	# Act
	var ok := _merge_system.try_merge(5, 3, 6, 3)

	# Assert
	assert_bool(ok, "try_merge should fail for different types").is_false()
	# Both towers remain in place (state unchanged)
	_assert_tower("cannon", 1, 5, 3)
	_assert_tower("ice", 1, 6, 3)
	# Signal: merge_failed with type mismatch
	_assert_merge_failed_contains("type mismatch")


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 4: try_merge fails — different star levels
# GDD edge case: 1-star + 2-star same type → fail (stars must match)
# ═══════════════════════════════════════════════════════════════════════════════════

func test_try_merge_fails_different_star_level() -> void:
	# Arrange: 1-star cannon at (5,3), 2-star cannon at (6,3)
	_place_tower("cannon", 1, 5, 3)
	_place_tower("cannon", 2, 6, 3)

	# Act
	var ok := _merge_system.try_merge(5, 3, 6, 3)

	# Assert
	assert_bool(ok, "try_merge should fail for different star levels").is_false()
	_assert_tower("cannon", 1, 5, 3)
	_assert_tower("cannon", 2, 6, 3)
	_assert_merge_failed_contains("Star level mismatch")


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 5: try_merge fails — max star level (3)
# GDD AC: GIVEN two 3-star cannons, WHEN released, THEN bounce back (max star)
# ═══════════════════════════════════════════════════════════════════════════════════

func test_try_merge_fails_max_star_level() -> void:
	# Arrange: two 3-star cannons
	_place_tower("cannon", 3, 5, 3)
	_place_tower("cannon", 3, 6, 3)

	# Act
	var ok := _merge_system.try_merge(5, 3, 6, 3)

	# Assert
	assert_bool(ok, "try_merge should fail for max star (3)").is_false()
	_assert_tower("cannon", 3, 5, 3)
	_assert_tower("cannon", 3, 6, 3)
	_assert_merge_failed_contains("max star")


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 6: try_merge fails — cannot merge tower with itself
# Edge case: from == to
# ═══════════════════════════════════════════════════════════════════════════════════

func test_try_merge_fails_self_merge() -> void:
	# Arrange
	_place_tower("cannon", 1, 5, 3)

	# Act: merge onto itself
	var ok := _merge_system.try_merge(5, 3, 5, 3)

	# Assert
	assert_bool(ok, "try_merge should fail for self-merge").is_false()
	_assert_tower("cannon", 1, 5, 3)
	_assert_merge_failed_contains("itself")


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 7: try_merge fails — missing source tower
# Edge case: from position is empty
# ═══════════════════════════════════════════════════════════════════════════════════

func test_try_merge_fails_missing_source_tower() -> void:
	# Arrange: only target exists
	_place_tower("cannon", 1, 6, 3)
	# (5,3) is empty

	# Act
	var ok := _merge_system.try_merge(5, 3, 6, 3)

	# Assert
	assert_bool(ok, "try_merge should fail with missing source").is_false()
	_assert_tower("cannon", 1, 6, 3)
	_assert_merge_failed_contains("No tower at source")


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 8: try_merge fails — missing target tower
# Edge case: to position is empty
# ═══════════════════════════════════════════════════════════════════════════════════

func test_try_merge_fails_missing_target_tower() -> void:
	# Arrange: only source exists
	_place_tower("cannon", 1, 5, 3)
	# (6,3) is empty

	# Act
	var ok := _merge_system.try_merge(5, 3, 6, 3)

	# Assert
	assert_bool(ok, "try_merge should fail with missing target").is_false()
	_assert_tower("cannon", 1, 5, 3)
	_assert_merge_failed_contains("No tower at target")


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 9: try_merge fails — insufficient gold for merge cost
# GDD edge case: gold < merge_cost → fail, bounce back
# ═══════════════════════════════════════════════════════════════════════════════════

func test_try_merge_fails_insufficient_gold() -> void:
	# Arrange: set merge_cost > current gold
	_merge_system._merge_cost = 300
	_economy.current_gold = 50

	_place_tower("cannon", 1, 5, 3)
	_place_tower("cannon", 1, 6, 3)

	# Act
	var ok := _merge_system.try_merge(5, 3, 6, 3)

	# Assert
	assert_bool(ok, "try_merge should fail when gold insufficient").is_false()
	# Both towers remain
	_assert_tower("cannon", 1, 5, 3)
	_assert_tower("cannon", 1, 6, 3)
	_assert_merge_failed_contains("Cannot afford")


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 10: try_merge succeeds with positive merge cost
# Merges two 2-star cannons → 3-star, deducting merge_cost from gold
# ═══════════════════════════════════════════════════════════════════════════════════

func test_try_merge_succeeds_with_positive_merge_cost() -> void:
	# Arrange: merge_cost = 30, gold = 200
	_merge_system._merge_cost = 30
	assert_int(_economy.current_gold).is_equal(200)

	_place_tower("cannon", 2, 5, 3)
	_place_tower("cannon", 2, 6, 3)

	# Act
	var ok := _merge_system.try_merge(5, 3, 6, 3)

	# Assert
	assert_bool(ok, "try_merge with cost should succeed").is_true()
	_assert_no_tower(5, 3)
	_assert_tower("cannon", 3, 6, 3)
	# Gold: 200 - 30 = 170
	assert_int(_economy.current_gold).is_equal(170)
	# Signal
	assert_int(_merge_completed_signals.size()).is_equal(1)
	assert_int(_merge_completed_signals.back().from_star).is_equal(2)
	assert_int(_merge_completed_signals.back().to_star).is_equal(3)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 11: try_merge fails — not in PREP phase
# GDD: merge is PREP phase exclusive. BATTLE phase should reject.
# ═══════════════════════════════════════════════════════════════════════════════════

func test_try_merge_fails_not_in_prep_phase() -> void:
	# Arrange: place towers, then switch to BATTLE
	_place_tower("cannon", 1, 5, 3)
	_place_tower("cannon", 1, 6, 3)
	_simulate_phase_change(MergeSystem.PHASE_BATTLE)

	# Act
	var ok := _merge_system.try_merge(5, 3, 6, 3)

	# Assert
	assert_bool(ok, "try_merge should fail in BATTLE phase").is_false()
	_assert_merge_failed_contains("Not in PREP phase")
	# Towers unchanged
	_assert_tower("cannon", 1, 5, 3)
	_assert_tower("cannon", 1, 6, 3)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 12: can_merge returns true for valid pair
# Pure query — no side effects, towers NOT modified
# ═══════════════════════════════════════════════════════════════════════════════════

func test_can_merge_returns_true_for_valid_pair() -> void:
	# Arrange
	_place_tower("cannon", 1, 5, 3)
	_place_tower("cannon", 1, 6, 3)

	# Act
	var result := _merge_system.can_merge(5, 3, 6, 3)

	# Assert
	assert_bool(result, "can_merge should return true").is_true()
	# Verify no side effects: towers still exist
	_assert_tower("cannon", 1, 5, 3)
	_assert_tower("cannon", 1, 6, 3)
	assert_int(_tower_system.get_tower_count()).is_equal(2)
	# No signals emitted (can_merge is a query)
	if has_node("/root/SignalBus"):
		assert_int(_merge_completed_signals.size()).is_equal(0)
		assert_int(_merge_failed_signals.size()).is_equal(0)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 13: can_merge returns false for invalid pairs
# Covers: different type, different star, max star, self, empty cells
# ═══════════════════════════════════════════════════════════════════════════════════

func test_can_merge_returns_false_for_invalid_pairs() -> void:
	# Arrange: cannon_1 at (5,3), ice_1 at (6,3), cannon_3 at (7,3)
	_place_tower("cannon", 1, 5, 3)
	_place_tower("ice", 1, 6, 3)
	_place_tower("cannon", 3, 7, 3)

	# Different types
	assert_bool(_merge_system.can_merge(5, 3, 6, 3), "cannon vs ice").is_false()

	# Different stars (cannon_1 vs cannon_3)
	assert_bool(_merge_system.can_merge(5, 3, 7, 3), "star 1 vs star 3").is_false()

	# Max star (cannon_3 with cannon_3 cannot merge — star >= 3)
	_place_tower("cannon", 3, 4, 3)
	assert_bool(_merge_system.can_merge(7, 3, 4, 3), "two 3-stars").is_false()

	# Self merge
	assert_bool(_merge_system.can_merge(5, 3, 5, 3), "self-merge").is_false()

	# Empty source
	assert_bool(_merge_system.can_merge(10, 7, 5, 3), "empty source").is_false()

	# Empty target
	assert_bool(_merge_system.can_merge(5, 3, 10, 7), "empty target").is_false()


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 14: start_drag + cancel_drag lifecycle
# Verifies drag state is properly set and cleaned up
# ═══════════════════════════════════════════════════════════════════════════════════

func test_start_drag_and_cancel_drag_lifecycle() -> void:
	# Arrange: place a tower
	_place_tower("cannon", 1, 5, 3)
	var tower: Tower = _get_tower(5, 3)
	assert_bool(tower != null).is_true()

	# Act: start drag
	_merge_system.start_drag(tower)

	# Assert: drag state set
	assert_bool(_merge_system._is_dragging, "should be dragging").is_true()
	assert_bool(_merge_system._drag_source_tower == tower, "should track source tower").is_true()
	assert_bool(_merge_system._ghost_node != null, "should create ghost").is_true()

	# Act: cancel drag
	_merge_system.cancel_drag()

	# Assert: drag state cleaned
	assert_bool(_merge_system._is_dragging, "should not be dragging after cancel").is_false()
	assert_bool(_merge_system._drag_source_tower == null, "source tower ref cleared").is_true()
	assert_bool(_merge_system._ghost_node == null, "ghost freed").is_true()
	# Tower still exists (cancel doesn't remove it)
	_assert_tower("cannon", 1, 5, 3)
	# merge_failed("cancelled") emitted
	_assert_merge_failed_contains("cancelled")


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 15: start_drag no-ops when not in PREP phase
# ═══════════════════════════════════════════════════════════════════════════════════

func test_start_drag_noops_in_battle_phase() -> void:
	# Arrange
	_place_tower("cannon", 1, 5, 3)
	var tower: Tower = _get_tower(5, 3)
	_simulate_phase_change(MergeSystem.PHASE_BATTLE)

	# Act
	_merge_system.start_drag(tower)

	# Assert
	assert_bool(_merge_system._is_dragging, "should not drag in BATTLE").is_false()


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 16: drag canceled on phase change from PREP to BATTLE
# ADR-0006/ADR-0007: phase switch during drag → force cancel, ghost disappears
# ═══════════════════════════════════════════════════════════════════════════════════

func test_drag_canceled_on_phase_change_to_battle() -> void:
	# Arrange
	_place_tower("cannon", 1, 5, 3)
	var tower: Tower = _get_tower(5, 3)
	_merge_system.start_drag(tower)
	assert_bool(_merge_system._is_dragging, "should be dragging").is_true()

	# Act: simulate phase change to BATTLE
	_simulate_phase_change(MergeSystem.PHASE_BATTLE)

	# Assert: drag canceled
	assert_bool(_merge_system._is_dragging, "drag should be canceled").is_false()
	assert_bool(_merge_system._drag_source_tower == null).is_true()
	assert_bool(_merge_system._ghost_node == null, "ghost should be freed").is_true()
	# Tower still in place
	_assert_tower("cannon", 1, 5, 3)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 17: game reset cleans drag state and resets phase
# ADR-0008: game_reset_requested → cancel_all() without emitting merge_failed
# ═══════════════════════════════════════════════════════════════════════════════════

func test_game_reset_cleans_drag_state() -> void:
	# Arrange: start a drag
	_place_tower("cannon", 1, 5, 3)
	var tower: Tower = _get_tower(5, 3)
	_merge_system.start_drag(tower)
	assert_bool(_merge_system._is_dragging, "should be dragging").is_true()

	# Switch to BATTLE so we can verify reset goes back to PREP
	_simulate_phase_change(MergeSystem.PHASE_BATTLE)
	assert_int(_merge_system._current_phase).is_equal(MergeSystem.PHASE_BATTLE)

	# Clear signal tracking to isolate reset behavior
	var fail_count_before := _merge_failed_signals.size()

	# Act: trigger game reset
	_merge_system._on_game_reset()

	# Assert
	assert_bool(_merge_system._is_dragging, "drag should be cleaned").is_false()
	assert_bool(_merge_system._drag_source_tower == null).is_true()
	assert_bool(_merge_system._ghost_node == null, "ghost freed").is_true()
	# Phase reset to PREP
	assert_int(_merge_system._current_phase).is_equal(MergeSystem.PHASE_PREP)
	# cancel_all() does NOT emit merge_failed (unlike cancel_drag)
	if has_node("/root/SignalBus"):
		assert_int(_merge_failed_signals.size()).is_equal(fail_count_before)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 18: update_drag_preview no-ops when not dragging
# Safety: called by InputHandler every frame — must not crash
# ═══════════════════════════════════════════════════════════════════════════════════

func test_update_drag_preview_noops_when_not_dragging() -> void:
	# Arrange: no active drag
	assert_bool(_merge_system._is_dragging, "should not be dragging").is_false()

	# Act: calling update_drag_preview should not error
	_merge_system.update_drag_preview()

	# Assert: no crash, state unchanged
	assert_bool(_merge_system._is_dragging).is_false()


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 19: cancel_drag no-ops when not dragging (idempotent)
# ═══════════════════════════════════════════════════════════════════════════════════

func test_cancel_drag_noops_when_not_dragging() -> void:
	# Arrange: no active drag
	assert_bool(_merge_system._is_dragging).is_false()

	# Act
	_merge_system.cancel_drag()

	# Assert: no crash, no spurious merge_failed emission
	assert_bool(_merge_system._is_dragging).is_false()
	if has_node("/root/SignalBus"):
		assert_int(_merge_failed_signals.size()).is_equal(0)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 20: try_merge with gold cost and exact affordability
# Edge case: gold == merge_cost → merge succeeds, gold becomes 0
# ═══════════════════════════════════════════════════════════════════════════════════

func test_try_merge_succeeds_with_exact_merge_cost() -> void:
	# Arrange: merge_cost = 200, gold = 200
	_merge_system._merge_cost = 200
	_economy.current_gold = 200
	_place_tower("ice", 1, 3, 2)
	_place_tower("ice", 1, 4, 2)

	# Act
	var ok := _merge_system.try_merge(3, 2, 4, 2)

	# Assert: succeeds, gold → 0
	assert_bool(ok).is_true()
	_assert_tower("ice", 2, 4, 2)
	assert_int(_economy.current_gold).is_equal(0)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 21: try_merge fails when merge cost is 1 above balance
# Edge case: gold = merge_cost - 1 → fail
# ═══════════════════════════════════════════════════════════════════════════════════

func test_try_merge_fails_merge_cost_one_above_balance() -> void:
	# Arrange
	_merge_system._merge_cost = 201
	_economy.current_gold = 200
	_place_tower("cannon", 1, 5, 3)
	_place_tower("cannon", 1, 6, 3)

	# Act
	var ok := _merge_system.try_merge(5, 3, 6, 3)

	# Assert
	assert_bool(ok).is_false()
	_assert_merge_failed_contains("Cannot afford")
	# Gold unchanged
	assert_int(_economy.current_gold).is_equal(200)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 22: 2-star to 3-star merge works (star < 3 check — valid at star=2)
# Boundary: star_level = 2 should pass the star_level < 3 check
# ═══════════════════════════════════════════════════════════════════════════════════

func test_try_merge_succeeds_two_2star_becomes_3star() -> void:
	# Arrange
	_place_tower("cannon", 2, 5, 3)
	_place_tower("cannon", 2, 6, 3)

	# Act
	var ok := _merge_system.try_merge(5, 3, 6, 3)

	# Assert
	assert_bool(ok).is_true()
	_assert_no_tower(5, 3)
	_assert_tower("cannon", 3, 6, 3)
	assert_int(_merge_completed_signals.size()).is_equal(1)
	assert_int(_merge_completed_signals.back().from_star).is_equal(2)
	assert_int(_merge_completed_signals.back().to_star).is_equal(3)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 23: merge_completed signal not emitted on failure
# Verifies signal hygiene: only success emits merge_completed
# ═══════════════════════════════════════════════════════════════════════════════════

func test_merge_completed_not_emitted_on_failure() -> void:
	# Arrange
	_place_tower("cannon", 1, 5, 3)
	_place_tower("ice", 1, 6, 3)

	# Act: different types → fail
	var ok := _merge_system.try_merge(5, 3, 6, 3)

	# Assert
	assert_bool(ok).is_false()
	_assert_merge_failed_contains("type mismatch")
	# merge_completed NOT emitted
	assert_int(_merge_completed_signals.size()).is_equal(0)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 24: try_merge from position A to B same as B to A (symmetric)
# Verification: merge direction doesn't matter — same result
# ═══════════════════════════════════════════════════════════════════════════════════

func test_try_merge_symmetric_result() -> void:
	# Arrange: cannons at (5,3) and (6,3)
	_place_tower("cannon", 1, 5, 3)
	_place_tower("cannon", 1, 6, 3)

	# Act: merge (6,3) → (5,3) — reverse direction
	var ok := _merge_system.try_merge(6, 3, 5, 3)

	# Assert: 2-star cannon at source position (5,3) — target was (5,3)
	assert_bool(ok).is_true()
	_assert_no_tower(6, 3)
	_assert_tower("cannon", 2, 5, 3)
