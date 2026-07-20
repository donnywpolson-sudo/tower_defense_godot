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
	var starting_money: int = int(game.snapshot().get("money", 0))
	var disabled_result: Dictionary = game.run_debug_command("give_money", {"amount": 25})
	_record_check(result, "debug_commands_start_disabled", not bool(disabled_result.get("ok", true)) and str(disabled_result.get("error", "")).contains("disabled"), disabled_result)
	_record_check(result, "disabled_command_does_not_mutate_money", int(game.snapshot().get("money", -1)) == starting_money, game.snapshot())

	game.set_debug_overlay_enabled(true)
	var command_names: Array = game.debug_command_names()
	_record_check(result, "debug_command_names_include_core_slice", command_names.has("give_money") and command_names.has("set_wave") and command_names.has("spawn_enemy") and command_names.has("kill_all_enemies") and command_names.has("skip_wave"), command_names)
	var enabled_snapshot: Dictionary = game.debug_overlay_snapshot()
	_record_check(result, "debug_overlay_lists_commands", enabled_snapshot.get("commands", []).size() >= 5 and enabled_snapshot.get("commands", []).has("spawn_enemy"), enabled_snapshot)

	var money_result: Dictionary = game.run_debug_command("give_money", {"amount": 50})
	_record_check(result, "give_money_command_succeeds", bool(money_result.get("ok", false)) and int(game.snapshot().get("money", 0)) == starting_money + 50, money_result)
	var invalid_money_result: Dictionary = game.run_debug_command("give_money", {"amount": -1})
	_record_check(result, "give_money_rejects_negative_amount", not bool(invalid_money_result.get("ok", true)), invalid_money_result)

	var wave_result: Dictionary = game.run_debug_command("set_wave", {"wave": 3})
	var wave_snapshot: Dictionary = game.snapshot()
	_record_check(result, "set_wave_command_succeeds", bool(wave_result.get("ok", false)) and int(wave_snapshot.get("wave", 0)) == 3 and not bool(wave_snapshot.get("wave_active", true)) and not bool(wave_snapshot.get("wave_complete", true)), wave_result)

	var spawn_result: Dictionary = game.run_debug_command("spawn_enemy", {"kind": "fast", "count": 2})
	var spawn_snapshot: Dictionary = game.debug_overlay_snapshot()
	_record_check(result, "spawn_enemy_command_succeeds", bool(spawn_result.get("ok", false)) and spawn_snapshot.get("enemies", []).size() == 2, spawn_snapshot.get("enemies", []))
	_record_check(result, "spawn_enemy_uses_canonical_kind", str(spawn_snapshot.get("enemies", [])[0].get("kind", "")) == "fast", spawn_snapshot.get("enemies", []))

	var kill_result: Dictionary = game.run_debug_command("kill_all_enemies")
	var after_kill_snapshot: Dictionary = game.snapshot()
	_record_check(result, "kill_all_enemies_command_succeeds", bool(kill_result.get("ok", false)) and int(after_kill_snapshot.get("enemy_count", -1)) == 0 and int(after_kill_snapshot.get("projectile_count", -1)) == 0, kill_result)

	var skip_money_before: int = int(game.snapshot().get("money", 0))
	var skip_research_before: int = int(game.snapshot().get("research_points", 0))
	var skip_result: Dictionary = game.run_debug_command("skip_wave")
	var skip_snapshot: Dictionary = game.snapshot()
	_record_check(result, "skip_wave_command_completes_wave", bool(skip_result.get("ok", false)) and bool(skip_snapshot.get("wave_complete", false)) and not bool(skip_snapshot.get("wave_active", true)), skip_result)
	_record_check(result, "skip_wave_applies_rewards_once", int(skip_snapshot.get("money", 0)) > skip_money_before and int(skip_snapshot.get("research_points", 0)) > skip_research_before, skip_snapshot)
	var skip_again_result: Dictionary = game.run_debug_command("skip_wave")
	_record_check(result, "skip_wave_is_idempotent_when_complete", bool(skip_again_result.get("ok", false)) and int(game.snapshot().get("money", 0)) == int(skip_snapshot.get("money", 0)), skip_again_result)

	var unknown_result: Dictionary = game.run_debug_command("missing_command")
	_record_check(result, "unknown_debug_command_fails", not bool(unknown_result.get("ok", true)), unknown_result)
	_record_check(result, "debug_commands_keep_runtime_invariants_clean", game.runtime_invariant_failures().is_empty(), game.runtime_invariant_failures())

	if result["ok"]:
		print("DEBUG_COMMANDS_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("DEBUG_COMMANDS_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	ValidationHarness.record_check(result, label, passed, detail)
