class_name WaveSpawner
extends Node
## WaveSpawner — manages the infinite wave spawning schedule.
##
## Implements: design/gdd/wave-spawner.md
## Architecture: docs/architecture/adr-0006-phase-state-machine.md (phase gating),
##               docs/architecture/adr-0008-state-reset-protocol.md (game reset)
##
## Responsibilities:
##   - Load WaveRules and execute SpawnRule instructions sequentially
##   - Spawn monsters one at a time with spawn_interval spacing
##   - Apply health scaling by wave number (3 tiers per GDD formulas)
##   - Track wave completion: all spawned monsters died or breached
##   - Emit wave_started/wave_ended via SignalBus for downstream systems
##   - Inter-wave pause (3s) before transitioning back to PREP
##
## Dependencies (injected):
##   - BoardGrid: for entrance world position (grid_to_world)
##   - MonsterPool: for spawn(monster_id, parent, position, data)
##
## Lifecycle:
##   1. PREP phase: caller invokes set_wave_rules() to load rules for next wave
##   2. PREP->BATTLE: PhaseManager transitions to BATTLE → WaveSpawner begins spawning
##   3. Spawn phase: monsters spawn one at a time per SpawnRule schedule
##   4. Battle phase: all monsters spawned; WaveSpawner waits for death/breach events
##   5. Wave complete: 3s inter-wave pause → emit wave_ended → PhaseManager → PREP
##   6. Repeat from step 1 with incremented wave_number


# ── Phase Constants (mirrors PhaseManager enum — ADR-0006) ───────────────────────

const PHASE_PREP: int = 0
const PHASE_BATTLE: int = 1

## Inter-wave pause duration in seconds (GDD: ~3s).
const INTER_WAVE_PAUSE: float = 3.0

## Path to monster data resources.
const MONSTER_DATA_PATH: String = "res://resources/monsters/"


# ── Injected Dependencies ────────────────────────────────────────────────────────

## BoardGrid reference — set via init(). Used to find ENTRANCE world position.
var _board: BoardGrid = null
var _pathfinding: Pathfinding = null
var _spawn_parent: Node = null

## MonsterPool reference — set via init(). Used to spawn monsters.
var _monster_pool: MonsterPool = null


# ── Current Phase ────────────────────────────────────────────────────────────────

## Current game phase. Updated via SignalBus.phase_changed.
## Defaults to PHASE_PREP — spawning is gated behind BATTLE transitions.
var _current_phase: int = PHASE_PREP


# ── Wave State ───────────────────────────────────────────────────────────────────

## Current wave number. Incremented each time PREP->BATTLE occurs.
## 0 means no wave has started yet.
var _wave_number: int = 0

## WaveRules resource loaded for the current wave. Contains SpawnRule instructions.
var _wave_rules: WaveRules = null

## Index into _wave_rules.rules[] of the current SpawnRule being executed.
var _current_rule_index: int = 0

## Number of monsters already spawned for the current SpawnRule.
var _current_rule_spawned: int = 0

## Total number of monsters scheduled for this wave (sum of all SpawnRule.counts).
var _enemies_total: int = 0

## Number of monsters spawned so far this wave.
var _enemies_spawned: int = 0

## Number of monsters that have died or breached this wave.
## When _enemies_spawned == _enemies_total AND _enemies_resolved == _enemies_total,
## the wave is complete.
var _enemies_resolved: int = 0

## Number of monsters killed (not breached) this wave. Reported in wave_ended.
var _enemies_killed: int = 0

## Number of monsters breached this wave. Reported in wave_ended.
var _enemies_breached: int = 0

## True while spawning is in progress (spawn_timer is active or more rules remain).
var _is_spawning: bool = false

## True during the inter-wave pause after all monsters are resolved.
var _is_inter_wave_pause: bool = false


# ── Cached Data ──────────────────────────────────────────────────────────────────

## World-space position of the ENTRANCE cell. Cached on first use.
var _entrance_world: Vector2 = Vector2.ZERO

## Whether the entrance position has been found and cached.
var _entrance_found: bool = false

## Cache of loaded MonsterData resources, keyed by monster_id.
## Used to avoid re-loading .tres files for common monster types.
var _monster_data_cache: Dictionary = {}


# ── Timers ───────────────────────────────────────────────────────────────────────

## Spawn interval timer. Fires every SpawnRule.spawn_interval seconds.
## Created in init(). One-shot per tick; rescheduled for next spawn.
var _spawn_timer: Timer

## Inter-wave pause timer. One-shot, fires after INTER_WAVE_PAUSE seconds.
var _inter_wave_timer: Timer


# ═══════════════════════════════════════════════════════════════════════════════════
# Public API
# ═══════════════════════════════════════════════════════════════════════════════════


## Initialize the wave spawner with required dependencies.
## Creates spawn and inter-wave timers. Subscribes to SignalBus for
## phase_changed, monster_died, monster_breached, and game_reset_requested.
##
## Usage:
##   var spawner := WaveSpawner.new()
##   spawner.init(board_grid, monster_pool)
func init(p_board: BoardGrid, p_monster_pool: MonsterPool, p_pathfinding = null, p_spawn_parent: Node = null) -> void:
	_board = p_board
	_monster_pool = p_monster_pool
	_pathfinding = p_pathfinding
	_spawn_parent = p_spawn_parent if p_spawn_parent else self
	_current_phase = PHASE_PREP

	# Create timers
	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = true
	_spawn_timer.timeout.connect(_on_spawn_tick)
	add_child(_spawn_timer)

	_inter_wave_timer = Timer.new()
	_inter_wave_timer.one_shot = true
	_inter_wave_timer.timeout.connect(_on_inter_wave_expired)
	add_child(_inter_wave_timer)

	# Subscribe to SignalBus events (has_node guard for test safety)
	if has_node("/root/SignalBus"):
		if not SignalBus.phase_changed.is_connected(_on_phase_changed):
			SignalBus.phase_changed.connect(_on_phase_changed)
		if not SignalBus.monster_died.is_connected(_on_monster_died):
			SignalBus.monster_died.connect(_on_monster_died)
		if not SignalBus.monster_breached.is_connected(_on_monster_breached):
			SignalBus.monster_breached.connect(_on_monster_breached)
		if not SignalBus.game_reset_requested.is_connected(_on_game_reset):
			SignalBus.game_reset_requested.connect(_on_game_reset)


## Set the WaveRules to use for the upcoming wave.
## Called during PREP phase (typically by a GameManager or WaveDataLoader).
## The rules are consumed when PREP->BATTLE transition occurs.
##
## Usage:
##   var rules := load("res://src/resources/waves/wave_1_5.tres") as WaveRules
##   spawner.set_wave_rules(rules)
func set_wave_rules(rules: WaveRules) -> void:
	_wave_rules = rules


## Returns the current wave number. 0 if no wave has started yet.
func get_wave_number() -> int:
	return _wave_number


## Returns true if a wave is currently active (spawning or waiting for resolution).
func is_wave_active() -> bool:
	return _is_spawning or (_wave_number > 0 and _enemies_resolved < _enemies_total)


## Returns the number of alive monsters in the current wave.
## Alive = spawned but not yet died or breached.
func get_alive_count() -> int:
	return _enemies_spawned - _enemies_resolved


# ═══════════════════════════════════════════════════════════════════════════════════
# Phase Gating (ADR-0006)
# ═══════════════════════════════════════════════════════════════════════════════════


## React to phase transitions from SignalBus.
## PREP -> BATTLE: increment wave counter, begin spawning sequence.
## BATTLE -> PREP: stop any active timers.
func _on_phase_changed(old_phase: int, new_phase: int) -> void:
	_current_phase = new_phase
	if new_phase == PHASE_BATTLE and old_phase == PHASE_PREP:
		_wave_number += 1
		_begin_spawning()
	elif new_phase == PHASE_PREP:
		# Cleanup: stop any active timers
		_spawn_timer.stop()
		_inter_wave_timer.stop()
		_is_spawning = false
		_is_inter_wave_pause = false


# ═══════════════════════════════════════════════════════════════════════════════════
# Spawning Logic
# ═══════════════════════════════════════════════════════════════════════════════════


## Begin the spawning sequence for the current wave.
## Resets per-wave counters, computes _enemies_total from WaveRules,
## emits wave_started, and fires the first spawn immediately (no initial delay).
func _begin_spawning() -> void:
	# Guard: must have wave rules loaded
	if _wave_rules == null:
		push_error("WaveSpawner._begin_spawning: No WaveRules set — cannot start wave %d" % _wave_number)
		return

	# Reset wave counters
	_current_rule_index = 0
	_current_rule_spawned = 0
	_enemies_spawned = 0
	_enemies_resolved = 0
	_enemies_killed = 0
	_enemies_breached = 0
	_is_spawning = true
	_is_inter_wave_pause = false

	# Sum total enemies from all spawn rules
	_enemies_total = 0
	for rule: SpawnRule in _wave_rules.rules:
		_enemies_total += rule.count

	# Handle edge case: wave with zero monsters (empty WaveRules)
	if _enemies_total == 0:
		_is_spawning = false
		_emit_wave_started()
		_start_inter_wave_pause()
		return

	# Ensure entrance position is cached
	_cache_entrance()

	# Emit wave_started signal
	_emit_wave_started()

	# Fire first spawn immediately — timer fires subsequent ones
	_on_spawn_tick()


## Timer callback for spawning the next monster in the current SpawnRule.
## Spawns one monster, increments counters, advances to next rule if needed.
## If all rules are exhausted, marks spawning complete.
func _on_spawn_tick() -> void:
	if not _is_spawning:
		return

	# Advance past completed or invalid rules
	while _current_rule_index < _wave_rules.rules.size():
		var rule: SpawnRule = _wave_rules.rules[_current_rule_index]
		if rule.count <= 0:
			_current_rule_index += 1
			_current_rule_spawned = 0
			continue
		if _current_rule_spawned >= rule.count:
			_current_rule_index += 1
			_current_rule_spawned = 0
			continue
		break

	# All rules exhausted — spawning phase complete
	if _current_rule_index >= _wave_rules.rules.size():
		_is_spawning = false
		# Check if wave is already complete (all spawned monsters already dead)
		_check_wave_complete()
		return

	var rule: SpawnRule = _wave_rules.rules[_current_rule_index]
	_spawn_one(rule)
	_current_rule_spawned += 1
	_enemies_spawned += 1

	# Schedule next spawn if more monsters remain
	if _current_rule_spawned < rule.count or _current_rule_index + 1 < _wave_rules.rules.size():
		_spawn_timer.wait_time = rule.spawn_interval
		_spawn_timer.start()
	else:
		# Last monster spawned — spawning phase complete
		_is_spawning = false
		_check_wave_complete()


## Spawn a single monster of the given rule's monster_id.
## Loads MonsterData, applies health scaling by wave number,
## and calls MonsterPool.spawn() at the cached entrance world position.
##
## GDD edge case: if monster_id is invalid (no MonsterData found),
## the spawn is silently skipped and the counter still increments.
func _spawn_one(rule: SpawnRule) -> void:
	var data: MonsterData = _load_monster_data(rule.monster_id)
	if data == null:
		# GDD edge case: spawn ID not found → skip
		push_warning("WaveSpawner._spawn_one: No MonsterData for '%s' — skipping" % rule.monster_id)
		return

	# Apply health scaling per wave difficulty tier
	var scaled_data: MonsterData = _apply_health_scaling(data, _wave_number)

	# Spawn at entrance world position
	if not _entrance_found:
		push_error("WaveSpawner._spawn_one: Entrance position not found — cannot spawn")
		return

	var monster := _monster_pool.spawn(rule.monster_id, _spawn_parent, _entrance_world, scaled_data)
	if monster and _pathfinding:
		var grid_path := _pathfinding.get_main_path()
		if not grid_path.is_empty():
			var world_path: Array[Vector2] = []
			for gp in grid_path:
				world_path.append(_board.grid_to_world(gp.x, gp.y))
			monster.set_path(world_path)


# ═══════════════════════════════════════════════════════════════════════════════════
# Health Scaling (GDD Formulas)
# ═══════════════════════════════════════════════════════════════════════════════════


## Apply health scaling to a MonsterData copy based on wave number.
##
## Wave 1-10:  linear growth  — health *= 1.0 + wave * 0.1
## Wave 11-25: accelerated     — health *= 1.0 + wave * 0.2
## Wave 26+:   affix era       — same scaling as 11-25, plus affixes activate
##
## Returns a duplicated MonsterData resource with scaled health.
## Does not mutate the original resource.
func _apply_health_scaling(data: MonsterData, wave_number: int) -> MonsterData:
	var scaled: MonsterData = data.duplicate()
	var multiplier: float = 1.0

	if wave_number <= 10:
		multiplier = 1.0 + float(wave_number) * 0.1
	elif wave_number <= 25:
		multiplier = 1.0 + float(wave_number) * 0.2
	else:
		# Wave 26+: continuing scaling + affix era
		# Affix application is deferred — see design/gdd/wave-spawner.md
		multiplier = 1.0 + float(wave_number) * 0.2

	scaled.health = data.health * multiplier
	return scaled


# ═══════════════════════════════════════════════════════════════════════════════════
# Monster Death / Breach Tracking
# ═══════════════════════════════════════════════════════════════════════════════════


## Handler for SignalBus.monster_died.
## Increments resolved counter and killed counter, then checks wave completion.
func _on_monster_died(_monster_id: String, _position: Vector2, _reward_gold: int) -> void:
	if _wave_number <= 0:
		return
	_enemies_resolved += 1
	_enemies_killed += 1
	_check_wave_complete()


## Handler for SignalBus.monster_breached.
## Increments resolved counter and breached counter, then checks wave completion.
func _on_monster_breached(_position: Vector2, _path: Array) -> void:
	if _wave_number <= 0:
		return
	_enemies_resolved += 1
	_enemies_breached += 1
	_check_wave_complete()


## Check if the wave is complete: all monsters spawned AND all resolved.
## If complete, starts the inter-wave pause timer.
func _check_wave_complete() -> void:
	if _is_inter_wave_pause:
		return
	if _enemies_spawned >= _enemies_total and _enemies_resolved >= _enemies_total:
		_start_inter_wave_pause()


## Begin the 3-second inter-wave pause. When the timer expires,
## _on_inter_wave_expired emits wave_ended.
func _start_inter_wave_pause() -> void:
	_is_inter_wave_pause = true
	_spawn_timer.stop()
	_inter_wave_timer.wait_time = INTER_WAVE_PAUSE
	_inter_wave_timer.start()


## Inter-wave pause timer callback.
## Emits wave_ended signal with statistics. PhaseManager should
## listen to wave_ended and transition BATTLE -> PREP.
func _on_inter_wave_expired() -> void:
	_is_inter_wave_pause = false
	_emit_wave_ended()


# ═══════════════════════════════════════════════════════════════════════════════════
# MonsterData Loading
# ═══════════════════════════════════════════════════════════════════════════════════


## Load MonsterData resource for the given monster_id.
## Loads from res://src/resources/monsters/{monster_id}.tres.
## Caches loaded resources in _monster_data_cache.
## Returns null if the .tres file cannot be loaded or is invalid.
func _load_monster_data(monster_id: String) -> MonsterData:
	if _monster_data_cache.has(monster_id):
		return _monster_data_cache[monster_id] as MonsterData

	var path: String = MONSTER_DATA_PATH + monster_id + ".tres"
	if not ResourceLoader.exists(path):
		push_warning("WaveSpawner._load_monster_data: Resource not found: %s" % path)
		return null

	var resource := load(path) as MonsterData
	if resource == null:
		push_error("WaveSpawner._load_monster_data: Failed to load MonsterData from: %s" % path)
		return null

	if resource.monster_id != monster_id:
		push_error("WaveSpawner._load_monster_data: monster_id mismatch in %s (expected '%s', got '%s')" % [path, monster_id, resource.monster_id])
		return null

	_monster_data_cache[monster_id] = resource
	return resource


# ═══════════════════════════════════════════════════════════════════════════════════
# Entrance Position
# ═══════════════════════════════════════════════════════════════════════════════════


## Scan the BoardGrid to locate the ENTRANCE cell and cache its world position.
## Runs once; subsequent calls are no-ops.
func _cache_entrance() -> void:
	if _entrance_found:
		return
	if _board == null:
		push_error("WaveSpawner._cache_entrance: BoardGrid not initialized")
		return

	for row in range(_board.rows):
		for col in range(_board.cols):
			if _board.get_cell_state(col, row) == BoardGrid.CellState.ENTRANCE:
				_entrance_world = _board.grid_to_world(col, row)
				_entrance_found = true
				return

	push_error("WaveSpawner._cache_entrance: No ENTRANCE cell found on board")


# ═══════════════════════════════════════════════════════════════════════════════════
# Signal Emission Helpers
# ═══════════════════════════════════════════════════════════════════════════════════


func _emit_wave_started() -> void:
	if has_node("/root/SignalBus"):
		SignalBus.wave_started.emit(_wave_number)


func _emit_wave_ended() -> void:
	if has_node("/root/SignalBus"):
		SignalBus.wave_ended.emit(_wave_number, _enemies_killed, _enemies_breached)


# ═══════════════════════════════════════════════════════════════════════════════════
# Game Reset (ADR-0008)
# ═══════════════════════════════════════════════════════════════════════════════════


## Handle game reset — clear all wave state and return to initial conditions.
## Connected to SignalBus.game_reset_requested in production.
func _on_game_reset() -> void:
	_spawn_timer.stop()
	_inter_wave_timer.stop()
	_wave_number = 0
	_wave_rules = null
	_current_rule_index = 0
	_current_rule_spawned = 0
	_enemies_total = 0
	_enemies_spawned = 0
	_enemies_resolved = 0
	_enemies_killed = 0
	_enemies_breached = 0
	_is_spawning = false
	_is_inter_wave_pause = false
	_current_phase = PHASE_PREP
