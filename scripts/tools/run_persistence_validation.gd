extends SceneTree

const VALIDATION_HARNESS = preload("res://scripts/tools/validation_harness.gd")


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

	var save_path := "user://migration_persistence_validation_%s.json" % Time.get_ticks_usec()
	var result: Dictionary = VALIDATION_HARNESS.new_result()

	_check_progression_parity(progress, result)
	_check_save_load_and_run_state(progress, game, save_path, result)
	_check_atomic_recovery(progress, game.serialize_run_state(), save_path, result)
	_check_split_wave_run_state_restore(game, result)
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
	progress.settings["game_speed"] = 2.0

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
	var poison_enemy: Dictionary = game.create_enemy("normal", 1, Vector2(180, 100), 1)
	poison_enemy["hp"] = 200.0
	poison_enemy["max_hp"] = 200.0
	poison_enemy["poison_stacks"] = 2
	poison_enemy["poison_timer"] = 2.5
	poison_enemy["poison_tick_timer"] = 0.25
	poison_enemy["poison_damage"] = 3.0
	poison_enemy["poison_regen_multiplier"] = 0.5
	poison_enemy["poison_source_tower_id"] = int(game.towers[0].get("tower_id", -1))
	poison_enemy["wildfire_burn_timer"] = 1.2
	poison_enemy["wildfire_burn_tick_timer"] = 0.25
	poison_enemy["wildfire_burn_damage"] = 1.5
	poison_enemy["wildfire_burn_source_tower_id"] = int(game.towers[0].get("tower_id", -1))
	game.enemies = [poison_enemy]
	run_state = game.serialize_run_state()
	_record_check(result, "run_state_preserves_poison_fields", int(run_state["enemies"][0].get("poison_stacks", 0)) == 2 and is_equal_approx(float(run_state["enemies"][0].get("poison_damage", 0.0)), 3.0) and is_equal_approx(float(run_state["enemies"][0].get("wildfire_burn_damage", 0.0)), 1.5), run_state["enemies"][0])
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
	_record_check(result, "loaded_settings_match", loaded_progress.settings["game_speed"] == 2.0, loaded_progress.settings)
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
	var restored_poison_enemy: Dictionary = restored_game.enemies[0] if restored_game.enemies.size() > 0 else {}
	_record_check(result, "restored_poison_fields_match", int(restored_poison_enemy.get("poison_stacks", 0)) == 2 and is_equal_approx(float(restored_poison_enemy.get("poison_damage", 0.0)), 3.0) and is_equal_approx(float(restored_poison_enemy.get("wildfire_burn_damage", 0.0)), 1.5), restored_poison_enemy)
	restored_game.process_step(0.05)
	_record_check(result, "restored_run_survives_process_step", restored_game.snapshot()["lives"] > 0, restored_game.snapshot())


func _check_atomic_recovery(progress: Node, baseline_run_state: Dictionary, save_path: String, result: Dictionary) -> void:
	var temp_path: String = progress.temporary_save_path(save_path)
	var canonical_before := FileAccess.get_file_as_string(save_path)
	var baseline_enemy_count: int = baseline_run_state.get("enemies", []).size()
	var baseline_tower_count: int = baseline_run_state.get("towers", []).size()
	_cleanup_artifact(temp_path)
	var blocked_created := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(temp_path)) == OK
	_record_check(result, "interrupted_save_temp_block_created", blocked_created, temp_path)
	var interrupted_saved: bool = progress.save_to_path(save_path, {"recovery_case": "interrupted"}, true)
	_record_check(result, "interrupted_save_fails_closed", not interrupted_saved, {"error": progress.last_save_error, "path": temp_path})
	_record_check(result, "interrupted_save_keeps_canonical_bytes", FileAccess.get_file_as_string(save_path) == canonical_before, save_path)
	var prior_loadable: bool = progress.load_from_path(save_path)
	var prior_run_state: Dictionary = progress.last_run_state
	_record_check(result, "interrupted_save_keeps_prior_payload_loadable", prior_loadable and prior_run_state.get("enemies", []).size() == baseline_enemy_count and prior_run_state.get("towers", []).size() == baseline_tower_count, prior_run_state)
	_cleanup_artifact(temp_path)

	_record_check(result, "malformed_temp_fixture_created", _write_text(temp_path, "{\"schema_version\":1"), temp_path)
	var malformed_saved: bool = progress.save_to_path(save_path, {"recovery_case": "malformed"}, true)
	_record_check(result, "malformed_temp_commit_succeeds", malformed_saved, {"error": progress.last_save_error})
	_record_check(result, "malformed_temp_is_removed_after_commit", not FileAccess.file_exists(temp_path), temp_path)
	_record_check(result, "malformed_temp_commit_loads_new_payload", progress.load_from_path(save_path) and str(progress.last_run_state.get("recovery_case", "")) == "malformed", progress.last_run_state)

	_record_check(result, "partial_temp_fixture_created", _write_text(temp_path, "{\"schema_version\":1,\"progression\":"), temp_path)
	var partial_saved: bool = progress.save_to_path(save_path, {"recovery_case": "partial"}, true)
	_record_check(result, "partial_temp_commit_succeeds", partial_saved, {"error": progress.last_save_error})
	_record_check(result, "partial_temp_is_removed_after_commit", not FileAccess.file_exists(temp_path), temp_path)
	_record_check(result, "partial_temp_commit_loads_new_payload", progress.load_from_path(save_path) and str(progress.last_run_state.get("recovery_case", "")) == "partial", progress.last_run_state)


func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func _cleanup_artifact(path: String) -> void:
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())


func _check_split_wave_run_state_restore(game: Node, result: Dictionary) -> void:
	var split_wave: int = _find_split_wave(game)
	_record_check(result, "persistence_split_wave_exists", split_wave > 0, {"split_wave": split_wave})
	if split_wave <= 0:
		return
	var active_setup: Dictionary = _prepare_active_split_child(game, split_wave)
	_record_check(result, "persistence_active_split_child_setup", bool(active_setup.get("ok", false)), active_setup)
	if not bool(active_setup.get("ok", false)):
		return
	var active_restored: Node = _restored_game_from_state(game.serialize_run_state())
	_record_check(result, "active_split_restore_accepts_state", active_restored != null, active_setup)
	if active_restored == null:
		return
	var active_snapshot: Dictionary = active_restored.snapshot()
	_record_check(result, "active_split_extra_counter_roundtrip", int(active_snapshot.get("spawned_extra_this_wave", -1)) == int(game.snapshot().get("spawned_extra_this_wave", -2)), {"restored": active_snapshot, "original": game.snapshot()})
	_record_check(result, "active_split_child_roundtrip", int(active_snapshot.get("enemy_count", 0)) == int(game.snapshot().get("enemy_count", -1)), {"restored": active_snapshot, "original": game.snapshot()})

	var completed_setup: Dictionary = _complete_active_split_child(game)
	_record_check(result, "persistence_completed_split_child_setup", bool(completed_setup.get("ok", false)), completed_setup)
	if not bool(completed_setup.get("ok", false)):
		return
	var completed_restored: Node = _restored_game_from_state(game.serialize_run_state())
	_record_check(result, "completed_split_restore_accepts_state", completed_restored != null, completed_setup)
	if completed_restored == null:
		return
	var completed_snapshot: Dictionary = completed_restored.snapshot()
	_record_check(result, "completed_split_restore_resolution_consistent", int(completed_snapshot.get("kills", 0)) + int(completed_snapshot.get("leaks", 0)) == int(completed_snapshot.get("spawned_total_this_wave", -1)), completed_snapshot)
	_record_check(result, "completed_split_restore_invariants_clean", completed_restored.runtime_invariant_failures().is_empty(), completed_restored.runtime_invariant_failures())


func _find_split_wave(game: Node) -> int:
	var schedule: Array = game.game_data.get("waves", {}).get("schedule", [])
	for index in range(schedule.size()):
		var wave_number := index + 1
		game.set_wave_for_test(wave_number)
		var row: Variant = schedule[index]
		var kind := "normal"
		if row is Dictionary:
			kind = str(row.get("enemy_kind", "normal"))
		var enemy: Dictionary = game.create_enemy(kind, wave_number, Vector2(180, 100), 1)
		if int(enemy.get("death_spawns", 0)) > 0:
			return wave_number
	return 0


func _prepare_active_split_child(game: Node, split_wave: int) -> Dictionary:
	var wave_info: Dictionary = game.spawn_regular_wave_for_test(split_wave)
	game.wave_active = true
	game.lives = max(game.lives, 200)
	var target_index := -1
	for index in range(game.enemies.size()):
		if int(game.enemies[index].get("death_spawns", 0)) > 0:
			target_index = index
			break
	if target_index < 0:
		return {"ok": false, "reason": "no split enemy", "wave_info": wave_info}
	var target: Dictionary = game.enemies[target_index]
	for index in range(game.enemies.size()):
		if index == target_index:
			continue
		game.enemies[index]["target_index"] = 999
	game.process_step(0.01)
	var tower: Dictionary = _test_tower_near(target)
	game.towers = [tower]
	_kill_enemy_with_projectile(game, target, tower)
	game.process_step(0.01)
	return {
		"ok": game.enemies.size() == int(target.get("death_spawns", 0)) and int(game.snapshot().get("spawned_extra_this_wave", 0)) == int(target.get("death_spawns", 0)),
		"snapshot": game.snapshot(),
	}


func _complete_active_split_child(game: Node) -> Dictionary:
	if game.enemies.is_empty():
		return {"ok": false, "reason": "no active child", "snapshot": game.snapshot()}
	var tower: Dictionary = game.towers[0] if game.towers.size() > 0 else _test_tower_near(game.enemies[0])
	if game.towers.is_empty():
		game.towers = [tower]
	for enemy in game.enemies.duplicate():
		_kill_enemy_with_projectile(game, enemy, tower)
		game.process_step(0.01)
	game.process_step(0.01)
	var snapshot: Dictionary = game.snapshot()
	return {
		"ok": bool(snapshot.get("wave_complete", false)) and int(snapshot.get("kills", 0)) + int(snapshot.get("leaks", 0)) == int(snapshot.get("spawned_total_this_wave", -1)),
		"snapshot": snapshot,
	}


func _restored_game_from_state(state: Dictionary) -> Node:
	var slice_script := load("res://scripts/game/vertical_slice_game.gd")
	var restored_game: Node = slice_script.new()
	root.add_child(restored_game)
	restored_game.name = "SplitRestoreProbe"
	if not restored_game.restore_run_state(state):
		return null
	return restored_game


func _test_tower_near(enemy: Dictionary) -> Dictionary:
	return {
		"type": "archer",
		"position": enemy.get("position", Vector2.ZERO),
		"level": 2,
		"range": 250.0,
		"damage": max(1.0, float(enemy.get("max_hp", 1.0)) * 2.0),
		"fire_rate": 0.5,
		"cooldown": 999.0,
		"target_mode": "first",
		"kills": 0,
		"money_spent": 0,
		"mutations": [],
		"selected_branch": "",
		"is_paragon": false,
		"total_damage": 0.0,
		"mastery_xp": 0.0,
	}


func _kill_enemy_with_projectile(game: Node, enemy: Dictionary, tower: Dictionary) -> void:
	tower["position"] = enemy.get("position", Vector2.ZERO)
	tower["damage"] = max(1.0, float(enemy.get("max_hp", 1.0)) * 2.0)
	var projectile: Dictionary = game.make_test_projectile(tower, enemy, enemy.get("position", Vector2.ZERO))
	game.update_projectile_for_test(projectile, 0.01)


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
	_cleanup_artifact(save_path + ".tmp")


func _root_node_or_new(node_name: String, script: Script) -> Node:
	return VALIDATION_HARNESS.root_node_or_new(self, node_name, script)


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	VALIDATION_HARNESS.record_check(result, label, passed, detail)
