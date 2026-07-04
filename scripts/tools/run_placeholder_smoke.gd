extends SceneTree


func _initialize() -> void:
	var config_script := load("res://scripts/autoload/game_config.gd")
	var harness_script := load("res://scripts/autoload/parity_harness.gd")
	var config: Node = config_script.new()
	var harness: Node = harness_script.new()
	root.add_child(config)
	root.add_child(harness)
	config.name = "GameConfig"
	harness.name = "ParityHarness"

	var result: Dictionary = harness.run_placeholder_scene_smoke()
	if result["ok"]:
		print("PLACEHOLDER_SMOKE_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("PLACEHOLDER_SMOKE_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)
