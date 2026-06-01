class_name SceneManager
extends Node
## Manages scene transitions with signal notifications and error handling.
##
## Intended for use as an autoload named "SceneManager". Provides safe accessors
## for the current scene, scene switching via file path or PackedScene, and
## signal-based notifications for loading/loaded/failed lifecycle.
##
## @tutorial: https://docs.godotengine.org/en/stable/classes/class_scenetree.html
##
## Usage:
## [codeblock]
##   # Switch to a new scene by file path
##   SceneManager.change_scene("res://scenes/gameplay.tscn")
##
##   # Listen for completion
##   SceneManager.scene_loaded.connect(_on_level_ready)
##   SceneManager.scene_load_failed.connect(_on_load_error)
##
##   # Safely access the current scene (null-guarded)
##   var current := SceneManager.get_current_scene()
##   if current != null:
##       current.do_something()
## [/codeblock]


# ── Signals ────────────────────────────────────────────────────────────────────

## Emitted immediately before a scene change begins.
## [param scene_path] is the target scene file path (empty for packed/reload).
signal scene_loading(scene_path: String)

## Emitted after a scene has been successfully loaded and activated.
## [param scene_path] is the loaded scene file path (empty for packed/reload).
signal scene_loaded(scene_path: String)

## Emitted when a scene transition fails.
## [param scene_path] is the requested path (empty if not applicable).
## [param error_code] is the [enum Error] returned by the engine.
signal scene_load_failed(scene_path: String, error_code: int)


# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Bridge signals to SignalBus autoload if present.
	# This allows UI and other systems to observe scene transitions
	# without directly coupling to the SceneManager.
	if has_node("/root/SignalBus"):
		_bridge_to_signal_bus()


# ── Public API ─────────────────────────────────────────────────────────────────

## Returns the current active scene node.
## [b]Null-safe:[/b] guards against both a null [SceneTree] and a null [member SceneTree.current_scene].
## Returns [code]null[/code] if no scene is currently active or the SceneManager
## is not in the scene tree.
func get_current_scene() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.current_scene


## Returns the file path of the current scene.
## [b]Null-safe:[/b] returns an empty [String] if no scene is active.
## This is a convenience wrapper — equivalent to calling
## [code]get_current_scene().scene_file_path[/code] with the null check built in.
func get_current_scene_path() -> String:
	var scene := get_current_scene()
	if scene == null:
		return ""
	return scene.scene_file_path


## Switches to the scene at [param scene_path].
## Returns [enum Error] — [constant OK] on success, or an error code on failure.
##
## [b]Lifecycle:[/b]
##   1. Emits [signal scene_loading] with [param scene_path].
##   2. Calls [method SceneTree.change_scene_to_file].
##   3. On success: emits [signal scene_loaded].
##   4. On failure: emits [signal scene_load_failed] with the path and error code.
func change_scene(scene_path: String) -> int:
	var tree := get_tree()
	if tree == null:
		scene_load_failed.emit(scene_path, ERR_UNAVAILABLE)
		return ERR_UNAVAILABLE

	scene_loading.emit(scene_path)

	var result := tree.change_scene_to_file(scene_path)
	if result != OK:
		scene_load_failed.emit(scene_path, result)
		return result

	scene_loaded.emit(scene_path)
	return OK


## Switches to the given [param packed_scene].
## Useful for programmatic scene creation and in-memory testing.
##
## Returns [constant OK] on success, [constant ERR_INVALID_PARAMETER] if
## [param packed_scene] is [code]null[/code], or the error code from the engine.
func change_scene_packed(packed_scene: PackedScene) -> int:
	var tree := get_tree()
	if tree == null:
		scene_load_failed.emit("", ERR_UNAVAILABLE)
		return ERR_UNAVAILABLE

	if packed_scene == null:
		scene_load_failed.emit("", ERR_INVALID_PARAMETER)
		return ERR_INVALID_PARAMETER

	scene_loading.emit("")

	var result := tree.change_scene_to_packed(packed_scene)
	if result != OK:
		scene_load_failed.emit("", result)
		return result

	scene_loaded.emit("")
	return OK


## Reloads the current scene from its source file on disk.
## Returns [constant OK] on success, or an error code on failure
## (e.g., [constant ERR_UNCONFIGURED] if the current scene has no file path).
func reload_current_scene() -> int:
	var tree := get_tree()
	if tree == null:
		scene_load_failed.emit("", ERR_UNAVAILABLE)
		return ERR_UNAVAILABLE

	scene_loading.emit("")

	var result := tree.reload_current_scene()
	if result != OK:
		scene_load_failed.emit("", result)
		return result

	scene_loaded.emit("")
	return OK


# ── Private ────────────────────────────────────────────────────────────────────

## Connects this manager's signals to the SignalBus autoload for
## cross-system notification. Called once in [method _ready] if SignalBus exists.
func _bridge_to_signal_bus() -> void:
	var bus := get_node("/root/SignalBus")

	scene_loading.connect(
		func(path: String) -> void:
			bus.scene_loading.emit(path)
	)

	scene_loaded.connect(
		func(path: String) -> void:
			bus.scene_loaded.emit(path)
	)

	scene_load_failed.connect(
		func(path: String, code: int) -> void:
			bus.scene_load_failed.emit(path, code)
	)
