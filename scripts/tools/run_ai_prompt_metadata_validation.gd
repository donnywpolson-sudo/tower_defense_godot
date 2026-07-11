extends SceneTree

const RUNNER_SCRIPT := "res://scripts/tools/run_ai_simulation_batch.gd"
const OUTPUT_BASE := "res://.godot/ai_simulation_validation"
const CHILD_LOG_DIR := "res://logs/godot"

var _errors: Array = []
var _run_id := ""


func _initialize() -> void:
	_run_id = str(Time.get_ticks_usec())
	_run_validation()
	if _errors.is_empty():
		print("AI_PROMPT_METADATA_VALIDATION_OK")
		quit(0)
	else:
		push_error("AI_PROMPT_METADATA_VALIDATION_FAILED")
		for error in _errors:
			push_error(str(error))
		quit(1)


func _run_validation() -> void:
	var smoke := _run_fixture("smoke", ["--metadata-fixture=smoke", "--runs=14", "--max-waves=2", "--report-label=metadata_smoke", "--compare-previous=false"])
	_expect_json_value(smoke, ["config", "evidence_tier"], "smoke", "smoke evidence tier")
	_expect_json_value(smoke, ["config", "profile_overridden"], true, "smoke profile override")
	_expect_json_value(smoke, ["config", "balance_actionable"], false, "smoke config balance actionable")
	_expect_json_value(smoke, ["balance_actionable"], false, "smoke report balance actionable")
	_expect_json_value(smoke, ["config", "enabled_tower_types"], ["archer", "machine_gun", "cannon", "frost", "poison", "sniper", "tesla"], "enabled tower coverage")
	_expect_json_value(smoke, ["config", "unsupported_tower_types"], ["support", "barracks"], "unsupported tower coverage")
	_expect_contains(smoke.get("prompt", ""), "Audit and verify the latest AI simulation report. Implement only confirmed issues supported by the report and current code.", "verification-first prompt")
	_expect_contains(smoke.get("prompt", ""), "No gameplay or data changes are acceptable when no confirmed issue exists.", "no-change allowed prompt")
	_expect_contains(smoke.get("prompt", ""), "This is smoke/custom diagnostic evidence and is not balance-actionable.", "smoke prompt warning")
	_expect_contains(smoke.get("markdown", ""), "No balance outliers met reporting thresholds for this run size.", "balance empty state")
	_expect_contains(smoke.get("markdown", ""), "Coverage scope: `direct_vertical_slice_api`", "coverage scope markdown")

	var medium := _run_fixture("medium", ["--metadata-fixture=medium", "--runs=420", "--max-waves=6", "--report-label=metadata_medium", "--compare-previous=false"])
	_expect_json_value(medium, ["config", "evidence_tier"], "medium", "medium evidence tier")
	_expect_json_value(medium, ["config", "profile_overridden"], false, "medium profile override")
	_expect_not_contains(medium.get("prompt", ""), "This is smoke/custom diagnostic evidence and is not balance-actionable.", "medium prompt smoke warning")
	_expect_contains(medium.get("markdown", ""), "| Wave | Runs | Avg money delta | Avg spend delta | Avg lives delta | Avg tech delta | Avg tower delta |", "economy delta labels markdown")
	_expect_not_contains(medium.get("markdown", ""), "| Wave | Runs | Avg money | Avg spend | Avg lives | Avg tech | Avg towers |", "stale economy labels markdown")
	_expect_contains(medium.get("prompt", ""), "| Wave | Runs | Avg money delta | Avg spend delta | Avg lives delta | Avg tech delta | Avg tower delta |", "economy delta labels prompt")
	_expect_not_contains(medium.get("prompt", ""), "| Wave | Runs | Avg money | Avg spend | Avg lives | Avg tech | Avg towers |", "stale economy labels prompt")

	var known_gap := _run_fixture("known_gap", ["--metadata-fixture=known_gap", "--runs=14", "--max-waves=2", "--report-label=metadata_known_gap", "--compare-previous=false"])
	_expect_contains(known_gap.get("prompt", ""), "Do Not Implement From This Prompt Unless Explicitly Requested", "known gap prompt heading")
	_expect_contains(known_gap.get("markdown", ""), "Do Not Implement From This Prompt Unless Explicitly Requested", "known gap markdown heading")

	_run_fixture("schema4", ["--metadata-fixture=schema4_previous", "--runs=14", "--max-waves=2", "--report-label=schema4_previous", "--compare-previous=false"])
	var schema5_after_schema4 := _run_fixture("schema4", ["--metadata-fixture=smoke", "--runs=14", "--max-waves=2", "--report-label=schema5_current", "--compare-previous=true"])
	_expect_contains(schema5_after_schema4.get("markdown", ""), "schema migration: establish a new schema 6 baseline.", "schema migration reason")
	_expect_contains(schema5_after_schema4.get("markdown", ""), "Schema 6 starts a new comparison baseline; deltas resume after the next matching schema 6 run.", "schema baseline text")

	_run_fixture("label", ["--metadata-fixture=medium", "--runs=420", "--max-waves=6", "--report-label=old_label", "--compare-previous=false"])
	var label_only := _run_fixture("label", ["--metadata-fixture=medium", "--runs=420", "--max-waves=6", "--report-label=new_label", "--compare-previous=true"])
	_expect_contains(label_only.get("markdown", ""), "Comparable: `yes`", "label-only comparable")
	_expect_not_contains(label_only.get("markdown", ""), "report_label", "label-only mismatch")

	_run_fixture("runs_mismatch", ["--metadata-fixture=medium", "medium", "--runs=421", "--max-waves=6", "--report-label=previous_runs", "--compare-previous=false"])
	var runs_mismatch := _run_fixture("runs_mismatch", ["--metadata-fixture=medium", "medium", "--runs=420", "--max-waves=6", "--report-label=current_runs", "--compare-previous=true"])
	_expect_contains(runs_mismatch.get("markdown", ""), "same family, not comparable: previous report has different runs.", "runs mismatch")

	_run_fixture("seed_mismatch", ["--metadata-fixture=medium", "--runs=420", "--max-waves=6", "--seed=999", "--report-label=previous_seed", "--compare-previous=false"])
	var seed_mismatch := _run_fixture("seed_mismatch", ["--metadata-fixture=medium", "--runs=420", "--max-waves=6", "--seed=12345", "--report-label=current_seed", "--compare-previous=true"])
	_expect_contains(seed_mismatch.get("markdown", ""), "same family, not comparable: previous report has different seed.", "seed mismatch")

	_run_fixture("strategies_mismatch", ["--metadata-fixture=medium", "--runs=420", "--max-waves=6", "--strategies=balanced_builder", "--report-label=previous_strategies", "--compare-previous=false"])
	var strategies_mismatch := _run_fixture("strategies_mismatch", ["--metadata-fixture=medium", "--runs=420", "--max-waves=6", "--report-label=current_strategies", "--compare-previous=true"])
	_expect_contains(strategies_mismatch.get("markdown", ""), "same family, not comparable: previous report has different strategies.", "strategies mismatch")

	_run_fixture("log_mismatch", ["--metadata-fixture=medium", "--runs=420", "--max-waves=6", "--full-action-log=true", "--report-label=previous_log", "--compare-previous=false"])
	var log_mismatch := _run_fixture("log_mismatch", ["--metadata-fixture=medium", "--runs=420", "--max-waves=6", "--full-action-log=false", "--report-label=current_log", "--compare-previous=true"])
	_expect_contains(log_mismatch.get("markdown", ""), "same family, not comparable: previous report has different full_action_log.", "full action log mismatch")

	_run_fixture("stronger_evidence", ["--metadata-fixture=medium", "--runs=420", "--max-waves=6", "--report-label=stronger_medium", "--compare-previous=false"])
	var weaker_after_stronger := _run_fixture("stronger_evidence", ["--metadata-fixture=smoke", "--runs=14", "--max-waves=2", "--report-label=weaker_smoke", "--compare-previous=false"])
	_expect_contains(weaker_after_stronger.get("markdown", ""), "Evidence warning: Stronger medium evidence exists", "stronger evidence markdown warning")
	_expect_contains(weaker_after_stronger.get("prompt", ""), "Evidence warning: Stronger medium evidence exists", "stronger evidence prompt warning")

	var readme := FileAccess.get_file_as_string("res://README.md")
	_expect_not_contains(readme, "codex_" + "prompts\\ai_simulation_latest.md", "README stale prompt path")


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
	var json_text := FileAccess.get_file_as_string(json_path)
	var parsed = JSON.parse_string(json_text)
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
	return "%s/ai_prompt_metadata_%s_%s.log" % [log_dir, _run_id, name]


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


func _expect_contains(text: String, needle: String, label: String) -> void:
	if not text.contains(needle):
		_errors.append("%s missing text: %s" % [label, needle])


func _expect_not_contains(text: String, needle: String, label: String) -> void:
	if text.contains(needle):
		_errors.append("%s unexpectedly contained text: %s" % [label, needle])


func _join_strings(values: Array, separator: String) -> String:
	var text := ""
	for index in range(values.size()):
		if index > 0:
			text += separator
		text += str(values[index])
	return text
