# MonsterPool — Global monster lifecycle manager (ADR-0004)
# Manages monster node pooling: spawn, despawn, warmup.
# Cross-system communication via SignalBus (ADR-0001).
class_name MonsterPool
extends Node

## Maximum pooled monsters per monster type before excess are queue_freed.
const MAX_POOLED_PER_TYPE: int = 50

## Pooled monsters organized by monster_id string.
## Dictionary[String, Array[Monster]] — keyed by data.monster_id (e.g. "goblin_standard").
var _pools: Dictionary = {}

## PackedScene references by monster_id string.
## Dictionary[String, PackedScene] — populated via register_scene().
var _scenes: Dictionary = {}

## Currently active (spawned but not yet despawned) monsters.
var _active: Array[Monster] = []


## Register a PackedScene for a monster type.
## Must be called before spawn() or warmup() for that type.
## Safe to call multiple times — overwrites previous registration.
func register_scene(type: String, scene: PackedScene) -> void:
	_scenes[type] = scene
	if not _pools.has(type):
		_pools[type] = []


## Spawn a monster of the given type, retrieving from pool if available.
## If the pool is empty, instantiates a fresh monster from the registered PackedScene.
##
## type:     Monster type identifier (matches MonsterData.monster_id).
## parent:   Scene tree node to parent the monster under (e.g. LevelScene/Monsters).
## position: World-space spawn position (Vector2).
## data:     MonsterData resource with this instance's attributes.
##
## Returns:  The spawned Monster instance, or null if no scene is registered.
##
## Note:     The monster is added to parent via call_deferred("add_child", monster)
##           per ADR-0004 safety constraint. Do not access monster.global_position
##           immediately after spawn — wait for the deferred add to complete.
func spawn(type: String, parent: Node, position: Vector2, data: MonsterData) -> Monster:
	var pool: Array = _pools.get(type, [])
	var monster: Monster

	if pool.size() > 0:
		monster = pool.pop_back() as Monster
	else:
		var scene: PackedScene = _scenes.get(type)
		if scene == null:
			push_error("MonsterPool: No scene registered for type '%s'" % type)
			return null
		monster = scene.instantiate() as Monster
		if monster == null:
			push_error("MonsterPool: Failed to instantiate scene for type '%s'" % type)
			return null

	monster.setup(data)
	monster.global_position = position
	parent.call_deferred("add_child", monster)
	_active.append(monster)
	return monster


## Return a monster to the pool. Called by the combat system when health <= 0.
##
## Processing order per ADR-0004:
##   1. Guard: no-op if monster is null or is_active is already false.
##   2. Capture monster_id, position, reward_gold before reset() clears data.
##   3. Remove from scene tree (if inside tree).
##   4. Call monster.reset() to clear all runtime state.
##   5. Remove from _active array.
##   6. Return to pool (if pool not full) or queue_free (if pool full).
##   7. Emit SignalBus.monster_died for downstream systems (economy, visual, HUD).
func despawn(monster: Monster) -> void:
	if monster == null or not monster.is_active:
		return

	var monster_id := monster.monster_id
	var position := monster.global_position
	var reward := 0
	var type := ""
	if monster.data != null:
		reward = monster.data.reward_gold
		type = monster.data.monster_id

	if monster.is_inside_tree():
		monster.get_parent().remove_child(monster)

	monster.reset()
	_active.erase(monster)

	if type != "":
		var pool: Array = _pools.get(type, [])
		if pool.size() < MAX_POOLED_PER_TYPE:
			pool.append(monster)
		else:
			# Pool full — destroy the node. Must erase from _active first
			# to prevent external iterators from accessing zombie nodes.
			monster.queue_free()
	else:
		# No type information (data was null) — cannot pool, must destroy.
		monster.queue_free()

	SignalBus.monster_died.emit(monster_id, position, reward)


## Pre-allocate count monsters of the given type into the pool.
## Pre-allocated nodes are off-tree (not parented to any node).
## Use during loading screens to absorb first-instantiation cost.
##
## Respects MAX_POOLED_PER_TYPE — will not exceed the cap.
## Safe to call multiple times; warmup is additive up to the cap.
func warmup(type: String, count: int) -> void:
	var scene: PackedScene = _scenes.get(type)
	if scene == null:
		push_error("MonsterPool: No scene registered for type '%s'" % type)
		return

	if not _pools.has(type):
		_pools[type] = []

	var pool: Array = _pools[type]
	for _i in range(count):
		if pool.size() >= MAX_POOLED_PER_TYPE:
			break
		var monster := scene.instantiate() as Monster
		if monster == null:
			push_error("MonsterPool: Failed to instantiate scene for type '%s'" % type)
			continue
		pool.append(monster)


## Return the number of currently active (spawned, not yet despawned) monsters.
func get_active_count() -> int:
	return _active.size()


## Return the number of pooled (off-tree, ready to reuse) monsters of a type.
func get_pooled_count(type: String) -> int:
	var pool: Array = _pools.get(type, [])
	return pool.size()


## Return a copy of the active monsters array.
## Used by tower targeting systems to find targets.
## Returns a duplicate so callers can safely iterate without mutation issues.
func get_active_monsters() -> Array[Monster]:
	return _active.duplicate()
