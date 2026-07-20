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
	_check_target_modes(game, result)

	if result["ok"]:
		print("TARGETING_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("TARGETING_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)


func _check_target_modes(game: Node, result: Dictionary) -> void:
	var plain_deep: Dictionary = game.make_test_enemy("plain_deep", Vector2(170, 100), 90.0, 260.0)
	var plain_shallow: Dictionary = game.make_test_enemy("plain_shallow", Vector2(150, 100), 20.0, 50.0)
	var marked: Dictionary = game.make_test_enemy("marked", Vector2(150, 100), 40.0, 140.0, true)
	var vulnerable: Dictionary = game.make_test_enemy("vulnerable", Vector2(150, 100), 40.0, 140.0, false, true)
	var flying_marked: Dictionary = game.make_test_enemy("flying_marked", Vector2(150, 100), 50.0, 140.0, true, false, true)
	var flying_plain: Dictionary = game.make_test_enemy("flying_plain", Vector2(170, 100), 80.0, 140.0, false, false, true)

	game.enemies = [plain_shallow, plain_deep]
	_expect_target(result, "first_uses_progress", game.find_target_for_test(game.make_test_tower("first")), "plain_deep")
	_expect_target(result, "last_uses_progress", game.find_target_for_test(game.make_test_tower("last")), "plain_shallow")
	_expect_target(result, "strongest_uses_hp", game.find_target_for_test(game.make_test_tower("strongest")), "plain_deep")
	_expect_target(result, "weakest_uses_hp", game.find_target_for_test(game.make_test_tower("weakest")), "plain_shallow")
	_expect_target(result, "closest_fallback", game.find_target_for_test(game.make_test_tower("closest")), "plain_shallow")

	game.enemies = [marked, plain_deep]
	_expect_target(result, "first_prefers_marked", game.find_target_for_test(game.make_test_tower("first")), "marked")
	_expect_target(result, "last_prefers_marked", game.find_target_for_test(game.make_test_tower("last")), "marked")
	_expect_target(result, "strongest_prefers_marked", game.find_target_for_test(game.make_test_tower("strongest")), "marked")

	game.enemies = [vulnerable, plain_deep]
	_expect_target(result, "first_prefers_vulnerable", game.find_target_for_test(game.make_test_tower("first")), "vulnerable")

	game.enemies = [flying_marked, flying_plain, plain_deep]
	_expect_target(result, "flying_mode_prefers_marked_flying", game.find_target_for_test(game.make_test_tower("flying", "tesla", 4)), "flying_marked")
	_expect_target(result, "archer_cannot_attack_flying", game.find_target_for_test(game.make_test_tower("flying", "archer", 2)), "plain_deep")


func _expect_target(result: Dictionary, label: String, target: Dictionary, expected_id: String) -> void:
	var actual_id := str(target.get("id", ""))
	_record_check(result, label, actual_id == expected_id, {"expected": expected_id, "actual": actual_id})


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	ValidationHarness.record_check(result, label, passed, detail)
