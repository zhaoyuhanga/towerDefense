extends GdUnitTestSuite
## Unit tests for WaveSpawner.
## Implements acceptance criteria from design/gdd/wave-spawner.md.
## Covers: spawn scheduling, health scaling by wave tier, phase gating,
## monster death/breach tracking, wave completion signals, inter-wave pause,
## edge cases (empty rules, invalid monster_id, all breached), game reset.


# ── Phase Constants (mirrors PhaseManager enum — ADR-0006) ───────────────────────

const PHASE_PREP: int = 0
const PHASE_BATTLE: int = 1


# ── Test Fixtures ────────────────────────────────────────────────────────────────

var _spawner: WaveSpawner
var _board: BoardGrid
var _monster_pool: MonsterPool
var _data_cache: Dictionary = {}    # {String: MonsterData} — reused across tests
var _scene_cache: Dictionary = {}   # {String: PackedScene} — reused across tests

# Signal tracking
var _wave_started_signals: Array = []   # tracks (wave_number) emitted via SignalBus
var _wave_ended_signals: Array = []     # tracks (wave_number, enemies_killed, enemies_breached)


func before() -> void:
	# BoardGrid: 20×15, entrance at (0,7), exit at (19,7)
	_board = BoardGrid.new()
	_board.init(20, 15, Vector2i(0, 7), Vector2i(19, 7))

	# MonsterPool: fresh instance for each test
	_monster_pool = MonsterPool.new()

	# WaveSpawner: init with board and pool
	_spawner = WaveSpawner.new()
	_spawner.init(_board, _monster_pool)

	# Clear signal tracking
	_wave_started_signals.clear()
	_wave_ended_signals.clear()

	# Subscribe to SignalBus signals for verification
	if has_node("/root/SignalBus"):
		if not SignalBus.wave_started.is_connected(_track_wave_started):
			SignalBus.wave_started.connect(_track_wave_started)
		if not SignalBus.wave_ended.is_connected(_track_wave_ended):
			SignalBus.wave_ended.connect(_track_wave_ended)


func after() -> void:
	# Stop timers
	if is_instance_valid(_spawner):
		_spawner._spawn_timer.stop()
		_spawner._inter_wave_timer.stop()

	# Disconnect spawner from SignalBus
	if has_node("/root/SignalBus"):
		if SignalBus.phase_changed.is_connected(_spawner._on_phase_changed):
			SignalBus.phase_changed.disconnect(_spawner._on_phase_changed)
		if SignalBus.monster_died.is_connected(_spawner._on_monster_died):
			SignalBus.monster_died.disconnect(_spawner._on_monster_died)
		if SignalBus.monster_breached.is_connected(_spawner._on_monster_breached):
			SignalBus.monster_breached.disconnect(_spawner._on_monster_breached)
		if SignalBus.game_reset_requested.is_connected(_spawner._on_game_reset):
			SignalBus.game_reset_requested.disconnect(_spawner._on_game_reset)

	# Disconnect signal trackers
	if has_node("/root/SignalBus"):
		if SignalBus.wave_started.is_connected(_track_wave_started):
			SignalBus.wave_started.disconnect(_track_wave_started)
		if SignalBus.wave_ended.is_connected(_track_wave_ended):
			SignalBus.wave_ended.disconnect(_track_wave_ended)

	# Free test instances
	if is_instance_valid(_spawner):
		_spawner.free()
	if is_instance_valid(_board):
		_board.free()
	if is_instance_valid(_monster_pool):
		# Free all pooled monsters
		for type_key in _monster_pool._pools.keys():
			for m in _monster_pool._pools[type_key]:
				if is_instance_valid(m):
					m.free()
		for m in _monster_pool._active:
			if is_instance_valid(m):
				m.free()
		_monster_pool.free()

	# Free cached data and scenes
	for key in _data_cache.keys():
		var d: MonsterData = _data_cache[key]
		if is_instance_valid(d):
			d.free()
	_data_cache.clear()
	_scene_cache.clear()

	# Clear signal tracking
	_wave_started_signals.clear()
	_wave_ended_signals.clear()


# ── Helpers ──────────────────────────────────────────────────────────────────────


func _track_wave_started(wave_number: int) -> void:
	_wave_started_signals.append(wave_number)


func _track_wave_ended(wave_number: int, enemies_killed: int, enemies_breached: int) -> void:
	_wave_ended_signals.append({"wave": wave_number, "killed": enemies_killed, "breached": enemies_breached})


## Create a MonsterData resource programmatically (no .tres file dependency).
func _make_monster_data(monster_id: String, health: float, speed: float, reward: int) -> MonsterData:
	var key: String = monster_id
	if _data_cache.has(key):
		return _data_cache[key]

	var data := MonsterData.new()
	data.monster_id = monster_id
	data.monster_name = monster_id.capitalize()
	data.health = health
	data.speed = speed
	data.reward_gold = reward
	data.tier = "Standard"
	data.size_ratio = 1.0
	data.has_affix = false
	_data_cache[key] = data
	return data


## Register a monster scene and data in the pool for spawn support.
func _register_monster_type(monster_id: String, health: float = 100.0, speed: float = 60.0, reward: int = 10) -> void:
	# Register MonsterData in spawner's cache so _load_monster_data succeeds
	var data := _make_monster_data(monster_id, health, speed, reward)
	_spawner._monster_data_cache[monster_id] = data

	# Register a PackedScene in the pool
	if not _scene_cache.has(monster_id):
		var scene := PackedScene.new()
		var prototype := TestMonster.new()
		scene.pack(prototype)
		prototype.free()
		_scene_cache[monster_id] = scene

	if not _monster_pool._scenes.has(monster_id):
		_monster_pool.register_scene(monster_id, _scene_cache[monster_id])


## Create a SpawnRule resource programmatically.
func _make_spawn_rule(monster_id: String, count: int, spawn_interval: float, affix_pool: Array[String] = []) -> SpawnRule:
	var rule := SpawnRule.new()
	rule.monster_id = monster_id
	rule.count = count
	rule.spawn_interval = spawn_interval
	rule.affix_pool = affix_pool.duplicate()
	return rule


## Create a WaveRules resource from an array of SpawnRules.
func _make_wave_rules(rules: Array[SpawnRule], wave_start: int = 1, wave_end: int = 1) -> WaveRules:
	var wave_rules := WaveRules.new()
	wave_rules.wave_range_start = wave_start
	wave_rules.wave_range_end = wave_end
	for rule in rules:
		wave_rules.rules.append(rule)
	return wave_rules


## Simulate a PREP->BATTLE phase transition through the spawner.
## This triggers wave spawning via the normal SignalBus path.
func _simulate_phase_transition_to_battle() -> void:
	_spawner._current_phase = PHASE_PREP  # ensure starting from PREP
	_spawner._on_phase_changed(PHASE_PREP, PHASE_BATTLE)


## Manually add recently spawned monsters to the spawner scene tree.
## MonsterPool.spawn() uses call_deferred for add_child — this simulates it.
func _add_spawned_children() -> void:
	for child in _spawner.get_children():
		if child is TestMonster and not child.is_inside_tree():
			# Already added by spawn's call_deferred, or we add it now
			pass


## Simulate killing a monster by emitting monster_died via SignalBus.
func _simulate_monster_kill() -> void:
	if has_node("/root/SignalBus"):
		SignalBus.monster_died.emit("test_123", Vector2.ZERO, 10)


## Simulate a monster breaching by emitting monster_breached via SignalBus.
func _simulate_monster_breach() -> void:
	if has_node("/root/SignalBus"):
		SignalBus.monster_breached.emit(Vector2.ZERO, [])


## Pipe through the inter-wave pause immediately (bypass real 3s timer).
func _fast_forward_inter_wave_pause() -> void:
	_spawner._on_inter_wave_expired()


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 1: Wave 1 spawns exactly 5 basic monsters at 1s intervals
# GDD AC: GIVEN wave 1 starts, WHEN WaveRules specifies 5 basic monsters
#         at 1s intervals, THEN exactly 5 spawn, each at 1s intervals
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_spawner_spawns_exact_count_at_specified_intervals() -> void:
	# Arrange
	_register_monster_type("basic", 100.0, 60.0, 10)
	var rule := _make_spawn_rule("basic", 5, 1.0)
	var wave_rules := _make_wave_rules([rule])
	_spawner.set_wave_rules(wave_rules)

	# Act: trigger wave start via phase transition
	_simulate_phase_transition_to_battle()

	# Assert
	assert_int(_spawner.get_wave_number()).is_equal(1)
	assert_int(_spawner._enemies_total).is_equal(5)
	assert_int(_spawner._enemies_spawned).is_equal(1)  # first monster spawned immediately
	assert_bool(_spawner._is_spawning).is_true()
	assert_bool(_spawner._is_inter_wave_pause).is_false()

	# Verify wave_started signal was emitted with correct wave number
	if has_node("/root/SignalBus"):
		assert_int(_wave_started_signals.size()).is_equal(1)
		assert_int(_wave_started_signals[0]).is_equal(1)

	# Simulate remaining spawn ticks at 1.0s intervals
	for i in range(2, 6):  # spawns 2, 3, 4, 5
		_spawner._on_spawn_tick()
		assert_int(_spawner._enemies_spawned).is_equal(i)
		assert_float(_spawner._spawn_timer.wait_time).is_equal(1.0)

	# After 5th spawn, spawning should be complete
	assert_bool(_spawner._is_spawning).is_false()
	assert_int(_spawner._enemies_spawned).is_equal(5)

	# Verify MonsterPool has 5 active monsters (minus call_deferred — monsters
	# may not be in tree yet, but pool tracks them in _active)
	assert_int(_monster_pool.get_active_count()).is_equal(5)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 2: wave_ended signal fires after all monsters killed + 3s pause
# GDD AC: GIVEN all monsters killed in wave, WHEN last one dies,
#         THEN wave_ended signal fires after 3s
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_spawner_emits_wave_ended_after_all_killed_and_pause() -> void:
	# Arrange: wave with 3 monsters
	_register_monster_type("basic", 100.0, 60.0, 10)
	var rule := _make_spawn_rule("basic", 3, 0.1)
	var wave_rules := _make_wave_rules([rule])
	_spawner.set_wave_rules(wave_rules)

	# Act: start wave, complete all spawns
	_simulate_phase_transition_to_battle()
	_spawner._on_spawn_tick()  # spawn 2
	_spawner._on_spawn_tick()  # spawn 3 — spawning complete
	assert_int(_spawner._enemies_spawned).is_equal(3)
	assert_bool(_spawner._is_spawning).is_false()

	# Verify wave_ended NOT yet emitted (monsters still alive)
	if has_node("/root/SignalBus"):
		assert_int(_wave_ended_signals.size()).is_equal(0)

	# Kill all 3 monsters
	for _i in range(3):
		_simulate_monster_kill()

	# Verify inter-wave pause started
	assert_bool(_spawner._is_inter_wave_pause).is_true()
	assert_int(_spawner._enemies_killed).is_equal(3)
	assert_int(_spawner._enemies_breached).is_equal(0)

	# Verify wave_ended NOT yet emitted (3s pause not expired)
	if has_node("/root/SignalBus"):
		assert_int(_wave_ended_signals.size()).is_equal(0)

	# Fast-forward the inter-wave pause
	_fast_forward_inter_wave_pause()

	# Assert: wave_ended emitted with correct stats
	if has_node("/root/SignalBus"):
		assert_int(_wave_ended_signals.size()).is_equal(1)
		assert_int(_wave_ended_signals[0]["wave"]).is_equal(1)
		assert_int(_wave_ended_signals[0]["killed"]).is_equal(3)
		assert_int(_wave_ended_signals[0]["breached"]).is_equal(0)

	assert_bool(_spawner._is_inter_wave_pause).is_false()


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 3: Health scaling by wave tier
# Wave 1-10:  health *= 1.0 + wave * 0.1
# Wave 11-25: health *= 1.0 + wave * 0.2
# Wave 26+:   health *= 1.0 + wave * 0.2
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_spawner_health_scaling_wave_1_linear() -> void:
	# Arrange: base health = 100, wave 5
	var data := _make_monster_data("test", 100.0, 60.0, 10)

	# Act
	var scaled := _spawner._apply_health_scaling(data, 5)

	# Assert: multiplier = 1.0 + 5 * 0.1 = 1.5, health = 150
	assert_float(scaled.health).is_equal(150.0)
	assert_float(data.health).is_equal(100.0)  # original unchanged


func test_wave_spawner_health_scaling_wave_10_boundary() -> void:
	var data := _make_monster_data("test", 100.0, 60.0, 10)

	var scaled := _spawner._apply_health_scaling(data, 10)

	# multiplier = 1.0 + 10 * 0.1 = 2.0
	assert_float(scaled.health).is_equal(200.0)


func test_wave_spawner_health_scaling_wave_11_accelerated() -> void:
	var data := _make_monster_data("test", 100.0, 60.0, 10)

	var scaled := _spawner._apply_health_scaling(data, 11)

	# multiplier = 1.0 + 11 * 0.2 = 3.2
	assert_float(scaled.health).is_equal(320.0)


func test_wave_spawner_health_scaling_wave_25_end_of_tier_2() -> void:
	var data := _make_monster_data("test", 100.0, 60.0, 10)

	var scaled := _spawner._apply_health_scaling(data, 25)

	# multiplier = 1.0 + 25 * 0.2 = 6.0
	assert_float(scaled.health).is_equal(600.0)


func test_wave_spawner_health_scaling_wave_26_tier_3() -> void:
	var data := _make_monster_data("test", 100.0, 60.0, 10)

	var scaled := _spawner._apply_health_scaling(data, 26)

	# multiplier = 1.0 + 26 * 0.2 = 6.2
	assert_float(scaled.health).is_equal(620.0)


func test_wave_spawner_health_scaling_wave_1_is_multiplied_not_additive() -> void:
	var data := _make_monster_data("test", 50.0, 60.0, 10)

	var scaled := _spawner._apply_health_scaling(data, 1)

	# multiplier = 1.0 + 1 * 0.1 = 1.1, health = 55.0
	assert_float(scaled.health).is_equal(55.0)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 4: Phase gating — spawn only in BATTLE phase
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_spawner_does_not_spawn_during_prep_phase() -> void:
	# Arrange: stay in PREP, set up wave rules
	_register_monster_type("basic", 100.0, 60.0, 10)
	var rule := _make_spawn_rule("basic", 5, 1.0)
	_spawner.set_wave_rules(_make_wave_rules([rule]))

	# Assert: no wave active yet
	assert_int(_spawner.get_wave_number()).is_equal(0)
	assert_bool(_spawner.is_wave_active()).is_false()
	assert_int(_spawner._enemies_total).is_equal(0)


func test_wave_spawner_phase_transition_triggers_spawn() -> void:
	# Arrange
	_register_monster_type("basic", 100.0, 60.0, 10)
	var rule := _make_spawn_rule("basic", 3, 0.5)
	_spawner.set_wave_rules(_make_wave_rules([rule]))

	# Act: PREP -> BATTLE
	_simulate_phase_transition_to_battle()

	# Assert
	assert_int(_spawner.get_wave_number()).is_equal(1)
	assert_bool(_spawner.is_wave_active()).is_true()
	assert_int(_spawner._enemies_spawned).is_equal(1)


func test_wave_spawner_battle_to_prep_stops_timer() -> void:
	# Arrange: start a wave
	_register_monster_type("basic", 100.0, 60.0, 10)
	var rule := _make_spawn_rule("basic", 10, 1.0)
	_spawner.set_wave_rules(_make_wave_rules([rule]))
	_simulate_phase_transition_to_battle()

	# Spawn timer should be running (more monsters to spawn)
	assert_bool(_spawner._spawn_timer.is_stopped()).is_false()

	# Act: BATTLE -> PREP
	_spawner._on_phase_changed(PHASE_BATTLE, PHASE_PREP)

	# Assert: timers stopped, spawning aborted
	assert_bool(_spawner._spawn_timer.is_stopped()).is_true()
	assert_bool(_spawner._inter_wave_timer.is_stopped()).is_true()
	assert_bool(_spawner._is_spawning).is_false()


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 5: Multiple waves increment wave_number correctly
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_spawner_multiple_waves_increment_wave_number() -> void:
	_register_monster_type("basic", 100.0, 60.0, 10)
	var rule := _make_spawn_rule("basic", 1, 0.1)

	# Wave 1
	_spawner.set_wave_rules(_make_wave_rules([rule]))
	_simulate_phase_transition_to_battle()
	assert_int(_spawner.get_wave_number()).is_equal(1)
	# Complete wave 1
	_spawner._on_spawn_tick() if _spawner._is_spawning else null  # spawn remaining if needed
	while _spawner._is_spawning:
		_spawner._on_spawn_tick()
	_simulate_monster_kill()  # kill the 1 monster
	_fast_forward_inter_wave_pause()

	# Reset for wave 2: simulate PREP phase, load new rules
	_spawner.set_wave_rules(_make_wave_rules([rule]))
	_spawner._on_phase_changed(PHASE_PREP, PHASE_BATTLE)
	assert_int(_spawner.get_wave_number()).is_equal(2)

	# Complete wave 2
	while _spawner._is_spawning:
		_spawner._on_spawn_tick()
	_simulate_monster_kill()
	_fast_forward_inter_wave_pause()

	# Wave 3
	_spawner.set_wave_rules(_make_wave_rules([rule]))
	_spawner._on_phase_changed(PHASE_PREP, PHASE_BATTLE)
	assert_int(_spawner.get_wave_number()).is_equal(3)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 6: Edge case — empty WaveRules (0 monsters)
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_spawner_empty_wave_rules_emits_wave_ended_immediately() -> void:
	# Arrange: WaveRules with zero spawn rules
	_spawner.set_wave_rules(_make_wave_rules([]))

	# Act: trigger wave start
	_simulate_phase_transition_to_battle()

	# Assert: wave started and immediately entered inter-wave pause
	assert_int(_spawner.get_wave_number()).is_equal(1)
	assert_int(_spawner._enemies_total).is_equal(0)
	assert_bool(_spawner._is_spawning).is_false()
	assert_bool(_spawner._is_inter_wave_pause).is_true()

	# Fast-forward pause
	_fast_forward_inter_wave_pause()

	# Assert: wave_ended emitted with zero stats
	if has_node("/root/SignalBus"):
		assert_int(_wave_ended_signals.size()).is_equal(1)
		assert_int(_wave_ended_signals[0]["wave"]).is_equal(1)
		assert_int(_wave_ended_signals[0]["killed"]).is_equal(0)
		assert_int(_wave_ended_signals[0]["breached"]).is_equal(0)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 7: Edge case — invalid monster_id is skipped
# GDD: SpawnRule references non-existent monster ID → skip that ID
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_spawner_skips_invalid_monster_id() -> void:
	# Arrange: rule with invalid monster_id, no scene/data registered
	_register_monster_type("valid", 100.0, 60.0, 10)
	var rule1 := _make_spawn_rule("invalid_monster", 2, 0.1)
	var rule2 := _make_spawn_rule("valid", 1, 0.1)
	_spawner.set_wave_rules(_make_wave_rules([rule1, rule2]))

	# Act: start wave
	_simulate_phase_transition_to_battle()

	# The spawner spawned 1 (from rule1, but invalid — skipped),
	# then rule1 counter = 1. Next tick: rule1 counter = 2 (also skipped).
	# Then next rule: valid spawns 1.
	# Total spawned: 1 valid, 2 skipped (but _enemies_spawned still increments)

	# Actually: _spawn_one is called but returns without spawning.
	# _enemies_spawned increments regardless.
	# _enemies_total = 3 (2 invalid + 1 valid)

	assert_int(_spawner._enemies_total).is_equal(3)
	assert_int(_spawner._enemies_spawned).is_equal(1)  # first invalid "spawned"
	assert_int(_monster_pool.get_active_count()).is_equal(0)  # no actual monster spawned

	# Complete remaining spawns
	_spawner._on_spawn_tick()  # invalid #2
	_spawner._on_spawn_tick()  # valid #1
	assert_int(_spawner._enemies_spawned).is_equal(3)
	assert_int(_monster_pool.get_active_count()).is_equal(1)

	# Kill the valid monster to complete wave
	_simulate_monster_kill()
	_fast_forward_inter_wave_pause()

	if has_node("/root/SignalBus"):
		assert_int(_wave_ended_signals.size()).is_equal(1)
		assert_int(_wave_ended_signals[0]["killed"]).is_equal(1)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 8: Edge case — all monsters breach (no kills)
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_spawner_all_monsters_breached_counts_correctly() -> void:
	# Arrange
	_register_monster_type("fast", 50.0, 120.0, 5)
	var rule := _make_spawn_rule("fast", 2, 0.1)
	_spawner.set_wave_rules(_make_wave_rules([rule]))

	# Act: start wave, complete spawns
	_simulate_phase_transition_to_battle()
	_spawner._on_spawn_tick()  # spawn 2

	# Both monsters breach
	_simulate_monster_breach()
	_simulate_monster_breach()

	# Assert
	assert_int(_spawner._enemies_breached).is_equal(2)
	assert_int(_spawner._enemies_killed).is_equal(0)
	assert_bool(_spawner._is_inter_wave_pause).is_true()

	_fast_forward_inter_wave_pause()

	if has_node("/root/SignalBus"):
		assert_int(_wave_ended_signals[0]["killed"]).is_equal(0)
		assert_int(_wave_ended_signals[0]["breached"]).is_equal(2)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 9: Mixed kills and breaches in one wave
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_spawner_mixed_kills_and_breaches() -> void:
	# Arrange: 4 monsters total
	_register_monster_type("mixed", 75.0, 80.0, 10)
	var rule := _make_spawn_rule("mixed", 4, 0.05)
	_spawner.set_wave_rules(_make_wave_rules([rule]))

	# Start wave, complete spawns
	_simulate_phase_transition_to_battle()
	for _i in range(3):
		_spawner._on_spawn_tick()  # spawn 2, 3, 4

	# 2 killed, 2 breached
	_simulate_monster_kill()
	_simulate_monster_kill()
	_simulate_monster_breach()
	_simulate_monster_breach()

	# Assert
	assert_int(_spawner._enemies_killed).is_equal(2)
	assert_int(_spawner._enemies_breached).is_equal(2)
	assert_int(_spawner._enemies_resolved).is_equal(4)
	assert_bool(_spawner._is_inter_wave_pause).is_true()

	_fast_forward_inter_wave_pause()

	if has_node("/root/SignalBus"):
		assert_int(_wave_ended_signals[0]["killed"]).is_equal(2)
		assert_int(_wave_ended_signals[0]["breached"]).is_equal(2)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 10: Monsters killed before all have spawned — wave continues normally
# GDD edge case: all currently spawned monsters killed before next spawn timer
#                → wait for timer → spawn next → wave continues
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_spawner_early_kills_do_not_end_wave() -> void:
	# Arrange: 3 monsters total
	_register_monster_type("basic", 100.0, 60.0, 10)
	var rule := _make_spawn_rule("basic", 3, 0.5)
	_spawner.set_wave_rules(_make_wave_rules([rule]))

	# Start wave: 1st monster spawned
	_simulate_phase_transition_to_battle()
	assert_int(_spawner._enemies_spawned).is_equal(1)

	# Kill the first monster immediately
	_simulate_monster_kill()
	assert_int(_spawner._enemies_resolved).is_equal(1)

	# Wave should NOT be complete (still 2 more to spawn)
	assert_bool(_spawner._is_spawning).is_true()
	assert_bool(_spawner._is_inter_wave_pause).is_false()

	# Spawn second monster
	_spawner._on_spawn_tick()
	assert_int(_spawner._enemies_spawned).is_equal(2)

	# Kill second monster, spawn third
	_simulate_monster_kill()
	_spawner._on_spawn_tick()
	assert_int(_spawner._enemies_spawned).is_equal(3)
	assert_bool(_spawner._is_spawning).is_false()

	# Kill third monster — now wave complete
	_simulate_monster_kill()
	assert_bool(_spawner._is_inter_wave_pause).is_true()

	_fast_forward_inter_wave_pause()
	if has_node("/root/SignalBus"):
		assert_int(_wave_ended_signals.size()).is_equal(1)
		assert_int(_wave_ended_signals[0]["killed"]).is_equal(3)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 11: wave_started / wave_ended signal parameters are correct
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_started_signal_emitted_with_correct_wave_number() -> void:
	_register_monster_type("basic", 100.0, 60.0, 10)
	var rule := _make_spawn_rule("basic", 1, 0.1)

	# Wave 1
	_spawner.set_wave_rules(_make_wave_rules([rule]))
	_simulate_phase_transition_to_battle()

	if has_node("/root/SignalBus"):
		assert_int(_wave_started_signals.size()).is_equal(1)
		assert_int(_wave_started_signals[0]).is_equal(1)

	# Complete wave 1
	while _spawner._is_spawning:
		_spawner._on_spawn_tick()
	_simulate_monster_kill()
	_fast_forward_inter_wave_pause()

	# Wave 2
	_spawner.set_wave_rules(_make_wave_rules([rule]))
	_spawner._on_phase_changed(PHASE_PREP, PHASE_BATTLE)

	if has_node("/root/SignalBus"):
		assert_int(_wave_started_signals.size()).is_equal(2)
		assert_int(_wave_started_signals[1]).is_equal(2)

	# Complete wave 2
	while _spawner._is_spawning:
		_spawner._on_spawn_tick()
	_simulate_monster_kill()
	_fast_forward_inter_wave_pause()

	# Wave 3
	_spawner.set_wave_rules(_make_wave_rules([rule]))
	_spawner._on_phase_changed(PHASE_PREP, PHASE_BATTLE)

	if has_node("/root/SignalBus"):
		assert_int(_wave_started_signals.size()).is_equal(3)
		assert_int(_wave_started_signals[2]).is_equal(3)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 12: Game reset clears all state (ADR-0008)
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_spawner_game_reset_clears_all_state() -> void:
	# Arrange: start a wave, progress partway
	_register_monster_type("basic", 100.0, 60.0, 10)
	var rule := _make_spawn_rule("basic", 5, 0.5)
	_spawner.set_wave_rules(_make_wave_rules([rule]))
	_simulate_phase_transition_to_battle()
	_spawner._on_spawn_tick()  # spawn 2
	_spawner._on_spawn_tick()  # spawn 3
	_simulate_monster_kill()

	# Verify non-initial state
	assert_int(_spawner.get_wave_number()).is_equal(1)
	assert_int(_spawner._enemies_spawned).is_equal(3)
	assert_int(_spawner._enemies_resolved).is_equal(1)
	assert_bool(_spawner._is_spawning).is_true()

	# Act: game reset
	_spawner._on_game_reset()

	# Assert: all state cleared to initial values
	assert_int(_spawner.get_wave_number()).is_equal(0)
	assert_int(_spawner._enemies_total).is_equal(0)
	assert_int(_spawner._enemies_spawned).is_equal(0)
	assert_int(_spawner._enemies_resolved).is_equal(0)
	assert_int(_spawner._enemies_killed).is_equal(0)
	assert_int(_spawner._enemies_breached).is_equal(0)
	assert_bool(_spawner._is_spawning).is_false()
	assert_bool(_spawner._is_inter_wave_pause).is_false()
	assert_int(_spawner._current_phase).is_equal(PHASE_PREP)
	assert_object(_spawner._wave_rules).is_null()
	assert_int(_spawner._current_rule_index).is_equal(0)
	assert_int(_spawner._current_rule_spawned).is_equal(0)
	assert_bool(_spawner._spawn_timer.is_stopped()).is_true()
	assert_bool(_spawner._inter_wave_timer.is_stopped()).is_true()


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 13: WaveSpawner with no WaveRules set before phase transition
# Edge case: phase changes to BATTLE but no rules loaded
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_spawner_no_rules_at_phase_transition_errors_gracefully() -> void:
	# Arrange: no WaveRules set
	assert_object(_spawner._wave_rules).is_null()

	# Act: PREP -> BATTLE without rules
	_simulate_phase_transition_to_battle()

	# Assert: wave number still incremented, but spawning aborted
	assert_int(_spawner.get_wave_number()).is_equal(1)
	assert_bool(_spawner._is_spawning).is_false()
	assert_int(_spawner._enemies_total).is_equal(0)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 14: SpawnRule with count=0 is skipped
# Edge case: a rule with zero count should not spawn anything
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_spawner_skips_zero_count_rule() -> void:
	# Arrange
	_register_monster_type("basic", 100.0, 60.0, 10)
	var rule_zero := _make_spawn_rule("basic", 0, 0.1)
	var rule_valid := _make_spawn_rule("basic", 2, 0.1)
	_spawner.set_wave_rules(_make_wave_rules([rule_zero, rule_valid]))

	# Act
	_simulate_phase_transition_to_battle()

	# Assert: first spawn skipped rule_zero, spawned from rule_valid
	assert_int(_spawner._enemies_total).is_equal(2)  # zero-count rule excluded from total
	assert_int(_spawner._enemies_spawned).is_equal(1)
	assert_int(_spawner._current_rule_index).is_equal(1)  # advanced past zero-count rule

	# Spawn remaining
	_spawner._on_spawn_tick()
	assert_int(_spawner._enemies_spawned).is_equal(2)
	assert_bool(_spawner._is_spawning).is_false()


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 15: Multiple SpawnRules in one wave execute sequentially
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_spawner_multiple_rules_execute_sequentially() -> void:
	# Arrange: wave with 2 basic + 1 elite
	_register_monster_type("basic", 100.0, 60.0, 10)
	_register_monster_type("elite", 200.0, 50.0, 25)
	var rule1 := _make_spawn_rule("basic", 2, 0.5)
	var rule2 := _make_spawn_rule("elite", 1, 0.5)
	_spawner.set_wave_rules(_make_wave_rules([rule1, rule2]))

	# Act: start wave
	_simulate_phase_transition_to_battle()

	# First spawn: basic (rule1)
	assert_int(_spawner._enemies_spawned).is_equal(1)
	assert_int(_spawner._current_rule_index).is_equal(0)
	assert_int(_spawner._current_rule_spawned).is_equal(1)

	# Second spawn: basic (rule1)
	_spawner._on_spawn_tick()
	assert_int(_spawner._enemies_spawned).is_equal(2)
	assert_int(_spawner._current_rule_index).is_equal(1)  # advanced to rule2
	assert_int(_spawner._current_rule_spawned).is_equal(1)  # first spawn of rule2

	# Third spawn: elite (rule2)
	_spawner._on_spawn_tick()
	assert_int(_spawner._enemies_spawned).is_equal(3)
	assert_bool(_spawner._is_spawning).is_false()

	# Verify pool: 2 basic + 1 elite active
	assert_int(_monster_pool.get_active_count()).is_equal(3)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 16: is_wave_active() returns correct values at each stage
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_spawner_is_wave_active_state_transitions() -> void:
	_register_monster_type("basic", 100.0, 60.0, 10)
	var rule := _make_spawn_rule("basic", 2, 0.5)
	_spawner.set_wave_rules(_make_wave_rules([rule]))

	# Before wave: inactive
	assert_bool(_spawner.is_wave_active()).is_false()

	# During spawning: active
	_simulate_phase_transition_to_battle()
	assert_bool(_spawner.is_wave_active()).is_true()

	# After spawning, monsters still alive: active
	_spawner._on_spawn_tick()  # spawn 2
	assert_bool(_spawner._is_spawning).is_false()
	assert_bool(_spawner.is_wave_active()).is_true()

	# After all killed, during inter-wave pause: inactive
	_simulate_monster_kill()
	_simulate_monster_kill()
	assert_bool(_spawner._is_inter_wave_pause).is_true()
	assert_bool(_spawner.is_wave_active()).is_false()

	# After inter-wave pause: inactive
	_fast_forward_inter_wave_pause()
	assert_bool(_spawner.is_wave_active()).is_false()


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 17: get_alive_count() tracks correctly through wave lifecycle
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_spawner_get_alive_count_tracks_correctly() -> void:
	_register_monster_type("basic", 100.0, 60.0, 10)
	var rule := _make_spawn_rule("basic", 3, 0.1)
	_spawner.set_wave_rules(_make_wave_rules([rule]))

	# Before wave
	assert_int(_spawner.get_alive_count()).is_equal(0)

	# After first spawn
	_simulate_phase_transition_to_battle()
	assert_int(_spawner.get_alive_count()).is_equal(1)

	# After second spawn
	_spawner._on_spawn_tick()
	assert_int(_spawner.get_alive_count()).is_equal(2)

	# After one kill
	_simulate_monster_kill()
	assert_int(_spawner.get_alive_count()).is_equal(1)

	# After third spawn
	_spawner._on_spawn_tick()
	assert_int(_spawner.get_alive_count()).is_equal(2)

	# After remaining kills
	_simulate_monster_kill()
	_simulate_monster_kill()
	assert_int(_spawner.get_alive_count()).is_equal(0)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 18: Inter-wave pause uses correct 3.0 second duration
# ═══════════════════════════════════════════════════════════════════════════════════

func test_wave_spawner_inter_wave_pause_duration_is_three_seconds() -> void:
	_register_monster_type("basic", 100.0, 60.0, 10)
	var rule := _make_spawn_rule("basic", 1, 0.1)
	_spawner.set_wave_rules(_make_wave_rules([rule]))

	# Start and complete wave
	_simulate_phase_transition_to_battle()
	while _spawner._is_spawning:
		_spawner._on_spawn_tick()
	_simulate_monster_kill()

	# Verify inter-wave timer is set to 3.0 seconds
	assert_bool(_spawner._is_inter_wave_pause).is_true()
	assert_float(_spawner._inter_wave_timer.wait_time).is_equal(WaveSpawner.INTER_WAVE_PAUSE)

	# Verify the constant matches the expected value
	assert_float(WaveSpawner.INTER_WAVE_PAUSE).is_equal(3.0)
