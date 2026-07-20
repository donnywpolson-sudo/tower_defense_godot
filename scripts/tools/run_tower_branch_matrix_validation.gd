extends SceneTree

const OK_TOKEN := "TOWER_BRANCH_MATRIX_VALIDATION_OK"
const OUTPUT_PATH := "res://logs/godot/tower_branch_matrix_wave7plus_2026_07_14.json"
const START_WAVE := 7
const END_WAVE := 20
const SETUP_MONEY := 5000
const SETUP_LIVES := 5000
const STEP_DELTA := 0.2
const MAX_CYCLES_PER_WAVE := 900
const REPEAT_COUNT := 2
const SEED := 20240715
const MAP_NAMES := ["Classic Road", "Split Road", "Zigzag Road", "Spiral Road"]
const SUPPORTED_TOWERS := ["archer", "machine_gun", "cannon", "frost", "poison", "sniper", "tesla"]

var _errors: Array = []


func _initialize() -> void:
	var probe_game := _create_game()
	probe_game.reset_slice()
	var map_indices := _resolve_map_indices(probe_game)
	var game_data: Dictionary = probe_game.game_data
	var schedule: Array = game_data.get("waves", {}).get("schedule", [])
	var tower_data: Dictionary = game_data.get("towers", {})
	var branch_catalog := _branch_catalog(tower_data)
	var expected_spend := _expected_setup_spend(game_data)
	var canonical_rows := _canonical_wave_rows(schedule)
	_teardown_game(probe_game)

	_validate_contract_inputs(map_indices, tower_data, branch_catalog, canonical_rows, expected_spend)
	var cases: Array = []
	for tower_type in SUPPORTED_TOWERS:
		for branch_id in branch_catalog.get(tower_type, []):
			for map_name in MAP_NAMES:
				for repeat_index in range(REPEAT_COUNT):
					cases.append(_run_case({
						"case_id": "%s_%s_%s_repeat%s" % [_slug(tower_type), _slug(branch_id), _slug(map_name), repeat_index + 1],
						"tower_type": tower_type,
						"branch_id": branch_id,
						"map_name": map_name,
						"map_index": int(map_indices.get(map_name, -1)),
						"repeat_index": repeat_index + 1,
					}))

	var determinism := _build_determinism_checks(cases)
	var summary := _build_summary(cases, canonical_rows)
	var classifications := _classify_branches(cases, canonical_rows)
	var gate := _build_gate(cases, determinism, summary, map_indices, branch_catalog, expected_spend)
	var report := {
		"schema_version": 1,
		"evidence_only": true,
		"no_canonical_mutation": true,
		"mutation_authorized": false,
		"seed": SEED,
		"matrix_definition": {
			"tower_count": branch_catalog.size(),
			"branch_count": _branch_count(branch_catalog),
			"map_count": MAP_NAMES.size(),
			"repeat_count": REPEAT_COUNT,
			"case_count": _branch_count(branch_catalog) * MAP_NAMES.size() * REPEAT_COUNT,
			"start_wave": START_WAVE,
			"end_wave": END_WAVE,
			"waves": "canonical schedule rows 7 through 20 inclusive",
		},
		"action_contract": {
			"setup_money": SETUP_MONEY,
			"setup_lives": SETUP_LIVES,
			"same_roster": SUPPORTED_TOWERS,
			"same_upgrade_recipe": "all seven towers to level 2; focal tower selects the requested branch and reaches level 4",
			"expected_total_spend": expected_spend,
			"same_scaled_delta": STEP_DELTA,
			"same_cycle_limit_per_wave": MAX_CYCLES_PER_WAVE,
			"replay_mode": "sequential canonical progression from wave 7 through wave 20",
			"override_scope": "none; canonical wave data is read-only",
		},
		"canonical_wave_rows": canonical_rows,
		"branch_catalog": _branch_metadata(tower_data),
		"summary": summary,
		"branch_classifications": classifications,
		"case_results": cases,
		"determinism_checks": determinism,
		"gate": gate,
		"errors": _errors,
		"no_code_change_if": "Do not mutate tower or branch values from this report alone. Require a separate branch-specific allowlisted contract and focused validation for any change.",
	}
	_write_report(report)
	if _errors.is_empty() and bool(gate.get("all_passed", false)):
		print(OK_TOKEN)
		print("  Evidence: %s" % ProjectSettings.globalize_path(OUTPUT_PATH))
		quit(0)
	else:
		push_error("TOWER_BRANCH_MATRIX_VALIDATION_FAILED")
		for error in _errors:
			push_error(str(error))
		quit(1)


func _run_case(spec: Dictionary) -> Dictionary:
	var game := _create_game()
	var map_index := int(spec.get("map_index", -1))
	var tower_type := str(spec.get("tower_type", ""))
	var branch_id := str(spec.get("branch_id", ""))
	var map_name := str(spec.get("map_name", ""))
	var action_trace: Array = []
	game.reset_slice(map_index)
	game.money = SETUP_MONEY
	game.lives = SETUP_LIVES
	game.set_game_speed(4.0)
	game.set_wave_for_test(START_WAVE)
	action_trace.append({"action": "reset_slice", "map_index": map_index})
	action_trace.append({"action": "set_wave", "wave": START_WAVE})

	var placement_results: Array = []
	var sites := _grid_site_scan()
	for roster_tower in SUPPORTED_TOWERS:
		var placed := false
		var selected_site := Vector2.INF
		for site in sites:
			var preview: Dictionary = game.placement_preview_snapshot(site, roster_tower)
			if not bool(preview.get("can_place", false)):
				continue
			selected_site = preview.get("snapped_site", site)
			placed = game.place_selected_tower(selected_site, roster_tower)
			if placed:
				sites.erase(site)
				break
		placement_results.append({
				"tower_type": roster_tower,
				"placed": placed,
				"site": [selected_site.x, selected_site.y] if placed else [],
			})
		if not placed:
			_errors.append("%s could not place roster tower %s on %s." % [str(spec.get("case_id", "")), roster_tower, map_name])

	var focal_index := -1
	var upgrade_results: Array = []
	for tower_index in range(game.towers.size()):
		game.selected_tower_index = tower_index
		var roster_type := str(game.towers[tower_index].get("type", ""))
		var level_two: bool = game.upgrade_selected_tower()
		var branch_selected := true
		var branch_upgrade := false
		var level_four := false
		if roster_type == tower_type:
			focal_index = tower_index
			var selected: bool = game.choose_selected_tower_branch(branch_id)
			branch_selected = selected
			branch_upgrade = game.upgrade_selected_tower()
			level_four = game.upgrade_selected_tower()
		upgrade_results.append({
				"tower_index": tower_index,
				"tower_type": roster_type,
				"level_two": level_two,
				"branch_selected": branch_selected,
				"branch_upgrade": branch_upgrade,
				"level_four": level_four,
			})
		if not level_two or (roster_type == tower_type and (not branch_selected or not branch_upgrade or not level_four)):
			_errors.append("%s failed the level/branch setup for %s:%s." % [str(spec.get("case_id", "")), tower_type, branch_id])

	var setup_state: Dictionary = game.serialize_run_state()
	var towers_state: Array = setup_state.get("towers", [])
	var selected_branch := str(towers_state[focal_index].get("selected_branch", "")) if focal_index >= 0 and focal_index < towers_state.size() else ""
	var total_spend := _total_spend(towers_state)
	var wave_rows: Array = []
	var start_succeeded := true
	for target_wave in range(START_WAVE, END_WAVE + 1):
		if bool(game.snapshot().get("game_over", false)):
			break
		var reward_choice: Dictionary = game.reward_card_choice_snapshot()
		if bool(reward_choice.get("pending", false)):
			var choices: Array = reward_choice.get("choices", [])
			if not choices.is_empty():
				game.choose_reward_card(str(choices[0].get("id", "")))
			# The runtime's player-facing reward path caps lives at 99. Restore the
			# synthetic audit budget after selecting the required deterministic card
			# so late-wave coverage measures tower/branch behavior rather than the
			# reward cap. This is validator state only; no canonical data is changed.
			game.lives = SETUP_LIVES
		var before_state: Dictionary = game.serialize_run_state()
		var before_focal_damage := _tower_damage(before_state.get("towers", []), focal_index)
		var before_focal_kills := _tower_kills(before_state.get("towers", []), focal_index)
		var started: bool = game.start_wave()
		if not started:
			start_succeeded = false
			_errors.append("%s could not start wave %s." % [str(spec.get("case_id", "")), target_wave])
			break
		var cycles := 0
		for cycle in range(MAX_CYCLES_PER_WAVE):
			cycles = cycle + 1
			game.set_game_speed(4.0)
			game._process_scaled_delta(STEP_DELTA)
			var live_snapshot: Dictionary = game.snapshot()
			if bool(live_snapshot.get("game_over", false)) or bool(live_snapshot.get("wave_complete", false)):
				break
		var final_snapshot: Dictionary = game.snapshot()
		var final_state: Dictionary = game.serialize_run_state()
		var final_towers: Array = final_state.get("towers", [])
		var wave_row: Dictionary = {
				"wave": target_wave,
				"enemy_kind": str(final_snapshot.get("enemy_family", "")),
				"spawn_limit": int(final_snapshot.get("spawn_limit", 0)),
				"spawned": int(final_snapshot.get("spawned_total_this_wave", 0)),
				"spawned_boss": int(final_snapshot.get("spawned_boss_this_wave", 0)),
				"spawned_commander": int(final_snapshot.get("spawned_commander_this_wave", 0)),
				"completed": bool(final_snapshot.get("wave_complete", false)),
				"game_over": bool(final_snapshot.get("game_over", false)),
				"stalled": not bool(final_snapshot.get("wave_complete", false)) and not bool(final_snapshot.get("game_over", false)),
				"lives": int(final_snapshot.get("lives", 0)),
				"leaks": int(final_snapshot.get("leaks", 0)),
				"kills": int(final_snapshot.get("kills", 0)),
				"cycles": cycles,
				"focal_damage": _tower_damage(final_towers, focal_index),
				"focal_damage_delta": _tower_damage(final_towers, focal_index) - before_focal_damage,
				"focal_kills": _tower_kills(final_towers, focal_index),
				"focal_kills_delta": _tower_kills(final_towers, focal_index) - before_focal_kills,
				"total_damage": _total_damage(final_towers),
				"total_spend": _total_spend(final_towers),
				"modifier": _wave_modifier(final_snapshot),
			}
		wave_rows.append(wave_row)
		if bool(wave_row.get("game_over", false)):
			break

	var final_state: Dictionary = game.serialize_run_state()
	var result := {
		"case_id": str(spec.get("case_id", "")),
		"tower_type": tower_type,
		"branch_id": branch_id,
		"map_name": map_name,
		"map_index": map_index,
		"repeat_index": int(spec.get("repeat_index", 0)),
		"seed": SEED,
		"placement_results": placement_results,
		"upgrade_results": upgrade_results,
		"focal_index": focal_index,
		"selected_branch": selected_branch,
		"branch_selected": selected_branch == branch_id,
		"setup_valid": placement_results.size() == SUPPORTED_TOWERS.size() and _all_placed(placement_results) and _all_level_two(upgrade_results) and focal_index >= 0,
		"start_succeeded": start_succeeded,
		"total_spend": _total_spend(final_state.get("towers", [])),
		"final_lives": int(game.snapshot().get("lives", 0)),
		"final_game_over": bool(game.snapshot().get("game_over", false)),
		"wave_rows": wave_rows,
		"runtime_invariant_failures": game.runtime_invariant_failures(),
		"action_trace": action_trace,
	}
	_teardown_game(game)
	return result


func _build_gate(cases: Array, determinism: Array, summary: Dictionary, map_indices: Dictionary, branch_catalog: Dictionary, expected_spend: int) -> Dictionary:
	var setup_failures := 0
	var branch_failures := 0
	var start_failures := 0
	var invariant_failures := 0
	var spend_values := {}
	var observed_towers := {}
	var observed_branches := {}
	var observed_maps := {}
	var observed_waves := {}
	for row in cases:
		if not bool(row.get("setup_valid", false)):
			setup_failures += 1
		if not bool(row.get("branch_selected", false)):
			branch_failures += 1
		if not bool(row.get("start_succeeded", false)):
			start_failures += 1
		invariant_failures += row.get("runtime_invariant_failures", []).size()
		spend_values[str(row.get("total_spend", 0))] = true
		observed_towers[str(row.get("tower_type", ""))] = true
		observed_branches["%s:%s" % [str(row.get("tower_type", "")), str(row.get("branch_id", ""))]] = true
		observed_maps[str(row.get("map_name", ""))] = true
		for wave_row in row.get("wave_rows", []):
			observed_waves[str(wave_row.get("wave", 0))] = true
	var expected_case_count: int = _branch_count(branch_catalog) * MAP_NAMES.size() * REPEAT_COUNT
	var structural := cases.size() == expected_case_count and setup_failures == 0 and branch_failures == 0 and start_failures == 0 and invariant_failures == 0 and spend_values.size() == 1 and spend_values.has(str(expected_spend))
	var coverage := observed_towers.size() == branch_catalog.size() and observed_branches.size() == _branch_count(branch_catalog) and observed_maps.size() == MAP_NAMES.size() and observed_waves.size() == END_WAVE - START_WAVE + 1
	var deterministic := determinism.filter(func(item): return not bool(item.get("same", false))).is_empty()
	return {
		"all_passed": structural and coverage and deterministic,
		"structural_all_passed": structural,
		"coverage_all_passed": coverage,
		"determinism_all_passed": deterministic,
		"expected_case_count": expected_case_count,
		"actual_case_count": cases.size(),
		"setup_failure_count": setup_failures,
		"branch_selection_failure_count": branch_failures,
		"start_failure_count": start_failures,
		"runtime_invariant_failure_count": invariant_failures,
		"spend_values": spend_values.keys(),
		"expected_total_spend": expected_spend,
		"observed_tower_count": observed_towers.size(),
		"observed_branch_count": observed_branches.size(),
		"observed_map_count": observed_maps.size(),
		"observed_wave_count": observed_waves.size(),
		"required_wave_range": [START_WAVE, END_WAVE],
		"mutation_authorized": false,
	}


func _build_summary(cases: Array, canonical_rows: Dictionary) -> Dictionary:
	var by_branch := {}
	for row in cases:
		var key := "%s:%s" % [str(row.get("tower_type", "")), str(row.get("branch_id", ""))]
		if not by_branch.has(key):
			by_branch[key] = {"tower_type": row.get("tower_type", ""), "branch_id": row.get("branch_id", ""), "case_count": 0, "completed_cases": 0, "game_over_cases": 0, "leaks": 0, "spawned": 0, "focal_damage": 0.0, "focal_kills": 0, "wave_rows": 0}
		var aggregate: Dictionary = by_branch[key]
		aggregate["case_count"] = int(aggregate.get("case_count", 0)) + 1
		aggregate["completed_cases"] = int(aggregate.get("completed_cases", 0)) + (0 if bool(row.get("final_game_over", false)) else 1)
		aggregate["game_over_cases"] = int(aggregate.get("game_over_cases", 0)) + (1 if bool(row.get("final_game_over", false)) else 0)
		for wave_row in row.get("wave_rows", []):
			aggregate["leaks"] = int(aggregate.get("leaks", 0)) + int(wave_row.get("leaks", 0))
			aggregate["spawned"] = int(aggregate.get("spawned", 0)) + int(wave_row.get("spawned", 0))
			aggregate["focal_damage"] = float(aggregate.get("focal_damage", 0.0)) + float(wave_row.get("focal_damage_delta", 0.0))
			aggregate["focal_kills"] = int(aggregate.get("focal_kills", 0)) + int(wave_row.get("focal_kills_delta", 0))
			aggregate["wave_rows"] = int(aggregate.get("wave_rows", 0)) + 1
	for aggregate in by_branch.values():
		aggregate["leak_rate"] = float(aggregate.get("leaks", 0)) / float(max(1, int(aggregate.get("spawned", 0))))
		aggregate["avg_focal_damage"] = float(aggregate.get("focal_damage", 0.0)) / float(max(1, int(aggregate.get("case_count", 0))))
		aggregate["completion_rate"] = float(aggregate.get("completed_cases", 0)) / float(max(1, int(aggregate.get("case_count", 0))))
	return {"by_branch": by_branch, "canonical_wave_count": canonical_rows.size(), "case_count": cases.size()}


func _classify_branches(cases: Array, canonical_rows: Dictionary) -> Dictionary:
	var by_branch_wave := {}
	for row in cases:
		var key := "%s:%s" % [str(row.get("tower_type", "")), str(row.get("branch_id", ""))]
		for wave_row in row.get("wave_rows", []):
			var wave_key := "%s/%s" % [key, str(wave_row.get("wave", 0))]
			if not by_branch_wave.has(wave_key):
				by_branch_wave[wave_key] = {"damage": 0.0, "leaks": 0, "rows": 0, "completed": 0}
			var aggregate: Dictionary = by_branch_wave[wave_key]
			aggregate["damage"] = float(aggregate.get("damage", 0.0)) + float(wave_row.get("focal_damage_delta", 0.0))
			aggregate["leaks"] = int(aggregate.get("leaks", 0)) + int(wave_row.get("leaks", 0))
			aggregate["rows"] = int(aggregate.get("rows", 0)) + 1
			aggregate["completed"] = int(aggregate.get("completed", 0)) + (1 if bool(wave_row.get("completed", false)) else 0)
	var result := {}
	for key in by_branch_wave.keys():
		var parts := str(key).split("/")
		var branch_key := parts[0]
		var wave := int(parts[1])
		if not result.has(branch_key):
			result[branch_key] = {"tower_type": branch_key.split(":")[0], "branch_id": branch_key.split(":")[1], "windows": {}, "wins": 0, "losses": 0, "classification": "insufficient_evidence"}
		var row: Dictionary = by_branch_wave[key]
		result[branch_key]["windows"][str(wave)] = {
			"enemy_kind": canonical_rows.get(str(wave), {}).get("enemy_kind", ""),
			"modifier": canonical_rows.get(str(wave), {}).get("modifier", ""),
			"avg_focal_damage": float(row.get("damage", 0.0)) / float(max(1, int(row.get("rows", 0)))),
			"avg_leaks": float(row.get("leaks", 0)) / float(max(1, int(row.get("rows", 0)))),
			"completion_rate": float(row.get("completed", 0)) / float(max(1, int(row.get("rows", 0)))),
		}
	for tower_type in SUPPORTED_TOWERS:
		var branch_keys: Array = []
		for key in result.keys():
			if str(key).begins_with("%s:" % tower_type):
				branch_keys.append(str(key))
		for wave in range(START_WAVE, END_WAVE + 1):
			var ranked_damage := branch_keys.duplicate()
			ranked_damage.sort_custom(func(left, right): return float(result[left]["windows"].get(str(wave), {}).get("avg_focal_damage", 0.0)) > float(result[right]["windows"].get(str(wave), {}).get("avg_focal_damage", 0.0)))
			var ranked_leaks := branch_keys.duplicate()
			ranked_leaks.sort_custom(func(left, right): return float(result[left]["windows"].get(str(wave), {}).get("avg_leaks", 999999.0)) < float(result[right]["windows"].get(str(wave), {}).get("avg_leaks", 999999.0)))
			if ranked_damage.size() > 0:
				result[ranked_damage[0]]["wins"] = int(result[ranked_damage[0]].get("wins", 0)) + 1
			if ranked_leaks.size() > 0:
				result[ranked_leaks[0]]["wins"] = int(result[ranked_leaks[0]].get("wins", 0)) + 1
	for key in result.keys():
		var record: Dictionary = result[key]
		var total_windows := (END_WAVE - START_WAVE + 1) * 2
		var wins := int(record.get("wins", 0))
		if wins >= int(ceil(float(total_windows) * 0.75)):
			record["classification"] = "dominance_risk"
		elif wins == 0:
			record["classification"] = "insufficient_evidence"
		else:
			record["classification"] = "distinct_job_candidate"
	return result


func _build_determinism_checks(cases: Array) -> Array:
	var checks: Array = []
	var keys := {}
	for row in cases:
		var key := "%s:%s:%s" % [str(row.get("tower_type", "")), str(row.get("branch_id", "")), str(row.get("map_name", ""))]
		if not keys.has(key):
			keys[key] = []
		keys[key].append(row)
	for key in keys.keys():
		var rows: Array = keys[key]
		rows.sort_custom(func(left, right): return int(left.get("repeat_index", 0)) < int(right.get("repeat_index", 0)))
		var same := rows.size() == REPEAT_COUNT
		if same:
			same = JSON.stringify(_normalized_case(rows[0])) == JSON.stringify(_normalized_case(rows[1]))
		checks.append({"key": key, "same": same, "repeat_count": rows.size()})
	return checks


func _normalized_case(row: Dictionary) -> Dictionary:
	var waves: Array = []
	for wave_row in row.get("wave_rows", []):
		waves.append({
			"wave": int(wave_row.get("wave", 0)),
			"enemy_kind": str(wave_row.get("enemy_kind", "")),
			"spawned": int(wave_row.get("spawned", 0)),
			"spawned_boss": int(wave_row.get("spawned_boss", 0)),
			"spawned_commander": int(wave_row.get("spawned_commander", 0)),
			"completed": bool(wave_row.get("completed", false)),
			"game_over": bool(wave_row.get("game_over", false)),
			"lives": int(wave_row.get("lives", 0)),
			"leaks": int(wave_row.get("leaks", 0)),
			"kills": int(wave_row.get("kills", 0)),
			"focal_damage_delta": float(wave_row.get("focal_damage_delta", 0.0)),
			"focal_kills_delta": int(wave_row.get("focal_kills_delta", 0)),
			"total_damage": float(wave_row.get("total_damage", 0.0)),
			"modifier": str(wave_row.get("modifier", "")),
		})
	return {"total_spend": int(row.get("total_spend", 0)), "selected_branch": str(row.get("selected_branch", "")), "wave_rows": waves}


func _validate_contract_inputs(map_indices: Dictionary, tower_data: Dictionary, branch_catalog: Dictionary, canonical_rows: Dictionary, expected_spend: int) -> void:
	if map_indices.size() != MAP_NAMES.size():
		_errors.append("Could not resolve every canonical map.")
	if tower_data.get("branch_unlock_level", 0) != 3:
		_errors.append("Branch unlock level is not the expected level 3.")
	if _branch_count(branch_catalog) != 7:
		_errors.append("Expected seven runtime-enabled branch definitions.")
	if expected_spend <= 0:
		_errors.append("Could not compute a positive matched setup spend.")
	for wave in range(START_WAVE, END_WAVE + 1):
		if not canonical_rows.has(str(wave)):
			_errors.append("Canonical schedule is missing wave %s." % wave)


func _canonical_wave_rows(schedule: Array) -> Dictionary:
	var result := {}
	for wave in range(START_WAVE, END_WAVE + 1):
		if wave - 1 >= schedule.size():
			continue
		var row: Dictionary = schedule[wave - 1]
		result[str(wave)] = {
			"wave": wave,
			"enemy_kind": str(row.get("enemy_kind", "")),
			"regular_enemy_count": int(row.get("regular_enemy_count", 0)),
			"spawn_interval": float(row.get("spawn_interval", 0.0)),
			"boss_count": int(row.get("boss_count", 0)),
			"commander_count": int(row.get("commander_count", 0)),
			"modifier": str(row.get("modifier", "")),
		}
	return result


func _branch_catalog(tower_data: Dictionary) -> Dictionary:
	var result := {}
	var definitions: Dictionary = tower_data.get("branch_definitions", {})
	var enabled: Dictionary = tower_data.get("runtime_enabled_branches", {})
	for tower_type in enabled:
		var branch_defs: Dictionary = definitions.get(tower_type, {})
		var branch_ids: Array = []
		for branch_id in enabled.get(tower_type, []):
			if branch_defs.has(str(branch_id)):
				branch_ids.append(str(branch_id))
		result[str(tower_type)] = branch_ids
	return result


func _branch_metadata(tower_data: Dictionary) -> Dictionary:
	var result := {}
	var definitions: Dictionary = tower_data.get("branch_definitions", {})
	for tower_type in _branch_catalog(tower_data):
		result[tower_type] = {}
		var branch_defs: Dictionary = definitions.get(tower_type, {})
		for branch_id in _branch_catalog(tower_data).get(tower_type, []):
			var branch: Dictionary = branch_defs[branch_id]
			result[tower_type][str(branch_id)] = {
				"role": str(branch.get("role", "")),
				"focus": str(branch.get("focus", "")),
				"signature": str(branch.get("signature", "")),
				"mechanics": str(branch.get("mechanics", "")),
			}
	return result


func _expected_setup_spend(game_data: Dictionary) -> int:
	var towers: Dictionary = game_data.get("towers", {})
	var costs: Dictionary = towers.get("shop_costs", {})
	var upgrades: Dictionary = game_data.get("upgrades", {}).get("tower_upgrade_costs", {})
	var total := 0
	for tower_type in SUPPORTED_TOWERS:
		total += int(costs.get(tower_type, 0))
		total += int(upgrades.get("1", upgrades.get(1, 0)))
	var focal_extra := int(upgrades.get("2", upgrades.get(2, 0))) + int(upgrades.get("3", upgrades.get(3, 0)))
	return total + focal_extra


func _grid_site_scan() -> Array:
	var sites: Array = []
	for y in range(108, 574, 27):
		for x in range(27, 901, 27):
			sites.append(Vector2(x, y))
	return sites


func _all_placed(rows: Array) -> bool:
	for row in rows:
		if not bool(row.get("placed", false)):
			return false
	return true


func _all_level_two(rows: Array) -> bool:
	for row in rows:
		if not bool(row.get("level_two", false)):
			return false
	return true


func _tower_damage(towers: Array, index: int) -> float:
	if index < 0 or index >= towers.size():
		return 0.0
	return float(towers[index].get("total_damage", 0.0))


func _tower_kills(towers: Array, index: int) -> int:
	if index < 0 or index >= towers.size():
		return 0
	return int(towers[index].get("kills", 0))


func _total_damage(towers: Array) -> float:
	var total := 0.0
	for tower in towers:
		total += float(tower.get("total_damage", 0.0))
	return total


func _total_spend(towers: Array) -> int:
	var total := 0
	for tower in towers:
		total += int(tower.get("money_spent", 0))
	return total


func _wave_modifier(snapshot: Dictionary) -> String:
	var forecast: Dictionary = snapshot.get("wave_forecast", {})
	return str(forecast.get("modifier", forecast.get("modifier_id", "")))


func _branch_count(catalog: Dictionary) -> int:
	var total := 0
	for values in catalog.values():
		total += values.size()
	return total


func _resolve_map_indices(game: Node) -> Dictionary:
	var result := {}
	var maps: Array = game.game_data.get("maps", {}).get("catalog", [])
	for map_name in MAP_NAMES:
		for index in range(maps.size()):
			if str(maps[index].get("name", "")) == map_name:
				result[map_name] = index
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
	config.name = "TowerBranchMatrixConfig"
	data_loader.name = "TowerBranchMatrixData"
	game.name = "TowerBranchMatrixGame"
	return game


func _teardown_game(game: Node) -> void:
	game.set_process(false)
	game.set_physics_process(false)
	if game.get_parent() != null:
		game.get_parent().remove_child(game)
	game.free()


func _slug(value: String) -> String:
	return value.to_lower().replace(" ", "_").replace(":", "_")


func _write_report(report: Dictionary) -> void:
	var path := ProjectSettings.globalize_path(OUTPUT_PATH)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_errors.append("Could not write evidence to %s." % path)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
