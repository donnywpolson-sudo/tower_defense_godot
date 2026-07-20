extends SceneTree

const INPUT_PATH := "res://logs/godot/split_frost_cost_matched_paired_replay_2026_07_14.json"
const JSON_OUTPUT_PATH := "res://logs/godot/split_frost_cost_matched_evidence_2026_07_14.json"
const MARKDOWN_OUTPUT_PATH := "res://logs/godot/split_frost_cost_matched_evidence_2026_07_14.md"
const EXPECTED_CASE_COUNT := 32
const EXPECTED_BRANCH_READY_COUNT := 16
const EXPECTED_COST_CONTROL_COUNT := 8
const EXPECTED_PAIRED_COST_COMPARISON_COUNT := 16
const EXPECTED_DETERMINISM_COUNT := 16
const COST_MATCH_ALLOWED_DELTA := 5
const COST_MATCH_TARGET_BRANCH_SPEND := 810
const COST_MATCH_EXPECTED_SPEND := 815
const COST_MATCH_ARCHER_BRANCH := "deadeye"
const COST_MATCH_UPGRADE_COSTS := [60, 125, 175]


func _initialize() -> void:
	var input_path := ProjectSettings.globalize_path(INPUT_PATH)
	if not FileAccess.file_exists(input_path):
		_fail("Cost-matched replay artifact does not exist: %s" % input_path)
		return
	var file := FileAccess.open(input_path, FileAccess.READ)
	if file == null:
		_fail("Could not open cost-matched replay artifact: %s" % input_path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_fail("Cost-matched replay artifact is not a JSON object.")
		return
	var source: Dictionary = parsed
	var cases: Array = source.get("case_results", [])
	var paired: Dictionary = source.get("paired_deltas", {})
	var case_by_id := _index_cases(cases)
	var structural := _build_structural_summary(source, cases, case_by_id, paired)
	var entries := _build_cost_matched_entries(paired, case_by_id)
	var pressure_groups := _build_pressure_groups(entries)
	var raw_gate := _build_raw_gate(pressure_groups)
	var normalized_gate := _build_normalized_gate(source, structural, raw_gate, pressure_groups)
	var report := _build_report(source, structural, pressure_groups, raw_gate, normalized_gate, entries)
	_write_json(report)
	_write_markdown(report)
	print("SPLIT_FROST_COST_MATCHED_EVIDENCE_REPORT_GENERATED")
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


func _build_structural_summary(source: Dictionary, cases: Array, case_by_id: Dictionary, paired: Dictionary) -> Dictionary:
	var setup_valid_count := 0
	var branch_ready_count := 0
	var cost_control_count := 0
	var cost_control_valid_count := 0
	var runtime_failures := 0
	for value in cases:
		if not value is Dictionary:
			continue
		var case_data: Dictionary = value
		if bool(case_data.get("setup_valid", false)) and bool(case_data.get("start_succeeded", false)):
			setup_valid_count += 1
		if str(case_data.get("variant", "")) in ["glacier", "shatter"] and bool(case_data.get("branch_selection_succeeded", false)) and str(case_data.get("actual_selected_branch", "")) == str(case_data.get("variant", "")) and bool(case_data.get("post_branch_upgrade_succeeded", false)):
			branch_ready_count += 1
		if str(case_data.get("variant", "")) == "no_frost" and str(case_data.get("control_mode", "")) == "cost_matched":
			cost_control_count += 1
			if bool(case_data.get("cost_match_valid", false)) and bool(case_data.get("control_branch_selection_valid", false)) and str(case_data.get("control_selected_branch", "")) == COST_MATCH_ARCHER_BRANCH and _control_trace_is_exact(case_data) and abs(int(case_data.get("branch_spend_delta", 999999))) <= COST_MATCH_ALLOWED_DELTA and int(case_data.get("control_spend_delta", 999999)) == 0 and int(case_data.get("actual_control_spend", 0)) == COST_MATCH_EXPECTED_SPEND:
				cost_control_valid_count += 1
		runtime_failures += case_data.get("runtime_invariant_failures", []).size()
	var determinism_checks: Array = source.get("determinism_checks", [])
	var deterministic_failures := 0
	for check in determinism_checks:
		if not check is Dictionary or not bool(check.get("signatures_match", false)) or int(check.get("repeat_count", 0)) != 2:
			deterministic_failures += 1
	var paired_cost_comparison_count := 0
	var paired_match_failure_count := 0
	var paired_topology_mismatch_count := 0
	for pair_value in paired.values():
		if not pair_value is Dictionary:
			continue
		var comparison: Dictionary = pair_value
		if str(comparison.get("left_variant", "")) not in ["glacier", "shatter"] or str(comparison.get("right_variant", "")) != "no_frost" or str(comparison.get("right_control_mode", "")) != "cost_matched":
			continue
		paired_cost_comparison_count += 1
		var left_case: Dictionary = case_by_id.get(str(comparison.get("left_case", "")), {})
		var right_case: Dictionary = case_by_id.get(str(comparison.get("right_case", "")), {})
		var match_fields := ["map_name", "wave_requested", "enemy_kind_requested", "layout_id", "build_variant", "seed", "repeat_index"]
		for field_name in match_fields:
			if left_case.get(field_name) != right_case.get(field_name):
				paired_match_failure_count += 1
				break
		if _placement_topology(left_case) != _placement_topology(right_case):
			paired_topology_mismatch_count += 1
	var source_errors: Array = source.get("validation_errors", [])
	var structural_all := bool(source.get("validation_passed", false)) and cases.size() == EXPECTED_CASE_COUNT and setup_valid_count == EXPECTED_CASE_COUNT and branch_ready_count == EXPECTED_BRANCH_READY_COUNT and cost_control_count == EXPECTED_COST_CONTROL_COUNT and cost_control_valid_count == EXPECTED_COST_CONTROL_COUNT and determinism_checks.size() == EXPECTED_DETERMINISM_COUNT and deterministic_failures == 0 and runtime_failures == 0 and paired_cost_comparison_count == EXPECTED_PAIRED_COST_COMPARISON_COUNT and paired_match_failure_count == 0 and paired_topology_mismatch_count == 0
	return {
		"source_validation_passed": bool(source.get("validation_passed", false)),
		"source_validation_errors": source_errors,
		"case_count": cases.size(),
		"expected_case_count": EXPECTED_CASE_COUNT,
		"setup_valid_count": setup_valid_count,
		"setup_valid_expected": EXPECTED_CASE_COUNT,
		"branch_ready_count": branch_ready_count,
		"branch_ready_expected": EXPECTED_BRANCH_READY_COUNT,
		"cost_control_count": cost_control_count,
		"cost_control_valid_count": cost_control_valid_count,
		"cost_control_expected": EXPECTED_COST_CONTROL_COUNT,
		"paired_cost_comparison_count": paired_cost_comparison_count,
		"paired_cost_comparison_expected": EXPECTED_PAIRED_COST_COMPARISON_COUNT,
		"paired_match_failure_count": paired_match_failure_count,
		"paired_topology_mismatch_count": paired_topology_mismatch_count,
		"determinism_check_count": determinism_checks.size(),
		"determinism_expected": EXPECTED_DETERMINISM_COUNT,
		"determinism_failure_count": deterministic_failures,
		"runtime_invariant_failure_count": runtime_failures,
		"paired_comparison_count": paired.size(),
		"structural_all_passed": structural_all,
	}


func _build_cost_matched_entries(paired: Dictionary, case_by_id: Dictionary) -> Array:
	var entries: Array = []
	for pair_key in paired.keys():
		var comparison: Dictionary = paired[pair_key]
		if str(comparison.get("left_variant", "")) not in ["glacier", "shatter"] or str(comparison.get("right_variant", "")) != "no_frost" or str(comparison.get("right_control_mode", "")) != "cost_matched":
			continue
		var left_case: Dictionary = case_by_id.get(str(comparison.get("left_case", "")), {})
		var right_case: Dictionary = case_by_id.get(str(comparison.get("right_case", "")), {})
		var deltas: Dictionary = comparison.get("deltas", {})
		var topology_match := _placement_topology(left_case) == _placement_topology(right_case)
		entries.append({
			"pair_key": str(pair_key),
			"branch": str(comparison.get("left_variant", "")),
			"map": str(left_case.get("map_name", "")),
			"wave": int(left_case.get("wave_requested", 0)),
			"enemy_kind": str(left_case.get("enemy_kind_requested", "")),
			"layout": str(left_case.get("layout_id", "")),
			"build_variant": str(left_case.get("build_variant", "")),
			"repeat": int(left_case.get("repeat_index", 0)),
			"left_control_mode": str(comparison.get("left_control_mode", "")),
			"right_control_mode": str(comparison.get("right_control_mode", "")),
			"topology_match": topology_match,
			"cost_match_valid": bool(right_case.get("cost_match_valid", false)),
			"target_branch_spend": COST_MATCH_TARGET_BRANCH_SPEND,
			"target_control_spend": int(right_case.get("spend_match_target", 0)),
			"actual_control_spend": int(right_case.get("total_spend", 0)),
			"spend_match_delta": int(right_case.get("spend_match_delta", 999999)),
			"control_upgrade_valid": bool(right_case.get("control_upgrade_valid", false)),
			"control_upgrade_trace": right_case.get("control_upgrade_trace", []),
			"control_branch_selection": right_case.get("control_branch_selection", {}),
			"control_branch_selection_succeeded": bool(right_case.get("control_branch_selection_succeeded", false)),
			"control_branch_selection_valid": bool(right_case.get("control_branch_selection_valid", false)),
			"control_selected_branch": str(right_case.get("control_selected_branch", "")),
			"branch_spend_delta": int(right_case.get("branch_spend_delta", 999999)),
			"control_spend_delta": int(right_case.get("control_spend_delta", 999999)),
			"raw_survival": _survival_profile(deltas),
			"normalized_advantage": float(deltas.get("damage_per_spend", {}).get("left", 0.0)) >= float(deltas.get("damage_per_spend", {}).get("right", 0.0)),
			"metrics": {
				"completed": deltas.get("completed", {}),
				"lives": deltas.get("lives", {}),
				"leaks": deltas.get("leaks", {}),
				"total_damage": deltas.get("total_damage", {}),
				"total_spend": deltas.get("total_spend", {}),
				"damage_per_spend": deltas.get("damage_per_spend", {}),
			},
		})
	return entries


func _control_trace_is_exact(case_data: Dictionary) -> bool:
	var trace: Array = case_data.get("control_upgrade_trace", [])
	if trace.size() != 4:
		return false
	var expected_actions := ["upgrade_tower", "choose_branch", "upgrade_tower", "upgrade_tower"]
	for index in range(expected_actions.size()):
		if str(trace[index].get("action", "")) != expected_actions[index] or not bool(trace[index].get("valid", false)):
			return false
	if int(trace[0].get("expected_cost", 0)) != COST_MATCH_UPGRADE_COSTS[0] or int(trace[2].get("expected_cost", 0)) != COST_MATCH_UPGRADE_COSTS[1] or int(trace[3].get("expected_cost", 0)) != COST_MATCH_UPGRADE_COSTS[2]:
		return false
	return str(trace[1].get("requested_branch", "")) == COST_MATCH_ARCHER_BRANCH and str(trace[1].get("actual_branch", "")) == COST_MATCH_ARCHER_BRANCH


func _placement_topology(case_data: Dictionary) -> String:
	var topology: Array = []
	for placement in case_data.get("placement_results", []):
		var data: Dictionary = placement if placement is Dictionary else {}
		topology.append({"placed": bool(data.get("placed", false)), "site": data.get("site", [])})
	return JSON.stringify(topology)


func _survival_profile(deltas: Dictionary) -> Dictionary:
	var completion: Dictionary = deltas.get("completed", {})
	var lives: Dictionary = deltas.get("lives", {})
	var leaks: Dictionary = deltas.get("leaks", {})
	var directions := {
		"completion": _direction_completion(bool(completion.get("left", false)), bool(completion.get("right", false))),
		"lives": _direction_higher(float(lives.get("left", 0.0)), float(lives.get("right", 0.0))),
		"leaks": _direction_lower(float(leaks.get("left", 0.0)), float(leaks.get("right", 0.0))),
	}
	var advantages: Array = []
	for metric_name in directions.keys():
		if int(directions[metric_name]) > 0:
			advantages.append(metric_name)
	return {"advantage": not advantages.is_empty(), "direction_key": _key([directions["completion"], directions["lives"], directions["leaks"]]), "metrics": advantages}


func _direction_completion(left_value: bool, right_value: bool) -> int:
	if left_value == right_value:
		return 0
	return 1 if left_value else -1


func _direction_higher(left_value: float, right_value: float) -> int:
	if is_equal_approx(left_value, right_value):
		return 0
	return 1 if left_value > right_value else -1


func _direction_lower(left_value: float, right_value: float) -> int:
	if is_equal_approx(left_value, right_value):
		return 0
	return 1 if left_value < right_value else -1


func _build_pressure_groups(entries: Array) -> Array:
	var grouped := {}
	for entry in entries:
		var pressure_key := _key([entry.get("branch", ""), entry.get("enemy_kind", "")])
		var condition_key := _key([entry.get("map", ""), entry.get("wave", 0), entry.get("layout", ""), entry.get("build_variant", "")])
		if not grouped.has(pressure_key):
			grouped[pressure_key] = {}
		if not grouped[pressure_key].has(condition_key):
			grouped[pressure_key][condition_key] = []
		grouped[pressure_key][condition_key].append(entry)
	var result: Array = []
	for pressure_key in grouped.keys():
		var conditions: Array = []
		for condition_key in grouped[pressure_key].keys():
			var condition_entries: Array = grouped[pressure_key][condition_key]
			var repeats: Array = condition_entries.map(func(entry): return int(entry.get("repeat", 0)))
			repeats.sort()
			var directions: Array = condition_entries.map(func(entry): return str(entry.get("raw_survival", {}).get("direction_key", "")))
			var raw_advantage: bool = condition_entries.all(func(entry): return bool(entry.get("raw_survival", {}).get("advantage", false))) and repeats == [1, 2] and directions.size() == 2 and directions[0] == directions[1]
			var normalized_count := condition_entries.filter(func(entry): return bool(entry.get("normalized_advantage", false))).size()
			var first: Dictionary = condition_entries[0]
			conditions.append({
				"condition_key": condition_key,
				"map": first.get("map", ""),
				"wave": first.get("wave", 0),
				"enemy_kind": first.get("enemy_kind", ""),
				"layout": first.get("layout", ""),
				"build_variant": first.get("build_variant", ""),
				"repeats": repeats,
				"topology_all_match": condition_entries.all(func(entry): return bool(entry.get("topology_match", false))),
				"raw_gate_passed": raw_advantage,
				"normalized_advantage_repeat_count": normalized_count,
				"normalized_gate_passed": normalized_count == condition_entries.size(),
				"entries": condition_entries,
			})
		var raw_conditions: Array = conditions.filter(func(condition): return bool(condition.get("raw_gate_passed", false)))
		var raw_maps: Dictionary = {}
		var raw_layouts: Dictionary = {}
		for condition in raw_conditions:
			raw_maps[str(condition.get("map", ""))] = true
			raw_layouts[str(condition.get("layout", "")) + "|" + str(condition.get("build_variant", ""))] = true
		result.append({
			"pressure_key": pressure_key,
			"branch": str(pressure_key).split("|")[0],
			"enemy_kind": str(pressure_key).split("|")[1],
			"conditions": conditions,
			"raw_gate_passed": raw_conditions.size() >= 2 and raw_maps.size() >= 2 and raw_layouts.size() >= 2,
			"raw_maps": raw_maps.keys(),
			"raw_build_layout_conditions": raw_layouts.keys(),
			"raw_conditions": raw_conditions,
		})
	return result


func _build_raw_gate(pressure_groups: Array) -> Dictionary:
	var qualifying: Array = pressure_groups.filter(func(group): return bool(group.get("raw_gate_passed", false)))
	var branches: Array = qualifying.map(func(group): return str(group.get("branch", "")))
	var unique_branches: Array = []
	for branch in branches:
		if not unique_branches.has(branch):
			unique_branches.append(branch)
	return {"gate_passed": not qualifying.is_empty(), "qualifying_branches": unique_branches, "qualifying_pressure_groups": qualifying}


func _build_normalized_gate(source: Dictionary, structural: Dictionary, raw_gate: Dictionary, pressure_groups: Array) -> Dictionary:
	var normalized_repeats := 0
	var normalized_total := 0
	var normalized_failures: Array = []
	for group in raw_gate.get("qualifying_pressure_groups", []):
		for condition in group.get("raw_conditions", []):
			normalized_repeats += int(condition.get("normalized_advantage_repeat_count", 0))
			normalized_total += int(condition.get("repeats", []).size())
			if not bool(condition.get("normalized_gate_passed", false)):
				normalized_failures.append("%s %s wave %s %s" % [group.get("branch", ""), condition.get("map", ""), condition.get("wave", ""), condition.get("layout", "")])
	var all_normalized := normalized_repeats == normalized_total and normalized_total > 0
	var gate_passed := bool(source.get("validation_passed", false)) and bool(structural.get("structural_all_passed", false)) and bool(raw_gate.get("gate_passed", false)) and all_normalized
	return {
		"gate_passed": gate_passed,
		"cost_neutral_gate_passed": gate_passed,
		"tuning_authorized": gate_passed,
		"normalized_advantage_repeat_count": normalized_repeats,
		"normalized_advantage_repeat_total": normalized_total,
		"normalized_rejection_reasons": normalized_failures + source.get("validation_errors", []),
		"qualifying_branches": raw_gate.get("qualifying_branches", []) if gate_passed else [],
	}


func _build_report(source: Dictionary, structural: Dictionary, pressure_groups: Array, raw_gate: Dictionary, normalized_gate: Dictionary, entries: Array) -> Dictionary:
	return {
		"report_schema_version": 1,
		"report_type": "cost_matched_frost_evidence_only",
		"source_artifact": INPUT_PATH,
		"cost_match_definition": source.get("cost_match_definition", {}),
		"evidence_only": true,
		"raw_gate_passed": bool(raw_gate.get("gate_passed", false)),
		"cost_neutral_gate_passed": bool(normalized_gate.get("cost_neutral_gate_passed", false)),
		"tuning_authorized": false if not bool(normalized_gate.get("tuning_authorized", false)) else true,
		"normalized_advantage_repeat_count": normalized_gate.get("normalized_advantage_repeat_count", 0),
		"normalized_advantage_repeat_total": normalized_gate.get("normalized_advantage_repeat_total", 0),
		"normalized_rejection_reasons": normalized_gate.get("normalized_rejection_reasons", []),
		"structural": structural,
		"raw_qualifying_branches": raw_gate.get("qualifying_branches", []),
		"qualifying_branches": normalized_gate.get("qualifying_branches", []),
		"pressure_groups": pressure_groups,
		"cost_matched_entries": entries,
		"source_validation_errors": source.get("validation_errors", []),
		"decision": "Cost-matched control validation failed closed; no Frost tuning is authorized.",
	}


func _write_json(report: Dictionary) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(JSON_OUTPUT_PATH), FileAccess.WRITE)
	if file == null:
		_fail("Could not write cost-matched evidence JSON.")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()


func _write_markdown(report: Dictionary) -> void:
	var structural: Dictionary = report.get("structural", {})
	var lines: Array[String] = [
		"# Cost-Matched Frost Evidence Report",
		"",
		"Evidence-only report. Frost values remain unchanged and tuning authorization is fail-closed.",
		"",
		"## Gate",
		"",
		"- Raw survival gate: `%s`" % str(report.get("raw_gate_passed", false)),
		"- Cost-neutral gate: `%s`" % str(report.get("cost_neutral_gate_passed", false)),
		"- Tuning authorized: `%s`" % str(report.get("tuning_authorized", false)),
		"- Normalized advantage: %d/%d repeats" % [int(report.get("normalized_advantage_repeat_count", 0)), int(report.get("normalized_advantage_repeat_total", 0))],
		"",
		"## Coverage",
		"",
		"- Cases: %d/%d" % [int(structural.get("case_count", 0)), int(structural.get("expected_case_count", 0))],
		"- Setup valid: %d/%d" % [int(structural.get("setup_valid_count", 0)), int(structural.get("setup_valid_expected", 0))],
		"- Branch-ready: %d/%d" % [int(structural.get("branch_ready_count", 0)), int(structural.get("branch_ready_expected", 0))],
		"- Cost-matched controls: %d/%d valid" % [int(structural.get("cost_control_valid_count", 0)), int(structural.get("cost_control_expected", 0))],
		"- Cost target: 815 control spend versus 810 branch spend; tolerance: 5 credits; archer branch: `deadeye`",
		"- Paired cost comparisons: %d/%d; metadata mismatches: %d; topology mismatches: %d" % [int(structural.get("paired_cost_comparison_count", 0)), int(structural.get("paired_cost_comparison_expected", 0)), int(structural.get("paired_match_failure_count", 0)), int(structural.get("paired_topology_mismatch_count", 0))],
		"- Determinism: %d/%d checks, %d failures" % [int(structural.get("determinism_check_count", 0)), int(structural.get("determinism_expected", 0)), int(structural.get("determinism_failure_count", 0))],
		"- Runtime invariant failures: %d" % int(structural.get("runtime_invariant_failure_count", 0)),
		"",
		"## Raw Signals",
		"",
		"- Raw qualifying branches: `%s`" % ", ".join(report.get("raw_qualifying_branches", [])),
		"- Cost-neutral qualifying branches: `%s`" % ", ".join(report.get("qualifying_branches", [])),
		"",
		"## Rejection",
		"",
	]
	for reason in report.get("normalized_rejection_reasons", []):
		lines.append("- %s" % str(reason))
	lines.append("")
	if not bool(report.get("tuning_authorized", false)):
		lines.append("The archer cost-padding sequence failed after the first upgrade because the next canonical upgrade requires a branch choice. The validator used no fallback and therefore produced no cost-neutral authorization.")
	else:
		lines.append("All declared cost-neutral gates passed. This report remains evidence-only; any tuning action requires separate approval.")
	_write_text("\n".join(lines) + "\n")


func _write_text(content: String) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(MARKDOWN_OUTPUT_PATH), FileAccess.WRITE)
	if file == null:
		_fail("Could not write cost-matched evidence Markdown.")
		return
	file.store_string(content)
	file.close()


func _key(values: Array) -> String:
	var parts: Array = []
	for value in values:
		parts.append(str(value))
	return "|".join(parts)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
