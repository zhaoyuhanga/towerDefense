class_name Monster
extends Node2D
## Abstract base class for all monster entities.
##
## Implements: design/gdd/monster-system.md
## Architecture: docs/architecture/adr-0004-monster-object-pool.md
##
## State machine: SPAWNING -> MOVING -> [DYING | BREACHED]
##                   STUNNED (sub-state of MOVING, applied by skills)
##
## Pool contract (ADR-0004):
##   - All initialization goes through setup() — never _ready()
##   - All cleanup goes through reset()
##   - setup() must be idempotent — called on both fresh and pooled instances
##   - Subclasses must call super.setup() and super.reset()

enum MonsterState {
	SPAWNING,   ## Brief entrance animation phase (~0.3s)
	MOVING,     ## Following path waypoints
	STUNNED,    ## Frozen/slowed by skill effects (e.g. freeze)
	DYING,      ## Health depleted — awaiting despawn by combat system
	BREACHED,   ## Reached exit waypoint — broke through the defensive line
}

## Unique instance identifier assigned at spawn time.
## Format: "{monster_id}_{timestamp_usec}"
var monster_id: String = ""

## True if this monster is currently active (spawned and not yet despawned).
var is_active: bool = false

## Monster configuration data resource (health, speed, reward, tier, etc.).
var data: MonsterData

## Current health. Initialized from data.health in setup().
var current_health: float = 0.0

## Current movement state. Set to SPAWNING initially; transitions to MOVING
## after set_path(); transitions to DYING/BREACHED on death/exit.
var state: MonsterState = MonsterState.SPAWNING

## World-coordinate waypoints to follow. Set via set_path() after spawn.
## Element 0 is the spawn position; last element is the exit.
## Empty until set_path() is called.
var _path: Array[Vector2] = []

## Index of the current target waypoint in _path.
var _waypoint_index: int = 0

## Speed multiplier from active status effects (1.0 = normal speed).
## Modified by apply_effect(); restored to 1.0 when effects expire.
var _speed_multiplier: float = 1.0

## Base speed cached from data.speed. Used with _speed_multiplier
## to compute effective movement speed each frame.
var _base_speed: float = 0.0

## Active effect Timer nodes. All timers are cleaned up in reset().
var _effect_timers: Array[Timer] = []


## Initialize or reinitialize this monster with configuration data.
## Called by MonsterPool.spawn() on both fresh instances and pool-reused instances.
## Must be idempotent — can be called multiple times across pool reuse cycles.
## Subclasses that override must call super.setup(p_data) first.
func setup(p_data: MonsterData) -> void:
	data = p_data
	monster_id = p_data.monster_id + "_" + str(Time.get_ticks_usec())
	current_health = p_data.health
	_base_speed = p_data.speed
	_speed_multiplier = 1.0
	is_active = true
	state = MonsterState.SPAWNING
	_path.clear()
	_waypoint_index = 0
	set_process(true)


## Reset monster to clean pooled state. Called by MonsterPool.despawn().
## Per ADR-0004 five-step checklist:
##   1. Kill all active Tweens (not applicable in base — subclasses override)
##   2. Stop and free all Timer nodes
##   3. Disconnect SignalBus connections (subclass responsibility if any)
##   4. Queue-free dynamic child nodes (effect timers handled here)
##   5. set_process(false) + set_physics_process(false)
## Subclasses that override must call super.reset() last.
func reset() -> void:
	is_active = false
	state = MonsterState.SPAWNING
	current_health = 0.0
	data = null
	_path.clear()
	_waypoint_index = 0
	_speed_multiplier = 1.0
	_base_speed = 0.0
	for timer in _effect_timers:
		if is_instance_valid(timer):
			timer.stop()
			timer.queue_free()
	_effect_timers.clear()
	set_process(false)
	set_physics_process(false)


## Set the world-coordinate movement path and begin moving.
## Called after spawn by the wave spawner or level controller.
##
## path: Array of Vector2 waypoints in world space.
##   path[0] should equal the spawn position.
##   path[path.size()-1] is the exit — reaching it triggers BREACHED.
##
## If the path has only one waypoint, the monster immediately breaches.
func set_path(path: Array[Vector2]) -> void:
	_path = path.duplicate()
	_waypoint_index = 0
	if _path.size() > 0:
		global_position = _path[0]
		if _path.size() > 1:
			_waypoint_index = 1
			state = MonsterState.MOVING
		else:
			# Single-point path: already at exit
			_on_reached_exit()


## Apply damage to this monster. Called by the combat/damage system.
## Amounts are in raw health points (no armor/resistance in MVP).
## If health reaches 0 or below, transitions state to DYING.
## No-ops when is_active is false or state is already DYING/BREACHED.
func take_damage(amount: float) -> void:
	if not is_active:
		return
	if state == MonsterState.DYING or state == MonsterState.BREACHED:
		return
	current_health -= amount
	if current_health <= 0.0:
		current_health = 0.0
		state = MonsterState.DYING
		queue_redraw()


## Apply a status effect to this monster. Called by the skills system.
##
## effect:  Effect type identifier string (e.g. "freeze").
## duration: How long the effect lasts in seconds.
## value:   Effect magnitude — meaning depends on effect type:
##          "freeze": speed multiplier (1.0 = normal, 0.5 = 50%, 0.0 = fully stopped).
##
## No-ops when is_active is false.
func apply_effect(effect: String, duration: float, value: float) -> void:
	if not is_active:
		return
	match effect:
		"freeze":
			state = MonsterState.STUNNED
			_speed_multiplier = value
			var timer := Timer.new()
			timer.one_shot = true
			timer.wait_time = duration
			timer.timeout.connect(_on_effect_expired.bind(timer))
			add_child(timer)
			_effect_timers.append(timer)
			timer.start()


## Callback when an effect Timer expires.
## Restores normal speed and transitions from STUNNED back to MOVING.
func _on_effect_expired(timer: Timer) -> void:
	if is_instance_valid(timer):
		timer.stop()
		timer.queue_free()
	_effect_timers.erase(timer)
	_speed_multiplier = 1.0
	if is_active and state == MonsterState.STUNNED:
		state = MonsterState.MOVING


func _draw() -> void:
	if not is_active:
		return
	var base_color := Color.RED
	var size := 10.0
	if data:
		match data.tier:
			"Elite": size = 14.0; base_color = Color.ORANGE
			"Boss": size = 20.0; base_color = Color.PURPLE
	if _speed_multiplier < 1.0:
		base_color = base_color.lerp(Color.CYAN, 0.5)
	match state:
		MonsterState.SPAWNING: base_color.a = 0.5
		MonsterState.DYING: base_color = Color.DARK_RED
		MonsterState.BREACHED: base_color = Color.DIM_GRAY

	# Body — rounded square
	draw_rect(Rect2(-size, -size*0.7, size*2, size*1.4), base_color, true, 4.0)
	# Eyes
	var eye_color := Color.WHITE if state != MonsterState.DYING else Color.DIM_GRAY
	draw_circle(Vector2(-size*0.35, -size*0.15), size*0.25, eye_color)
	draw_circle(Vector2(size*0.35, -size*0.15), size*0.25, eye_color)
	draw_circle(Vector2(-size*0.35, -size*0.15), size*0.12, Color.BLACK)
	draw_circle(Vector2(size*0.35, -size*0.15), size*0.12, Color.BLACK)
	# Mouth
	draw_arc(Vector2(0, size*0.1), size*0.4, 0, PI, 8, Color.BLACK, 1.5)
	# Feet
	draw_rect(Rect2(-size*0.6, size*0.6, size*0.4, size*0.4), base_color.darkened(0.3), true, 2.0)
	draw_rect(Rect2(size*0.2, size*0.6, size*0.4, size*0.4), base_color.darkened(0.3), true, 2.0)
	# Health bar
	if current_health > 0 and data:
		var hp_ratio := current_health / data.health
		var bar_w := size * 1.8
		draw_rect(Rect2(-bar_w/2, -size-6, bar_w, 3), Color.DIM_GRAY)
		draw_rect(Rect2(-bar_w/2, -size-6, bar_w * hp_ratio, 3), Color.GREEN if hp_ratio > 0.5 else (Color.YELLOW if hp_ratio > 0.25 else Color.RED))


func _process(delta: float) -> void:
	if not is_active:
		return
	if state != MonsterState.MOVING and state != MonsterState.STUNNED:
		return
	if _waypoint_index >= _path.size():
		return

	var target := _path[_waypoint_index]
	var direction := target - global_position
	var distance := direction.length()
	var effective_speed := _base_speed * _speed_multiplier
	var step := effective_speed * delta

	if distance <= step:
		# Arrived at current waypoint
		global_position = target
		_waypoint_index += 1
		if _waypoint_index >= _path.size():
			_on_reached_exit()
	else:
		# Move toward waypoint at effective speed
		global_position += direction.normalized() * step


## Called when the monster reaches the final waypoint (the exit).
## Transitions to BREACHED state and emits the cross-system signal.
func _on_reached_exit() -> void:
	state = MonsterState.BREACHED
	is_active = false
	SignalBus.monster_breached.emit(global_position, _path)
