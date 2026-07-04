extends SceneTree


func _initialize() -> void:
	var config_script := load("res://scripts/autoload/game_config.gd")
	var data_script := load("res://scripts/autoload/game_data.gd")
	var slice_script := load("res://scripts/game/vertical_slice_game.gd")
	var config: Node = config_script.new()
	var data_loader: Node = data_script.new()
	var game: Node = slice_script.new()
	root.add_child(config)
	root.add_child(data_loader)
	root.add_child(game)
	config.name = "GameConfig"
	data_loader.name = "GameData"
	game.name = "VerticalSliceGame"
	game.reset_slice()

	var result: Dictionary = {
		"ok": true,
		"checks": [],
		"errors": [],
	}
	_check_upgrade_panel(game, result)

	if result["ok"]:
		print("UPGRADE_PANEL_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("UPGRADE_PANEL_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)


func _check_upgrade_panel(game: Node, result: Dictionary) -> void:
	var starting_money: int = game.snapshot()["money"]
	_record_check(result, "place_archer_selects_tower", game.place_archer(game.RECOMMENDED_BUILD_SITE), game.snapshot())

	var panel: Dictionary = game.upgrade_panel_snapshot()
	_record_check(result, "panel_visible_after_placement", panel["visible"] == true, panel)
	_record_check(result, "panel_tower_name_matches_python_copy", panel["tower_name"] == "Archer Tower", panel)
	_record_check(result, "panel_stats_match_slice_archer", panel["stats"] == "L2 | DMG 39 | Range 163", panel)
	_record_check(result, "panel_details_show_branch_gate", str(panel["details"]).contains("Pick branch"), panel)
	_record_check(result, "target_label_initial", panel["target_label"] == "Target First", panel)
	_record_check(result, "sell_refund_matches_python_rate", panel["sell_refund"] == 37, panel)
	_record_check(result, "branch_gate_defers_upgrade_options", panel["needs_branch_choice"] == true and panel["upgrade_options"].is_empty(), panel)

	var target_rect: Rect2 = game.get_target_button_rect()
	_record_check(result, "target_click_handled", game.handle_upgrade_panel_click(target_rect.position + target_rect.size * 0.5), game.upgrade_panel_snapshot())
	var after_target: Dictionary = game.upgrade_panel_snapshot()
	_record_check(result, "target_click_cycles_mode", after_target["target_mode"] == "last", after_target)

	var sell_rect: Rect2 = game.get_sell_button_rect()
	_record_check(result, "sell_click_handled", game.handle_upgrade_panel_click(sell_rect.position + sell_rect.size * 0.5), game.snapshot())
	var after_sell: Dictionary = game.snapshot()
	_record_check(result, "sell_removes_selected_tower", after_sell["tower_count"] == 0, after_sell)
	_record_check(result, "sell_adds_refund", after_sell["money"] == starting_money - 50 + 37, after_sell)
	_record_check(result, "panel_hidden_after_sell", game.upgrade_panel_snapshot()["visible"] == false, game.upgrade_panel_snapshot())


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	result["checks"].append({
		"label": label,
		"passed": passed,
		"detail": detail,
	})
	if not passed:
		result["ok"] = false
		result["errors"].append("%s failed: %s" % [label, str(detail)])
