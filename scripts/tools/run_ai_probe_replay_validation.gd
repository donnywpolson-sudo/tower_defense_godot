extends SceneTree

const REPLAY_ID := "frost_tower_family_wave6_map0_v1"
const OUTPUT_PATH := "res://logs/godot/ai_probe_replay_frost_wave6.json"
const STEP_DELTA := 0.2
const MAX_CYCLES := 900
const SETUP_MONEY := 5000
const SETUP_LIVES := 25
const TOWER_TYPE := "frost"
const WAVE := 6
const SITES := [Vector2(351, 297), Vector2(108, 162), Vector2(567, 513)]
const SOURCE_LEAK_RATE := 23.0 / 28.0
const TARGET_MAX_LEAK_RATE := 0.35

var _errors: Array = []


func _initialize() -> void:
	var baseline_first := _run_case("baseline_first", true)
	var baseline_repeat := _run_case("baseline_repeat", true)
	var no_upgrade := _run_case("counterfactual_no_upgrade", false)
	var deterministic := _case_signature(baseline_first) == _case_signature(baseline_repeat)
	if not deterministic:
		_errors.append("Repeated frost baseline replay was not deterministic.")
	if not bool(baseline_first.get("setup_valid", false)):
		_errors.append("Frost baseline setup did not reproduce the recorded three-tower layout.")
	if float(baseline_first.get("leak_rate", 0.0)) > TARGET_MAX_LEAK_RATE:
		_errors.append("Frost replay still exceeds the tower-family leak ceiling after the balance pass.")
	var report := {
		"replay_id": REPLAY_ID,
		"selected_replay": {
			"candidate": "SCENARIO-0003",
			"reason": "Frost had the highest recorded tower-family leak rate: 23 of 28 enemies leaked and only 2 lives remained.",
			"source_leak_rate": SOURCE_LEAK_RATE,
			"target_max_leak_rate": TARGET_MAX_LEAK_RATE,
			"source_packet": "2026_07_13_0926",
			"source_issue": "scenario_leak_rate_out_of_range",
		},
		"fix_summary": {
			"base_damage": "27 -> 40 before level-one scaling; level-one runtime damage is now 37",
			"initial_slow_multiplier": "0.76 -> 0.62",
			"repeat_hit_behavior": "Repeated hits deepen chill by 0.04 down to a 0.50 multiplier floor, then expiry resets speed.",
		},
		"deterministic": deterministic,
		"action_trace": [
			{"action": "reset_slice", "map_index": 0},
			{"action": "set_money", "money": SETUP_MONEY},
			{"action": "set_lives", "lives": SETUP_LIVES},
			{"action": "set_game_speed", "speed": 4.0},
			{"action": "set_wave_for_test", "wave": WAVE},
			{"action": "place_selected_tower", "tower_type": TOWER_TYPE, "sites": _site_payload()},
			{"action": "select_tower", "tower_index": 0},
			{"action": "upgrade_selected_tower", "baseline": true},
			{"action": "start_wave", "wave": WAVE},
			{"action": "process_scaled_delta", "delta": STEP_DELTA, "until": "wave_complete_or_game_over", "max_cycles": MAX_CYCLES},
		],
		"cases": [baseline_first, baseline_repeat, no_upgrade],
		"no_code_change_if": "Do not generalize this tuning from one map and wave; rerun broader map, branch, and economy coverage before further frost changes.",
	}
	_write_report(report)
	if _errors.is_empty():
		print("AI_PROBE_REPLAY_VALIDATION_OK")
		print("  Selected replay: %s" % REPLAY_ID)
		print("  Baseline leak rate: %.6f" % float(baseline_first.get("leak_rate", 0.0)))
		print("  Counterfactual leak rate: %.6f" % float(no_upgrade.get("leak_rate", 0.0)))
		print("  Deterministic: %s" % deterministic)
		print("  Evidence: %s" % ProjectSettings.globalize_path(OUTPUT_PATH))
		quit(0)
	else:
		push_error("AI_PROBE_REPLAY_VALIDATION_FAILED")
		for error in _errors:
			push_error(str(error))
		quit(1)


func _run_case(case_id: String, upgrade: bool) -> Dictionary:
	var game := _create_game()
	game.reset_slice(0)
	game.money = SETUP_MONEY
	game.lives = SETUP_LIVES
	game.set_game_speed(4.0)
	game.set_wave_for_test(WAVE)
	var placed: Array = []
	var placement_results: Array = []
	for site in SITES:
		var placed_ok: bool = game.place_selected_tower(site, TOWER_TYPE)
		placement_results.append({"site": [site.x, site.y], "placed": placed_ok})
		if placed_ok:
			placed.append([site.x, site.y])
	game.selected_tower_index = 0
	var upgrade_ok := false
	if upgrade and not placed.is_empty():
		upgrade_ok = game.upgrade_selected_tower()
	var start_ok: bool = game.start_wave()
	var cycles := 0
	if start_ok:
		for cycle in range(MAX_CYCLES):
			cycles = cycle + 1
			game.set_game_speed(4.0)
			game._process_scaled_delta(STEP_DELTA)
			var snapshot: Dictionary = game.snapshot()
			if bool(snapshot.get("game_over", false)) or bool(snapshot.get("wave_complete", false)):
				break
	var final_snapshot: Dictionary = game.snapshot()
	var tower_summary := _tower_summary(game)
	var spawned := int(final_snapshot.get("spawned_total_this_wave", 0))
	var leaks := int(final_snapshot.get("leaks", 0))
	var result := {
		"case_id": case_id,
		"upgrade_requested": upgrade,
		"setup_valid": placed.size() == SITES.size(),
		"placement_results": placement_results,
		"upgrade_succeeded": upgrade_ok,
		"start_succeeded": start_ok,
		"completed": bool(final_snapshot.get("wave_complete", false)),
		"game_over": bool(final_snapshot.get("game_over", false)),
		"cycles_to_resolution": cycles,
		"spawned": spawned,
		"kills": int(final_snapshot.get("kills", 0)),
		"leaks": leaks,
		"lives": int(final_snapshot.get("lives", 0)),
		"leak_rate": float(leaks) / float(max(1, spawned)),
		"final_snapshot": final_snapshot,
		"tower_summary": tower_summary,
		"runtime_invariant_failures": game.runtime_invariant_failures(),
	}
	_teardown_game(game)
	return result


func _create_game() -> Node:
	var config_script := load("res://scripts/autoload/game_config.gd")
	var data_script := load("res://scripts/autoload/game_data.gd")
	var slice_script := load("res://scripts/game/vertical_slice_game.gd")
	var config: Node = config_script.new()
	var data_loader: Node = data_script.new()
	var game: Node = slice_script.new()
	root.add_child(config)
	root.add_child(data_loader)
	root.add_child(game)
	config.name = "ReplayGameConfig"
	data_loader.name = "ReplayGameData"
	game.name = "ReplayVerticalSliceGame"
	return game


func _teardown_game(game: Node) -> void:
	game.set_process(false)
	game.set_physics_process(false)
	if game.get_parent() != null:
		game.get_parent().remove_child(game)
	game.free()


func _tower_summary(game: Node) -> Array:
	var summary: Array = []
	for tower in game.serialize_run_state().get("towers", []):
		var raw_position: Variant = tower.get("position", [0.0, 0.0])
		var position := Vector2.ZERO
		if raw_position is Vector2:
			position = raw_position
		elif raw_position is Array and raw_position.size() >= 2:
			position = Vector2(float(raw_position[0]), float(raw_position[1]))
		summary.append({
			"type": str(tower.get("type", "")),
			"position": [position.x, position.y],
			"level": int(tower.get("level", 0)),
			"damage": float(tower.get("damage", 0.0)),
			"range": float(tower.get("range", 0.0)),
			"fire_rate": float(tower.get("fire_rate", 0.0)),
			"kills": int(tower.get("kills", 0)),
			"money_spent": int(tower.get("money_spent", 0)),
			"selected_branch": str(tower.get("selected_branch", "")),
		})
	return summary


func _site_payload() -> Array:
	var payload: Array = []
	for site in SITES:
		payload.append([site.x, site.y])
	return payload


func _case_signature(case_result: Dictionary) -> String:
	return JSON.stringify({
		"setup_valid": case_result.get("setup_valid", false),
		"placement_results": case_result.get("placement_results", []),
		"upgrade_succeeded": case_result.get("upgrade_succeeded", false),
		"start_succeeded": case_result.get("start_succeeded", false),
		"completed": case_result.get("completed", false),
		"game_over": case_result.get("game_over", false),
		"cycles_to_resolution": case_result.get("cycles_to_resolution", 0),
		"spawned": case_result.get("spawned", 0),
		"kills": case_result.get("kills", 0),
		"leaks": case_result.get("leaks", 0),
		"lives": case_result.get("lives", 0),
		"leak_rate": case_result.get("leak_rate", 0.0),
		"tower_summary": case_result.get("tower_summary", []),
		"runtime_invariant_failures": case_result.get("runtime_invariant_failures", []),
	})


func _write_report(report: Dictionary) -> void:
	var path := ProjectSettings.globalize_path(OUTPUT_PATH)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_errors.append("Could not write replay evidence to %s." % path)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
