extends Node2D

@export var category: String = "towers"
@export var asset_key: String = "archer"
@export var frames: Array[String] = ["idle_1", "idle_2"]
@export var frame_ms: int = 220

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_update_frame()


func _process(_delta: float) -> void:
	_update_frame()


func _update_frame() -> void:
	var assets := get_node_or_null("/root/GameAssets")
	if assets == null:
		return
	var tex: Texture2D = assets.animation_frame(category, asset_key, frames, frame_ms)
	if tex != null:
		sprite.texture = tex
