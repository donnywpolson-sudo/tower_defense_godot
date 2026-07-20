extends SceneTree


func _initialize() -> void:
	var config_script := load("res://scripts/autoload/game_config.gd")
	var data_script := load("res://scripts/autoload/game_data.gd")
	var slice_script := load("res://scripts/game/vertical_slice_game.gd")
	var hud_script := load("res://scripts/ui/debug_hud.gd")
	var config: Node = config_script.new()
	var data_loader: Node = data_script.new()
	var game: Node = slice_script.new()
	var hud: CanvasLayer = hud_script.new()
	root.add_child(config)
	root.add_child(data_loader)
	root.add_child(game)
	root.add_child(hud)
	config.name = "GameConfig"
	data_loader.name = "GameData"
	game.name = "VerticalSliceGame"
	hud.name = "DebugHUD"
	game.reset_slice()

	var result: Dictionary = {
		"ok": true,
		"checks": [],
		"errors": [],
	}
	_record_check(result, "debug_overlay_starts_disabled", bool(game.debug_overlay_snapshot().get("enabled", true)) == false, game.debug_overlay_snapshot())
	_record_check(result, "place_archer_for_overlay", game.place_archer(Vector2(300, 243)), game.snapshot())
	_record_check(result, "start_wave_for_overlay", game.start_wave(), game.snapshot())
	game.set_debug_overlay_enabled(true)
	for _step in range(24):
		game.process_step(0.05)
	var debug_snapshot: Dictionary = game.debug_overlay_snapshot()
	var game_snapshot: Dictionary = game.snapshot()
	_record_check(result, "debug_overlay_enables", bool(debug_snapshot.get("enabled", false)), debug_snapshot)
	_record_check(result, "debug_economy_matches_game", int(debug_snapshot.get("economy", {}).get("money", -1)) == int(game_snapshot.get("money", -2)), debug_snapshot.get("economy", {}))
	_record_check(result, "debug_wave_matches_game", int(debug_snapshot.get("wave", {}).get("spawn_limit", -1)) == int(game_snapshot.get("spawn_limit", -2)), debug_snapshot.get("wave", {}))
	_record_check(result, "debug_tower_records_present", debug_snapshot.get("towers", []).size() == int(game_snapshot.get("tower_count", 0)) and debug_snapshot.get("towers", []).size() > 0, debug_snapshot.get("towers", []))
	_record_check(result, "debug_enemy_records_present", debug_snapshot.get("enemies", []).size() == int(game_snapshot.get("enemy_count", 0)) and debug_snapshot.get("enemies", []).size() > 0, debug_snapshot.get("enemies", []))
	_record_check(result, "debug_projectile_records_match", debug_snapshot.get("projectiles", []).size() == int(game_snapshot.get("projectile_count", -1)), debug_snapshot.get("projectiles", []))
	var status: Dictionary = game.status_snapshot()
	_record_check(result, "status_carries_debug_overlay", bool(status.get("debug_overlay", {}).get("enabled", false)), status)
	hud.set_status(status)
	var debug_label := hud.get_node_or_null("DebugLabel") as Label
	_record_check(result, "hud_debug_label_visible", debug_label != null and debug_label.visible and debug_label.text.contains("DBG"), debug_label.text if debug_label != null else "<missing>")
	game.set_debug_overlay_enabled(false)
	hud.set_status(game.status_snapshot())
	_record_check(result, "debug_overlay_disables", bool(game.debug_overlay_snapshot().get("enabled", true)) == false, game.debug_overlay_snapshot())
	_record_check(result, "hud_debug_label_hidden", debug_label != null and not debug_label.visible and debug_label.text == "", debug_label.text if debug_label != null else "<missing>")

	if result["ok"]:
		print("DEBUG_OVERLAY_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("DEBUG_OVERLAY_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	ValidationHarness.record_check(result, label, passed, detail)
