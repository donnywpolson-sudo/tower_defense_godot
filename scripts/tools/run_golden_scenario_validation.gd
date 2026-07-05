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
	_check_opening_wave_golden(game, result)
	_check_upgrade_restore_mid_combat_golden(game, slice_script, result)

	if result["ok"]:
		print("GOLDEN_SCENARIO_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("GOLDEN_SCENARIO_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)


func _check_opening_wave_golden(game: Node, result: Dictionary) -> void:
	game.reset_slice()
	_record_check(result, "opening_place_archer", game.place_archer(Vector2(300, 243)), game.snapshot())
	_record_check(result, "opening_start_wave", game.start_wave(), game.snapshot())
	_run_until_wave_complete(game, 1600)
	var wave_one: Dictionary = game.snapshot()
	_record_check(result, "opening_wave_1_fixed_outcome", wave_one["wave"] == 1 and wave_one["wave_complete"] == true and wave_one["spawned_this_wave"] == 11 and wave_one["kills"] == 10 and wave_one["leaks"] == 1 and wave_one["money"] == 175 and wave_one["lives"] == 24 and wave_one["research_points"] == 1, wave_one)
	_record_check(result, "opening_wave_1_rewards_fixed", wave_one["wave_reward_money"] == 10 and wave_one["wave_reward_research"] == 1, wave_one)
	_record_check(result, "opening_wave_1_has_no_invariant_failures", game.runtime_invariant_failures().is_empty(), game.runtime_invariant_failures())

	_record_check(result, "opening_start_wave_2", game.start_wave(), game.snapshot())
	_run_until_wave_complete(game, 2200)
	var wave_two: Dictionary = game.snapshot()
	_record_check(result, "opening_wave_2_fixed_outcome", wave_two["wave"] == 2 and wave_two["wave_complete"] == true and wave_two["enemy_family"] == "swarm" and wave_two["spawned_this_wave"] == 16 and wave_two["kills"] == 16 and wave_two["leaks"] == 0 and wave_two["money"] == 250 and wave_two["lives"] == 24 and wave_two["research_points"] == 2, wave_two)
	_record_check(result, "opening_wave_2_has_no_invariant_failures", game.runtime_invariant_failures().is_empty(), game.runtime_invariant_failures())


func _check_upgrade_restore_mid_combat_golden(game: Node, slice_script: Script, result: Dictionary) -> void:
	game.reset_slice()
	game.money = 1000
	_record_check(result, "upgrade_restore_place_archer", game.place_archer(Vector2(300, 243)), game.snapshot())
	_record_check(result, "upgrade_restore_first_upgrade", game.upgrade_selected_tower(), _selected_tower_state(game))
	var branch_options: Array = game.upgrade_panel_snapshot().get("branch_options", [])
	var branch_id := str(branch_options[0].get("id", "")) if not branch_options.is_empty() else ""
	_record_check(result, "upgrade_restore_branch_available", not branch_id.is_empty(), game.upgrade_panel_snapshot())
	if not branch_id.is_empty():
		_record_check(result, "upgrade_restore_choose_branch", game.choose_selected_tower_branch(branch_id), game.upgrade_panel_snapshot())
	_record_check(result, "upgrade_restore_second_upgrade", game.upgrade_selected_tower(), _selected_tower_state(game))
	var tower_state: Dictionary = _selected_tower_state(game)
	_record_check(result, "upgrade_restore_tower_reaches_level_3", int(tower_state.get("level", 0)) == 3 and str(tower_state.get("selected_branch", "")) == branch_id, tower_state)
	_record_check(result, "upgrade_restore_start_wave", game.start_wave(), game.snapshot())
	for _step in range(40):
		game.process_step(0.05)

	var original: Dictionary = game.snapshot()
	var run_state: Dictionary = game.serialize_run_state()
	_record_check(result, "upgrade_restore_mid_combat_state_has_entities", original["wave_active"] == true and original["tower_count"] == 1 and original["enemy_count"] > 0, original)
	_record_check(result, "upgrade_restore_state_has_no_invariant_failures", game.runtime_invariant_failures().is_empty(), game.runtime_invariant_failures())

	var restored_game: Node = slice_script.new()
	root.add_child(restored_game)
	restored_game.name = "GoldenScenarioRestoredGame"
	_record_check(result, "upgrade_restore_accepts_state", restored_game.restore_run_state(run_state), restored_game.snapshot())
	var restored: Dictionary = restored_game.snapshot()
	_record_check(result, "upgrade_restore_counts_match", restored["money"] == original["money"] and restored["lives"] == original["lives"] and restored["wave"] == original["wave"] and restored["wave_active"] == original["wave_active"] and restored["tower_count"] == original["tower_count"] and restored["enemy_count"] == original["enemy_count"], {"original": original, "restored": restored})
	_record_check(result, "upgrade_restore_projectiles_match", restored["projectile_count"] == original["projectile_count"], {"original": original, "restored": restored})
	_record_check(result, "upgrade_restore_restored_has_no_invariant_failures", restored_game.runtime_invariant_failures().is_empty(), restored_game.runtime_invariant_failures())
	restored_game.process_step(0.05)
	_record_check(result, "upgrade_restore_restored_can_continue", restored_game.snapshot()["wave_active"] == true and restored_game.snapshot()["lives"] > 0, restored_game.snapshot())


func _run_until_wave_complete(game: Node, max_steps: int) -> void:
	for _step in range(max_steps):
		if bool(game.snapshot().get("wave_complete", false)):
			return
		game.process_step(0.05)


func _selected_tower_state(game: Node) -> Dictionary:
	var state: Dictionary = game.serialize_run_state()
	var towers: Array = state.get("towers", [])
	return towers[0] if not towers.is_empty() else {}


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	result["checks"].append({
		"label": label,
		"passed": passed,
		"detail": detail,
	})
	if not passed:
		result["ok"] = false
		result["errors"].append("%s failed: %s" % [label, str(detail)])
