class_name TowerSystem
extends Node
## TowerSystem — manages all towers on the board: placement, selling, attack gating.
##
## Implements: design/gdd/tower-system.md
## Architecture: docs/architecture/adr-0002-data-resources.md
## Phase gating: ADR-0006 (tower attacks only in BATTLE, place/sell only in PREP)
##
## Responsibilities:
##   - Tower lifecycle: create, place, sell, remove
##   - Phase gating: start/stop attack timers on phase transitions
##   - TowerData loading: load .tres files from res://resources/towers/
##   - Attack bridging: connect Tower.attack_triggered to damage application
##
## Dependencies (injected):
##   - BoardGrid: for cell state management (get/set cell state)
##   - MonsterPool: for active monster queries (find_target)
##
## Attack dispatch bridge:
##   Tower emits attack_triggered → TowerSystem._on_attack_triggered() →
##   applies damage/effects to monsters. When CombatSystem is implemented,
##   the bridge delegates to combat.process_tower_attack() instead.


# ── Phase Constants (mirrors PhaseManager enum — ADR-0006) ───────────────────────

const PHASE_PREP: int = 0
const PHASE_BATTLE: int = 1


# ── Tower Storage ────────────────────────────────────────────────────────────────

## All towers currently on the board, keyed by grid position: { Vector2i: Tower }
var _towers: Dictionary = {}


## Cached TowerData resources, keyed by "tower_id_star" (e.g. "cannon_2").
## Populated by _ensure_data_loaded() on first placement request.
var _tower_data_cache: Dictionary = {}


# ── Injected Dependencies ────────────────────────────────────────────────────────

## BoardGrid reference — set via init().
var _board: BoardGrid = null

## MonsterPool reference — set via init().
var _monster_pool: MonsterPool = null

## Current game phase. Updated via SignalBus.phase_changed.
## Defaults to PHASE_PREP — attacks are stopped until first BATTLE transition.
var _current_phase: int = PHASE_PREP


# ═══════════════════════════════════════════════════════════════════════════════════
# Public API
# ═══════════════════════════════════════════════════════════════════════════════════


## Initialize the tower system with required dependencies.
## Subscribes to SignalBus.phase_changed for attack gating (has_node guard for tests).
##
## Usage:
##   tower_system.init(board_grid, monster_pool)
func init(p_board: BoardGrid, p_monster_pool: MonsterPool) -> void:
	_board = p_board
	_monster_pool = p_monster_pool
	_current_phase = PHASE_PREP

	# Subscribe to phase changes for attack gating
	if has_node("/root/SignalBus"):
		if not SignalBus.phase_changed.is_connected(_on_phase_changed):
			SignalBus.phase_changed.connect(_on_phase_changed)


## Place a tower on the board at (col, row).
##
## Preconditions (all must pass — returns false otherwise):
##   1. _current_phase == PHASE_PREP (only place during preparation)
##   2. Cell at (col, row) is EMPTY
##   3. TowerData exists for the requested tower_id + star combination
##   4. Economy check: sufficient gold (delegated to SignalBus consumer —
##      TowerSystem does not hold gold balance; caller must pre-check)
##
## On success:
##   - Creates a Tower node, adds it as child
##   - Positions it at cell center (via BoardGrid.grid_to_world)
##   - Sets cell state to TOWER
##   - Returns true
##
## Returns false if any precondition fails.
func place_tower(tower_id: String, star: int, col: int, row: int) -> bool:
	# Phase gate: only place during PREP
	if _current_phase != PHASE_PREP:
		push_warning("TowerSystem.place_tower: Cannot place during BATTLE phase")
		return false

	# Board must be initialized
	if _board == null:
		push_error("TowerSystem.place_tower: BoardGrid not initialized")
		return false

	# Position must be valid
	if not _board.is_valid_position(col, row):
		push_warning("TowerSystem.place_tower: Invalid position (%d, %d)" % [col, row])
		return false

	# Cell must be EMPTY
	if _board.get_cell_state(col, row) != BoardGrid.CellState.EMPTY:
		push_warning("TowerSystem.place_tower: Cell (%d, %d) is not EMPTY" % [col, row])
		return false

	# Cell must not already have a tower
	var key := Vector2i(col, row)
	if _towers.has(key):
		push_warning("TowerSystem.place_tower: Tower already exists at (%d, %d)" % [col, row])
		return false

	# Load tower data
	var data: TowerData = _load_tower_data(tower_id, star)
	if data == null:
		push_error("TowerSystem.place_tower: No TowerData for '%s' star %d" % [tower_id, star])
		return false

	# Create and setup tower
	var tower := Tower.new()
	tower.setup(data, key)
	tower.global_position = _board.grid_to_world(col, row)
	tower.set_monster_pool(_monster_pool)
	tower.attack_triggered.connect(_on_attack_triggered)
	add_child(tower)

	# Update board cell state
	if not _board.set_cell_state(col, row, BoardGrid.CellState.TOWER):
		push_error("TowerSystem.place_tower: Failed to set cell state to TOWER at (%d, %d)" % [col, row])
		tower.teardown()
		tower.queue_free()
		return false

	_towers[key] = tower
	return true


## Sell a tower at (col, row) and return its sell_value in gold.
##
## Preconditions:
##   1. _current_phase == PHASE_PREP (only sell during preparation — GDD edge case)
##   2. A tower exists at (col, row)
##
## On success:
##   - Removes tower from board
##   - Resets cell state to EMPTY
##   - Returns sell_value (int)
##
## Returns 0 if any precondition fails.
func sell_tower(col: int, row: int) -> int:
	# Phase gate: only sell during PREP
	if _current_phase != PHASE_PREP:
		push_warning("TowerSystem.sell_tower: Cannot sell during BATTLE phase")
		return 0

	var key := Vector2i(col, row)
	var tower: Tower = _towers.get(key)
	if tower == null:
		push_warning("TowerSystem.sell_tower: No tower at (%d, %d)" % [col, row])
		return 0

	var refund: int = tower.get_sell_value()

	_remove_tower_internal(col, row)
	return refund


## Get the tower at grid position (col, row).
## Returns null if no tower exists at that position.
func get_tower(col: int, row: int) -> Tower:
	return _towers.get(Vector2i(col, row))


## Remove a tower at (col, row) without returning gold.
## Used by merge-upgrade system (tower replaced in-place, no sell refund).
## No-ops if no tower exists at the position.
func remove_tower(col: int, row: int) -> void:
	_remove_tower_internal(col, row)


## Return a copy of all towers currently on the board.
## Used by HUD/UI for tower info display and merge-upgrade queries.
func get_all_towers() -> Array[Tower]:
	var result: Array[Tower] = []
	result.resize(_towers.size())
	var i: int = 0
	for tower in _towers.values():
		result[i] = tower
		i += 1
	return result


## Return the number of towers currently on the board.
func get_tower_count() -> int:
	return _towers.size()


# ═══════════════════════════════════════════════════════════════════════════════════
# Internal: Tower Lifecycle
# ═══════════════════════════════════════════════════════════════════════════════════


## Internal removal logic shared by sell_tower() and remove_tower().
## Stops attack timer, tears down tower, resets cell to EMPTY, removes from _towers.
func _remove_tower_internal(col: int, row: int) -> void:
	var key := Vector2i(col, row)
	var tower: Tower = _towers.get(key)
	if tower == null:
		return

	if tower.attack_triggered.is_connected(_on_attack_triggered):
		tower.attack_triggered.disconnect(_on_attack_triggered)

	tower.stop_attacking()
	tower.teardown()
	_towers.erase(key)

	if _board != null:
		_board.set_cell_state(col, row, BoardGrid.CellState.EMPTY)

	if is_instance_valid(tower):
		tower.queue_free()


# ═══════════════════════════════════════════════════════════════════════════════════
# Internal: Phase Gating (ADR-0006)
# ═══════════════════════════════════════════════════════════════════════════════════


## React to phase transitions from SignalBus.
## PREP -> BATTLE: start all tower attack timers.
## BATTLE -> PREP: stop all tower attack timers.
func _on_phase_changed(old_phase: int, new_phase: int) -> void:
	_current_phase = new_phase
	match new_phase:
		PHASE_BATTLE:
			_start_all_attacks()
		PHASE_PREP:
			_stop_all_attacks()


## Start attack timers on all active towers.
func _start_all_attacks() -> void:
	for tower in _towers.values():
		tower.start_attacking()


## Stop attack timers on all active towers.
## Called on BATTLE -> PREP transition and on game reset.
func _stop_all_attacks() -> void:
	for tower in _towers.values():
		tower.stop_attacking()


# ═══════════════════════════════════════════════════════════════════════════════════
# Internal: TowerData Loading (ADR-0002)
# ═══════════════════════════════════════════════════════════════════════════════════


## Load TowerData resource for the given tower_id and star_level.
## Caches loaded resources in _tower_data_cache for subsequent lookups.
## Returns null if the .tres file cannot be loaded.
##
## Load path: res://resources/towers/{tower_id}_{star}.tres
func _load_tower_data(tower_id: String, star: int) -> TowerData:
	var cache_key: String = tower_id + "_" + str(star)
	if _tower_data_cache.has(cache_key):
		return _tower_data_cache[cache_key] as TowerData

	var path: String = "res://resources/towers/%s_%d.tres" % [tower_id, star]
	if not ResourceLoader.exists(path):
		push_error("TowerSystem._load_tower_data: Resource not found: %s" % path)
		return null

	var resource := load(path) as TowerData
	if resource == null:
		push_error("TowerSystem._load_tower_data: Failed to load TowerData from: %s" % path)
		return null

	# Validate loaded data
	if resource.tower_id != tower_id:
		push_error("TowerSystem._load_tower_data: tower_id mismatch in %s (expected '%s', got '%s')" % [path, tower_id, resource.tower_id])
		return null
	if resource.star_level != star:
		push_error("TowerSystem._load_tower_data: star_level mismatch in %s (expected %d, got %d)" % [path, star, resource.star_level])
		return null

	_tower_data_cache[cache_key] = resource
	return resource


## Preload all tower data into cache. Called during loading screen to absorb
## first-load cost. Safe to call multiple times — subsequent calls are no-ops
## for already-cached resources.
##
## Iterates the towers directory and loads all .tres files found.
func preload_all_tower_data() -> void:
	var dir_path: String = "res://resources/towers/"
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("TowerSystem.preload_all_tower_data: Cannot open directory: %s" % dir_path)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var resource := load(dir_path + file_name) as TowerData
			if resource != null:
				var key: String = resource.tower_id + "_" + str(resource.star_level)
				if not _tower_data_cache.has(key):
					_tower_data_cache[key] = resource
		file_name = dir.get_next()
	dir.list_dir_end()


# ═══════════════════════════════════════════════════════════════════════════════════
# Internal: Attack Bridge (Combat Intermediary — EPIC TR-tower-002)
# ═══════════════════════════════════════════════════════════════════════════════════


## Bridge handler for Tower.attack_triggered signal.
## Applies damage/effects to the target monster based on attack_type.
##
## When CombatSystem is implemented, this method delegates to
## combat.process_tower_attack() instead of applying damage directly.
##
## Attack type dispatch:
##   "aoe"   — Splash damage: primary target takes full damage,
##             surrounding monsters in 3×3 grid area take special_value% splash.
##   "slow"  — Speed reduction: target's speed multiplied by special_value
##             (0.5 = 50% slow) for effect_duration seconds.
##             Non-stacking: only the strongest slow applies (max special_value).
##   "pierce" — Chain attack: primary target takes damage,
##             30% chance to bounce to next nearest monster (up to special_value bounces).
##   "normal" — Simple single-target damage.
func _on_attack_triggered(tower: Tower, target: Monster, attack_info: Dictionary) -> void:
	if not is_instance_valid(target) or not target.is_active:
		return

	var attack_type: String = attack_info.get("attack_type", "normal")
	var amount: float = attack_info.get("amount", 0.0)
	var special: float = attack_info.get("special_value", 0.0)
	var duration: float = attack_info.get("effect_duration", 0.0)

	match attack_type:
		"aoe":
			_apply_aoe_attack(tower, target, amount, special)
		"slow":
			_apply_slow_attack(target, amount, special, duration)
		"pierce":
			_apply_pierce_attack(tower, target, amount, special)
		_:
			# "normal" or unknown type — single-target direct damage
			target.take_damage(amount)
			if target.current_health <= 0.0:
				_monster_pool.despawn(target)


## Apply AOE (Area of Effect) attack — Cannon tower.
## Primary target takes full damage.
## Monsters within splash_radius cells (Manhattan distance) take splash_pct% of damage.
##
## splash_radius derived from special_value: 0 = single target, 1 = 3×3, 2 = 5×5.
## splash_pct defaults to 50% of attack damage.
func _apply_aoe_attack(tower: Tower, target: Monster, amount: float, splash_radius: float) -> void:
	# Primary target takes full damage
	target.take_damage(amount)
	if target.current_health <= 0.0:
		_monster_pool.despawn(target)

	if splash_radius <= 0.0:
		return

	# Determine splash area in world space
	# splash_radius is in cell units (1 = adjacent cells in 3×3, 2 = 5×5)
	var cell_size: int = 56
	if _board != null:
		cell_size = _board.cell_size

	var center_world: Vector2 = target.global_position
	var splash_range: float = splash_radius * float(cell_size) + float(cell_size) * 0.5

	# Gather all active monsters
	var all_monsters: Array[Monster] = _monster_pool.get_active_monsters()
	var splash_damage: float = amount * 0.5  # 50% splash

	for monster in all_monsters:
		if monster == target:
			continue
		if not is_instance_valid(monster) or not monster.is_active:
			continue
		if monster.state == Monster.MonsterState.DYING or monster.state == Monster.MonsterState.BREACHED:
			continue
		if monster.global_position.distance_to(center_world) <= splash_range:
			monster.take_damage(splash_damage)


## Apply slow attack — Ice tower.
## Target takes full damage + speed reduction.
## Slow is non-stacking per GDD edge case: only the strongest slow (lowest speed_multiplier)
## applies. If target already has a stronger slow, this one does nothing.
##
## Uses Monster.apply_effect("freeze", duration, speed_multiplier) per Monster class API.
func _apply_slow_attack(target: Monster, amount: float, slow_value: float, duration: float) -> void:
	# Full damage to target
	target.take_damage(amount)
	if target.current_health <= 0.0:
		_monster_pool.despawn(target)
		return

	# slow_value is the speed multiplier (e.g., 0.5 = 50% speed)
	# Guard: if target already has a stronger slow (lower multiplier), skip
	if target._speed_multiplier < 1.0 and target._speed_multiplier <= slow_value:
		# Existing slow is stronger or equal — non-stacking per GDD edge case
		return

	# Default duration if not specified in data
	if duration <= 0.0:
		duration = 1.0  # GDD default for ice tower slow

	target.apply_effect("freeze", duration, slow_value)


## Apply pierce (chain/bounce) attack — Arrow tower.
## Primary target takes full damage.
## 30% chance to bounce to the next nearest monster (within range).
## Chains up to special_value (max_bounces) times.
##
## Each bounce: 30% probability check. On success, the nearest monster
## (not already hit) takes damage and the chain continues.
func _apply_pierce_attack(tower: Tower, target: Monster, amount: float, max_bounces: float) -> void:
	# Primary target takes full damage
	target.take_damage(amount)
	if target.current_health <= 0.0:
		_monster_pool.despawn(target)
		return

	var bounces: int = int(max_bounces)
	if bounces <= 0:
		return

	var hit_targets: Array[Monster] = [target]
	var current_source: Monster = target
	var bounce_damage: float = amount  # Same damage per bounce

	for _i in range(bounces):
		# 30% chance to bounce per GDD
		if randf() >= 0.3:
			break

		var next_target: Monster = _find_nearest_monster(current_source, hit_targets, tower)
		if next_target == null:
			break

		next_target.take_damage(bounce_damage)
		hit_targets.append(next_target)
		current_source = next_target


## Find the nearest monster to `source` that is not in `exclude` list and is within
## tower range. Returns null if no eligible target found.
func _find_nearest_monster(source: Monster, exclude: Array[Monster], tower: Tower) -> Monster:
	var all_monsters: Array[Monster] = _monster_pool.get_active_monsters()
	var nearest: Monster = null
	var nearest_dist_sq: float = INF
	var range_sq: float = tower.tower_data.range * tower.tower_data.range
	var source_pos: Vector2 = source.global_position

	for monster in all_monsters:
		if exclude.has(monster):
			continue
		if not is_instance_valid(monster) or not monster.is_active:
			continue
		if monster.state == Monster.MonsterState.DYING or monster.state == Monster.MonsterState.BREACHED:
			continue

		var dist_sq: float = monster.global_position.distance_squared_to(source_pos)
		if dist_sq <= range_sq and dist_sq < nearest_dist_sq:
			nearest = monster
			nearest_dist_sq = dist_sq

	return nearest


# ═══════════════════════════════════════════════════════════════════════════════════
# Internal: Game Reset (ADR-0008)
# ═══════════════════════════════════════════════════════════════════════════════════


## Handle game reset — remove all towers and clear state.
## Connected to SignalBus.game_reset_requested in production.
func _on_game_reset() -> void:
	var keys: Array = _towers.keys().duplicate()
	for key in keys:
		var tower: Tower = _towers[key]
		if tower.attack_triggered.is_connected(_on_attack_triggered):
			tower.attack_triggered.disconnect(_on_attack_triggered)
		tower.stop_attacking()
		tower.teardown()
		if is_instance_valid(tower):
			tower.queue_free()
	_towers.clear()
	_current_phase = PHASE_PREP
