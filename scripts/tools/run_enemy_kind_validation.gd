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
	_check_game_data_enemy_kinds(game, result)
	_check_shield_absorption(game, result)
	_check_flying_targeting_from_game_data_enemy(game, result)
	_check_wave_modifier_application(game, result)

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


func _check_game_data_enemy_kinds(game: Node, result: Dictionary) -> void:
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
		var enemy: Dictionary = game.make_game_data_enemy_for_test(kind, 1)
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
	var shielded: Dictionary = game.make_game_data_enemy_for_test("shield", 1)
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


func _check_flying_targeting_from_game_data_enemy(game: Node, result: Dictionary) -> void:
	var flying: Dictionary = game.make_game_data_enemy_for_test("flying", 1)
	flying["id"] = "game_data_flying"
	var normal: Dictionary = game.make_game_data_enemy_for_test("normal", 1)
	normal["id"] = "game_data_normal"
	normal["position"] = Vector2(170, 100)
	normal["progress"] = 80.0
	flying["position"] = Vector2(150, 100)
	flying["progress"] = 40.0
	game.enemies = [flying, normal]
	_record_check(result, "tesla_targets_game_data_flying", str(game.find_target_for_test(game.make_test_tower("flying", "tesla", 4)).get("id", "")) == "game_data_flying", game.enemies)
	_record_check(result, "archer_ignores_game_data_flying", str(game.find_target_for_test(game.make_test_tower("flying", "archer", 2)).get("id", "")) == "game_data_normal", game.enemies)


func _check_wave_modifier_application(game: Node, result: Dictionary) -> void:
	game.set_wave_for_test(8)
	var encrypted: Dictionary = game.create_enemy("normal", 8, Vector2(180, 100), 1)
	_record_check(result, "armored_modifier_adds_shield", int(encrypted["shield_hits"]) == 1 and int(encrypted["max_shield_hits"]) == 1, encrypted)
	_record_check(result, "armored_modifier_reduces_damage_taken", is_equal_approx(float(encrypted["damage_taken_multiplier"]), 0.8), encrypted)

	game.set_wave_for_test(11)
	var haste_enemy: Dictionary = game.create_enemy("fast", 11, Vector2(180, 100), 1)
	var no_haste_speed: float = (62.0 + 11.0 * 2.0) * 1.65
	_record_check(result, "haste_modifier_increases_speed", is_equal_approx(float(haste_enemy["speed"]), no_haste_speed * 1.22), haste_enemy)

	game.set_wave_for_test(12)
	var regen_enemy: Dictionary = game.create_enemy("swarm", 12, Vector2(180, 100), 1)
	regen_enemy["hp"] = float(regen_enemy["max_hp"]) * 0.5
	game.enemies = [regen_enemy]
	game.process_step(1.0)
	_record_check(result, "regen_modifier_restores_hp", float(regen_enemy["hp"]) > float(regen_enemy["max_hp"]) * 0.5, regen_enemy)

	game.set_wave_for_test(9)
	var split_enemy: Dictionary = game.create_enemy("swarm", 9, Vector2(180, 100), 1)
	split_enemy["hp"] = 0.0
	game.enemies = [split_enemy]
	game.process_step(0.01)
	_record_check(result, "split_modifier_spawns_child", game.enemies.size() == 1 and int(game.enemies[0].get("death_spawns", -1)) == 0 and int(game.enemies[0].get("reward", -1)) == 0, game.enemies)

	game.set_wave_for_test(21)
	var volatile_source: Dictionary = game.create_enemy("armored", 21, Vector2(180, 100), 1)
	var volatile_neighbor: Dictionary = game.create_enemy("armored", 21, Vector2(190, 100), 1)
	var neighbor_hp: float = float(volatile_neighbor["hp"])
	volatile_source["hp"] = 0.0
	game.enemies = [volatile_source, volatile_neighbor]
	game.process_step(0.01)
	_record_check(result, "volatile_modifier_damages_nearby_enemy", float(volatile_neighbor["hp"]) < neighbor_hp, volatile_neighbor)


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
