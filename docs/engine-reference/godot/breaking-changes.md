# Godot — Breaking Changes

Last verified: 2026-06-01

Changes between Godot versions, focused on post-LLM-cutoff changes (4.4+).
Every API break listed here has been verified against official migration guides.

---

## 4.5 → 4.6 (Jan 2026 — POST-CUTOFF, HIGH RISK)

### AnimationPlayer — String → StringName (GDScript ❌)

| Member | Old Type | New Type |
|--------|----------|-----------|
| `assigned_animation` property | `String` | `StringName` |
| `autoplay` property | `String` | `StringName` |
| `current_animation` property | `String` | `StringName` |
| `get_queue()` return | `PackedStringArray` | `StringName[]` |
| `current_animation_changed` signal `name` | `String` | `StringName` |

### FileAccess Changes

| Method | Change |
|--------|--------|
| `create_temp()` | `mode_flags` 参数类型从 `int` 改为 `FileAccess.ModeFlags` |
| `get_as_text()` | 移除了 `skip_cr` 参数 |

### Networking — Methods Moved to Base Classes (GDScript ❌)

| Old Location | Method | New Location |
|-------------|--------|-------------|
| `StreamPeerTCP.disconnect_from_host()` | → | `StreamPeerSocket` |
| `StreamPeerTCP.get_status()` | → | `StreamPeerSocket` |
| `StreamPeerTCP.poll()` | → | `StreamPeerSocket` |
| `TCPServer.is_connection_available()` | → | `SocketServer` |
| `TCPServer.is_listening()` | → | `SocketServer` |
| `TCPServer.stop()` | → | `SocketServer` |

### EditorFileDialog — Removed Methods

| Method | Status |
|--------|--------|
| `add_side_menu()` | **Removed entirely** ❌ |
| `add_filter()`, `add_option()`, `clear_filters()`, `get_line_edit()`, `invalidate()`, `popup_file_dialog()`, etc. | Moved to base class `FileDialog` |

### 3D — SpringBoneSimulator3D Type Changes

All `SpringBoneSimulator3D.BoneDirection` → `SkeletonModifier3D.BoneDirection`
All `SpringBoneSimulator3D.RotationAxis` → `SkeletonModifier3D.RotationAxis`

### Changed Defaults (New Projects)

| Area | Setting | Old Default | New Default |
|------|---------|-------------|-------------|
| Windows | `rendering/rendering_device/driver.windows` | — | **D3D12** |
| Physics | `physics/3d/physics_engine` | — | **Jolt Physics** |
| Rendering | `Environment.glow_blend_mode` | Soft Light (2) | **Screen (1)** |
| Rendering | `Environment.glow_intensity` | 0.8 | **0.3** |
| Rendering | `sky_reflections/roughness_layers` | 8 | **7** |
| GUI | `PopupMenu.submenu_popup_delay` | 0.3 | **0.2** |

### Behavior Changes

| Area | Change |
|------|--------|
| Glow | Rewritten — screen blend default, significantly brighter. Reduce intensity. |
| Volumetric fog | More physically accurate — appears brighter; reduce density/energy |
| AStarGrid2D | `get_id_path()`/`get_point_path()` return empty path when `from_id` is disabled/solid ⚠️ **RELEVANT TO MAZING** |
| TSCN format | `load_steps` no longer written; unique node IDs saved → version control diffs |
| IK | Full inverse kinematics restored (CCDIK, FABRIK, Jacobian, Spline, TwoBoneIK) |

---

## 4.4 → 4.5 (Late 2025 — POST-CUTOFF, HIGH RISK)

### Core — Renamed Methods

| Old API | New API | GDScript | C# |
|---------|---------|----------|----|
| `JSONRPC.set_scope()` | `JSONRPC.set_method()` | ❌ | ❌ |
| `Node.get_rpc_config()` | `Node.get_node_rpc_config()` | ❌ | ✔️ |

### Core — Type Changes

| Method | Change |
|--------|--------|
| `Node.set_name()` | `name` 参数 `String` → `StringName` (all ✔️) |

### Rendering — Removed Methods

| Removed API | Notes |
|-------------|-------|
| `RenderingServer.instance_reset_physics_interpolation()` | 彻底移除 (GDScript ❌) |
| `RenderingServer.instance_set_interpolated()` | 彻底移除 (GDScript ❌) |

### C# Enum Breaking Change

| Old | New |
|-----|-----|
| `RenderingDevice.Features.Address` | `RenderingDevice.Features.BufferDeviceAddress` |

### GLTF — C# int → long

`GLTFAccessor` 和 `GLTFBufferView` 的多数字段从 `int`→`long` (C# ❌)

### RichTextLabel

| Old | New |
|-----|-----|
| `add_image(size_in_percent)` | `add_image(width_in_percent, height_in_percent)` |
| `update_image(size_in_percent)` | `update_image(width_in_percent, height_in_percent)` |

### Behavior Changes

| Area | Change | Mitigation |
|------|--------|------------|
| TileMapLayer | Physics chunking enabled by default | Set `physics_quadrant_size=1` for old behavior |
| Resource.duplicate(true) | No longer duplicates external resources | Use `duplicate_deep(DEEP_DUPLICATE_ALL)` |
| Navigation | Regions update asynchronously via threads | Toggle `region_use_async_iterations` |
| GDScript | Variadic arguments added | New feature, no break |
| GDScript | `@abstract` decorator | New feature, no break |
| Accessibility | AccessKit screen reader support | New feature, no break |

---

## 4.3 → 4.4 (Mid 2025 — NEAR CUTOFF, VERIFY)

| Subsystem | Change | Details |
|-----------|--------|---------|
| Core | `FileAccess.store_*` return `bool` | Was `void`. 14 methods affected. |
| Core | `OS.execute_with_pipe` | Added optional `blocking` parameter |
| Rendering | `RenderingDevice.draw_list_begin` | Many parameters removed; `breadcrumb` added |
| Rendering | Shader texture types | `Texture2D` → `Texture` in parameter/return types |
| Particles | `.restart()` method | Added optional `keep_seed` parameter |
| GUI | `RichTextLabel.push_meta` | Added optional `tooltip` parameter |

---

## Relevance to This Project

| Change | Applies? | Notes |
|--------|----------|-------|
| AnimationPlayer String→StringName | ⚠️ Possible | Only if using AnimationPlayer for UI effects |
| AStarGrid2D empty path on solid | ✅ **YES** | Core to mazing pathfinding! |
| Networking changes | ❌ | Offline game |
| 3D physics/rendering | ❌ | 2D project |
| EditorFileDialog | ❌ | No editor plugins |
| TileMapLayer physics chunking | ⚠️ Possible | If using TileMap for grid |
| `duplicate_deep()` | ⚠️ Possible | Use for deep-copying tower configs |
| `@abstract` | ✅ Use it | Use for base Enemy/Tower classes |
| Variadic arguments | ✅ Use it | Useful for utility functions |
