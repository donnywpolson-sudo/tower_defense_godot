extends SceneTree


func _initialize() -> void:
	var config_script := load("res://scripts/autoload/game_config.gd")
	var data_script := load("res://scripts/autoload/game_data.gd")
	var slice_script := load("res://scripts/game/vertical_slice_game.gd")
	var config: Node = config_script.new()
	var data_loader: Node = data_script.new()
	var game: Node = slice_script.new()
	root.add_child(config)
	root.add_child(data_loader)
	root.add_child(game)
	config.name = "GameConfig"
	data_loader.name = "GameData"
	game.name = "VerticalSliceGame"
	game.reset_slice()

	var result: Dictionary = {
		"ok": true,
		"checks": [],
		"errors": [],
	}
	_record_check(result, "place_archer", game.place_archer(Vector2(300, 243)), game.snapshot())
	_record_check(result, "start_wave", game.start_wave(), game.snapshot())
	for _step in range(1600):
		if game.snapshot().get("wave_complete", false):
			break
		game.process_step(0.05)
	var snapshot: Dictionary = game.snapshot()
	_record_check(result, "wave_complete", snapshot["wave_complete"] == true, snapshot)
	_record_check(result, "spawn_limit", snapshot["spawned_this_wave"] == snapshot["slice_spawn_limit"], snapshot)
	_record_check(result, "kills_or_leaks_resolve_wave", snapshot["kills"] + snapshot["leaks"] == snapshot["slice_spawn_limit"], snapshot)
	_record_check(result, "reward_money_matches_classic_wave_1", snapshot["wave_reward_money"] == 10, snapshot)
	_record_check(result, "reward_research_matches_wave_1", snapshot["wave_reward_research"] == 1, snapshot)
	_record_check(result, "money_changed_from_start", snapshot["money"] != GameConfig.STARTING_MONEY, snapshot)

	if result["ok"]:
		print("VERTICAL_SLICE_SMOKE_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("VERTICAL_SLICE_SMOKE_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	result["checks"].append({
		"label": label,
		"passed": passed,
		"detail": detail,
	})
	if not passed:
		result["ok"] = false
		result["errors"].append("%s failed: %s" % [label, str(detail)])
