extends Node2D

@onready var debug_hud: CanvasLayer = $DebugHUD
@onready var vertical_slice_game: Node2D = $VerticalSliceGame


func _ready() -> void:
	if debug_hud.has_method("set_status"):
		debug_hud.set_status({
			"title": GameConfig.GAME_TITLE,
			"version": GameConfig.GODOT_VERSION_PIN,
			"phase": "vertical slice",
			"gameplay": "Classic Road / Archer / Normal packets",
		})
	if vertical_slice_game.has_signal("status_changed"):
		vertical_slice_game.status_changed.connect(_on_vertical_slice_status_changed)


func _on_vertical_slice_status_changed(status: Dictionary) -> void:
	if debug_hud.has_method("set_status"):
		debug_hud.set_status(status)
