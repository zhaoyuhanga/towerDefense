class_name HoverHighlight
extends Node2D
## Draws a highlight rect under the mouse cursor

func _draw() -> void:
	draw_rect(Rect2(0,0,56,56), Color(1,1,1,0.12), true)
	draw_rect(Rect2(0,0,56,56), Color(1,0.85,0.3,0.4), false, 2)
