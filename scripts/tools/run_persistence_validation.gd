extends SceneTree


func _initialize() -> void:
	var config_script := load("res://scripts/autoload/game_config.gd")
	var data_script := load("res://scripts/autoload/game_data.gd")
	var assets_script := load("res://scripts/autoload/game_assets.gd")
	var audio_script := load("res://scripts/autoload/game_audio.gd")
	var progress_script := load("res://scripts/autoload/game_progress.gd")
	var slice_script := load("res://scripts/game/vertical_slice_game.gd")

	var config: Node = _root_node_or_new("GameConfig", config_script)
	var data_loader: Node = _root_node_or_new("GameData", data_script)
	var assets: Node = _root_node_or_new("GameAssets", assets_script)
	var audio: Node = _root_node_or_new("GameAudio", audio_script)
	var progress: Node = _root_node_or_new("GameProgress", progress_script)
	var game: Node = slice_script.new()
	root.add_child(game)
	game.name = "VerticalSliceGame"
	game.progress_override = progress
	assets.load_manifest()

	var save_path := "res://.godot/migration_persistence_validation_%s.json" % Time.get_ticks_usec()
	var result: Dictionary = {
		"ok": true,
		"checks": [],
		"errors": [],
	}

	_check_progression_parity(progress, result)
	_check_save_load_and_run_state(progress, game, save_path, result)
	_check_scene_reload(result)
	_cleanup_save(save_path)

	if result["ok"]:
		print("PERSISTENCE_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("PERSISTENCE_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)


func _check_progression_parity(progress: Node, result: Dictionary) -> void:
	progress.reset_progression()
	progress.stars = 5
	for skill_key in ["money", "damage", "research", "intel", "shield"]:
		_record_check(result, "buy_%s_upgrade" % skill_key, progress.buy_skill_upgrade(skill_key), progress.progression_state())
	var defaults: Dictionary = progress.new_run_defaults()
	_record_check(result, "progression_spends_five_stars", progress.stars == 0, progress.progression_state())
	_record_check(result, "starting_money_bonus_matches_game_data", defaults["money"] == 200, defaults)
	_record_check(result, "starting_lives_bonus_matches_game_data", defaults["lives"] == 27, defaults)
	_record_check(result, "starting_research_bonus_matches_game_data", defaults["research_points"] == 2, defaults)
	_record_check(result, "tower_damage_bonus_matches_game_data", is_equal_approx(float(defaults["tower_damage_multiplier"]), 1.05), defaults)
	progress.starting_reward_choice_bonus_level = 6
	_record_check(result, "intel_cost_maxes_at_level_six", progress.skill_upgrade_cost("intel") == null, progress.skill_upgrade_details("intel"))
	_record_check(result, "intel_max_copy_matches_game_data", progress.skill_upgrade_details("intel") == ["Wave Intel", "Lv 6 | MAX"], progress.skill_upgrade_details("intel"))


func _check_save_load_and_run_state(progress: Node, game: Node, save_path: String, result: Dictionary) -> void:
	progress.reset_progression()
	progress.stars = 3
	progress.starting_money_bonus_level = 1
	progress.starting_research_bonus_level = 1
	progress.starting_lives_bonus_level = 1
	progress.tower_damage_bonus_level = 1
	progress.settings["game_speed"] = 1.5

	game.reset_slice()
	var starting: Dictionary = game.snapshot()
	_record_check(result, "run_defaults_apply_to_money", starting["money"] == 200, starting)
	_record_check(result, "run_defaults_apply_to_lives", starting["lives"] == 27, starting)
	_record_check(result, "run_defaults_apply_to_research", starting["research_points"] == 2, starting)
	_record_check(result, "place_progressed_archer", game.place_archer(game.RECOMMENDED_BUILD_SITE), game.snapshot())
	var placed_tower: Dictionary = game.towers[0] if game.towers.size() > 0 else {}
	_record_check(result, "progressed_archer_starts_level_one", int(placed_tower.get("level", 0)) == 1, placed_tower)
	var expected_damage: float = game._basic_slice_tower_damage("archer", 1) * float(progress.new_run_defaults().get("tower_damage_multiplier", 1.0))
	_record_check(result, "progressed_damage_applies", is_equal_approx(float(placed_tower.get("damage", 0.0)), expected_damage), {"tower": placed_tower, "expected_damage": expected_damage})
	_record_check(result, "start_progressed_run", game.start_wave(), game.snapshot())
	for _step in range(20):
		game.process_step(0.05)

	var run_state: Dictionary = game.serialize_run_state()
	_record_check(result, "run_state_has_tower", run_state["towers"].size() == 1, run_state)
	_record_check(result, "temp_save_path_is_new", not FileAccess.file_exists(save_path), save_path)
	var saved: bool = progress.save_to_path(save_path, run_state, false)
	_record_check(result, "save_creates_temp_profile", saved, {"path": save_path, "error": progress.last_save_error, "global": ProjectSettings.globalize_path(save_path)})
	_record_check(result, "save_refuses_overwrite_without_flag", not progress.save_to_path(save_path, run_state, false), save_path)

	var progress_script := load("res://scripts/autoload/game_progress.gd")
	var loaded_progress: Node = progress_script.new()
	root.add_child(loaded_progress)
	loaded_progress.name = "LoadedGameProgress"
	_record_check(result, "load_reads_temp_profile", loaded_progress.load_from_path(save_path), loaded_progress.payload())
	_record_check(result, "loaded_progression_matches", loaded_progress.progression_state() == progress.progression_state(), loaded_progress.progression_state())
	_record_check(result, "loaded_settings_match", loaded_progress.settings["game_speed"] == 1.5, loaded_progress.settings)
	_record_check(result, "loaded_run_state_present", not loaded_progress.last_run_state.is_empty(), loaded_progress.last_run_state)

	var slice_script := load("res://scripts/game/vertical_slice_game.gd")
	var restored_game: Node = slice_script.new()
	root.add_child(restored_game)
	restored_game.name = "RestoredVerticalSliceGame"
	restored_game.progress_override = loaded_progress
	_record_check(result, "restore_run_state_accepts_payload", restored_game.restore_run_state(loaded_progress.last_run_state), restored_game.snapshot())
	var restored: Dictionary = restored_game.snapshot()
	var original: Dictionary = game.snapshot()
	_record_check(result, "restored_money_matches", restored["money"] == original["money"], {"restored": restored, "original": original})
	_record_check(result, "restored_wave_state_matches", restored["wave_active"] == original["wave_active"] and restored["spawned_this_wave"] == original["spawned_this_wave"], {"restored": restored, "original": original})
	_record_check(result, "restored_entity_counts_match", restored["tower_count"] == original["tower_count"] and restored["enemy_count"] == original["enemy_count"] and restored["projectile_count"] == original["projectile_count"], {"restored": restored, "original": original})
	restored_game.process_step(0.05)
	_record_check(result, "restored_run_survives_process_step", restored_game.snapshot()["lives"] > 0, restored_game.snapshot())


func _check_scene_reload(result: Dictionary) -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_record_check(result, "main_scene_loads", scene != null, scene)
	if scene == null:
		return
	var first := scene.instantiate()
	root.add_child(first)
	_record_check(result, "main_scene_has_vertical_slice", first.get_node_or_null("VerticalSliceGame") != null, first.get_children().map(func(child): return child.name))
	root.remove_child(first)
	first.queue_free()
	var second := scene.instantiate()
	root.add_child(second)
	_record_check(result, "main_scene_reload_has_vertical_slice", second.get_node_or_null("VerticalSliceGame") != null, second.get_children().map(func(child): return child.name))
	root.remove_child(second)
	second.queue_free()


func _cleanup_save(save_path: String) -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _root_node_or_new(node_name: String, script: Script) -> Node:
	var existing := root.get_node_or_null(node_name)
	if existing != null:
		return existing
	var node: Node = script.new()
	root.add_child(node)
	node.name = node_name
	return node


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	result["checks"].append({
		"label": label,
		"passed": passed,
		"detail": detail,
	})
	if not passed:
		result["ok"] = false
		result["errors"].append("%s failed: %s" % [label, str(detail)])
