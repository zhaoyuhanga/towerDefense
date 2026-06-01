class_name EconomySystem
extends Node
## Economy system — manages the player's gold balance.
##
## Implements: design/gdd/economy.md
## Architecture: ADR-0002 (data-driven config via .tres)
## State Reset: ADR-0008 (config-based reset on game_reset_requested)
##
## Gold is the sole currency. Income comes from monster kills
## (kill_reward_multiplier applied via _on_monster_died) and selling
## towers/blocks (via add_gold). Expense goes to purchasing towers,
## blocks, and merges (via spend_gold + can_afford pre-check).
##
## All balance changes emit SignalBus.gold_changed.
##
## Lifecycle:
##   init(config) — sets starting gold, connects to SignalBus
##   spend_gold(amount) — attempt purchase, returns bool
##   add_gold(amount) — non-kill income (selling)
##   can_afford(amount) — pre-purchase check
##   _on_game_reset() — config-based reset to starting_gold


# ── Configuration ──────────────────────────────────────────────────────────────

## Economy configuration resource (EconomyConfig).
## Set via init(). Contains starting_gold, kill_reward_multiplier,
## and all cost/sell constants. Must not be null after initialization.
var _config: EconomyConfig


# ── Public State ───────────────────────────────────────────────────────────────

## Current gold balance.
## Read-only externally; mutate via spend_gold() / add_gold().
var current_gold: int = 0

## Global multiplier applied to monster kill gold rewards.
## Loaded from _config.kill_reward_multiplier at init() and on game reset.
## 1.0 = base reward, 2.0 = double, 0.5 = half.
var kill_reward_multiplier: float = 1.0


# ═══════════════════════════════════════════════════════════════════════════════════
# Public API
# ═══════════════════════════════════════════════════════════════════════════════════


## Initialize the economy system with configuration.
## Sets starting gold and multiplier from config. Subscribes to SignalBus
## for monster_died (kill income) and game_reset_requested (state reset).
## Emits initial gold_changed signal with starting gold.
##
## Usage:
##   var economy := EconomySystem.new()
##   economy.init(economy_config)
func init(config: EconomyConfig = null) -> void:
	if config != null:
		_config = config
		kill_reward_multiplier = config.kill_reward_multiplier
		current_gold = config.starting_gold
	else:
		_config = EconomyConfig.new()
		_config.starting_gold = 200
		_config.kill_reward_multiplier = 1.0
		kill_reward_multiplier = 1.0
		current_gold = 200

	# Subscribe to SignalBus events (has_node guard for test safety)
	if has_node("/root/SignalBus"):
		if not SignalBus.monster_died.is_connected(_on_monster_died):
			SignalBus.monster_died.connect(_on_monster_died)
		if not SignalBus.game_reset_requested.is_connected(_on_game_reset):
			SignalBus.game_reset_requested.connect(_on_game_reset)

	_emit_gold_changed()


## Check if the player can afford the given amount.
## Returns true only if amount > 0 AND current_gold >= amount.
## Use this before spend_gold() to gate purchase UI (grey out buttons).
##
## GDD edge case: amount <= 0 always returns false — no free purchases.
func can_afford(amount: int) -> bool:
	return amount > 0 and current_gold >= amount


## Spend gold. Returns true on success, false if insufficient funds
## or amount <= 0. Gold balance is unchanged on failure.
##
## Emits SignalBus.gold_changed on success.
##
## GDD AC: GIVEN current_gold=200, WHEN spend_gold(50), THEN true, gold=150
## GDD AC: GIVEN current_gold=30, WHEN spend_gold(50), THEN false, gold unchanged
func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return false
	if not can_afford(amount):
		return false
	current_gold -= amount
	_emit_gold_changed()
	return true


## Add gold to balance. Used for non-kill income (selling towers/blocks).
## Amount must be positive (> 0). No-ops silently on amount <= 0.
##
## Emits SignalBus.gold_changed on success.
##
## For monster kill income: use the monster_died signal path instead —
## it applies kill_reward_multiplier automatically.
func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	current_gold += amount
	_emit_gold_changed()


# ═══════════════════════════════════════════════════════════════════════════════════
# Internal: Signal Handlers
# ═══════════════════════════════════════════════════════════════════════════════════


## Handler for SignalBus.monster_died.
## Applies kill_reward_multiplier to the base reward_gold and adds result
## to current_gold. Rounds to nearest integer.
##
## GDD AC: GIVEN monster killed with reward_gold=10, multiplier=1.0,
##         WHEN monster_died signal emitted, THEN gold increases by 10.
func _on_monster_died(_monster_id: String, _position: Vector2, reward_gold: int) -> void:
	var final_reward := int(round(reward_gold * kill_reward_multiplier))
	add_gold(final_reward)


## Handler for SignalBus.game_reset_requested (ADR-0008).
## Resets gold to _config.starting_gold and reloads kill_reward_multiplier
## from config. Emits gold_changed with the new balance.
##
## If _config is null (should not happen after init), falls back to
## safe defaults: current_gold=0, kill_reward_multiplier=1.0.
func _on_game_reset() -> void:
	if _config != null:
		current_gold = _config.starting_gold
		kill_reward_multiplier = _config.kill_reward_multiplier
	else:
		current_gold = 0
		kill_reward_multiplier = 1.0
	_emit_gold_changed()


# ═══════════════════════════════════════════════════════════════════════════════════
# Internal: Helpers
# ═══════════════════════════════════════════════════════════════════════════════════


## Emit gold_changed signal via SignalBus if available.
## Uses has_node guard for test environments where SignalBus may not exist.
func _emit_gold_changed() -> void:
	if has_node("/root/SignalBus"):
		SignalBus.gold_changed.emit(current_gold)
