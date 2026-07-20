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
	_check_split_wave_resolution_accounting(game, result)

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


func _check_split_wave_resolution_accounting(game: Node, result: Dictionary) -> void:
	var split_wave: int = _find_split_wave(game)
	_record_check(result, "effective_split_wave_exists", split_wave > 0, {"split_wave": split_wave})
	if split_wave <= 0:
		return
	_check_split_child_kill_path(game, result, split_wave)
	_check_split_child_leak_path(game, result, split_wave)


func _find_split_wave(game: Node) -> int:
	var schedule: Array = game.game_data.get("waves", {}).get("schedule", [])
	for index in range(schedule.size()):
		var wave_number := index + 1
		game.set_wave_for_test(wave_number)
		var row: Variant = schedule[index]
		var kind := "normal"
		if row is Dictionary:
			kind = str(row.get("enemy_kind", "normal"))
		var enemy: Dictionary = game.create_enemy(kind, wave_number, Vector2(180, 100), 1)
		if int(enemy.get("death_spawns", 0)) > 0:
			return wave_number
	return 0


func _check_split_child_kill_path(game: Node, result: Dictionary, split_wave: int) -> void:
	var setup: Dictionary = _prepare_controlled_split_wave(game, split_wave)
	if not bool(setup.get("ok", false)):
		_record_check(result, "split_kill_setup", false, setup)
		return
	var target: Dictionary = setup["target"]
	var expected_children := int(target.get("death_spawns", 0))
	_record_check(result, "split_kill_target_has_death_spawns", expected_children > 0, target)
	if expected_children <= 0:
		return
	var tower: Dictionary = _test_tower_near(target)
	game.towers = [tower]
	_kill_enemy_with_projectile(game, target, tower)
	game.process_step(0.01)
	var after_parent: Dictionary = game.snapshot()
	_record_check(result, "split_kill_child_created", game.enemies.size() == expected_children and int(after_parent.get("spawned_extra_this_wave", 0)) == expected_children, {"enemies": game.enemies, "snapshot": after_parent})
	var parent_resolved := _resolved_count(after_parent)
	_kill_enemy_with_projectile(game, target, tower)
	game.process_step(0.01)
	var after_parent_retry: Dictionary = game.snapshot()
	_record_check(result, "split_parent_not_duplicate_resolved", _resolved_count(after_parent_retry) == parent_resolved and int(after_parent_retry.get("spawned_extra_this_wave", 0)) == expected_children, {"before": after_parent, "after_retry": after_parent_retry})
	if game.enemies.is_empty():
		return
	var child: Dictionary = game.enemies[0]
	_record_check(result, "split_kill_child_reward_zero", int(child.get("reward", -1)) == 0, child)
	var tower_damage_before := float(tower.get("total_damage", 0.0))
	var tower_mastery_before := float(tower.get("mastery_xp", 0.0))
	_kill_enemy_with_projectile(game, child, tower)
	game.process_step(0.01)
	game.process_step(0.01)
	var final_snapshot: Dictionary = game.snapshot()
	var final_resolved := _resolved_count(final_snapshot)
	_kill_enemy_with_projectile(game, child, tower)
	game.process_step(0.01)
	var after_child_retry: Dictionary = game.snapshot()
	_record_check(result, "split_child_kill_completes_wave", bool(final_snapshot.get("wave_complete", false)) and not bool(final_snapshot.get("game_over", false)), final_snapshot)
	_record_check(result, "split_child_kill_total_resolution", _resolved_count(final_snapshot) == int(final_snapshot.get("spawned_total_this_wave", -1)), final_snapshot)
	_record_check(result, "split_child_kill_no_over_resolution", _resolved_count(final_snapshot) <= int(final_snapshot.get("spawned_total_this_wave", -1)), final_snapshot)
	_record_check(result, "split_child_not_duplicate_resolved", _resolved_count(after_child_retry) == final_resolved and int(after_child_retry.get("spawned_extra_this_wave", 0)) == expected_children, {"before": final_snapshot, "after_retry": after_child_retry})
	_record_check(result, "split_child_kill_credits_tower", int(tower.get("kills", 0)) >= 2, tower)
	_record_check(result, "split_child_damage_mastery_recorded", float(tower.get("total_damage", 0.0)) > tower_damage_before and float(tower.get("mastery_xp", 0.0)) > tower_mastery_before, tower)
	_record_check(result, "split_child_kill_invariants_clean", game.runtime_invariant_failures().is_empty(), game.runtime_invariant_failures())
	_record_check(result, "split_extra_counter_resets_next_wave", game.advance_to_next_wave() and int(game.snapshot().get("spawned_extra_this_wave", -1)) == 0, game.snapshot())


func _check_split_child_leak_path(game: Node, result: Dictionary, split_wave: int) -> void:
	var setup: Dictionary = _prepare_controlled_split_wave(game, split_wave)
	if not bool(setup.get("ok", false)):
		_record_check(result, "split_leak_setup", false, setup)
		return
	var target: Dictionary = setup["target"]
	var expected_children := int(target.get("death_spawns", 0))
	if expected_children <= 0:
		_record_check(result, "split_leak_target_has_death_spawns", false, target)
		return
	var tower: Dictionary = _test_tower_near(target)
	game.towers = [tower]
	_kill_enemy_with_projectile(game, target, tower)
	game.process_step(0.01)
	var after_parent: Dictionary = game.snapshot()
	_record_check(result, "split_leak_child_created", game.enemies.size() == expected_children and int(after_parent.get("spawned_extra_this_wave", 0)) == expected_children, {"enemies": game.enemies, "snapshot": after_parent})
	if game.enemies.is_empty():
		return
	var before_lives := int(game.snapshot().get("lives", 0))
	var before_tower_kills := int(tower.get("kills", 0))
	for child in game.enemies:
		child["target_index"] = 999
	game.process_step(0.01)
	game.process_step(0.01)
	var final_snapshot: Dictionary = game.snapshot()
	_record_check(result, "split_child_leak_completes_wave", bool(final_snapshot.get("wave_complete", false)) and not bool(final_snapshot.get("game_over", false)), final_snapshot)
	_record_check(result, "split_child_leak_exact_life_loss", before_lives - int(final_snapshot.get("lives", 0)) == expected_children, {"before_lives": before_lives, "snapshot": final_snapshot})
	_record_check(result, "split_child_leak_no_tower_kill_credit", int(tower.get("kills", 0)) == before_tower_kills, tower)
	_record_check(result, "split_child_leak_total_resolution", _resolved_count(final_snapshot) == int(final_snapshot.get("spawned_total_this_wave", -1)), final_snapshot)
	_record_check(result, "split_child_leak_no_over_resolution", _resolved_count(final_snapshot) <= int(final_snapshot.get("spawned_total_this_wave", -1)), final_snapshot)
	_record_check(result, "split_child_leak_invariants_clean", game.runtime_invariant_failures().is_empty(), game.runtime_invariant_failures())


func _prepare_controlled_split_wave(game: Node, split_wave: int) -> Dictionary:
	var wave_info: Dictionary = game.spawn_regular_wave_for_test(split_wave)
	game.wave_active = true
	game.lives = max(game.lives, 200)
	if game.enemies.is_empty():
		return {"ok": false, "reason": "no enemies", "wave_info": wave_info}
	var target_index := -1
	for index in range(game.enemies.size()):
		if int(game.enemies[index].get("death_spawns", 0)) > 0:
			target_index = index
			break
	if target_index < 0:
		return {"ok": false, "reason": "no split enemy", "wave_info": wave_info, "enemies": game.enemies}
	var target: Dictionary = game.enemies[target_index]
	for index in range(game.enemies.size()):
		if index == target_index:
			continue
		game.enemies[index]["target_index"] = 999
	game.process_step(0.01)
	return {
		"ok": game.enemies.size() == 1 and game.enemies[0] == target,
		"target": target,
		"wave_info": wave_info,
		"snapshot": game.snapshot(),
	}


func _test_tower_near(enemy: Dictionary) -> Dictionary:
	var tower := {
		"type": "archer",
		"position": enemy.get("position", Vector2.ZERO),
		"level": 2,
		"range": 250.0,
		"damage": max(1.0, float(enemy.get("max_hp", 1.0)) * 2.0),
		"fire_rate": 0.5,
		"cooldown": 999.0,
		"target_mode": "first",
		"kills": 0,
		"money_spent": 0,
		"mutations": [],
		"selected_branch": "",
		"is_paragon": false,
		"total_damage": 0.0,
		"mastery_xp": 0.0,
	}
	return tower


func _kill_enemy_with_projectile(game: Node, enemy: Dictionary, tower: Dictionary) -> void:
	tower["position"] = enemy.get("position", Vector2.ZERO)
	tower["damage"] = max(1.0, float(enemy.get("max_hp", 1.0)) * 2.0)
	var projectile: Dictionary = game.make_test_projectile(tower, enemy, enemy.get("position", Vector2.ZERO))
	game.update_projectile_for_test(projectile, 0.01)


func _resolved_count(snapshot: Dictionary) -> int:
	return int(snapshot.get("kills", 0)) + int(snapshot.get("leaks", 0))


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	ValidationHarness.record_check(result, label, passed, detail)
