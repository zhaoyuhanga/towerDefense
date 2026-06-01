# Godot 4.6 — Current Best Practices

Last verified: 2026-06-01 | Engine: Godot 4.6

Practices that are **new or changed** since the model's training data (~4.3).
This supplements (not replaces) the agent's built-in knowledge.

---

## 2D Grid / Pathfinding (✅ RELEVANT — Mazes & Tower Defense)

### AStarGrid2D — Behavior Change (4.6)

**⚠️ CRITICAL**: `get_id_path()` and `get_point_path()` now return **empty array**
when `from_id` is a disabled or solid point. Previously they might return partial results.

```gdscript
# ✅ Always check before requesting a path
if not astar_grid.is_point_solid(from_pos):
    var path := astar_grid.get_id_path(from_pos, to_pos)
```

### TileMapLayer

- **Physics chunking (4.5+)**: Enabled by default. For tile-by-tile precision, set `physics_quadrant_size` to `1`.
- Leave chunking enabled unless you need per-tile physics accuracy.

---

## GDScript (4.5+)

### Variadic Arguments

```gdscript
func log_values(prefix: String, values: Variant...) -> void:
    for v in values:
        print(prefix, ": ", v)

# Usage
log_values("DEBUG", pos, tile_type, cost)
```

### @abstract Classes and Methods

```gdscript
@abstract
class_name BaseTower extends Node2D

@abstract
func get_attack_target() -> Enemy:
    pass  # Subclasses MUST override

@abstract
func get_star_bonus(star_level: int) -> Dictionary:
    pass
```

### Static Typing (Always)

```gdscript
# ❌
var health = 100

# ✅
var health: int = 100
var enemies: Array[Enemy] = []
func take_damage(amount: float) -> bool:
```

### Script Backtracing

Detailed call stacks available even in Release builds (4.5+).

---

## Signals (4.0+, Still Best Practice)

```gdscript
# ✅ Connect in code (type-safe)
button.pressed.connect(_on_button_pressed)

# ✅ Custom signals with typed parameters
signal wave_started(wave_number: int)
signal tower_merged(from_star: int, to_star: int, position: Vector2i)
signal path_blocked(blocked_position: Vector2i)

# ❌ Never use string-based connections
```

---

## Resources (4.5+)

### duplicate_deep() for Nested Resources

```gdscript
# Old (shallow — external resources shared)
var copy := original.duplicate(true)

# New (deep — everything copied)
var copy := original.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
```

---

## Performance Patterns

### Object Pooling for Enemies

```gdscript
var enemy_pool: Array[Enemy] = []
var active_enemies: Array[Enemy] = []

func spawn_enemy(type: EnemyType, position: Vector2) -> Enemy:
    var enemy := _get_pooled_enemy(type)
    enemy.setup(position)
    active_enemies.append(enemy)
    return enemy

func despawn_enemy(enemy: Enemy) -> void:
    active_enemies.erase(enemy)
    enemy.reset()
    enemy_pool.append(enemy)
```

### Avoid `_process()` polling

```gdscript
# ❌ Polling in _process
func _process(delta: float) -> void:
    for tower in towers:
        tower.check_range()

# ✅ Timer-driven
func _on_attack_timer_timeout() -> void:
    for tower in towers:
        tower.fire_at_nearest_enemy()
```

### Cache node references

```gdscript
# ❌ Path lookup every frame
func _process(_delta: float) -> void:
    $UI/WaveLabel.text = str(current_wave)

# ✅ Cache once
@onready var wave_label: Label = $UI/WaveLabel
func _update_ui() -> void:
    wave_label.text = str(current_wave)
```

---

## UI / Mouse Input (2D Desktop)

### Mouse Input for Grid-Based Game

```gdscript
func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        match event.button_index:
            MOUSE_BUTTON_LEFT:
                _handle_left_click(event.position)
            MOUSE_BUTTON_RIGHT:
                _handle_right_click(event.position)

func _screen_to_grid(screen_pos: Vector2) -> Vector2i:
    var local_pos := get_global_mouse_position()
    return Vector2i(
        floori(local_pos.x / TILE_SIZE),
        floori(local_pos.y / TILE_SIZE)
    )
```

---

## Project Settings for 2D Desktop

Recommended for a 2D TD game:

```ini
[rendering]
renderer/rendering_method=forward_plus

[display]
window/stretch/mode=canvas_items
window/stretch/aspect=expand

[input_devices]
pointing/emulate_touch_from_mouse=false
```

---

## Tooling

- **ripgrep has no `gdscript` type**: `*.gd` is registered under `gap` (GAP programming language).
  `rg --type gdscript` is a hard error. Always use `rg --glob "*.gd"` or `glob: "*.gd"` (Grep tool).

---

## Accessibility (4.5+)

Godot 4.5 introduced **AccessKit** for screen reader support. For MVP: focus on clean UI text and readable fonts. Full accessibility can wait for V1.0+.

---

## Not Applicable to This Project

- **3D physics** (Jolt, SpringBone, IK restoration) — 2D project
- **Networking** (StreamPeerTCP, TCPServer) — offline game
- **D3D12 rendering** — 2D, Compatibility renderer preferred
- **GLTF import** — no 3D assets
- **Editor plugins** — not building editor tools
