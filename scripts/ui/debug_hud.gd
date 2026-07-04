extends CanvasLayer

var status := {}
var label: Label


func _ready() -> void:
	label = Label.new()
	label.name = "StatusLabel"
	label.position = Vector2(16, 14)
	label.add_theme_font_size_override("font_size", 16)
	add_child(label)
	_refresh()


func set_status(next_status: Dictionary) -> void:
	status = next_status.duplicate()
	_refresh()


func _refresh() -> void:
	if label == null:
		return
	var lines := [
		status.get("title", GameConfig.GAME_TITLE),
		"Godot %s" % status.get("version", GameConfig.GODOT_VERSION_PIN),
		"Phase: %s" % status.get("phase", "project shell"),
		"Gameplay: %s" % status.get("gameplay", "not ported"),
	]
	label.text = "\n".join(lines)
