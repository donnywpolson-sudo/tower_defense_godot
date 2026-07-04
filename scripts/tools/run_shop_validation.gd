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
	var starting_money: int = game.snapshot()["money"]
	var shop: Dictionary = game.shop_snapshot()
	_record_check(result, "shop_starts_unselected", shop["selected_build_type"] == "", shop)
	_record_check(result, "slice_shop_has_one_enabled_button", shop["button_count"] == 1, shop)

	var button: Dictionary = shop["buttons"][0]
	_record_check(result, "archer_button_present", button["tower_type"] == "archer", button)
	_record_check(result, "archer_button_cost_matches_baseline", button["cost"] == 50, button)
	_record_check(result, "archer_button_affordable", button["affordable"] == true, button)

	var rect: Rect2 = game.get_shop_button_rects()[0]["rect"]
	var handled: bool = game.handle_shop_click(rect.position + rect.size * 0.5)
	var after_select: Dictionary = game.snapshot()
	_record_check(result, "shop_click_handled", handled, after_select)
	_record_check(result, "shop_click_selects_archer", after_select["selected_build_type"] == "archer", after_select)
	_record_check(result, "shop_select_does_not_spend_money", after_select["money"] == starting_money, after_select)

	var placed: bool = game.handle_map_click(game.RECOMMENDED_BUILD_SITE)
	var after_place: Dictionary = game.snapshot()
	_record_check(result, "selected_tower_places_on_map", placed, after_place)
	_record_check(result, "placement_spends_archer_cost", after_place["money"] == starting_money - 50, after_place)
	_record_check(result, "placement_clears_selection", after_place["selected_build_type"] == "", after_place)
	_record_check(result, "placement_adds_one_tower", after_place["tower_count"] == 1, after_place)

	_record_check(result, "wave_starts_after_shop_placement", game.start_wave(), game.snapshot())


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	result["checks"].append({
		"label": label,
		"passed": passed,
		"detail": detail,
	})
	if not passed:
		result["ok"] = false
		result["errors"].append("%s failed: %s" % [label, str(detail)])
