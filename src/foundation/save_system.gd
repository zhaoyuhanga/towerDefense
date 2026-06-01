class_name SaveSystem
extends Node
## Save System — manages save file I/O for game state persistence.
##
## Foundation layer. Provides a generic save/load interface backed by
## Godot [ConfigFile]. Each save slot is a separate [code].sav[/code] file
## in [member save_directory]. Game state is passed as a [Dictionary] of
## key-value pairs — the SaveSystem is data-agnostic; it serializes whatever
## the caller provides.
##
## Save file format (ConfigFile sections):
##   [codeblock]
##   [meta]
##   timestamp=1717200000
##   version="1.0.0"
##   slot_name="Slot 0"
##
##   [data]
##   gold=500
##   wave=3
##   grid=PackedInt32Array(...)
##   [/codeblock]
##
## Usage:
## [codeblock]
##   # Save
##   var data := { "gold": 500, "wave": 3, "grid": packed_grid }
##   var err := save_system.save_game("0", data)
##   if err != OK:
##       push_error("Save failed: ", err)
##
##   # Load
##   var loaded := save_system.load_game("0")
##   if loaded.is_empty():
##       push_error("No save data in slot 0")
##   else:
##       gold = loaded["gold"]
##       wave = loaded["wave"]
##
##   # List all saves
##   var slots := save_system.get_all_save_slots()
##   for meta in slots:
##       print("Slot: %s, Timestamp: %d" % [meta.slot_name, meta.timestamp])
## [/codeblock]
##
## Dependencies: none (zero upstream dependencies — foundation layer).
##
## @tutorial: https://docs.godotengine.org/en/stable/classes/class_configfile.html


# ── Signals ────────────────────────────────────────────────────────────────────

## Emitted after a save operation completes successfully.
## [param slot_name] is the slot identifier (e.g. "0", "auto", "quick").
signal game_saved(slot_name: String)

## Emitted after a save file has been successfully loaded.
## [param slot_name] is the slot identifier that was loaded.
signal game_loaded(slot_name: String)

## Emitted when a save or load operation fails.
## [param slot_name] is the slot identifier involved in the failed operation.
## [param error_code] is the [enum Error] describing the failure.
signal save_failed(slot_name: String, error_code: int)

## Emitted after a save file has been successfully deleted.
## [param slot_name] is the slot identifier that was deleted.
signal save_deleted(slot_name: String)


# ── Configuration ──────────────────────────────────────────────────────────────

## Base directory for save files. Uses Godot's [code]user://[/code] path
## so saves persist across game updates and are isolated per-user.
## Overridable for testing (point to a temp directory).
@export var save_directory: String = "user://saves/"

## File extension appended to save file names.
@export var save_extension: String = ".sav"

## Game version string written into every save file's metadata.
## Used for save-compatibility checks on load.
@export var game_version: String = "1.0.0"


# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Bridge signals to SignalBus autoload if present.
	# This allows UI and other systems to observe save events
	# without directly coupling to the SaveSystem.
	if has_node("/root/SignalBus"):
		_bridge_to_signal_bus()


# ── Public API — Save ──────────────────────────────────────────────────────────

## Saves [param data] to the slot identified by [param slot_name].
##
## Adds metadata (timestamp, version, slot_name) automatically.
## Overwrites any existing save in the same slot without confirmation.
##
## Returns [constant OK] on success, or an [enum Error] code on failure
## (e.g., [constant ERR_CANT_CREATE] if the directory cannot be created,
## [constant ERR_FILE_CANT_WRITE] if the file cannot be written).
##
## [param slot_name]: Identifier for the save slot (e.g. "0", "auto", "quick").
## [param data]: Dictionary of game state to persist. Keys must be [String],
##     values must be Godot Variant types supported by [ConfigFile.set_value].
func save_game(slot_name: String, data: Dictionary) -> int:
	if slot_name.is_empty():
		push_error("SaveSystem.save_game: slot_name must not be empty")
		save_failed.emit(slot_name, ERR_INVALID_PARAMETER)
		return ERR_INVALID_PARAMETER

	# Ensure the save directory exists
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("SaveSystem.save_game: cannot access user:// directory")
		save_failed.emit(slot_name, ERR_CANT_CREATE)
		return ERR_CANT_CREATE

	var save_dir_name := save_directory.trim_prefix("user://")
	if not dir.dir_exists(save_dir_name):
		var mkdir_err := dir.make_dir(save_dir_name)
		if mkdir_err != OK:
			push_error("SaveSystem.save_game: cannot create directory: %s" % save_directory)
			save_failed.emit(slot_name, mkdir_err)
			return mkdir_err

	# Build ConfigFile with metadata and game data
	var config := ConfigFile.new()

	# Metadata section
	config.set_value("meta", "timestamp", Time.get_unix_time_from_system())
	config.set_value("meta", "version", game_version)
	config.set_value("meta", "slot_name", slot_name)

	# Data section: write each key-value pair
	for key in data:
		config.set_value("data", key, data[key])

	# Write to disk
	var file_path := _file_path(slot_name)
	var err := config.save(file_path)
	if err != OK:
		push_error("SaveSystem.save_game: failed to write save file: %s (error %d)" % [file_path, err])
		save_failed.emit(slot_name, err)
		return err

	game_saved.emit(slot_name)
	return OK


# ── Public API — Load ──────────────────────────────────────────────────────────

## Loads save data from the slot identified by [param slot_name].
##
## Returns a [Dictionary] containing all key-value pairs from the [code][data][/code]
## section. Returns an empty [Dictionary] if the save file does not exist, is
## corrupt, or cannot be read.
##
## The metadata ([code][meta][/code] section) is not included in the returned
## dictionary — use [method get_save_metadata] to inspect metadata separately.
##
## Emits [signal game_loaded] on success, [signal save_failed] on failure.
func load_game(slot_name: String) -> Dictionary:
	if slot_name.is_empty():
		push_error("SaveSystem.load_game: slot_name must not be empty")
		save_failed.emit(slot_name, ERR_INVALID_PARAMETER)
		return {}

	var file_path := _file_path(slot_name)
	if not FileAccess.file_exists(file_path):
		push_warning("SaveSystem.load_game: save file not found: %s" % file_path)
		save_failed.emit(slot_name, ERR_FILE_NOT_FOUND)
		return {}

	var config := ConfigFile.new()
	var err := config.load(file_path)
	if err != OK:
		push_error("SaveSystem.load_game: failed to load save file: %s (error %d)" % [file_path, err])
		save_failed.emit(slot_name, err)
		return {}

	# Extract data section into a Dictionary
	var result: Dictionary = {}
	if config.has_section("data"):
		var keys := config.get_section_keys("data")
		for key in keys:
			result[key] = config.get_value("data", key)

	game_loaded.emit(slot_name)
	return result


# ── Public API — Delete ────────────────────────────────────────────────────────

## Deletes the save file for [param slot_name].
##
## Returns [constant OK] on success, [constant ERR_FILE_NOT_FOUND] if the save
## does not exist, or another [enum Error] code if deletion fails.
##
## Emits [signal save_deleted] on success, [signal save_failed] on failure.
func delete_save(slot_name: String) -> int:
	if slot_name.is_empty():
		push_error("SaveSystem.delete_save: slot_name must not be empty")
		save_failed.emit(slot_name, ERR_INVALID_PARAMETER)
		return ERR_INVALID_PARAMETER

	var file_path := _file_path(slot_name)
	if not FileAccess.file_exists(file_path):
		push_warning("SaveSystem.delete_save: save file not found: %s" % file_path)
		save_failed.emit(slot_name, ERR_FILE_NOT_FOUND)
		return ERR_FILE_NOT_FOUND

	var err := DirAccess.remove_absolute(file_path)
	if err != OK:
		push_error("SaveSystem.delete_save: failed to delete: %s (error %d)" % [file_path, err])
		save_failed.emit(slot_name, err)
		return err

	save_deleted.emit(slot_name)
	return OK


# ── Public API — Query ─────────────────────────────────────────────────────────

## Returns [code]true[/code] if a save file exists for [param slot_name].
func has_save(slot_name: String) -> bool:
	if slot_name.is_empty():
		return false
	return FileAccess.file_exists(_file_path(slot_name))


## Returns the metadata [Dictionary] for [param slot_name] without loading
## the full game data.
##
## The returned dictionary contains keys: [code]timestamp[/code] (int),
## [code]version[/code] (String), [code]slot_name[/code] (String).
##
## Returns an empty [Dictionary] if the save file does not exist or is unreadable.
func get_save_metadata(slot_name: String) -> Dictionary:
	if slot_name.is_empty():
		return {}

	var file_path := _file_path(slot_name)
	if not FileAccess.file_exists(file_path):
		return {}

	var config := ConfigFile.new()
	var err := config.load(file_path)
	if err != OK:
		push_warning("SaveSystem.get_save_metadata: cannot read metadata from: %s" % file_path)
		return {}

	var result: Dictionary = {}
	if config.has_section("meta"):
		var keys := config.get_section_keys("meta")
		for key in keys:
			result[key] = config.get_value("meta", key)

	return result


## Scans [member save_directory] for all save files and returns an [Array] of
## metadata [Dictionary] entries, one per discovered save.
##
## Each entry contains: [code]slot_name[/code], [code]timestamp[/code],
## [code]version[/code], and [code]file_path[/code].
##
## Entries are sorted by timestamp descending (most recent first).
## Returns an empty [Array] if no saves exist or the directory is inaccessible.
func get_all_save_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	var dir := DirAccess.open(save_directory)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(save_extension):
			var slot_name := file_name.trim_suffix(save_extension)
			var file_path := save_directory + file_name
			var config := ConfigFile.new()
			if config.load(file_path) == OK and config.has_section("meta"):
				var entry: Dictionary = {
					"slot_name": slot_name,
					"file_path": file_path,
					"timestamp": config.get_value("meta", "timestamp", 0),
					"version": config.get_value("meta", "version", ""),
				}
				result.append(entry)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Sort by timestamp descending (most recent first)
	result.sort_custom(func(a: Dictionary, b: Dictionary): return a.timestamp > b.timestamp)

	return result


# ── Public API — Convenience ───────────────────────────────────────────────────

## Saves [param data] to the autosave slot ("auto").
## Convenience wrapper around [method save_game].
func autosave(data: Dictionary) -> int:
	return save_game("auto", data)


## Saves [param data] to the quicksave slot ("quick").
## Convenience wrapper around [method save_game].
func quick_save(data: Dictionary) -> int:
	return save_game("quick", data)


## Loads from the quicksave slot ("quick").
## Convenience wrapper around [method load_game].
func quick_load() -> Dictionary:
	return load_game("quick")


## Loads from the autosave slot ("auto").
## Convenience wrapper around [method load_game].
func load_autosave() -> Dictionary:
	return load_game("auto")


# ── Private ────────────────────────────────────────────────────────────────────

## Builds the full file path for a given slot name.
func _file_path(slot_name: String) -> String:
	return save_directory + slot_name + save_extension


## Connects this system's signals to the SignalBus autoload for
## cross-system notification. Called once in [method _ready] if SignalBus exists.
##
## Note: Save-related signals must exist on SignalBus for bridging to work.
## If they do not, the connection is silently skipped (Godot will warn in debug).
func _bridge_to_signal_bus() -> void:
	var bus := get_node("/root/SignalBus")

	if bus.has_signal("game_saved"):
		game_saved.connect(
			func(slot: String) -> void:
				bus.game_saved.emit(slot)
		)

	if bus.has_signal("game_loaded"):
		game_loaded.connect(
			func(slot: String) -> void:
				bus.game_loaded.emit(slot)
		)

	if bus.has_signal("save_failed"):
		save_failed.connect(
			func(slot: String, code: int) -> void:
				bus.save_failed.emit(slot, code)
		)

	if bus.has_signal("save_deleted"):
		save_deleted.connect(
			func(slot: String) -> void:
				bus.save_deleted.emit(slot)
		)
