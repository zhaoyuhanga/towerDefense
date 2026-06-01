# Technical Preferences

<!-- Populated by /setup-engine. Updated as the user makes decisions throughout development. -->
<!-- All agents reference this file for project-specific standards and conventions. -->

## Engine & Language

- **Engine**: Godot 4.6
- **Language**: GDScript
- **Rendering**: Compatibility (2D 桌面优先)
- **Physics**: GodotPhysics2D（2D 无需 Jolt）

## Input & Platform

- **Target Platforms**: PC（Windows / macOS）
- **Input Methods**: Keyboard/Mouse
- **Primary Input**: Mouse（点击放置方块，拖拽合星）
- **Gamepad Support**: None
- **Touch Support**: None
- **Platform Notes**: 纯桌面离线应用，无需网络。UI 基于鼠标悬停和点击，不支持手柄导航

## Naming Conventions

- **Classes**: PascalCase（e.g., `PlayerController`）
- **Variables/functions**: snake_case（e.g., `move_speed`）
- **Signals/Events**: snake_case 过去式（e.g., `health_changed`）
- **Files**: snake_case 匹配类名（e.g., `player_controller.gd`）
- **Scenes/Prefabs**: PascalCase 匹配根节点（e.g., `PlayerController.tscn`）
- **Constants**: UPPER_SNAKE_CASE（e.g., `MAX_HEALTH`）

## Performance Budgets

- **Target Framerate**: 60 FPS
- **Frame Budget**: 16.6ms
- **Draw Calls**: [TO BE CONFIGURED — 2D 项目 draw call 通常不是瓶颈]
- **Memory Ceiling**: [TO BE CONFIGURED]

## Testing

- **Framework**: GUT（Godot Unit Testing）
- **Minimum Coverage**: [TO BE CONFIGURED]
- **Required Tests**: 平衡公式、玩法系统

## Forbidden Patterns

<!-- Add patterns that should never appear in this project's codebase -->
- [None configured yet — add as architectural decisions are made]

## Allowed Libraries / Addons

<!-- Add approved third-party dependencies here -->
- [None configured yet — add as dependencies are approved]

## Architecture Decisions Log

<!-- Quick reference linking to full ADRs in docs/architecture/ -->
- [No ADRs yet — use /architecture-decision to create one]

## Engine Specialists

<!-- Written by /setup-engine when engine is configured. -->
<!-- Read by /code-review, /architecture-decision, /architecture-review, and team skills -->
<!-- to know which specialist to spawn for engine-specific validation. -->

- **Primary**: godot-specialist
- **Language/Code Specialist**: godot-gdscript-specialist (all .gd files)
- **Shader Specialist**: godot-shader-specialist (.gdshader files, VisualShader resources)
- **UI Specialist**: godot-specialist (no dedicated UI specialist — primary covers all UI)
- **Additional Specialists**: godot-gdextension-specialist (GDExtension / native C++ bindings only)
- **Routing Notes**: Invoke primary for architecture decisions, ADR validation, and cross-cutting code review. Invoke GDScript specialist for code quality, signal architecture, static typing enforcement, and GDScript idioms. Invoke shader specialist for material design and shader code. Invoke GDExtension specialist only when native extensions are involved.

### File Extension Routing

<!-- Skills use this table to select the right specialist per file type. -->

| File Extension / Type | Specialist to Spawn |
|-----------------------|---------------------|
| Game code (.gd files) | godot-gdscript-specialist |
| Shader / material files (.gdshader, VisualShader) | godot-shader-specialist |
| UI / screen files (Control nodes, CanvasLayer) | godot-specialist |
| Scene / prefab / level files (.tscn, .tres) | godot-specialist |
| Native extension / plugin files (.gdextension, C++) | godot-gdextension-specialist |
| General architecture review | godot-specialist |
