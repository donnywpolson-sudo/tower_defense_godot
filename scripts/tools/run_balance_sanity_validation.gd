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

	var result: Dictionary = data_loader.validate_balance_sanity()
	if result["ok"]:
		print("BALANCE_SANITY_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		for warning in result.get("warnings", []):
			print("  WARN %s" % str(warning))
		quit(0)
	else:
		push_error("BALANCE_SANITY_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		for warning in result.get("warnings", []):
			print("  WARN %s" % str(warning))
		quit(1)
