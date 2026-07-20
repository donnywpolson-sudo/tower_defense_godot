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

	var result: Dictionary = {"ok": true, "checks": [], "errors": []}
	_check_demolition_branch(game, result)
	if result["ok"]:
		print("CANNON_DEMOLITION_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("CANNON_DEMOLITION_VALIDATION_FAILED")
		for error in result["errors"]:
			print("FAILED %s" % error)
			push_error(error)
		quit(1)


func _check_demolition_branch(game: Node, result: Dictionary) -> void:
	var t3: Dictionary = game.make_test_tower("first", "cannon", 3)
	t3["selected_branch"] = "demolition"
	t3["damage"] = 20.0
	var target: Dictionary = game.make_test_enemy("demolition_target", Vector2(200, 100), 0.0, 100.0)
	game.towers = [t3]
	game.enemies = [target]
	_hit(game, t3, target)
	_record_check(result, "t3_builds_breach_stack", int(target.get("breach_stacks", 0)) == 1, target)
	_record_check(result, "t3_does_not_add_vulnerability", is_equal_approx(float(target.get("breach_vulnerability_multiplier", 1.0)), 1.0), target)

	var t4: Dictionary = game.make_test_tower("first", "cannon", 4)
	t4["selected_branch"] = "demolition"
	t4["damage"] = 20.0
	var shielded: Dictionary = game.make_test_enemy("shielded_target", Vector2(200, 100), 0.0, 100.0)
	shielded["shield_hits"] = 2
	shielded["max_shield_hits"] = 2
	game.towers = [t4]
	game.enemies = [shielded]
	_hit(game, t4, shielded)
	_record_check(result, "t4_strips_shield_on_breach_hit", int(shielded.get("shield_hits", 0)) == 0, shielded)
	_record_check(result, "t4_shield_block_preserves_hp", is_equal_approx(float(shielded.get("hp", 0.0)), 100.0), shielded)

	var t5: Dictionary = game.make_test_tower("first", "cannon", 5)
	t5["selected_branch"] = "demolition"
	t5["damage"] = 20.0
	var exposed: Dictionary = game.make_test_enemy("exposed_target", Vector2(200, 100), 0.0, 100.0)
	game.towers = [t5]
	game.enemies = [exposed]
	_hit(game, t5, exposed)
	_record_check(result, "t5_applies_vulnerability_after_hit", is_equal_approx(float(exposed.get("breach_vulnerability_multiplier", 1.0)), 1.15), exposed)
	_hit(game, t5, exposed)
	_record_check(result, "t5_vulnerability_increases_follow_up_damage", is_equal_approx(float(exposed.get("hp", 0.0)), 57.0), exposed)
	game.update_enemy_for_test(exposed, 3.1)
	_record_check(result, "breach_expires_cleanly", int(exposed.get("breach_stacks", 0)) == 0 and is_equal_approx(float(exposed.get("breach_vulnerability_multiplier", 1.0)), 1.0), exposed)

	var persisted: Dictionary = game.make_game_data_enemy_for_test("armored", 1)
	persisted["breach_stacks"] = 2
	persisted["breach_timer"] = 2.5
	persisted["breach_vulnerability_multiplier"] = 1.15
	game.enemies = [persisted]
	var saved_state: Dictionary = game.serialize_run_state()
	var restored_ok: bool = game.restore_run_state(saved_state)
	var restored: Dictionary = game.enemies[0] if restored_ok and not game.enemies.is_empty() else {}
	_record_check(result, "breach_state_restores", restored_ok and int(restored.get("breach_stacks", 0)) == 2 and is_equal_approx(float(restored.get("breach_vulnerability_multiplier", 1.0)), 1.15), restored)

	var artillery: Dictionary = game.make_test_tower("first", "cannon", 3)
	artillery["selected_branch"] = "artillery"
	artillery["damage"] = 20.0
	var artillery_target: Dictionary = game.make_test_enemy("artillery_target", Vector2(200, 100), 0.0, 100.0)
	var artillery_near: Dictionary = game.make_test_enemy("artillery_near", Vector2(240, 100), 0.0, 100.0)
	var artillery_far: Dictionary = game.make_test_enemy("artillery_far", Vector2(310, 100), 0.0, 100.0)
	game.towers = [artillery]
	game.enemies = [artillery_target, artillery_near, artillery_far]
	_hit(game, artillery, artillery_target)
	_record_check(result, "artillery_t3_splashes_nearby_target", is_equal_approx(float(artillery_near.get("hp", 0.0)), 91.0), artillery_near)
	_record_check(result, "artillery_t3_respects_splash_radius", is_equal_approx(float(artillery_far.get("hp", 0.0)), 100.0), artillery_far)
	_record_check(result, "artillery_does_not_build_breach", int(artillery_near.get("breach_stacks", 0)) == 0, artillery_near)

	var artillery_t4: Dictionary = game.make_test_tower("first", "cannon", 4)
	artillery_t4["selected_branch"] = "artillery"
	artillery_t4["damage"] = 20.0
	var cluster_target: Dictionary = game.make_test_enemy("cluster_target", Vector2(200, 100), 0.0, 100.0)
	var cluster_near: Dictionary = game.make_test_enemy("cluster_near", Vector2(240, 100), 0.0, 100.0)
	var cluster_second: Dictionary = game.make_test_enemy("cluster_second", Vector2(200, 145), 0.0, 100.0)
	game.towers = [artillery_t4]
	game.enemies = [cluster_target, cluster_near, cluster_second]
	_hit(game, artillery_t4, cluster_target)
	_record_check(result, "artillery_t4_adds_cluster_target", is_equal_approx(float(cluster_near.get("hp", 0.0)), 91.0) and is_equal_approx(float(cluster_second.get("hp", 0.0)), 91.0), {"near": cluster_near, "second": cluster_second})


func _hit(game: Node, tower: Dictionary, target: Dictionary) -> void:
	var projectile: Dictionary = game.make_test_projectile(tower, target, Vector2(193, 100))
	game.update_projectile_for_test(projectile, 0.02)


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	ValidationHarness.record_check(result, label, passed, detail)
