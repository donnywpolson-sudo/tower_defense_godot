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
	_check_first_five_regular_waves(game, result)
	_check_all_regular_schedule_rows(game, result)
	_check_restore_refreshes_schedule_rows(game, result)
	_check_helper_bounds(game, result)
	_check_wave_pressure_budget(game, result)
	_check_final_wave_advance_fails_safely(game, result)
	_check_status_snapshot_uses_schedule_enemy(game, result)

	if result["ok"]:
		print("WAVE_SCHEDULE_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("WAVE_SCHEDULE_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)


func _check_first_five_regular_waves(game: Node, result: Dictionary) -> void:
	var expected: Dictionary = {
		1: {"enemy_kind": "normal", "regular_count": 11, "boss_count": 0, "commander_count": 0, "spawn_interval": 0.66},
		2: {"enemy_kind": "swarm", "regular_count": 16, "boss_count": 0, "commander_count": 0, "spawn_interval": 0.596},
		3: {"enemy_kind": "fast", "regular_count": 19, "boss_count": 0, "commander_count": 0, "spawn_interval": 0.584},
		4: {"enemy_kind": "tank", "regular_count": 22, "boss_count": 0, "commander_count": 0, "spawn_interval": 0.572},
		5: {"enemy_kind": "swarm", "regular_count": 25, "boss_count": 1, "commander_count": 0, "spawn_interval": 0.56},
	}
	for wave_number in expected:
		var summary: Dictionary = game.spawn_regular_wave_for_test(wave_number)
		var want: Dictionary = expected[wave_number]
		_record_check(result, "wave_%s_kind" % wave_number, summary["enemy_kind"] == want["enemy_kind"], summary)
		_record_check(result, "wave_%s_count" % wave_number, int(summary["spawned_count"]) == int(want["regular_count"]) + int(want["boss_count"]) + int(want["commander_count"]) and int(summary["spawn_limit"]) == int(want["regular_count"]), summary)
		_record_check(result, "wave_%s_interval" % wave_number, is_equal_approx(float(summary["spawn_interval"]), float(want["spawn_interval"])), summary)
		_record_check(result, "wave_%s_kind_count" % wave_number, int(summary["kind_counts"].get(want["enemy_kind"], 0)) == int(want["regular_count"]) + int(want["boss_count"]), summary)
		_record_check(result, "wave_%s_boss_count" % wave_number, int(summary["game_data_boss_count"]) == int(want["boss_count"]) and int(summary["spawned_boss_count"]) == int(want["boss_count"]), summary)
		_record_check(result, "wave_%s_commander_count" % wave_number, int(summary["game_data_commander_count"]) == int(want["commander_count"]) and int(summary["spawned_commander_count"]) == int(want["commander_count"]), summary)


func _check_all_regular_schedule_rows(game: Node, result: Dictionary) -> void:
	var schedule: Array = game.game_data.get("waves", {}).get("schedule", [])
	_record_check(result, "schedule_has_30_rows", schedule.size() == 30, {"schedule_count": schedule.size()})
	for index in range(schedule.size()):
		var wave_number: int = index + 1
		var row: Dictionary = schedule[index]
		var summary: Dictionary = game.spawn_regular_wave_for_test(wave_number)
		var regular_count := int(row.get("regular_enemy_count", -1))
		var detail := {
			"wave": wave_number,
			"expected_enemy_kind": str(row.get("enemy_kind", "")),
			"expected_regular_enemy_count": regular_count,
			"expected_spawn_interval": float(row.get("spawn_interval", -1.0)),
			"game_data_boss_count": int(row.get("boss_count", 0)),
			"game_data_commander_count": int(row.get("commander_count", 0)),
			"summary": summary,
		}
		var boss_count := int(row.get("boss_count", 0))
		var commander_count := int(row.get("commander_count", 0))
		_record_check(result, "wave_%s_regular_count_from_schedule" % wave_number, int(summary["spawned_count"]) == regular_count + boss_count + commander_count and int(summary["spawn_limit"]) == regular_count, detail)
		_record_check(result, "wave_%s_not_legacy_slice_limit" % wave_number, int(summary["spawn_limit"]) != 3, detail)
		_record_check(result, "wave_%s_kind_from_schedule" % wave_number, str(summary["enemy_kind"]) == str(row.get("enemy_kind", "")), detail)
		_record_check(result, "wave_%s_interval_from_schedule" % wave_number, is_equal_approx(float(summary["spawn_interval"]), float(row.get("spawn_interval", -1.0))), detail)
		_record_check(result, "wave_%s_spawns_bosses" % wave_number, int(summary["spawned_boss_count"]) == boss_count, detail)
		_record_check(result, "wave_%s_spawns_commanders" % wave_number, int(summary["spawned_commander_count"]) == commander_count, detail)
		if row.get("modifier", null) != null:
			_record_check(result, "wave_%s_reports_wave_modifier" % wave_number, summary["modifier"] == str(row.get("modifier", "")) and summary["modifier_label"] != "", detail)


func _check_restore_refreshes_schedule_rows(game: Node, result: Dictionary) -> void:
	var schedule: Array = game.game_data.get("waves", {}).get("schedule", [])
	for wave_number in [2, 5, 30]:
		var restored: bool = game.restore_run_state({
			"schema_version": 1,
			"wave": wave_number,
			"wave_active": false,
			"wave_complete": false,
			"spawned_this_wave": 0,
			"spawn_timer": 0.0,
			"towers": [],
			"enemies": [],
			"projectiles": [],
		})
		var row: Dictionary = schedule[wave_number - 1]
		var snapshot: Dictionary = game.snapshot()
		var detail := {
			"wave": wave_number,
			"restored": restored,
			"expected_enemy_kind": str(row.get("enemy_kind", "")),
			"expected_regular_enemy_count": int(row.get("regular_enemy_count", -1)),
			"expected_spawn_interval": float(row.get("spawn_interval", -1.0)),
			"snapshot": snapshot,
		}
		_record_check(result, "restore_wave_%s_accepts_state" % wave_number, restored, detail)
		_record_check(result, "restore_wave_%s_refreshes_schedule_row" % wave_number, snapshot["wave"] == wave_number and snapshot["enemy_family"] == str(row.get("enemy_kind", "")) and int(snapshot["spawn_limit"]) == int(row.get("regular_enemy_count", -1)) and is_equal_approx(float(snapshot["spawn_interval"]), float(row.get("spawn_interval", -1.0))), detail)


func _check_helper_bounds(game: Node, result: Dictionary) -> void:
	var low: Dictionary = game.spawn_regular_wave_for_test(0)
	_record_check(result, "helper_wave_zero_clamps_to_wave_1", low["wave"] == 1 and low["enemy_kind"] == "normal" and low["spawn_limit"] == 11 and is_equal_approx(float(low["spawn_interval"]), 0.66), low)
	var high: Dictionary = game.spawn_regular_wave_for_test(999)
	_record_check(result, "helper_high_wave_clamps_to_wave_30", high["wave"] == 30 and high["enemy_kind"] == "swarm" and high["spawn_limit"] == 100 and is_equal_approx(float(high["spawn_interval"]), 0.26), high)


func _check_wave_pressure_budget(game: Node, result: Dictionary) -> void:
	var wave_one: Dictionary = game.spawn_regular_wave_for_test(1)
	var wave_two: Dictionary = game.spawn_regular_wave_for_test(2)
	var wave_one_enemy: Dictionary = game.make_game_data_enemy_for_test("normal", 1)
	var wave_two_enemy: Dictionary = game.make_game_data_enemy_for_test("swarm", 2)
	var wave_one_pressure := wave_pressure_score(wave_one, wave_one_enemy)
	var wave_two_pressure := wave_pressure_score(wave_two, wave_two_enemy)
	_record_check(result, "wave_1_pressure_below_wave_2", wave_one_pressure < wave_two_pressure, {
		"wave_1_pressure": wave_one_pressure,
		"wave_2_pressure": wave_two_pressure,
		"wave_1": wave_one,
		"wave_2": wave_two,
	})


func wave_pressure_score(row: Dictionary, enemy_stats: Dictionary) -> float:
	var count := int(row.get("spawn_limit", row.get("regular_enemy_count", 0)))
	var spawn_interval := float(row.get("spawn_interval", 0.6))
	var hp := float(enemy_stats.get("hp", 1.0))
	var speed := float(enemy_stats.get("speed", 1.0))
	var density: float = 1.0 / max(0.1, spawn_interval)
	return count * hp * density * (speed / 64.0)


func _check_final_wave_advance_fails_safely(game: Node, result: Dictionary) -> void:
	game.set_wave_for_test(30)
	game.wave_complete = true
	game.wave_active = false
	var advanced: bool = game.advance_to_next_wave()
	var snapshot: Dictionary = game.snapshot()
	_record_check(result, "final_wave_advance_returns_false", advanced == false, snapshot)
	_record_check(result, "final_wave_advance_keeps_wave_30_schedule", snapshot["wave"] == 30 and snapshot["wave_complete"] == true and snapshot["spawn_limit"] == 100 and snapshot["enemy_family"] == "swarm", snapshot)


func _check_status_snapshot_uses_schedule_enemy(game: Node, result: Dictionary) -> void:
	game.set_wave_for_test(2)
	var status: Dictionary = game.status_snapshot()
	var snapshot: Dictionary = game.snapshot()
	_record_check(result, "status_uses_wave_2_enemy_kind", str(status.get("gameplay", "")).contains("Swarm") and not str(status.get("gameplay", "")).contains("Normal"), status)
	_record_check(result, "snapshot_uses_active_schedule_limit", snapshot["spawn_limit"] == 16 and snapshot["slice_spawn_limit"] == 3 and snapshot["spawn_limit"] != snapshot["slice_spawn_limit"], snapshot)
	game.set_wave_for_test(8)
	var forecast: Dictionary = game.wave_forecast_snapshot()
	_record_check(result, "forecast_uses_modifier_recommendation", forecast["label"] == "Normal + Encrypted" and forecast["modifier"] == "armored" and str(forecast["recommendation"]).contains("Sniper"), forecast)


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	ValidationHarness.record_check(result, label, passed, detail)
