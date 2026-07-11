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
	_check_shop_flow(game, result)

	if result["ok"]:
		print("SHOP_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("SHOP_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)


func _check_shop_flow(game: Node, result: Dictionary) -> void:
	var shop: Dictionary = game.shop_snapshot()
	_record_check(result, "shop_starts_unselected", shop["selected_build_type"] == "", shop)
	_record_check(result, "speed_controls_start_normal", shop["speed_control"]["label"] == "1x" and shop["speed_control"]["buttons"].size() == 4, shop["speed_control"])
	var expected_order: Array = _expected_root_shop_order(game)
	var supported: Array = ["archer", "machine_gun", "cannon", "frost", "sniper", "tesla"]
	var unsupported: Array = ["poison", "support", "barracks"]
	_record_check(result, "shop_exposes_game_data_root_roster", shop["button_count"] == expected_order.size() and _button_order(shop["buttons"]) == expected_order, shop)
	_record_check(result, "shop_keeps_canonical_shop_order_reference", shop["canonical_shop_order"] == game.game_data.get("towers", {}).get("shop_order", []), shop)
	_check_shop_layout(game, result)
	_check_bottom_dock_layout(game, result)

	for tower_type in expected_order:
		var button: Dictionary = _button_by_type(shop["buttons"], tower_type)
		var expected_cost: int = int(game.game_data.get("towers", {}).get("shop_costs", {}).get(tower_type, -1))
		_record_check(result, "%s_button_present" % tower_type, not button.is_empty(), {"tower_type": tower_type, "shop": shop})
		_record_check(result, "%s_cost_matches_game_data" % tower_type, int(button.get("cost", -1)) == expected_cost, button)
		_record_check(result, "%s_has_clean_shop_label" % tower_type, str(button.get("short_label", "")) == _expected_shop_label(tower_type), button)
		_record_check(result, "%s_enabled_state" % tower_type, bool(button.get("enabled", false)) == supported.has(tower_type), button)
		var expected_visual_state := "affordable" if supported.has(tower_type) else "unavailable"
		_record_check(result, "%s_visual_state" % tower_type, str(button.get("visual_state", "")) == expected_visual_state, button)

	for tower_type in supported:
		_check_supported_tower_flow(game, result, tower_type)

	for tower_type in unsupported:
		_check_unsupported_tower_flow(game, result, tower_type)

	_check_grid_placement_flow(game, result)
	_check_repeat_placement_flow(game, result)
	_check_cancel_and_status_flow(game, result)

	game.reset_slice()
	_record_check(result, "wave_starts_after_non_archer_shop_placement", _place_tower_from_shop(game, "machine_gun") and game.start_wave(), game.snapshot())


func _check_shop_layout(game: Node, result: Dictionary) -> void:
	var control_rects: Array = [game.get_start_wave_button_rect()]
	for speed_button in game.get_speed_button_rects():
		control_rects.append(speed_button["rect"])

	var overlaps: Array = []
	for button in game.get_shop_button_rects():
		var button_rect: Rect2 = button["rect"]
		for control_rect in control_rects:
			if _rects_overlap(button_rect, control_rect):
				overlaps.append({
					"tower_type": str(button.get("tower_type", "")),
					"button_rect": button_rect,
					"control_rect": control_rect,
				})
	_record_check(result, "shop_buttons_do_not_overlap_wave_or_speed_controls", overlaps.is_empty(), overlaps)


func _check_bottom_dock_layout(game: Node, result: Dictionary) -> void:
	game.set_layout_viewport_override_for_tests(Vector2(1180, 820))
	game.reset_slice()
	var layout: Dictionary = game.layout_snapshot()
	var dock_rect: Rect2 = layout["dock_rect"]
	var build_panel: Rect2 = layout["build_panel_rect"]
	var wave_panel: Rect2 = layout["wave_panel_rect"]
	var detail_panel: Rect2 = layout["detail_panel_rect"]
	_record_check(result, "bottom_layout_activates_for_tall_viewport", str(layout["mode"]) == "bottom_dock" and is_equal_approx(float(layout["map_scale"]), 1.0533333), layout)
	_record_check(result, "bottom_layout_has_three_dock_panels", _rect_inside(build_panel, dock_rect) and _rect_inside(wave_panel, dock_rect) and _rect_inside(detail_panel, dock_rect), layout)

	var buttons: Array = game.get_shop_button_rects()
	var buttons_inside_build_panel := true
	for button in buttons:
		buttons_inside_build_panel = buttons_inside_build_panel and _rect_inside(button["rect"], build_panel)
	_record_check(result, "bottom_shop_buttons_inside_build_panel", buttons_inside_build_panel, buttons)
	_record_check(result, "bottom_shop_uses_four_column_grid", buttons.size() >= 5 and is_equal_approx(buttons[0]["rect"].position.x, buttons[4]["rect"].position.x) and buttons[4]["rect"].position.y > buttons[0]["rect"].position.y, buttons)

	var control_rects: Array = [game.get_start_wave_button_rect()]
	for speed_button in game.get_speed_button_rects():
		control_rects.append(speed_button["rect"])
	var overlaps: Array = []
	for button in buttons:
		var button_rect: Rect2 = button["rect"]
		for control_rect in control_rects:
			if _rects_overlap(button_rect, control_rect):
				overlaps.append({"button_rect": button_rect, "control_rect": control_rect})
	_record_check(result, "bottom_shop_buttons_do_not_overlap_wave_or_speed_controls", overlaps.is_empty(), overlaps)

	game.money = 1000
	var selected: bool = _click_shop_button(game, "archer")
	var dock_click_handled: bool = game.handle_map_click(dock_rect.position + Vector2(6, 6))
	_record_check(result, "bottom_dock_click_does_not_place_tower", selected and dock_click_handled == false and game.snapshot()["tower_count"] == 0, game.snapshot())
	var screen_site: Vector2 = game.map_to_screen_position(game.RECOMMENDED_BUILD_SITE)
	var placed: bool = game.handle_map_click(screen_site)
	var run_state: Dictionary = game.serialize_run_state()
	var towers: Array = run_state.get("towers", [])
	var stored_position: Array = towers[0].get("position", []) if towers.size() == 1 else []
	var grid_step: float = float(game.config.get("build_grid_step", 27))
	var expected_site := Vector2(round(game.RECOMMENDED_BUILD_SITE.x / grid_step) * grid_step, round(game.RECOMMENDED_BUILD_SITE.y / grid_step) * grid_step)
	_record_check(result, "bottom_map_click_converts_to_game_data_site", placed and stored_position.size() == 2 and is_equal_approx(float(stored_position[0]), expected_site.x) and is_equal_approx(float(stored_position[1]), expected_site.y), {"screen_site": screen_site, "run_state": run_state, "expected_site": expected_site})
	game.clear_layout_viewport_override_for_tests()
	game.reset_slice()


func _check_supported_tower_flow(game: Node, result: Dictionary, tower_type: String) -> void:
	game.reset_slice()
	var starting_money: int = game.snapshot()["money"]
	var expected_cost: int = int(game.game_data.get("towers", {}).get("shop_costs", {}).get(tower_type, -1))
	var placed: bool = _place_tower_from_shop(game, tower_type)
	var after_place: Dictionary = game.snapshot()
	_record_check(result, "%s_places_from_shop" % tower_type, placed, after_place)
	_record_check(result, "%s_spends_game_data_cost" % tower_type, after_place["money"] == starting_money - expected_cost, after_place)
	_record_check(result, "%s_keeps_selection_after_placement" % tower_type, after_place["selected_build_type"] == tower_type, after_place)
	_record_check(result, "%s_adds_matching_tower" % tower_type, after_place["tower_count"] == 1 and after_place["tower_family"] == tower_type, after_place)

	game.reset_slice()
	game.money = expected_cost - 1
	var unaffordable_button: Dictionary = _button_by_type(game.shop_snapshot()["buttons"], tower_type)
	_record_check(result, "%s_unaffordable_visual_state" % tower_type, str(unaffordable_button.get("visual_state", "")) == "unaffordable", unaffordable_button)
	var selected: bool = _click_shop_button(game, tower_type)
	var selected_button: Dictionary = _button_by_type(game.shop_snapshot()["buttons"], tower_type)
	var unaffordable_preview: Dictionary = game.placement_preview_snapshot(game.RECOMMENDED_BUILD_SITE)
	var blocked: bool = game.handle_map_click(game.RECOMMENDED_BUILD_SITE)
	var after_blocked: Dictionary = game.snapshot()
	_record_check(result, "%s_can_select_when_unaffordable" % tower_type, selected and after_blocked["selected_build_type"] == tower_type, after_blocked)
	_record_check(result, "%s_selected_visual_state" % tower_type, str(selected_button.get("visual_state", "")) == "selected", selected_button)
	_record_check(result, "%s_unaffordable_preview_has_reason" % tower_type, bool(unaffordable_preview.get("can_place", true)) == false and str(unaffordable_preview.get("disabled_reason", "")).contains("$"), unaffordable_preview)
	_record_check(result, "%s_blocks_unaffordable_placement" % tower_type, blocked == false and after_blocked["tower_count"] == 0 and after_blocked["money"] == expected_cost - 1, after_blocked)


func _check_unsupported_tower_flow(game: Node, result: Dictionary, tower_type: String) -> void:
	game.reset_slice()
	var starting_money: int = game.snapshot()["money"]
	var button: Dictionary = _button_by_type(game.shop_snapshot()["buttons"], tower_type)
	var clicked: bool = _click_shop_button(game, tower_type)
	var placed: bool = game.handle_map_click(game.RECOMMENDED_BUILD_SITE)
	var snapshot: Dictionary = game.snapshot()
	_record_check(result, "%s_is_visible_disabled" % tower_type, not button.is_empty() and button["enabled"] == false and not str(button.get("disabled_reason", "")).is_empty(), button)
	_record_check(result, "%s_disabled_click_is_handled" % tower_type, clicked, snapshot)
	_record_check(result, "%s_disabled_click_does_not_select" % tower_type, snapshot["selected_build_type"] == "", snapshot)
	_record_check(result, "%s_disabled_does_not_place" % tower_type, placed == false and snapshot["tower_count"] == 0 and snapshot["money"] == starting_money, snapshot)


func _check_grid_placement_flow(game: Node, result: Dictionary) -> void:
	game.reset_slice()
	var off_grid_site := Vector2(301, 244)
	var grid_step: float = float(game.config.get("build_grid_step", 27))
	var expected_site := Vector2(round(off_grid_site.x / grid_step) * grid_step, round(off_grid_site.y / grid_step) * grid_step)
	var clicked: bool = _click_shop_button(game, "archer")
	var off_map_preview: Dictionary = game.placement_preview_snapshot(Vector2(-32, -32))
	var path_blocked_site := Vector2(189, 297)
	var path_blocked_preview: Dictionary = game.placement_preview_snapshot(path_blocked_site)
	var placed: bool = game.handle_map_click(off_grid_site)
	var run_state: Dictionary = game.serialize_run_state()
	var towers: Array = run_state.get("towers", [])
	var stored_position: Array = towers[0].get("position", []) if towers.size() == 1 else []
	var snapped: bool = stored_position.size() == 2 and is_equal_approx(float(stored_position[0]), expected_site.x) and is_equal_approx(float(stored_position[1]), expected_site.y)
	_record_check(result, "off_map_preview_has_reason", clicked and bool(off_map_preview.get("can_place", true)) == false and not str(off_map_preview.get("disabled_reason", "")).is_empty(), off_map_preview)
	_record_check(result, "path_blocked_preview_has_reason", clicked and bool(path_blocked_preview.get("can_place", true)) == false and str(path_blocked_preview.get("disabled_reason", "")) == "Blocked by path", path_blocked_preview)
	_record_check(result, "off_grid_tower_click_places", clicked and placed and towers.size() == 1, {"run_state": run_state, "expected_site": expected_site})
	_record_check(result, "off_grid_tower_click_snaps_to_grid", snapped, {"stored_position": stored_position, "expected_site": expected_site, "grid_step": grid_step})


func _check_repeat_placement_flow(game: Node, result: Dictionary) -> void:
	game.reset_slice()
	game.money = 1000
	var selected: bool = _click_shop_button(game, "archer")
	var first_placed: bool = _place_next_valid_from_build(game)
	var after_first: Dictionary = game.snapshot()
	var occupied_preview: Dictionary = {}
	var run_state: Dictionary = game.serialize_run_state()
	var towers: Array = run_state.get("towers", [])
	if towers.size() > 0:
		var position: Array = towers[0].get("position", [])
		if position.size() == 2:
			occupied_preview = game.placement_preview_snapshot(Vector2(float(position[0]), float(position[1])))
	var second_placed: bool = _place_next_valid_from_build(game)
	var after_second: Dictionary = game.snapshot()
	var canceled: bool = _right_click_cancel(game)
	var after_cancel: Dictionary = game.snapshot()
	_record_check(result, "repeat_build_keeps_archer_after_first_place", selected and first_placed and after_first["selected_build_type"] == "archer", after_first)
	_record_check(result, "occupied_preview_has_reason", bool(occupied_preview.get("can_place", true)) == false and not str(occupied_preview.get("disabled_reason", "")).is_empty(), occupied_preview)
	_record_check(result, "repeat_build_places_second_without_reselect", second_placed and after_second["tower_count"] == 2 and after_second["selected_build_type"] == "archer", after_second)
	_record_check(result, "repeat_build_right_click_exits_build_mode", canceled and after_cancel["selected_build_type"] == "", after_cancel)


func _check_cancel_and_status_flow(game: Node, result: Dictionary) -> void:
	game.reset_slice()
	var selected: bool = _click_shop_button(game, "machine_gun")
	var status: Dictionary = game.status_snapshot()
	_record_check(result, "selected_build_not_in_run_status", selected and not str(status.get("gameplay", "")).contains("Gunner"), status)
	var canceled: bool = _right_click_cancel(game)
	var snapshot: Dictionary = game.snapshot()
	_record_check(result, "right_click_cancels_build_selection", canceled and snapshot["selected_build_type"] == "", snapshot)
	_record_check(result, "canceled_selection_does_not_place", game.handle_map_click(game.RECOMMENDED_BUILD_SITE) == false and game.snapshot()["tower_count"] == 0, game.snapshot())


func _place_tower_from_shop(game: Node, tower_type: String) -> bool:
	if not _click_shop_button(game, tower_type):
		return false
	return game.handle_map_click(game.RECOMMENDED_BUILD_SITE)


func _place_next_valid_from_build(game: Node) -> bool:
	for y in range(108, 570, 27):
		for x in range(54, 864, 27):
			var site := Vector2(float(x), float(y))
			if game.can_place_tower(site):
				return game.handle_map_click(site)
	return false


func _click_shop_button(game: Node, tower_type: String) -> bool:
	for button in game.get_shop_button_rects():
		if str(button["tower_type"]) == tower_type:
			var rect: Rect2 = button["rect"]
			return game.handle_shop_click(rect.get_center())
	return false


func _right_click_cancel(game: Node) -> bool:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	game._unhandled_input(event)
	return game.snapshot()["selected_build_type"] == ""


func _expected_root_shop_order(game: Node) -> Array:
	var root_ids: Array = game.game_data.get("towers", {}).get("root_tower_ids", [])
	var shop_order: Array = game.game_data.get("towers", {}).get("shop_order", [])
	var expected: Array = []
	for tower_id in root_ids:
		if str(tower_id) == "archer":
			expected.append("archer")
	for tower_id in shop_order:
		var tower_type := str(tower_id)
		if root_ids.has(tower_type) and not expected.has(tower_type):
			expected.append(tower_type)
	for tower_id in root_ids:
		var tower_type := str(tower_id)
		if not expected.has(tower_type):
			expected.append(tower_type)
	return expected


func _button_order(buttons: Array) -> Array:
	var order: Array = []
	for button in buttons:
		order.append(str(button["tower_type"]))
	return order


func _button_by_type(buttons: Array, tower_type: String) -> Dictionary:
	for button in buttons:
		if str(button["tower_type"]) == tower_type:
			return button
	return {}


func _expected_shop_label(tower_type: String) -> String:
	var labels := {
		"archer": "Archer",
		"machine_gun": "Gunner",
		"cannon": "Cannon",
		"frost": "Frost",
		"poison": "Venom",
		"support": "Support",
		"sniper": "Sniper",
		"tesla": "Tesla",
		"barracks": "Garrison",
	}
	return str(labels.get(tower_type, tower_type))


func _rects_overlap(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x and a.end.x > b.position.x and a.position.y < b.end.y and a.end.y > b.position.y


func _rect_inside(inner: Rect2, outer: Rect2) -> bool:
	return outer.has_point(inner.position) and outer.has_point(inner.end - Vector2(0.1, 0.1))


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	result["checks"].append({
		"label": label,
		"passed": passed,
		"detail": detail,
	})
	if not passed:
		result["ok"] = false
		result["errors"].append("%s failed: %s" % [label, str(detail)])
