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
	game.set_layout_viewport_override_for_tests(Vector2(1180, 820))
	game.reset_slice()
	game.money = 400
	var layout: Dictionary = game.layout_snapshot()
	_record_check(result, "bottom_upgrade_layout_active", str(layout["mode"]) == "bottom_dock", layout)
	_record_check(result, "upgrade_panel_uses_bottom_detail_panel", layout["upgrade_panel_rect"] == layout["detail_panel_rect"], layout)
	var starting_money: int = game.snapshot()["money"]
	_record_check(result, "place_archer_selects_tower", game.place_archer(game.RECOMMENDED_BUILD_SITE), game.snapshot())

	var panel: Dictionary = game.upgrade_panel_snapshot()
	_record_check(result, "bottom_target_and_sell_fit_upgrade_panel", _rect_inside(game.get_target_button_rect(), game.get_upgrade_panel_rect()) and _rect_inside(game.get_sell_button_rect(), game.get_upgrade_panel_rect()), {"target": game.get_target_button_rect(), "sell": game.get_sell_button_rect(), "panel": game.get_upgrade_panel_rect()})
	_record_check(result, "panel_visible_after_placement", panel["visible"] == true, panel)
	_record_check(result, "panel_tower_name_matches_game_data_copy", panel["tower_name"] == "Archer Tower", panel)
	_record_check(result, "placed_tower_starts_at_level_one", panel["stats"] == "L1", panel)
	_record_check(result, "panel_stat_detail_has_damage_range_fire", _has_damage_range_fire_stats(panel), panel)
	_record_check(result, "panel_details_show_future_focus", str(panel["details"]).contains("Focus at L3") and not str(panel["details"]).contains("Branch"), panel)
	_record_check(result, "target_label_initial", panel["target_label"] == "Target First", panel)
	_record_check(result, "sell_refund_matches_game_data_rate", panel["sell_refund"] == 37, panel)
	_record_check(result, "level_one_upgrade_available", panel["needs_branch_choice"] == false and panel["upgrade_options"].size() == 1 and int(panel["upgrade_options"][0]["cost"]) == 60, panel)
	var upgrade_rects: Array = game.get_upgrade_button_rects()
	_record_check(result, "upgrade_button_available", upgrade_rects.size() == 1, upgrade_rects)
	game.money = 59
	panel = game.upgrade_panel_snapshot()
	_record_check(result, "unaffordable_upgrade_has_reason", panel["upgrade_options"].size() == 1 and bool(panel["upgrade_options"][0]["enabled"]) == false and not str(panel["upgrade_options"][0].get("disabled_reason", "")).is_empty(), panel)
	_record_check(result, "unaffordable_upgrade_click_does_not_mutate", game.handle_upgrade_panel_click(upgrade_rects[0].position + upgrade_rects[0].size * 0.5) and game.snapshot()["money"] == 59 and game.upgrade_panel_snapshot()["stats"] == "L1", {"snapshot": game.snapshot(), "panel": game.upgrade_panel_snapshot()})
	game.money = starting_money - 50
	_record_check(result, "upgrade_click_handled", game.handle_upgrade_panel_click(upgrade_rects[0].position + upgrade_rects[0].size * 0.5), game.upgrade_panel_snapshot())
	panel = game.upgrade_panel_snapshot()
	_record_check(result, "upgrade_moves_tower_to_level_two", panel["stats"] == "L2" and int(panel["stat_detail"]["damage"]) == 39 and int(panel["stat_detail"]["range"]) == 163 and str(panel["stat_detail"]["shooting_speed_label"]) == "2.0/s", panel)
	_record_check(result, "focus_gate_shows_l3_choices", panel["needs_branch_choice"] == true and panel["upgrade_options"].is_empty() and panel["branch_options"].size() >= 2 and str(panel["details"]).contains("Choose L3 Focus"), panel)
	_record_check(result, "ranger_focus_names_present", _has_ranger_focus_names(panel), panel["branch_options"])
	_record_check(result, "focus_options_are_single_word", _focus_options_are_single_word(panel), panel["branch_options"])
	_record_check(result, "focus_options_have_perk_copy", _focus_options_have_perk_copy(panel), panel["branch_options"])
	_record_check(result, "focus_options_do_not_use_abbreviations_as_primary", _focus_options_do_not_use_abbreviations_as_primary(panel), panel["branch_options"])
	var focus_rects: Array = game.get_branch_button_rects()
	_record_check(result, "focus_buttons_match_options", focus_rects.size() == panel["branch_options"].size() and _focus_rects_use_display_names(focus_rects), focus_rects)
	var chosen_branch: String = str(focus_rects[0]["branch_id"])
	_record_check(result, "focus_click_handled", game.handle_upgrade_panel_click(focus_rects[0]["rect"].position + focus_rects[0]["rect"].size * 0.5), game.upgrade_panel_snapshot())
	panel = game.upgrade_panel_snapshot()
	_record_check(result, "focus_selection_stored", panel["selected_branch"] == chosen_branch and str(panel["selected_branch_name"]) != "" and not str(panel["selected_branch_name"]).contains(" ") and panel["needs_branch_choice"] == false, panel)
	upgrade_rects = game.get_upgrade_button_rects()
	_record_check(result, "l3_upgrade_available_after_branch", upgrade_rects.size() == 1 and panel["upgrade_options"].size() == 1 and int(panel["upgrade_options"][0]["cost"]) == 125 and str(panel["upgrade_options"][0]["title"]) == "Upgrade to L3", panel)
	_record_check(result, "l3_upgrade_click_handled", game.handle_upgrade_panel_click(upgrade_rects[0].position + upgrade_rects[0].size * 0.5), game.upgrade_panel_snapshot())
	panel = game.upgrade_panel_snapshot()
	_record_check(result, "upgrade_moves_tower_to_level_three", panel["stats"] == "L3" and panel["selected_branch"] == chosen_branch and str(panel["details"]).contains("Focus: %s" % str(panel["selected_branch_name"])) and not str(panel["details"]).contains("Branch:"), panel)

	var target_rect: Rect2 = game.get_target_button_rect()
	_record_check(result, "target_click_handled", game.handle_upgrade_panel_click(target_rect.position + target_rect.size * 0.5), game.upgrade_panel_snapshot())
	var after_target: Dictionary = game.upgrade_panel_snapshot()
	_record_check(result, "target_click_cycles_mode", after_target["target_mode"] == "last", after_target)

	var sell_rect: Rect2 = game.get_sell_button_rect()
	_record_check(result, "sell_click_handled", game.handle_upgrade_panel_click(sell_rect.position + sell_rect.size * 0.5), game.snapshot())
	var after_sell: Dictionary = game.snapshot()
	_record_check(result, "sell_removes_selected_tower", after_sell["tower_count"] == 0, after_sell)
	_record_check(result, "sell_adds_refund", after_sell["money"] == starting_money - 50 - 60 - 125 + 176, after_sell)
	_record_check(result, "panel_hidden_after_sell", game.upgrade_panel_snapshot()["visible"] == false, game.upgrade_panel_snapshot())
	game.clear_layout_viewport_override_for_tests()


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	result["checks"].append({
		"label": label,
		"passed": passed,
		"detail": detail,
	})
	if not passed:
		result["ok"] = false
		result["errors"].append("%s failed: %s" % [label, str(detail)])


func _has_damage_range_fire_stats(panel: Dictionary) -> bool:
	var stats: Dictionary = panel.get("stat_detail", {})
	if int(stats.get("damage", 0)) != 36 or int(stats.get("range", 0)) != 151:
		return false
	if str(stats.get("shooting_speed_label", "")) != "2.0/s":
		return false
	return stats.has("damage_rating") and stats.has("range_rating") and stats.has("shooting_speed_rating")


func _has_ranger_focus_names(panel: Dictionary) -> bool:
	var names := _focus_names(panel)
	return names.has("Deadeye") and names.has("Trapline") and names.has("Beastmaster")


func _focus_names(panel: Dictionary) -> Array:
	var names: Array = []
	for option in panel.get("branch_options", []):
		names.append(str(option.get("focus_name", option.get("name", ""))))
	return names


func _focus_options_are_single_word(panel: Dictionary) -> bool:
	for name in _focus_names(panel):
		var focus_name := str(name)
		if focus_name.is_empty() or focus_name.contains(" ") or focus_name.contains("-"):
			return false
	return true


func _focus_options_have_perk_copy(panel: Dictionary) -> bool:
	for option in panel.get("branch_options", []):
		if str(option.get("focus_category", "")).is_empty():
			return false
		if str(option.get("perk_summary", "")).is_empty():
			return false
		if str(option.get("effect_preview", "")).is_empty():
			return false
	return true


func _focus_options_do_not_use_abbreviations_as_primary(panel: Dictionary) -> bool:
	for option in panel.get("branch_options", []):
		var focus_name := str(option.get("focus_name", ""))
		if focus_name.is_empty() or str(option.get("name", "")) != focus_name:
			return false
		if focus_name == str(option.get("short", "")):
			return false
	return true


func _focus_rects_use_display_names(focus_rects: Array) -> bool:
	for rect in focus_rects:
		var focus_name := str(rect.get("focus_name", ""))
		if focus_name.is_empty() or str(rect.get("name", "")) != focus_name:
			return false
		if focus_name == str(rect.get("short", "")):
			return false
		if str(rect.get("perk_summary", "")).is_empty():
			return false
	return true


func _rect_inside(inner: Rect2, outer: Rect2) -> bool:
	return outer.has_point(inner.position) and outer.has_point(inner.end - Vector2(0.1, 0.1))
