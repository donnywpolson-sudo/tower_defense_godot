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
	_check_projectile_logic(game, result)

	if result["ok"]:
		print("PROJECTILE_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("PROJECTILE_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)


func _check_projectile_logic(game: Node, result: Dictionary) -> void:
	_record_check(result, "archer_speed", game.projectile_speed_for_test(game.make_test_tower("first", "archer", 2)) == 420.0, game.projectile_speed_for_test(game.make_test_tower("first", "archer", 2)))
	_record_check(result, "sniper_speed", game.projectile_speed_for_test(game.make_test_tower("first", "sniper", 3)) == 760.0, game.projectile_speed_for_test(game.make_test_tower("first", "sniper", 3)))
	_record_check(result, "machine_gun_speed", game.projectile_speed_for_test(game.make_test_tower("first", "machine_gun", 2)) == 760.0, game.projectile_speed_for_test(game.make_test_tower("first", "machine_gun", 2)))
	_record_check(result, "tesla_speed", game.projectile_speed_for_test(game.make_test_tower("first", "tesla", 4)) == 760.0, game.projectile_speed_for_test(game.make_test_tower("first", "tesla", 4)))
	_record_check(result, "mortar_speed", game.projectile_speed_for_test(game.make_test_tower("first", "mortar", 2)) == 300.0, game.projectile_speed_for_test(game.make_test_tower("first", "mortar", 2)))

	var tower: Dictionary = game.make_test_tower("first", "archer", 2)
	tower["damage"] = 39.0
	var target: Dictionary = game.make_test_enemy("target", Vector2(200, 100), 0.0, 83.0)
	game.enemies = [target]
	var projectile: Dictionary = game.make_test_projectile(tower, target, Vector2(100, 100))
	game.update_projectile_for_test(projectile, 0.10)
	_record_check(
		result,
		"projectile_moves_toward_target",
		projectile["position"].x > 100.0 and projectile["position"].x < 200.0 and not projectile["dead"],
		{"position": projectile["position"], "dead": projectile["dead"]}
	)

	projectile["position"] = Vector2(193, 100)
	game.update_projectile_for_test(projectile, 0.02)
	_record_check(result, "projectile_hits_under_8_px", projectile["dead"] == true, {"position": projectile["position"], "dead": projectile["dead"]})
	_record_check(result, "projectile_applies_damage", target["hp"] == 44.0, {"hp": target["hp"], "expected": 44.0})
	_record_check(result, "tower_damage_credit", tower["total_damage"] == 39.0, {"total_damage": tower["total_damage"], "mastery_xp": tower["mastery_xp"]})

	var stale_target: Dictionary = game.make_test_enemy("stale", Vector2(160, 100), 0.0, 20.0)
	var stale_projectile: Dictionary = game.make_test_projectile(tower, stale_target, Vector2(100, 100))
	game.enemies = []
	game.update_projectile_for_test(stale_projectile, 0.05)
	_record_check(result, "stale_target_projectile_dies", stale_projectile["dead"] == true, {"dead": stale_projectile["dead"]})


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	result["checks"].append({
		"label": label,
		"passed": passed,
		"detail": detail,
	})
	if not passed:
		result["ok"] = false
		result["errors"].append("%s failed: %s" % [label, str(detail)])
