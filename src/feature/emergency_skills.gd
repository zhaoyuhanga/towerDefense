class_name EmergencySkills
extends Node
## EmergencySkills -- manages limited-use emergency abilities during BATTLE phase.
##
## Implements: design/gdd/emergency-skills.md
## Architecture: docs/architecture/adr-0006-phase-state-machine.md (phase gating)
## State Reset: docs/architecture/adr-0008-state-reset-protocol.md
##
## Two skills: "freeze" (stops all monsters for duration seconds) and
## "repair" (restores defense HP by effect_amount). Both have per-session
## use limits (from SkillConfig.max_uses) and per-wave replenishment
## (from SkillConfig.per_wave_replenish). Cooldown between consecutive
## activations of the same skill. Skills are only usable during BATTLE phase.
##
## Freeze skill: iterates all active monsters via MonsterPool and calls
##   apply_effect("freeze", config.duration, 0.0) to fully stop each monster.
##
## Repair skill: invokes the repair_callback Callable with config.effect_amount.
##   The defense line system registers this callback during initialization.
##   Until a callback is set, repair is a safe no-op.
##
## Dependencies:
##   - MonsterPool: for freeze skill (get_active_monsters + apply_effect)
##   - SkillConfig resources (.tres files): per-skill configuration
##   - repair_callback Callable: set by defense system for repair skill effect
##
## Lifecycle:
##   1. init(monster_pool, skill_configs) -- load configs, subscribe SignalBus
##   2. BATTLE phase -- activate_skill() available
##   3. wave_started -- replenish uses per SkillConfig.per_wave_replenish
##   4. game_reset_requested -- reset all uses to max_uses, clear cooldowns

# ==============================================================================
# Phase Constants (mirrors PhaseManager.Phase enum -- ADR-0006)
# ==============================================================================

const PHASE_PREP: int = 0
const PHASE_BATTLE: int = 1


# ==============================================================================
# SkillState -- Inner Class
# ==============================================================================

## Runtime state for a single emergency skill.
## Tracks remaining uses, cooldown timer, and references the SkillConfig resource.
class SkillState:
	## Skill configuration resource -- all tuning knobs from .tres file.
	var config: SkillConfig

	## Number of uses remaining in the current game session.
	## Decremented on each activation. Replenished on wave_started (capped at max_uses).
	## Reset to max_uses on game_reset.
	var remaining_uses: int

	## Seconds remaining on the current cooldown. 0.0 means ready to use.
	## Ticks down during BATTLE phase only.
	var cooldown_remaining: float

	## True if the skill is currently on cooldown and cannot be activated.
	var is_on_cooldown: bool

	func _init(p_config: SkillConfig) -> void:
		config = p_config
		remaining_uses = p_config.max_uses
		cooldown_remaining = 0.0
		is_on_cooldown = false


# ==============================================================================
# Injected Dependencies
# ==============================================================================

## MonsterPool reference -- set via init(). Used by freeze skill to iterate
## active monsters and apply the freeze effect.
var _monster_pool: MonsterPool = null


# ==============================================================================
# Current Phase
# ==============================================================================

## Current game phase, cached locally via SignalBus.phase_changed subscription.
## Skills are only usable in BATTLE phase. Defaults to PREP.
var _current_phase: int = PHASE_PREP


# ==============================================================================
# Skill States
# ==============================================================================

## Map of skill_id (String) -> SkillState for all registered skills.
## Populated in init() from the skill_configs array.
var _skills: Dictionary = {}


# ==============================================================================
# Repair Callback
# ==============================================================================

## Callback invoked when the repair skill is activated.
## Set by the defense line system during initialization.
## Signature: func(amount: float) -> void
## Default is a no-op -- safe to call before the defense system is ready.
var repair_callback: Callable = func(_amount: float): pass


# ==============================================================================
# Public API -- Initialization
# ==============================================================================


## Initialize the emergency skills system with required dependencies.
##
## Loads all SkillConfig entries from the provided array. Each config's
## skill_id must be unique. Duplicate or invalid configs are skipped with
## a warning.
##
## Subscribes to SignalBus for:
##   - phase_changed: phase gating (skills only in BATTLE)
##   - wave_started: replenish uses per wave
##   - game_reset_requested: full state reset per ADR-0008
##
## Usage:
##   var skills := EmergencySkills.new()
##   skills.init(monster_pool, [freeze_config, repair_config])
##   add_child(skills)
func init(p_monster_pool: MonsterPool, skill_configs: Array[SkillConfig]) -> void:
	_monster_pool = p_monster_pool
	_current_phase = PHASE_PREP

	# Load skill configurations
	for config: SkillConfig in skill_configs:
		if config == null:
			push_warning("EmergencySkills.init: Null SkillConfig in array -- skipping")
			continue
		if config.skill_id.is_empty():
			push_warning("EmergencySkills.init: SkillConfig with empty skill_id -- skipping")
			continue
		if _skills.has(config.skill_id):
			push_warning("EmergencySkills.init: Duplicate skill_id '%s' -- skipping" % config.skill_id)
			continue
		_skills[config.skill_id] = SkillState.new(config)

	# Subscribe to SignalBus events (has_node guard for test safety)
	if has_node("/root/SignalBus"):
		if not SignalBus.phase_changed.is_connected(_on_phase_changed):
			SignalBus.phase_changed.connect(_on_phase_changed)
		if not SignalBus.wave_started.is_connected(_on_wave_started):
			SignalBus.wave_started.connect(_on_wave_started)
		if not SignalBus.game_reset_requested.is_connected(_on_game_reset):
			SignalBus.game_reset_requested.connect(_on_game_reset)


# ==============================================================================
# Public API -- Skill Activation
# ==============================================================================


## Activate an emergency skill by its skill_id.
##
## Validation checks (in order -- all must pass):
##   1. skill_id exists in registered skills
##   2. Current phase is BATTLE (phase gating)
##   3. Skill has remaining uses (> 0)
##   4. Skill is not on cooldown
##
## On success (atomic execution):
##   - Decrements remaining_uses by 1
##   - Starts cooldown timer (cooldown_remaining = config.cooldown)
##   - Executes skill effect:
##       "freeze": calls apply_effect("freeze", duration, 0.0) on all active monsters
##       "repair": invokes repair_callback.call(effect_amount)
##       other:   emits SignalBus.skill_activated(skill_id) for subscriber-driven effects
##   - Emits SignalBus.skill_activated(skill_id) for visual feedback
##   - Returns true
##
## On failure: returns false (no state changes, no signal emitted).
##
## GDD AC: GIVEN freeze uses=0, WHEN button clicked, THEN no response (returns false).
##
## Usage:
##   if skills.activate_skill("freeze"):
##       print("All monsters frozen!")
func activate_skill(skill_id: String) -> bool:
	# Check skill exists
	if not _skills.has(skill_id):
		push_warning("EmergencySkills.activate_skill: Unknown skill_id '%s'" % skill_id)
		return false

	# Phase gate -- skills only available in BATTLE
	if _current_phase != PHASE_BATTLE:
		return false

	var state: SkillState = _skills[skill_id]

	# Check uses remaining
	if state.remaining_uses <= 0:
		return false

	# Check cooldown
	if state.is_on_cooldown:
		return false

	# -- Execute Skill (atomic: decrement uses + start cooldown upfront) ------

	state.remaining_uses -= 1
	state.is_on_cooldown = true
	state.cooldown_remaining = state.config.cooldown

	# Apply effect based on skill type
	match skill_id:
		"freeze":
			_execute_freeze(state.config)
		"repair":
			_execute_repair(state.config)

	# Emit signal for visual feedback / HUD updates
	if has_node("/root/SignalBus"):
		SignalBus.skill_activated.emit(skill_id)

	return true


# ==============================================================================
# Public API -- Queries
# ==============================================================================


## Check if a skill can be activated right now.
## Pure query -- no side effects. Used by UI to grey out buttons.
##
## Returns true iff: skill_id exists AND in BATTLE phase AND has uses remaining
## AND not on cooldown.
func can_activate(skill_id: String) -> bool:
	if not _skills.has(skill_id):
		return false
	if _current_phase != PHASE_BATTLE:
		return false
	var state: SkillState = _skills[skill_id]
	return state.remaining_uses > 0 and not state.is_on_cooldown


## Get the number of remaining uses for a skill.
## Returns 0 for unknown skill_ids.
func get_remaining_uses(skill_id: String) -> int:
	if not _skills.has(skill_id):
		return 0
	return _skills[skill_id].remaining_uses


## Get the maximum uses for a skill (from config).
## Returns 0 for unknown skill_ids.
func get_max_uses(skill_id: String) -> int:
	if not _skills.has(skill_id):
		return 0
	return _skills[skill_id].config.max_uses


## Get the cooldown remaining for a skill in seconds.
## Returns 0.0 for unknown skill_ids or skills not on cooldown.
func get_cooldown_remaining(skill_id: String) -> float:
	if not _skills.has(skill_id):
		return 0.0
	return _skills[skill_id].cooldown_remaining


## Get the SkillConfig for a registered skill.
## Returns null for unknown skill_ids. Used by UI for display names, icons, etc.
func get_skill_config(skill_id: String) -> SkillConfig:
	if not _skills.has(skill_id):
		return null
	return _skills[skill_id].config


## Register a new skill or replace an existing one at runtime.
## Used for testing and for systems that dynamically add skills.
## If a skill with the same skill_id already exists, its state is replaced.
func register_skill(config: SkillConfig) -> void:
	if config == null or config.skill_id.is_empty():
		push_warning("EmergencySkills.register_skill: Invalid config")
		return
	_skills[config.skill_id] = SkillState.new(config)


# ==============================================================================
# Public API -- Per-Frame Update
# ==============================================================================


## Update cooldowns each frame. Call from _process() of the owning scene.
## Only advances cooldowns during BATTLE phase. Cooldowns do not tick down
## during PREP (player is planning) or PAUSED (game is frozen).
##
## Can be called directly in tests to simulate frame delta without scene tree.
func _process(delta: float) -> void:
	if _current_phase != PHASE_BATTLE:
		return

	for skill_id in _skills:
		var state: SkillState = _skills[skill_id]
		if state.is_on_cooldown:
			state.cooldown_remaining -= delta
			if state.cooldown_remaining <= 0.0:
				state.cooldown_remaining = 0.0
				state.is_on_cooldown = false


# ==============================================================================
# Internal -- Skill Execution
# ==============================================================================


## Execute freeze skill: apply freeze effect to all active monsters.
## Speed multiplier = 0.0 (fully stopped). Duration from config.
## No-ops gracefully if MonsterPool is null or has no active monsters.
func _execute_freeze(config: SkillConfig) -> void:
	if _monster_pool == null:
		push_error("EmergencySkills._execute_freeze: MonsterPool not set")
		return

	for monster: Monster in _monster_pool.get_active_monsters():
		if monster != null and is_instance_valid(monster):
			monster.apply_effect("freeze", config.duration, 0.0)


## Execute repair skill: invoke the repair callback with effect_amount.
## The defense line system is responsible for handling the actual HP change.
## This indirection keeps EmergencySkills decoupled from the defense system.
func _execute_repair(config: SkillConfig) -> void:
	repair_callback.call(config.effect_amount)


# ==============================================================================
# Signal Handlers
# ==============================================================================


## React to phase transitions from SignalBus.
## Caches the new phase locally for skill activation gating.
## ADR-0006: systems use local phase cache + SignalBus subscription.
func _on_phase_changed(_old_phase: int, new_phase: int) -> void:
	_current_phase = new_phase


## React to wave started -- replenish skill uses per SkillConfig.per_wave_replenish.
## Each skill gains per_wave_replenish additional uses, capped at max_uses.
## GDD: 次数在准备阶段通过特定方式积累（如每波+1 次）.
func _on_wave_started(_wave_number: int) -> void:
	for skill_id in _skills:
		var state: SkillState = _skills[skill_id]
		var replenish: int = state.config.per_wave_replenish
		if replenish > 0:
			state.remaining_uses = min(state.remaining_uses + replenish, state.config.max_uses)


## Handle game reset -- restore all skills to max_uses, clear all cooldowns,
## and reset phase to PREP.
## ADR-0008: config-based reset on game_reset_requested.
func _on_game_reset() -> void:
	_current_phase = PHASE_PREP
	for skill_id in _skills:
		var state: SkillState = _skills[skill_id]
		state.remaining_uses = state.config.max_uses
		state.cooldown_remaining = 0.0
		state.is_on_cooldown = false
