extends SceneTree


func _initialize() -> void:
	var config_script := load("res://scripts/autoload/game_config.gd")
	var data_script := load("res://scripts/autoload/game_data.gd")
	var config: Node = config_script.new()
	var data_loader: Node = data_script.new()
	root.add_child(config)
	root.add_child(data_loader)
	config.name = "GameConfig"
	data_loader.name = "GameData"

	var result: Dictionary = data_loader.validate_baseline()
	if result["ok"]:
		print("DATA_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("DATA_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)
