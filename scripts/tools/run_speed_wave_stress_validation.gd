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
	_check_speed_controls(game, result)
	_check_wave_two_stress(game, result)

	if result["ok"]:
		print("SPEED_WAVE_STRESS_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("SPEED_WAVE_STRESS_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)


func _check_speed_controls(game: Node, result: Dictionary) -> void:
	_record_check(result, "speed_starts_at_1x", game.speed_control_snapshot()["label"] == "1x", game.speed_control_snapshot())
	_record_check(result, "speed_can_pause", game.set_game_speed(0.0) and game.speed_control_snapshot()["label"] == "Paused", game.speed_control_snapshot())
	_record_check(result, "speed_can_set_2x", game.set_game_speed(2.0) and game.speed_control_snapshot()["label"] == "2x", game.speed_control_snapshot())
	_record_check(result, "speed_can_set_4x", game.set_game_speed(4.0) and game.speed_control_snapshot()["label"] == "4x", game.speed_control_snapshot())
	_record_check(result, "invalid_speed_rejected", game.set_game_speed(3.0) == false and game.speed_control_snapshot()["label"] == "4x", game.speed_control_snapshot())

	game.reset_slice()
	game.money = 1000
	_record_check(result, "place_pause_probe_tower", _place_first_valid(game, "archer"), game.snapshot())
	_record_check(result, "start_pause_probe_wave", game.start_wave(), game.snapshot())
	game.set_game_speed(0.0)
	game._process_scaled_delta(1.0)
	var paused: Dictionary = game.snapshot()
	_record_check(result, "paused_game_does_not_spawn", paused["spawned_this_wave"] == 0 and paused["enemy_count"] == 0, paused)


func _check_wave_two_stress(game: Node, result: Dictionary) -> void:
	game.reset_slice()
	game.money = 1000
	var tower_types := ["archer", "machine_gun", "cannon", "sniper", "tesla"]
	for tower_type in tower_types:
		_record_check(result, "place_%s_for_stress" % tower_type, _place_first_valid(game, tower_type), game.snapshot())
	_record_check(result, "stress_has_multiple_towers", game.snapshot()["tower_count"] >= 4, game.snapshot())

	_record_check(result, "stress_wave_1_starts", game.start_wave(), game.snapshot())
	_record_check(result, "stress_wave_1_completes", _run_until_wave_complete(game, 1, 2600), game.snapshot())
	_record_check(result, "stress_wave_2_starts", game.start_wave(), game.snapshot())
	var wave_two: Dictionary = game.snapshot()
	_record_check(result, "stress_wave_2_loaded", wave_two["wave"] == 2 and wave_two["spawn_limit"] == 16 and wave_two["enemy_family"] == "swarm", wave_two)
	_record_check(result, "stress_wave_2_completes", _run_until_wave_complete(game, 2, 3200), game.snapshot())
	var complete: Dictionary = game.snapshot()
	_record_check(result, "stress_wave_2_resolved_cleanly", complete["wave"] == 2 and complete["wave_complete"] == true and complete["enemy_count"] == 0 and complete["projectile_count"] == 0 and complete["kills"] + complete["leaks"] == complete["spawn_limit"], complete)
	_record_check(result, "stress_wave_3_starts_after_wave_2", game.start_wave() and game.snapshot()["wave"] == 3, game.snapshot())


func _run_until_wave_complete(game: Node, expected_wave: int, max_steps: int) -> bool:
	var speed_cycle := [1.0, 2.0, 4.0]
	for step in range(max_steps):
		game.set_game_speed(float(speed_cycle[step % speed_cycle.size()]))
		game._process_scaled_delta(0.05)
		var snapshot: Dictionary = game.snapshot()
		if int(snapshot["wave"]) != expected_wave:
			return false
		if bool(snapshot["wave_complete"]):
			return true
	return false


func _place_first_valid(game: Node, tower_type: String) -> bool:
	if not game.select_shop_tower(tower_type):
		return false
	for y in range(108, 570, 27):
		for x in range(54, 864, 27):
			var site := Vector2(float(x), float(y))
			if game.can_place_tower(site):
				return game.place_selected_tower(site, tower_type)
	return false


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	ValidationHarness.record_check(result, label, passed, detail)
