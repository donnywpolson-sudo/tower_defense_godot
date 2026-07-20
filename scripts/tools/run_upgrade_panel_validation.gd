extends SceneTree

const VALIDATION_HARNESS = preload("res://scripts/tools/validation_harness.gd")


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

	var result: Dictionary = VALIDATION_HARNESS.new_result()
	_check_upgrade_panel(game, result)
	_check_supported_branch_runtime(game, result)

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
	_record_check(result, "panel_details_show_supported_upgrade_limit", str(panel["details"]).contains("Upgrades through L2") and not str(panel["details"]).contains("Branch"), panel)
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
	_record_check(result, "unfinished_archer_branches_fail_closed", panel["needs_branch_choice"] == false and panel["branch_options"].is_empty() and panel["upgrade_options"].size() == 1 and not bool(panel["upgrade_options"][0]["enabled"]) and str(panel["upgrade_options"][0]["disabled_reason"]).contains("not implemented"), panel)

	var target_rect: Rect2 = game.get_target_button_rect()
	_record_check(result, "target_click_handled", game.handle_upgrade_panel_click(target_rect.position + target_rect.size * 0.5), game.upgrade_panel_snapshot())
	var after_target: Dictionary = game.upgrade_panel_snapshot()
	_record_check(result, "target_click_cycles_mode", after_target["target_mode"] == "last", after_target)

	var sell_rect: Rect2 = game.get_sell_button_rect()
	_record_check(result, "sell_click_handled", game.handle_upgrade_panel_click(sell_rect.position + sell_rect.size * 0.5), game.snapshot())
	var after_sell: Dictionary = game.snapshot()
	_record_check(result, "sell_removes_selected_tower", after_sell["tower_count"] == 0, after_sell)
	_record_check(result, "sell_adds_refund", after_sell["money"] == starting_money - 50 - 60 + 82, after_sell)
	_record_check(result, "panel_hidden_after_sell", game.upgrade_panel_snapshot()["visible"] == false, game.upgrade_panel_snapshot())
	game.clear_layout_viewport_override_for_tests()


func _check_supported_branch_runtime(game: Node, result: Dictionary) -> void:
	game.reset_slice()
	game.money = 1000
	_record_check(result, "place_supported_cannon", game.place_selected_tower(game.RECOMMENDED_BUILD_SITE, "cannon"), game.snapshot())
	game.selected_tower_index = 0
	_record_check(result, "supported_cannon_upgrade_l2", game.upgrade_selected_tower(), game.towers[0])
	var panel: Dictionary = game.upgrade_panel_snapshot()
	var branch_ids: Array = panel.get("branch_options", []).map(func(option): return str(option.get("id", "")))
	branch_ids.sort()
	_record_check(result, "only_supported_cannon_branches_visible", branch_ids == ["artillery", "demolition"], branch_ids)
	_record_check(result, "unsupported_cannon_branch_rejected", not game.choose_selected_tower_branch("terraformer"), game.latest_feedback)
	_record_check(result, "select_demolition_branch", game.choose_selected_tower_branch("demolition"), game.upgrade_panel_snapshot())
	_record_check(result, "supported_cannon_upgrade_l3", game.upgrade_selected_tower(), game.towers[0])
	var enemy: Dictionary = game.make_test_enemy("breach", Vector2(100, 100), 0.0)
	game._apply_cannon_branch_effect(enemy, game.towers[0], "cannon", 3)
	_record_check(result, "demolition_branch_has_runtime_effect", int(enemy.get("breach_stacks", 0)) == 1 and int(enemy.get("breach_source_tower_id", -1)) == int(game.towers[0].get("tower_id", -2)), enemy)


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	VALIDATION_HARNESS.record_check(result, label, passed, detail)


func _has_damage_range_fire_stats(panel: Dictionary) -> bool:
	var stats: Dictionary = panel.get("stat_detail", {})
	if int(stats.get("damage", 0)) != 36 or int(stats.get("range", 0)) != 151:
		return false
	if str(stats.get("shooting_speed_label", "")) != "2.0/s":
		return false
	return stats.has("damage_rating") and stats.has("range_rating") and stats.has("shooting_speed_rating")


func _rect_inside(inner: Rect2, outer: Rect2) -> bool:
	return outer.has_point(inner.position) and outer.has_point(inner.end - Vector2(0.1, 0.1))
