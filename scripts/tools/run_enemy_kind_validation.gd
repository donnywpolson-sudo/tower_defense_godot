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
	_check_baseline_enemy_kinds(game, result)
	_check_shield_absorption(game, result)
	_check_flying_targeting_from_baseline_enemy(game, result)

	if result["ok"]:
		print("ENEMY_KIND_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("ENEMY_KIND_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)


func _check_baseline_enemy_kinds(game: Node, result: Dictionary) -> void:
	var expected: Dictionary = {
		"normal": {"hp": 83.0, "speed": 64.0, "reward": 4, "shield_hits": 0, "flying": false, "commander": false},
		"fast": {"hp": 53.95, "speed": 105.6, "reward": 5, "shield_hits": 0, "flying": false, "commander": false},
		"tank": {"hp": 182.6, "speed": 39.68, "reward": 8, "shield_hits": 0, "flying": false, "commander": false},
		"swarm": {"hp": 37.35, "speed": 73.6, "reward": 4, "shield_hits": 0, "flying": false, "commander": false},
		"shield": {"hp": 99.6, "speed": 57.6, "reward": 7, "shield_hits": 2, "flying": false, "commander": false},
		"flying": {"hp": 74.7, "speed": 86.4, "reward": 8, "shield_hits": 0, "flying": true, "commander": false},
		"armored": {"hp": 112.05, "speed": 54.4, "reward": 8, "shield_hits": 3, "flying": false, "commander": false},
		"commander": {"hp": 215.8, "speed": 55.04, "reward": 22, "shield_hits": 1, "flying": false, "commander": true},
	}
	for kind in expected:
		var enemy: Dictionary = game.make_baseline_enemy_for_test(kind, 1)
		var want: Dictionary = expected[kind]
		_record_check(result, "%s_kind" % kind, enemy["kind"] == kind, enemy)
		_record_check(result, "%s_hp" % kind, is_equal_approx(float(enemy["hp"]), float(want["hp"])), enemy)
		_record_check(result, "%s_speed" % kind, is_equal_approx(float(enemy["speed"]), float(want["speed"])), enemy)
		_record_check(result, "%s_reward" % kind, int(enemy["reward"]) == int(want["reward"]), enemy)
		_record_check(result, "%s_shield_hits" % kind, int(enemy["shield_hits"]) == int(want["shield_hits"]), enemy)
		_record_check(result, "%s_flying" % kind, bool(enemy["flying"]) == bool(want["flying"]), enemy)
		_record_check(result, "%s_commander" % kind, bool(enemy["commander"]) == bool(want["commander"]), enemy)


func _check_shield_absorption(game: Node, result: Dictionary) -> void:
	var tower: Dictionary = game.make_test_tower("first", "archer", 2)
	tower["damage"] = 39.0
	var shielded: Dictionary = game.make_baseline_enemy_for_test("shield", 1)
	game.enemies = [shielded]
	var projectile: Dictionary = game.make_test_projectile(tower, shielded, shielded["position"])
	game.update_projectile_for_test(projectile, 0.01)
	_record_check(result, "shield_hit_consumes_layer", int(shielded["shield_hits"]) == 1, shielded)
	_record_check(result, "shield_hit_preserves_hp", is_equal_approx(float(shielded["hp"]), float(shielded["max_hp"])), shielded)
	_record_check(result, "shield_hit_does_not_credit_hp_damage", float(tower.get("total_damage", 0.0)) == 0.0, tower)

	var second_projectile: Dictionary = game.make_test_projectile(tower, shielded, shielded["position"])
	game.update_projectile_for_test(second_projectile, 0.01)
	var third_projectile: Dictionary = game.make_test_projectile(tower, shielded, shielded["position"])
	game.update_projectile_for_test(third_projectile, 0.01)
	_record_check(result, "damage_after_shields_drop", is_equal_approx(float(shielded["hp"]), float(shielded["max_hp"]) - 39.0), shielded)
	_record_check(result, "tower_damage_credit_after_shields_drop", is_equal_approx(float(tower.get("total_damage", 0.0)), 39.0), tower)


func _check_flying_targeting_from_baseline_enemy(game: Node, result: Dictionary) -> void:
	var flying: Dictionary = game.make_baseline_enemy_for_test("flying", 1)
	flying["id"] = "baseline_flying"
	var normal: Dictionary = game.make_baseline_enemy_for_test("normal", 1)
	normal["id"] = "baseline_normal"
	normal["position"] = Vector2(170, 100)
	normal["progress"] = 80.0
	flying["position"] = Vector2(150, 100)
	flying["progress"] = 40.0
	game.enemies = [flying, normal]
	_record_check(result, "tesla_targets_baseline_flying", str(game.find_target_for_test(game.make_test_tower("flying", "tesla", 4)).get("id", "")) == "baseline_flying", game.enemies)
	_record_check(result, "archer_ignores_baseline_flying", str(game.find_target_for_test(game.make_test_tower("flying", "archer", 2)).get("id", "")) == "baseline_normal", game.enemies)


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	var stored_detail: Variant = detail
	if detail is Dictionary or detail is Array:
		stored_detail = detail.duplicate(true)
	result["checks"].append({
		"label": label,
		"passed": passed,
		"detail": stored_detail,
	})
	if not passed:
		result["ok"] = false
		result["errors"].append("%s failed: %s" % [label, str(stored_detail)])
