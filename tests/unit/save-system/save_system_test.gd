extends GdUnitTestSuite
## Unit tests for SaveSystem — save/load lifecycle, error handling, metadata
## queries, signal emissions, and convenience methods.
##
## Tests use a temporary save directory under user://test_saves/ to isolate
## test data from production saves. The directory is cleaned up in after().
##
## Test Cases:
##   1. save_game() — basic save returns OK
##   2. save_game() — empty slot_name fails
##   3. save_game() — data round-trips correctly
##   4. save_game() — overwrites existing save
##   5. load_game() — nonexistent save returns empty dict
##   6. load_game() — empty slot_name fails
##   7. has_save() — returns true after save, false for missing
##   8. delete_save() — removes file, has_save returns false after
##   9. delete_save() — nonexistent returns ERR_FILE_NOT_FOUND
##  10. delete_save() — empty slot_name fails
##  11. get_save_metadata() — returns metadata after save
##  12. get_save_metadata() — missing returns empty dict
##  13. get_all_save_slots() — returns saves sorted by timestamp descending
##  14. get_all_save_slots() — empty directory returns empty array
##  15. autosave() — saves to "auto" slot
##  16. quick_save() / quick_load() — convenience round-trip
##  17. load_autosave() — loads from "auto" slot
##  18. Signals — game_saved emitted on successful save
##  19. Signals — game_loaded emitted on successful load
##  20. Signals — save_deleted emitted on successful delete
##  21. Signals — save_failed emitted on error


# ── Test Constants ─────────────────────────────────────────────────────────────

const TEST_SAVE_DIR := "user://test_saves/"


# ── Test Fixture ───────────────────────────────────────────────────────────────

var _save_system: SaveSystem


func before() -> void:
	# Create SaveSystem with isolated test directory
	_save_system = SaveSystem.new()
	_save_system.save_directory = TEST_SAVE_DIR
	add_child(_save_system)

	# Ensure clean test directory
	_cleanup_test_dir()


func after() -> void:
	_cleanup_test_dir()
	_save_system.free()


func _cleanup_test_dir() -> void:
	var dir := DirAccess.open(TEST_SAVE_DIR)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

	# Remove the directory itself
	var parent := DirAccess.open("user://")
	if parent != null:
		# Only remove if empty — ignore errors if already gone
		parent.remove("test_saves")


# ── Test 1: save_game() basic ──────────────────────────────────────────────────

func test_save_system_save_game_returns_ok() -> void:
	# Arrange
	var data := { "gold": 500, "wave": 3 }

	# Act
	var result := _save_system.save_game("0", data)

	# Assert
	assert_int(result).is_equal(OK)


# ── Test 2: save_game() empty slot_name fails ──────────────────────────────────

func test_save_system_save_game_empty_slot_name_returns_invalid_parameter() -> void:
	# Arrange
	var data := { "gold": 100 }

	# Act
	var result := _save_system.save_game("", data)

	# Assert
	assert_int(result).is_equal(ERR_INVALID_PARAMETER)


# ── Test 3: save_game() data round-trips correctly ─────────────────────────────

func test_save_system_save_game_then_load_game_returns_same_data() -> void:
	# Arrange: data with multiple value types
	var original := {
		"gold": 500,
		"wave": 3,
		"player_name": "TestPlayer",
		"difficulty": 2.5,
		"unlocked": true,
	}
	_save_system.save_game("roundtrip_test", original)

	# Act
	var loaded := _save_system.load_game("roundtrip_test")

	# Assert: all keys present with correct values
	assert_int(loaded.size()).is_equal(original.size())
	assert_int(loaded["gold"]).is_equal(500)
	assert_int(loaded["wave"]).is_equal(3)
	assert_str(loaded["player_name"]).is_equal("TestPlayer")
	assert_float(loaded["difficulty"]).is_equal(2.5)
	assert_bool(loaded["unlocked"]).is_true()


# ── Test 4: save_game() overwrites existing save ────────────────────────────────

func test_save_system_save_game_overwrites_existing_save() -> void:
	# Arrange: save initial data
	_save_system.save_game("overwrite_test", { "gold": 100, "wave": 1 })

	# Act: overwrite with different data
	var new_data := { "gold": 999, "wave": 50, "extra_key": "new_value" }
	_save_system.save_game("overwrite_test", new_data)
	var loaded := _save_system.load_game("overwrite_test")

	# Assert: loaded data matches the new data, not the old
	assert_int(loaded["gold"]).is_equal(999)
	assert_int(loaded["wave"]).is_equal(50)
	assert_str(loaded["extra_key"]).is_equal("new_value")


# ── Test 5: load_game() nonexistent save returns empty dict ────────────────────

func test_save_system_load_game_nonexistent_returns_empty_dictionary() -> void:
	# Act
	var result := _save_system.load_game("nonexistent_slot")

	# Assert
	assert_bool(result.is_empty()).is_true()


# ── Test 6: load_game() empty slot_name fails ──────────────────────────────────

func test_save_system_load_game_empty_slot_name_returns_empty_dictionary() -> void:
	# Act
	var result := _save_system.load_game("")

	# Assert
	assert_bool(result.is_empty()).is_true()


# ── Test 7: has_save() returns true/false correctly ─────────────────────────────

func test_save_system_has_save_returns_true_after_save() -> void:
	# Arrange: save first
	_save_system.save_game("exists_test", { "key": "value" })

	# Act
	var result := _save_system.has_save("exists_test")

	# Assert
	assert_bool(result).is_true()


func test_save_system_has_save_returns_false_for_missing() -> void:
	# Act
	var result := _save_system.has_save("missing_slot")

	# Assert
	assert_bool(result).is_false()


func test_save_system_has_save_empty_slot_name_returns_false() -> void:
	# Act
	var result := _save_system.has_save("")

	# Assert
	assert_bool(result).is_false()


# ── Test 8: delete_save() removes file ─────────────────────────────────────────

func test_save_system_delete_save_returns_ok_and_removes_file() -> void:
	# Arrange
	_save_system.save_game("delete_me", { "temp": true })
	assert_bool(_save_system.has_save("delete_me")).is_true()

	# Act
	var result := _save_system.delete_save("delete_me")

	# Assert: operation succeeded and file no longer exists
	assert_int(result).is_equal(OK)
	assert_bool(_save_system.has_save("delete_me")).is_false()


# ── Test 9: delete_save() nonexistent returns ERR_FILE_NOT_FOUND ────────────────

func test_save_system_delete_save_nonexistent_returns_file_not_found() -> void:
	# Act
	var result := _save_system.delete_save("does_not_exist")

	# Assert
	assert_int(result).is_equal(ERR_FILE_NOT_FOUND)


# ── Test 10: delete_save() empty slot_name fails ───────────────────────────────

func test_save_system_delete_save_empty_slot_name_returns_invalid_parameter() -> void:
	# Act
	var result := _save_system.delete_save("")

	# Assert
	assert_int(result).is_equal(ERR_INVALID_PARAMETER)


# ── Test 11: get_save_metadata() returns metadata ──────────────────────────────

func test_save_system_get_save_metadata_returns_meta_keys() -> void:
	# Arrange
	_save_system.save_game("meta_test", { "gold": 200 })

	# Act
	var meta := _save_system.get_save_metadata("meta_test")

	# Assert: metadata contains expected keys
	assert_bool(meta.has("timestamp")).is_true()
	assert_bool(meta.has("version")).is_true()
	assert_bool(meta.has("slot_name")).is_true()
	assert_str(meta["slot_name"]).is_equal("meta_test")
	assert_str(meta["version"]).is_equal(_save_system.game_version)
	# timestamp must be a positive integer (recent)
	assert_bool(meta["timestamp"] is int).is_true()
	assert_bool(meta["timestamp"] > 0).is_true()


# ── Test 12: get_save_metadata() missing returns empty ──────────────────────────

func test_save_system_get_save_metadata_missing_returns_empty_dictionary() -> void:
	# Act
	var result := _save_system.get_save_metadata("no_such_slot")

	# Assert
	assert_bool(result.is_empty()).is_true()


func test_save_system_get_save_metadata_empty_slot_name_returns_empty() -> void:
	# Act
	var result := _save_system.get_save_metadata("")

	# Assert
	assert_bool(result.is_empty()).is_true()


# ── Test 13: get_all_save_slots() returns sorted list ──────────────────────────

func test_save_system_get_all_save_slots_returns_sorted_by_timestamp() -> void:
	# Arrange: save multiple slots
	_save_system.save_game("slot_a", { "n": 1 })
	# Brief pause so timestamps differ (unix seconds granularity)
	OS.delay_msec(1100)
	_save_system.save_game("slot_b", { "n": 2 })

	# Act
	var slots := _save_system.get_all_save_slots()

	# Assert: at least 2 slots, most recent first
	assert_bool(slots.size() >= 2).is_true()
	# slot_b has a later timestamp, so it should come first
	assert_str(slots[0]["slot_name"]).is_equal("slot_b")
	assert_str(slots[1]["slot_name"]).is_equal("slot_a")
	assert_bool(slots[0]["timestamp"] >= slots[1]["timestamp"]).is_true()


# ── Test 14: get_all_save_slots() empty directory returns empty array ───────────

func test_save_system_get_all_save_slots_empty_directory_returns_empty_array() -> void:
	# No saves created — test directory is clean after before()
	var slots := _save_system.get_all_save_slots()
	assert_int(slots.size()).is_equal(0)


# ── Test 15: autosave() convenience method ─────────────────────────────────────

func test_save_system_autosave_saves_to_auto_slot() -> void:
	# Act
	var result := _save_system.autosave({ "auto_data": true })

	# Assert
	assert_int(result).is_equal(OK)
	assert_bool(_save_system.has_save("auto")).is_true()

	var loaded := _save_system.load_game("auto")
	assert_bool(loaded["auto_data"]).is_true()


# ── Test 16: quick_save() / quick_load() round-trip ────────────────────────────

func test_save_system_quick_save_then_quick_load_roundtrips() -> void:
	# Arrange
	var data := { "quick_gold": 750, "quick_wave": 8 }

	# Act: quicksave
	var save_result := _save_system.quick_save(data)
	assert_int(save_result).is_equal(OK)

	# Act: quickload
	var loaded := _save_system.quick_load()

	# Assert
	assert_int(loaded["quick_gold"]).is_equal(750)
	assert_int(loaded["quick_wave"]).is_equal(8)


# ── Test 17: load_autosave() convenience method ────────────────────────────────

func test_save_system_load_autosave_loads_from_auto_slot() -> void:
	# Arrange
	_save_system.autosave({ "resume_gold": 1200 })

	# Act
	var loaded := _save_system.load_autosave()

	# Assert
	assert_int(loaded["resume_gold"]).is_equal(1200)


# ── Test 18: signal game_saved emitted on successful save ──────────────────────

func test_save_system_emits_game_saved_on_successful_save() -> void:
	# Arrange: connect listener
	var emitted_slot := ""
	_save_system.game_saved.connect(
		func(slot: String) -> void:
			emitted_slot = slot
	)

	# Act
	_save_system.save_game("signal_test", { "x": 1 })

	# Assert
	assert_str(emitted_slot).is_equal("signal_test")


# ── Test 19: signal game_loaded emitted on successful load ─────────────────────

func test_save_system_emits_game_loaded_on_successful_load() -> void:
	# Arrange
	_save_system.save_game("load_signal_test", { "y": 2 })
	var emitted_slot := ""
	_save_system.game_loaded.connect(
		func(slot: String) -> void:
			emitted_slot = slot
	)

	# Act
	_save_system.load_game("load_signal_test")

	# Assert
	assert_str(emitted_slot).is_equal("load_signal_test")


# ── Test 20: signal save_deleted emitted on successful delete ──────────────────

func test_save_system_emits_save_deleted_on_successful_delete() -> void:
	# Arrange
	_save_system.save_game("delete_signal_test", { "z": 3 })
	var emitted_slot := ""
	_save_system.save_deleted.connect(
		func(slot: String) -> void:
			emitted_slot = slot
	)

	# Act
	_save_system.delete_save("delete_signal_test")

	# Assert
	assert_str(emitted_slot).is_equal("delete_signal_test")


# ── Test 21: signal save_failed emitted on error ───────────────────────────────

func test_save_system_emits_save_failed_on_empty_slot_name() -> void:
	# Arrange
	var emitted_slot := ""
	var emitted_code := -1
	_save_system.save_failed.connect(
		func(slot: String, code: int) -> void:
			emitted_slot = slot
			emitted_code = code
	)

	# Act
	_save_system.save_game("", { "bad": true })

	# Assert
	assert_str(emitted_slot).is_equal("")
	assert_int(emitted_code).is_equal(ERR_INVALID_PARAMETER)


func test_save_system_emits_save_failed_on_load_nonexistent() -> void:
	# Arrange
	var emitted_code := -1
	_save_system.save_failed.connect(
		func(_slot: String, code: int) -> void:
			emitted_code = code
	)

	# Act
	_save_system.load_game("nonexistent_slot")

	# Assert
	assert_int(emitted_code).is_equal(ERR_FILE_NOT_FOUND)


func test_save_system_emits_save_failed_on_delete_nonexistent() -> void:
	# Arrange
	var emitted_code := -1
	_save_system.save_failed.connect(
		func(_slot: String, code: int) -> void:
			emitted_code = code
	)

	# Act
	_save_system.delete_save("nonexistent_slot")

	# Assert
	assert_int(emitted_code).is_equal(ERR_FILE_NOT_FOUND)


# ── Test: SignalBus bridging verification ──────────────────────────────────────

func test_save_system_signals_bridge_to_signal_bus_when_present() -> void:
	# Arrange: register a SignalBus with save signals at /root/SignalBus
	var signal_bus := _SignalBusMock.new()
	signal_bus.name = "SignalBus"
	get_tree().root.add_child(signal_bus)

	# Create a fresh SaveSystem so _ready() fires and bridges
	var ss := SaveSystem.new()
	ss.save_directory = TEST_SAVE_DIR
	add_child(ss)

	var bus_received_save := ""
	signal_bus.game_saved.connect(
		func(slot: String) -> void:
			bus_received_save = slot
	)

	# Act
	ss.save_game("bridge_test", { "bridged": true })

	# Assert: signal propagated to the bus
	assert_str(bus_received_save).is_equal("bridge_test")

	# Cleanup
	ss.free()
	signal_bus.free()


# ── Inner Class: SignalBus Mock ────────────────────────────────────────────────

class _SignalBusMock extends Node:
	## Lightweight SignalBus mock with save-related signals for bridging test.
	signal game_saved(slot_name: String)
	signal game_loaded(slot_name: String)
	signal save_failed(slot_name: String, error_code: int)
	signal save_deleted(slot_name: String)
