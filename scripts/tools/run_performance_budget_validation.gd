extends SceneTree

const STRESS_ENEMY_COUNT := 120
const STRESS_STEP_COUNT := 180
const STRESS_STEP_DELTA := 0.025
const AVG_STEP_BUDGET_USEC := 5000
const MAX_STEP_BUDGET_USEC := 50000
const TOTAL_BUDGET_USEC := 900000
const MAX_ENEMY_BUDGET := 160
const MAX_PROJECTILE_BUDGET := 120


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
	_setup_stress_load(game, result)
	_check_simulation_budget(game, result)

	if result["ok"]:
		print("PERFORMANCE_BUDGET_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("PERFORMANCE_BUDGET_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)


func _setup_stress_load(game: Node, result: Dictionary) -> void:
	game.money = 5000
	for tower_type in ["archer", "machine_gun", "cannon", "sniper", "tesla"]:
		_record_check(result, "place_%s_for_performance_budget" % tower_type, _place_first_valid(game, tower_type), game.snapshot())
	_record_check(result, "performance_budget_has_towers", int(game.snapshot().get("tower_count", 0)) >= 5, game.snapshot())
	game.set_debug_overlay_enabled(true)
	_record_check(result, "performance_budget_set_wave", bool(game.run_debug_command("set_wave", {"wave": 10}).get("ok", false)), game.snapshot())
	var spawned := 0
	for kind in ["normal", "fast", "tank"]:
		var command_result: Dictionary = game.run_debug_command("spawn_enemy", {"kind": kind, "count": 40})
		spawned += int(command_result.get("detail", {}).get("count", 0)) if bool(command_result.get("ok", false)) else 0
		_record_check(result, "spawn_%s_stress_enemies" % kind, bool(command_result.get("ok", false)), command_result)
	var snapshot: Dictionary = game.snapshot()
	_record_check(result, "performance_budget_enemy_count", spawned == STRESS_ENEMY_COUNT and int(snapshot.get("enemy_count", 0)) == STRESS_ENEMY_COUNT and int(snapshot.get("enemy_count", 0)) <= MAX_ENEMY_BUDGET, snapshot)


func _check_simulation_budget(game: Node, result: Dictionary) -> void:
	var max_step_usec := 0
	var total_step_usec := 0
	var max_enemy_count := int(game.snapshot().get("enemy_count", 0))
	var max_projectile_count := int(game.snapshot().get("projectile_count", 0))
	for _step in range(STRESS_STEP_COUNT):
		var before := Time.get_ticks_usec()
		game.process_step(STRESS_STEP_DELTA)
		var elapsed: int = Time.get_ticks_usec() - before
		total_step_usec += elapsed
		max_step_usec = max(max_step_usec, elapsed)
		var snapshot: Dictionary = game.snapshot()
		max_enemy_count = max(max_enemy_count, int(snapshot.get("enemy_count", 0)))
		max_projectile_count = max(max_projectile_count, int(snapshot.get("projectile_count", 0)))
	var avg_step_usec := float(total_step_usec) / float(max(1, STRESS_STEP_COUNT))
	var budget_report := {
		"steps": STRESS_STEP_COUNT,
		"delta": STRESS_STEP_DELTA,
		"avg_step_usec": avg_step_usec,
		"max_step_usec": max_step_usec,
		"total_step_usec": total_step_usec,
		"avg_budget_usec": AVG_STEP_BUDGET_USEC,
		"max_budget_usec": MAX_STEP_BUDGET_USEC,
		"total_budget_usec": TOTAL_BUDGET_USEC,
		"max_enemy_count": max_enemy_count,
		"max_enemy_budget": MAX_ENEMY_BUDGET,
		"max_projectile_count": max_projectile_count,
		"max_projectile_budget": MAX_PROJECTILE_BUDGET,
		"final_snapshot": game.snapshot(),
	}
	_record_check(result, "average_step_time_within_budget", avg_step_usec <= float(AVG_STEP_BUDGET_USEC), budget_report)
	_record_check(result, "max_step_time_within_budget", max_step_usec <= MAX_STEP_BUDGET_USEC, budget_report)
	_record_check(result, "total_stress_time_within_budget", total_step_usec <= TOTAL_BUDGET_USEC, budget_report)
	_record_check(result, "entity_counts_within_budget", max_enemy_count <= MAX_ENEMY_BUDGET and max_projectile_count <= MAX_PROJECTILE_BUDGET, budget_report)
	_record_check(result, "performance_stress_keeps_invariants_clean", game.runtime_invariant_failures().is_empty(), game.runtime_invariant_failures())


func _place_first_valid(game: Node, tower_type: String) -> bool:
	if not game.select_shop_tower(tower_type):
		return false
	for y in range(108, 570, 27):
		for x in range(54, 864, 27):
			var site := Vector2(float(x), float(y))
			if game.can_place_tower(site):
				return game.place_selected_tower(site, tower_type)
	return false


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	result["checks"].append({
		"label": label,
		"passed": passed,
		"detail": detail,
	})
	if not passed:
		result["ok"] = false
		result["errors"].append("%s failed: %s" % [label, str(detail)])
