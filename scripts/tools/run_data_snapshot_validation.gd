extends SceneTree


func _initialize() -> void:
	var config: Node = load("res://scripts/autoload/game_config.gd").new()
	var data_loader: Node = load("res://scripts/autoload/game_data.gd").new()
	root.add_child(config)
	root.add_child(data_loader)
	config.name = "GameConfig"
	data_loader.name = "GameData"
	var result: Dictionary = data_loader.validate_content_snapshot()
	if bool(result.get("ok", false)):
		print("DATA_SNAPSHOT_VALIDATION_OK")
		quit(0)
		return
	for error in result.get("errors", []):
		push_error(error)
	quit(1)
