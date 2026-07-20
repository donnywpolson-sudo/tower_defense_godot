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
	_record_check(result, "frost_level_two_slow_multiplier", is_equal_approx(float(frost_state_after_hit["slow_multiplier"]), 0.58), frost_state_after_hit)
	var frost_rehit_projectile: Dictionary = game.make_test_projectile(frost_tower, frost_target, frost_target["position"] + Vector2(-7, 0))
	game.update_projectile_for_test(frost_rehit_projectile, 0.02)
	_record_check(result, "frost_rehits_deepen_chill", is_equal_approx(float(frost_target.get("slow_multiplier", 1.0)), 0.54), {"slow_timer": frost_target.get("slow_timer", 0.0), "slow_multiplier": frost_target.get("slow_multiplier", 1.0)})
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
	_record_check(result, "frost_reapply_after_expiry_uses_new_level", is_equal_approx(float(frost_target.get("slow_multiplier", 1.0)), 0.62), {"slow_timer": frost_target.get("slow_timer", 0.0), "slow_multiplier": frost_target.get("slow_multiplier", 1.0)})

	var poison_tower: Dictionary = game.make_test_tower("first", "poison", 2)
	poison_tower["damage"] = 20.0
	var poison_target: Dictionary = game.make_test_enemy("poison_target", Vector2(200, 100), 0.0, 200.0)
	game.enemies = [poison_target]
	var poison_projectile: Dictionary = game.make_test_projectile(poison_tower, poison_target, Vector2(193, 100))
	game.update_projectile_for_test(poison_projectile, 0.02)
	_record_check(result, "poison_projectile_hits", poison_projectile["dead"] == true, {"dead": poison_projectile["dead"]})
	_record_check(result, "poison_applies_stack", int(poison_target.get("poison_stacks", 0)) == 1, poison_target)
	_record_check(result, "poison_applies_anti_regen", is_equal_approx(float(poison_target.get("poison_regen_multiplier", 1.0)), 0.5), poison_target)
	var poison_hp_after_hit: float = float(poison_target["hp"])
	game.update_enemy_for_test(poison_target, 0.5)
	_record_check(result, "poison_ticks_damage", float(poison_target["hp"]) < poison_hp_after_hit, {"before": poison_hp_after_hit, "after": poison_target["hp"]})
	game.update_enemy_for_test(poison_target, 3.1)
	_record_check(result, "poison_expires_cleanly", int(poison_target.get("poison_stacks", 0)) == 0 and is_equal_approx(float(poison_target.get("poison_regen_multiplier", 1.0)), 1.0), poison_target)

	var plague_tower: Dictionary = game.make_test_tower("first", "poison", 3)
	plague_tower["damage"] = 20.0
	plague_tower["selected_branch"] = "plague_mist"
	var plague_target: Dictionary = game.make_test_enemy("plague_target", Vector2(200, 100), 0.0, 200.0)
	var plague_near: Dictionary = game.make_test_enemy("plague_near", Vector2(240, 100), 0.0, 200.0)
	var plague_second: Dictionary = game.make_test_enemy("plague_second", Vector2(200, 145), 0.0, 200.0)
	var plague_far: Dictionary = game.make_test_enemy("plague_far", Vector2(300, 100), 0.0, 200.0)
	game.towers = [plague_tower]
	game.enemies = [plague_target, plague_near, plague_second, plague_far]
	var plague_projectile: Dictionary = game.make_test_projectile(plague_tower, plague_target, Vector2(193, 100))
	game.update_projectile_for_test(plague_projectile, 0.02)
	_record_check(result, "plague_mist_spreads_to_nearby_targets", int(plague_near.get("poison_stacks", 0)) == 1 and int(plague_second.get("poison_stacks", 0)) == 1, {"near": plague_near, "second": plague_second})
	_record_check(result, "plague_mist_respects_spread_radius", int(plague_far.get("poison_stacks", 0)) == 0, plague_far)

	var venom_tower: Dictionary = game.make_test_tower("first", "poison", 3)
	venom_tower["damage"] = 20.0
	venom_tower["selected_branch"] = "venom_cask"
	var venom_boss: Dictionary = game.make_test_enemy("venom_boss", Vector2(200, 100), 0.0, 200.0)
	venom_boss["boss"] = true
	var venom_normal: Dictionary = game.make_test_enemy("venom_normal", Vector2(240, 100), 0.0, 200.0)
	game.towers = [venom_tower]
	game.enemies = [venom_boss, venom_normal]
	var venom_boss_projectile: Dictionary = game.make_test_projectile(venom_tower, venom_boss, Vector2(193, 100))
	var venom_normal_projectile: Dictionary = game.make_test_projectile(venom_tower, venom_normal, Vector2(233, 100))
	game.update_projectile_for_test(venom_boss_projectile, 0.02)
	game.update_projectile_for_test(venom_normal_projectile, 0.02)
	var boss_hp_after_hit: float = float(venom_boss["hp"])
	var normal_hp_after_hit: float = float(venom_normal["hp"])
	game.update_enemy_for_test(venom_boss, 0.5)
	game.update_enemy_for_test(venom_normal, 0.5)
	_record_check(result, "venom_cask_scales_boss_poison", (boss_hp_after_hit - float(venom_boss["hp"])) > (normal_hp_after_hit - float(venom_normal["hp"])), {"boss_damage": boss_hp_after_hit - float(venom_boss["hp"]), "normal_damage": normal_hp_after_hit - float(venom_normal["hp"])})

	var wildfire_tower: Dictionary = game.make_test_tower("first", "poison", 3)
	wildfire_tower["damage"] = 20.0
	wildfire_tower["selected_branch"] = "wildfire"
	var wildfire_target: Dictionary = game.make_test_enemy("wildfire_target", Vector2(200, 100), 0.0, 200.0)
	var wildfire_near: Dictionary = game.make_test_enemy("wildfire_near", Vector2(245, 100), 0.0, 200.0)
	var wildfire_far: Dictionary = game.make_test_enemy("wildfire_far", Vector2(310, 100), 0.0, 200.0)
	game.towers = [wildfire_tower]
	game.enemies = [wildfire_target, wildfire_near, wildfire_far]
	var wildfire_projectile: Dictionary = game.make_test_projectile(wildfire_tower, wildfire_target, Vector2(193, 100))
	game.update_projectile_for_test(wildfire_projectile, 0.02)
	_record_check(result, "wildfire_bloom_ignites_primary", float(wildfire_target.get("wildfire_burn_timer", 0.0)) > 0.0, wildfire_target)
	_record_check(result, "wildfire_bloom_ignites_nearby_targets", float(wildfire_near.get("wildfire_burn_timer", 0.0)) > 0.0 and is_equal_approx(float(wildfire_far.get("wildfire_burn_timer", 0.0)), 0.0), {"near": wildfire_near, "far": wildfire_far})
	var wildfire_hp_before_tick: float = float(wildfire_near["hp"])
	game.update_enemy_for_test(wildfire_near, 0.5)
	_record_check(result, "wildfire_burn_ticks_damage", float(wildfire_near["hp"]) < wildfire_hp_before_tick, {"before": wildfire_hp_before_tick, "after": wildfire_near["hp"]})


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	ValidationHarness.record_check(result, label, passed, detail)
