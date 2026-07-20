extends SceneTree

const INPUT_PATH := "res://logs/godot/split_frost_shatter_burst_ablation_2026_07_14.json"
const JSON_OUTPUT_PATH := "res://logs/godot/split_frost_shatter_burst_ablation_evidence_2026_07_14.json"
const MARKDOWN_OUTPUT_PATH := "res://logs/godot/split_frost_shatter_burst_ablation_evidence_2026_07_14.md"
const BASELINE_RATIO := 0.20
const CANDIDATE_RATIOS := [0.18, 0.16]
const EXPECTED_CASES_PER_ARM := 32
const EXPECTED_SETUP_PER_ARM := 32
const EXPECTED_BRANCH_READY_PER_ARM := 16
const EXPECTED_COST_CONTROLS_PER_ARM := 8
const EXPECTED_DETERMINISM_PER_ARM := 16
const COST_MATCH_ALLOWED_DELTA := 5
const COST_MATCH_EXPECTED_SPEND := 815
const COST_MATCH_ARCHER_BRANCH := "deadeye"


func _initialize() -> void:
	var input_path := ProjectSettings.globalize_path(INPUT_PATH)
	if not FileAccess.file_exists(input_path):
		_fail("Shatter ablation replay artifact does not exist: %s" % input_path)
		return
	var file := FileAccess.open(input_path, FileAccess.READ)
	if file == null:
		_fail("Could not open Shatter ablation replay artifact: %s" % input_path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_fail("Shatter ablation replay artifact is not a JSON object.")
		return
	var source: Dictionary = parsed
	var arm_summaries := {}
	for arm_key in source.get("arms", {}).keys():
		var arm_data: Dictionary = source.get("arms", {}).get(arm_key, {})
		arm_summaries[str(arm_key)] = _summarize_arm(arm_data)
	var selection := _select_candidate(arm_summaries)
	var report := {
		"report_schema_version": 1,
		"report_type": "split_frost_shatter_burst_ablation_evidence_only",
		"source_artifact": INPUT_PATH,
		"evidence_only": true,
		"data_edit_authorized": false,
		"tuning_authorized": false,
		"baseline_ratio": BASELINE_RATIO,
		"candidate_ratios": CANDIDATE_RATIOS,
		"arms": arm_summaries,
		"recommended_ratio": selection.get("ratio", null),
		"recommendation_status": selection.get("status", "no_change"),
		"recommendation_reasons": selection.get("reasons", []),
		"source_validation_passed": bool(source.get("validation_passed", false)),
		"source_validation_errors": source.get("validation_errors", []),
		"case_count": int(source.get("case_count", 0)),
		"expected_case_count": int(source.get("ablation_definition", {}).get("expected_total_cases", 96)),
		"runtime_invariant_failure_count": source.get("runtime_invariant_failures", []).size(),
		"decision": "Evidence-only candidate ranking; no canonical Frost value was changed.",
	}
	_write_json(report)
	_write_markdown(report)
	print("SPLIT_FROST_SHATTER_ABLATION_EVIDENCE_REPORT_GENERATED")
	print("  JSON: %s" % ProjectSettings.globalize_path(JSON_OUTPUT_PATH))
	print("  Markdown: %s" % ProjectSettings.globalize_path(MARKDOWN_OUTPUT_PATH))
	quit(0)


func _summarize_arm(arm_data: Dictionary) -> Dictionary:
	var cases: Array = arm_data.get("case_results", [])
	var paired: Dictionary = arm_data.get("paired_deltas", {})
	var determinism_checks: Array = arm_data.get("determinism_checks", [])
	var case_by_id := _index_cases(cases)
	var setup_valid_count := 0
	var branch_ready_count := 0
	var cost_control_count := 0
	var cost_control_valid_count := 0
	var runtime_failure_count := 0
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
			if bool(case_data.get("cost_match_valid", false)) and bool(case_data.get("control_branch_selection_valid", false)) and str(case_data.get("control_selected_branch", "")) == COST_MATCH_ARCHER_BRANCH and abs(int(case_data.get("branch_spend_delta", 999999))) <= COST_MATCH_ALLOWED_DELTA and int(case_data.get("actual_control_spend", 0)) == COST_MATCH_EXPECTED_SPEND:
				cost_control_valid_count += 1
		runtime_failure_count += case_data.get("runtime_invariant_failures", []).size()
	var determinism_failure_count := 0
	for check in determinism_checks:
		if not check is Dictionary or int(check.get("repeat_count", 0)) != 2 or not bool(check.get("signatures_match", false)):
			determinism_failure_count += 1
	var entries := _build_shatter_entries(paired, case_by_id)
	var conditions := _build_conditions(entries)
	var raw_conditions: Array = conditions.filter(func(condition): return bool(condition.get("raw_gate_passed", false)))
	var raw_maps := {}
	var raw_layouts := {}
	for condition in raw_conditions:
		raw_maps[str(condition.get("map", ""))] = true
		raw_layouts[str(condition.get("layout", ""))] = true
	var raw_gate_passed: bool = raw_conditions.size() >= 2 and raw_maps.size() >= 2 and raw_layouts.size() >= 2
	var normalized_repeat_count := 0
	var normalized_repeat_total := 0
	var normalized_excess_total := 0.0
	for condition in raw_conditions:
		normalized_repeat_count += int(condition.get("normalized_advantage_repeat_count", 0))
		normalized_repeat_total += int(condition.get("repeats", []).size())
		normalized_excess_total += float(condition.get("normalized_excess", 0.0))
	var normalized_gate_passed: bool = raw_gate_passed and normalized_repeat_total > 0 and normalized_repeat_count == normalized_repeat_total
	var structural_all_passed: bool = bool(arm_data.get("validation_passed", false)) and cases.size() == EXPECTED_CASES_PER_ARM and setup_valid_count == EXPECTED_SETUP_PER_ARM and branch_ready_count == EXPECTED_BRANCH_READY_PER_ARM and cost_control_count == EXPECTED_COST_CONTROLS_PER_ARM and cost_control_valid_count == EXPECTED_COST_CONTROLS_PER_ARM and determinism_checks.size() == EXPECTED_DETERMINISM_PER_ARM and determinism_failure_count == 0 and runtime_failure_count == 0 and entries.size() == 8
	return {
		"ratio": float(arm_data.get("ratio", 0.0)),
		"validation_passed": bool(arm_data.get("validation_passed", false)),
		"validation_errors": arm_data.get("validation_errors", []),
		"case_count": cases.size(),
		"setup_valid_count": setup_valid_count,
		"branch_ready_count": branch_ready_count,
		"cost_control_count": cost_control_count,
		"cost_control_valid_count": cost_control_valid_count,
		"determinism_check_count": determinism_checks.size(),
		"determinism_failure_count": determinism_failure_count,
		"runtime_invariant_failure_count": runtime_failure_count,
		"paired_comparison_count": paired.size(),
		"entry_count": entries.size(),
		"raw_gate_passed": raw_gate_passed,
		"raw_maps": raw_maps.keys(),
		"raw_conditions": raw_conditions,
		"normalized_gate_passed": normalized_gate_passed,
		"normalized_advantage_repeat_count": normalized_repeat_count,
		"normalized_advantage_repeat_total": normalized_repeat_total,
		"normalized_excess": normalized_excess_total / float(max(1, raw_conditions.size())),
		"structural_all_passed": structural_all_passed,
		"conditions": conditions,
		"entries": entries,
	}


func _build_shatter_entries(paired: Dictionary, case_by_id: Dictionary) -> Array:
	var entries: Array = []
	for pair_key in paired.keys():
		var comparison: Dictionary = paired[pair_key]
		if str(comparison.get("left_variant", "")) != "shatter" or str(comparison.get("right_variant", "")) != "no_frost" or str(comparison.get("right_control_mode", "")) != "cost_matched":
			continue
		var left_case: Dictionary = case_by_id.get(str(comparison.get("left_case", "")), {})
		var right_case: Dictionary = case_by_id.get(str(comparison.get("right_case", "")), {})
		var deltas: Dictionary = comparison.get("deltas", {})
		var damage_per_spend: Dictionary = deltas.get("damage_per_spend", {})
		var left_dps := float(damage_per_spend.get("left", 0.0))
		var right_dps := float(damage_per_spend.get("right", 0.0))
		entries.append({
			"pair_key": str(pair_key),
			"ratio": float(left_case.get("shatter_burst_ratio", 0.0)),
			"map": str(left_case.get("map_name", "")),
			"wave": int(left_case.get("wave_requested", 0)),
			"enemy_kind": str(left_case.get("enemy_kind_requested", "")),
			"layout": str(left_case.get("layout_id", "")),
			"build_variant": str(left_case.get("build_variant", "")),
			"repeat": int(left_case.get("repeat_index", 0)),
			"topology_match": _placement_topology(left_case) == _placement_topology(right_case),
			"cost_match_valid": bool(right_case.get("cost_match_valid", false)),
			"control_selected_branch": str(right_case.get("control_selected_branch", "")),
			"actual_control_spend": int(right_case.get("actual_control_spend", 0)),
			"branch_spend_delta": int(right_case.get("branch_spend_delta", 999999)),
			"raw_survival": _survival_profile(deltas),
			"normalized_advantage": left_dps >= right_dps,
			"normalized_gap": left_dps - right_dps,
			"metrics": {
				"completed": deltas.get("completed", {}),
				"lives": deltas.get("lives", {}),
				"leaks": deltas.get("leaks", {}),
				"total_damage": deltas.get("total_damage", {}),
				"total_spend": deltas.get("total_spend", {}),
				"damage_per_spend": damage_per_spend,
			},
		})
	return entries


func _build_conditions(entries: Array) -> Array:
	var grouped := {}
	for entry in entries:
		var key := "%s|%s|%s|%s" % [entry.get("map", ""), entry.get("wave", 0), entry.get("layout", ""), entry.get("build_variant", "")]
		if not grouped.has(key):
			grouped[key] = []
		grouped[key].append(entry)
	var conditions: Array = []
	for key in grouped.keys():
		var group: Array = grouped[key]
		group.sort_custom(func(left, right): return int(left.get("repeat", 0)) < int(right.get("repeat", 0)))
		var directions: Array = group.map(func(entry): return str(entry.get("raw_survival", {}).get("direction_key", "")))
		var raw_passed: bool = group.size() == 2 and group[0].get("repeat", 0) == 1 and group[1].get("repeat", 0) == 2 and group.all(func(entry): return bool(entry.get("raw_survival", {}).get("advantage", false))) and directions[0] == directions[1] and group.all(func(entry): return bool(entry.get("topology_match", false)) and bool(entry.get("cost_match_valid", false)) and entry.get("control_selected_branch", "") == COST_MATCH_ARCHER_BRANCH and int(entry.get("actual_control_spend", 0)) == COST_MATCH_EXPECTED_SPEND and abs(int(entry.get("branch_spend_delta", 999999))) <= COST_MATCH_ALLOWED_DELTA)
		var normalized_count: int = group.filter(func(entry): return bool(entry.get("normalized_advantage", false))).size()
		var normalized_excess := 0.0
		for entry in group:
			normalized_excess += max(0.0, float(entry.get("normalized_gap", 0.0)))
		conditions.append({
			"condition_key": str(key),
			"map": group[0].get("map", ""),
			"wave": group[0].get("wave", 0),
			"enemy_kind": group[0].get("enemy_kind", ""),
			"layout": group[0].get("layout", ""),
			"build_variant": group[0].get("build_variant", ""),
			"repeats": group.map(func(entry): return int(entry.get("repeat", 0))),
			"raw_gate_passed": raw_passed,
			"normalized_advantage_repeat_count": normalized_count,
			"normalized_gate_passed": raw_passed and normalized_count == group.size(),
			"normalized_excess": normalized_excess / float(max(1, group.size())),
			"entries": group,
		})
	return conditions


func _select_candidate(arms: Dictionary) -> Dictionary:
	var baseline: Dictionary = arms.get("0.20", {})
	var reasons: Array = []
	if baseline.is_empty():
		return {"status": "no_change", "ratio": null, "reasons": ["Baseline 0.20 arm is missing."]}
	var selected_ratio := -1.0
	for ratio in CANDIDATE_RATIOS:
		var key := "%.2f" % float(ratio)
		var candidate: Dictionary = arms.get(key, {})
		var lower_excess: bool = not candidate.is_empty() and float(candidate.get("normalized_excess", 999999.0)) < float(baseline.get("normalized_excess", 999999.0))
		var qualifies: bool = not candidate.is_empty() and bool(candidate.get("structural_all_passed", false)) and bool(candidate.get("raw_gate_passed", false)) and bool(candidate.get("normalized_gate_passed", false)) and lower_excess
		candidate["lower_normalized_excess_than_baseline"] = lower_excess
		candidate["candidate_qualifies"] = qualifies
		arms[key] = candidate
		if qualifies and selected_ratio < 0.0:
			selected_ratio = float(ratio)
		if not qualifies:
			reasons.append("Ratio %s did not satisfy all candidate gates." % key)
	if selected_ratio >= 0.0:
		reasons.append("Ratio %.2f is the smallest candidate reduction that preserves the declared Shatter survival gate and lowers normalized excess." % selected_ratio)
		return {"status": "candidate_recommended", "ratio": selected_ratio, "reasons": reasons}
	return {"status": "no_change", "ratio": null, "reasons": reasons}


func _index_cases(cases: Array) -> Dictionary:
	var result := {}
	for value in cases:
		if value is Dictionary:
			var case_data: Dictionary = value
			result[str(case_data.get("case_id", ""))] = case_data
	return result


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
	return {"advantage": not advantages.is_empty(), "direction_key": "%d|%d|%d" % [directions["completion"], directions["lives"], directions["leaks"]], "metrics": advantages}


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


func _write_json(report: Dictionary) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(JSON_OUTPUT_PATH), FileAccess.WRITE)
	if file == null:
		_fail("Could not write Shatter ablation evidence JSON.")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()


func _write_markdown(report: Dictionary) -> void:
	var lines: Array[String] = [
		"# Shatter Death-Burst Ablation Evidence",
		"",
		"Evidence-only report. Canonical Frost values remain unchanged and no data edit is authorized.",
		"",
		"## Recommendation",
		"",
		"- Status: `%s`" % str(report.get("recommendation_status", "no_change")),
		"- Recommended ratio: `%s`" % str(report.get("recommended_ratio", "none")),
		"- Data edit authorized: `false`",
		"",
		"## Arms",
		"",
	]
	for arm_key in report.get("arms", {}).keys():
		var arm: Dictionary = report.get("arms", {}).get(arm_key, {})
		lines.append("- `%s`: cases %d, setup %d/32, branch-ready %d/16, controls %d/8, determinism failures %d, runtime failures %d" % [arm_key, int(arm.get("case_count", 0)), int(arm.get("setup_valid_count", 0)), int(arm.get("branch_ready_count", 0)), int(arm.get("cost_control_valid_count", 0)), int(arm.get("determinism_failure_count", 0)), int(arm.get("runtime_invariant_failure_count", 0))])
		lines.append("  - Raw survival gate: `%s`; normalized gate: `%s`; normalized excess: `%.6f`; candidate qualifies: `%s`" % [str(arm.get("raw_gate_passed", false)), str(arm.get("normalized_gate_passed", false)), float(arm.get("normalized_excess", 0.0)), str(arm.get("candidate_qualifies", false))])
	lines.append("")
	for reason in report.get("recommendation_reasons", []):
		lines.append("- %s" % str(reason))
	_write_text("\n".join(lines) + "\n")


func _write_text(content: String) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(MARKDOWN_OUTPUT_PATH), FileAccess.WRITE)
	if file == null:
		_fail("Could not write Shatter ablation evidence Markdown.")
		return
	file.store_string(content)
	file.close()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
