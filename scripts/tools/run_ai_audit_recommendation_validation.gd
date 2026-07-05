extends SceneTree

const RECOMMENDER := preload("res://scripts/tools/recommend_ai_audit_settings.gd")
const FALLBACK_ARGS := "medium --scenario-probes=auto"
const FAILED_MEDIUM_ARGS := "medium --runs=260 --max-waves=6 --seed-count=5 --scenario-probes=full --full-action-log=true --compare-previous=false --report-label=diagnostic_ai_exit"
const WAVE_MISMATCH_ARGS := "medium --runs=120 --max-waves=8 --seed-count=3 --scenario-probes=full --full-action-log=true --compare-previous=false --strategies=balanced_builder,value_upgrader,anti_leak_targeting --report-label=wave_resolution_diagnostic"
const ALLOWED_POSITIONAL := ["medium", "deep", "overnight"]
const ALLOWED_FLAGS := [
	"--runs",
	"--max-waves",
	"--seed",
	"--seed-count",
	"--seed-step",
	"--scenario-probes",
	"--full-action-log",
	"--compare-previous",
	"--report-label",
	"--strategies",
	"--strategy-group",
]

var _errors: Array = []


func _initialize() -> void:
	_run_validation()
	if _errors.is_empty():
		print("AI_AUDIT_RECOMMENDATION_VALIDATION_OK")
		quit(0)
	else:
		push_error("AI_AUDIT_RECOMMENDATION_VALIDATION_FAILED")
		for error in _errors:
			push_error(str(error))
		quit(1)


func _run_validation() -> void:
	_expect_recommendation(
		"failed medium",
		_report_text("failed", _scorecard_with_non_sim_gaps(), "### F1. Fresh medium AI simulation failed before producing a packet\nThe fresh medium run failed before producing a packet. No new packet was produced.", "Run one bounded AI simulation diagnostic."),
		FAILED_MEDIUM_ARGS
	)
	_expect_recommendation(
		"wave mismatch",
		_report_text("fresh", _scorecard_with_non_sim_gaps(), "### F2. Archived deep evidence contains `wave_resolution_mismatch`\nThe report highlights `wave_resolution_mismatch`.", "Reproduce wave accounting."),
		WAVE_MISMATCH_ARGS
	)
	var non_sim := RECOMMENDER.recommend_from_text(_report_text("fresh", _scorecard_with_non_sim_gaps(), "### F1. Non-simulation gaps dominate\nNo AI-specific failure.", "Run lane-specific checks."))
	_expect_contains(non_sim, FALLBACK_ARGS, "non-simulation fallback args")
	var non_sim_args := _recommended_args(non_sim)
	if non_sim_args.begins_with("deep") or non_sim_args.begins_with("overnight"):
		_errors.append("non-simulation must not recommend deep or overnight args: %s" % non_sim_args)
	_expect_contains(non_sim, "Non-simulation gaps", "non-simulation gap label")
	_validate_supported_args(non_sim, "non-simulation")

	var malformed := RECOMMENDER.recommend_from_text("# malformed")
	_expect_contains(malformed, FALLBACK_ARGS, "malformed fallback args")
	_expect_contains(malformed, "Confidence: low", "malformed low confidence")
	_validate_supported_args(malformed, "malformed")

	var missing := RECOMMENDER.recommend_from_report_path("res://.godot/missing_audit_report_fixture.md")
	_expect_contains(missing, FALLBACK_ARGS, "missing report fallback args")
	_expect_contains(missing, "Confidence: low", "missing low confidence")
	_validate_supported_args(missing, "missing")

	_expect_batch_menu_contract()


func _expect_recommendation(label: String, report_text: String, expected_args: String) -> void:
	var output := RECOMMENDER.recommend_from_text(report_text)
	_expect_contains(output, expected_args, "%s args" % label)
	_validate_supported_args(output, label)


func _report_text(bundle_kind: String, scorecard: String, findings: String, next_action: String) -> String:
	var bundle := "| Item | Status | Result |\n| --- | --- | --- |\n"
	if bundle_kind == "failed":
		bundle += "| `.\\TOWER_DEFENSE_AI_SIMULATION.bat medium --scenario-probes=auto` | failed | Noninteractive form reached 240/420 runs; no new packet was produced. |\n"
	else:
		bundle += "| `.\\TOWER_DEFENSE_AI_SIMULATION.bat medium --scenario-probes=auto` | fresh | Completed. |\n"
	return "\n".join([
		"# AI Simulation Audit Report",
		"## Minimum Coverage Evidence Bundle",
		bundle,
		"## Scorecard",
		scorecard,
		"## Findings",
		findings,
		"## Next Recommended Action",
		next_action,
	])


func _scorecard_with_non_sim_gaps() -> String:
	return "\n".join([
		"| Audit area | Status | Score | Evidence basis |",
		"| --- | --- | ---: | --- |",
		"| Core gameplay rules | partially proven | 72 | Direct API evidence. |",
		"| Memory and resource usage | not proven | 35 | No memory-growth result. |",
		"| Audio | partially proven | 52 | Timing and mix are not proven. |",
		"| Build/export stability | out of scope | N/A | No export lane. |",
		"| Accessibility | not proven | 30 | Not audited. |",
	])


func _validate_supported_args(output: String, label: String) -> void:
	var args := _recommended_args(output)
	if args.is_empty():
		_errors.append("%s did not print recommended command args." % label)
		return
	for token in args.split(" ", false):
		if token in ALLOWED_POSITIONAL:
			continue
		if token.begins_with("--"):
			var key := token.split("=", false, 1)[0]
			if not ALLOWED_FLAGS.has(key):
				_errors.append("%s printed unsupported flag %s." % [label, key])


func _recommended_args(output: String) -> String:
	for line in output.split("\n"):
		var text := str(line).strip_edges()
		if text.begins_with("Recommended command args:"):
			return text.trim_prefix("Recommended command args:").strip_edges()
	return ""


func _expect_batch_menu_contract() -> void:
	var batch := FileAccess.get_file_as_string("res://TOWER_DEFENSE_AI_SIMULATION.bat")
	_expect_contains(batch, "echo   1  Strategy Smoke   5 sec          14     2 waves    1       quick bot check", "menu smoke")
	_expect_contains(batch, "echo   2  Medium           5 min          420    6 waves    5       normal research", "menu medium")
	_expect_contains(batch, "echo   3  Deep             2 hr           2,500  20 waves   8       deeper evidence", "menu deep")
	_expect_contains(batch, "echo   4  Overnight        8+ hr          6,000  50 waves   12      full research", "menu overnight")
	_expect_contains(batch, "echo   5  Cancel", "menu cancel")
	_expect_contains(batch, "if \"!PROFILE_CHOICE!\"==\"1\" (\n    set \"USER_ARGS= --runs=14 --max-waves=2 --report-label=strategy_smoke\"", "choice 1 mapping")
	_expect_contains(batch, "if \"!PROFILE_CHOICE!\"==\"2\" (\n    set \"USER_ARGS= medium\"", "choice 2 mapping")
	_expect_contains(batch, "if \"!PROFILE_CHOICE!\"==\"3\" (\n    set \"USER_ARGS= deep\"", "choice 3 mapping")
	_expect_contains(batch, "if \"!PROFILE_CHOICE!\"==\"4\" (\n    set \"USER_ARGS= overnight\"", "choice 4 mapping")
	_expect_contains(batch, "if \"!PROFILE_CHOICE!\"==\"5\" (\n    echo Cancelled.", "choice 5 cancel")
	_expect_contains(batch, "goto recommend_done", "--recommend skips simulation")


func _expect_contains(text: String, needle: String, label: String) -> void:
	if not text.contains(needle):
		_errors.append("%s missing text: %s" % [label, needle])


func _expect_not_contains(text: String, needle: String, label: String) -> void:
	if text.contains(needle):
		_errors.append("%s unexpectedly contained text: %s" % [label, needle])
