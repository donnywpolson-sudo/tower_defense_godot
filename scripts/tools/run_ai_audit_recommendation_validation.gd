extends SceneTree

const RECOMMENDER := preload("res://scripts/tools/recommend_ai_audit_settings.gd")
const FALLBACK_ARGS := "--profile=medium --scenario-probes=auto --record=flagged --report-only"
const FAILED_MEDIUM_ARGS := "--profile=medium --runs=260 --max-waves=6 --seed-count=5 --scenario-probes=full --record=full --compare-previous=false --report-only --report-label=diagnostic_ai_exit"
const WAVE_MISMATCH_ARGS := "--profile=medium --runs=120 --max-waves=8 --seed-count=3 --scenario-probes=full --record=full --compare-previous=false --report-only --strategies=balanced_builder,value_upgrader,anti_leak_targeting --report-label=wave_resolution_diagnostic"
const ALLOWED_POSITIONAL := ["smoke", "medium", "deep", "overnight"]
const ALLOWED_FLAGS := [
	"--runs",
	"--max-waves",
	"--seed",
	"--seed-count",
	"--seed-step",
	"--scenario-probes",
	"--full-action-log",
	"--profile",
	"--record",
	"--coverage",
	"--manifest",
	"--compare-to",
	"--report-only",
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
	_expect_structured_output(non_sim, "non-simulation")
	_expect_contains(non_sim, "Non-simulation gaps", "non-simulation gap label")
	_validate_supported_args(non_sim, "non-simulation")

	var malformed := RECOMMENDER.recommend_from_text("# malformed")
	_expect_contains(malformed, FALLBACK_ARGS, "malformed fallback args")
	_expect_contains(malformed, "Confidence: low", "malformed low confidence")
	_expect_structured_output(malformed, "malformed")
	_validate_supported_args(malformed, "malformed")

	var missing := RECOMMENDER.recommend_from_report_path("res://.godot/missing_audit_report_fixture.md")
	_expect_contains(missing, FALLBACK_ARGS, "missing report fallback args")
	_expect_contains(missing, "Confidence: low", "missing low confidence")
	_expect_structured_output(missing, "missing")
	_validate_supported_args(missing, "missing")

	_expect_batch_menu_contract()


func _expect_recommendation(label: String, report_text: String, expected_args: String) -> void:
	var output := RECOMMENDER.recommend_from_text(report_text)
	var args := RECOMMENDER.recommend_args_from_text(report_text)
	if args != expected_args:
		_errors.append("%s args mismatch: expected %s, got %s" % [label, expected_args, args])
	_expect_structured_output(output, label)
	_validate_supported_args(output, label)


func _report_text(bundle_kind: String, scorecard: String, findings: String, next_action: String) -> String:
	var bundle := "| Item | Status | Result |\n| --- | --- | --- |\n"
	if bundle_kind == "failed":
		bundle += "| `.\\_ai_audit_workflow\\_internal\\TOWER_DEFENSE_AI_SIMULATION.bat medium --scenario-probes=auto` | failed | Configured Medium profile stopped before producing a complete packet. |\n"
	else:
		bundle += "| `.\\_ai_audit_workflow\\_internal\\TOWER_DEFENSE_AI_SIMULATION.bat medium --scenario-probes=auto` | fresh | Completed. |\n"
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
	var collecting := false
	var parts: Array = []
	for line in output.split("\n"):
		var text := str(line).strip_edges()
		if text == "Command args:":
			collecting = true
			continue
		if text.begins_with("Command args:"):
			return text.trim_prefix("Command args:").strip_edges()
		if collecting:
			if text.is_empty() or text == "Why":
				break
			parts.append(text)
	return " ".join(parts)


func _expect_structured_output(output: String, label: String) -> void:
	for heading in [
		"Audit recommendation",
		"Current evidence",
		"Recommended next run",
		"Why",
		"Non-simulation gaps",
		"Limitations",
	]:
		_expect_contains(output, heading, "%s heading %s" % [label, heading])
	_expect_contains(output, "Action:", "%s action label" % label)
	_expect_contains(output, "Command args:", "%s command args supporting detail" % label)
	if output.begins_with(FALLBACK_ARGS) or output.begins_with(FAILED_MEDIUM_ARGS) or output.begins_with(WAVE_MISMATCH_ARGS):
		_errors.append("%s output led with raw command args." % label)


func _expect_batch_menu_contract() -> void:
	var batch := FileAccess.get_file_as_string("res://_ai_audit_workflow/_internal/TOWER_DEFENSE_AI_SIMULATION.bat")
	_expect_contains(batch, "echo   #  Profile            Purpose", "menu table header")
	_expect_contains(batch, "echo   0  Recommended         use the current contract recommendation", "menu recommended")
	_expect_contains(batch, "echo   1  Smoke               bounded report-only sanity check", "menu smoke")
	_expect_contains(batch, "echo   2  Medium              standard report-only audit", "menu medium")
	_expect_contains(batch, "echo   3  Deep                deeper report-only audit", "menu deep")
	_expect_contains(batch, "echo   4  Overnight           full report-only audit", "menu overnight")
	_expect_contains(batch, "echo   5  Cancel              exit launcher", "menu cancel")
	_expect_contains(batch, "EXECUTION_LABEL", "execution label state")
	_expect_contains(batch, "Contract: config.json", "contract summary")
	_expect_not_contains(batch, "Estimated runtime:", "estimated runtime claims removed")
	_expect_not_contains(batch, "Timeout:", "timeout summary removed")
	_expect_contains(batch, "set /p \"PROFILE_CHOICE=Choose a tier [0]: \"", "menu prompt")
	_expect_contains(batch, "if \"!PROFILE_CHOICE!\"==\"\" set \"PROFILE_CHOICE=0\"", "menu default")
	_expect_not_contains(batch, "Enter 0, 1, 2, 3, 4, or 5, then press Enter:", "old menu prompt")
	_expect_not_contains(batch, "call :show_recommendation_if_available", "stale root recommendation auto-read")
	_expect_contains(batch, "if \"!PROFILE_CHOICE!\"==\"0\" (\n    set \"USER_ARGS= !RECOMMENDED_ARGS!\"", "choice 0 mapping")
	_expect_contains(batch, "if \"!PROFILE_CHOICE!\"==\"1\" (\n    set \"USER_ARGS= --profile=smoke --runs=14 --max-waves=2 --report-label=strategy_smoke --record=flagged --report-only\"", "choice 1 mapping")
	_expect_contains(batch, "if \"!PROFILE_CHOICE!\"==\"2\" (\n    set \"USER_ARGS= --profile=medium --record=flagged --report-only\"", "choice 2 mapping")
	_expect_contains(batch, "if \"!PROFILE_CHOICE!\"==\"3\" (\n    set \"USER_ARGS= --profile=deep --record=flagged --report-only\"", "choice 3 mapping")
	_expect_contains(batch, "if \"!PROFILE_CHOICE!\"==\"4\" (\n    set \"USER_ARGS= --profile=overnight --record=flagged --report-only\"", "choice 4 mapping")
	_expect_contains(batch, "if \"!PROFILE_CHOICE!\"==\"5\" (\n    echo Cancelled.", "choice 5 cancel")
	_expect_contains(batch, "goto recommend_done", "--recommend skips simulation")


func _expect_contains(text: String, needle: String, label: String) -> void:
	if not text.contains(needle):
		_errors.append("%s missing text: %s" % [label, needle])


func _expect_not_contains(text: String, needle: String, label: String) -> void:
	if text.contains(needle):
		_errors.append("%s unexpectedly contained text: %s" % [label, needle])
