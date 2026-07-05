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
	var initial_wave_control: Dictionary = game.wave_control_snapshot()
	_record_check(result, "start_without_tower_has_disabled_reason", bool(initial_wave_control.get("enabled", true)) == false and not str(initial_wave_control.get("disabled_reason", "")).is_empty(), initial_wave_control)
	_record_check(result, "start_without_tower_sets_feedback", game.start_wave() == false and not str(game.snapshot().get("latest_feedback", {}).get("message", "")).is_empty(), game.snapshot())
	_record_check(result, "place_archer", game.place_archer(Vector2(300, 243)), game.snapshot())
	_record_check(result, "start_wave_button_enabled", bool(game.wave_control_snapshot().get("enabled", false)) and str(game.wave_control_snapshot().get("label", "")).contains("Start Wave 1"), game.wave_control_snapshot())
	_record_check(result, "click_start_wave_button", _click_start_wave_button(game), game.snapshot())
	for _step in range(1600):
		if game.snapshot().get("wave_complete", false):
			break
		game.process_step(0.05)
	var snapshot: Dictionary = game.snapshot()
	_record_check(result, "wave_complete", snapshot["wave_complete"] == true, snapshot)
	_record_check(result, "spawn_limit_matches_game_data_wave_1", snapshot["spawn_limit"] == 11 and snapshot["game_data_regular_enemy_count"] == 11, snapshot)
	_record_check(result, "spawned_game_data_regular_count", snapshot["spawned_this_wave"] == snapshot["spawn_limit"], snapshot)
	_record_check(result, "kills_or_leaks_resolve_wave", snapshot["kills"] + snapshot["leaks"] == snapshot["spawn_limit"], snapshot)
	_record_check(result, "reward_money_matches_classic_wave_1", snapshot["wave_reward_money"] == 10, snapshot)
	_record_check(result, "reward_research_matches_wave_1", snapshot["wave_reward_research"] == 1, snapshot)
	_record_check(result, "money_keeps_wave_reward_after_build", snapshot["money"] >= GameConfig.STARTING_MONEY - 50 + snapshot["wave_reward_money"], snapshot)
	_record_check(result, "next_wave_button_enabled", bool(game.wave_control_snapshot().get("enabled", false)) and str(game.wave_control_snapshot().get("label", "")).contains("Start Wave 2"), game.wave_control_snapshot())
	_record_check(result, "start_wave_advances_after_completion", _click_start_wave_button(game), game.snapshot())
	var wave_two: Dictionary = game.snapshot()
	_record_check(result, "wave_2_schedule_loaded", wave_two["wave"] == 2 and wave_two["wave_active"] == true and wave_two["spawn_limit"] == 16 and wave_two["enemy_family"] == "swarm" and is_equal_approx(float(wave_two["spawn_interval"]), 0.596), wave_two)
	for _step in range(2200):
		if game.snapshot().get("wave_complete", false):
			break
		game.process_step(0.05)
	var wave_two_complete: Dictionary = game.snapshot()
	_record_check(result, "wave_2_completes_regular_count", wave_two_complete["wave"] == 2 and wave_two_complete["wave_complete"] == true and wave_two_complete["spawned_this_wave"] == 16 and wave_two_complete["kills"] + wave_two_complete["leaks"] == 16, wave_two_complete)
	_record_check(result, "start_wave_advances_to_wave_3", _click_start_wave_button(game), game.snapshot())
	var wave_three: Dictionary = game.snapshot()
	_record_check(result, "wave_3_schedule_loaded", wave_three["wave"] == 3 and wave_three["wave_active"] == true and wave_three["spawn_limit"] == 19 and wave_three["enemy_family"] == "fast" and is_equal_approx(float(wave_three["spawn_interval"]), 0.584), wave_three)
	_check_lives_never_go_negative(game, result)

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


func _click_start_wave_button(game: Node) -> bool:
	var rect: Rect2 = game.get_start_wave_button_rect()
	return game.handle_wave_control_click(rect.get_center())


func _check_lives_never_go_negative(game: Node, result: Dictionary) -> void:
	game.reset_slice()
	game.lives = 1
	game.spawn_regular_wave_for_test(1)
	game.wave_active = true
	for enemy in game.enemies:
		enemy["target_index"] = 999
	game.process_step(0.05)
	var snapshot: Dictionary = game.snapshot()
	_record_check(result, "final_leak_triggers_game_over", snapshot["lives"] == 0 and snapshot["game_over"] == true and snapshot["wave_active"] == false and snapshot["enemy_count"] == 0, snapshot)
	_record_check(result, "game_over_blocks_wave_start", game.start_wave() == false, game.snapshot())
	var restart_rect: Rect2 = game.get_game_over_restart_rect()
	_record_check(result, "game_over_restart_resets_run", game.handle_game_over_click(restart_rect.get_center()) and game.snapshot()["game_over"] == false and game.snapshot()["lives"] > 0, game.snapshot())
