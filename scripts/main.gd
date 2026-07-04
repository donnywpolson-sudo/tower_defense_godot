extends Node2D

@onready var debug_hud: CanvasLayer = $DebugHUD


func _ready() -> void:
	if debug_hud.has_method("set_status"):
		debug_hud.set_status({
			"title": GameConfig.GAME_TITLE,
			"version": GameConfig.GODOT_VERSION_PIN,
			"phase": "project shell",
			"gameplay": "not ported",
		})
