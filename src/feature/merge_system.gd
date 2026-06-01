class_name MergeSystem
extends Node
## Merge system — manages tower merge/upgrade operations.
##
## Implements: design/gdd/merge-upgrade.md
## Architecture: docs/architecture/adr-0007-drag-merge-input.md
## State Reset: docs/architecture/adr-0008-state-reset-protocol.md
##
## Core merge rule per GDD:
##   Two towers with same tower_id AND same star_level (and star_level < 3)
##   can be merged. Both source towers are destroyed, and a new tower
##   (same tower_id, star_level + 1) is created at the target position.
##   New tower attributes come from TowerData files — data-driven, per ADR-0002.
##
## Merge cost is read from EconomyConfig.MERGE_COST (default 0 = free merge).
## On failure, towers remain in place and merge_failed is emitted so the
## visual system can play the bounce-back animation (~0.3s elastic per GDD).
##
## Drag interface per ADR-0007:
##   InputHandler calls start_drag() → update_drag_preview() per frame →
##   try_merge() on drop or cancel_drag() on right-click / phase switch.
##
## Dependencies (injected via init):
##   - TowerSystem: tower lifecycle (get/create/remove)
##   - BoardGrid: cell state queries
##   - EconomySystem: gold balance + merge cost deduction
##   - EconomyConfig: merge_cost value from .tres


# ── Configuration ──────────────────────────────────────────────────────────────

## Economy configuration resource (EconomyConfig).
## Set via init(). Contains MERGE_COST among other economy knobs.
## Must not be null after initialization.
var _config: EconomyConfig

## Cached merge cost from config. Read once at init() and on game reset.
var _merge_cost: int = 0


# ── Injected Dependencies ──────────────────────────────────────────────────────

## TowerSystem reference — set via init(). Used for tower lifecycle operations.
var _tower_system: TowerSystem = null

## BoardGrid reference — set via init(). Used for cell state queries.
var _board: BoardGrid = null

## EconomySystem reference — set via init(). Used for gold balance checks.
var _economy: EconomySystem = null


# ── Phase Gating (ADR-0006) ────────────────────────────────────────────────────

## Phase constants mirroring PhaseManager.Phase enum.
const PHASE_PREP: int = 0
const PHASE_BATTLE: int = 1

## Current game phase, cached locally via SignalBus.phase_changed subscription.
## Defaults to PHASE_PREP — merge is allowed until first BATTLE transition.
var _current_phase: int = PHASE_PREP


# ── Drag State (ADR-0007) ──────────────────────────────────────────────────────

## True while a drag operation is in progress (between start_drag and
## try_merge/cancel_drag). Guards update_drag_preview.
var _is_dragging: bool = false

## The tower being dragged. Set by start_drag(), cleared on merge/cancel.
var _drag_source_tower: Tower = null

## Grid position of the dragged tower at drag start.
var _drag_source_col: int = -1
var _drag_source_row: int = -1


# ── Ghost Preview ──────────────────────────────────────────────────────────────

## Semi-transparent visual copy of the dragged tower.
## Created by _create_ghost() on start_drag(), freed by _cleanup_drag().
## modulate.a = 0.6 per ADR-0007. z_index = 100 to render above grid.
var _ghost_node: Node2D = null


# ── Reset Guard (ADR-0008) ─────────────────────────────────────────────────────

## Prevents re-entrant reset from signal cascades.
var _is_resetting: bool = false


# ═══════════════════════════════════════════════════════════════════════════════════
# Public API
# ═══════════════════════════════════════════════════════════════════════════════════


## Initialize the merge system with required dependencies.
##
## Subscribes to SignalBus.phase_changed (phase gating) and
## SignalBus.game_reset_requested (state reset per ADR-0008).
## Caches merge_cost from EconomyConfig.
##
## Usage:
##   var merge_sys := MergeSystem.new()
##   merge_sys.init(tower_system, board, economy, economy_config)
func init(p_tower_system: TowerSystem, p_board: BoardGrid, p_economy: EconomySystem, p_config: EconomyConfig) -> void:
	_tower_system = p_tower_system
	_board = p_board
	_economy = p_economy
	_config = p_config
	_merge_cost = p_config.MERGE_COST
	_current_phase = PHASE_PREP

	# Subscribe to SignalBus events (has_node guard for test safety)
	if has_node("/root/SignalBus"):
		if not SignalBus.phase_changed.is_connected(_on_phase_changed):
			SignalBus.phase_changed.connect(_on_phase_changed)
		if not SignalBus.game_reset_requested.is_connected(_on_game_reset):
			SignalBus.game_reset_requested.connect(_on_game_reset)


## Begin a drag operation for the given tower.
##
## Creates a semi-transparent ghost preview that follows the mouse.
## No-ops if not in PREP phase, if tower is null, or if tower is invalid.
## If already dragging, cancels the previous drag first (one drag at a time).
##
## Called by InputHandler when the player begins dragging a tower.
func start_drag(tower: Tower) -> void:
	if _current_phase != PHASE_PREP:
		return
	if tower == null or not is_instance_valid(tower):
		return
	if _is_dragging:
		cancel_drag()

	_is_dragging = true
	_drag_source_tower = tower
	_drag_source_col = tower.grid_pos.x
	_drag_source_row = tower.grid_pos.y

	_create_ghost(tower)


## Update the ghost preview position to the current mouse position.
##
## No-ops if not in a drag operation or if the ghost was freed externally.
## Called by InputHandler in _process() while drag state is DRAGGING.
func update_drag_preview() -> void:
	if not _is_dragging:
		return
	if _ghost_node != null and is_instance_valid(_ghost_node):
		_ghost_node.global_position = _ghost_node.get_global_mouse_position()


## Attempt to merge the tower at (from_col, from_row) with the tower at
## (to_col, to_row). Returns true on success, false on failure.
##
## Validation checklist (all must pass):
##   1. _current_phase == PHASE_PREP (phase gate)
##   2. Source and target positions are different
##   3. A tower exists at each position
##   4. Both towers have valid TowerData
##   5. tower_id matches between source and target
##   6. star_level matches between source and target
##   7. star_level < 3 (3-star is max — cannot merge further)
##   8. If merge_cost > 0, player can afford it
##
## On success (atomic execution):
##   1. Deduct merge_cost from economy (if > 0)
##   2. Remove both source and target towers via TowerSystem
##   3. Create new tower at target position with star_level + 1
##   4. Clean up drag state (ghost freed)
##   5. Emit SignalBus.merge_completed
##
## On failure:
##   Emits SignalBus.merge_failed(reason) — visual system plays bounce-back.
##   Towers are not modified. Drag state is preserved (player can retry).
##
## GDD AC:
##   GIVEN two 1-star cannons adjacent, WHEN dragged one onto the other,
##   THEN both disappear, a 2-star cannon appears at target position.
##   GIVEN 1-star cannon dragged onto 1-star ice tower,
##   WHEN released, THEN both bounce back (merge_failed emitted).
##   GIVEN two 3-star cannons, WHEN released, THEN bounce back (max star).
func try_merge(from_col: int, from_row: int, to_col: int, to_row: int) -> bool:
	# Phase gate
	if _current_phase != PHASE_PREP:
		_emit_merge_failed("Not in PREP phase")
		return false

	# Cannot merge with itself
	if from_col == to_col and from_row == to_row:
		_emit_merge_failed("Cannot merge tower with itself")
		return false

	# Get source tower
	var source_tower: Tower = _tower_system.get_tower(from_col, from_row)
	if source_tower == null:
		_emit_merge_failed("No tower at source (%d, %d)" % [from_col, from_row])
		return false

	# Get target tower
	var target_tower: Tower = _tower_system.get_tower(to_col, to_row)
	if target_tower == null:
		_emit_merge_failed("No tower at target (%d, %d)" % [to_col, to_row])
		return false

	# Validate tower data
	var source_data: TowerData = source_tower.tower_data
	var target_data: TowerData = target_tower.tower_data
	if source_data == null:
		_emit_merge_failed("Source tower data missing")
		return false
	if target_data == null:
		_emit_merge_failed("Target tower data missing")
		return false

	# Same tower type
	if source_data.tower_id != target_data.tower_id:
		_emit_merge_failed("Tower type mismatch: %s vs %s" % [source_data.tower_id, target_data.tower_id])
		return false

	# Same star level
	if source_data.star_level != target_data.star_level:
		_emit_merge_failed("Star level mismatch: %d vs %d" % [source_data.star_level, target_data.star_level])
		return false

	# Not already max star
	if source_data.star_level >= 3:
		_emit_merge_failed("Already max star level (3)")
		return false

	# Check merge cost affordability
	if _merge_cost > 0:
		if not _economy.can_afford(_merge_cost):
			_emit_merge_failed("Cannot afford merge cost: %d gold" % _merge_cost)
			return false

	# ── Execute Merge (atomic) ──────────────────────────────────────────────

	var new_star: int = source_data.star_level + 1
	var tower_id: String = source_data.tower_id
	var from_star: int = source_data.star_level

	# Step 1: Remove both source towers
	_tower_system.remove_tower(from_col, from_row)
	_tower_system.remove_tower(to_col, to_row)

	# Step 2: Deduct merge cost (if any)
	if _merge_cost > 0:
		# spend_gold should succeed — we already validated can_afford above
		var spent: bool = _economy.spend_gold(_merge_cost)
		if not spent:
			# Edge case: gold changed between check and spend (should be impossible
			# in single-player, but guard against it)
			push_error("MergeSystem.try_merge: spend_gold(%d) failed after can_afford passed" % _merge_cost)
			_emit_merge_failed("Merge cost deduction failed")
			return false

	# Step 3: Place new merged tower at target position
	var placed: bool = _tower_system.place_tower(tower_id, new_star, to_col, to_row)
	if not placed:
		# Catastrophic: both source towers are already removed.
		# Log error and emit failure — the board has lost two towers.
		push_error("MergeSystem.try_merge: Failed to place merged tower '%s' star %d at (%d, %d)" % [tower_id, new_star, to_col, to_row])
		_emit_merge_failed("Failed to create merged tower")
		return false

	# Step 4: Clean up drag state
	_cleanup_drag()

	# Step 5: Emit success — visual system plays merge animation
	if has_node("/root/SignalBus"):
		SignalBus.merge_completed.emit(from_star, new_star, Vector2i(to_col, to_row))

	return true


## Cancel the current drag operation.
##
## Cleans up ghost preview and resets drag state. Emits merge_failed("cancelled")
## so the visual system can play the bounce-back animation (~0.3s elastic).
##
## Called by InputHandler on: right-click during drag, or phase switch to BATTLE.
## Safe to call when not dragging (no-ops).
func cancel_drag() -> void:
	if not _is_dragging:
		return
	_cleanup_drag()
	_emit_merge_failed("cancelled")


## Cancel any active merge/drag operation.
##
## Called during game reset (ADR-0008 Phase 1 — DESTROY phase).
## Unlike cancel_drag(), does NOT emit merge_failed — reset is not a
## user-facing failure, and visual systems will be cleared separately.
func cancel_all() -> void:
	if not _is_dragging:
		return
	_is_dragging = false
	_drag_source_tower = null
	_drag_source_col = -1
	_drag_source_row = -1
	if _ghost_node != null:
		if is_instance_valid(_ghost_node):
			_ghost_node.queue_free()
		_ghost_node = null


## Check whether a merge between two grid positions would be valid.
## Does NOT execute the merge — pure query. Used by UI/InputHandler for
## highlighting valid merge targets (green/red glow on hover per ADR-0007).
##
## Returns true iff all merge preconditions are met (same checks as try_merge
## except phase gate is included).
func can_merge(from_col: int, from_row: int, to_col: int, to_row: int) -> bool:
	if _current_phase != PHASE_PREP:
		return false
	if from_col == to_col and from_row == to_row:
		return false

	var source_tower: Tower = _tower_system.get_tower(from_col, from_row)
	if source_tower == null:
		return false

	var target_tower: Tower = _tower_system.get_tower(to_col, to_row)
	if target_tower == null:
		return false

	var source_data: TowerData = source_tower.tower_data
	var target_data: TowerData = target_tower.tower_data
	if source_data == null or target_data == null:
		return false

	if source_data.tower_id != target_data.tower_id:
		return false
	if source_data.star_level != target_data.star_level:
		return false
	if source_data.star_level >= 3:
		return false
	if _merge_cost > 0 and not _economy.can_afford(_merge_cost):
		return false

	return true


# ═══════════════════════════════════════════════════════════════════════════════════
# Internal: Signal Handlers
# ═══════════════════════════════════════════════════════════════════════════════════


## React to phase transitions from SignalBus.
## Caches the new phase locally. If leaving PREP phase while dragging,
## force-cancels the drag — towers stay in place, ghost disappears.
##
## ADR-0006: PREP → BATTLE: cancel any in-progress merge drags.
func _on_phase_changed(_old_phase: int, new_phase: int) -> void:
	_current_phase = new_phase
	if new_phase != PHASE_PREP and _is_dragging:
		cancel_drag()


## Handle game reset — cancel any active drag and reset phase to PREP.
##
## ADR-0008 Phase 1 (DESTROY): cancel_all() silently cleans up drag state
## without emitting merge_failed — other systems are also resetting.
##
## Guarded by _is_resetting for idempotency (prevents double-execution
## from signal cascades).
func _on_game_reset() -> void:
	if _is_resetting:
		return
	_is_resetting = true
	cancel_all()
	_current_phase = PHASE_PREP
	_is_resetting = false


# ═══════════════════════════════════════════════════════════════════════════════════
# Internal: Helpers
# ═══════════════════════════════════════════════════════════════════════════════════


## Emit merge_failed signal via SignalBus.
## Uses has_node guard for test environments where SignalBus may not exist.
func _emit_merge_failed(reason: String) -> void:
	if has_node("/root/SignalBus"):
		SignalBus.merge_failed.emit(reason)


## Clean up all drag-related state.
## Frees ghost node, resets drag flags, clears tower reference.
func _cleanup_drag() -> void:
	_is_dragging = false
	_drag_source_tower = null
	_drag_source_col = -1
	_drag_source_row = -1
	if _ghost_node != null:
		if is_instance_valid(_ghost_node):
			_ghost_node.queue_free()
		_ghost_node = null


## Create a semi-transparent ghost copy of the tower for drag preview.
##
## The ghost is a lightweight Node2D (not a full Tower) that follows the
## mouse cursor. modulate.a = 0.6 per ADR-0007. z_index = 100 to render
## above the grid and other towers.
##
## In production, the visual feedback system may replace this with a
## dedicated sprite toml for richer visuals (glow, particles).
func _create_ghost(tower: Tower) -> void:
	# Clean up any existing ghost first
	if _ghost_node != null and is_instance_valid(_ghost_node):
		_ghost_node.queue_free()
	_ghost_node = null

	# Create a lightweight placeholder node at the tower's position
	_ghost_node = Node2D.new()
	_ghost_node.modulate = Color(1.0, 1.0, 1.0, 0.6)
	_ghost_node.global_position = tower.global_position
	_ghost_node.z_index = 100
	add_child(_ghost_node)
