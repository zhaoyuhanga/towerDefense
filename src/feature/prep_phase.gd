class_name PhaseManager
extends Node
## PhaseManager -- manages the game phase state machine (PREP <-> BATTLE <-> PAUSED).
##
## Implements: design/gdd/prep-phase.md
## Architecture: docs/architecture/adr-0006-phase-state-machine.md
## State Reset: docs/architecture/adr-0008-state-reset-protocol.md
##
## Single source of truth for the current game phase. All phase transitions
## are validated here. Phase changes are broadcast via SignalBus.phase_changed
## (int-typed parameters per ADR-0006 to avoid Autoload->PhaseManager coupling).
##
## PREP phase:  Player builds maze, places/sells/merges towers, previews next wave.
## BATTLE phase: Monsters march, towers auto-attack, emergency skills available.
## PAUSED phase: Engine-level pause (get_tree().paused = true), all logic frozen.
##
## Lifecycle:
##   1. Game start -> PhaseManager initialized in PREP (no initial signal emit)
##   2. Player clicks "Start Wave" -> start_wave() -> PREP -> BATTLE
##   3. All monsters resolved -> WaveSpawner calls on_wave_ended() -> BATTLE -> PREP
##   4. Repeat 2-3 for each wave
##   5. ESC key (V1.0) -> pause() -> PAUSED -> resume() -> previous phase
##
## Systems consume phase via SignalBus.phase_changed subscription + local cache.
## Systems that need to query the initial phase use %PhaseManager Unique Name lookup.

# ==============================================================================
# Phase Enum
# ==============================================================================

enum Phase {
	PREP = 0,    ## Build phase -- player places blocks, buys/merges towers
	BATTLE = 1,  ## Combat phase -- monsters march, towers auto-attack
	PAUSED = 2,  ## Pause (V1.0) -- ESC-triggered, engine-level freeze via get_tree().paused
}


# ==============================================================================
# Public State
# ==============================================================================

## Current game phase. Read-only externally -- use start_wave() / on_wave_ended()
## to request transitions, never assign directly.
## Systems should subscribe to SignalBus.phase_changed for updates rather
## than polling this value.
var current_phase: Phase = Phase.PREP

## Information about the next wave for UI preview during PREP phase.
## Set via set_next_wave_preview() by the wave data loader.
## Keys: "wave_number" (int), "monster_types" (Array[String]),
##       "monster_count" (int), "has_boss" (bool), "has_affix" (bool)
var next_wave_preview: Dictionary = {}


# ==============================================================================
# Private State
# ==============================================================================

## Phase before entering PAUSED. Used by resume() to restore the correct phase.
var _previous_phase: Phase = Phase.PREP

## Guard preventing re-entrant phase transitions from signal cascades.
var _is_transitioning: bool = false


# ==============================================================================
# Public API -- Initialization
# ==============================================================================


## Initialize the phase manager. Subscribes to SignalBus.game_reset_requested
## for ADR-0008 state reset. Does NOT emit the initial phase -- systems default
## to PREP as an implicit contract (ADR-0006 section "SignalBus + local cache").
##
## Must be called after adding to the scene tree if SignalBus subscription
## is needed. In tests, call init() directly before use.
##
## Usage:
##   var pm := PhaseManager.new()
##   pm.init()
##   add_child(pm)
func init() -> void:
	current_phase = Phase.PREP
	_previous_phase = Phase.PREP
	_is_transitioning = false

	# Subscribe to game reset (has_node guard for test safety)
	if has_node("/root/SignalBus"):
		if not SignalBus.game_reset_requested.is_connected(_on_game_reset):
			SignalBus.game_reset_requested.connect(_on_game_reset)


# ==============================================================================
# Public API -- Phase Transitions
# ==============================================================================


## Transition from PREP to BATTLE.
## Called by InputHandler when the player clicks the "Start Wave" button.
## No-ops with a warning if not currently in PREP.
func start_wave() -> void:
	if current_phase != Phase.PREP:
		push_warning("PhaseManager.start_wave: Cannot start wave from phase %s" % Phase.find_key(current_phase))
		return
	_set_phase(Phase.BATTLE)


## Transition from BATTLE to PREP.
## Called by WaveSpawner after all monsters are resolved and the inter-wave
## pause timer expires.
## No-ops with a warning if not currently in BATTLE.
func on_wave_ended() -> void:
	if current_phase != Phase.BATTLE:
		push_warning("PhaseManager.on_wave_ended: Cannot end wave from phase %s" % Phase.find_key(current_phase))
		return
	_set_phase(Phase.PREP)


## Pause the game (V1.0). Transitions from PREP or BATTLE to PAUSED.
## Uses get_tree().paused = true to freeze all _process / _physics_process /
## Timer / Tween. UI elements that must remain interactive should be set to
## PROCESS_MODE_ALWAYS.
## No-ops if already PAUSED.
func pause() -> void:
	if current_phase == Phase.PAUSED:
		return
	_previous_phase = current_phase
	get_tree().paused = true
	_set_phase(Phase.PAUSED)


## Resume the game from PAUSED (V1.0). Restores the phase from before pause.
## No-ops if not currently in PAUSED.
func resume() -> void:
	if current_phase != Phase.PAUSED:
		return
	get_tree().paused = false
	_set_phase(_previous_phase)


# ==============================================================================
# Public API -- Wave Preview
# ==============================================================================


## Set the next wave preview data for UI display during PREP phase.
##
## preview: Dictionary with keys:
##   - "wave_number": int       -- the upcoming wave number
##   - "monster_types": Array[String] -- unique monster IDs appearing
##   - "monster_count": int     -- total monsters in the wave
##   - "has_boss": bool         -- whether a boss monster appears
##   - "has_affix": bool        -- whether any monsters have affixes
func set_next_wave_preview(preview: Dictionary) -> void:
	next_wave_preview = preview.duplicate()


## Clear the next wave preview. Called automatically when transitioning
## to BATTLE. Can also be called manually to reset the preview state.
func clear_wave_preview() -> void:
	next_wave_preview.clear()


# ==============================================================================
# Internal -- Phase Transition
# ==============================================================================


## Validate and execute a phase transition.
##
## Rejects duplicate phases (PREP -> PREP, BATTLE -> BATTLE) with a warning.
## Rejects re-entrant calls via _is_transitioning guard.
##
## Emits SignalBus.phase_changed(old_phase as int, new_phase as int).
## Parameters are int (not Phase enum) to match SignalBus signal signature,
## avoiding the Autoload -> PhaseManager reverse dependency (ADR-0006).
##
## When transitioning to BATTLE, automatically clears the wave preview.
func _set_phase(new_phase: Phase) -> void:
	if _is_transitioning:
		push_warning("PhaseManager._set_phase: Re-entrant transition blocked (tried %s -> %s)" % [Phase.find_key(current_phase), Phase.find_key(new_phase)])
		return

	if new_phase == current_phase:
		push_warning("PhaseManager._set_phase: Duplicate phase %s -- ignoring" % Phase.find_key(new_phase))
		return

	_is_transitioning = true
	var old_phase: Phase = current_phase
	current_phase = new_phase

	# Clear wave preview when entering BATTLE
	if new_phase == Phase.BATTLE:
		clear_wave_preview()

	# Emit via SignalBus (int cast per ADR-0006)
	if has_node("/root/SignalBus"):
		SignalBus.phase_changed.emit(old_phase as int, new_phase as int)

	_is_transitioning = false


# ==============================================================================
# Game Reset (ADR-0008)
# ==============================================================================


## Handle game reset -- return to initial phase (PREP).
## Unpauses the tree if currently paused. Clears wave preview.
## Emits phase_changed so all systems re-synchronize.
func _on_game_reset() -> void:
	# Ensure tree is unpaused if resetting from PAUSED
	if get_tree().paused:
		get_tree().paused = false

	_is_transitioning = false
	_previous_phase = Phase.PREP
	clear_wave_preview()

	var old_phase: Phase = current_phase
	current_phase = Phase.PREP

	if has_node("/root/SignalBus"):
		SignalBus.phase_changed.emit(old_phase as int, Phase.PREP as int)
