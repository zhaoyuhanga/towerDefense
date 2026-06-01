class_name InputHandler
extends Node
## InputHandler — Mouse input router with drag state machine.
##
## Foundation layer. Translates raw [InputEvent] to semantic game actions
## and routes them to target systems via signals. Phase-gated so that
## PREP allows full board interaction while BATTLE only permits UI buttons.
##
## Routing priority chain: UI > TOWER > BLOCK > EMPTY > Void
## Drag threshold: 3.0 px — movement below this threshold is a click.
##
## Usage:
##   [codeblock]
##   # In LevelScene:
##   var input_handler := InputHandler.new()
##   input_handler.set_board_grid($BoardGrid)
##   add_child(input_handler)
##   input_handler.grid_clicked.connect(tower_system._on_grid_clicked)
##   input_handler.drag_ended.connect(merge_system._on_drag_ended)
##   [/codeblock]
##
## Dependencies:
##   - BoardGrid (soft) — world_to_grid() for coordinate conversion
##   - SignalBus (soft) — phase_changed signal for phase caching
##
## @tutorial: design/gdd/input-handling.md
## @tutorial: docs/architecture/adr-0007-drag-merge-input.md
## @tutorial: docs/architecture/adr-0006-phase-state-machine.md


# ============================================================
# Constants
# ============================================================

## Phase values — kept as [int] to avoid Feature-layer dependency (ADR-0006).
## Matches [enum Phase] values from PhaseManager.
const PHASE_PREP: int = 0
const PHASE_BATTLE: int = 1
const PHASE_PAUSED: int = 2


# ============================================================
# Enums
# ============================================================

## Drag state machine states.
enum DragState {
	## No mouse button pressed — waiting for input.
	IDLE = 0,
	## Mouse pressed but moving distance < [member drag_threshold].
	PRESSING = 1,
	## Mouse pressed and moved > [member drag_threshold] — drag in progress.
	DRAGGING = 2,
	## Drag released — resolving target. Transitional, returns to IDLE same frame.
	RELEASING = 3,
}


# ============================================================
# Configuration
# ============================================================

## Pixel distance threshold to distinguish a click from a drag.
## Movement below this value during PRESSING state is treated as a click.
## Tuning: 2–5 px (GDD §Tuning Knobs).
@export var drag_threshold: float = 3.0


# ============================================================
# State
# ============================================================

## Current drag state machine state.
var drag_state: DragState = DragState.IDLE

## World position where the left mouse button was pressed.
var drag_start_pos: Vector2 = Vector2.ZERO

## Grid coordinates of the cell where the drag originated.
## Valid only when [member drag_state] is PRESSING or DRAGGING.
var drag_source_grid: Vector2i = Vector2i(-1, -1)

## Cached current game phase. Initialized to PREP (matches PhaseManager default).
## Updated via [signal SignalBus.phase_changed] subscription.
var _current_phase: int = PHASE_PREP

## Soft reference to the BoardGrid node. Inject via [method set_board_grid].
var _board_grid: BoardGrid = null


# ============================================================
# Signals — semantic game actions for downstream systems
# ============================================================

## Emitted when left-click is detected (press + release within [member drag_threshold]).
## Target system decides action based on cell state at (col, row).
signal grid_clicked(col: int, row: int)

## Emitted on right-click on a grid cell.
## BLOCK → remove block; TOWER → sell tower; (-1, -1) → cancel selection.
signal grid_right_clicked(col: int, row: int)

## Emitted when a drag is confirmed (mouse moved > [member drag_threshold] over a TOWER).
## Downstream system creates the drag preview / ghost.
signal drag_started(source_col: int, source_row: int)

## Emitted each frame during drag with the current mouse world position.
## Downstream system updates the ghost / preview position.
signal drag_moved(world_pos: Vector2)

## Emitted when a drag is released. (target_col, target_row) may be (-1, -1)
## if released outside the grid — downstream system handles bounce-back.
signal drag_ended(source_col: int, source_row: int, target_col: int, target_row: int)

## Emitted when a drag is cancelled (right-click during drag, or phase switch).
## Downstream system destroys the preview and returns the tower to its original cell.
signal drag_cancelled()


# ============================================================
# Lifecycle
# ============================================================

func _ready() -> void:
	# Subscribe to phase changes — cached locally to avoid Feature-layer refs
	if has_node("/root/SignalBus"):
		SignalBus.phase_changed.connect(_on_phase_changed)

	# Try to resolve BoardGrid from the scene tree if not already injected
	if _board_grid == null:
		_resolve_board_grid()


## Inject the [BoardGrid] reference. Must be called before any input processing.
## Exists primarily for unit testing — in production the scene tree lookup
## in [method _ready] handles resolution automatically.
func set_board_grid(board: BoardGrid) -> void:
	_board_grid = board


func _resolve_board_grid() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for child in parent.get_children():
		if child is BoardGrid:
			_board_grid = child as BoardGrid
			return


# ============================================================
# Engine Input Entry Point
# ============================================================

func _input(event: InputEvent) -> void:
	# Only process mouse events — keyboard reserved for future
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return

	# UI hit test: if a Control node covers this position, let UI consume it
	if _is_event_on_ui(event):
		return

	if event is InputEventMouseButton:
		_handle_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_motion(event as InputEventMouseMotion)


# ============================================================
# Public: Input simulation (for testing)
# ============================================================

## Simulate left mouse button press at [param world_pos].
## Exposed for unit tests to drive the state machine without real InputEvents.
func handle_left_press(world_pos: Vector2) -> void:
	# Phase gate: BATTLE blocks board interaction
	if _current_phase == PHASE_BATTLE:
		return

	if _board_grid == null:
		return

	var grid_pos := _board_grid.world_to_grid(world_pos)
	if grid_pos == Vector2i(-1, -1):
		return  # Clicked outside grid

	var cell_state: int = _board_grid.get_cell_state(grid_pos.x, grid_pos.y) as int

	# TOWER cells: start drag. Other cells: emit grid_clicked immediately
	if cell_state == BoardGrid.CellState.TOWER:
		drag_state = DragState.PRESSING
		drag_start_pos = world_pos
		drag_source_grid = grid_pos
	else:
		grid_clicked.emit(grid_pos.x, grid_pos.y)


## Simulate left mouse button release at [param world_pos].
## Exposed for unit tests to drive the state machine without real InputEvents.
func handle_left_release(world_pos: Vector2) -> void:
	match drag_state:
		DragState.IDLE:
			# Press was on UI or void — nothing to resolve
			pass

		DragState.PRESSING:
			# Released before drag threshold → it's a click
			drag_state = DragState.IDLE
			grid_clicked.emit(drag_source_grid.x, drag_source_grid.y)
			_reset_drag_state()

		DragState.DRAGGING:
			# Drag released — determine target cell
			drag_state = DragState.IDLE
			var target_grid := Vector2i(-1, -1)
			if _board_grid != null:
				target_grid = _board_grid.world_to_grid(world_pos)
			drag_ended.emit(drag_source_grid.x, drag_source_grid.y, target_grid.x, target_grid.y)
			_reset_drag_state()


## Simulate right mouse button press at [param world_pos].
## Exposed for unit tests to drive the state machine without real InputEvents.
func handle_right_press(world_pos: Vector2) -> void:
	# Phase gate: BATTLE blocks right-click on board
	if _current_phase == PHASE_BATTLE:
		return

	# Right-click during drag → cancel the drag (GDD edge case)
	if drag_state == DragState.DRAGGING or drag_state == DragState.PRESSING:
		cancel_drag()
		return

	if _board_grid == null:
		return

	var grid_pos := _board_grid.world_to_grid(world_pos)
	if grid_pos == Vector2i(-1, -1):
		# Clicked outside grid → cancel current selection
		grid_right_clicked.emit(-1, -1)
		return

	var cell_state: int = _board_grid.get_cell_state(grid_pos.x, grid_pos.y) as int

	# Right-click on BLOCK → remove; on TOWER → sell; else → cancel selection
	match cell_state:
		BoardGrid.CellState.BLOCK, BoardGrid.CellState.TOWER:
			grid_right_clicked.emit(grid_pos.x, grid_pos.y)
		_:
			grid_right_clicked.emit(-1, -1)  # Cancel selection


## Process a mouse motion event to [param world_pos].
## Drives drag detection — transitioning from PRESSING to DRAGGING
## when movement exceeds [member drag_threshold].
## Exposed for unit tests to drive the state machine without real InputEvents.
func handle_mouse_motion(world_pos: Vector2) -> void:
	match drag_state:
		DragState.PRESSING:
			if world_pos.distance_to(drag_start_pos) > drag_threshold:
				# Threshold exceeded → confirm drag
				drag_state = DragState.DRAGGING
				drag_started.emit(drag_source_grid.x, drag_source_grid.y)
		DragState.DRAGGING:
			drag_moved.emit(world_pos)


# ============================================================
# Public: Drag control
# ============================================================

## Cancel the current drag, if any. Emits [signal drag_cancelled].
## Called when right-click interrupts a drag or when the phase changes.
func cancel_drag() -> void:
	if drag_state == DragState.DRAGGING or drag_state == DragState.PRESSING:
		drag_state = DragState.IDLE
		drag_cancelled.emit()
		_reset_drag_state()


## Returns true if the drag state machine is currently in DRAGGING state.
func is_dragging() -> bool:
	return drag_state == DragState.DRAGGING


## Returns the current cached game phase.
func get_current_phase() -> int:
	return _current_phase


# ============================================================
# Internal: Engine event dispatch
# ============================================================

func _handle_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				handle_left_press(event.position)
			else:
				handle_left_release(event.position)
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				handle_right_press(event.position)
		# Middle button, wheel, etc. — ignored in MVP


func _handle_motion(event: InputEventMouseMotion) -> void:
	handle_mouse_motion(event.position)


# ============================================================
# Internal: Phase synchronization
# ============================================================

func _on_phase_changed(_old: int, new: int) -> void:
	_current_phase = new as int

	# Force-cancel any in-progress drag on phase switch (ADR-0007 / GDD edge case)
	if _current_phase == PHASE_BATTLE or _current_phase == PHASE_PAUSED:
		if drag_state == DragState.DRAGGING or drag_state == DragState.PRESSING:
			cancel_drag()


# ============================================================
# Internal: UI hit testing
# ============================================================

func _is_event_on_ui(event: InputEvent) -> bool:
	if not (event is InputEventMouse):
		return false
	var mouse_event := event as InputEventMouse

	# Use Godot's built-in GUI focus tracking.
	# If a Control has keyboard/gamepad focus and the click is within its rect,
	# the Control will consume it. For mouse-only focus (4.6 dual-focus system),
	# we check against visible root-level Controls.
	var viewport := get_viewport()
	if viewport == null:
		return false

	# Check if any visible Control under the mouse cursor
	for child in viewport.get_children():
		if not (child is Control):
			continue
		var ctrl := child as Control
		if ctrl.visible and ctrl.get_global_rect().has_point(mouse_event.global_position):
			return true

	return false


# ============================================================
# Internal: State cleanup
# ============================================================

func _reset_drag_state() -> void:
	drag_start_pos = Vector2.ZERO
	drag_source_grid = Vector2i(-1, -1)
