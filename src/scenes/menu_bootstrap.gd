# Menu Scene — Minimal bootstrap
extends Control


func _ready() -> void:
	var label := Label.new()
	label.text = "Mazing Tower Defense"
	label.add_theme_font_size_override("font_size", 48)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchors_preset = Control.PRESET_CENTER
	add_child(label)

	var btn := Button.new()
	btn.text = "Start Game"
	btn.position = Vector2(860, 600)
	btn.size = Vector2(200, 60)
	btn.pressed.connect(_on_start)
	add_child(btn)

	var high_score_label := Label.new()
	high_score_label.name = "HighScoreLabel"
	high_score_label.text = "High Score: " + str(_load_high_score())
	high_score_label.position = Vector2(860, 680)
	high_score_label.size = Vector2(200, 30)
	high_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(high_score_label)


func _on_start() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _load_high_score() -> int:
	var config := ConfigFile.new()
	if config.load("user://save_data.cfg") == OK:
		return config.get_value("progress", "high_score", 0)
	return 0
