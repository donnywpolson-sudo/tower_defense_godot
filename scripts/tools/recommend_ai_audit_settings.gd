extends SceneTree

const DEFAULT_REPORT_PATH := "res://_ai_audit_workflow/_internal/TOWER_DEFENSE_AI_SIMULATION_AUDIT_REPORT.md"
const FALLBACK_ARGS := "medium --scenario-probes=auto"
const FAILED_MEDIUM_ARGS := "medium --runs=260 --max-waves=6 --seed-count=5 --scenario-probes=full --full-action-log=true --compare-previous=false --report-label=diagnostic_ai_exit"
const WAVE_MISMATCH_ARGS := "medium --runs=120 --max-waves=8 --seed-count=3 --scenario-probes=full --full-action-log=true --compare-previous=false --strategies=balanced_builder,value_upgrader,anti_leak_targeting --report-label=wave_resolution_diagnostic"
const WRAP_WIDTH := 76


func _initialize() -> void:
	var options := _parse_options()
	var report_path := str(options.get("report_path", DEFAULT_REPORT_PATH))
	if bool(options.get("args_only", false)):
		print(recommend_args_from_report_path(report_path))
	else:
		print(recommend_from_report_path(report_path))
	quit(0)


static func recommend_from_report_path(report_path: String) -> String:
	return _format_recommendation_data(_recommendation_data_from_report_path(report_path))


static func recommend_args_from_report_path(report_path: String) -> String:
	return str(_recommendation_data_from_report_path(report_path).get("args", FALLBACK_ARGS))


static func recommend_from_text(report_text: String) -> String:
	return _format_recommendation_data(_recommendation_data_from_text(report_text))


static func recommend_args_from_text(report_text: String) -> String:
	return str(_recommendation_data_from_text(report_text).get("args", FALLBACK_ARGS))


static func _recommendation_data_from_report_path(report_path: String) -> Dictionary:
	if report_path.is_empty() or not FileAccess.file_exists(report_path):
		return _recommendation_data(
			FALLBACK_ARGS,
			"Run standard medium audit baseline",
			"Audit report was not found.",
			"Audit report was not found; use a conservative medium baseline or run the audit workflow first.",
			"low",
			[],
			"Report-path checks only confirm that the file is missing; they do not inspect gameplay state."
		)
	return _recommendation_data_from_text(FileAccess.get_file_as_string(report_path))


static func _recommendation_data_from_text(report_text: String) -> Dictionary:
	var bundle := _section(report_text, "Minimum Coverage Evidence Bundle")
	var scorecard := _section(report_text, "Scorecard")
	var findings := _section(report_text, "Findings")
	var next_action := _section(report_text, "Next Recommended Action")
	var parsed_sections := not bundle.is_empty() and not scorecard.is_empty() and not findings.is_empty() and not next_action.is_empty()
	if not parsed_sections:
		return _recommendation_data(
			FALLBACK_ARGS,
			"Refresh audit report, then use medium baseline",
			"Required audit report headings are missing.",
			"Audit report is missing required headings; use the fallback recommendation until the report is refreshed.",
			"low",
			[],
			"Malformed reports can hide newer evidence; refresh the report before treating this as a final recommendation."
		)

	var combined := "\n".join([bundle, scorecard, findings, next_action]).to_lower()
	var non_sim_gaps := _non_simulation_gaps(scorecard)
	if _has_failed_medium_packet_signal(combined):
		return _recommendation_data(
			FAILED_MEDIUM_ARGS,
			"Run bounded failed-medium diagnostic",
			"Fresh medium evidence failed or did not produce a current packet.",
			"Fresh medium AI simulation failed or did not produce a current packet; run a bounded diagnostic before deeper research.",
			"high",
			non_sim_gaps,
			"Simulation diagnostics will not close non-simulation lanes listed below."
		)
	if combined.contains("wave_resolution_mismatch"):
		return _recommendation_data(
			WAVE_MISMATCH_ARGS,
			"Reproduce wave accounting mismatch",
			"Audit text mentions wave_resolution_mismatch.",
			"Wave accounting mismatches need focused full-action-log reproduction against current code.",
			"high",
			non_sim_gaps,
			"Focused reproduction can confirm the mismatch but may not prove unrelated balance or UI behavior."
		)
	if not non_sim_gaps.is_empty():
		return _recommendation_data(
			FALLBACK_ARGS,
			"Close non-simulation gaps before deep simulation",
			"Scorecard has unresolved non-simulation coverage gaps.",
			"Non-simulation coverage gaps dominate; do lane-specific validation or manual review instead of escalating to deep or overnight.",
			"medium",
			non_sim_gaps,
			"The medium baseline is only supporting simulation evidence; it is not a substitute for lane-specific checks."
		)
	return _recommendation_data(
		FALLBACK_ARGS,
		"Run standard medium evidence refresh",
		"Audit report has no urgent simulation-specific diagnostic signal.",
		"No urgent simulation-specific diagnostic signal was found; use the standard medium baseline if fresh evidence is needed.",
		"medium",
		[],
		"This is a conservative default derived from report text, not a guarantee that the current balance is complete."
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


static func _recommendation_data(args: String, action: String, evidence: String, reason: String, confidence: String, non_sim_gaps: Array, limitations: String) -> Dictionary:
	return {
		"args": args,
		"action": action,
		"evidence": evidence,
		"reason": reason,
		"confidence": confidence,
		"non_sim_gaps": non_sim_gaps,
		"limitations": limitations,
	}


static func _format_recommendation_data(data: Dictionary) -> String:
	var lines := [
		"Audit recommendation",
		"  Action: %s" % str(data.get("action", "Run standard medium audit baseline")),
		"  Confidence: %s" % str(data.get("confidence", "low")),
		"",
		"Current evidence",
	]
	_append_wrapped(lines, str(data.get("evidence", "No current report evidence was parsed.")), "  ")
	lines.append("")
	lines.append("Recommended next run")
	lines.append("  Command args:")
	_append_wrapped(lines, str(data.get("args", FALLBACK_ARGS)), "    ")
	lines.append("")
	lines.append("Why")
	_append_wrapped(lines, str(data.get("reason", "")), "    ")
	lines.append("")
	lines.append("Non-simulation gaps")
	var non_sim_gaps: Array = data.get("non_sim_gaps", [])
	if not non_sim_gaps.is_empty():
		for gap in non_sim_gaps:
			lines.append("  - %s" % str(gap))
	else:
		lines.append("  None detected in parsed scorecard.")
	lines.append("")
	lines.append("Limitations")
	_append_wrapped(lines, str(data.get("limitations", "Recommendation is inferred from audit report text only.")), "  ")
	return "\n".join(lines)


static func _parse_options() -> Dictionary:
	var options := {"report_path": DEFAULT_REPORT_PATH, "args_only": false}
	var pending_key := ""
	for arg in OS.get_cmdline_user_args():
		var text := str(arg).strip_edges()
		var normalized := text
		while normalized.begins_with("-"):
			normalized = normalized.substr(1)
		if not pending_key.is_empty():
			options[pending_key] = text
			pending_key = ""
		elif normalized in ["args-only", "args_only"]:
			options["args_only"] = true
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


static func _append_wrapped(lines: Array, text: String, indent: String) -> void:
	var words := text.split(" ", false)
	var current := indent
	for word in words:
		var next_text := "%s%s" % [indent, word] if current == indent else "%s %s" % [current, word]
		if current != indent and next_text.length() > WRAP_WIDTH:
			lines.append(current)
			current = "%s%s" % [indent, word]
		else:
			current = next_text
	if current != indent:
		lines.append(current)
