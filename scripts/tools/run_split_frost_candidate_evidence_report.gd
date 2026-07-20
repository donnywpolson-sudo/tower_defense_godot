extends SceneTree

const INPUT_PATH := "res://logs/godot/split_frost_broader_paired_replay_2026_07_14.json"
const JSON_OUTPUT_PATH := "res://logs/godot/split_frost_candidate_evidence_2026_07_14.json"
const MARKDOWN_OUTPUT_PATH := "res://logs/godot/split_frost_candidate_evidence_2026_07_14.md"
const EXPECTED_CANDIDATE_COUNT := 20

var _errors: Array[String] = []


func _initialize() -> void:
	var source_path := ProjectSettings.globalize_path(INPUT_PATH)
	if not FileAccess.file_exists(source_path):
		_fail("Source artifact does not exist: %s" % source_path)
		return

	var source_file := FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		_fail("Could not open source artifact: %s" % source_path)
		return
	var parsed: Variant = JSON.parse_string(source_file.get_as_text())
	source_file.close()
	if not parsed is Dictionary:
		_fail("Source artifact is not a JSON object.")
		return

	var source: Dictionary = parsed
	var cases: Array = source.get("broader_case_results", [])
	var paired_deltas: Dictionary = source.get("broader_paired_deltas", {})
	var candidates: Array = source.get("broader_summary", {}).get("candidate_branch_advantages", [])
	var case_by_id := _index_cases(cases)
	var candidate_entries: Array = []
	var condition_groups: Dictionary = {}
	var family_groups: Dictionary = {}
	var seen_pair_keys: Dictionary = {}

	if candidates.size() != EXPECTED_CANDIDATE_COUNT:
		_errors.append("Expected %d candidates, found %d." % [EXPECTED_CANDIDATE_COUNT, candidates.size()])

	for candidate in candidates:
		if not candidate is Dictionary:
			_errors.append("Candidate entry is not an object.")
			continue
		var candidate_data: Dictionary = candidate
		var pair_key := str(candidate_data.get("pair_key", ""))
		if pair_key.is_empty() or seen_pair_keys.has(pair_key):
			_errors.append("Candidate pair key is missing or duplicated: %s" % pair_key)
			continue
		seen_pair_keys[pair_key] = true
		var comparison_variant: Variant = paired_deltas.get(pair_key, null)
		if not comparison_variant is Dictionary:
			_errors.append("Missing paired comparison for %s." % pair_key)
			continue
		var comparison: Dictionary = comparison_variant
		var left_case_id := str(comparison.get("left_case", ""))
		var right_case_id := str(comparison.get("right_case", ""))
		var left_case: Dictionary = case_by_id.get(left_case_id, {})
		var right_case: Dictionary = case_by_id.get(right_case_id, {})
		_validate_match(pair_key, comparison, left_case, right_case)
		if left_case.is_empty() or right_case.is_empty():
			continue

		var entry := _candidate_entry(candidate_data, comparison, left_case, right_case)
		candidate_entries.append(entry)
		_append_group(condition_groups, str(entry["condition_key"]), entry)
		_append_group(family_groups, str(entry["family_key"]), entry)

	var condition_summaries := _build_condition_summaries(condition_groups, family_groups)
	var family_summaries := _build_family_summaries(family_groups, condition_groups)
	var gate := _build_deterministic_gate(source, cases, candidate_entries)
	var report := _build_report(source, candidate_entries, condition_summaries, family_summaries, gate)
	if not _errors.is_empty():
		report["validation_passed"] = false
		report["validation_errors"] = _errors.duplicate()
		_write_json(report)
		_write_markdown(report)
		_fail("Evidence report validation failed: %s" % "; ".join(_errors))
		return

	_write_json(report)
	_write_markdown(report)
	print("SPLIT_FROST_CANDIDATE_EVIDENCE_REPORT_OK")
	print("  JSON: %s" % ProjectSettings.globalize_path(JSON_OUTPUT_PATH))
	print("  Markdown: %s" % ProjectSettings.globalize_path(MARKDOWN_OUTPUT_PATH))
	quit(0)


func _index_cases(cases: Array) -> Dictionary:
	var result := {}
	for value in cases:
		if value is Dictionary:
			var case_data: Dictionary = value
			result[str(case_data.get("case_id", ""))] = case_data
	return result


func _validate_match(pair_key: String, comparison: Dictionary, left_case: Dictionary, right_case: Dictionary) -> void:
	if left_case.is_empty() or right_case.is_empty():
		_errors.append("Missing case data for %s." % pair_key)
		return
	if str(comparison.get("left_variant", "")) not in ["glacier", "shatter"] or str(comparison.get("right_variant", "")) != "no_frost":
		_errors.append("Unexpected variants for %s." % pair_key)
	var match_fields := [
		"map_index",
		"map_name",
		"wave_requested",
		"enemy_kind_requested",
		"layout_id",
		"build_variant",
		"seed",
		"repeat_index",
	]
	for field in match_fields:
		if left_case.get(field, null) != right_case.get(field, null):
			_errors.append("Unmatched %s for %s." % [field, pair_key])
	if _placement_topology(left_case) != _placement_topology(right_case):
		_errors.append("Unmatched placement topology for %s." % pair_key)
	if int(left_case.get("repeat_index", 0)) not in [1, 2] or int(right_case.get("repeat_index", 0)) not in [1, 2]:
		_errors.append("Unexpected repeat index for %s." % pair_key)


func _placement_topology(case_data: Dictionary) -> String:
	var topology: Array = []
	for placement in case_data.get("placement_results", []):
		if not placement is Dictionary:
			topology.append({"placed": false, "site": []})
			continue
		var placement_data: Dictionary = placement
		topology.append({
			"placed": bool(placement_data.get("placed", false)),
			"site": placement_data.get("site", []),
		})
	return JSON.stringify(topology)


func _candidate_entry(candidate: Dictionary, comparison: Dictionary, left_case: Dictionary, right_case: Dictionary) -> Dictionary:
	var branch := str(candidate.get("branch", comparison.get("left_variant", "")))
	var reasons: Array = candidate.get("reasons", [])
	var reason_text := ",".join(reasons.map(func(value): return str(value)))
	var map_name := str(left_case.get("map_name", comparison.get("left_map", "")))
	var wave := int(left_case.get("wave_requested", comparison.get("wave", 0)))
	var enemy := str(left_case.get("enemy_kind_requested", ""))
	var layout := str(left_case.get("layout_id", comparison.get("layout_id", "")))
	var build := str(left_case.get("build_variant", comparison.get("build_variant", "")))
	var family_key := _key([branch, map_name, wave, enemy, reason_text])
	var condition_key := _key([branch, map_name, wave, enemy, layout, build, reason_text])
	var deltas: Dictionary = comparison.get("deltas", {})
	return {
		"pair_key": str(candidate.get("pair_key", "")),
		"branch": branch,
		"map": map_name,
		"wave": wave,
		"enemy_kind": enemy,
		"layout": layout,
		"build_variant": build,
		"repeat": int(left_case.get("repeat_index", 0)),
		"reasons": reasons,
		"condition_key": condition_key,
		"family_key": family_key,
		"metrics": {
			"completion": _metric(deltas, "completed"),
			"lives": _metric(deltas, "lives"),
			"leaks": _metric(deltas, "leaks"),
			"total_damage": _metric(deltas, "total_damage"),
			"total_spend": _metric(deltas, "total_spend"),
			"damage_per_spend": _metric(deltas, "damage_per_spend"),
			"frost_total_damage": _metric(deltas, "frost_total_damage"),
			"slow_observations": _metric(deltas, "slow_observations"),
			"freeze_observations": _metric(deltas, "freeze_observations"),
			"shatter_observations": _metric(deltas, "shatter_observations"),
			"min_slow_multiplier": _metric(deltas, "min_slow_multiplier"),
			"max_shatter_vulnerability": _metric(deltas, "max_shatter_vulnerability"),
		},
	}


func _metric(deltas: Dictionary, metric_name: String) -> Dictionary:
	var row: Dictionary = deltas.get(metric_name, {})
	return {
		"branch": row.get("left", null),
		"no_frost": row.get("right", null),
		"delta": row.get("delta", null),
		"same": row.get("same", null),
	}


func _append_group(groups: Dictionary, key: String, entry: Dictionary) -> void:
	var entries: Array = groups.get(key, [])
	entries.append(entry)
	groups[key] = entries


func _build_condition_summaries(condition_groups: Dictionary, family_groups: Dictionary) -> Array:
	var result: Array = []
	var keys := condition_groups.keys()
	keys.sort()
	for key in keys:
		var entries: Array = condition_groups[key]
		var first: Dictionary = entries[0]
		var family_entries: Array = family_groups[first["family_key"]]
		var repeats: Array = []
		for entry in entries:
			repeats.append(int(entry["repeat"]))
		repeats.sort()
		var classification := "isolated"
		if entries.size() == 2 and repeats == [1, 2]:
			classification = "mixed" if _family_condition_count(family_entries) > 1 else "repeated"
		result.append({
			"branch": first["branch"],
			"map": first["map"],
			"wave": first["wave"],
			"enemy_kind": first["enemy_kind"],
			"layout": first["layout"],
			"build_variant": first["build_variant"],
			"reasons": first["reasons"],
			"repeat_indices": repeats,
			"candidate_count": entries.size(),
			"classification": classification,
			"pair_keys": entries.map(func(entry): return entry["pair_key"]),
		})
	return result


func _build_family_summaries(family_groups: Dictionary, condition_groups: Dictionary) -> Array:
	var result: Array = []
	var keys := family_groups.keys()
	keys.sort()
	for key in keys:
		var entries: Array = family_groups[key]
		var condition_keys: Array = []
		for entry in entries:
			if not condition_keys.has(entry["condition_key"]):
				condition_keys.append(entry["condition_key"])
		var classification := "isolated"
		if entries.size() >= 2:
			classification = "mixed" if condition_keys.size() > 1 else "repeated"
		var first: Dictionary = entries[0]
		result.append({
			"branch": first["branch"],
			"map": first["map"],
			"wave": first["wave"],
			"enemy_kind": first["enemy_kind"],
			"reasons": first["reasons"],
			"candidate_count": entries.size(),
			"condition_count": condition_keys.size(),
			"classification": classification,
			"conditions": _condition_labels(condition_keys, condition_groups),
		})
	return result


func _family_condition_count(entries: Array) -> int:
	var keys: Array = []
	for entry in entries:
		if not keys.has(entry["condition_key"]):
			keys.append(entry["condition_key"])
	return keys.size()


func _condition_labels(keys: Array, condition_groups: Dictionary) -> Array:
	var labels: Array = []
	for key in keys:
		var entries: Array = condition_groups[key]
		var first: Dictionary = entries[0]
		labels.append({
			"layout": first["layout"],
			"build_variant": first["build_variant"],
			"repeats": entries.size(),
		})
	return labels


func _build_deterministic_gate(source: Dictionary, cases: Array, entries: Array) -> Dictionary:
	var structural := _build_gate_structural_checks(source, cases, entries)
	var branch_results := {}
	var raw_qualifying_branches: Array = []
	var qualifying_branches: Array = []
	var raw_qualifying_maps: Dictionary = {}
	var qualifying_maps: Dictionary = {}
	var raw_qualifying_conditions: Array = []
	var qualifying_conditions: Array = []
	var normalized_advantage_repeat_count := 0
	var normalized_advantage_repeat_total := 0
	var normalized_rejection_reasons: Array = []
	for branch in ["glacier", "shatter"]:
		var branch_result := _evaluate_branch_gate(str(branch), entries)
		branch_results[str(branch)] = branch_result
		if bool(branch_result.get("raw_gate_passed", false)):
			raw_qualifying_branches.append(str(branch))
			for map_name in branch_result.get("raw_qualifying_maps", []):
				raw_qualifying_maps[str(map_name)] = true
			raw_qualifying_conditions.append_array(branch_result.get("raw_qualifying_conditions", []))
		if bool(branch_result.get("gate_passed", false)):
			qualifying_branches.append(str(branch))
			for map_name in branch_result.get("qualifying_maps", []):
				qualifying_maps[str(map_name)] = true
			qualifying_conditions.append_array(branch_result.get("qualifying_conditions", []))
		for condition_result in branch_result.get("raw_qualifying_conditions", []):
			normalized_advantage_repeat_count += int(condition_result.get("normalized_advantage_repeat_count", 0))
			normalized_advantage_repeat_total += int(condition_result.get("repeat_indices", []).size())
		normalized_rejection_reasons.append_array(branch_result.get("normalized_rejection_reasons", []))
	var rejection_reasons: Array = []
	rejection_reasons.append_array(structural.get("rejection_reasons", []))
	if raw_qualifying_branches.is_empty():
		rejection_reasons.append("No branch met the two-map and two-build-layout survival-repeat threshold.")
	if qualifying_branches.is_empty():
		rejection_reasons.append("No raw qualifying branch met the cost-neutral normalized-damage threshold.")
	var raw_gate_passed := bool(structural.get("all_passed", false)) and not raw_qualifying_branches.is_empty()
	var cost_neutral_gate_passed := bool(structural.get("all_passed", false)) and not qualifying_branches.is_empty()
	return {
		"gate_passed": cost_neutral_gate_passed,
		"raw_gate_passed": raw_gate_passed,
		"cost_neutral_gate_passed": cost_neutral_gate_passed,
		"tuning_authorized": cost_neutral_gate_passed,
		"requirements": {
			"minimum_maps": 2,
			"minimum_distinct_build_layout_conditions": 2,
			"required_repeats": [1, 2],
			"required_survival_metrics": ["completion", "lives", "leaks"],
			"spend_normalized_damage_is_reported": true,
			"spend_normalized_damage_is_gate_threshold": true,
			"normalized_damage_must_pass_every_repeat_and_condition": true,
		},
		"structural_checks": structural,
		"branch_results": branch_results,
		"raw_qualifying_branches": raw_qualifying_branches,
		"qualifying_branches": qualifying_branches,
		"raw_qualifying_maps": raw_qualifying_maps.keys(),
		"qualifying_maps": qualifying_maps.keys(),
		"raw_qualifying_conditions": raw_qualifying_conditions,
		"qualifying_conditions": qualifying_conditions,
		"normalized_advantage_repeat_count": normalized_advantage_repeat_count,
		"normalized_advantage_repeat_total": normalized_advantage_repeat_total,
		"normalized_rejection_reasons": _unique_strings(normalized_rejection_reasons),
		"rejection_reasons": rejection_reasons,
		"decision_note": "This report emits authorization state only; it never changes Frost values.",
	}


func _build_gate_structural_checks(source: Dictionary, cases: Array, entries: Array) -> Dictionary:
	var setup_valid_count := 0
	var branch_case_count := 0
	var branch_ready_count := 0
	var runtime_invariant_failure_count := 0
	for case_data in cases:
		if not case_data is Dictionary:
			continue
		var case_value: Dictionary = case_data
		if bool(case_value.get("setup_valid", false)):
			setup_valid_count += 1
		for failure in case_value.get("runtime_invariant_failures", []):
			runtime_invariant_failure_count += 1
		var variant := str(case_value.get("variant", ""))
		if variant in ["glacier", "shatter"]:
			branch_case_count += 1
			if bool(case_value.get("branch_selection_succeeded", false)) and str(case_value.get("actual_selected_branch", "")) == variant and bool(case_value.get("post_branch_upgrade_succeeded", false)):
				branch_ready_count += 1
	var determinism_checks: Array = source.get("broader_determinism_checks", [])
	var determinism_failures := 0
	for check in determinism_checks:
		if not check is Dictionary or not bool(check.get("signatures_match", false)) or int(check.get("repeat_count", 0)) != 2:
			determinism_failures += 1
	var summary: Dictionary = source.get("broader_summary", {})
	var setup_all := setup_valid_count == cases.size() and cases.size() > 0
	var branch_ready_all := branch_case_count > 0 and branch_ready_count == branch_case_count
	var runtime_clean := runtime_invariant_failure_count == 0
	var deterministic := bool(summary.get("determinism_all_match", false)) and determinism_checks.size() > 0 and determinism_failures == 0
	var matched_controls := entries.size() == EXPECTED_CANDIDATE_COUNT and _errors.is_empty()
	var rejection_reasons: Array = []
	if not matched_controls:
		rejection_reasons.append("Matched-control or placement-topology validation failed.")
	if not setup_all:
		rejection_reasons.append("Setup validity is not 100%.")
	if not branch_ready_all:
		rejection_reasons.append("Branch selection or post-branch upgrade readiness is not 100%.")
	if not deterministic:
		rejection_reasons.append("Deterministic repeat signatures are not all identical.")
	if not runtime_clean:
		rejection_reasons.append("Runtime invariant failures are present.")
	return {
		"all_passed": matched_controls and setup_all and branch_ready_all and deterministic and runtime_clean,
		"matched_controls": matched_controls,
		"case_count": cases.size(),
		"setup_valid_count": setup_valid_count,
		"setup_valid_all": setup_all,
		"branch_case_count": branch_case_count,
		"branch_ready_count": branch_ready_count,
		"branch_ready_all": branch_ready_all,
		"runtime_invariant_failure_count": runtime_invariant_failure_count,
		"runtime_clean": runtime_clean,
		"determinism_check_count": determinism_checks.size(),
		"determinism_failure_count": determinism_failures,
		"deterministic_all_match": deterministic,
		"rejection_reasons": rejection_reasons,
	}


func _evaluate_branch_gate(branch: String, entries: Array) -> Dictionary:
	var pressure_groups: Dictionary = {}
	for entry in entries:
		if str(entry.get("branch", "")) != branch:
			continue
		var pressure_key := _key([branch, entry.get("enemy_kind", "")])
		_append_group(pressure_groups, pressure_key, entry)
	var pressure_results: Array = []
	var qualifying_pressure_groups: Array = []
	var raw_qualifying_pressure_groups: Array = []
	var raw_qualifying_maps: Dictionary = {}
	var qualifying_maps: Dictionary = {}
	var raw_qualifying_conditions: Array = []
	var qualifying_conditions: Array = []
	var branch_rejection_reasons: Array = []
	var normalized_rejection_reasons: Array = []
	for pressure_key in pressure_groups.keys():
		var pressure_entries: Array = pressure_groups[pressure_key]
		var condition_groups: Dictionary = {}
		for entry in pressure_entries:
			_append_group(condition_groups, str(entry.get("condition_key", "")), entry)
		var condition_results: Array = []
		for condition_key in condition_groups.keys():
			condition_results.append(_evaluate_condition_group(condition_key, condition_groups[condition_key]))
		var raw_condition_results: Array = []
		var all_conditions_consistent := true
		var raw_maps: Dictionary = {}
		var raw_build_layouts: Dictionary = {}
		var normalized_condition_results: Array = []
		for condition_result in condition_results:
			if not bool(condition_result.get("raw_survival_gate_passed", false)):
				all_conditions_consistent = false
				continue
			raw_condition_results.append(condition_result)
			raw_maps[str(condition_result.get("map", ""))] = true
			raw_build_layouts[str(condition_result.get("layout", "")) + "|" + str(condition_result.get("build_variant", ""))] = true
			if bool(condition_result.get("normalized_gate_passed", false)):
				normalized_condition_results.append(condition_result)
		var rejection_reasons: Array = []
		var normalized_reasons: Array = []
		if not all_conditions_consistent:
			rejection_reasons.append("A candidate condition has missing or contradictory survival direction across repeats.")
		if raw_maps.size() < 2:
			rejection_reasons.append("Fewer than two maps support the same enemy-family pressure.")
		if raw_build_layouts.size() < 2:
			rejection_reasons.append("Fewer than two distinct build/layout conditions support the same enemy-family pressure.")
		if normalized_condition_results.size() != raw_condition_results.size():
			normalized_reasons.append("Spend-normalized damage advantage failed in one or more required repeats or conditions.")
		var raw_gate_passed := all_conditions_consistent and raw_maps.size() >= 2 and raw_build_layouts.size() >= 2
		var cost_neutral_gate_passed := raw_gate_passed and normalized_condition_results.size() == raw_condition_results.size()
		var first: Dictionary = pressure_entries[0]
		var pressure_result := {
			"branch": branch,
			"enemy_kind": first.get("enemy_kind", ""),
			"gate_passed": cost_neutral_gate_passed,
			"raw_gate_passed": raw_gate_passed,
			"cost_neutral_gate_passed": cost_neutral_gate_passed,
			"candidate_entry_count": pressure_entries.size(),
			"condition_count": condition_results.size(),
			"raw_survival_condition_count": raw_condition_results.size(),
			"normalized_condition_count": normalized_condition_results.size(),
			"qualifying_maps": raw_maps.keys(),
			"qualifying_build_layout_conditions": raw_build_layouts.keys(),
			"condition_results": condition_results,
			"rejection_reasons": rejection_reasons,
			"normalized_rejection_reasons": normalized_reasons,
		}
		pressure_results.append(pressure_result)
		if raw_gate_passed:
			raw_qualifying_pressure_groups.append(pressure_result)
			for map_name in raw_maps.keys():
				raw_qualifying_maps[str(map_name)] = true
			for condition_result in raw_condition_results:
				raw_qualifying_conditions.append(condition_result)
		if cost_neutral_gate_passed:
			qualifying_pressure_groups.append(pressure_result)
			for map_name in raw_maps.keys():
				qualifying_maps[str(map_name)] = true
			for condition_result in raw_condition_results:
				qualifying_conditions.append(condition_result)
		else:
			branch_rejection_reasons.append_array(rejection_reasons)
			normalized_rejection_reasons.append_array(normalized_reasons)
	var gate_passed := not qualifying_pressure_groups.is_empty()
	var raw_gate_passed := not raw_qualifying_pressure_groups.is_empty()
	return {
		"branch": branch,
		"gate_passed": gate_passed,
		"raw_gate_passed": raw_gate_passed,
		"cost_neutral_gate_passed": gate_passed,
		"raw_qualifying_pressure_groups": raw_qualifying_pressure_groups,
		"qualifying_pressure_groups": qualifying_pressure_groups,
		"pressure_groups": pressure_results,
		"raw_qualifying_maps": raw_qualifying_maps.keys(),
		"qualifying_maps": qualifying_maps.keys(),
		"raw_qualifying_conditions": raw_qualifying_conditions,
		"qualifying_conditions": qualifying_conditions,
		"rejection_reasons": _unique_strings(branch_rejection_reasons),
		"normalized_rejection_reasons": _unique_strings(normalized_rejection_reasons),
	}


func _evaluate_condition_group(condition_key: String, entries: Array) -> Dictionary:
	var first: Dictionary = entries[0]
	var repeats: Array = []
	var direction_keys: Array = []
	var survival_metric_entries := 0
	var normalized_damage_advantage_repeats := 0
	var repeat_profiles: Array = []
	for entry in entries:
		repeats.append(int(entry.get("repeat", 0)))
		var profile := _survival_profile(entry)
		repeat_profiles.append(profile)
		direction_keys.append(str(profile.get("direction_key", "")))
		if bool(profile.get("advantage", false)):
			survival_metric_entries += 1
		var normalized: Dictionary = entry.get("metrics", {}).get("damage_per_spend", {})
		if float(normalized.get("branch", 0.0)) >= float(normalized.get("no_frost", 0.0)):
			normalized_damage_advantage_repeats += 1
	repeats.sort()
	var repeat_complete := repeats == [1, 2]
	var direction_consistent: bool = direction_keys.size() == 2 and direction_keys[0] == direction_keys[1]
	var raw_survival_gate_passed: bool = repeat_complete and direction_consistent and survival_metric_entries == entries.size()
	var normalized_gate_passed: bool = normalized_damage_advantage_repeats == entries.size()
	var normalized_rejection_reasons: Array = []
	if not normalized_gate_passed:
		normalized_rejection_reasons.append("Spend-normalized damage advantage did not hold in every repeat.")
	return {
		"condition_key": condition_key,
		"map": first.get("map", ""),
		"wave": first.get("wave", 0),
		"enemy_kind": first.get("enemy_kind", ""),
		"layout": first.get("layout", ""),
		"build_variant": first.get("build_variant", ""),
		"reasons": first.get("reasons", []),
		"repeat_indices": repeats,
		"repeat_complete": repeat_complete,
		"direction_consistent": direction_consistent,
		"survival_metric_entry_count": survival_metric_entries,
		"raw_survival_gate_passed": raw_survival_gate_passed,
		"raw_gate_passed": raw_survival_gate_passed,
		"normalized_damage_advantage_repeat_count": normalized_damage_advantage_repeats,
		"normalized_damage_advantage_all_repeats": normalized_damage_advantage_repeats == entries.size(),
		"normalized_advantage_repeat_count": normalized_damage_advantage_repeats,
		"normalized_gate_passed": normalized_gate_passed,
		"normalized_rejection_reasons": normalized_rejection_reasons,
		"repeat_profiles": repeat_profiles,
		"pair_keys": entries.map(func(entry): return entry.get("pair_key", "")),
	}


func _survival_profile(entry: Dictionary) -> Dictionary:
	var metrics: Dictionary = entry.get("metrics", {})
	var completion: Dictionary = metrics.get("completion", {})
	var lives: Dictionary = metrics.get("lives", {})
	var leaks: Dictionary = metrics.get("leaks", {})
	var directions := {
		"completion": _direction_completion(bool(completion.get("branch", false)), bool(completion.get("no_frost", false))),
		"lives": _direction_higher(float(lives.get("branch", 0.0)), float(lives.get("no_frost", 0.0))),
		"leaks": _direction_lower(float(leaks.get("branch", 0.0)), float(leaks.get("no_frost", 0.0))),
	}
	var advantage_metrics: Array = []
	var disadvantage_metrics: Array = []
	for metric_name in directions.keys():
		if int(directions[metric_name]) > 0:
			advantage_metrics.append(metric_name)
		elif int(directions[metric_name]) < 0:
			disadvantage_metrics.append(metric_name)
	return {
		"advantage": not advantage_metrics.is_empty(),
		"direction_key": _key([directions["completion"], directions["lives"], directions["leaks"]]),
		"directions": directions,
		"advantage_metrics": advantage_metrics,
		"disadvantage_metrics": disadvantage_metrics,
	}


func _direction_completion(branch_value: bool, control_value: bool) -> int:
	if branch_value == control_value:
		return 0
	return 1 if branch_value else -1


func _direction_higher(branch_value: float, control_value: float) -> int:
	if is_equal_approx(branch_value, control_value):
		return 0
	return 1 if branch_value > control_value else -1


func _direction_lower(branch_value: float, control_value: float) -> int:
	if is_equal_approx(branch_value, control_value):
		return 0
	return 1 if branch_value < control_value else -1


func _unique_strings(values: Array) -> Array:
	var result: Array = []
	for value in values:
		var text := str(value)
		if not result.has(text):
			result.append(text)
	return result


func _build_report(source: Dictionary, entries: Array, conditions: Array, families: Array, gate: Dictionary) -> Dictionary:
	var branch_counts := _count_by(entries, "branch")
	var reason_counts := _count_reasons(entries)
	var map_counts := _count_by(entries, "map")
	var enemy_counts := _count_by(entries, "enemy_kind")
	var classification_counts := _count_by(conditions, "classification")
	var repeat_complete := 0
	for entry in conditions:
		if entry["repeat_indices"] == [1, 2]:
			repeat_complete += 1
	var matched_controls := entries.size() == EXPECTED_CANDIDATE_COUNT and _errors.is_empty()
	return {
		"report_schema_version": 1,
		"report_type": "candidate_frost_evidence_only",
		"source_artifact": INPUT_PATH,
		"source_schema_version": source.get("schema_version", null),
		"evidence_only": true,
		"tuning_authorized": bool(gate.get("tuning_authorized", false)),
		"validation_passed": matched_controls,
		"validation_errors": _errors.duplicate(),
		"deterministic_frost_tuning_gate": gate,
		"coverage": {
			"candidate_entries": entries.size(),
			"expected_candidate_entries": EXPECTED_CANDIDATE_COUNT,
			"all_candidates_represented_exactly_once": entries.size() == EXPECTED_CANDIDATE_COUNT and entries.size() == EXPECTED_CANDIDATE_COUNT,
			"matched_no_frost_controls": matched_controls,
			"condition_groups": conditions.size(),
			"repeat_complete_condition_groups": repeat_complete,
			"repeat_complete": repeat_complete == conditions.size(),
		},
		"summary": {
			"by_branch": branch_counts,
			"by_reason": reason_counts,
			"by_map": map_counts,
			"by_enemy_kind": enemy_counts,
			"condition_classifications": classification_counts,
			"mixed_condition_families": families.filter(func(family): return family["classification"] == "mixed").size(),
			"isolated_condition_families": families.filter(func(family): return family["classification"] == "isolated").size(),
		},
		"signal_groups": conditions,
		"condition_families": families,
		"candidate_entries": entries,
	}


func _count_by(entries: Array, field: String) -> Dictionary:
	var result := {}
	for entry in entries:
		var value := str(entry.get(field, ""))
		result[value] = int(result.get(value, 0)) + 1
	return result


func _count_reasons(entries: Array) -> Dictionary:
	var result := {}
	for entry in entries:
		for reason in entry.get("reasons", []):
			var value := str(reason)
			result[value] = int(result.get(value, 0)) + 1
	return result


func _key(values: Array) -> String:
	var parts: Array = []
	for value in values:
		parts.append(str(value))
	return "|".join(parts)


func _write_json(report: Dictionary) -> void:
	var path := ProjectSettings.globalize_path(JSON_OUTPUT_PATH)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_errors.append("Could not write JSON report: %s" % path)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()


func _write_markdown(report: Dictionary) -> void:
	var summary: Dictionary = report.get("summary", {})
	var coverage: Dictionary = report.get("coverage", {})
	var gate: Dictionary = report.get("deterministic_frost_tuning_gate", {})
	var structural: Dictionary = gate.get("structural_checks", {})
	var lines: Array[String] = [
		"# Candidate Frost Evidence Report",
		"",
		"Evidence-only analysis of the matched paired replay artifact. The gate emits authorization state but never changes Frost values.",
		"",
		"## Gate",
		"",
		"- Source: `%s`" % report.get("source_artifact", ""),
		"- Candidate entries: %d/%d" % [int(coverage.get("candidate_entries", 0)), int(coverage.get("expected_candidate_entries", 0))],
		"- Matched no-Frost controls: `%s`" % str(coverage.get("matched_no_frost_controls", false)),
		"- Repeat-complete conditions: %d/%d" % [int(coverage.get("repeat_complete_condition_groups", 0)), int(coverage.get("condition_groups", 0))],
		"- Tuning authorized: `%s`" % str(report.get("tuning_authorized", false)),
		"",
		"## Deterministic Frost Tuning Gate",
		"",
		"- Gate passed: `%s`" % str(gate.get("gate_passed", false)),
		"- Raw survival gate: `%s`" % str(gate.get("raw_gate_passed", false)),
		"- Cost-neutral gate: `%s`" % str(gate.get("cost_neutral_gate_passed", false)),
		"- Structural checks: `%s`" % str(structural.get("all_passed", false)),
		"- Setup valid: %d/%d" % [int(structural.get("setup_valid_count", 0)), int(structural.get("case_count", 0))],
		"- Branch-ready: %d/%d" % [int(structural.get("branch_ready_count", 0)), int(structural.get("branch_case_count", 0))],
		"- Deterministic repeats: %d checks, %d failures" % [int(structural.get("determinism_check_count", 0)), int(structural.get("determinism_failure_count", 0))],
		"- Runtime invariant failures: %d" % int(structural.get("runtime_invariant_failure_count", 0)),
		"- Raw qualifying branches: `%s`" % ", ".join(gate.get("raw_qualifying_branches", [])),
		"- Cost-neutral qualifying branches: `%s`" % ", ".join(gate.get("qualifying_branches", [])),
		"- Normalized advantage repeats: %d/%d" % [int(gate.get("normalized_advantage_repeat_count", 0)), int(gate.get("normalized_advantage_repeat_total", 0))],
		"- Raw qualifying maps: `%s`" % ", ".join(gate.get("raw_qualifying_maps", [])),
		"- Cost-neutral qualifying maps: `%s`" % ", ".join(gate.get("qualifying_maps", [])),
		"",
		"| Branch | Raw gate | Cost-neutral gate | Raw maps | Cost-neutral maps | Raw rejection reasons | Normalized rejection reasons |",
		"|---|---|---|---|---|---|---|",
	]
	var branch_results: Dictionary = gate.get("branch_results", {})
	var branch_names: Array = branch_results.keys()
	branch_names.sort()
	for branch_name in branch_names:
		var branch_result: Dictionary = branch_results.get(branch_name, {})
		lines.append("| %s | %s | %s | %s | %s | %s | %s |" % [
			branch_name,
			str(branch_result.get("raw_gate_passed", false)),
			str(branch_result.get("cost_neutral_gate_passed", false)),
			", ".join(branch_result.get("raw_qualifying_maps", [])),
			", ".join(branch_result.get("qualifying_maps", [])),
			"; ".join(branch_result.get("rejection_reasons", [])),
			"; ".join(branch_result.get("normalized_rejection_reasons", [])),
		])
	lines.append("")
	lines.append("## Candidate Summary")
	lines.append("")
	lines.append("| Dimension | Counts |")
	lines.append("|---|---|")
	lines.append("| Branch | %s |" % _format_counts(summary.get("by_branch", {})))
	lines.append("| Reason | %s |" % _format_counts(summary.get("by_reason", {})))
	lines.append("| Map | %s |" % _format_counts(summary.get("by_map", {})))
	lines.append("| Enemy kind | %s |" % _format_counts(summary.get("by_enemy_kind", {})))
	lines.append("| Condition classification | %s |" % _format_counts(summary.get("condition_classifications", {})))
	lines.append("")
	lines.append("## Matched Signal Groups")
	lines.append("")
	lines.append("| Branch | Map | Wave | Enemy | Layout | Build | Reason | Repeats | Classification |")
	lines.append("|---|---|---:|---|---|---|---|---:|---|")
	for group in report.get("signal_groups", []):
		lines.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s |" % [
			group.get("branch", ""), group.get("map", ""), group.get("wave", ""), group.get("enemy_kind", ""),
			group.get("layout", ""), group.get("build_variant", ""), ", ".join(group.get("reasons", [])),
			", ".join(group.get("repeat_indices", [])), group.get("classification", ""),
		])
	lines.append("")
	lines.append("## Per-Entry Metric Comparisons")
	lines.append("")
	lines.append("Each row is matched to the same map, wave, enemy kind, layout, build variant, seed, and repeat in its no-Frost control.")
	lines.append("")
	lines.append("| Branch | Map | Wave | Enemy | Build | Repeat | Completion | Lives | Leaks | Damage | Spend | Damage/spend | Frost/runtime observations |")
	lines.append("|---|---|---:|---|---|---:|---|---|---|---|---|---|---|")
	for entry in report.get("candidate_entries", []):
		var metrics: Dictionary = entry.get("metrics", {})
		lines.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % [
			entry.get("branch", ""), entry.get("map", ""), entry.get("wave", ""), entry.get("enemy_kind", ""),
			entry.get("build_variant", ""), entry.get("repeat", ""), _metric_text(metrics, "completion"),
			_metric_text(metrics, "lives"), _metric_text(metrics, "leaks"), _metric_text(metrics, "total_damage"),
			_metric_text(metrics, "total_spend"), _metric_text(metrics, "damage_per_spend"), _runtime_text(metrics),
		])
	lines.append("")
	lines.append("## Decision")
	lines.append("")
	lines.append("Spend-normalized damage is a required gate metric: every condition counted toward a raw qualifying branch must pass in both repeats.")
	if bool(report.get("tuning_authorized", false)):
		lines.append("The deterministic gate passed for: %s. No Frost values were changed; this report only emits authorization state for a separate tuning decision." % ", ".join(gate.get("qualifying_branches", [])))
	elif bool(gate.get("raw_gate_passed", false)):
		lines.append("Raw survival evidence exists for: %s, but cost-neutral authorization failed. Frost values must remain unchanged." % ", ".join(gate.get("raw_qualifying_branches", [])))
	else:
		lines.append("The deterministic gate did not pass. Frost values must remain unchanged until a separately approved paired replay establishes actionable evidence.")
	_write_text(MARKDOWN_OUTPUT_PATH, "\n".join(lines) + "\n")


func _format_counts(value: Variant) -> String:
	var dictionary: Dictionary = value if value is Dictionary else {}
	var keys := dictionary.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		parts.append("%s=%s" % [str(key), str(dictionary[key])])
	return ", ".join(parts)


func _metric_text(metrics: Dictionary, metric_name: String) -> String:
	var metric: Dictionary = metrics.get(metric_name, {})
	return "%s / %s" % [str(metric.get("branch", "")), str(metric.get("no_frost", ""))]


func _runtime_text(metrics: Dictionary) -> String:
	var parts: Array[String] = []
	for metric_name in ["frost_total_damage", "slow_observations", "freeze_observations", "shatter_observations"]:
		var metric: Dictionary = metrics.get(metric_name, {})
		parts.append("%s=%s/%s" % [metric_name, str(metric.get("branch", "")), str(metric.get("no_frost", ""))])
	return "; ".join(parts)


func _write_text(path_value: String, content: String) -> void:
	var path := ProjectSettings.globalize_path(path_value)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_errors.append("Could not write report: %s" % path)
		return
	file.store_string(content)
	file.close()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
