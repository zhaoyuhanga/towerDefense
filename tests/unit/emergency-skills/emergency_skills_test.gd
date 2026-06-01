extends GdUnitTestSuite
## Unit tests for EmergencySkills system.
## Implements acceptance criteria from design/gdd/emergency-skills.md.
## Covers: skill activation, phase gating, use tracking, cooldowns,
## per-wave replenishment, game reset, repair callback, edge cases.

# Preload TestMonster class_name so it is available in this test suite
# regardless of test execution order.
const TestMonsterScript = preload("res://tests/unit/monster-system/test_monster.gd")


# ==============================================================================
# Test Fixtures
# ==============================================================================

var _skills: EmergencySkills
var _monster_pool: MonsterPool
var _freeze_config: SkillConfig
var _repair_config: SkillConfig


func before() -> void:
	# Create MonsterPool (no scene tree needed for unit tests)
	_monster_pool = MonsterPool.new()

	# Create freeze skill config
	_freeze_config = SkillConfig.new()
	_freeze_config.skill_id = "freeze"
	_freeze_config.skill_name = "冰冻"
	_freeze_config.duration = 2.0
	_freeze_config.cooldown = 5.0
	_freeze_config.max_uses = 3
	_freeze_config.effect_amount = 0.0  # unused for freeze
	_freeze_config.per_wave_replenish = 1

	# Create repair skill config
	_repair_config = SkillConfig.new()
	_repair_config.skill_id = "repair"
	_repair_config.skill_name = "维修"
	_repair_config.duration = 0.0  # instant
	_repair_config.cooldown = 8.0
	_repair_config.max_uses = 2
	_repair_config.effect_amount = 30.0
	_repair_config.per_wave_replenish = 1

	# Create EmergencySkills and initialize
	_skills = EmergencySkills.new()
	_skills.init(_monster_pool, [_freeze_config, _repair_config])


func after() -> void:
	if is_instance_valid(_skills):
		_skills.free()
	_skills = null
	if is_instance_valid(_monster_pool):
		_monster_pool.free()
	_monster_pool = null
	if is_instance_valid(_freeze_config):
		_freeze_config.free()
	_freeze_config = null
	if is_instance_valid(_repair_config):
		_repair_config.free()
	_repair_config = null


# ==============================================================================
# Helpers
# ==============================================================================


## Set the system into BATTLE phase (skills become usable).
func _enter_battle() -> void:
	_skills._current_phase = EmergencySkills.PHASE_BATTLE


## Create a SkillConfig programmatically for ad-hoc skill testing.
func _make_skill_config(skill_id: String, max_uses: int, cooldown: float,
		per_wave: int = 0, duration: float = 0.0,
		effect_amount: float = 0.0) -> SkillConfig:
	var config := SkillConfig.new()
	config.skill_id = skill_id
	config.skill_name = skill_id.capitalize()
	config.max_uses = max_uses
	config.cooldown = cooldown
	config.per_wave_replenish = per_wave
	config.duration = duration
	config.effect_amount = effect_amount
	return config


## Create and register an active TestMonster in the monster pool.
## Returns the monster for assertions.
func _create_active_monster(pos: Vector2 = Vector2(100, 100)) -> Monster:
	var monster := TestMonsterScript.new()
	var data := _make_monster_data("goblin_standard", 100.0, 60.0, 10)
	monster.setup(data)
	monster.global_position = pos

	# Register scene in pool so get_active_monsters works
	var scene := PackedScene.new()
	var proto := TestMonsterScript.new()
	scene.pack(proto)
	proto.free()
	_monster_pool.register_scene("goblin_standard", scene)

	# Add to pool's active list
	_monster_pool._active.append(monster)

	return monster


## Create a MonsterData resource programmatically (no .tres dependency).
func _make_monster_data(monster_id: String, health: float, speed: float, reward: int) -> MonsterData:
	var data := MonsterData.new()
	data.monster_id = monster_id
	data.monster_name = monster_id.capitalize()
	data.health = health
	data.speed = speed
	data.reward_gold = reward
	data.tier = "Standard"
	data.size_ratio = 1.0
	data.has_affix = false
	return data


# ==============================================================================
# Initialization Tests
# ==============================================================================


## Test: init() loads skill configs and registers both skills.
func test_skills_init_loads_configs() -> void:
	assert_int(_skills.get_remaining_uses("freeze")).is_equal(3)
	assert_int(_skills.get_remaining_uses("repair")).is_equal(2)
	assert_int(_skills.get_max_uses("freeze")).is_equal(3)
	assert_int(_skills.get_max_uses("repair")).is_equal(2)


## Test: init() skips null configs gracefully.
func test_skills_init_skips_null_configs() -> void:
	var es := EmergencySkills.new()
	var pool := MonsterPool.new()
	var configs: Array[SkillConfig] = [null, _freeze_config, null]
	es.init(pool, configs)

	assert_int(es.get_remaining_uses("freeze")).is_equal(3)
	# Only "freeze" registered; nulls skipped
	assert_int(es.get_remaining_uses("repair")).is_equal(0)

	es.free()
	pool.free()


## Test: init() skips empty skill_id configs.
func test_skills_init_skips_empty_skill_id() -> void:
	var es := EmergencySkills.new()
	var pool := MonsterPool.new()
	var bad_config := SkillConfig.new()
	bad_config.skill_id = ""
	bad_config.max_uses = 5
	var configs: Array[SkillConfig] = [bad_config, _freeze_config]
	es.init(pool, configs)

	assert_int(es.get_remaining_uses("freeze")).is_equal(3)
	assert_int(es.get_remaining_uses("")).is_equal(0)

	es.free()
	pool.free()
	bad_config.free()


## Test: init() skips duplicate skill_ids.
func test_skills_init_skips_duplicate_skill_ids() -> void:
	var es := EmergencySkills.new()
	var pool := MonsterPool.new()
	var dup_config := SkillConfig.new()
	dup_config.skill_id = "freeze"
	dup_config.max_uses = 99
	var configs: Array[SkillConfig] = [_freeze_config, dup_config]
	es.init(pool, configs)

	# First registration wins; duplicate skipped
	assert_int(es.get_max_uses("freeze")).is_equal(3)
	assert_int(es.get_remaining_uses("freeze")).is_equal(3)

	es.free()
	pool.free()
	dup_config.free()


# ==============================================================================
# Skill Activation Tests
# ==============================================================================


## Test: activate_skill("freeze") succeeds in BATTLE phase.
## GDD AC: GIVEN freeze available + monsters moving, WHEN skill activated,
##         THEN all monsters stop moving for 2 seconds.
func test_skills_activate_freeze_in_battle_succeeds() -> void:
	# Arrange: enter BATTLE, create a moving monster
	_enter_battle()
	var monster := _create_active_monster()
	monster.state = Monster.MonsterState.MOVING
	assert_float(monster._speed_multiplier).is_equal(1.0)

	# Act
	var result := _skills.activate_skill("freeze")

	# Assert
	assert_bool(result, "activate_skill should return true").is_true()
	assert_int(_skills.get_remaining_uses("freeze")).is_equal(2)
	# Monster should now be frozen
	assert_float(monster._speed_multiplier).is_equal(0.0)
	assert_int(monster.state as int).is_equal(Monster.MonsterState.STUNNED as int)
	# Cooldown started
	assert_float(_skills.get_cooldown_remaining("freeze")).is_equal(5.0)

	# Cleanup
	monster.free()


## Test: activate_skill("freeze") consumes one use.
func test_skills_activate_freeze_consumes_use() -> void:
	_enter_battle()

	_skills.activate_skill("freeze")
	assert_int(_skills.get_remaining_uses("freeze")).is_equal(2)

	_skills.activate_skill("freeze")
	assert_int(_skills.get_remaining_uses("freeze")).is_equal(1)

	_skills.activate_skill("freeze")
	assert_int(_skills.get_remaining_uses("freeze")).is_equal(0)


## Test: activate_skill("repair") invokes repair callback with correct amount.
func test_skills_activate_repair_invokes_callback() -> void:
	# Arrange: set up a callback that captures the amount
	_enter_battle()
	var captured_amount: float = -1.0
	_skills.repair_callback = func(amount: float): captured_amount = amount

	# Act
	var result := _skills.activate_skill("repair")

	# Assert
	assert_bool(result).is_true()
	assert_float(captured_amount).is_equal(30.0)
	assert_int(_skills.get_remaining_uses("repair")).is_equal(1)


## Test: activate_skill in PREP phase is rejected.
## GDD: 技能按钮仅在战斗阶段可用。准备阶段不显示/不可用。
func test_skills_activate_in_prep_is_rejected() -> void:
	# Current phase is PREP (default after init)
	var result := _skills.activate_skill("freeze")

	assert_bool(result).is_false()
	assert_int(_skills.get_remaining_uses("freeze")).is_equal(3)  # unchanged


## Test: activate_skill with zero uses returns false.
## GDD AC: GIVEN freeze uses=0, WHEN button clicked, THEN no response.
func test_skills_activate_no_uses_rejected() -> void:
	_enter_battle()
	# Consume all 3 uses
	_skills.activate_skill("freeze")  # -> 2
	_skills.activate_skill("freeze")  # -> 1
	_skills.activate_skill("freeze")  # -> 0

	# Act: try to use when 0 remaining
	var result := _skills.activate_skill("freeze")

	# Assert
	assert_bool(result).is_false()
	assert_int(_skills.get_remaining_uses("freeze")).is_equal(0)


## Test: activate_skill on cooldown returns false.
func test_skills_activate_on_cooldown_rejected() -> void:
	_enter_battle()
	_skills.activate_skill("freeze")  # Now on cooldown (5.0s)

	# Act: try to use again immediately
	var result := _skills.activate_skill("freeze")

	# Assert
	assert_bool(result).is_false()
	assert_int(_skills.get_remaining_uses("freeze")).is_equal(2)  # unchanged


## Test: activate_skill with unknown skill_id returns false.
func test_skills_activate_unknown_skill_rejected() -> void:
	_enter_battle()
	var result := _skills.activate_skill("lightning")

	assert_bool(result).is_false()


# ==============================================================================
# Freeze Effect Tests
# ==============================================================================


## Test: freeze applies effect with speed=0.0 to all active monsters.
func test_skills_freeze_stops_all_active_monsters() -> void:
	_enter_battle()
	var m1 := _create_active_monster(Vector2(100, 100))
	m1.state = Monster.MonsterState.MOVING
	var m2 := _create_active_monster(Vector2(200, 200))
	m2.state = Monster.MonsterState.MOVING
	var m3 := _create_active_monster(Vector2(300, 300))
	m3.state = Monster.MonsterState.MOVING

	# Act
	_skills.activate_skill("freeze")

	# Assert: all 3 monsters frozen
	assert_float(m1._speed_multiplier).is_equal(0.0)
	assert_int(m1.state as int).is_equal(Monster.MonsterState.STUNNED as int)
	assert_float(m2._speed_multiplier).is_equal(0.0)
	assert_int(m2.state as int).is_equal(Monster.MonsterState.STUNNED as int)
	assert_float(m3._speed_multiplier).is_equal(0.0)
	assert_int(m3.state as int).is_equal(Monster.MonsterState.STUNNED as int)

	# Cleanup
	for m in [m1, m2, m3]:
		m.free()


## Test: freeze does not crash when no active monsters.
func test_skills_freeze_no_monsters_no_crash() -> void:
	_enter_battle()

	# Act + Assert: should not crash with empty active list
	var result := _skills.activate_skill("freeze")
	assert_bool(result).is_true()


## Test: freeze skips dead/breached monsters (they are not in active list).
## GDD edge case: 怪物已死亡 -- 不施加效果.
func test_skills_freeze_skips_dead_monsters() -> void:
	_enter_battle()
	# Only 1 active monster -- no dead/breached ones in pool
	var m_alive := _create_active_monster(Vector2(100, 100))
	m_alive.state = Monster.MonsterState.MOVING

	# Act
	_skills.activate_skill("freeze")

	# Assert: only alive monster frozen
	assert_float(m_alive._speed_multiplier).is_equal(0.0)

	m_alive.free()


# ==============================================================================
# Cooldown Tests
# ==============================================================================


## Test: Cooldown ticks down during BATTLE phase.
func test_skills_cooldown_ticks_down_in_battle() -> void:
	_enter_battle()
	_skills.activate_skill("freeze")

	# Initially cooldown is 5.0
	assert_float(_skills.get_cooldown_remaining("freeze")).is_equal(5.0)
	assert_bool(_skills.can_activate("freeze")).is_false()

	# Act: tick 2 seconds
	_skills._process(2.0)

	# Assert
	assert_float(_skills.get_cooldown_remaining("freeze")).is_equal(3.0)


## Test: Cooldown expires and skill becomes usable again.
func test_skills_cooldown_expires_completely() -> void:
	_enter_battle()
	_skills.activate_skill("freeze")

	# Act: tick full cooldown
	_skills._process(5.0)

	# Assert
	assert_float(_skills.get_cooldown_remaining("freeze")).is_equal(0.0)
	assert_bool(_skills.can_activate("freeze")).is_true()


## Test: Cooldown does not tick during PREP phase.
func test_skills_cooldown_does_not_tick_in_prep() -> void:
	_enter_battle()
	_skills.activate_skill("freeze")
	assert_float(_skills.get_cooldown_remaining("freeze")).is_equal(5.0)

	# Switch to PREP
	_skills._current_phase = EmergencySkills.PHASE_PREP

	# Act: tick while in PREP
	_skills._process(10.0)

	# Assert: cooldown unchanged
	assert_float(_skills.get_cooldown_remaining("freeze")).is_equal(5.0)


## Test: Cooldown does not go below 0.0 (clamped).
func test_skills_cooldown_clamped_at_zero() -> void:
	_enter_battle()
	_skills.activate_skill("freeze")

	# Act: tick more than cooldown
	_skills._process(100.0)

	# Assert
	assert_float(_skills.get_cooldown_remaining("freeze")).is_equal(0.0)


# ==============================================================================
# Query Tests
# ==============================================================================


## Test: can_activate returns true when all conditions met.
func test_skills_can_activate_returns_true_when_ready() -> void:
	_enter_battle()
	assert_bool(_skills.can_activate("freeze")).is_true()
	assert_bool(_skills.can_activate("repair")).is_true()


## Test: can_activate returns false in PREP phase.
func test_skills_can_activate_false_in_prep() -> void:
	assert_bool(_skills.can_activate("freeze")).is_false()
	assert_bool(_skills.can_activate("repair")).is_false()


## Test: can_activate returns false for unknown skill.
func test_skills_can_activate_false_for_unknown() -> void:
	_enter_battle()
	assert_bool(_skills.can_activate("nonexistent")).is_false()


## Test: get_remaining_uses returns 0 for unknown skill.
func test_skills_get_remaining_uses_unknown_returns_zero() -> void:
	assert_int(_skills.get_remaining_uses("phantom")).is_equal(0)


## Test: get_max_uses returns 0 for unknown skill.
func test_skills_get_max_uses_unknown_returns_zero() -> void:
	assert_int(_skills.get_max_uses("phantom")).is_equal(0)


## Test: get_cooldown_remaining returns 0.0 for unknown skill.
func test_skills_get_cooldown_remaining_unknown_returns_zero() -> void:
	assert_float(_skills.get_cooldown_remaining("phantom")).is_equal(0.0)


## Test: get_skill_config returns null for unknown skill.
func test_skills_get_skill_config_unknown_returns_null() -> void:
	assert_object(_skills.get_skill_config("phantom")).is_null()


## Test: get_skill_config returns the correct config.
func test_skills_get_skill_config_returns_config() -> void:
	var config := _skills.get_skill_config("freeze")
	assert_object(config).is_not_null()
	assert_str(config.skill_id).is_equal("freeze")
	assert_str(config.skill_name).is_equal("冰冻")


# ==============================================================================
# Register Skill Tests
# ==============================================================================


## Test: register_skill adds a new skill at runtime.
func test_skills_register_adds_new_skill() -> void:
	var config := _make_skill_config("lightning", 1, 10.0)

	_skills.register_skill(config)

	assert_int(_skills.get_remaining_uses("lightning")).is_equal(1)
	assert_int(_skills.get_max_uses("lightning")).is_equal(1)

	config.free()


## Test: register_skill replaces an existing skill.
func test_skills_register_replaces_existing() -> void:
	var config := _make_skill_config("freeze", 99, 1.0)

	_skills.register_skill(config)

	assert_int(_skills.get_max_uses("freeze")).is_equal(99)
	assert_int(_skills.get_remaining_uses("freeze")).is_equal(99)

	config.free()


# ==============================================================================
# Per-Wave Replenishment Tests
# ==============================================================================


## Test: wave_started replenishes uses up to per_wave_replenish.
## GDD: 次数在准备阶段通过特定方式积累（如每波+1 次）.
func test_skills_wave_started_replenishes_uses() -> void:
	_enter_battle()
	# Use freeze twice (3 -> 1 remaining)
	_skills.activate_skill("freeze")
	_skills.activate_skill("freeze")
	assert_int(_skills.get_remaining_uses("freeze")).is_equal(1)

	# Act: simulate wave_started (replenish +1)
	_skills._on_wave_started(2)

	# Assert: 1 + 1 = 2
	assert_int(_skills.get_remaining_uses("freeze")).is_equal(2)


## Test: wave_started replenishment capped at max_uses.
func test_skills_replenish_capped_at_max_uses() -> void:
	_enter_battle()
	# Use freeze once (3 -> 2 remaining)
	_skills.activate_skill("freeze")
	assert_int(_skills.get_remaining_uses("freeze")).is_equal(2)

	# Act: replenish +1 (should go to 3, not 4)
	_skills._on_wave_started(2)

	# Assert: capped at max_uses = 3
	assert_int(_skills.get_remaining_uses("freeze")).is_equal(3)


## Test: wave_started does not replenish when per_wave_replenish is 0.
func test_skills_no_replenish_when_per_wave_is_zero() -> void:
	# Arrange: skill with per_wave_replenish = 0
	var config := _make_skill_config("noreplenish", 2, 3.0, 0)
	_skills.register_skill(config)
	_enter_battle()
	_skills.activate_skill("noreplenish")
	assert_int(_skills.get_remaining_uses("noreplenish")).is_equal(1)

	# Act
	_skills._on_wave_started(2)

	# Assert: no replenishment
	assert_int(_skills.get_remaining_uses("noreplenish")).is_equal(1)

	config.free()


# ==============================================================================
# Game Reset Tests (ADR-0008)
# ==============================================================================


## Test: game_reset restores all skills to max_uses and clears cooldowns.
func test_skills_game_reset_restores_all_uses() -> void:
	_enter_battle()
	# Consume all uses and put freeze on cooldown
	_skills.activate_skill("freeze")  # -> 2 remaining, cooldown 5s
	_skills.activate_skill("freeze")  # -> 1
	_skills.activate_skill("freeze")  # -> 0
	assert_int(_skills.get_remaining_uses("freeze")).is_equal(0)
	assert_bool(_skills._skills["freeze"].is_on_cooldown).is_true()

	# Act
	_skills._on_game_reset()

	# Assert: uses restored, cooldown cleared
	assert_int(_skills.get_remaining_uses("freeze")).is_equal(3)
	assert_int(_skills.get_remaining_uses("repair")).is_equal(2)
	assert_float(_skills.get_cooldown_remaining("freeze")).is_equal(0.0)
	assert_bool(_skills._skills["freeze"].is_on_cooldown).is_false()
	# Phase reset to PREP
	assert_int(_skills._current_phase).is_equal(EmergencySkills.PHASE_PREP)


# ==============================================================================
# Repair Callback Tests
# ==============================================================================


## Test: Default repair callback is a safe no-op.
func test_skills_default_repair_callback_is_noop() -> void:
	_enter_battle()

	# Act + Assert: should not crash with default (no-op) callback
	var result := _skills.activate_skill("repair")
	assert_bool(result).is_true()
	assert_int(_skills.get_remaining_uses("repair")).is_equal(1)


## Test: Repair callback can be replaced after init.
func test_skills_repair_callback_replaced_after_init() -> void:
	_enter_battle()
	var call_count := 0
	_skills.repair_callback = func(_amount: float): call_count += 1

	_skills.activate_skill("repair")
	_skills.activate_skill("repair")  # second use -- uses=2 so still available

	assert_int(call_count).is_equal(2)
	assert_int(_skills.get_remaining_uses("repair")).is_equal(0)
