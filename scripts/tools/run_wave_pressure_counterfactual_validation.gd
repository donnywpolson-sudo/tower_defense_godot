extends SceneTree

const OK_TOKEN := "WAVE_PRESSURE_COUNTERFACTUAL_VALIDATION_OK"
const OUTPUT_PATH := "res://logs/godot/wave_pressure_counterfactual_2026_07_14.json"
const STEP_DELTA := 0.2
const MAX_CYCLES := 900
const SETUP_MONEY := 5000
const SETUP_LIVES := 25
const WAVE_NUMBER := 4
const BASELINE_TANK_COUNT := 22
const VARIANT_TANK_COUNTS := [18, 20, 22]
const REPEAT_COUNT := 2
const SEED := 20240714
const MAP_NAMES := ["Classic Road", "Split Road", "Zigzag Road", "Spiral Road"]
const BUILD_VARIANTS := ["mixed", "rotated_lane_priority"]
const MIXED_TOWERS := ["archer", "machine_gun", "cannon", "frost", "poison", "sniper", "tesla"]
const CANDIDATE_SITES := [
	Vector2(108, 108), Vector2(108, 540), Vector2(324, 108), Vector2(324, 540),
	Vector2(486, 162), Vector2(486, 486), Vector2(702, 108), Vector2(702, 540),
	Vector2(243, 351), Vector2(648, 351), Vector2(378, 405), Vector2(756, 405),
]

var _errors: Array = []


func _initialize() -> void:
	var probe_game := _create_game()
	probe_game.reset_slice()
	var map_indices := _resolve_map_indices(probe_game)
	var schedule: Array = probe_game.game_data.get("waves", {}).get("schedule", [])
	var canonical_wave_row: Dictionary = schedule[WAVE_NUMBER - 1] if schedule.size() >= WAVE_NUMBER else {}
	_teardown_game(probe_game)

	if map_indices.size() != MAP_NAMES.size():
		_errors.append("Could not resolve every canonical map.")
	if int(canonical_wave_row.get("regular_enemy_count", -1)) != BASELINE_TANK_COUNT:
		_errors.append("Canonical wave 4 tank count changed before the counterfactual ran.")
	if str(canonical_wave_row.get("enemy_kind", "")) != "tank":
		_errors.append("Canonical wave 4 enemy kind is not tank.")

	var cases: Array = []
	for map_name in MAP_NAMES:
		for build_variant in BUILD_VARIANTS:
			for tank_count in VARIANT_TANK_COUNTS:
				for repeat_index in range(REPEAT_COUNT):
					cases.append(_run_case({
						"case_id": "%s_%s_tanks%s_repeat%s" % [_slug(map_name), build_variant, tank_count, repeat_index + 1],
						"map_name": map_name,
						"map_index": int(map_indices.get(map_name, -1)),
						"build_variant": build_variant,
						"tank_count": tank_count,
						"repeat_index": repeat_index + 1,
					}))

	var paired := _build_paired_comparisons(cases)
	var determinism := _build_determinism_checks(cases)
	var summary := _build_summary(cases)
	var gate := _build_candidate_gate(cases, summary, paired, determinism)
	var report := {
		"schema_version": 1,
		"evidence_only": true,
		"no_canonical_mutation": true,
		"seed": SEED,
		"matrix_definition": {
			"wave": WAVE_NUMBER,
			"canonical_baseline_tank_count": BASELINE_TANK_COUNT,
			"tank_count_variants": VARIANT_TANK_COUNTS,
			"maps": MAP_NAMES,
			"build_variants": BUILD_VARIANTS,
			"repeat_count": REPEAT_COUNT,
			"expected_case_count": MAP_NAMES.size() * BUILD_VARIANTS.size() * VARIANT_TANK_COUNTS.size() * REPEAT_COUNT,
		},
		"action_contract": {
			"setup_money": SETUP_MONEY,
			"setup_lives": SETUP_LIVES,
			"same_tower_roster": MIXED_TOWERS,
			"same_upgrade_recipe": "place every supported tower, then apply exactly one level-2 upgrade to each placed tower",
			"same_scaled_delta": STEP_DELTA,
			"same_cycle_limit": MAX_CYCLES,
			"override_scope": "in-memory wave 4 regular_enemy_count only; canonical data file is never written",
		},
		"canonical_wave_row": canonical_wave_row,
		"summary": summary,
		"case_results": cases,
		"paired_comparisons": paired,
		"determinism_checks": determinism,
		"candidate_gate": gate,
		"errors": _errors,
		"no_code_change_if": "Do not change wave 4 count or tank strength from aggregate telemetry alone; require this matched matrix, clean runtime invariants, deterministic repeats, and a predeclared allowlisted mutation contract.",
	}
	_write_report(report)
	if _errors.is_empty() and bool(gate.get("structural_all_passed", false)):
		print(OK_TOKEN)
		print("  Evidence: %s" % ProjectSettings.globalize_path(OUTPUT_PATH))
		quit(0)
	else:
		push_error("WAVE_PRESSURE_COUNTERFACTUAL_VALIDATION_FAILED")
		for error in _errors:
			push_error(str(error))
		quit(1)


func _run_case(spec: Dictionary) -> Dictionary:
	var game := _create_game()
	var map_index := int(spec.get("map_index", -1))
	var map_name := str(spec.get("map_name", ""))
	var build_variant := str(spec.get("build_variant", "mixed"))
	var tank_count := int(spec.get("tank_count", BASELINE_TANK_COUNT))
	var action_trace: Array = [
		{"action": "reset_slice", "map_index": map_index},
		{"action": "set_wave", "wave": WAVE_NUMBER},
		{"action": "override_wave4_tank_count", "tank_count": tank_count},
		{"action": "set_money", "money": SETUP_MONEY},
		{"action": "set_lives", "lives": SETUP_LIVES},
		{"action": "set_game_speed", "speed": 4.0},
	]
	game.reset_slice(map_index)
	var schedule: Array = game.game_data.get("waves", {}).get("schedule", [])
	var override_applied := schedule.size() >= WAVE_NUMBER and str(schedule[WAVE_NUMBER - 1].get("enemy_kind", "")) == "tank"
	if override_applied:
		schedule[WAVE_NUMBER - 1]["regular_enemy_count"] = tank_count
	else:
		_errors.append("%s did not expose a tank schedule row for wave 4." % str(spec.get("case_id", "")))
	game.money = SETUP_MONEY
	game.lives = SETUP_LIVES
	game.set_game_speed(4.0)
	var wave_setup: Dictionary = game.set_wave_for_test(WAVE_NUMBER)
	var placement_results: Array = []
	var sites := _candidate_site_scan(build_variant)
	for tower_type in MIXED_TOWERS:
		var placed := false
		var selected_site := Vector2.INF
		for site in sites:
			var preview: Dictionary = game.placement_preview_snapshot(site, tower_type)
			if not bool(preview.get("can_place", false)):
				continue
			selected_site = preview.get("snapped_site", site)
			placed = game.place_selected_tower(selected_site, tower_type)
			if placed:
				sites.erase(site)
				break
		placement_results.append({"tower_type": tower_type, "placed": placed, "site": [selected_site.x, selected_site.y] if placed else []})
		action_trace.append({"action": "place_tower", "tower_type": tower_type, "placed": placed})

	var upgrade_results: Array = []
	for tower_index in range(game.towers.size()):
		game.selected_tower_index = tower_index
		var upgraded: bool = game.upgrade_selected_tower()
		upgrade_results.append({"tower_index": tower_index, "upgraded": upgraded})
		action_trace.append({"action": "upgrade_tower", "tower_index": tower_index, "upgraded": upgraded})

	var start_succeeded: bool = game.start_wave()
	action_trace.append({"action": "start_wave", "started": start_succeeded})
	var cycles := 0
	if start_succeeded:
		for cycle in range(MAX_CYCLES):
			cycles = cycle + 1
			game.set_game_speed(4.0)
			game._process_scaled_delta(STEP_DELTA)
			var live_snapshot: Dictionary = game.snapshot()
			if bool(live_snapshot.get("game_over", false)) or bool(live_snapshot.get("wave_complete", false)):
				break

	var final_snapshot: Dictionary = game.snapshot()
	var final_state: Dictionary = game.serialize_run_state()
	var total_damage := 0.0
	var total_spend := 0
	for tower in final_state.get("towers", []):
		total_damage += float(tower.get("total_damage", 0.0))
		total_spend += int(tower.get("money_spent", 0))
	var result := {
		"case_id": str(spec.get("case_id", "")),
		"map_name": map_name,
		"map_index": map_index,
		"build_variant": build_variant,
		"tank_count": tank_count,
		"repeat_index": int(spec.get("repeat_index", 0)),
		"seed": SEED,
		"wave_setup": wave_setup,
		"override_applied": override_applied,
		"placement_results": placement_results,
		"upgrade_results": upgrade_results,
		"setup_valid": placement_results.size() == MIXED_TOWERS.size() and _all_placements_succeeded(placement_results) and _all_upgrades_succeeded(upgrade_results),
		"start_succeeded": start_succeeded,
		"enemy_kind": str(final_snapshot.get("enemy_family", "")),
		"spawn_limit": int(final_snapshot.get("spawn_limit", 0)),
		"spawn_interval": float(final_snapshot.get("spawn_interval", 0.0)),
		"completed": bool(final_snapshot.get("wave_complete", false)),
		"game_over": bool(final_snapshot.get("game_over", false)),
		"lives": int(final_snapshot.get("lives", 0)),
		"leaks": int(final_snapshot.get("leaks", 0)),
		"kills": int(final_snapshot.get("kills", 0)),
		"spawned": int(final_snapshot.get("spawned_this_wave", 0)) + int(final_snapshot.get("spawned_extra_this_wave", 0)),
		"cycles_to_resolution": cycles,
		"total_damage": total_damage,
		"total_spend": total_spend,
		"damage_per_spend": total_damage / float(max(1, total_spend)),
		"runtime_invariant_failures": game.runtime_invariant_failures(),
		"action_trace": action_trace,
	}
	_teardown_game(game)
	return result


func _build_summary(cases: Array) -> Dictionary:
	var by_variant := {}
	for tank_count in VARIANT_TANK_COUNTS:
		var rows: Array = []
		for result in cases:
			if int(result.get("tank_count", -1)) == tank_count:
				rows.append(result)
		var spawned := 0
		var leaks := 0
		var completed := 0
		var game_over := 0
		var total_damage := 0.0
		var spends := {}
		for row in rows:
			spawned += int(row.get("spawned", 0))
			leaks += int(row.get("leaks", 0))
			completed += 1 if bool(row.get("completed", false)) else 0
			game_over += 1 if bool(row.get("game_over", false)) else 0
			total_damage += float(row.get("total_damage", 0.0))
			spends[str(row.get("total_spend", 0))] = true
		by_variant[str(tank_count)] = {
			"case_count": rows.size(),
			"completed": completed,
			"completion_rate": float(completed) / float(max(1, rows.size())),
			"game_over": game_over,
			"game_over_rate": float(game_over) / float(max(1, rows.size())),
			"spawned": spawned,
			"leaks": leaks,
			"leak_rate": float(leaks) / float(max(1, spawned)),
			"avg_damage": total_damage / float(max(1, rows.size())),
			"spend_values": spends.keys(),
		}
	return {"by_tank_count": by_variant, "case_count": cases.size()}


func _build_candidate_gate(cases: Array, summary: Dictionary, paired: Dictionary, determinism: Array) -> Dictionary:
	var structural := true
	var setup_failures := 0
	var start_failures := 0
	var invariant_failures := 0
	var spend_values := {}
	for row in cases:
		if not bool(row.get("setup_valid", false)):
			setup_failures += 1
		if not bool(row.get("start_succeeded", false)):
			start_failures += 1
		invariant_failures += row.get("runtime_invariant_failures", []).size()
		spend_values[str(row.get("total_spend", 0))] = true
	structural = setup_failures == 0 and start_failures == 0 and invariant_failures == 0 and spend_values.size() == 1 and determinism.filter(func(item): return not bool(item.get("same", false))).is_empty()
	var baseline: Dictionary = summary.get("by_tank_count", {}).get("22", {})
	var recommendation_status := "no_candidate"
	var recommended_tank_count := 0
	for candidate in [20, 18]:
		var row: Dictionary = summary.get("by_tank_count", {}).get(str(candidate), {})
		var completion_delta := float(row.get("completion_rate", 0.0)) - float(baseline.get("completion_rate", 0.0))
		var leak_delta := float(row.get("leak_rate", 0.0)) - float(baseline.get("leak_rate", 0.0))
		var game_over_delta := float(row.get("game_over_rate", 0.0)) - float(baseline.get("game_over_rate", 0.0))
		if structural and completion_delta >= 0.10 and leak_delta <= -0.10 and game_over_delta <= -0.10:
			recommendation_status = "candidate_recommended"
			recommended_tank_count = candidate
			break
	return {
		"evidence_only": true,
		"structural_all_passed": structural,
		"setup_failure_count": setup_failures,
		"start_failure_count": start_failures,
		"runtime_invariant_failure_count": invariant_failures,
		"shared_total_spend": spend_values.size() == 1,
		"determinism_all_passed": determinism.filter(func(item): return not bool(item.get("same", false))).is_empty(),
		"recommendation_status": recommendation_status,
		"recommended_tank_count": recommended_tank_count,
		"gate_thresholds": {"completion_delta_min": 0.10, "leak_delta_max": -0.10, "game_over_delta_max": -0.10},
		"paired_comparison_count": paired.size(),
	}


func _build_paired_comparisons(cases: Array) -> Dictionary:
	var result := {}
	for map_name in MAP_NAMES:
		for build_variant in BUILD_VARIANTS:
			for repeat_index in range(1, REPEAT_COUNT + 1):
				var rows := {}
				for row in cases:
					if str(row.get("map_name", "")) == map_name and str(row.get("build_variant", "")) == build_variant and int(row.get("repeat_index", 0)) == repeat_index:
						rows[str(row.get("tank_count", 0))] = row
				if rows.size() != VARIANT_TANK_COUNTS.size():
					_errors.append("Missing paired rows for %s/%s/repeat%s." % [map_name, build_variant, repeat_index])
					continue
				for candidate in [20, 18]:
					result["%s_%s_repeat%s_%s_vs_22" % [_slug(map_name), build_variant, repeat_index, candidate]] = _compare_cases(rows[str(candidate)], rows["22"])
	return result


func _compare_cases(candidate: Dictionary, baseline: Dictionary) -> Dictionary:
	return {
		"candidate_tank_count": int(candidate.get("tank_count", 0)),
		"baseline_tank_count": int(baseline.get("tank_count", 0)),
		"completion_delta": (1 if bool(candidate.get("completed", false)) else 0) - (1 if bool(baseline.get("completed", false)) else 0),
		"game_over_delta": (1 if bool(candidate.get("game_over", false)) else 0) - (1 if bool(baseline.get("game_over", false)) else 0),
		"leak_delta": int(candidate.get("leaks", 0)) - int(baseline.get("leaks", 0)),
		"lives_delta": int(candidate.get("lives", 0)) - int(baseline.get("lives", 0)),
		"damage_delta": float(candidate.get("total_damage", 0.0)) - float(baseline.get("total_damage", 0.0)),
		"same_spend": int(candidate.get("total_spend", 0)) == int(baseline.get("total_spend", 0)),
	}


func _build_determinism_checks(cases: Array) -> Array:
	var checks: Array = []
	for map_name in MAP_NAMES:
		for build_variant in BUILD_VARIANTS:
			for tank_count in VARIANT_TANK_COUNTS:
				var rows := cases.filter(func(row): return str(row.get("map_name", "")) == map_name and str(row.get("build_variant", "")) == build_variant and int(row.get("tank_count", 0)) == tank_count)
				if rows.size() != REPEAT_COUNT:
					checks.append({"key": "%s/%s/%s" % [map_name, build_variant, tank_count], "same": false, "reason": "repeat count mismatch"})
					continue
				var left: Dictionary = rows[0]
				var right: Dictionary = rows[1]
				var same := true
				for key in ["enemy_kind", "spawn_limit", "spawned", "completed", "game_over", "lives", "leaks", "kills", "total_damage", "total_spend", "runtime_invariant_failures"]:
					if str(left.get(key, "")) != str(right.get(key, "")):
						same = false
				checks.append({"key": "%s/%s/tanks%s" % [map_name, build_variant, tank_count], "same": same})
	return checks


func _resolve_map_indices(game: Node) -> Dictionary:
	var result := {}
	for map_name in MAP_NAMES:
		var maps: Array = game.game_data.get("maps", {}).get("catalog", [])
		for index in range(maps.size()):
			if str(maps[index].get("name", "")) == map_name:
				result[map_name] = index
	return result


func _candidate_site_scan(build_variant: String) -> Array:
	var sites: Array = CANDIDATE_SITES.duplicate()
	if build_variant == "rotated_lane_priority":
		sites = [
			Vector2(702, 540), Vector2(702, 108), Vector2(486, 486), Vector2(486, 162),
			Vector2(324, 540), Vector2(324, 108), Vector2(108, 540), Vector2(108, 108),
			Vector2(648, 351), Vector2(243, 351), Vector2(756, 405), Vector2(378, 405),
		]
	var grid_sites: Array = []
	for y in range(108, 574, 27):
		for x in range(27, 901, 27):
			grid_sites.append(Vector2(x, y))
	sites.append_array(grid_sites)
	return sites


func _all_placements_succeeded(rows: Array) -> bool:
	for row in rows:
		if not bool(row.get("placed", false)):
			return false
	return true


func _all_upgrades_succeeded(rows: Array) -> bool:
	for row in rows:
		if not bool(row.get("upgraded", false)):
			return false
	return true


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
	config.name = "WavePressureConfig"
	data_loader.name = "WavePressureData"
	game.name = "WavePressureGame"
	return game


func _teardown_game(game: Node) -> void:
	game.set_process(false)
	game.set_physics_process(false)
	if game.get_parent() != null:
		game.get_parent().remove_child(game)
	game.free()


func _slug(value: String) -> String:
	return value.to_lower().replace(" ", "_")


func _write_report(report: Dictionary) -> void:
	var path := ProjectSettings.globalize_path(OUTPUT_PATH)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_errors.append("Could not write evidence to %s." % path)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
