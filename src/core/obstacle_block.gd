class_name ObstacleBlock
extends Node
## Obstacle Block system — handles placement and removal of obstacle blocks on the grid.
##
## Gold is managed internally (int _gold). place_block() deducts BLOCK_COST,
## remove_block() refunds BLOCK_SELL_VALUE. All monetary side effects are
## self-contained within this system.
##
## Defense-in-depth phase gating: both place_block() and remove_block() reject
## during BATTLE phase. Only PREP phase allows board modification.
##
## Path validation: uses Pathfinding.would_path_be_reachable() as a speculative
## pre-check before committing a block placement, preventing dead-end boards.
##
## EconomyConfig override: if an EconomyConfig resource is passed to initialize(),
## its BLOCK_COST, BLOCK_SELL_VALUE, and MAX_BLOCKS values override the
## GDD-authoritative defaults below.
##
## GDD-authoritative defaults (Stellar Merge TD GDD, Section Block System):
##   BLOCK_COST       = 25 gold
##   BLOCK_SELL_VALUE = 10 gold
##   MAX_BLOCKS       = 10
##
## Usage:
##   var obstacle := ObstacleBlock.new()
##   obstacle.initialize(board, pathfinding, 200, economy_config)
##   add_child(obstacle)
##
##   # Place a block at grid (10, 7)
##   if obstacle.place_block(10, 7):
##       print("Block placed! Gold remaining: ", obstacle.get_gold())
##
##   # Remove the block
##   obstacle.remove_block(10, 7)
##
## Dependencies:
##   - BoardGrid (hard) — cell state queries and mutations
##   - Pathfinding (hard) — would_path_be_reachable() pre-check
##   - EconomyConfig (soft) — optional config override at initialize()
##   - SignalBus (soft) — gold_changed, block_count_changed emissions


# ============================================================
# GDD-Authoritative Defaults
# ============================================================

## Gold cost to place a single obstacle block on the board.
## Overridden by EconomyConfig.BLOCK_COST if config is provided to initialize().
var BLOCK_COST: int = 25

## Gold returned when removing/selling a block.
## Overridden by EconomyConfig.BLOCK_SELL_VALUE if config is provided to initialize().
var BLOCK_SELL_VALUE: int = 10

## Maximum number of blocks allowed on the board simultaneously.
## Overridden by EconomyConfig.MAX_BLOCKS if config is provided to initialize().
var MAX_BLOCKS: int = 10


# ============================================================
# Constants — Phase Values
# ============================================================

## Phase values kept as [int] to avoid Feature-layer dependency (ADR-0006).
## Matches PhaseManager.Phase enum and InputHandler.PHASE_* constants.
const PHASE_PREP: int = 0
const PHASE_BATTLE: int = 1
const PHASE_PAUSED: int = 2


# ============================================================
# State
# ============================================================

## Internal gold balance. Deducted on place, credited on remove.
## Must never go negative; place_block() checks affordability before deducting.
var _gold: int = 0

## Number of blocks currently placed on the board.
## Capped at MAX_BLOCKS; place_block() enforces this limit.
var _block_count: int = 0

## Reference to the BoardGrid data layer. Set via initialize().
var _board: BoardGrid = null

## Reference to the Pathfinding system. Set via initialize().
var _pathfinding: Pathfinding = null

## Current game phase, cached locally from SignalBus.phase_changed.
## Initialized to PREP. place_block() and remove_block() gate on this value.
var _current_phase: int = PHASE_PREP


# ============================================================
# Lifecycle
# ============================================================

func _ready() -> void:
	# Subscribe to phase changes for defense-in-depth gating
	if has_node("/root/SignalBus"):
		SignalBus.phase_changed.connect(_on_phase_changed)


# ============================================================
# Public API — Initialization
# ============================================================

## Initialize the obstacle block system with required dependencies.
##
## [param board] is the BoardGrid data layer for cell state queries/mutations.
## [param pathfinding] is the Pathfinding system for would_path_be_reachable() checks.
## [param starting_gold] is the initial gold balance for this system.
## [param config] is an optional EconomyConfig resource overriding GDD defaults.
##
## Must be called before any place_block() or remove_block() calls.
## Safe to call multiple times — re-initializes all state.
func initialize(board: BoardGrid, pathfinding: Pathfinding, starting_gold: int, config: EconomyConfig = null) -> void:
	_board = board
	_pathfinding = pathfinding
	_gold = starting_gold
	_block_count = 0
	_emit_gold_changed()

	# EconomyConfig override — apply only if provided
	if config != null:
		BLOCK_COST = config.BLOCK_COST
		BLOCK_SELL_VALUE = config.BLOCK_SELL_VALUE
		MAX_BLOCKS = config.MAX_BLOCKS


# ============================================================
# Public API — Block Placement
# ============================================================

## Attempt to place an obstacle block at grid position ([param col], [param row]).
##
## Validates: phase gate (PREP only), grid bounds, cell vacancy, block limit,
## gold affordability, and path reachability. All checks must pass before the
## BoardGrid state is mutated.
##
## On success: deducts BLOCK_COST gold, increments block count, emits
## gold_changed and block_count_changed via SignalBus (if available).
##
## Returns true if the block was placed, false otherwise.
##
## Usage:
##   if obstacle.place_block(10, 7):
##       print("Block placed at (10, 7)")
func place_block(col: int, row: int) -> bool:
	# ── Defense-in-depth: Phase gate ────────────────────────
	if _current_phase != PHASE_PREP:
		return false

	# ── Guard: dependencies initialized ─────────────────────
	if _board == null or _pathfinding == null:
		return false

	# ── Guard: grid bounds ─────────────────────────────────
	if not _board.is_valid_position(col, row):
		return false

	# ── Guard: cell must be EMPTY ──────────────────────────
	if _board.get_cell_state(col, row) != BoardGrid.CellState.EMPTY:
		return false

	# ── Guard: block limit ─────────────────────────────────
	if _block_count >= MAX_BLOCKS:
		return false

	# ── Guard: affordability ───────────────────────────────
	if _gold < BLOCK_COST:
		return false

	# ── Guard: path reachability (dead-end prevention) ─────
	var blocked_pos := Vector2i(col, row)
	if not _pathfinding.would_path_be_reachable(blocked_pos):
		return false

	# ── All checks passed — commit ─────────────────────────
	var success := _board.set_cell_state(col, row, BoardGrid.CellState.BLOCK)
	if not success:
		return false

	_gold -= BLOCK_COST
	_block_count += 1

	_emit_gold_changed()
	_emit_block_count_changed()

	return true


# ============================================================
# Public API — Block Removal
# ============================================================

## Attempt to remove an obstacle block at grid position ([param col], [param row]).
##
## Validates: phase gate (PREP only), grid bounds, and that the target cell
## actually contains a BLOCK. Removal refunds BLOCK_SELL_VALUE gold and
## decrements the block count.
##
## On success: credits BLOCK_SELL_VALUE gold, decrements block count, emits
## gold_changed and block_count_changed via SignalBus (if available).
##
## Returns true if the block was removed, false otherwise.
##
## Usage:
##   if obstacle.remove_block(10, 7):
##       print("Block removed — refunded ", BLOCK_SELL_VALUE, " gold")
func remove_block(col: int, row: int) -> bool:
	# ── Defense-in-depth: Phase gate ────────────────────────
	if _current_phase != PHASE_PREP:
		return false

	# ── Guard: dependencies initialized ─────────────────────
	if _board == null:
		return false

	# ── Guard: grid bounds ─────────────────────────────────
	if not _board.is_valid_position(col, row):
		return false

	# ── Guard: cell must contain a BLOCK ───────────────────
	if _board.get_cell_state(col, row) != BoardGrid.CellState.BLOCK:
		return false

	# ── Commit: clear the cell ─────────────────────────────
	var success := _board.set_cell_state(col, row, BoardGrid.CellState.EMPTY)
	if not success:
		return false

	_gold += BLOCK_SELL_VALUE
	_block_count -= 1

	_emit_gold_changed()
	_emit_block_count_changed()

	return true


# ============================================================
# Public API — Getters
# ============================================================

## Return the current internal gold balance.
##
## Usage:
##   var gold := obstacle.get_gold()
##   hud.update_gold_display(gold)
func get_gold() -> int:
	return _gold


## Return the number of blocks currently placed on the board.
##
## Usage:
##   var placed := obstacle.get_block_count()
##   print("Blocks on board: ", placed)
func get_block_count() -> int:
	return _block_count


## Return the number of additional blocks that can be placed.
## Computed as MAX_BLOCKS - current block count.
##
## Usage:
##   var remaining := obstacle.get_remaining_blocks()
##   hud.update_block_counter(remaining)
func get_remaining_blocks() -> int:
	return MAX_BLOCKS - _block_count


## Set the internal gold balance directly.
## Clamped to zero (gold cannot go negative). Used for game initialization
## and reset. Emits gold_changed via SignalBus if available.
##
## Usage:
##   obstacle.set_gold(200)  # Set starting gold for a new game
func set_gold(amount: int) -> void:
	_gold = max(0, amount)
	_emit_gold_changed()


# ============================================================
# Internal — Phase Synchronization
# ============================================================

## Handle phase transitions from SignalBus.phase_changed.
## Updates the locally cached phase for defense-in-depth gating.
## place_block() and remove_block() consult _current_phase on every call.
func _on_phase_changed(_old: int, new: int) -> void:
	_current_phase = new as int


# ============================================================
# Internal — Signal Emission (ADR-0001)
# ============================================================

## Emit gold_changed via SignalBus. Guarded by has_node for test safety.
func _emit_gold_changed() -> void:
	if has_node("/root/SignalBus"):
		SignalBus.gold_changed.emit(_gold)


## Emit block_count_changed via SignalBus. Guarded by has_node for test safety.
## Sends the number of remaining block slots (MAX_BLOCKS - _block_count).
func _emit_block_count_changed() -> void:
	if has_node("/root/SignalBus"):
		SignalBus.block_count_changed.emit(MAX_BLOCKS - _block_count)
