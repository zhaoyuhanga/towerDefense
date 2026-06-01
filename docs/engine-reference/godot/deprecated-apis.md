# Godot 4.6 — Deprecated APIs

Last verified: 2026-06-01

If an agent suggests any API in the "Deprecated" column, it MUST be replaced
with the "Use Instead" column.

## Nodes & Classes

| Deprecated | Use Instead | Since | Notes |
|------------|-------------|-------|-------|
| `TileMap` | `TileMapLayer` | 4.3 | One node per layer instead of multi-layer node |
| `VisibilityNotifier2D` | `VisibleOnScreenNotifier2D` | 4.0 | Renamed for clarity |
| `VisibilityNotifier3D` | `VisibleOnScreenNotifier3D` | 4.0 | Renamed for clarity |
| `YSort` | `Node2D.y_sort_enabled` | 4.0 | Property on Node2D, not a separate node |
| `Navigation2D` / `Navigation3D` | `NavigationServer2D` / `NavigationServer3D` | 4.0 | Server-based API |
| `EditorSceneFormatImporterFBX` | `EditorSceneFormatImporterFBX2GLTF` | 4.3 | Renamed |
| `EditorFileDialog.add_side_menu()` | No replacement — removed | 4.6 | Functionality no longer available |

## Methods & Properties

| Deprecated | Use Instead | Since | Notes |
|------------|-------------|-------|-------|
| `yield()` | `await signal` | 4.0 | GDScript 2.0 coroutine syntax |
| `connect("signal", obj, "method")` | `signal.connect(callable)` | 4.0 | Callable-based connections |
| `instance()` | `instantiate()` | 4.0 | Renamed |
| `PackedScene.instance()` | `PackedScene.instantiate()` | 4.0 | Renamed |
| `get_world()` | `get_world_3d()` | 4.0 | Explicit 2D/3D split |
| `OS.get_ticks_msec()` | `Time.get_ticks_msec()` | 4.0 | Time singleton preferred |
| `duplicate()` for nested resources | `duplicate_deep()` | 4.5 | Explicit deep copy control |
| `Skeleton3D` signal `bone_pose_updated` | `skeleton_updated` | 4.3 | Renamed |
| `AnimationPlayer.method_call_mode` | `AnimationMixer.callback_mode_method` | 4.3 | Moved to base class |
| `AnimationPlayer.playback_active` | `AnimationMixer.active` | 4.3 | Moved to base class |
| `JSONRPC.set_scope()` | `JSONRPC.set_method()` | 4.5 | Renamed |
| `Node.get_rpc_config()` | `Node.get_node_rpc_config()` | 4.5 | Renamed |
| `RenderingServer.instance_reset_physics_interpolation()` | None — removed | 4.5 | 2D not affected |
| `RenderingServer.instance_set_interpolated()` | None — removed | 4.5 | 2D not affected |
| `StreamPeerTCP.disconnect_from_host()` | `StreamPeerSocket.disconnect_from_host()` | 4.6 | Moved to base class |
| `TCPServer.is_connection_available()` | `SocketServer.is_connection_available()` | 4.6 | Moved to base class |
| `RichTextLabel.add_image(size_in_percent)` | `add_image(width_in_percent, height_in_percent)` | 4.5 | Split into two params |

## Patterns (Not Just APIs)

| Deprecated Pattern | Use Instead | Why |
|--------------------|-------------|-----|
| String-based `connect()` | Typed signal connections | Type-safe, refactor-friendly |
| `$NodePath` in `_process()` | `@onready var` cached reference | Performance: path lookup every frame |
| Untyped `Array` / `Dictionary` | `Array[Type]`, typed variables | GDScript compiler optimizations |
| `Texture2D` in shader parameters | `Texture` base type | Changed in 4.4 |
| Manual post-process viewport chains | `Compositor` + `CompositorEffect` | Structured post-processing (4.3+) |
| GodotPhysics3D for new projects | Jolt Physics 3D | Default since 4.6; better stability |

## 2D-Specific Notes (This Project)

- `AStarGrid2D` is the recommended pathfinding for grid-based games (not hand-rolled A*)
- `TileMapLayer` replaces `TileMap` — always use `TileMapLayer` for new projects
- `NavigationServer2D` is now a dedicated server (not proxied through 3D) since 4.5
- `@abstract` and variadic args available since 4.5 — use them
