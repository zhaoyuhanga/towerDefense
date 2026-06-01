class_name DataLoader
extends Node
## Centralized data loading and validation utility per ADR-0002.
## Uses DirAccess to scan a directory for .tres files, loads each via load(),
## indexes them into a Dictionary by "[id]_[variant]" key, and validates.
##
## Each consuming system calls load_resources() from its _ready() method.
## No central autoload — each system owns its data Dictionary.
##
## Usage:
##     var tower_data := DataLoader.load_resources(
##         "res://src/resources/towers",
##         load("res://src/resources/tower_data.gd")
##     )
##     var errors := DataLoader.validate_tower_data(tower_data)
##     if errors.size() > 0:
##         for err in errors:
##             push_error(err)

## Emitted when a load operation completes. Carries the resource type name
## and the number of successfully loaded entries.
signal data_loaded(resource_name: String, entry_count: int)


# ---------------------------------------------------------------------------
# Public API — Loading
# ---------------------------------------------------------------------------


## Scans [param path] directory for .tres files, loads each one, validates
## against [param resource_class], and returns a Dictionary indexed by the
## entity's natural key ("tower_id_star_level" for TowerData, "monster_id"
## for MonsterData, fallback to filename for unrecognized types).
##
## [param path]: Absolute resource path (e.g. "res://src/resources/towers").
## [param resource_class]: A Script reference obtained via load()/preload()
##     (e.g. load("res://src/resources/tower_data.gd")).
##     Each loaded resource must be an instance of this script class.
##
## Returns: Dictionary[String, Resource]. Empty dict if directory missing
##     or no valid .tres files found.
static func load_resources(path: String, resource_class: Script) -> Dictionary:
	var result := {}

	var dir := DirAccess.open(path)
	if dir == null:
		push_error("DataLoader: Cannot open directory: " + path)
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			_load_and_index(path + "/" + file_name, resource_class, result)
		file_name = dir.get_next()
	dir.list_dir_end()

	return result


## Loads a single .tres file and returns it as a Resource.
## Returns null and pushes an error if the file is missing or corrupt.
##
## [param path]: Full resource path to a single .tres file
##     (e.g. "res://src/resources/economy_default.tres").
##
## Returns: The loaded Resource, or null on failure.
static func load_single(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		push_error("DataLoader: Resource file not found: " + path)
		return null

	var res := load(path)
	if res == null:
		push_error("DataLoader: Failed to load (corrupt or invalid): " + path)
		return null

	return res


# ---------------------------------------------------------------------------
# Public API — Validation
# ---------------------------------------------------------------------------


## Validates a Dictionary of TowerData resources loaded by load_resources().
## Checks:
##   - attack within [1.0, 999.0] for every entry
##   - cost >= 0 for every entry
##   - attack monotonic by star_level within the same tower_id
##     (1-star attack < 2-star attack < 3-star attack)
##
## Returns: PackedStringArray of error messages. Empty array = all valid.
static func validate_tower_data(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()

	# Group towers by tower_id
	var by_id: Dictionary = {}
	for key in data:
		var td: TowerData = data[key]
		if td == null:
			errors.append("Null entry at key: " + str(key))
			continue
		var tid := td.tower_id
		if not by_id.has(tid):
			by_id[tid] = []
		by_id[tid].append(td)

	for tid in by_id:
		var towers: Array = by_id[tid]
		# Sort ascending by star_level
		towers.sort_custom(func(a: TowerData, b: TowerData): return a.star_level < b.star_level)

		var prev_attack: float = -1.0
		for td: TowerData in towers:
			# Range check: attack
			if td.attack < 1.0 or td.attack > 999.0:
				errors.append("TowerData %s star %d: attack %.1f out of range [1.0, 999.0]" % [td.tower_id, td.star_level, td.attack])

			# Cost >= 0
			if td.cost < 0:
				errors.append("TowerData %s star %d: cost %d < 0" % [td.tower_id, td.star_level, td.cost])

			# Monotonic by star
			if prev_attack >= 0.0 and td.attack <= prev_attack:
				errors.append("TowerData %s: attack not monotonic — star %d (%.1f) <= star %d (%.1f)" % [td.tower_id, td.star_level, td.attack, td.star_level - 1, prev_attack])

			prev_attack = td.attack

	return errors


## Validates a Dictionary of MonsterData resources loaded by load_resources().
## Checks:
##   - health within [1.0, 99999.0] for every entry
##   - speed within [20.0, 200.0] for every entry
##   - health monotonic by tier: Boss health > Elite health > Standard health
##     (max within each tier compared)
##
## Returns: PackedStringArray of error messages. Empty array = all valid.
static func validate_monster_data(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()

	# Collect max health per tier
	var tier_max_health := {
		"Standard": 0.0,
		"Elite": 0.0,
		"Boss": 0.0,
	}

	for key in data:
		var md: MonsterData = data[key]
		if md == null:
			errors.append("Null entry at key: " + str(key))
			continue

		# Range check: health
		if md.health < 1.0 or md.health > 99999.0:
			errors.append("MonsterData %s: health %.1f out of range [1.0, 99999.0]" % [md.monster_id, md.health])

		# Range check: speed
		if md.speed < 20.0 or md.speed > 200.0:
			errors.append("MonsterData %s: speed %.1f out of range [20.0, 200.0]" % [md.monster_id, md.speed])

		# Track max health per tier
		if tier_max_health.has(md.tier):
			if md.health > tier_max_health[md.tier]:
				tier_max_health[md.tier] = md.health
		else:
			errors.append("MonsterData %s: unknown tier '%s'" % [md.monster_id, md.tier])

	# Tier health hierarchy: Boss > Elite > Standard
	var boss_health: float = tier_max_health.get("Boss", 0.0)
	var elite_health: float = tier_max_health.get("Elite", 0.0)
	var standard_health: float = tier_max_health.get("Standard", 0.0)

	if boss_health > 0.0 and elite_health > 0.0 and boss_health <= elite_health:
		errors.append("MonsterData tier violation: Boss max health (%.1f) <= Elite max health (%.1f)" % [boss_health, elite_health])
	if elite_health > 0.0 and standard_health > 0.0 and elite_health <= standard_health:
		errors.append("MonsterData tier violation: Elite max health (%.1f) <= Standard max health (%.1f)" % [elite_health, standard_health])

	return errors


## Validates an EconomyConfig resource loaded by load_single().
## Checks:
##   - starting_gold > 0
##   - BLOCK_COST > 0
##   - BLOCK_SELL_VALUE > 0
##   - MERGE_COST >= 0
##   - kill_reward_multiplier > 0.0
##
## Returns: PackedStringArray of error messages. Empty array = all valid.
static func validate_economy_config(config: EconomyConfig) -> PackedStringArray:
	var errors := PackedStringArray()

	if config == null:
		errors.append("EconomyConfig is null")
		return errors

	if config.starting_gold <= 0:
		errors.append("EconomyConfig: starting_gold %d <= 0" % config.starting_gold)
	if config.BLOCK_COST <= 0:
		errors.append("EconomyConfig: BLOCK_COST %d <= 0" % config.BLOCK_COST)
	if config.BLOCK_SELL_VALUE <= 0:
		errors.append("EconomyConfig: BLOCK_SELL_VALUE %d <= 0" % config.BLOCK_SELL_VALUE)
	if config.MERGE_COST < 0:
		errors.append("EconomyConfig: MERGE_COST %d < 0" % config.MERGE_COST)
	if config.kill_reward_multiplier <= 0.0:
		errors.append("EconomyConfig: kill_reward_multiplier %.2f <= 0.0" % config.kill_reward_multiplier)

	return errors


# ---------------------------------------------------------------------------
# Internal Helpers
# ---------------------------------------------------------------------------


## Loads a single .tres file, validates type, checks for duplicate keys,
## and inserts into [param result] Dictionary.
static func _load_and_index(full_path: String, resource_class: Script, result: Dictionary) -> void:
	var res := load(full_path)
	if res == null:
		push_error("DataLoader: Failed to load resource: " + full_path)
		return

	if not is_instance_of(res, resource_class):
		push_error("DataLoader: Type mismatch in %s — expected %s, got %s" % [full_path, resource_class.resource_path.get_file(), res.get_class()])
		return

	var key := _make_key(res)
	if key == "":
		push_error("DataLoader: Could not determine key for: " + full_path)
		return

	if result.has(key):
		push_warning("DataLoader: Duplicate key '%s' — %s overwrites previous entry" % [key, full_path])

	result[key] = res


## Derives a natural key from a Resource instance.
## TowerData → "tower_id_star_level"
## MonsterData → "monster_id"
## Fallback → filename without extension
static func _make_key(res: Resource) -> String:
	var tid = res.get("tower_id")
	if tid != null:
		var star = res.get("star_level")
		return str(tid) + "_" + str(star if star != null else 0)

	var mid = res.get("monster_id")
	if mid != null:
		return str(mid)

	# Fallback: use the filename portion of the resource path
	var rp: String = res.resource_path
	if rp != "":
		return rp.get_file().get_basename()

	return ""
