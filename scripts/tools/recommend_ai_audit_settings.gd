extends SceneTree

const DEFAULT_REPORT_PATH := "res://TOWER_DEFENSE_AI_SIMULATION_AUDIT_REPORT.md"
const FALLBACK_ARGS := "medium --scenario-probes=auto"
const FAILED_MEDIUM_ARGS := "medium --runs=260 --max-waves=6 --seed-count=5 --scenario-probes=full --full-action-log=true --compare-previous=false --report-label=diagnostic_ai_exit"
const WAVE_MISMATCH_ARGS := "medium --runs=120 --max-waves=8 --seed-count=3 --scenario-probes=full --full-action-log=true --compare-previous=false --strategies=balanced_builder,value_upgrader,anti_leak_targeting --report-label=wave_resolution_diagnostic"


func _initialize() -> void:
	var options := _parse_options()
	var recommendation := recommend_from_report_path(str(options.get("report_path", DEFAULT_REPORT_PATH)))
	print(recommendation)
	quit(0)


static func recommend_from_report_path(report_path: String) -> String:
	if report_path.is_empty() or not FileAccess.file_exists(report_path):
		return _format_recommendation(
			FALLBACK_ARGS,
			"Audit report was not found; use a conservative medium baseline or run the audit workflow first.",
			"low",
			[]
		)
	return recommend_from_text(FileAccess.get_file_as_string(report_path))


static func recommend_from_text(report_text: String) -> String:
	var bundle := _section(report_text, "Minimum Coverage Evidence Bundle")
	var scorecard := _section(report_text, "Scorecard")
	var findings := _section(report_text, "Findings")
	var next_action := _section(report_text, "Next Recommended Action")
	var parsed_sections := not bundle.is_empty() and not scorecard.is_empty() and not findings.is_empty() and not next_action.is_empty()
	if not parsed_sections:
		return _format_recommendation(
			FALLBACK_ARGS,
			"Audit report is missing required headings; use the fallback recommendation until the report is refreshed.",
			"low",
			[]
		)

	var combined := "\n".join([bundle, scorecard, findings, next_action]).to_lower()
	var non_sim_gaps := _non_simulation_gaps(scorecard)
	if _has_failed_medium_packet_signal(combined):
		return _format_recommendation(
			FAILED_MEDIUM_ARGS,
			"Fresh medium AI simulation failed or did not produce a current packet; run a bounded diagnostic before deeper research.",
			"high",
			non_sim_gaps
		)
	if combined.contains("wave_resolution_mismatch"):
		return _format_recommendation(
			WAVE_MISMATCH_ARGS,
			"Wave accounting mismatches need focused full-action-log reproduction against current code.",
			"high",
			non_sim_gaps
		)
	if not non_sim_gaps.is_empty():
		return _format_recommendation(
			FALLBACK_ARGS,
			"Non-simulation coverage gaps dominate; do lane-specific validation or manual review instead of escalating to deep or overnight.",
			"medium",
			non_sim_gaps
		)
	return _format_recommendation(
		FALLBACK_ARGS,
		"No urgent simulation-specific diagnostic signal was found; use the standard medium baseline if fresh evidence is needed.",
		"medium",
		[]
	)


static func _has_failed_medium_packet_signal(text: String) -> bool:
	return (
		text.contains("medium") and text.contains("failed") and text.contains("no new packet")
	) or (
		text.contains("fresh medium") and text.contains("failed") and text.contains("missing")
	) or (
		text.contains("failed before producing a packet")
	)


static func _non_simulation_gaps(scorecard: String) -> Array:
	var gaps: Array = []
	var lower := scorecard.to_lower()
	var lane_labels := {
		"memory and resource usage": "memory/resource validation",
		"audio": "audio feedback review",
		"build/export stability": "export validation",
		"platform compatibility": "platform compatibility checks",
		"accessibility": "accessibility review",
		"localization": "localization/text review",
	}
	for lane in lane_labels.keys():
		if lower.contains("| %s | not proven" % lane) or lower.contains("| %s | out of scope" % lane) or lower.contains("| %s | partially proven | 3" % lane) or lower.contains("| %s | partially proven | 4" % lane) or lower.contains("| %s | partially proven | 5" % lane):
			gaps.append(lane_labels[lane])
	return gaps


static func _section(markdown: String, heading: String) -> String:
	var lines := markdown.split("\n")
	var target := "## %s" % heading
	var in_section := false
	var collected: Array = []
	for raw_line in lines:
		var line := str(raw_line).strip_edges()
		if line == target:
			in_section = true
			continue
		if in_section and line.begins_with("## "):
			break
		if in_section:
			collected.append(str(raw_line))
	return "\n".join(collected).strip_edges()


static func _format_recommendation(args: String, reason: String, confidence: String, non_sim_gaps: Array) -> String:
	var lines := [
		"Current audit recommendation:",
		"  Recommended command args: %s" % args,
		"  Confidence: %s" % confidence,
		"  Reason: %s" % reason,
	]
	if not non_sim_gaps.is_empty():
		lines.append("  Non-simulation gaps: %s" % _join_strings(non_sim_gaps, ", "))
	return "\n".join(lines)


static func _parse_options() -> Dictionary:
	var options := {"report_path": DEFAULT_REPORT_PATH}
	var pending_key := ""
	for arg in OS.get_cmdline_user_args():
		var text := str(arg).strip_edges()
		var normalized := text
		while normalized.begins_with("-"):
			normalized = normalized.substr(1)
		if not pending_key.is_empty():
			options[pending_key] = text
			pending_key = ""
		elif normalized in ["report-path", "report_path"]:
			pending_key = "report_path"
		elif normalized.begins_with("report-path=") or normalized.begins_with("report_path="):
			options["report_path"] = _arg_value(text)
	return options


static func _arg_value(arg: String) -> String:
	var parts := arg.split("=", false, 1)
	return parts[1] if parts.size() > 1 else ""


static func _join_strings(values: Array, separator: String) -> String:
	var text := ""
	for index in range(values.size()):
		if index > 0:
			text += separator
		text += str(values[index])
	return text
