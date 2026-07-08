extends SceneTree

const RUNNER_SCRIPT := "res://scripts/tools/run_ai_simulation_batch.gd"
const OUTPUT_BASE := "res://.godot/ai_scenario_probe_validation"
const CHILD_LOG_DIR := "res://logs/godot"

var _errors: Array = []
var _run_id := ""


func _initialize() -> void:
	_run_id = str(Time.get_ticks_usec())
	_run_validation()
	if _errors.is_empty():
		print("AI_SCENARIO_PROBE_VALIDATION_OK")
		quit(0)
	else:
		push_error("AI_SCENARIO_PROBE_VALIDATION_FAILED")
		for error in _errors:
			push_error(str(error))
		quit(1)


func _run_validation() -> void:
	var smoke := _run_fixture("smoke", ["--runs=1", "--max-waves=1", "--report-label=scenario_probe_validation_smoke", "--compare-previous=false", "--scenario-probes=smoke"])
	_expect_json_value(smoke, ["scenario_probes", "mode"], "smoke", "smoke mode")
	_expect_probe_ids(smoke, "tower_family_probes", ["archer", "cannon", "tesla"], "smoke tower probes")
	_expect_probe_ids(smoke, "enemy_kind_probes", ["normal", "fast", "tank", "flying"], "smoke enemy probes")
	_expect_probe_waves(smoke, "scheduled_wave_probes", [5, 8], "smoke scheduled waves")
	_expect_branch_subset(smoke, ["archer", "cannon", "tesla"], "smoke branches")
	_expect_flying_probe_uses_unlocked_anti_air(smoke, "smoke")

	var full := _run_fixture("full", ["--runs=1", "--max-waves=1", "--report-label=scenario_probe_validation_full", "--compare-previous=false", "--scenario-probes=full"])
	_expect_json_value(full, ["schema_version"], 6, "schema version")
	_expect_json_value(full, ["scenario_probes", "mode"], "full", "full mode")
	_expect_probe_ids(full, "tower_family_probes", ["archer", "machine_gun", "cannon", "sniper", "tesla"], "full tower probes")
	_expect_probe_ids(full, "enemy_kind_probes", ["armored", "commander", "fast", "flying", "normal", "shield", "swarm", "tank"], "full enemy probes")
	_expect_probe_waves(full, "scheduled_wave_probes", [5, 8, 10, 12, 15, 16, 20, 24, 25, 28, 30], "full scheduled waves")
	_expect_all_enabled_branches(full)
	_expect_branch_exercise(full)
	_expect_special_wave_diagnostics(full)
	_expect_flying_probe_uses_unlocked_anti_air(full, "full")
	_expect_contains(full.get("markdown", ""), "## Scenario probes", "markdown scenario section")
	_expect_contains(full.get("prompt", ""), "## Scenario Probes", "prompt scenario section")


func _run_fixture(name: String, user_args: Array) -> Dictionary:
	var output_dir := "%s/%s/%s" % [OUTPUT_BASE, _run_id, name]
	var args := ["--headless", "--no-header", "--log-file", _child_log_path(name), "--path", ProjectSettings.globalize_path("res://"), "--script", RUNNER_SCRIPT, "--"]
	for arg in user_args:
		args.append(str(arg))
	args.append("--output-dir=%s" % output_dir)
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), args, output, true, false)
	if exit_code != 0:
		_errors.append("Fixture %s failed with exit code %s: %s" % [name, exit_code, _join_strings(output, "\n")])
		return {"json": {}, "markdown": "", "prompt": ""}
	var json_path := _latest_file(output_dir, "ai_simulation_data_", ".json")
	var markdown_path := _latest_file(output_dir, "ai_simulation_report_", ".md")
	var prompt_path := _latest_file(output_dir, "ai_simulation_codex_prompt_", ".md")
	if json_path.is_empty() or markdown_path.is_empty() or prompt_path.is_empty():
		_errors.append("Fixture %s did not write timestamped outputs under %s." % [name, output_dir])
		return {"json": {}, "markdown": "", "prompt": ""}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_errors.append("Fixture %s did not write parseable JSON at %s." % [name, json_path])
		parsed = {}
	return {
		"json": parsed,
		"markdown": FileAccess.get_file_as_string(markdown_path),
		"prompt": FileAccess.get_file_as_string(prompt_path),
	}


func _child_log_path(name: String) -> String:
	var log_dir := ProjectSettings.globalize_path(CHILD_LOG_DIR)
	DirAccess.make_dir_recursive_absolute(log_dir)
	return "%s/ai_scenario_probe_%s_%s.log" % [log_dir, _run_id, name]


func _latest_file(output_dir: String, prefix: String, suffix: String) -> String:
	var dir := DirAccess.open(output_dir)
	if dir == null:
		return ""
	var latest := ""
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.begins_with(prefix) and file_name.ends_with(suffix):
			if latest.is_empty() or file_name > latest:
				latest = file_name
		file_name = dir.get_next()
	dir.list_dir_end()
	return "" if latest.is_empty() else "%s/%s" % [output_dir, latest]


func _expect_json_value(fixture: Dictionary, path: Array, expected, label: String) -> void:
	var current = fixture.get("json", {})
	for key in path:
		if typeof(current) != TYPE_DICTIONARY or not current.has(key):
			_errors.append("%s missing JSON path %s." % [label, _join_strings(path, ".")])
			return
		current = current[key]
	if current != expected:
		_errors.append("%s expected %s, got %s." % [label, str(expected), str(current)])


func _expect_probe_ids(fixture: Dictionary, group: String, expected: Array, label: String) -> void:
	var probes: Array = fixture.get("json", {}).get("scenario_probes", {}).get(group, [])
	var ids: Array = []
	for probe in probes:
		ids.append(str(probe.get("id", "")))
	ids.sort()
	var sorted_expected := expected.duplicate()
	sorted_expected.sort()
	if ids != sorted_expected:
		_errors.append("%s expected %s, got %s." % [label, str(sorted_expected), str(ids)])


func _expect_probe_waves(fixture: Dictionary, group: String, expected: Array, label: String) -> void:
	var probes: Array = fixture.get("json", {}).get("scenario_probes", {}).get(group, [])
	var waves: Array = []
	for probe in probes:
		waves.append(int(probe.get("wave", 0)))
	waves.sort()
	var sorted_expected := expected.duplicate()
	sorted_expected.sort()
	if waves != sorted_expected:
		_errors.append("%s expected %s, got %s." % [label, str(sorted_expected), str(waves)])


func _expect_branch_subset(fixture: Dictionary, tower_types: Array, label: String) -> void:
	var probes: Array = fixture.get("json", {}).get("scenario_probes", {}).get("branch_probes", [])
	var towers: Array = []
	for probe in probes:
		towers.append(str(probe.get("tower_type", "")))
	towers.sort()
	var sorted_expected := tower_types.duplicate()
	sorted_expected.sort()
	if towers != sorted_expected:
		_errors.append("%s expected %s, got %s." % [label, str(sorted_expected), str(towers)])


func _expect_all_enabled_branches(fixture: Dictionary) -> void:
	var expected_count := 15
	var probes: Array = fixture.get("json", {}).get("scenario_probes", {}).get("branch_probes", [])
	if probes.size() != expected_count:
		_errors.append("full branch probe count expected %s, got %s." % [expected_count, probes.size()])


func _expect_branch_exercise(fixture: Dictionary) -> void:
	var probes: Array = fixture.get("json", {}).get("scenario_probes", {}).get("branch_probes", [])
	for probe in probes:
		if str(probe.get("selected_branch", "")) != str(probe.get("branch_id", "")) or not bool(probe.get("post_branch_upgrade_succeeded", false)):
			_errors.append("branch probe did not exercise requested branch: %s." % str(probe))


func _expect_special_wave_diagnostics(fixture: Dictionary) -> void:
	var probes: Array = fixture.get("json", {}).get("scenario_probes", {}).get("scheduled_wave_probes", [])
	var diagnostic_count := 0
	for probe in probes:
		for failure in probe.get("failures", []):
			if str(failure.get("label", "")) == "scenario_scheduled_special_unspawned" and str(failure.get("severity", "")) == "info":
				diagnostic_count += 1
	if diagnostic_count == 0:
		_errors.append("expected at least one scheduled special known-gap diagnostic.")


func _expect_flying_probe_uses_unlocked_anti_air(fixture: Dictionary, label: String) -> void:
	var probe := _probe_by_id(fixture, "enemy_kind_probes", "flying")
	if probe.is_empty():
		_errors.append("%s flying enemy probe missing." % label)
		return
	var setup: Dictionary = probe.get("anti_air_setup", {})
	if int(setup.get("tesla_level", 0)) < 4:
		_errors.append("%s flying probe expected Tesla level >= 4, got %s." % [label, str(setup)])
	if int(setup.get("sniper_level", 0)) < 3:
		_errors.append("%s flying probe expected Sniper level >= 3, got %s." % [label, str(setup)])
	if float(probe.get("damage_delta", 0.0)) <= 0.0:
		_errors.append("%s flying probe expected anti-air damage, got %s." % [label, str(probe)])
	for failure in probe.get("failures", []):
		if str(failure.get("label", "")) == "scenario_spend_efficiency_out_of_range":
			_errors.append("%s flying probe should not report zero-efficiency anti-air setup: %s." % [label, str(probe)])


func _probe_by_id(fixture: Dictionary, group: String, id: String) -> Dictionary:
	var probes: Array = fixture.get("json", {}).get("scenario_probes", {}).get(group, [])
	for probe in probes:
		if str(probe.get("id", "")) == id:
			return probe
	return {}


func _expect_contains(text: String, needle: String, label: String) -> void:
	if not text.contains(needle):
		_errors.append("%s missing text: %s" % [label, needle])


func _join_strings(values: Array, separator: String) -> String:
	var text := ""
	for index in range(values.size()):
		if index > 0:
			text += separator
		text += str(values[index])
	return text
