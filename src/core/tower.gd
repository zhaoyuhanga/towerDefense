class_name Tower
extends Node2D
## Single tower instance placed on the board grid.
##
## Implements: design/gdd/tower-system.md


func _draw() -> void:
	if not tower_data:
		return
	var c := Color.GRAY
	match tower_data.attack_type:
		"aoe": c = Color.ORANGE_RED
		"slow": c = Color.CORNFLOWER_BLUE
		"pierce": c = Color.GREEN
	draw_rect(Rect2(-14, -14, 28, 28), c)
	draw_rect(Rect2(-14, -14, 28, 28), Color.WHITE, false, 2.0)
	for i in range(tower_data.star_level):
		draw_circle(Vector2(-8 + i * 8, 18), 2.0, Color.GOLD)
## Architecture: docs/architecture/adr-0002-data-resources.md
##
## Lifecycle:
##   setup() -> start_attacking() (on BATTLE phase) -> stop_attacking() (on PREP phase) -> teardown()
##
## Attack cycle per GDD:
##   Timer fires every 1.0/attack_speed seconds.
##   find_target() selects the monster closest to exit (highest waypoint_index),
##   tiebreak by lowest current_health.
##
## Attack types dispatched via attack_triggered signal — TowerSystem bridges to damage application.
## Tower does NOT call monster.take_damage() directly (per EPIC combat-intermediary requirement).


## Tower configuration data resource (TowerData .tres).
## Set via setup(); never null while is_active is true.
var tower_data: TowerData

## Grid position of this tower on the board (col, row).
var grid_pos: Vector2i = Vector2i(-1, -1)

## True after setup(), false after teardown(). Guards attack processing.
var is_active: bool = false

## Emitted when this tower fires an attack. TowerSystem connects to bridge damage application.
## Parameters: tower (self), target (Monster), attack_info (Dictionary with type/amount/special/duration).
signal attack_triggered(tower: Tower, target: Monster, attack_info: Dictionary)

## Internal Timer for attack cycle. Interval = 1.0 / tower_data.attack_speed.
## Created in setup(), freed in teardown(). Started/stopped by phase gating.
var _attack_timer: Timer = null


## Initialize or reinitialize this tower with configuration data and position.
## Called by TowerSystem.place_tower().
## Idempotent — safe to call on pooled instances (future pooling support).
func setup(p_data: TowerData, p_grid_pos: Vector2i) -> void:
	tower_data = p_data
	grid_pos = p_grid_pos
	is_active = true

	if _attack_timer == null:
		_attack_timer = Timer.new()
		_attack_timer.one_shot = false
		add_child(_attack_timer)
	_attack_timer.wait_time = 1.0 / p_data.attack_speed
	if not _attack_timer.timeout.is_connected(_on_attack_tick):
		_attack_timer.timeout.connect(_on_attack_tick)


## Start the attack timer. Called when phase transitions to BATTLE.
## No-ops if already running or is_active is false.
func start_attacking() -> void:
	if not is_active:
		return
	if _attack_timer != null and _attack_timer.is_stopped():
		_attack_timer.start()


## Stop the attack timer. Called when phase transitions to PREP.
## Also called during merge animation gap per EPIC requirement.
func stop_attacking() -> void:
	if _attack_timer != null and not _attack_timer.is_stopped():
		_attack_timer.stop()


## Teardown this tower — stop timer, disconnect signals, mark inactive.
## Called by TowerSystem.sell_tower() and remove_tower().
func teardown() -> void:
	if _attack_timer != null:
		_attack_timer.stop()
		if _attack_timer.timeout.is_connected(_on_attack_tick):
			_attack_timer.timeout.disconnect(_on_attack_tick)
	is_active = false
	tower_data = null
	grid_pos = Vector2i(-1, -1)
	# Note: attack_triggered signal disconnection is handled by TowerSystem
	# in _remove_tower_internal() before calling teardown().


## Returns the sell value from tower data (gold refund on sell).
func get_sell_value() -> int:
	if tower_data != null:
		return tower_data.sell_value
	return 0


## Attack tick callback — fires every 1.0/attack_speed seconds.
## Finds the best target among active monsters in range and emits attack_triggered.
## No-ops if is_active is false (guard against phase transitions mid-tick).
##
## Target selection per GDD:
##   1. Filter active monsters by distance <= tower_data.range
##   2. Pick the one with highest waypoint_index (closest to exit)
##   3. Tiebreak: lowest current_health
func _on_attack_tick() -> void:
	if not is_active or tower_data == null:
		return

	# Gather active monsters from MonsterPool (delegated by TowerSystem)
	var candidates: Array[Monster] = _get_monsters_in_range()
	if candidates.is_empty():
		return

	var target: Monster = _select_target(candidates)
	if target == null:
		return

	var attack_info: Dictionary = _build_attack_info()
	attack_triggered.emit(self, target, attack_info)


## Filter active monsters to those within tower_data.range of this tower's world position.
## Returns empty array if no monsters in range.
func _get_monsters_in_range() -> Array[Monster]:
	var all_monsters: Array[Monster] = []
	# MonsterPool reference is injected by TowerSystem via set_monster_pool()
	if _monster_pool_ref != null and is_instance_valid(_monster_pool_ref):
		all_monsters = _monster_pool_ref.get_active_monsters()

	var in_range: Array[Monster] = []
	var my_pos: Vector2 = global_position
	var range_sq: float = tower_data.range * tower_data.range

	for monster in all_monsters:
		if not is_instance_valid(monster) or not monster.is_active:
			continue
		if monster.state == Monster.MonsterState.DYING or monster.state == Monster.MonsterState.BREACHED:
			continue
		if monster.global_position.distance_squared_to(my_pos) <= range_sq:
			in_range.append(monster)

	return in_range


## Select the highest-priority target from candidates.
## Priority 1: highest _waypoint_index (farthest along path, closest to exit).
##         Tie: lowest current_health.
func _select_target(candidates: Array[Monster]) -> Monster:
	var best: Monster = candidates[0]
	for i in range(1, candidates.size()):
		var monster: Monster = candidates[i]
		if monster._waypoint_index > best._waypoint_index:
			best = monster
		elif monster._waypoint_index == best._waypoint_index:
			if monster.current_health < best.current_health:
				best = monster
	return best


## Build the attack_info dictionary dispatched with attack_triggered.
## Contains attack_type, amount, special_value, and effect_duration.
func _build_attack_info() -> Dictionary:
	return {
		"attack_type": tower_data.attack_type,
		"amount": tower_data.attack,
		"special_value": tower_data.special_value,
		"effect_duration": tower_data.effect_duration,
	}


# ── MonsterPool Reference (Dependency Injection) ─────────────────────────────────

## Weak reference to MonsterPool for querying active monsters.
## Set by TowerSystem after creating the Tower. Uses weak ref pattern
## to avoid hard dependency on autoload path (test-safe).
var _monster_pool_ref: MonsterPool = null


## Inject the MonsterPool reference for target queries.
## Called by TowerSystem after tower creation.
func set_monster_pool(pool: MonsterPool) -> void:
	_monster_pool_ref = pool
