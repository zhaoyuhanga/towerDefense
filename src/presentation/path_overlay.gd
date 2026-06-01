class_name PathOverlay
extends Node2D
## Draws the monster path as a visible gold line

var _pathfinding: Pathfinding
var _board: BoardGrid

func setup(pf: Pathfinding, b: BoardGrid) -> void:
	_pathfinding = pf; _board = b
	if has_node("/root/SignalBus"):
		SignalBus.path_updated.connect(func(_p): queue_redraw())
		SignalBus.path_blocked.connect(func(): queue_redraw())
	queue_redraw()

func _draw() -> void:
	if not _pathfinding or not _board: return
	var path := _pathfinding.get_main_path()
	if path.is_empty(): return
	var pts: PackedVector2Array = []
	for gp in path: pts.append(_board.grid_to_world(gp.x, gp.y) - position)
	if pts.size() < 2: return
	draw_polyline(pts, Color(1,0.85,0.3,0.3), 6)
	draw_polyline(pts, Color(1,0.85,0.3,0.8), 2)
