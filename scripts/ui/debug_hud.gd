extends CanvasLayer

var status := {}
var label: Label
var debug_label: Label


func _ready() -> void:
	_ensure_labels()
	_refresh()


func set_status(next_status: Dictionary) -> void:
	status = next_status.duplicate()
	_refresh()


func _refresh() -> void:
	_ensure_labels()
	label.text = "%s / %s" % [
		status.get("title", GameConfig.GAME_TITLE),
		status.get("phase", "project shell"),
	]
	var debug_value: Variant = status.get("debug_overlay", {})
	var debug: Dictionary = debug_value if debug_value is Dictionary else {}
	debug_label.visible = bool(debug.get("enabled", false))
	if not debug_label.visible:
		debug_label.text = ""
		return
	var economy_value: Variant = debug.get("economy", {})
	var wave_value: Variant = debug.get("wave", {})
	var economy: Dictionary = economy_value if economy_value is Dictionary else {}
	var wave: Dictionary = wave_value if wave_value is Dictionary else {}
	var towers: Array = debug.get("towers", []) if debug.get("towers", []) is Array else []
	var enemies: Array = debug.get("enemies", []) if debug.get("enemies", []) is Array else []
	var projectiles: Array = debug.get("projectiles", []) if debug.get("projectiles", []) is Array else []
	debug_label.text = "DBG W%s %s/%s | $%s L%s R%s | T/E/P %s/%s/%s" % [
		wave.get("wave", "?"),
		wave.get("spawned_this_wave", "?"),
		wave.get("spawn_limit", "?"),
		economy.get("money", "?"),
		economy.get("lives", "?"),
		economy.get("research_points", "?"),
		towers.size(),
		enemies.size(),
		projectiles.size(),
	]


func _ensure_labels() -> void:
	if label == null:
		label = Label.new()
		label.name = "StatusLabel"
		label.position = Vector2(float(GameConfig.MAP_WIDTH) + 18.0, 18.0)
		label.add_theme_font_size_override("font_size", 11)
		label.modulate = Color(0.78, 0.82, 0.76, 0.72)
		add_child(label)
	if debug_label == null:
		debug_label = Label.new()
		debug_label.name = "DebugLabel"
		debug_label.position = Vector2(float(GameConfig.MAP_WIDTH) + 18.0, 36.0)
		debug_label.add_theme_font_size_override("font_size", 10)
		debug_label.modulate = Color(0.68, 0.86, 0.92, 0.82)
		add_child(debug_label)
