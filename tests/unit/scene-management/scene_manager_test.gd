extends GdUnitTestSuite
## Unit tests for SceneManager — scene transition lifecycle, null guards,
## signal ordering, and SignalBus bridging (Option A: SignalBus added
## to scene root in before()).
##
## Test Cases:
##   1. get_current_scene() — null guard when not in tree
##   2. get_current_scene_path() — empty string when not in tree
##   3. change_scene() — ERR_UNAVAILABLE when no tree
##   4. change_scene() — invalid path emits failure signal
##   5. change_scene_packed() — null PackedScene returns ERR_INVALID_PARAMETER
##   6. change_scene() — signals emit in correct order (loading → failed, no loaded)
##   7. SignalBus bridging — signals propagate to /root/SignalBus


# ── Inner Class: SignalBus (Option A) ──────────────────────────────────────────

class SignalBus extends Node:
	## Lightweight signal bus for cross-system scene transition notifications.
	## Added to /root/SignalBus in before() so SceneManager._ready() can bridge.
	signal scene_loading(scene_path: String)
	signal scene_loaded(scene_path: String)
	signal scene_load_failed(scene_path: String, error_code: int)


# ── Test Fixture ───────────────────────────────────────────────────────────────

var _scene_manager: SceneManager
var _signal_bus: SignalBus


func before() -> void:
	# Option A: Register SignalBus at scene root before SceneManager._ready() fires.
	# This ensures the bridge connection in SceneManager._ready() succeeds.
	_signal_bus = SignalBus.new()
	_signal_bus.name = "SignalBus"
	get_tree().root.add_child(_signal_bus)

	# Create SceneManager and add to tree — _ready() fires immediately,
	# establishing the SignalBus bridge.
	_scene_manager = SceneManager.new()
	add_child(_scene_manager)


func after() -> void:
	_scene_manager.free()
	_signal_bus.free()


# ── Test 1: get_current_scene() null guard (not in tree) ───────────────────────

func test_scene_manager_get_current_scene_returns_null_when_not_in_tree() -> void:
	# Arrange: SceneManager created but NOT added to scene tree.
	# get_tree() is null in this state, so the null guard must return null.
	var sm := SceneManager.new()

	# Act
	var result := sm.get_current_scene()

	# Assert: null guard prevents crash, returns null
	assert_object(result).is_null()

	# Cleanup
	sm.free()


# ── Test 2: get_current_scene_path() null guard (not in tree) ──────────────────

func test_scene_manager_get_current_scene_path_returns_empty_when_not_in_tree() -> void:
	# Arrange: SceneManager without a tree has no current scene.
	var sm := SceneManager.new()

	# Act
	var result := sm.get_current_scene_path()

	# Assert: returns empty string instead of crashing
	assert_str(result).is_equal("")

	# Cleanup
	sm.free()


# ── Test 3: change_scene() returns ERR_UNAVAILABLE when not in tree ────────────

func test_scene_manager_change_scene_no_tree_returns_unavailable() -> void:
	# Arrange
	var sm := SceneManager.new()

	# Act
	var result := sm.change_scene("res://scenes/any_scene.tscn")

	# Assert
	assert_int(result).is_equal(ERR_UNAVAILABLE)

	# Cleanup
	sm.free()


# ── Test 4: change_scene() invalid path emits failure signal ───────────────────

func test_scene_manager_change_scene_invalid_path_emits_failure_signal() -> void:
	# Arrange: connect listener to scene_load_failed on the in-tree SceneManager
	var received_path := ""
	var received_code := -1
	_scene_manager.scene_load_failed.connect(
		func(path: String, code: int) -> void:
			received_path = path
			received_code = code
	)

	# Act: attempt to load a file that does not exist
	var result := _scene_manager.change_scene("res://nonexistent_scene.tscn")

	# Assert: error returned, and failure signal emitted with correct data
	assert_int(result).is_not_equal(OK)
	assert_str(received_path).is_equal("res://nonexistent_scene.tscn")
	assert_int(received_code).is_not_equal(OK)


# ── Test 5: change_scene_packed() null parameter ───────────────────────────────

func test_scene_manager_change_scene_packed_null_returns_invalid_parameter() -> void:
	# Arrange: connect listener to scene_load_failed
	var received_path := "not empty"
	var received_code := -1
	_scene_manager.scene_load_failed.connect(
		func(path: String, code: int) -> void:
			received_path = path
			received_code = code
	)

	# Act: pass null PackedScene
	var result := _scene_manager.change_scene_packed(null)

	# Assert: ERR_INVALID_PARAMETER returned and emitted
	assert_int(result).is_equal(ERR_INVALID_PARAMETER)
	assert_str(received_path).is_equal("")
	assert_int(received_code).is_equal(ERR_INVALID_PARAMETER)


# ── Test 6: signals emit in correct order (loading → failed, never loaded) ─────

func test_scene_manager_change_scene_emits_loading_then_failed_in_order() -> void:
	# Arrange: record signal emission sequence
	var signal_log: Array[String] = []
	_scene_manager.scene_loading.connect(
		func(_path: String) -> void:
			signal_log.append("loading")
	)
	_scene_manager.scene_load_failed.connect(
		func(_path: String, _code: int) -> void:
			signal_log.append("failed")
	)
	_scene_manager.scene_loaded.connect(
		func(_path: String) -> void:
			signal_log.append("loaded")
	)

	# Act: trigger a failed scene change
	_scene_manager.change_scene("res://nonexistent_scene.tscn")

	# Assert: exactly two signals — loading first, then failed. "loaded" never fires.
	assert_int(signal_log.size()).is_equal(2)
	assert_str(signal_log[0]).is_equal("loading")
	assert_str(signal_log[1]).is_equal("failed")


# ── Test 7: SignalBus bridging (Option A verification) ─────────────────────────

func test_scene_manager_signal_bus_bridges_signals_on_scene_load_failed() -> void:
	# Arrange: SignalBus was registered at /root/SignalBus in before().
	# SceneManager._ready() has already bridged its signals to SignalBus.
	# Connect a test listener directly to SignalBus to verify bridging.
	var bus_received: Array = []
	_signal_bus.scene_load_failed.connect(
		func(path: String, code: int) -> void:
			bus_received.append([path, code])
	)

	# Act: trigger scene_load_failed through the SceneManager
	_scene_manager.change_scene("res://nonexistent_scene.tscn")

	# Assert: SignalBus received exactly one forwarded event
	assert_int(bus_received.size()).is_equal(1)
	assert_str(bus_received[0][0]).is_equal("res://nonexistent_scene.tscn")
	assert_int(bus_received[0][1]).is_not_equal(OK)
