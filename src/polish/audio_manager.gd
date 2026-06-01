class_name AudioManager
extends Node
## AudioManager -- manages all game audio (SFX + music).
##
## Implements: design/gdd/audio.md
## State Reset: docs/architecture/adr-0008-state-reset-protocol.md
##
## Pure signal consumer -- subscribes to all audio-relevant gameplay signals.
## Does NOT write to any game system.
##
## V1.0 STATUS: All audio playback is STUBBED. Each signal handler logs a
## push_warning indicating the event is not yet implemented. Volume controls
## are stub properties with no actual effect on audio output.
##
## When V1.0 audio production begins:
##   - Load .ogg files from assets/audio/sfx/ and assets/audio/music/
##   - Create AudioStreamPlayer nodes for SFX and Music channels
##   - Replace push_warning calls with actual audio playback
##   - Wire volume controls to AudioServer or bus volumes
##
## Event coverage (per GDD audio event table):
##   Tower shoot (HIGH)   -- not yet signal-driven, needs tower_attacked signal
##   Monster death (HIGH)  -- monster_died
##   Merge success (HIGH)  -- merge_completed
##   Merge failure (MED)   -- merge_failed
##   Block placement (MED) -- cell_state_changed (BLOCK)
##   Block removal (MED)   -- cell_state_changed (EMPTY from BLOCK)
##   UI button click (LOW) -- handled by UI layer directly (not this system)
##   Wave start (MED)     -- wave_started
##   Wave victory (MED)   -- wave_ended
##   Monster breach (HIGH)-- monster_breached
##   Skill activate (MED) -- skill_activated
##   Background music (LOW)-- game running loop
##
## Usage:
##   var audio := AudioManager.new()
##   audio.init()
##   add_child(audio)


# ==============================================================================
# Volume State (stubs -- V1.0 implementation)
# ==============================================================================

## Master volume. Range [0.0, 1.0]. Default 1.0.
## V1.0: sets AudioServer master bus volume.
var _master_volume: float = 1.0

## SFX volume. Range [0.0, 1.0]. Default 1.0.
## V1.0: sets SFX bus volume.
var _sfx_volume: float = 1.0

## Music volume. Range [0.0, 1.0]. Default 0.8.
## V1.0: sets Music bus volume.
var _music_volume: float = 0.8


# ==============================================================================
# Board Cell State Constants (mirror BoardGrid.CellState)
# ==============================================================================

const CELL_EMPTY: int = 0
const CELL_BLOCK: int = 3


# ==============================================================================
# Public API -- Initialization
# ==============================================================================


## Initialize the audio manager.
##
## Subscribes to all audio-relevant SignalBus signals.
## All handlers are V1.0 stubs that log push_warning.
##
## Must be called after adding to the scene tree if SignalBus access is needed.
func init() -> void:
	# Subscribe to SignalBus events (has_node guard for test safety)
	if has_node("/root/SignalBus"):
		if not SignalBus.monster_died.is_connected(_on_monster_died):
			SignalBus.monster_died.connect(_on_monster_died)
		if not SignalBus.monster_breached.is_connected(_on_monster_breached):
			SignalBus.monster_breached.connect(_on_monster_breached)
		if not SignalBus.damage_dealt.is_connected(_on_damage_dealt):
			SignalBus.damage_dealt.connect(_on_damage_dealt)
		if not SignalBus.merge_completed.is_connected(_on_merge_completed):
			SignalBus.merge_completed.connect(_on_merge_completed)
		if not SignalBus.merge_failed.is_connected(_on_merge_failed):
			SignalBus.merge_failed.connect(_on_merge_failed)
		if not SignalBus.wave_started.is_connected(_on_wave_started):
			SignalBus.wave_started.connect(_on_wave_started)
		if not SignalBus.wave_ended.is_connected(_on_wave_ended):
			SignalBus.wave_ended.connect(_on_wave_ended)
		if not SignalBus.cell_state_changed.is_connected(_on_cell_state_changed):
			SignalBus.cell_state_changed.connect(_on_cell_state_changed)
		if not SignalBus.skill_activated.is_connected(_on_skill_activated):
			SignalBus.skill_activated.connect(_on_skill_activated)
		if not SignalBus.game_reset_requested.is_connected(_on_game_reset):
			SignalBus.game_reset_requested.connect(_on_game_reset)
		if not SignalBus.phase_changed.is_connected(_on_phase_changed):
			SignalBus.phase_changed.connect(_on_phase_changed)
		if not SignalBus.block_count_changed.is_connected(_on_block_count_changed):
			SignalBus.block_count_changed.connect(_on_block_count_changed)


# ==============================================================================
# Public API -- Volume Control (V1.0 stubs)
# ==============================================================================


## Set master volume level.
## V1.0: applies to AudioServer master bus.
func set_master_volume(volume: float) -> void:
	_master_volume = clampf(volume, 0.0, 1.0)
	push_warning("AudioManager: set_master_volume(%.2f) -- V1.0 stub (no audio output)" % _master_volume)


## Set SFX volume level.
## V1.0: applies to SFX bus.
func set_sfx_volume(volume: float) -> void:
	_sfx_volume = clampf(volume, 0.0, 1.0)
	push_warning("AudioManager: set_sfx_volume(%.2f) -- V1.0 stub (no audio output)" % _sfx_volume)


## Set music volume level.
## V1.0: applies to Music bus.
func set_music_volume(volume: float) -> void:
	_music_volume = clampf(volume, 0.0, 1.0)
	push_warning("AudioManager: set_music_volume(%.2f) -- V1.0 stub (no audio output)" % _music_volume)


## Get current master volume.
func get_master_volume() -> float:
	return _master_volume


## Get current SFX volume.
func get_sfx_volume() -> float:
	return _sfx_volume


## Get current music volume.
func get_music_volume() -> float:
	return _music_volume


# ==============================================================================
# Public API -- Music Control (V1.0 stubs)
# ==============================================================================


## Start background music playback.
## V1.0: loads and plays the main BGM loop from assets/audio/music/.
func play_bgm() -> void:
	push_warning("AudioManager: play_bgm() -- V1.0 stub (no audio output)")


## Stop background music playback.
## V1.0: stops the BGM AudioStreamPlayer.
func stop_bgm() -> void:
	push_warning("AudioManager: stop_bgm() -- V1.0 stub (no audio output)")


# ==============================================================================
# Signal Handlers -- Monster Events
# ==============================================================================


## GDD audio event: 怪物死亡 -- SFX, HIGH priority.
func _on_monster_died(_monster_id: String, _position: Vector2, _reward_gold: int) -> void:
	push_warning("AudioManager: monster_died SFX not implemented (V1.0)")


## GDD audio event: 防线突破 -- SFX, HIGH priority.
func _on_monster_breached(_position: Vector2, _path: Array) -> void:
	push_warning("AudioManager: monster_breached SFX not implemented (V1.0)")


# ==============================================================================
# Signal Handlers -- Combat Events
# ==============================================================================


## GDD audio event: 塔射击 -- SFX, HIGH priority.
## Note: damage_dealt is used as proxy for tower attack audio.
## V1.0 may introduce a dedicated tower_attacked signal with position data.
func _on_damage_dealt(_target_id: String, _amount: float, _damage_type: String) -> void:
	push_warning("AudioManager: tower_shoot SFX not implemented (V1.0)")


# ==============================================================================
# Signal Handlers -- Merge Events
# ==============================================================================


## GDD audio event: 合星成功 -- SFX, HIGH priority.
func _on_merge_completed(_from_star: int, _to_star: int, _position: Vector2i) -> void:
	push_warning("AudioManager: merge_completed SFX not implemented (V1.0)")


## GDD audio event: 合星失败 -- SFX, MEDIUM priority.
func _on_merge_failed(_reason: String) -> void:
	push_warning("AudioManager: merge_failed SFX not implemented (V1.0)")


# ==============================================================================
# Signal Handlers -- Wave Events
# ==============================================================================


## GDD audio event: 波次开始 -- SFX, MEDIUM priority.
func _on_wave_started(_wave_number: int) -> void:
	push_warning("AudioManager: wave_started SFX not implemented (V1.0)")


## GDD audio event: 波次胜利 -- SFX, MEDIUM priority.
func _on_wave_ended(_wave_number: int, _enemies_killed: int, _enemies_breached: int) -> void:
	push_warning("AudioManager: wave_ended SFX not implemented (V1.0)")


# ==============================================================================
# Signal Handlers -- Board Events
# ==============================================================================


## GDD audio events: 方块放置 / 方块移除 -- SFX, MEDIUM priority.
## Distinguishes placement (EMPTY -> BLOCK) from removal (BLOCK -> EMPTY).
func _on_cell_state_changed(_col: int, _row: int, old_state: int, new_state: int) -> void:
	if new_state == CELL_BLOCK and old_state == CELL_EMPTY:
		push_warning("AudioManager: block_placement SFX not implemented (V1.0)")
	elif new_state == CELL_EMPTY and old_state == CELL_BLOCK:
		push_warning("AudioManager: block_removal SFX not implemented (V1.0)")


# ==============================================================================
# Signal Handlers -- Skill Events
# ==============================================================================


## GDD audio event: 技能激活 -- SFX, MEDIUM priority.
func _on_skill_activated(_skill_id: String) -> void:
	push_warning("AudioManager: skill_activated SFX not implemented (V1.0)")


# ==============================================================================
# Signal Handlers -- Phase / Reset Events
# ==============================================================================


## Handle phase transition.
## V1.0: may trigger phase-specific audio transitions (e.g., BGM switch).
func _on_phase_changed(_old_phase: int, _new_phase: int) -> void:
	# V1.0: phase-specific audio transitions
	# e.g., switch BGM from prep theme to battle theme
	pass


## Handle game reset -- reset audio state per ADR-0008.
## V1.0: stop all active SFX, reset BGM to beginning if playing.
func _on_game_reset() -> void:
	# V1.0: stop all active audio, reset BGM
	push_warning("AudioManager: game_reset -- V1.0 stub (no active audio to stop)")


## GDD audio event: UI 按钮点击 -- SFX, LOW priority.
## Note: Block count changes are often caused by UI-initiated actions.
## This serves as a proxy for block-related UI interaction sounds.
func _on_block_count_changed(_remaining: int) -> void:
	# Low priority -- UI click audio is typically handled directly by the UI layer.
	# This handler exists for V1.0 centralized audio routing if desired.
	pass
