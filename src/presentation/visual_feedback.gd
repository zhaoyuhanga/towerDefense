class_name VisualFeedback
extends Node
## VisualFeedback -- unified manager for all non-UI visual effects.
##
## Implements: design/gdd/visual-feedback.md
## UX Patterns: design/ux/interaction-patterns.md (Patterns 4, 5, 6 feedback side)
## Accessibility: design/accessibility-requirements.md (Section 3.1 silent mode)
## State Reset: docs/architecture/adr-0008-state-reset-protocol.md
##
## Pure signal consumer -- subscribes to all gameplay signals and plays
## corresponding visual effects. Does NOT write to any game system.
##
## Node structure:
##   VisualFeedback (Node)
##     ├── WorldLayer (Node2D)     -- world-space effects (particles, damage numbers)
##     └── ScreenLayer (CanvasLayer) -- screen-space effects (flashes, borders, vignettes)
##
## MVP effects use simple primitives (ColorRect, Label, Tween).
## Complex effects (5-stage merge animation, path redraw) are stubbed for V1.0.
##
## Lifecycle:
##   1. Instantiated by SceneManager, added to main scene
##   2. init() called -- subscribes to SignalBus, creates child layers
##   3. All signal handlers trigger visual effects
##   4. _on_game_reset() -- clears all active effects per ADR-0008
##
## Usage:
##   var vfx := VisualFeedback.new()
##   vfx.init()
##   add_child(vfx)


# ==============================================================================
# Color Constants
# ==============================================================================

const COLOR_DEATH_ORGANIC := Color(0.85, 0.40, 0.15, 1.0)  # Warm orange-brown
const COLOR_DAMAGE_WHITE := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_DAMAGE_GOLD := Color(1.0, 0.85, 0.30, 1.0)
const COLOR_DAMAGE_CYAN := Color(0.30, 0.85, 0.90, 1.0)
const COLOR_BREACH_RED := Color(0.90, 0.15, 0.15, 0.60)
const COLOR_CRISIS_RED := Color(0.95, 0.10, 0.10, 0.50)
const COLOR_SUCCESS_GOLD := Color(1.0, 0.85, 0.30, 1.0)
const COLOR_FAIL_RED := Color(0.95, 0.20, 0.20, 1.0)
const COLOR_BLOCK_PLACEMENT := Color(0.60, 0.65, 0.75, 1.0)

# Damage number constants
const DAMAGE_FLOAT_DURATION: float = 0.8
const DAMAGE_FLOAT_DISTANCE: float = 40.0


# ==============================================================================
# Child Layers
# ==============================================================================

## Node2D child for world-space effects (death particles, damage numbers).
## Positioned in world coordinates relative to the game scene.
var _world_layer: Node2D = null

## CanvasLayer child for screen-space effects (border flashes, vignettes).
## Always renders on top of everything regardless of camera position.
var _screen_layer: CanvasLayer = null

## ColorRect used for screen border flash effects (breach, crisis, wave transition).
var _screen_flash_rect: ColorRect = null

## Vignette ColorRect for wave victory effect.
var _vignette_rect: ColorRect = null


# ==============================================================================
# Public API -- Initialization
# ==============================================================================


## Initialize the visual feedback system.
##
## Creates the WorldLayer (Node2D) and ScreenLayer (CanvasLayer) children.
## Subscribes to all visual-relevant SignalBus signals.
##
## Must be called after adding to the scene tree for world-space effects
## to have correct coordinate transforms.
func init() -> void:
	# Create child layers
	_create_world_layer()
	_create_screen_layer()

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
		if not SignalBus.path_blocked.is_connected(_on_path_blocked):
			SignalBus.path_blocked.connect(_on_path_blocked)
		if not SignalBus.path_updated.is_connected(_on_path_updated):
			SignalBus.path_updated.connect(_on_path_updated)
		if not SignalBus.phase_changed.is_connected(_on_phase_changed):
			SignalBus.phase_changed.connect(_on_phase_changed)
		if not SignalBus.game_reset_requested.is_connected(_on_game_reset):
			SignalBus.game_reset_requested.connect(_on_game_reset)


# ==============================================================================
# Internal -- Layer Creation
# ==============================================================================


## Create the WorldLayer Node2D for world-space visual effects.
## This node should be positioned where the game world is rendered.
## Effects spawned as children of this node inherit world coordinates.
func _create_world_layer() -> void:
	_world_layer = Node2D.new()
	_world_layer.name = "WorldLayer"
	add_child(_world_layer)


## Create the ScreenLayer CanvasLayer for screen-space visual effects.
## Contains a full-screen ColorRect for border flashes and a vignette overlay.
func _create_screen_layer() -> void:
	_screen_layer = CanvasLayer.new()
	_screen_layer.name = "ScreenLayer"
	_screen_layer.layer = 100  # Render above HUD
	add_child(_screen_layer)

	# Full-screen flash rectangle (used for breach, crisis, wave transition)
	_screen_flash_rect = ColorRect.new()
	_screen_flash_rect.name = "ScreenFlash"
	_screen_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_flash_rect.color = Color(0.0, 0.0, 0.0, 0.0)  # Start fully transparent
	_screen_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_layer.add_child(_screen_flash_rect)

	# Vignette overlay (used for wave victory)
	_vignette_rect = ColorRect.new()
	_vignette_rect.name = "Vignette"
	_vignette_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette_rect.color = Color(0.0, 0.0, 0.0, 0.0)  # Start fully transparent
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_layer.add_child(_vignette_rect)


# ==============================================================================
# Signal Handlers -- Monster Events
# ==============================================================================


## Handle monster death: spawn organic particle scatter at death position.
## GDD: 有机碎片飞散 + 暖色微光.
## MVP: creates 6-8 small colored rectangles that scatter outward and fade.
func _on_monster_died(monster_id: String, position: Vector2, _reward_gold: int) -> void:
	_spawn_death_particles(position)


## Handle monster breach: screen red flash + path scar visual.
## GDD: 路径红色伤疤 + UI 边框红闪.
## MVP: flashes the screen border red for 0.3s.
func _on_monster_breached(position: Vector2, _path: Array) -> void:
	_flash_screen_border(COLOR_BREACH_RED, 0.35)
	# Path scar visual is stubbed for V1.0
	# V1.0: add a red trail on the path from position to defense point


# ==============================================================================
# Signal Handlers -- Combat Events
# ==============================================================================


## Handle damage dealt: spawn a floating damage number near the target.
## GDD: 白色/金色/青色弹出 -- color determined by damage_type.
##   "physical" -> white, "critical" -> gold, "magic" / "ice" -> cyan, default -> white.
func _on_damage_dealt(_target_id: String, amount: float, damage_type: String) -> void:
	# Determine color by damage type
	var color: Color = COLOR_DAMAGE_WHITE
	match damage_type:
		"critical":
			color = COLOR_DAMAGE_GOLD
		"magic", "ice", "freeze":
			color = COLOR_DAMAGE_CYAN
		_:
			color = COLOR_DAMAGE_WHITE
	# Damage numbers need world position of the target.
	# Since damage_dealt only carries target_id, we use Vector2.ZERO as placeholder.
	# V1.0: look up target position from TowerSystem/MonsterPool by target_id.
	_spawn_damage_number(Vector2.ZERO, amount, color)


# ==============================================================================
# Signal Handlers -- Merge Events
# ==============================================================================


## Handle merge completed: play 5-stage merge animation at position.
## GDD: 5 stage animation (converge → flash → reveal → star-confirm → settle) ~0.6-0.8s.
## MVP: simplified gold flash at position with scale pulse.
## V1.0: full 5-stage animation with particles, glow, star indicator.
func _on_merge_completed(from_star: int, to_star: int, position: Vector2i) -> void:
	# MVP: simple flash + scale pulse at the merge position
	var world_pos := Vector2(position.x * 56.0 + 28.0, position.y * 56.0 + 28.0)
	_show_merge_success_flash(world_pos, to_star)


## Handle merge failed: visual rejection feedback.
## GDD: 两塔弹回原位 + 光标红色 X.
## MVP: brief red flash on screen border.
## V1.0: tower bounce-back animation + red X cursor sprite.
func _on_merge_failed(_reason: String) -> void:
	_flash_screen_border(COLOR_FAIL_RED, 0.25)
	# V1.0: show red X at cursor position for 0.5s


# ==============================================================================
# Signal Handlers -- Wave Events
# ==============================================================================


## Handle wave started: wave number pulse + UI border color transition.
## GDD: 波次数字跳动 + UI 边框变色过渡.
## MVP: brief gold screen flash.
func _on_wave_started(_wave_number: int) -> void:
	_flash_screen_border(COLOR_SUCCESS_GOLD, 0.3)


## Handle wave ended: victory glow + vignette effect.
## GDD: 路线确认光 + 暗角聚拢.
## MVP: brief screen flash with vignette fade.
func _on_wave_ended(_wave_number: int, _enemies_killed: int, _enemies_breached: int) -> void:
	# Vignette pulse: darken edges briefly then fade out
	if _vignette_rect != null and is_instance_valid(_vignette_rect):
		var tween := create_tween()
		tween.tween_property(_vignette_rect, "color", Color(0.0, 0.0, 0.0, 0.30), 0.3)
		tween.tween_property(_vignette_rect, "color", Color(0.0, 0.0, 0.0, 0.0), 0.7)


# ==============================================================================
# Signal Handlers -- Board Events
# ==============================================================================


## Handle cell state change: block placement fade-in or path update visual.
## GDD: 方块淡入 0.15s.
## MVP: logs the cell state change for block placement.
## V1.0: actual fade-in animation for BLOCK cells.
func _on_cell_state_changed(_col: int, _row: int, _old_state: int, new_state: int) -> void:
	# BLOCK state constant mirrors BoardGrid.CellState.BLOCK (value 3)
	const CELL_BLOCK: int = 3
	if new_state == CELL_BLOCK:
		# V1.0: fade-in block sprite at (col, row) over 0.15s
		pass


# ==============================================================================
# Signal Handlers -- Skill Events
# ==============================================================================


## Handle skill activated: visual feedback for emergency skill use.
## GDD: skill_activated event -- visual dependent on skill type.
## MVP: brief screen flash colored by skill type.
func _on_skill_activated(skill_id: String) -> void:
	match skill_id:
		"freeze":
			_flash_screen_border(Color(0.30, 0.70, 0.95, 0.40), 0.4)  # Ice blue
		"repair":
			_flash_screen_border(Color(0.30, 0.90, 0.40, 0.40), 0.4)  # Heal green
		_:
			_flash_screen_border(COLOR_SUCCESS_GOLD, 0.3)


# ==============================================================================
# Signal Handlers -- Pathfinding Events
# ==============================================================================


## Handle path blocked: visual indication that path is obstructed.
## GDD: 路径更新 -- 路径线重绘.
## MVP: brief red flash to indicate path issue.
## V1.0: redraw path line with blocked indication.
func _on_path_blocked() -> void:
	_flash_screen_border(COLOR_FAIL_RED, 0.2)
	# V1.0: path redraw callback


## Handle path updated: path recalculated successfully.
## GDD: 路径线重绘.
## MVP: no-op (path rendering is handled by GridRenderer).
## V1.0: smooth path line transition animation.
func _on_path_updated(_new_path: Array) -> void:
	# Path line rendering is the GridRenderer's responsibility.
	# This hook exists for future path-change animations (V1.0).
	pass


# ==============================================================================
# Signal Handlers -- Phase / Reset Events
# ==============================================================================


## Handle phase transition: clear any active effects that shouldn't persist
## across phase boundaries.
func _on_phase_changed(_old_phase: int, _new_phase: int) -> void:
	# Clear any lingering screen effects
	if _screen_flash_rect != null and is_instance_valid(_screen_flash_rect):
		_screen_flash_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	if _vignette_rect != null and is_instance_valid(_vignette_rect):
		_vignette_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	# Clear world-layer children (particles, damage numbers)
	if _world_layer != null and is_instance_valid(_world_layer):
		for child in _world_layer.get_children():
			if is_instance_valid(child):
				child.queue_free()


## Handle game reset: clear all active effects per ADR-0008.
func _on_game_reset() -> void:
	# Clear screen effects
	if _screen_flash_rect != null and is_instance_valid(_screen_flash_rect):
		_screen_flash_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	if _vignette_rect != null and is_instance_valid(_vignette_rect):
		_vignette_rect.color = Color(0.0, 0.0, 0.0, 0.0)

	# Clear all world-layer effects
	if _world_layer != null and is_instance_valid(_world_layer):
		for child in _world_layer.get_children():
			if is_instance_valid(child):
				child.queue_free()


# ==============================================================================
# Internal -- Screen-Space Effects
# ==============================================================================


## Flash the screen with a color overlay, fading out over duration seconds.
## Uses the _screen_flash_rect ColorRect. If a flash is already in progress,
## the new flash replaces it (old tween is killed by create_tween).
func _flash_screen_border(color: Color, duration: float) -> void:
	if _screen_flash_rect == null or not is_instance_valid(_screen_flash_rect):
		return
	# Kill any existing flash tween
	if _screen_flash_rect.has_meta("_flash_tween"):
		var old_tween: Tween = _screen_flash_rect.get_meta("_flash_tween")
		if is_instance_valid(old_tween):
			old_tween.kill()

	_screen_flash_rect.color = color
	var tween := create_tween()
	tween.tween_property(_screen_flash_rect, "color", Color(color.r, color.g, color.b, 0.0), duration)
	_screen_flash_rect.set_meta("_flash_tween", tween)


# ==============================================================================
# Internal -- World-Space Effects
# ==============================================================================


## Spawn a floating damage number at a world position.
## Creates a temporary Label that floats upward and fades out.
func _spawn_damage_number(position: Vector2, amount: float, color: Color) -> void:
	if _world_layer == null or not is_instance_valid(_world_layer):
		return

	var label := Label.new()
	label.name = "DamageNumber"
	label.text = str(int(amount))
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	label.add_theme_constant_override("outline_size", 2)
	label.position = position
	label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	label.z_index = 200  # Render above towers and monsters
	_world_layer.add_child(label)

	# Animate: float upward + fade out
	var tween := create_tween()
	tween.set_parallel(true)
	var target_pos := position + Vector2(0.0, -DAMAGE_FLOAT_DISTANCE)
	tween.tween_property(label, "position", target_pos, DAMAGE_FLOAT_DURATION).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, DAMAGE_FLOAT_DURATION)
	tween.tween_property(label, "scale", Vector2(1.3, 1.3), DAMAGE_FLOAT_DURATION * 0.3)
	tween.chain().tween_property(label, "scale", Vector2(1.0, 1.0), DAMAGE_FLOAT_DURATION * 0.7)

	# Free the label after animation completes
	tween.finished.connect(_cleanup_node.bind(label))


## Spawn death particles at a world position.
## MVP: creates 6-8 small colored rectangles that scatter outward and fade.
## V1.0: replace with proper particle system (GPUParticles2D or CPUParticles2D).
func _spawn_death_particles(position: Vector2) -> void:
	if _world_layer == null or not is_instance_valid(_world_layer):
		return

	const PARTICLE_COUNT: int = 7
	const SCATTER_RADIUS: float = 30.0
	const PARTICLE_SIZE: float = 5.0
	const PARTICLE_DURATION: float = 0.5

	for i in range(PARTICLE_COUNT):
		var particle := ColorRect.new()
		particle.name = "DeathParticle_%d" % i
		particle.size = Vector2(PARTICLE_SIZE, PARTICLE_SIZE)
		particle.color = COLOR_DEATH_ORGANIC
		particle.position = position - Vector2(PARTICLE_SIZE / 2.0, PARTICLE_SIZE / 2.0)
		particle.z_index = 150
		_world_layer.add_child(particle)

		# Random scatter direction
		var angle: float = randf() * TAU
		var distance: float = randf_range(SCATTER_RADIUS * 0.5, SCATTER_RADIUS)
		var target_pos := position + Vector2(cos(angle), sin(angle)) * distance

		# Animate: scatter + fade + shrink
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(particle, "position", target_pos - Vector2(PARTICLE_SIZE / 2.0, PARTICLE_SIZE / 2.0), PARTICLE_DURATION).set_ease(Tween.EASE_OUT)
		tween.tween_property(particle, "modulate:a", 0.0, PARTICLE_DURATION)
		tween.tween_property(particle, "scale", Vector2(0.2, 0.2), PARTICLE_DURATION)
		tween.finished.connect(_cleanup_node.bind(particle))


## Show a simplified merge success flash at a world position.
## MVP: brief gold flash circle at the merge position.
## V1.0: full 5-stage merge animation (converge -> flash -> reveal -> star-confirm -> settle).
func _show_merge_success_flash(position: Vector2, _to_star: int) -> void:
	if _world_layer == null or not is_instance_valid(_world_layer):
		return

	var flash := ColorRect.new()
	flash.name = "MergeFlash"
	flash.size = Vector2(56.0, 56.0)  # Cell-sized
	flash.position = position - Vector2(28.0, 28.0)
	flash.color = COLOR_SUCCESS_GOLD
	flash.modulate = Color(1.0, 1.0, 1.0, 0.8)
	flash.z_index = 250
	_world_layer.add_child(flash)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "modulate:a", 0.0, 0.6)
	tween.tween_property(flash, "scale", Vector2(1.5, 1.5), 0.6)
	tween.finished.connect(_cleanup_node.bind(flash))


# ==============================================================================
# Internal -- Helpers
# ==============================================================================


## Cleanup callback for tween.finished -- frees the temporary node.
func _cleanup_node(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
