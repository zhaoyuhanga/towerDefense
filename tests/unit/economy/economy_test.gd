extends GdUnitTestSuite
## Unit tests for EconomySystem.
## Implements acceptance criteria from design/gdd/economy.md.
## Covers: init with config, spend_gold (success/failure/edge), can_afford,
## add_gold, kill_reward_multiplier application, game reset to config starting gold.


# ── Test Fixtures ────────────────────────────────────────────────────────────────

var _economy: EconomySystem
var _config: EconomyConfig
var _gold_changed_signals: Array = []  # tracks (current_gold) emitted via SignalBus


func before() -> void:
	_config = EconomyConfig.new()
	_config.starting_gold = 200
	_config.BLOCK_COST = 10
	_config.BLOCK_SELL_VALUE = 5
	_config.MERGE_COST = 0
	_config.kill_reward_multiplier = 1.0

	_economy = EconomySystem.new()
	_gold_changed_signals.clear()

	# Subscribe to gold_changed for signal verification
	if has_node("/root/SignalBus"):
		if not SignalBus.gold_changed.is_connected(_track_gold_changed):
			SignalBus.gold_changed.connect(_track_gold_changed)


func after() -> void:
	# Disconnect SignalBus listener
	if has_node("/root/SignalBus"):
		if SignalBus.gold_changed.is_connected(_track_gold_changed):
			SignalBus.gold_changed.disconnect(_track_gold_changed)

	# Disconnect economy system from SignalBus
	if has_node("/root/SignalBus"):
		if SignalBus.monster_died.is_connected(_economy._on_monster_died):
			SignalBus.monster_died.disconnect(_economy._on_monster_died)
		if SignalBus.game_reset_requested.is_connected(_economy._on_game_reset):
			SignalBus.game_reset_requested.disconnect(_economy._on_game_reset)

	if is_instance_valid(_economy):
		_economy.free()
	if is_instance_valid(_config):
		_config.free()

	_gold_changed_signals.clear()


# ── Helpers ──────────────────────────────────────────────────────────────────────


func _track_gold_changed(current: int) -> void:
	_gold_changed_signals.append(current)


## Initialize economy with the fixture config and verify preconditions.
func _init_economy() -> void:
	_economy.init(_config)


## Assert gold_changed was emitted with the given value as the most recent emission.
func _assert_gold_changed_emitted(expected: int) -> void:
	if has_node("/root/SignalBus"):
		assert_bool(_gold_changed_signals.size() > 0,
			"gold_changed should have been emitted at least once").is_true()
		assert_int(_gold_changed_signals.back()).is_equal(expected)
	else:
		# SignalBus unavailable — fall back to state check
		assert_int(_economy.current_gold).is_equal(expected)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 1: Init sets starting gold from config
# GDD AC: GIVEN 新游戏开始，WHEN 初始化完成，
#         THEN current_gold = EconomyConfig.starting_gold
# ═══════════════════════════════════════════════════════════════════════════════════

func test_economy_init_sets_starting_gold_from_config() -> void:
	# Arrange: config.starting_gold = 200 (set in before)

	# Act
	_init_economy()

	# Assert
	assert_int(_economy.current_gold).is_equal(200)
	assert_float(_economy.kill_reward_multiplier).is_equal(1.0)
	_assert_gold_changed_emitted(200)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 2: spend_gold succeeds with sufficient funds
# GDD AC: GIVEN current_gold=200，WHEN spend_gold(50)，
#         THEN 返回 true，current_gold=150
# ═══════════════════════════════════════════════════════════════════════════════════

func test_economy_spend_gold_succeeds_with_sufficient_funds() -> void:
	# Arrange
	_init_economy()
	assert_int(_economy.current_gold).is_equal(200)

	# Act
	var ok := _economy.spend_gold(50)

	# Assert
	assert_bool(ok, "spend_gold(50) should succeed with 200 gold").is_true()
	assert_int(_economy.current_gold).is_equal(150)
	_assert_gold_changed_emitted(150)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 3: spend_gold fails with insufficient funds
# GDD AC: GIVEN current_gold=30，WHEN spend_gold(50)，
#         THEN 返回 false，current_gold 不变
# ═══════════════════════════════════════════════════════════════════════════════════

func test_economy_spend_gold_fails_with_insufficient_funds() -> void:
	# Arrange: set gold to 30
	_init_economy()
	_economy.current_gold = 30
	var gold_before := _economy.current_gold

	# Act
	var ok := _economy.spend_gold(50)

	# Assert
	assert_bool(ok, "spend_gold(50) should fail with 30 gold").is_false()
	assert_int(_economy.current_gold).is_equal(gold_before)
	# gold_changed should NOT have been emitted after the initial one
	if has_node("/root/SignalBus"):
		assert_int(_gold_changed_signals.size()).is_equal(1)  # only init emission
		# Note: _gold_changed_signals.back() is 200 from init, not 30 —
		# direct assignment of current_gold = 30 bypasses the signal.


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 4: spend_gold fails for zero or negative amount
# GDD edge case: amount <= 0 — no free purchases, returns false
# ═══════════════════════════════════════════════════════════════════════════════════

func test_economy_spend_gold_fails_for_zero_or_negative() -> void:
	# Arrange
	_init_economy()
	var gold_before := _economy.current_gold

	# Act + Assert: spend(0)
	var ok_zero := _economy.spend_gold(0)
	assert_bool(ok_zero, "spend_gold(0) should fail").is_false()
	assert_int(_economy.current_gold).is_equal(gold_before)

	# Act + Assert: spend(-10)
	var ok_neg := _economy.spend_gold(-10)
	assert_bool(ok_neg, "spend_gold(-10) should fail").is_false()
	assert_int(_economy.current_gold).is_equal(gold_before)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 5: can_afford returns true when sufficient
# GDD query: can_afford(amount) — pre-purchase check
# ═══════════════════════════════════════════════════════════════════════════════════

func test_economy_can_afford_returns_true_when_sufficient() -> void:
	# Arrange
	_init_economy()

	# Act + Assert
	assert_bool(_economy.can_afford(50)).is_true()
	assert_bool(_economy.can_afford(200)).is_true()   # exact match
	assert_bool(_economy.can_afford(1)).is_true()      # minimum purchase


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 6: can_afford returns false when insufficient or invalid amount
# GDD edge case: 金币为0时尝试购买 → can_afford() → false
# ═══════════════════════════════════════════════════════════════════════════════════

func test_economy_can_afford_returns_false_when_insufficient() -> void:
	# Arrange
	_init_economy()

	# Act + Assert: over budget
	assert_bool(_economy.can_afford(201)).is_false()

	# Zero or negative amounts are never affordable
	assert_bool(_economy.can_afford(0)).is_false()
	assert_bool(_economy.can_afford(-10)).is_false()

	# Edge: gold at 0
	_economy.current_gold = 0
	assert_bool(_economy.can_afford(1)).is_false()


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 7: add_gold increases balance
# GDD: 收入来源 — 出售塔/方块时调用 add_gold()
# ═══════════════════════════════════════════════════════════════════════════════════

func test_economy_add_gold_increases_balance() -> void:
	# Arrange
	_init_economy()
	assert_int(_economy.current_gold).is_equal(200)

	# Act
	_economy.add_gold(50)

	# Assert
	assert_int(_economy.current_gold).is_equal(250)
	_assert_gold_changed_emitted(250)

	# Edge: add_gold(0) no-ops
	var gold_before := _economy.current_gold
	_economy.add_gold(0)
	assert_int(_economy.current_gold).is_equal(gold_before)

	# Edge: add_gold(-10) no-ops
	_economy.add_gold(-10)
	assert_int(_economy.current_gold).is_equal(gold_before)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 8: monster_died handler applies kill_reward_multiplier
# GDD AC: GIVEN 怪物被击杀，WHEN monster_died(reward_gold=10) 信号发射，
#         THEN current_gold 增加 10 (with multiplier=1.0)
# Also tests non-default multiplier values.
# ═══════════════════════════════════════════════════════════════════════════════════

func test_economy_monster_died_applies_kill_reward_multiplier() -> void:
	# Arrange: multiplier = 1.0
	_init_economy()
	assert_int(_economy.current_gold).is_equal(200)

	# Act: simulate monster_died with reward_gold=10
	_economy._on_monster_died("goblin_001", Vector2.ZERO, 10)

	# Assert: 200 + round(10 * 1.0) = 210
	assert_int(_economy.current_gold).is_equal(210)

	# Arrange: change multiplier to 1.5
	_economy.kill_reward_multiplier = 1.5

	# Act: reward_gold=10, multiplier=1.5 => 15
	_economy._on_monster_died("goblin_002", Vector2.ZERO, 10)

	# Assert: 210 + 15 = 225
	assert_int(_economy.current_gold).is_equal(225)

	# Arrange: change multiplier to 0.5
	_economy.kill_reward_multiplier = 0.5

	# Act: reward_gold=10, multiplier=0.5 => 5
	_economy._on_monster_died("goblin_003", Vector2.ZERO, 10)

	# Assert: 225 + 5 = 230
	assert_int(_economy.current_gold).is_equal(230)


# ═══════════════════════════════════════════════════════════════════════════════════
# Test 9: game_reset resets gold to config.starting_gold
# ADR-0008: On game_reset_requested, economy resets to config values.
# Verifies both current_gold and kill_reward_multiplier are restored.
# ═══════════════════════════════════════════════════════════════════════════════════

func test_economy_game_reset_resets_to_config_starting_gold() -> void:
	# Arrange: init, then modify state
	_init_economy()
	assert_int(_economy.current_gold).is_equal(200)
	assert_float(_economy.kill_reward_multiplier).is_equal(1.0)

	# Spend and earn to drift from starting state
	_economy.spend_gold(100)     # gold: 200 -> 100
	_economy.kill_reward_multiplier = 2.0
	_economy._on_monster_died("test", Vector2.ZERO, 50)  # gold: 100 + 100 = 200

	# Verify we drifted
	assert_int(_economy.current_gold).is_equal(200)
	assert_float(_economy.kill_reward_multiplier).is_equal(2.0)

	# Act: trigger game reset
	_economy._on_game_reset()

	# Assert: gold back to config.starting_gold (200), multiplier restored to 1.0
	assert_int(_economy.current_gold).is_equal(200)
	assert_float(_economy.kill_reward_multiplier).is_equal(1.0)
	_assert_gold_changed_emitted(200)
