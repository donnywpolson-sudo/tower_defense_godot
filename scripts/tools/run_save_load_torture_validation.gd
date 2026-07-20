extends SceneTree


func _initialize() -> void:
	var config_script := load("res://scripts/autoload/game_config.gd")
	var data_script := load("res://scripts/autoload/game_data.gd")
	var progress_script := load("res://scripts/autoload/game_progress.gd")
	var slice_script := load("res://scripts/game/vertical_slice_game.gd")
	var config: Node = _root_node_or_new("GameConfig", config_script)
	var data_loader: Node = _root_node_or_new("GameData", data_script)
	var progress: Node = _root_node_or_new("GameProgress", progress_script)
	var save_path := "user://save_load_torture_%s.json" % Time.get_ticks_usec()
	var result: Dictionary = {
		"ok": true,
		"checks": [],
		"errors": [],
	}

	_check_active_combat_file_roundtrip(progress, slice_script, save_path, result)
	_check_temporary_artifact_recovery(progress, save_path, result)
	_check_upgrade_selection_roundtrip(progress, slice_script, result)
	_check_debug_skip_wave_roundtrip(progress, slice_script, result)
	_check_game_over_roundtrip(progress, slice_script, result)
	_cleanup_save(save_path)

	if result["ok"]:
		print("SAVE_LOAD_TORTURE_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("SAVE_LOAD_TORTURE_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)


func _check_active_combat_file_roundtrip(progress: Node, slice_script: Script, save_path: String, result: Dictionary) -> void:
	progress.reset_progression()
	var game: Node = _new_game(slice_script, "SaveLoadActiveCombatGame", progress)
	_record_check(result, "active_combat_place_tower", game.place_archer(game.RECOMMENDED_BUILD_SITE), game.snapshot())
	_record_check(result, "active_combat_start_wave", game.start_wave(), game.snapshot())
	for _step in range(480):
		game.process_step(0.05)
		var snapshot: Dictionary = game.snapshot()
		if int(snapshot.get("enemy_count", 0)) > 0 and int(snapshot.get("projectile_count", 0)) > 0:
			break
	var active_snapshot: Dictionary = game.snapshot()
	_record_check(result, "active_combat_has_enemy_and_projectile", int(active_snapshot.get("enemy_count", 0)) > 0 and int(active_snapshot.get("projectile_count", 0)) > 0, active_snapshot)
	var run_state: Dictionary = game.serialize_run_state()
	_record_check(result, "active_combat_serializes_projectile_links", run_state.get("projectiles", []).size() > 0 and int(run_state.get("projectiles", [])[0].get("target_index", -1)) >= 0 and int(run_state.get("projectiles", [])[0].get("source_tower_id", -1)) > 0 and not run_state.get("projectiles", [])[0].has("tower_index"), run_state.get("projectiles", []))
	_record_check(result, "torture_save_path_is_new", not FileAccess.file_exists(save_path), save_path)
	_record_check(result, "active_combat_save_creates_file", progress.save_to_path(save_path, run_state, false), {"path": save_path, "error": progress.last_save_error})
	var progress_script := load("res://scripts/autoload/game_progress.gd")
	var loaded_progress: Node = progress_script.new()
	root.add_child(loaded_progress)
	loaded_progress.name = "SaveLoadTortureLoadedProgress"
	_record_check(result, "active_combat_load_reads_file", loaded_progress.load_from_path(save_path), loaded_progress.payload())
	var restored: Node = _new_game(slice_script, "SaveLoadActiveCombatRestoredGame", loaded_progress)
	_record_check(result, "active_combat_restore_accepts_loaded_state", restored.restore_run_state(loaded_progress.last_run_state), restored.snapshot())
	_record_check(result, "active_combat_restore_matches_counts", _snapshots_match(active_snapshot, restored.snapshot(), ["money", "lives", "wave", "wave_active", "spawned_this_wave", "tower_count", "enemy_count", "projectile_count"]), {"original": active_snapshot, "restored": restored.snapshot()})
	restored.process_step(0.05)
	_record_check(result, "active_combat_restored_step_keeps_invariants", restored.runtime_invariant_failures().is_empty(), restored.runtime_invariant_failures())


func _check_temporary_artifact_recovery(progress: Node, save_path: String, result: Dictionary) -> void:
	var temp_path: String = progress.temporary_save_path(save_path)
	_cleanup_artifact(temp_path)
	_record_check(result, "malformed_temp_fixture_created", _write_text(temp_path, "{\"schema_version\":1"), temp_path)
	var malformed_saved: bool = progress.save_to_path(save_path, {"recovery_case": "malformed"}, true)
	_record_check(result, "malformed_temp_save_recovers", malformed_saved, {"error": progress.last_save_error})
	_record_check(result, "malformed_temp_cleanup_is_bounded", not FileAccess.file_exists(temp_path), temp_path)
	_record_check(result, "malformed_temp_payload_loads", progress.load_from_path(save_path) and str(progress.last_run_state.get("recovery_case", "")) == "malformed", progress.last_run_state)

	_record_check(result, "partial_temp_fixture_created", _write_text(temp_path, "{\"schema_version\":1,\"progression\":"), temp_path)
	var partial_saved: bool = progress.save_to_path(save_path, {"recovery_case": "partial"}, true)
	_record_check(result, "partial_temp_save_recovers", partial_saved, {"error": progress.last_save_error})
	_record_check(result, "partial_temp_cleanup_is_bounded", not FileAccess.file_exists(temp_path), temp_path)
	_record_check(result, "partial_temp_payload_loads", progress.load_from_path(save_path) and str(progress.last_run_state.get("recovery_case", "")) == "partial", progress.last_run_state)


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


func _check_upgrade_selection_roundtrip(progress: Node, slice_script: Script, result: Dictionary) -> void:
	progress.reset_progression()
	var game: Node = _new_game(slice_script, "SaveLoadUpgradeGame", progress)
	game.set_debug_overlay_enabled(true)
	game.run_debug_command("give_money", {"amount": 500})
	_record_check(result, "upgrade_roundtrip_place_tower", game.place_archer(game.RECOMMENDED_BUILD_SITE), game.snapshot())
	_record_check(result, "upgrade_roundtrip_upgrade_tower", game.upgrade_selected_tower(), game.upgrade_panel_snapshot())
	_record_check(result, "upgrade_roundtrip_cycle_target", game.cycle_selected_target_mode(), game.upgrade_panel_snapshot())
	var original: Dictionary = game.snapshot()
	var restored: Node = _restore_state(slice_script, progress, "SaveLoadUpgradeRestoredGame", game.serialize_run_state(), result, "upgrade_roundtrip_restore_accepts_state")
	_record_check(result, "upgrade_roundtrip_selection_survives", bool(restored.upgrade_panel_snapshot().get("visible", false)) and int(restored.upgrade_panel_snapshot().get("selected_tower_index", -1)) == 0, restored.upgrade_panel_snapshot())
	_record_check(result, "upgrade_roundtrip_tower_level_survives", restored.towers.size() == 1 and int(restored.towers[0].get("level", 0)) == 2, restored.towers)
	_record_check(result, "upgrade_roundtrip_target_mode_survives", restored.towers.size() == 1 and str(restored.towers[0].get("target_mode", "")) == str(game.towers[0].get("target_mode", "")), {"original": game.towers, "restored": restored.towers})
	_record_check(result, "upgrade_roundtrip_snapshot_counts_match", _snapshots_match(original, restored.snapshot(), ["money", "tower_count", "selected_build_type", "game_speed"]), {"original": original, "restored": restored.snapshot()})


func _check_debug_skip_wave_roundtrip(progress: Node, slice_script: Script, result: Dictionary) -> void:
	progress.reset_progression()
	var game: Node = _new_game(slice_script, "SaveLoadSkipWaveGame", progress)
	game.set_debug_overlay_enabled(true)
	_record_check(result, "skip_roundtrip_set_wave", bool(game.run_debug_command("set_wave", {"wave": 4}).get("ok", false)), game.snapshot())
	_record_check(result, "skip_roundtrip_skip_wave", bool(game.run_debug_command("skip_wave").get("ok", false)), game.snapshot())
	var original: Dictionary = game.snapshot()
	var restored: Node = _restore_state(slice_script, progress, "SaveLoadSkipWaveRestoredGame", game.serialize_run_state(), result, "skip_roundtrip_restore_accepts_state")
	_record_check(result, "skip_roundtrip_wave_complete_survives", bool(restored.snapshot().get("wave_complete", false)) and not bool(restored.snapshot().get("wave_active", true)), restored.snapshot())
	_record_check(result, "skip_roundtrip_rewards_survive", int(restored.snapshot().get("wave_reward_money", 0)) == int(original.get("wave_reward_money", -1)) and int(restored.snapshot().get("wave_reward_research", 0)) == int(original.get("wave_reward_research", -1)), {"original": original, "restored": restored.snapshot()})
	var money_before_step: int = int(restored.snapshot().get("money", 0))
	restored.process_step(0.05)
	_record_check(result, "skip_roundtrip_step_does_not_double_reward", int(restored.snapshot().get("money", -1)) == money_before_step, restored.snapshot())


func _check_game_over_roundtrip(progress: Node, slice_script: Script, result: Dictionary) -> void:
	progress.reset_progression()
	var game: Node = _new_game(slice_script, "SaveLoadGameOverGame", progress)
	game.lives = 1
	game.spawn_regular_wave_for_test(1)
	game.wave_active = true
	for enemy in game.enemies:
		enemy["target_index"] = 999
	game.process_step(0.05)
	var original: Dictionary = game.snapshot()
	_record_check(result, "game_over_roundtrip_reaches_game_over", bool(original.get("game_over", false)) and int(original.get("lives", -1)) == 0, original)
	var restored: Node = _restore_state(slice_script, progress, "SaveLoadGameOverRestoredGame", game.serialize_run_state(), result, "game_over_roundtrip_restore_accepts_state")
	_record_check(result, "game_over_roundtrip_state_survives", bool(restored.snapshot().get("game_over", false)) and int(restored.snapshot().get("lives", -1)) == 0 and int(restored.snapshot().get("enemy_count", -1)) == 0, restored.snapshot())
	_record_check(result, "game_over_roundtrip_blocks_wave_start", restored.start_wave() == false, restored.snapshot())
	restored.process_step(0.05)
	_record_check(result, "game_over_roundtrip_step_keeps_invariants", restored.runtime_invariant_failures().is_empty(), restored.runtime_invariant_failures())


func _new_game(slice_script: Script, node_name: String, progress: Node) -> Node:
	var game: Node = slice_script.new()
	root.add_child(game)
	game.name = node_name
	game.progress_override = progress
	game.reset_slice()
	return game


func _restore_state(slice_script: Script, progress: Node, node_name: String, state: Dictionary, result: Dictionary, label: String) -> Node:
	var game: Node = _new_game(slice_script, node_name, progress)
	_record_check(result, label, game.restore_run_state(state), game.snapshot())
	return game


func _snapshots_match(original: Dictionary, restored: Dictionary, keys: Array) -> bool:
	for key in keys:
		if original.get(key) != restored.get(key):
			return false
	return true


func _cleanup_save(save_path: String) -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	_cleanup_artifact(save_path + ".tmp")


func _root_node_or_new(node_name: String, script: Script) -> Node:
	var existing := root.get_node_or_null(node_name)
	if existing != null:
		return existing
	var node: Node = script.new()
	root.add_child(node)
	node.name = node_name
	return node


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	ValidationHarness.record_check(result, label, passed, detail)
