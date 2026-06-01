# SignalBus — Global event bus (ADR-0001)
# All cross-system signals are declared here.
# Systems emit via SignalBus.[signal_name].emit(...)
# Systems subscribe via SignalBus.[signal_name].connect(callable)
extends Node

# === Board Grid ===
signal cell_state_changed(col: int, row: int, old_state: int, new_state: int)

# === Pathfinding ===
signal path_updated(new_path: Array)
signal path_blocked()

# === Monster Lifecycle ===
signal monster_died(monster_id: String, position: Vector2, reward_gold: int)
signal monster_breached(position: Vector2, path: Array)

# === Combat ===
signal damage_dealt(target_id: String, amount: float, damage_type: String)

# === Wave ===
signal wave_started(wave_number: int)
signal wave_ended(wave_number: int, enemies_killed: int, enemies_breached: int)

# === Merge ===
signal merge_completed(from_star: int, to_star: int, position: Vector2i)
signal merge_failed(reason: String)

# === Economy ===
signal gold_changed(current_gold: int)

# === Phase ===
signal phase_changed(old_phase: int, new_phase: int)

# === Skills ===
signal skill_activated(skill_id: String)

# === Blocks ===
signal block_count_changed(remaining: int)

# === Game Lifecycle ===
signal game_reset_requested()
