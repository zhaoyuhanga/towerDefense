class_name HUD
extends CanvasLayer
## HUD -- Heads-Up Display system managing all on-screen UI elements.
##
## Implements: design/gdd/hud-ui.md
## UX Patterns: design/ux/interaction-patterns.md (Pattern 7: Button Click)
## Accessibility: design/accessibility-requirements.md
## State Reset: docs/architecture/adr-0008-state-reset-protocol.md
##
## The HUD is a pure signal consumer -- it subscribes to SignalBus signals
## and updates its display elements accordingly. It does NOT write to any
## game system. Button clicks invoke injected Callables, which are wired
## by the scene manager to the appropriate game systems.
##
## All UI is created programmatically (no .tscn). Two main bars:
##   - Top bar (48px): wave count, gold, defense HP bar, menu button
##   - Bottom bar (64px): tower selection buttons, block button, skill buttons, start wave
##
## Phase-gated visibility: tower/block buttons visible in PREP only.
## Skill buttons visible in BATTLE only. Start button visible in PREP only.
##
## Lifecycle:
##   1. Instantiated by SceneManager, added as scene child
##   2. init(deps) called -- injects callbacks, subscribes to SignalBus
##   3. _process() polls EmergencySkills for cooldown label updates
##   4. _on_game_reset() -- resets all UI state per ADR-0008
##
## Usage:
##   var hud := HUD.new()
##   hud.init({
##       "callbacks": {
##           "on_start_wave": func(): pm.start_wave(),
##           "on_select_tower": func(id: String): input.select_tower(id),
##           "on_activate_skill": func(id: String): skills.activate_skill(id),
##           "on_place_block": func(): input.enter_block_placement(),
##       },
##       "tower_configs": [cannon_data, ice_data, arrow_data],
##       "skill_configs": [freeze_config, repair_config],
##       "emergency_skills": emergency_skills_ref,
##   })
##   add_child(hud)


# ==============================================================================
# Phase Constants (mirror PhaseManager.Phase enum -- ADR-0006)
# ==============================================================================

const PHASE_PREP: int = 0
const PHASE_BATTLE: int = 1
const PHASE_PAUSED: int = 2


# ==============================================================================
# Layout Constants
# ==============================================================================

const TOP_BAR_HEIGHT: int = 48
const BOTTOM_BAR_HEIGHT: int = 64
const BUTTON_MIN_WIDTH: int = 56
const BUTTON_MIN_HEIGHT: int = 44
const LABEL_MIN_HEIGHT: int = 24

# Color palette (Art Bible Section 7 -- extended 7-color palette, geometric)
const COLOR_PANEL_BG := Color(0.10, 0.12, 0.18, 0.90)
const COLOR_TEXT := Color(0.92, 0.92, 0.92, 1.0)
const COLOR_GOLD := Color(1.0, 0.85, 0.30, 1.0)
const COLOR_DEFENSE_GREEN := Color(0.30, 0.88, 0.30, 1.0)
const COLOR_DEFENSE_RED := Color(0.90, 0.22, 0.22, 1.0)
const COLOR_DEFENSE_YELLOW := Color(1.0, 0.76, 0.15, 1.0)
const COLOR_SELECTED_BORDER := Color(1.0, 0.85, 0.30, 1.0)
const COLOR_BUTTON_NORMAL := Color(0.18, 0.22, 0.32, 1.0)
const COLOR_BUTTON_HOVER := Color(0.25, 0.30, 0.42, 1.0)
const COLOR_BUTTON_PRESSED := Color(0.14, 0.16, 0.24, 1.0)
const COLOR_BUTTON_DISABLED := Color(0.25, 0.25, 0.25, 0.55)
const COLOR_CRISIS_FLASH := Color(0.90, 0.15, 0.15, 0.70)

# Text sizes (accessibility: core HUD >= 16px, button labels >= 14px)
const FONT_SIZE_HUD_CORE: int = 18
const FONT_SIZE_BUTTON: int = 14
const FONT_SIZE_SMALL: int = 12


# ==============================================================================
# Injected Dependencies
# ==============================================================================

## Callback dictionary for button actions. Keys:
##   "on_start_wave": Callable
##   "on_select_tower": Callable(String tower_id)
##   "on_activate_skill": Callable(String skill_id)
##   "on_place_block": Callable
##   "on_menu": Callable (optional -- V1.0)
var _callbacks: Dictionary = {}

## EmergencySkills reference for polling cooldown state in _process().
## Set via init(). May be null if EmergencySkills is not yet initialized.
var _emergency_skills: EmergencySkills = null

## TowerData array for tower button labels and icons.
## Each entry provides tower_id and display_name.
var _tower_configs: Array[TowerData] = []

## SkillConfig array for skill button labels and icons.
## Each entry provides skill_id and display_name.
var _skill_configs: Array[SkillConfig] = []


# ==============================================================================
# Cached State (from SignalBus subscriptions)
# ==============================================================================

## Current game phase. Updated via SignalBus.phase_changed.
## Used to gate button visibility: PREP=tower/block/start, BATTLE=skills.
var _current_phase: int = PHASE_PREP

## Current gold balance. Updated via SignalBus.gold_changed.
var _current_gold: int = 0

## Current wave number. Updated via SignalBus.wave_started.
var _current_wave: int = 0

## Current defense HP percentage (0.0 to 1.0). Updated manually via
## update_defense_hp() called by the defense system.
var _defense_hp_ratio: float = 1.0

## Currently selected tower_id for placement. Updated when tower button is clicked.
var _selected_tower_id: String = ""


# ==============================================================================
# Top Bar Nodes
# ==============================================================================

var _top_bar: Panel = null
var _wave_label: Label = null
var _gold_label: Label = null
var _defense_bar: ProgressBar = null
var _defense_label: Label = null
var _menu_button: Button = null


# ==============================================================================
# Bottom Bar Nodes
# ==============================================================================

var _bottom_bar: Panel = null
var _tower_buttons: Dictionary = {}   ## tower_id -> Button
var _block_button: Button = null
var _block_count_label: Label = null
var _skill_buttons: Dictionary = {}   ## skill_id -> Dictionary { "button": Button, "uses_label": Label, "cd_label": Label }
var _start_button: Button = null


# ==============================================================================
# Public API -- Initialization
# ==============================================================================


## Initialize the HUD with injected dependencies and callbacks.
##
## deps is a Dictionary with optional keys:
##   "callbacks": Dictionary of Callables for button actions (see _callbacks docs)
##   "tower_configs": Array[TowerData] for tower button labels
##   "skill_configs": Array[SkillConfig] for skill button labels
##   "emergency_skills": EmergencySkills reference for cooldown polling
##
## Subscribes to SignalBus for: gold_changed, phase_changed, wave_started,
## block_count_changed, skill_activated, game_reset_requested.
##
## Creates all UI elements programmatically.
##
## Usage:
##   hud.init({
##       "callbacks": { "on_start_wave": start_callable, ... },
##       "tower_configs": [cannon, ice, arrow],
##       "skill_configs": [freeze, repair],
##       "emergency_skills": skills_ref,
##   })
func init(deps: Dictionary) -> void:
	# Store injected dependencies
	if deps.has("callbacks") and deps["callbacks"] is Dictionary:
		_callbacks = deps["callbacks"]
	if deps.has("tower_configs") and deps["tower_configs"] is Array:
		_tower_configs = deps["tower_configs"]
	if deps.has("skill_configs") and deps["skill_configs"] is Array:
		_skill_configs = deps["skill_configs"]
	if deps.has("emergency_skills") and deps["emergency_skills"] is EmergencySkills:
		_emergency_skills = deps["emergency_skills"]

	# Create UI structure
	_create_top_bar()
	_create_bottom_bar()

	# Subscribe to SignalBus events (has_node guard for test safety)
	if has_node("/root/SignalBus"):
		if not SignalBus.gold_changed.is_connected(_on_gold_changed):
			SignalBus.gold_changed.connect(_on_gold_changed)
		if not SignalBus.phase_changed.is_connected(_on_phase_changed):
			SignalBus.phase_changed.connect(_on_phase_changed)
		if not SignalBus.wave_started.is_connected(_on_wave_started):
			SignalBus.wave_started.connect(_on_wave_started)
		if not SignalBus.block_count_changed.is_connected(_on_block_count_changed):
			SignalBus.block_count_changed.connect(_on_block_count_changed)
		if not SignalBus.skill_activated.is_connected(_on_skill_activated):
			SignalBus.skill_activated.connect(_on_skill_activated)
		if not SignalBus.game_reset_requested.is_connected(_on_game_reset):
			SignalBus.game_reset_requested.connect(_on_game_reset)

	# Refresh all displays from initial state
	_refresh_phase_visibility()
	_update_gold_display(0)


# ==============================================================================
# Public API -- Manual Updates
# ==============================================================================


## Update the defense HP bar display.
## Called by the defense line system when HP changes.
##
## ratio: float between 0.0 (dead) and 1.0 (full HP).
func update_defense_hp(ratio: float) -> void:
	_defense_hp_ratio = clampf(ratio, 0.0, 1.0)
	if _defense_bar != null and is_instance_valid(_defense_bar):
		_defense_bar.value = _defense_hp_ratio * 100.0
		# Color: green > 60%, yellow 30-60%, red < 30% (crisis threshold)
		if _defense_hp_ratio > 0.6:
			_defense_bar.modulate = COLOR_DEFENSE_GREEN
		elif _defense_hp_ratio > 0.3:
			_defense_bar.modulate = COLOR_DEFENSE_YELLOW
		else:
			_defense_bar.modulate = COLOR_DEFENSE_RED
	if _defense_label != null and is_instance_valid(_defense_label):
		_defense_label.text = "%d%%" % int(_defense_hp_ratio * 100)


## Update the wave number display.
## Can be called directly for initial state before first wave_started signal.
func set_wave_number(wave: int) -> void:
	_current_wave = wave
	if _wave_label != null and is_instance_valid(_wave_label):
		_wave_label.text = "波次 %d" % wave


# ==============================================================================
# Public API -- Selection
# ==============================================================================


## Programmatically select a tower button (e.g., when InputHandler changes
## the selected tower via keyboard shortcut -- V1.0).
##
## Updates the visual state of tower buttons: selected gets gold border,
## all others revert to normal.
func set_selected_tower(tower_id: String) -> void:
	_selected_tower_id = tower_id
	for tid: String in _tower_buttons:
		var btn: Button = _tower_buttons[tid]
		if not is_instance_valid(btn):
			continue
		if tid == tower_id:
			_set_button_selected_style(btn, true)
		else:
			_set_button_selected_style(btn, false)


# ==============================================================================
# Per-Frame Update
# ==============================================================================


## Update cooldown labels on skill buttons each frame.
## Polls EmergencySkills for cooldown state. Only runs during BATTLE phase
## when skill buttons are visible.
func _process(_delta: float) -> void:
	if _current_phase != PHASE_BATTLE:
		return
	if _emergency_skills == null or not is_instance_valid(_emergency_skills):
		return
	for skill_id: String in _skill_buttons:
		var cd_remaining: float = _emergency_skills.get_cooldown_remaining(skill_id)
		var uses: int = _emergency_skills.get_remaining_uses(skill_id)
		var can_act: bool = _emergency_skills.can_activate(skill_id)
		_update_skill_button_state(skill_id, uses, cd_remaining, can_act)


# ==============================================================================
# Internal -- UI Creation: Top Bar
# ==============================================================================


## Create the top bar with wave count, gold, defense HP bar, and menu button.
## Anchored to the top of the screen, 48px height.
func _create_top_bar() -> void:
	_top_bar = Panel.new()
	_top_bar.name = "TopBar"
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.custom_minimum_size = Vector2(0, TOP_BAR_HEIGHT)
	_top_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Apply background style
	var top_bg := StyleBoxFlat.new()
	top_bg.bg_color = COLOR_PANEL_BG
	top_bg.border_width_bottom = 2
	top_bg.border_color = Color(0.25, 0.28, 0.38, 1.0)
	_top_bar.add_theme_stylebox_override("panel", top_bg)
	add_child(_top_bar)

	# HBoxContainer for horizontal layout
	var hbox := HBoxContainer.new()
	hbox.name = "TopBarHBox"
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 16)
	_top_bar.add_child(hbox)

	# Spacer left
	var spacer_left := Control.new()
	spacer_left.custom_minimum_size = Vector2(12, 0)
	hbox.add_child(spacer_left)

	# Wave label
	_wave_label = _create_hud_label("波次 0")
	_wave_label.name = "WaveLabel"
	hbox.add_child(_wave_label)

	# Separator
	hbox.add_child(_create_separator())

	# Gold label
	_gold_label = _create_hud_label("金币 0")
	_gold_label.name = "GoldLabel"
	_gold_label.add_theme_color_override("font_color", COLOR_GOLD)
	hbox.add_child(_gold_label)

	# Separator
	hbox.add_child(_create_separator())

	# Defense HP container (label + progress bar)
	var defense_container := HBoxContainer.new()
	defense_container.name = "DefenseContainer"
	defense_container.add_theme_constant_override("separation", 8)
	hbox.add_child(defense_container)

	_defense_label = _create_hud_label("100%")
	_defense_label.name = "DefenseLabel"
	defense_container.add_child(_defense_label)

	_defense_bar = ProgressBar.new()
	_defense_bar.name = "DefenseBar"
	_defense_bar.custom_minimum_size = Vector2(120, 20)
	_defense_bar.min_value = 0.0
	_defense_bar.max_value = 100.0
	_defense_bar.value = 100.0
	_defense_bar.show_percentage = false
	_defense_bar.modulate = COLOR_DEFENSE_GREEN
	defense_container.add_child(_defense_bar)

	# Expanding spacer (pushes menu button to right)
	var spacer_mid := Control.new()
	spacer_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer_mid)

	# Menu button (right-aligned)
	_menu_button = _create_text_button("≡", "MenuButton")
	_menu_button.custom_minimum_size = Vector2(44, 36)
	hbox.add_child(_menu_button)
	_menu_button.pressed.connect(_on_menu_pressed)

	# Spacer right
	var spacer_right := Control.new()
	spacer_right.custom_minimum_size = Vector2(12, 0)
	hbox.add_child(spacer_right)


# ==============================================================================
# Internal -- UI Creation: Bottom Bar
# ==============================================================================


## Create the bottom bar with tower buttons, block button, skill buttons,
## and start wave button. Anchored to the bottom of the screen, 64px height.
func _create_bottom_bar() -> void:
	_bottom_bar = Panel.new()
	_bottom_bar.name = "BottomBar"
	_bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom_bar.custom_minimum_size = Vector2(0, BOTTOM_BAR_HEIGHT)
	_bottom_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bot_bg := StyleBoxFlat.new()
	bot_bg.bg_color = COLOR_PANEL_BG
	bot_bg.border_width_top = 2
	bot_bg.border_color = Color(0.25, 0.28, 0.38, 1.0)
	_bottom_bar.add_theme_stylebox_override("panel", bot_bg)
	add_child(_bottom_bar)

	# HBoxContainer for horizontal layout
	var hbox := HBoxContainer.new()
	hbox.name = "BottomBarHBox"
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 10)
	_bottom_bar.add_child(hbox)

	# Spacer left
	var spacer_left := Control.new()
	spacer_left.custom_minimum_size = Vector2(12, 0)
	hbox.add_child(spacer_left)

	# Tower selection buttons
	_create_tower_buttons(hbox)

	# Separator
	hbox.add_child(_create_separator())

	# Block button with count label
	_create_block_button(hbox)

	# Separator
	hbox.add_child(_create_separator())

	# Skill buttons
	_create_skill_buttons(hbox)

	# Expanding spacer (pushes start button to right)
	var spacer_mid := Control.new()
	spacer_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer_mid)

	# Start wave button
	_start_button = _create_text_button("开始", "StartButton")
	_start_button.custom_minimum_size = Vector2(80, 44)
	# Highlight start button with a slightly different color
	var start_bg := StyleBoxFlat.new()
	start_bg.bg_color = Color(0.18, 0.45, 0.18, 1.0)
	start_bg.border_width_left = 2
	start_bg.border_width_right = 2
	start_bg.border_width_top = 2
	start_bg.border_width_bottom = 2
	start_bg.border_color = Color(0.25, 0.65, 0.25, 1.0)
	start_bg.corner_radius_top_left = 4
	start_bg.corner_radius_top_right = 4
	start_bg.corner_radius_bottom_left = 4
	start_bg.corner_radius_bottom_right = 4
	_start_button.add_theme_stylebox_override("normal", start_bg)
	_start_button.pressed.connect(_on_start_wave_pressed)
	hbox.add_child(_start_button)

	# Spacer right
	var spacer_right := Control.new()
	spacer_right.custom_minimum_size = Vector2(12, 0)
	hbox.add_child(spacer_right)


# ==============================================================================
# Internal -- Tower Buttons
# ==============================================================================


## Create tower selection buttons from tower_configs.
## Each button displays the tower's display_name and is mutually exclusive
## (radio-like behavior -- clicking one deselects others).
func _create_tower_buttons(parent: HBoxContainer) -> void:
	for config: TowerData in _tower_configs:
		if config == null or config.tower_id.is_empty():
			continue
		var btn := _create_text_button(config.tower_name, "TowerBtn_%s" % config.tower_id)
		btn.custom_minimum_size = Vector2(BUTTON_MIN_WIDTH, BUTTON_MIN_HEIGHT)
		btn.tooltip_text = config.description if not config.description.is_empty() else config.tower_name
		var tid: String = config.tower_id
		btn.pressed.connect(_on_tower_button_pressed.bind(tid))
		_tower_buttons[tid] = btn
		parent.add_child(btn)


# ==============================================================================
# Internal -- Block Button
# ==============================================================================


## Create the block placement button with remaining count label.
func _create_block_button(parent: HBoxContainer) -> void:
	var container := HBoxContainer.new()
	container.name = "BlockContainer"
	container.add_theme_constant_override("separation", 4)
	parent.add_child(container)

	_block_button = _create_text_button("方块", "BlockButton")
	_block_button.custom_minimum_size = Vector2(BUTTON_MIN_WIDTH, BUTTON_MIN_HEIGHT)
	_block_button.tooltip_text = "Place obstacle block"
	_block_button.pressed.connect(_on_block_button_pressed)
	container.add_child(_block_button)

	_block_count_label = _create_hud_label("10")
	_block_count_label.name = "BlockCountLabel"
	_block_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	container.add_child(_block_count_label)


# ==============================================================================
# Internal -- Skill Buttons
# ==============================================================================


## Create skill buttons from skill_configs.
## Each skill button shows: icon/name, uses remaining, and cooldown timer.
func _create_skill_buttons(parent: HBoxContainer) -> void:
	for config: SkillConfig in _skill_configs:
		if config == null or config.skill_id.is_empty():
			continue

		var container := VBoxContainer.new()
		container.name = "SkillContainer_%s" % config.skill_id
		container.add_theme_constant_override("separation", 2)
		parent.add_child(container)

		# Skill button (top)
		var btn := _create_text_button(config.skill_name, "SkillBtn_%s" % config.skill_id)
		btn.custom_minimum_size = Vector2(BUTTON_MIN_WIDTH, 32)
		btn.tooltip_text = config.skill_name
		var sid: String = config.skill_id
		btn.pressed.connect(_on_skill_button_pressed.bind(sid))
		container.add_child(btn)

		# Info row (uses + cooldown)
		var info_row := HBoxContainer.new()
		info_row.name = "SkillInfo_%s" % sid
		info_row.add_theme_constant_override("separation", 4)
		container.add_child(info_row)

		var uses_label := Label.new()
		uses_label.name = "UsesLabel_%s" % sid
		uses_label.text = "%d/%d" % [config.max_uses, config.max_uses]
		uses_label.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
		uses_label.add_theme_color_override("font_color", COLOR_TEXT)
		uses_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info_row.add_child(uses_label)

		var cd_label := Label.new()
		cd_label.name = "CdLabel_%s" % sid
		cd_label.text = ""
		cd_label.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
		cd_label.add_theme_color_override("font_color", COLOR_GOLD)
		cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info_row.add_child(cd_label)

		_skill_buttons[sid] = {
			"button": btn,
			"uses_label": uses_label,
			"cd_label": cd_label,
		}


# ==============================================================================
# Internal -- UI Helpers
# ==============================================================================


## Create a standard HUD label with core text styling.
func _create_hud_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE_HUD_CORE)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## Create a vertical separator line between HUD sections.
func _create_separator() -> ColorRect:
	var sep := ColorRect.new()
	sep.name = "Separator"
	sep.custom_minimum_size = Vector2(2, 0)
	sep.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sep.color = Color(0.25, 0.28, 0.38, 0.5)
	return sep


## Create a styled text button with hover/pressed visual states.
func _create_text_button(text: String, node_name: String) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = text
	btn.add_theme_font_size_override("font_size", FONT_SIZE_BUTTON)
	btn.add_theme_color_override("font_color", COLOR_TEXT)

	# Normal style
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = COLOR_BUTTON_NORMAL
	normal_style.border_width_left = 2
	normal_style.border_width_right = 2
	normal_style.border_width_top = 2
	normal_style.border_width_bottom = 2
	normal_style.border_color = Color(0.30, 0.34, 0.45, 1.0)
	normal_style.corner_radius_top_left = 3
	normal_style.corner_radius_top_right = 3
	normal_style.corner_radius_bottom_left = 3
	normal_style.corner_radius_bottom_right = 3
	btn.add_theme_stylebox_override("normal", normal_style)

	# Hover style
	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = COLOR_BUTTON_HOVER
	hover_style.border_color = Color(0.45, 0.50, 0.62, 1.0)
	btn.add_theme_stylebox_override("hover", hover_style)

	# Pressed style
	var pressed_style := normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = COLOR_BUTTON_PRESSED
	btn.add_theme_stylebox_override("pressed", pressed_style)

	# Disabled style
	var disabled_style := normal_style.duplicate() as StyleBoxFlat
	disabled_style.bg_color = COLOR_BUTTON_DISABLED
	btn.add_theme_stylebox_override("disabled", disabled_style)

	return btn


## Apply or remove selected visual style from a button.
## Selected: gold border + slightly brighter background.
## Not selected: revert to normal border color.
func _set_button_selected_style(btn: Button, selected: bool) -> void:
	if not is_instance_valid(btn):
		return

	var normal_style: StyleBoxFlat = btn.get_theme_stylebox("normal")
	if normal_style == null:
		normal_style = StyleBoxFlat.new()
		normal_style.bg_color = COLOR_BUTTON_NORMAL

	if selected:
		normal_style.border_color = COLOR_SELECTED_BORDER
		normal_style.bg_color = Color(0.25, 0.28, 0.38, 1.0)
	else:
		normal_style.border_color = Color(0.30, 0.34, 0.45, 1.0)
		normal_style.bg_color = COLOR_BUTTON_NORMAL

	btn.add_theme_stylebox_override("normal", normal_style)


# ==============================================================================
# Internal -- Display Updates
# ==============================================================================


## Refresh the phase-based visibility of all buttons.
## PREP: tower buttons, block button, start button visible; skill buttons hidden.
## BATTLE: skill buttons visible; tower/block/start hidden.
func _refresh_phase_visibility() -> void:
	var in_prep: bool = (_current_phase == PHASE_PREP)

	# Tower buttons -- visible only in PREP
	for btn: Button in _tower_buttons.values():
		if is_instance_valid(btn):
			btn.visible = in_prep

	# Block button + count -- visible only in PREP
	if _block_button != null and is_instance_valid(_block_button):
		_block_button.visible = in_prep
	if _block_count_label != null and is_instance_valid(_block_count_label):
		_block_count_label.visible = in_prep

	# Start button -- visible only in PREP
	if _start_button != null and is_instance_valid(_start_button):
		_start_button.visible = in_prep

	# Skill buttons -- visible only in BATTLE
	for skill_entry: Dictionary in _skill_buttons.values():
		var btn: Button = skill_entry.get("button", null)
		if btn != null and is_instance_valid(btn):
			var parent: VBoxContainer = btn.get_parent() as VBoxContainer
			if parent != null and is_instance_valid(parent):
				parent.visible = not in_prep


## Update the gold display label.
func _update_gold_display(amount: int) -> void:
	if _gold_label != null and is_instance_valid(_gold_label):
		_gold_label.text = "金币 %d" % amount


## Update a single skill button's visual state (uses, cooldown, enabled/disabled).
func _update_skill_button_state(skill_id: String, uses: int, cd_remaining: float, can_act: bool) -> void:
	var entry: Dictionary = _skill_buttons.get(skill_id, {})
	if entry.is_empty():
		return

	var btn: Button = entry.get("button", null)
	var uses_label: Label = entry.get("uses_label", null)
	var cd_label: Label = entry.get("cd_label", null)

	# Button enabled/disabled
	if btn != null and is_instance_valid(btn):
		btn.disabled = not can_act

	# Uses remaining label
	if uses_label != null and is_instance_valid(uses_label):
		var max_uses: int = 0
		if _emergency_skills != null and is_instance_valid(_emergency_skills):
			max_uses = _emergency_skills.get_max_uses(skill_id)
		uses_label.text = "%d/%d" % [uses, max_uses]
		if uses <= 0:
			uses_label.add_theme_color_override("font_color", COLOR_DEFENSE_RED)
		else:
			uses_label.add_theme_color_override("font_color", COLOR_TEXT)

	# Cooldown label
	if cd_label != null and is_instance_valid(cd_label):
		if cd_remaining > 0.0:
			cd_label.text = "%.1fs" % cd_remaining
			cd_label.visible = true
		else:
			cd_label.text = ""
			cd_label.visible = false


# ==============================================================================
# Signal Handlers
# ==============================================================================


## React to gold changes from SignalBus.gold_changed.
func _on_gold_changed(current_gold: int) -> void:
	_current_gold = current_gold
	_update_gold_display(current_gold)


## React to phase transitions from SignalBus.phase_changed.
## Refreshes button visibility and clears tower selection on phase change.
func _on_phase_changed(_old_phase: int, new_phase: int) -> void:
	_current_phase = new_phase
	set_selected_tower("")  # Clear selection
	_refresh_phase_visibility()


## React to wave started from SignalBus.wave_started.
func _on_wave_started(wave_number: int) -> void:
	set_wave_number(wave_number)


## React to block count changes from SignalBus.block_count_changed.
func _on_block_count_changed(remaining: int) -> void:
	if _block_count_label != null and is_instance_valid(_block_count_label):
		_block_count_label.text = str(remaining)
	if _block_button != null and is_instance_valid(_block_button):
		_block_button.disabled = (remaining <= 0)


## React to skill activation from SignalBus.skill_activated.
## Immediately updates the skill button display (uses decremented, cooldown started).
func _on_skill_activated(skill_id: String) -> void:
	if _emergency_skills == null or not is_instance_valid(_emergency_skills):
		return
	var uses: int = _emergency_skills.get_remaining_uses(skill_id)
	var cd: float = _emergency_skills.get_cooldown_remaining(skill_id)
	var can_act: bool = _emergency_skills.can_activate(skill_id)
	_update_skill_button_state(skill_id, uses, cd, can_act)


## Handle game reset -- restore all UI to initial state.
## ADR-0008: reset local caches and refresh all displays.
func _on_game_reset() -> void:
	_current_phase = PHASE_PREP
	_current_wave = 0
	_current_gold = 0
	_defense_hp_ratio = 1.0
	_selected_tower_id = ""

	# Reset labels
	if _wave_label != null and is_instance_valid(_wave_label):
		_wave_label.text = "波次 0"
	if _gold_label != null and is_instance_valid(_gold_label):
		_gold_label.text = "金币 0"
	if _defense_bar != null and is_instance_valid(_defense_bar):
		_defense_bar.value = 100.0
		_defense_bar.modulate = COLOR_DEFENSE_GREEN
	if _defense_label != null and is_instance_valid(_defense_label):
		_defense_label.text = "100%"
	if _block_count_label != null and is_instance_valid(_block_count_label):
		_block_count_label.text = "10"

	# Reset tower selection
	set_selected_tower("")

	# Reset skill button labels
	for sid: String in _skill_buttons:
		var entry: Dictionary = _skill_buttons[sid]
		var btn: Button = entry.get("button", null)
		var uses_label: Label = entry.get("uses_label", null)
		var cd_label: Label = entry.get("cd_label", null)
		if btn != null and is_instance_valid(btn):
			btn.disabled = true
		if uses_label != null and is_instance_valid(uses_label):
			uses_label.text = "?/?"
			uses_label.add_theme_color_override("font_color", COLOR_TEXT)
		if cd_label != null and is_instance_valid(cd_label):
			cd_label.text = ""
			cd_label.visible = false

	# Refresh phase visibility
	_refresh_phase_visibility()


# ==============================================================================
# Button Click Handlers
# ==============================================================================


## Handle tower selection button click.
## Invokes the injected "on_select_tower" callback with the tower_id.
## Updates local selection state and button visuals.
func _on_tower_button_pressed(tower_id: String) -> void:
	# Toggle: clicking selected tower deselects it
	var new_selection: String = "" if _selected_tower_id == tower_id else tower_id
	set_selected_tower(new_selection)

	if _callbacks.has("on_select_tower"):
		var cb: Callable = _callbacks["on_select_tower"]
		cb.call(new_selection)


## Handle skill button click.
## Invokes the injected "on_activate_skill" callback with the skill_id.
func _on_skill_button_pressed(skill_id: String) -> void:
	if _callbacks.has("on_activate_skill"):
		var cb: Callable = _callbacks["on_activate_skill"]
		cb.call(skill_id)


## Handle block button click.
## Invokes the injected "on_place_block" callback.
func _on_block_button_pressed() -> void:
	if _callbacks.has("on_place_block"):
		var cb: Callable = _callbacks["on_place_block"]
		cb.call()


## Handle start wave button click.
## Invokes the injected "on_start_wave" callback.
func _on_start_wave_pressed() -> void:
	if _callbacks.has("on_start_wave"):
		var cb: Callable = _callbacks["on_start_wave"]
		cb.call()


## Handle menu button click (V1.0 -- pause/menu overlay).
## Invokes the injected "on_menu" callback if available.
func _on_menu_pressed() -> void:
	if _callbacks.has("on_menu"):
		var cb: Callable = _callbacks["on_menu"]
		cb.call()
