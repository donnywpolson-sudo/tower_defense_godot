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
	_record_check(result, "frost_speed", game.projectile_speed_for_test(game.make_test_tower("first", "frost", 2)) == 360.0, game.projectile_speed_for_test(game.make_test_tower("first", "frost", 2)))

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

	var frost_tower: Dictionary = game.make_test_tower("first", "frost", 2)
	frost_tower["damage"] = 27.0
	var frost_target: Dictionary = game.make_test_enemy("frost_target", Vector2(200, 100), 0.0, 83.0)
	game.enemies = [frost_target]
	var frost_projectile: Dictionary = game.make_test_projectile(frost_tower, frost_target, Vector2(193, 100))
	game.update_projectile_for_test(frost_projectile, 0.02)
	_record_check(result, "frost_projectile_hits", frost_projectile["dead"] == true, {"position": frost_projectile["position"], "dead": frost_projectile["dead"]})
	_record_check(result, "frost_applies_damage", frost_target["hp"] == 56.0, {"hp": frost_target["hp"], "expected": 56.0})
	var frost_state_after_hit := {"slow_timer": frost_target.get("slow_timer", 0.0), "slow_multiplier": frost_target.get("slow_multiplier", 1.0)}
	_record_check(result, "frost_applies_slow_timer", is_equal_approx(float(frost_state_after_hit["slow_timer"]), 1.55), frost_state_after_hit)
	_record_check(result, "frost_level_two_slow_multiplier", is_equal_approx(float(frost_state_after_hit["slow_multiplier"]), 0.72), frost_state_after_hit)
	frost_target["speed"] = 62.0
	var before_position: Vector2 = frost_target["position"]
	game.update_enemy_for_test(frost_target, 0.50)
	var slowed_distance: float = before_position.distance_to(frost_target["position"])
	_record_check(result, "frost_slow_reduces_enemy_movement", slowed_distance > 0.0 and slowed_distance < 31.0, {"slowed_distance": slowed_distance, "slow_timer": frost_target.get("slow_timer", 0.0)})
	game.update_enemy_for_test(frost_target, 2.0)
	_record_check(result, "frost_slow_expires_cleanly", is_equal_approx(float(frost_target.get("slow_timer", 0.0)), 0.0) and is_equal_approx(float(frost_target.get("slow_multiplier", 1.0)), 1.0), {"slow_timer": frost_target.get("slow_timer", 0.0), "slow_multiplier": frost_target.get("slow_multiplier", 1.0)})
	var level_one_frost: Dictionary = game.make_test_tower("first", "frost", 1)
	level_one_frost["damage"] = 0.0
	var reapply_projectile: Dictionary = game.make_test_projectile(level_one_frost, frost_target, frost_target["position"] + Vector2(-7, 0))
	game.update_projectile_for_test(reapply_projectile, 0.02)
	_record_check(result, "frost_reapply_after_expiry_uses_new_level", is_equal_approx(float(frost_target.get("slow_multiplier", 1.0)), 0.76), {"slow_timer": frost_target.get("slow_timer", 0.0), "slow_multiplier": frost_target.get("slow_multiplier", 1.0)})


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	result["checks"].append({
		"label": label,
		"passed": passed,
		"detail": detail,
	})
	if not passed:
		result["ok"] = false
		result["errors"].append("%s failed: %s" % [label, str(detail)])
