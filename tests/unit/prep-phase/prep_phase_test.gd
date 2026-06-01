extends GdUnitTestSuite
## Unit tests for PhaseManager (prep_phase.gd).
## Implements acceptance criteria from design/gdd/prep-phase.md.
## Covers: initial state, PREP->BATTLE->PREP cycle, duplicate rejection,
## pause/resume (V1.0), wave preview, game reset, re-entrant guard.


# ==============================================================================
# Test Fixtures
# ==============================================================================

var _pm: PhaseManager
var _signal_log: Array = []  # [{old_phase: int, new_phase: int}]


func before() -> void:
	_pm = PhaseManager.new()
	_pm.init()
	_signal_log.clear()

	# Connect to SignalBus if available to record phase_changed emissions
	if has_node("/root/SignalBus"):
		if not SignalBus.phase_changed.is_connected(_record_phase_changed):
			SignalBus.phase_changed.connect(_record_phase_changed)


func after() -> void:
	if has_node("/root/SignalBus"):
		if SignalBus.phase_changed.is_connected(_record_phase_changed):
			SignalBus.phase_changed.disconnect(_record_phase_changed)
	_signal_log.clear()
	if is_instance_valid(_pm):
		_pm.free()
	_pm = null


# ==============================================================================
# Helpers
# ==============================================================================

func _record_phase_changed(old_phase: int, new_phase: int) -> void:
	_signal_log.append({"old_phase": old_phase, "new_phase": new_phase})


## Assert that the last phase_changed signal carried the expected values.
func _assert_last_signal(expected_old: int, expected_new: int) -> void:
	assert_bool(_signal_log.size() > 0, "Expected phase_changed signal but none emitted").is_true()
	if _signal_log.size() > 0:
		var last: Dictionary = _signal_log[_signal_log.size() - 1]
		assert_int(last["old_phase"]).is_equal(expected_old)
		assert_int(last["new_phase"]).is_equal(expected_new)


# ==============================================================================
# Initial State Tests
# ==============================================================================


## Test: PhaseManager initializes in PREP phase.
## GDD AC: GIVEN game start, WHEN initialization complete, THEN phase is PREP.
func test_phase_initial_state_is_prep() -> void:
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.PREP as int)


## Test: PhaseManager does NOT emit phase_changed on init (implicit contract).
## ADR-0006: systems default to PREP; no initial signal to avoid race with
## subscription order in _ready().
func test_phase_init_does_not_emit_signal() -> void:
	# _signal_log was cleared in before() and init() does not emit
	assert_int(_signal_log.size()).is_equal(0)


# ==============================================================================
# PREP -> BATTLE Transition Tests
# ==============================================================================


## Test: start_wave() transitions PREP -> BATTLE and emits phase_changed.
## GDD AC: GIVEN PREP phase, WHEN click "Start", THEN switch to BATTLE,
##         phase_changed signal emitted.
func test_phase_start_wave_prep_to_battle() -> void:
	# Act
	_pm.start_wave()

	# Assert
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.BATTLE as int)
	_assert_last_signal(PhaseManager.Phase.PREP as int, PhaseManager.Phase.BATTLE as int)


## Test: start_wave() from BATTLE is rejected (no-op + warning).
## GDD edge case: 非法转换 BATTLE -> BATTLE 被拒绝.
func test_phase_start_wave_from_battle_is_rejected() -> void:
	# Arrange: transition to BATTLE first
	_pm.start_wave()
	_signal_log.clear()

	# Act: try to start wave again
	_pm.start_wave()

	# Assert: state unchanged, no signal emitted
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.BATTLE as int)
	assert_int(_signal_log.size()).is_equal(0)


## Test: start_wave() from PAUSED is rejected.
func test_phase_start_wave_from_paused_is_rejected() -> void:
	# Arrange: enter PAUSED
	_pm.pause()
	_signal_log.clear()

	# Act
	_pm.start_wave()

	# Assert: still PAUSED
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.PAUSED as int)
	assert_int(_signal_log.size()).is_equal(0)
	# Restore for cleanup
	_pm.resume()


# ==============================================================================
# BATTLE -> PREP Transition Tests
# ==============================================================================


## Test: on_wave_ended() transitions BATTLE -> PREP and emits phase_changed.
## GDD AC: GIVEN BATTLE phase, WHEN wave ends, THEN auto-switch to PREP.
func test_phase_on_wave_ended_battle_to_prep() -> void:
	# Arrange: go to BATTLE first
	_pm.start_wave()
	_signal_log.clear()

	# Act
	_pm.on_wave_ended()

	# Assert
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.PREP as int)
	_assert_last_signal(PhaseManager.Phase.BATTLE as int, PhaseManager.Phase.PREP as int)


## Test: on_wave_ended() from PREP is rejected (no-op + warning).
func test_phase_on_wave_ended_from_prep_is_rejected() -> void:
	# Act: try to end wave while already in PREP
	_pm.on_wave_ended()

	# Assert: state unchanged, no signal emitted
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.PREP as int)
	assert_int(_signal_log.size()).is_equal(0)


## Test: on_wave_ended() from PAUSED is rejected.
func test_phase_on_wave_ended_from_paused_is_rejected() -> void:
	# Arrange: enter PAUSED
	_pm.pause()
	_signal_log.clear()

	# Act
	_pm.on_wave_ended()

	# Assert: still PAUSED
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.PAUSED as int)
	assert_int(_signal_log.size()).is_equal(0)
	# Restore for cleanup
	_pm.resume()


# ==============================================================================
# Duplicate Transition Rejection Tests
# ==============================================================================


## Test: Duplicate PREP -> PREP transition is rejected.
## ADR-0006 Validation Criterion 2: illegal transitions rejected with warnings.
func test_phase_duplicate_prep_rejected() -> void:
	# Act: _set_phase(PREP) when already PREP
	_pm._set_phase(PhaseManager.Phase.PREP)

	# Assert
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.PREP as int)
	assert_int(_signal_log.size()).is_equal(0)


## Test: Duplicate BATTLE -> BATTLE transition is rejected.
func test_phase_duplicate_battle_rejected() -> void:
	# Arrange
	_pm.start_wave()
	_signal_log.clear()

	# Act: _set_phase(BATTLE) when already BATTLE
	_pm._set_phase(PhaseManager.Phase.BATTLE)

	# Assert
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.BATTLE as int)
	assert_int(_signal_log.size()).is_equal(0)


# ==============================================================================
# Full Cycle Test
# ==============================================================================


## Test: Full PREP -> BATTLE -> PREP cycle emits exactly 2 signals.
## ADR-0006 Validation Criterion 1: complete cycle produces correct signals.
func test_phase_full_cycle_emits_correct_signals() -> void:
	# Act: complete one wave cycle
	_pm.start_wave()
	_pm.on_wave_ended()

	# Assert: 2 signals emitted with correct parameters
	assert_int(_signal_log.size()).is_equal(2)
	assert_int(_signal_log[0]["old_phase"]).is_equal(PhaseManager.Phase.PREP as int)
	assert_int(_signal_log[0]["new_phase"]).is_equal(PhaseManager.Phase.BATTLE as int)
	assert_int(_signal_log[1]["old_phase"]).is_equal(PhaseManager.Phase.BATTLE as int)
	assert_int(_signal_log[1]["new_phase"]).is_equal(PhaseManager.Phase.PREP as int)


## Test: 100 PREP <-> BATTLE cycles produce correct state.
## ADR-0006 Validation Criterion 5: no state drift over repeated cycles.
func test_phase_hundred_cycles_no_state_drift() -> void:
	for i in range(100):
		_pm.start_wave()
		assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.BATTLE as int)
		_pm.on_wave_ended()
		assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.PREP as int)

	# After 100 cycles, should be back in PREP
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.PREP as int)
	# 2 signals per cycle = 200 signals
	assert_int(_signal_log.size()).is_equal(200)


# ==============================================================================
# Pause / Resume Tests (V1.0)
# ==============================================================================


## Test: pause() from PREP transitions to PAUSED and remembers PREP.
func test_phase_pause_from_prep_then_resume() -> void:
	# Act
	_pm.pause()

	# Assert: now PAUSED
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.PAUSED as int)

	# Act: resume
	_pm.resume()

	# Assert: back to PREP
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.PREP as int)


## Test: pause() from BATTLE transitions to PAUSED and remembers BATTLE.
func test_phase_pause_from_battle_then_resume() -> void:
	# Arrange
	_pm.start_wave()

	# Act
	_pm.pause()
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.PAUSED as int)

	# Act: resume
	_pm.resume()

	# Assert: back to BATTLE
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.BATTLE as int)


## Test: pause() from PAUSED is no-op.
func test_phase_pause_when_already_paused_is_noop() -> void:
	_pm.pause()
	_signal_log.clear()

	# Act: try to pause again
	_pm.pause()

	# Assert: still PAUSED, no signal emitted
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.PAUSED as int)
	assert_int(_signal_log.size()).is_equal(0)
	# Restore
	_pm.resume()


## Test: resume() from non-PAUSED phase is no-op.
func test_phase_resume_when_not_paused_is_noop() -> void:
	# Act: resume while in PREP
	_pm.resume()

	# Assert: still PREP, no signal
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.PREP as int)
	assert_int(_signal_log.size()).is_equal(0)


# ==============================================================================
# Wave Preview Tests
# ==============================================================================


## Test: set_next_wave_preview stores preview data.
## GDD: 准备阶段显示下一波怪物信息 -- 类型、数量、是否有词缀/Boss.
func test_phase_set_wave_preview_stores_data() -> void:
	# Arrange
	var preview := {
		"wave_number": 5,
		"monster_types": ["goblin_standard", "orc_boss"],
		"monster_count": 12,
		"has_boss": true,
		"has_affix": false,
	}

	# Act
	_pm.set_next_wave_preview(preview)

	# Assert
	assert_int(_pm.next_wave_preview["wave_number"]).is_equal(5)
	assert_int(_pm.next_wave_preview["monster_count"]).is_equal(12)
	assert_bool(_pm.next_wave_preview["has_boss"]).is_true()
	assert_bool(_pm.next_wave_preview["has_affix"]).is_false()
	assert_int((_pm.next_wave_preview["monster_types"] as Array).size()).is_equal(2)


## Test: Wave preview is auto-cleared when entering BATTLE.
func test_phase_wave_preview_cleared_on_battle() -> void:
	# Arrange
	_pm.set_next_wave_preview({"wave_number": 1, "monster_count": 5})
	assert_bool(_pm.next_wave_preview.is_empty()).is_false()

	# Act
	_pm.start_wave()

	# Assert: preview cleared
	assert_bool(_pm.next_wave_preview.is_empty()).is_true()


## Test: clear_wave_preview manually clears the preview.
func test_phase_clear_wave_preview_manually() -> void:
	# Arrange
	_pm.set_next_wave_preview({"wave_number": 3, "monster_count": 8})

	# Act
	_pm.clear_wave_preview()

	# Assert
	assert_bool(_pm.next_wave_preview.is_empty()).is_true()


# ==============================================================================
# Game Reset Tests (ADR-0008)
# ==============================================================================


## Test: _on_game_reset restores PREP phase and emits signal.
## GDD edge case: 玩家重置 --> 回到 PREP 阶段.
func test_phase_game_reset_returns_to_prep() -> void:
	# Arrange: go to BATTLE
	_pm.start_wave()
	_signal_log.clear()

	# Act
	_pm._on_game_reset()

	# Assert
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.PREP as int)
	_assert_last_signal(PhaseManager.Phase.BATTLE as int, PhaseManager.Phase.PREP as int)
	assert_bool(_pm.next_wave_preview.is_empty()).is_true()


## Test: _on_game_reset from PAUSED unpauses and returns to PREP.
func test_phase_game_reset_from_paused_unpauses() -> void:
	# Arrange
	_pm.pause()
	_signal_log.clear()

	# Act
	_pm._on_game_reset()

	# Assert
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.PREP as int)
	_assert_last_signal(PhaseManager.Phase.PAUSED as int, PhaseManager.Phase.PREP as int)


# ==============================================================================
# Re-entrant Guard Test
# ==============================================================================


## Test: Re-entrant transition via signal cascade is blocked.
## Simulates a subscriber calling start_wave() from within phase_changed handler.
func test_phase_reentrant_transition_blocked() -> void:
	# Arrange: set up a handler that tries to trigger another transition
	var reentrant_attempted := false

	var handler := func(_old: int, _new: int) -> void:
		reentrant_attempted = true
		_pm.start_wave()  # Should be blocked by _is_transitioning guard

	if has_node("/root/SignalBus"):
		SignalBus.phase_changed.connect(handler)

	# Act
	_pm.start_wave()

	# Assert: start_wave inside handler was blocked; still in BATTLE
	assert_bool(reentrant_attempted).is_true()
	assert_int(_pm.current_phase as int).is_equal(PhaseManager.Phase.BATTLE as int)

	# Cleanup
	if has_node("/root/SignalBus"):
		if SignalBus.phase_changed.is_connected(handler):
			SignalBus.phase_changed.disconnect(handler)
