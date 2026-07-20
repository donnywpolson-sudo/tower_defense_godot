extends SceneTree


func _initialize() -> void:
	var progress: Node = load("res://scripts/autoload/game_progress.gd").new()
	root.add_child(progress)
	progress.settings["game_speed"] = 2.0
	var run_state := {"schema_version": 1, "money": 10}
	var parsed: Variant = JSON.parse_string(JSON.stringify(progress.payload(run_state)))
	var applied: bool = parsed is Dictionary and progress.apply_payload(parsed)
	if not applied or int(progress.last_run_state.get("schema_version", 0)) != 1 or int(progress.last_run_state.get("money", 0)) != 10:
		push_error("PROGRESS_PAYLOAD_VALIDATION_FAILED applied=%s parsed=%s payload=%s" % [applied, str(parsed), str(progress.payload())])
		quit(1)
		return
	print("PROGRESS_PAYLOAD_VALIDATION_OK")
	quit(0)
