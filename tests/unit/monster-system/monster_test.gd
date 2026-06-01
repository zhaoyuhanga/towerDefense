extends GdUnitTestSuite
## Unit tests for Monster base class and MonsterPool lifecycle.
## Implements acceptance criteria from design/gdd/monster-system.md.
## Covers: setup/reset, take_damage, apply_effect, movement, pool spawn/despawn.

# Test fixtures
var _monster: TestMonster
var _pool: MonsterPool
var _data: MonsterData


func before() -> void:
	_monster = TestMonster.new()
	_data = MonsterData.new()
	_data.monster_id = "test_monster"
	_data.monster_name = "Test Monster"
	_data.health = 100.0
	_data.speed = 60.0
	_data.reward_gold = 10
	_data.tier = "Standard"
	_data.size_ratio = 1.0
	_data.has_affix = false

	_pool = MonsterPool.new()


func after() -> void:
	if is_instance_valid(_monster):
		_monster.free()
	if is_instance_valid(_data):
		_data.free()
	if is_instance_valid(_pool):
		# Free all pooled monsters (off-tree nodes not auto-freed)
		for type_key in _pool._pools.keys():
			for m in _pool._pools[type_key]:
				if is_instance_valid(m):
					m.free()
		# Free any remaining active monsters
		for m in _pool._active:
			if is_instance_valid(m):
				m.free()
		_pool.free()


func after_each() -> void:
	# Ensure monster is clean between tests
	if is_instance_valid(_monster) and _monster.is_active:
		_monster.reset()


# ---------------------------------------------------------------------------
# Helper: create a programmatic PackedScene containing a TestMonster node.
# Used by pool tests — no .tscn files, purely code-generated.
# ---------------------------------------------------------------------------
func _create_test_scene() -> PackedScene:
	var scene := PackedScene.new()
	var prototype := TestMonster.new()
	var result := scene.pack(prototype)
	assert_int(result).is_equal(OK)
	prototype.free()
	return scene


# ===========================================================================
# Test 1: setup() initializes monster state from MonsterData
# ===========================================================================
func test_monster_setup_initializes_from_data() -> void:
	# Act
	_monster.setup(_data)

	# Assert
	assert_bool(_monster.is_active).is_true()
	assert_float(_monster.current_health).is_equal(_data.health)
	assert_object(_monster.data).is_same(_data)
	assert_str(_monster.monster_id).contains("test_monster")
	assert_int(_monster.state as int).is_equal(Monster.MonsterState.SPAWNING as int)


# ===========================================================================
# Test 2: take_damage() reduces health by damage amount
# GDD AC: GIVEN health=100 WHEN take_damage(30) THEN current_health=70
# ===========================================================================
func test_monster_take_damage_reduces_health() -> void:
	# Arrange
	_monster.setup(_data)

	# Act
	_monster.take_damage(30.0)

	# Assert
	assert_float(_monster.current_health).is_equal(70.0)


# ===========================================================================
# Test 3: take_damage() with lethal amount sets DYING state
# GDD AC: GIVEN current_health=10 WHEN take_damage(20) THEN health=0, state=DYING
# ===========================================================================
func test_monster_take_damage_fatal_sets_dying() -> void:
	# Arrange
	_monster.setup(_data)

	# Act
	_monster.take_damage(100.0)

	# Assert
	assert_float(_monster.current_health).is_equal(0.0)
	assert_int(_monster.state as int).is_equal(Monster.MonsterState.DYING as int)


# ===========================================================================
# Test 4: take_damage() no-ops when monster is inactive
# Edge case: calling damage on a monster that was never set up
# ===========================================================================
func test_monster_take_damage_noop_when_inactive() -> void:
	# Arrange: monster is inactive (never setup)

	# Act
	_monster.take_damage(30.0)

	# Assert: health unchanged from default
	assert_float(_monster.current_health).is_equal(0.0)
	assert_bool(_monster.is_active).is_false()


# ===========================================================================
# Test 5: apply_effect("freeze") sets STUNNED state and speed multiplier
# GDD AC: GIVEN freeze WHEN apply_effect(monster, "freeze", 3.0, 0.5)
#         THEN monster is stunned, speed reduced by 50%
# ===========================================================================
func test_monster_apply_effect_freeze_stuns_and_slows() -> void:
	# Arrange
	_monster.setup(_data)

	# Act
	_monster.apply_effect("freeze", 3.0, 0.5)

	# Assert
	assert_int(_monster.state as int).is_equal(Monster.MonsterState.STUNNED as int)
	assert_float(_monster._speed_multiplier).is_equal(0.5)
	assert_int(_monster._effect_timers.size()).is_equal(1)
	# Timer should be one-shot with correct duration
	var timer: Timer = _monster._effect_timers[0]
	assert_float(timer.wait_time).is_equal(3.0)
	assert_bool(timer.one_shot).is_true()


# ===========================================================================
# Test 6: apply_effect() no-ops when monster is inactive
# Edge case: applying effect to a despawned/pooled monster
# ===========================================================================
func test_monster_apply_effect_noop_when_inactive() -> void:
	# Arrange: monster is inactive

	# Act
	_monster.apply_effect("freeze", 3.0, 0.5)

	# Assert: state unchanged, no timers created
	assert_float(_monster._speed_multiplier).is_equal(1.0)
	assert_int(_monster._effect_timers.size()).is_equal(0)
	assert_int(_monster.state as int).is_equal(Monster.MonsterState.SPAWNING as int)


# ===========================================================================
# Test 7: Monster follows world-coordinate path and breaches at exit
# GDD AC: GIVEN monster spawned WHEN reaches last waypoint THEN
#         monster_breached emitted, state becomes BREACHED
# ===========================================================================
func test_monster_movement_reaches_exit_and_breaches() -> void:
	# Arrange: setup with speed=60, path with two waypoints 50px apart
	_monster.setup(_data)
	var path := [Vector2(0.0, 0.0), Vector2(50.0, 0.0)]
	_monster.set_path(path)
	assert_int(_monster.state as int).is_equal(Monster.MonsterState.MOVING as int)

	# Act: one frame at delta=1.0s — step=60 > remaining distance=50
	_monster._process(1.0)

	# Assert: arrived at waypoint, no more waypoints -> breached
	assert_int(_monster.state as int).is_equal(Monster.MonsterState.BREACHED as int)
	assert_bool(_monster.is_active).is_false()
	assert_float(_monster.global_position.x).is_equal(50.0)


# ===========================================================================
# Test 8: MonsterPool.spawn() returns an active monster added to _active
# Uses programmatic PackedScene — no .tscn dependency.
# ===========================================================================
func test_pool_spawn_returns_active_monster() -> void:
	# Arrange
	var parent := Node.new()
	var scene := _create_test_scene()
	_pool.register_scene("test_monster", scene)

	# Act
	var monster := _pool.spawn("test_monster", parent, Vector2(42.0, 77.0), _data)

	# Assert
	assert_object(monster).is_not_null()
	assert_bool(monster.is_active).is_true()
	assert_float(monster.current_health).is_equal(_data.health)
	assert_float(monster.global_position.x).is_equal(42.0)
	assert_float(monster.global_position.y).is_equal(77.0)
	assert_int(_pool.get_active_count()).is_equal(1)
	assert_bool(_pool.get_active_monsters().has(monster)).is_true()

	# Cleanup: manually add_child so deferred call is a no-op, then free
	parent.add_child(monster)
	parent.free()


# ===========================================================================
# Test 9: MonsterPool.despawn() returns monster to pool, removes from _active
# GDD AC: GIVEN monster killed WHEN despawn THEN monster_died emitted
#         and monster returned to pool for reuse
# ===========================================================================
func test_pool_despawn_returns_monster_to_pool() -> void:
	# Arrange: spawn a monster and add to tree so despawn can remove it
	var parent := Node.new()
	var scene := _create_test_scene()
	_pool.register_scene("test_monster", scene)

	var monster := _pool.spawn("test_monster", parent, Vector2(100.0, 200.0), _data)
	# spawn uses call_deferred for add_child — add synchronously here for test
	parent.add_child(monster)

	assert_int(_pool.get_active_count()).is_equal(1)
	assert_int(_pool.get_pooled_count("test_monster")).is_equal(0)

	# Act
	_pool.despawn(monster)

	# Assert: removed from active, added to pool, cleaned up
	assert_int(_pool.get_active_count()).is_equal(0)
	assert_int(_pool.get_pooled_count("test_monster")).is_equal(1)
	assert_bool(monster.is_active).is_false()
	assert_bool(monster.is_inside_tree()).is_false()
	assert_object(monster.data).is_null()

	parent.free()
