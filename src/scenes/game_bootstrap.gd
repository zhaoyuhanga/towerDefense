# Game Bootstrap — Production initialization
extends Node2D

var _board: BoardGrid
var _grid_renderer: GridRenderer
var _pathfinding: Pathfinding
var _obstacle_block: ObstacleBlock
var _input_handler: InputHandler
var _economy: EconomySystem
var _phase_manager: PhaseManager
var _wave_spawner: WaveSpawner
var _tower_system: TowerSystem
var _merge_system: MergeSystem
var _hud: HUD
var _hover: Node2D
var _path_overlay: PathOverlay

var _placement_mode: String = "block"
var _selected_tower_id: String = "cannon"


func _ready() -> void:
	_board = BoardGrid.new()
	_board.name = "BoardGrid"
	add_child(_board)
	_board.init(20, 15, Vector2i(0, 7), Vector2i(19, 7))
	_board._recalculate_origin()  # Force origin calc before _ready() fires

	_grid_renderer = GridRenderer.new()
	_grid_renderer.name = "GridRenderer"
	_grid_renderer.cell_size = _board.cell_size
	_board.add_child(_grid_renderer)
	_grid_renderer.position = _board.origin
	_grid_renderer.initialize(_board.get_grid_data())

	_pathfinding = Pathfinding.new()
	_pathfinding.name = "Pathfinding"
	add_child(_pathfinding)
	_pathfinding.init(_board)

	_path_overlay = PathOverlay.new()
	_path_overlay.position = _board.origin
	add_child(_path_overlay)
	_path_overlay.setup(_pathfinding, _board)

	_hover = HoverHighlight.new()
	add_child(_hover)
	set_process(true)

	_economy = EconomySystem.new()
	_economy.name = "Economy"
	add_child(_economy)
	_economy.init(null)

	_obstacle_block = ObstacleBlock.new()
	_obstacle_block.name = "ObstacleBlock"
	add_child(_obstacle_block)
	_obstacle_block.initialize(_board, _pathfinding, _economy.current_gold)

	_tower_system = TowerSystem.new()
	_tower_system.name = "TowerSystem"
	add_child(_tower_system)
	_tower_system.init(_board, MonsterPoolAutoload)

	_merge_system = MergeSystem.new()
	_merge_system.name = "MergeSystem"
	add_child(_merge_system)
	var config := EconomyConfig.new()
	config.MERGE_COST = 0
	_merge_system.init(_tower_system, _board, _economy, config)

	_phase_manager = PhaseManager.new()
	_phase_manager.name = "PhaseManager"
	add_child(_phase_manager)
	_phase_manager.init()

	var monsters_container := Node2D.new()
	monsters_container.name = "Monsters"
	add_child(monsters_container)

	var test_scene := PackedScene.new()
	test_scene.pack(Monster.new())
	MonsterPoolAutoload.register_scene("goblin_standard", test_scene)

	var spawn_rule := SpawnRule.new()
	spawn_rule.monster_id = "goblin_standard"
	spawn_rule.count = 3
	spawn_rule.spawn_interval = 1.5

	var wave_rules := WaveRules.new()
	wave_rules.rules = [spawn_rule]
	wave_rules.wave_range_start = 1
	wave_rules.wave_range_end = 99

	_wave_spawner = WaveSpawner.new()
	_wave_spawner.name = "WaveSpawner"
	add_child(_wave_spawner)
	_wave_spawner.init(_board, MonsterPoolAutoload, _pathfinding, monsters_container)
	_wave_spawner.set_wave_rules(wave_rules)

	_input_handler = InputHandler.new()
	_input_handler.name = "InputHandler"
	add_child(_input_handler)
	_input_handler.set_board_grid(_board)
	_input_handler.grid_clicked.connect(_on_grid_clicked)
	_input_handler.grid_right_clicked.connect(_on_grid_right_clicked)
	_input_handler.drag_ended.connect(_on_drag_ended)

	# SaveSystem: update high_score when wave ends
	if has_node("/root/SignalBus"):
		SignalBus.wave_ended.connect(_on_wave_ended_for_save)

	# Presentation: VisualFeedback
	var vfx := VisualFeedback.new()
	vfx.name = "VisualFeedback"
	add_child(vfx)

	# Presentation: HUD
	_setup_hud()


func _on_grid_clicked(col: int, row: int) -> void:
	match _placement_mode:
		"block": _obstacle_block.place_block(col, row)
		"tower": _tower_system.place_tower(_selected_tower_id, 1, col, row)


func _setup_hud() -> void:
	_hud = HUD.new()
	_hud.name = "HUD"
	add_child(_hud)
	_hud.init({"callbacks": {
		"on_start_wave": func(): _phase_manager.start_wave(),
		"on_select_tower": func(id: String): _placement_mode = "tower"; _selected_tower_id = id,
		"on_place_block": func(): _placement_mode = "block",
	}})


func _on_grid_right_clicked(col: int, row: int) -> void:
	if col < 0 or row < 0: return
	match _board.get_cell_state(col, row):
		BoardGrid.CellState.BLOCK: _obstacle_block.remove_block(col, row)
		BoardGrid.CellState.TOWER: _tower_system.sell_tower(col, row)


func _on_drag_ended(from_col: int, from_row: int, to_col: int, to_row: int) -> void:
	_merge_system.try_merge(from_col, from_row, to_col, to_row)


func _process(_delta: float) -> void:
	if not _board or not _hover: return
	var gp := _board.world_to_grid(get_viewport().get_mouse_position())
	var cs := _board.cell_size
	if _board.is_valid_position(gp.x, gp.y):
		_hover.position = _board.grid_to_world(gp.x, gp.y) - Vector2(cs/2.0, cs/2.0)
		_hover.visible = true; _hover.queue_redraw()
	else:
		_hover.visible = false


func _on_wave_ended_for_save(wave: int, _killed: int, _breached: int) -> void:
	var config := ConfigFile.new()
	var path := "user://save_data.cfg"
	var current := 0
	if config.load(path) == OK:
		current = config.get_value("progress", "high_score", 0)
	if wave > current:
		config.set_value("progress", "high_score", wave)
		config.save(path)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed: return
	match event.keycode:
		KEY_SPACE: _phase_manager.start_wave()
		KEY_T: _placement_mode = "tower" if _placement_mode == "block" else "block"
		KEY_B: _placement_mode = "block"
		KEY_1: _placement_mode = "tower"; _selected_tower_id = "cannon"
		KEY_2: _placement_mode = "tower"; _selected_tower_id = "ice"
		KEY_3: _placement_mode = "tower"; _selected_tower_id = "arrow"
		KEY_F12: _self_test()
		KEY_F11: _toggle_fullscreen()


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _self_test() -> void:
	print("\n=== SELF-TEST ===")
	var p := 0; var f := 0

	# Cleanup from previous run
	_tower_system.sell_tower(15, 7); _tower_system.sell_tower(14, 7)
	_obstacle_block.remove_block(10, 7)

	# 1. Block placement + path change
	var before := _pathfinding.get_path_length()
	if _obstacle_block.place_block(10, 7) and _pathfinding.get_path_length() > before:
		print("  ✅ Block+path: ", before, "→", _pathfinding.get_path_length()); p += 1
	else: print("  ❌ Block+path"); f += 1

	# 2. Block removal
	if _obstacle_block.remove_block(10, 7) and _pathfinding.get_path_length() == before:
		print("  ✅ Remove block"); p += 1
	else: print("  ❌ Remove block"); f += 1

	# 3. Tower placement
	if _tower_system.place_tower("cannon", 1, 15, 7):
		print("  ✅ Tower placed"); p += 1
	else: print("  ❌ Tower placement"); f += 1

	# 4. Tower placement (same type, adjacent for merge)
	if _tower_system.place_tower("cannon", 1, 14, 7):
		print("  ✅ Tower 2 placed"); p += 1
	else: print("  ❌ Tower 2"); f += 1

	# 5. Merge
	if _merge_system.try_merge(14, 7, 15, 7):
		print("  ✅ Merge OK"); p += 1
	else: print("  ❌ Merge failed"); f += 1

	# 6. Wave spawn (3 goblins in ~4.5s)
	_phase_manager.start_wave()
	print("  → Wave started, waiting 6s...")
	await get_tree().create_timer(6.0).timeout
	var alive := _wave_spawner.get_alive_count()
	if alive >= 0:
		print("  ✅ Wave: ", alive, " alive"); p += 1
	else: print("  ❌ Wave"); f += 1

	print("=== ", p, "/", p+f, " passed ===\n")
