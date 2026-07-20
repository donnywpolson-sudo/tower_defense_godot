extends SceneTree

const OK_TOKEN := "AI_WORKFLOW_CONTRACT_VALIDATION_OK"
const OUTPUT_DIR := "res://.godot/ai_simulation/workflow_contract_validation"
const COMPLETION_OUTPUT_DIR := "res://.godot/ai_simulation/workflow_contract_completion_validation"


func _initialize() -> void:
	var failures: Array = []
	_validate_pursue_goal_approval_contract(failures)
	var config = JSON.parse_string(FileAccess.get_file_as_string("res://_ai_audit_workflow/_internal/config.json"))
	if typeof(config) != TYPE_DICTIONARY:
		failures.append("workflow config did not parse as an object")
	else:
		_check_profile(config, "Smoke", 14, 2, failures)
		_check_profile(config, "Medium", 420, 6, failures)
		_check_profile(config, "Deep", 2500, 20, failures)
		_check_profile(config, "Overnight", 6000, 50, failures)
		if str(config.get("profileAliases", {}).get("Light", "")) != "Medium":
			failures.append("Light compatibility alias is not Medium")
		if not bool(config.get("reportFirstDefault", false)):
			failures.append("reportFirstDefault is not enabled")

	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_path)
	var command_output: Array = []
	var executable := OS.get_executable_path()
	var arguments := [
		"--headless",
		"--log-file",
		ProjectSettings.globalize_path("logs/godot/godot_ai_workflow_contract_fixture.log"),
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--script",
		"res://scripts/tools/run_ai_simulation_batch.gd",
		"--",
		"--profile=smoke",
		"--runs=20",
		"--max-waves=1",
		"--seed-count=1",
		"--strategy-group=standard_research",
		"--branch-set=glacier,shatter",
		"--map-set=split",
		"--scenario-probes=off",
		"--coverage=smoke",
		"--record=flagged",
		"--report-only",
		"--output-dir=%s" % OUTPUT_DIR,
	]
	var exit_code := OS.execute(executable, arguments, command_output, true)
	if exit_code != 0:
		failures.append("fixture runner exited with %s: %s" % [exit_code, " ".join(command_output)])
	else:
		var packet := _latest_packet(output_path)
		_validate_packet(packet, failures)
		_validate_completion_fixture(failures)
		_validate_reward_card_slice(failures)
		_validate_unfinished_branch_rejection(failures)

	if failures.is_empty():
		print(OK_TOKEN)
		quit(0)
	else:
		for failure in failures:
			push_error(str(failure))
		push_error("AI_WORKFLOW_CONTRACT_VALIDATION_FAILED")
		quit(1)


func _validate_pursue_goal_approval_contract(failures: Array) -> void:
	var wrapper := FileAccess.get_file_as_string("res://_ai_audit_workflow/PURSUE_GOAL.ps1")
	var runner := FileAccess.get_file_as_string("res://_ai_audit_workflow/_internal/pursue_goal.ps1")
	var queue_builder := FileAccess.get_file_as_string("res://_ai_audit_workflow/_internal/build_improvement_queue.ps1")
	var improvement_runner := FileAccess.get_file_as_string("res://_ai_audit_workflow/_internal/run_improvement_pass.ps1")
	var remediation_contract := FileAccess.get_file_as_string("res://_ai_audit_workflow/_internal/remediation_contract.ps1")
	for token in ["ApproveMutation", "ApproveExport"]:
		if not wrapper.contains(token):
			failures.append("pursue-goal wrapper is missing %s" % token)
		if not runner.contains(token):
			failures.append("pursue-goal runner is missing %s" % token)
	for token in ["Mutation stage requires explicit -ApproveMutation", "Export stage requires explicit -ApproveExport"]:
		if not runner.contains(token):
			failures.append("pursue-goal runner is missing approval guard: %s" % token)
	if not runner.contains("-ApproveMutation:' + [string]$ApproveMutation") or not runner.contains("-ApproveExport:' + [string]$ApproveExport"):
		failures.append("pursue-goal child goals do not receive approval switches")
	for token in ["allowedFiles", "validator", "expectedToken", "timeoutSeconds"]:
		if not queue_builder.contains(token):
			failures.append("queue builder is missing structured remediation contract: %s" % token)
	for token in ["findingId", "disposition", "filesChanged", "no_code_change", "git diff --check"]:
		if not (improvement_runner + remediation_contract).contains(token):
			failures.append("improvement runner is missing structured closure gate: %s" % token)
	for token in ["^[a-z0-9][a-z0-9_-]{0,63}$", "res://scripts/tools/", "Goal contract escaped"]:
		if not runner.contains(token):
			failures.append("pursue-goal runner is missing repository-only guard: %s" % token)


func _check_profile(config: Dictionary, profile: String, runs: int, waves: int, failures: Array) -> void:
	var row: Dictionary = config.get("tiers", {}).get(profile, {})
	if int(row.get("runs", -1)) != runs or int(row.get("maxWaves", -1)) != waves:
		failures.append("%s profile is not %s runs/%s waves" % [profile, runs, waves])


func _latest_packet(folder: String) -> Dictionary:
	var dir := DirAccess.open(folder)
	if dir == null:
		return {}
	var names: Array = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.begins_with("ai_simulation_data_") and file_name.ends_with(".json"):
			names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	if names.is_empty():
		return {}
	names.sort()
	var json_name := str(names[names.size() - 1])
	var packet_id := json_name.trim_prefix("ai_simulation_data_").trim_suffix(".json")
	return {
		"id": packet_id,
		"json": folder.path_join(json_name),
		"report": folder.path_join("ai_simulation_report_%s.md" % packet_id),
		"prompt": folder.path_join("ai_simulation_codex_prompt_%s.md" % packet_id),
		"manifest": folder.path_join("ai_simulation_manifest_%s.json" % packet_id),
	}


func _validate_packet(packet: Dictionary, failures: Array) -> void:
	if packet.is_empty():
		failures.append("fixture did not produce a packet")
		return
	for key in ["json", "report", "prompt", "manifest"]:
		if not FileAccess.file_exists(str(packet[key])):
			failures.append("packet is missing %s" % key)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(str(packet["json"])))
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(str(packet["manifest"])))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(manifest) != TYPE_DICTIONARY:
		failures.append("packet JSON or manifest did not parse")
		return
	var identity: Dictionary = parsed.get("packet_identity", {})
	var manifest_identity: Dictionary = manifest.get("packet_identity", {})
	if str(identity.get("packet_id", "")) != str(packet["id"]):
		failures.append("JSON packet identity does not match filename")
	if str(manifest_identity.get("packet_id", "")) != str(packet["id"]):
		failures.append("manifest packet identity does not match filename")
	if str(identity.get("canonical_data_hash", "")) == "" or str(identity.get("git_status_classification", "")) == "":
		failures.append("packet identity is missing canonical data or Git classification")
	if identity != manifest_identity:
		failures.append("manifest and JSON packet identities differ")
	for key in ["report", "prompt"]:
		var artifact_text := FileAccess.get_file_as_string(str(packet[key]))
		if not artifact_text.contains(str(packet["id"])) or not artifact_text.contains("Split Road") or not artifact_text.contains("Map set:"):
			failures.append("%s artifact does not contain the complete packet identity summary" % key)
	if int(parsed.get("schema_version", 0)) != 7:
		failures.append("unexpected packet schema")
	var packet_config: Dictionary = parsed.get("config", {})
	if str(packet_config.get("record", "")) != "flagged" or not bool(packet_config.get("report_only", false)):
		failures.append("record/report-only interface metadata is incorrect")
	if str(packet_config.get("map_set", "")) != "split" or packet_config.get("selected_map_names", []) != ["Split Road"]:
		failures.append("Split map-set identity is missing or incorrect")
	if str(packet_config.get("completion_mode", "off")) != "off" or bool(packet_config.get("completion_focus", false)):
		failures.append("default fixture unexpectedly entered completion mode")
	var expected_strategies := ["balanced_builder", "tower_specialist", "upgrade_rusher", "wide_builder", "target_mode_tester", "edge_case_explorer", "speed_stress", "economy_saver", "leak_recovery", "value_upgrader"]
	var configured_strategies: Array = packet_config.get("strategies", [])
	for strategy in expected_strategies:
		if not configured_strategies.has(strategy):
			failures.append("standard_research strategy is missing: %s" % strategy)
	var runs: Array = parsed.get("runs", [])
	if runs.size() != int(packet_config.get("runs", 0)):
		failures.append("packet run count does not match config")
	var map_indices: Array = identity.get("map_indices", [])
	if map_indices.size() != 1:
		failures.append("Split packet map identity does not contain exactly one map index")
	var branch_counts := {"glacier": 0, "shatter": 0}
	var strategy_counts := {}
	for run in runs:
		if str(run.get("map_name", "")) != "Split Road":
			failures.append("packet contains a non-Split map run")
		if map_indices.size() == 1 and int(run.get("map_index", -1)) != int(map_indices[0]):
			failures.append("packet map index does not match map identity")
		var assignment := str(run.get("branch_assignment", ""))
		if branch_counts.has(assignment):
			branch_counts[assignment] = int(branch_counts[assignment]) + 1
		var strategy := str(run.get("strategy", ""))
		strategy_counts[strategy] = int(strategy_counts.get(strategy, 0)) + 1
	if int(branch_counts["glacier"]) != int(branch_counts["shatter"]):
		failures.append("branch assignment is unbalanced")
	for strategy in expected_strategies:
		if int(strategy_counts.get(strategy, 0)) <= 0:
			failures.append("packet has no run for strategy %s" % strategy)


func _validate_completion_fixture(failures: Array) -> void:
	var output_path := ProjectSettings.globalize_path(COMPLETION_OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_path)
	var command_output: Array = []
	var executable := OS.get_executable_path()
	var arguments := [
		"--headless",
		"--log-file",
		ProjectSettings.globalize_path("logs/godot/godot_ai_workflow_completion_contract_fixture.log"),
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--script",
		"res://scripts/tools/run_ai_simulation_batch.gd",
		"--",
		"--profile=medium",
		"--runs=4",
		"--max-waves=1",
		"--seed-count=1",
		"--strategies=completion_research",
		"--branch-set=glacier,shatter",
		"--map-set=split",
		"--completion-mode=prebranch",
		"--scenario-probes=off",
		"--coverage=full",
		"--record=flagged",
		"--report-only",
		"--output-dir=%s" % COMPLETION_OUTPUT_DIR,
	]
	var exit_code := OS.execute(executable, arguments, command_output, true)
	if exit_code != 0:
		failures.append("completion fixture runner exited with %s: %s" % [exit_code, " ".join(command_output)])
		return
	var packet := _latest_packet(output_path)
	if packet.is_empty():
		failures.append("completion fixture did not produce a packet")
		return
	for key in ["json", "report", "prompt", "manifest"]:
		if not FileAccess.file_exists(str(packet[key])):
			failures.append("completion packet is missing %s" % key)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(str(packet["json"])))
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(str(packet["manifest"])))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(manifest) != TYPE_DICTIONARY:
		failures.append("completion packet JSON or manifest did not parse")
		return
	var identity: Dictionary = parsed.get("packet_identity", {})
	var manifest_identity: Dictionary = manifest.get("packet_identity", {})
	if identity != manifest_identity or str(identity.get("packet_id", "")) != str(packet["id"]):
		failures.append("completion packet identity does not match its manifest or filename")
	var config: Dictionary = parsed.get("config", {})
	if str(config.get("completion_mode", "")) != "prebranch" or not bool(config.get("completion_focus", false)):
		failures.append("completion fixture did not declare prebranch completion mode")
	if int(config.get("completion_setup_budget", 0)) != 5000 or str(config.get("completion_layout_id", "")) != "split_default_control":
		failures.append("completion fixture setup contract is incorrect")
	if config.get("strategies", []) != ["completion_research"] or str(config.get("map_set", "")) != "split":
		failures.append("completion fixture strategy or map contract is incorrect")
	var runs: Array = parsed.get("runs", [])
	if runs.size() != 4:
		failures.append("completion fixture run count is not 4")
	var branch_counts := {"glacier": 0, "shatter": 0}
	for run in runs:
		if not bool(run.get("completion_focus", false)) or not bool(run.get("completion_setup_valid", false)):
			failures.append("completion fixture run is not setup-valid completion evidence")
		if not bool(run.get("completion_branch_ready", false)) or not bool(run.get("completion_post_branch_upgrade_succeeded", false)):
			failures.append("completion fixture run did not reach a valid Frost branch state")
		if str(run.get("completion_actual_branch", "")) != str(run.get("branch_assignment", "")):
			failures.append("completion fixture actual Frost branch differs from assignment")
		var assignment := str(run.get("branch_assignment", ""))
		if branch_counts.has(assignment):
			branch_counts[assignment] = int(branch_counts[assignment]) + 1
	if int(branch_counts["glacier"]) != 2 or int(branch_counts["shatter"]) != 2:
		failures.append("completion fixture branch assignment is not balanced")
	var completion_metrics: Dictionary = parsed.get("completion_coverage_metrics", {})
	if not bool(completion_metrics.get("enabled", false)) or not bool(completion_metrics.get("standard_balance_excluded", false)) or not completion_metrics.has("coverage_failure"):
		failures.append("completion metrics are not isolated from standard balance evidence")
	var completion_strategy_metrics: Dictionary = parsed.get("strategy_metrics", {})
	if not completion_strategy_metrics.is_empty() or bool(parsed.get("balance_actionable", true)):
		failures.append("completion fixture contaminated standard balance metrics")
	for key in ["report", "prompt"]:
		var artifact_text := FileAccess.get_file_as_string(str(packet[key]))
		if not artifact_text.contains(str(packet["id"])) or not artifact_text.contains("prebranch") or not artifact_text.contains("Completion"):
			failures.append("completion %s artifact is missing completion identity" % key)


func _validate_reward_card_slice(failures: Array) -> void:
	var script = load("res://scripts/game/vertical_slice_game.gd")
	var game = script.new()
	root.add_child(game)
	game.reset_slice()
	game.money = 5000
	if not game.place_archer():
		failures.append("reward-card fixture could not place a tower")
	game.set_wave_for_test(3)
	game.wave_active = true
	game.spawned_this_wave = int(game.snapshot().get("spawn_limit", 0))
	game.kills = game.spawned_this_wave
	game.enemies = []
	game.process_step(0.01)
	var choice: Dictionary = game.reward_card_choice_snapshot()
	if not bool(choice.get("pending", false)) or choice.get("choices", []).is_empty():
		failures.append("wave 3 did not offer a reward-card choice")
	else:
		var selected: Dictionary = choice.get("choices", [])[0]
		if not game.choose_reward_card(str(selected.get("id", ""))):
			failures.append("reward-card choice could not be selected")
		if bool(game.reward_card_choice_snapshot().get("pending", false)):
			failures.append("reward-card choice remained pending after selection")
	game.queue_free()


func _validate_unfinished_branch_rejection(failures: Array) -> void:
	var script = load("res://scripts/game/vertical_slice_game.gd")
	var game = script.new()
	root.add_child(game)
	game.reset_slice()
	game.money = 5000
	game.set_wave_for_test(8)
	if not game.place_selected_tower(Vector2(300, 243), "machine_gun"):
		failures.append("machine-gun branch fixture could not place a tower")
	else:
		game.selected_tower_index = 0
		if not game.upgrade_selected_tower():
			failures.append("machine-gun fixture could not reach level 2")
		var money_before: int = game.money
		if game.choose_selected_tower_branch("vulcan"):
			failures.append("unfinished machine-gun Vulcan branch was selectable")
		if game.upgrade_selected_tower() or game.money != money_before or int(game.towers[0].get("level", 0)) != 2:
			failures.append("unfinished machine-gun upgrade did not fail closed")
	game.queue_free()
