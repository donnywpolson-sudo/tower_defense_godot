extends Node2D

signal status_changed(status: Dictionary)

const ARCHER_ID := "archer"
const ENEMY_KIND := "normal"
const BASELINE_ENEMY_KINDS := ["normal", "fast", "tank", "swarm", "shield", "flying", "armored", "commander"]
const SLICE_SPAWN_LIMIT := 3
const PROJECTILE_HIT_DISTANCE := 8.0
const RECOMMENDED_BUILD_SITE := Vector2(300, 243)
const SHOP_BUTTON_SIZE := Vector2(120, 28)
const SHOP_BUTTON_GAP := 4.0
const NO_SELECTED_TOWER := -1

var baseline: Dictionary = {}
var config: Dictionary = {}
var map_record: Dictionary = {}
var path_points: Array = []
var wave_row: Dictionary = {}
var archer_data: Dictionary = {}

var money: int = 0
var lives: int = 0
var research_points: int = 0
var wave: int = 1
var wave_active: bool = false
var wave_complete: bool = false
var spawned_this_wave: int = 0
var spawn_timer: float = 0.0
var leaks: int = 0
var kills: int = 0
var wave_reward_money: int = 0
var wave_reward_research: int = 0
var selected_build_type: String = ""
var selected_tower_index: int = NO_SELECTED_TOWER

var towers: Array = []
var enemies: Array = []
var projectiles: Array = []
var progress_override: Node = null


func _ready() -> void:
	reset_slice()
	set_process(true)


func reset_slice() -> void:
	baseline = GameData.load_baseline()
	config = baseline.get("config", {})
	map_record = baseline.get("maps", {}).get("catalog", [])[0]
	path_points = _points_from_path(map_record.get("paths", [[[]]])[0])
	wave_row = baseline.get("waves", {}).get("schedule", [])[0]
	archer_data = baseline.get("towers", {}).get("tower_types", {}).get(ARCHER_ID, {})
	var run_defaults := _new_run_defaults()
	money = int(run_defaults.get("money", config.get("starting_money", GameConfig.STARTING_MONEY)))
	lives = int(run_defaults.get("lives", config.get("starting_lives", GameConfig.STARTING_LIVES)))
	research_points = int(run_defaults.get("research_points", 0))
	wave = 1
	wave_active = false
	wave_complete = false
	spawned_this_wave = 0
	spawn_timer = 0.0
	leaks = 0
	kills = 0
	wave_reward_money = 0
	wave_reward_research = 0
	selected_build_type = ""
	selected_tower_index = NO_SELECTED_TOWER
	towers = []
	enemies = []
	projectiles = []
	_emit_status()
	queue_redraw()


func place_archer(site: Vector2 = RECOMMENDED_BUILD_SITE) -> bool:
	return place_selected_tower(site, ARCHER_ID)


func place_selected_tower(site: Vector2, tower_type: String = "") -> bool:
	if tower_type.is_empty():
		tower_type = selected_build_type
	if tower_type != ARCHER_ID:
		return false
	var cost: int = _shop_cost(tower_type)
	if money < cost:
		return false
	if not _can_place_tower_site(site):
		return false
	money -= cost
	var run_defaults := _new_run_defaults()
	var damage_multiplier: float = float(run_defaults.get("tower_damage_multiplier", 1.0))
	var tower := {
		"type": ARCHER_ID,
		"position": site,
		"level": 2,
		"range": float(config.get("base_tower_range", 145)) + 18.0,
		"damage": 39.0 * damage_multiplier,
		"fire_rate": 0.50,
		"cooldown": 0.0,
		"target_mode": "first",
		"kills": 0,
		"money_spent": cost,
		"mutations": [],
		"selected_branch": "",
		"is_paragon": false,
	}
	towers.append(tower)
	selected_tower_index = towers.size() - 1
	if selected_build_type == tower_type:
		selected_build_type = ""
	_play_sound("sounds/ui/build.wav", 360.0)
	_emit_status()
	queue_redraw()
	return true


func can_place_tower(site: Vector2) -> bool:
	if selected_build_type.is_empty():
		return false
	if money < _shop_cost(selected_build_type):
		return false
	return _can_place_tower_site(site)


func _can_place_tower_site(site: Vector2) -> bool:
	if site.x < 0.0 or site.x > float(config.get("map_width", GameConfig.MAP_WIDTH)):
		return false
	if site.y < float(config.get("build_grid_top", 81)) or site.y > float(config.get("height", GameConfig.LOGICAL_HEIGHT)):
		return false
	for tower in towers:
		if site.distance_to(tower["position"]) < float(config.get("build_tile_size", 54)):
			return false
	var blocked_distance: float = float(config.get("path_width", 54)) / 2.0 + float(config.get("build_tile_size", 54)) / 2.0
	for index in range(path_points.size() - 1):
		if _distance_point_to_segment(site, path_points[index], path_points[index + 1]) < blocked_distance:
			return false
	return true


func start_wave() -> bool:
	if wave_active or wave_complete or towers.is_empty():
		return false
	wave_active = true
	spawn_timer = 0.0
	spawned_this_wave = 0
	_play_sound("sounds/ui/wave.wav", 480.0)
	_emit_status()
	return true


func set_tower_target_mode(index: int, target_mode: String) -> bool:
	if index < 0 or index >= towers.size():
		return false
	var target_modes: Array = baseline.get("towers", {}).get("target_modes", [])
	if not target_modes.has(target_mode):
		return false
	towers[index]["target_mode"] = target_mode
	_emit_status()
	return true


func process_step(delta: float) -> void:
	if wave_active:
		_update_spawning(delta)
	_update_enemies(delta)
	_update_towers(delta)
	_update_projectiles(delta)
	_check_wave_completion()
	queue_redraw()


func _process(delta: float) -> void:
	process_step(min(delta, 0.05))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start_wave"):
		start_wave()
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if handle_shop_click(mouse_event.position):
				return
			if handle_upgrade_panel_click(mouse_event.position):
				return
			handle_map_click(mouse_event.position)


func handle_shop_click(pos: Vector2) -> bool:
	for button in get_shop_button_rects():
		var rect: Rect2 = button["rect"]
		if rect.has_point(pos):
			if bool(button.get("enabled", false)):
				selected_build_type = str(button["tower_type"])
				selected_tower_index = NO_SELECTED_TOWER
				_emit_status()
				queue_redraw()
			return true
	return false


func handle_map_click(pos: Vector2) -> bool:
	if not selected_build_type.is_empty():
		return place_selected_tower(pos)
	var tower_index: int = _tower_index_at(pos)
	selected_tower_index = tower_index
	_emit_status()
	queue_redraw()
	return tower_index != NO_SELECTED_TOWER


func handle_upgrade_panel_click(pos: Vector2) -> bool:
	if selected_tower_index == NO_SELECTED_TOWER:
		return false
	if not get_upgrade_panel_rect().has_point(pos):
		return false
	if get_target_button_rect().has_point(pos):
		cycle_selected_target_mode()
		return true
	if get_sell_button_rect().has_point(pos):
		sell_selected_tower()
		return true
	return true


func select_shop_tower(tower_type: String) -> bool:
	if tower_type != ARCHER_ID:
		return false
	selected_build_type = tower_type
	selected_tower_index = NO_SELECTED_TOWER
	_emit_status()
	queue_redraw()
	return true


func get_shop_button_rects() -> Array:
	var rects: Array = []
	var start_x: float = float(config.get("map_width", GameConfig.MAP_WIDTH)) + 14.0
	var start_y: float = 126.0
	for index in range(_current_slice_shop_towers().size()):
		var tower_type: String = _current_slice_shop_towers()[index]
		var col: int = index % 2
		var row: int = int(index / 2)
		var rect := Rect2(
			Vector2(start_x + col * (SHOP_BUTTON_SIZE.x + SHOP_BUTTON_GAP), start_y + row * (SHOP_BUTTON_SIZE.y + SHOP_BUTTON_GAP)),
			SHOP_BUTTON_SIZE
		)
		rects.append({
			"rect": rect,
			"tower_type": tower_type,
			"label": _tower_label(tower_type),
			"cost": _shop_cost(tower_type),
			"selected": selected_build_type == tower_type,
			"affordable": money >= _shop_cost(tower_type),
			"enabled": tower_type == ARCHER_ID,
		})
	return rects


func shop_snapshot() -> Dictionary:
	var buttons: Array = []
	for button in get_shop_button_rects():
		buttons.append({
			"tower_type": button["tower_type"],
			"label": button["label"],
			"cost": button["cost"],
			"selected": button["selected"],
			"affordable": button["affordable"],
			"enabled": button["enabled"],
		})
	return {
		"selected_build_type": selected_build_type,
		"button_count": buttons.size(),
		"buttons": buttons,
		"python_shop_order": baseline.get("towers", {}).get("shop_order", []),
	}


func get_upgrade_panel_rect() -> Rect2:
	return Rect2(
		Vector2(float(config.get("map_width", GameConfig.MAP_WIDTH)) + 8.0, 286.0),
		Vector2(float(config.get("ui_width", GameConfig.UI_WIDTH)) - 16.0, 304.0)
	)


func get_target_button_rect() -> Rect2:
	var panel := get_upgrade_panel_rect()
	return Rect2(Vector2(panel.position.x + 14.0, panel.end.y - 82.0), Vector2(panel.size.x - 28.0, 30.0))


func get_sell_button_rect() -> Rect2:
	var panel := get_upgrade_panel_rect()
	return Rect2(Vector2(panel.position.x + 14.0, panel.end.y - 44.0), Vector2(panel.size.x - 28.0, 30.0))


func upgrade_panel_snapshot() -> Dictionary:
	var tower := _selected_tower()
	if tower.is_empty():
		return {
			"visible": false,
			"selected_tower_index": selected_tower_index,
		}
	var needs_branch: bool = _tower_needs_branch_choice(tower)
	var options: Array = [] if needs_branch else _upgrade_options_for_tower(tower)
	return {
		"visible": true,
		"selected_tower_index": selected_tower_index,
		"tower_type": tower.get("type", ""),
		"tower_name": _tower_display_name(tower),
		"stats": _tower_stat_text(tower),
		"details": _tower_detail_text(tower),
		"target_label": "Target %s" % str(tower.get("target_mode", "first")).capitalize(),
		"target_mode": tower.get("target_mode", "first"),
		"sell_label": "Sell +$%s" % _sell_refund(tower),
		"sell_refund": _sell_refund(tower),
		"needs_branch_choice": needs_branch,
		"upgrade_options": options,
	}


func cycle_selected_target_mode() -> bool:
	var tower := _selected_tower()
	if tower.is_empty():
		return false
	var target_modes: Array = baseline.get("towers", {}).get("target_modes", [])
	if target_modes.is_empty():
		return false
	var current_mode: String = str(tower.get("target_mode", "first"))
	var index: int = target_modes.find(current_mode)
	if index == -1:
		index = 0
	tower["target_mode"] = target_modes[(index + 1) % target_modes.size()]
	_emit_status()
	queue_redraw()
	return true


func sell_selected_tower() -> bool:
	var tower := _selected_tower()
	if tower.is_empty():
		return false
	money += _sell_refund(tower)
	towers.remove_at(selected_tower_index)
	selected_tower_index = NO_SELECTED_TOWER
	_play_sound("sounds/ui/sell.wav", 260.0)
	_emit_status()
	queue_redraw()
	return true


func _current_slice_shop_towers() -> Array:
	return [ARCHER_ID]


func _shop_cost(tower_type: String) -> int:
	return int(baseline.get("towers", {}).get("shop_costs", {}).get(tower_type, 50))


func _tower_label(tower_type: String) -> String:
	return str(baseline.get("towers", {}).get("tower_types", {}).get(tower_type, {}).get("label", tower_type.capitalize()))


func _selected_tower() -> Dictionary:
	if selected_tower_index < 0 or selected_tower_index >= towers.size():
		return {}
	return towers[selected_tower_index]


func _tower_index_at(pos: Vector2) -> int:
	for index in range(towers.size()):
		if pos.distance_to(towers[index]["position"]) < 24.0:
			return index
	return NO_SELECTED_TOWER


func _tower_display_name(tower: Dictionary) -> String:
	return "%s Tower" % _tower_label(str(tower.get("type", ARCHER_ID)))


func _tower_stat_text(tower: Dictionary) -> String:
	return "L%s | DMG %s | Range %s" % [
		int(tower.get("level", 1)),
		int(tower.get("damage", 0)),
		int(tower.get("range", 0)),
	]


func _tower_detail_text(tower: Dictionary) -> String:
	var tower_type: String = str(tower.get("type", ARCHER_ID))
	var data: Dictionary = baseline.get("towers", {}).get("tower_types", {}).get(tower_type, {})
	var family: String = str(data.get("family", data.get("label", "Basic"))).replace(" Family", "")
	var branch_text := "Pick branch" if _tower_needs_branch_choice(tower) else "Branch at L3"
	var mutations: Array = tower.get("mutations", [])
	return "%s | %s | Traits %s/2" % [
		family,
		branch_text,
		mutations.size(),
	]


func _tower_needs_branch_choice(tower: Dictionary) -> bool:
	var root_ids: Array = baseline.get("towers", {}).get("root_tower_ids", [])
	var branch_unlock_level: int = int(baseline.get("towers", {}).get("branch_unlock_level", 3))
	return root_ids.has(tower.get("type", "")) and int(tower.get("level", 1)) == branch_unlock_level - 1 and str(tower.get("selected_branch", "")).is_empty()


func _upgrade_options_for_tower(tower: Dictionary) -> Array:
	var cost: int = _upgrade_cost(tower)
	if cost == 0:
		return []
	return [{
		"tower_type": tower.get("type", ""),
		"title": _upgrade_title(tower),
		"cost": cost,
		"description": "",
		"enabled": money >= cost,
	}]


func _upgrade_title(tower: Dictionary) -> String:
	var tower_type: String = str(tower.get("type", ARCHER_ID))
	var next_level: int = int(tower.get("level", 1)) + 1
	var tiers: Dictionary = baseline.get("towers", {}).get("tower_types", {}).get(tower_type, {}).get("tiers", {})
	return str(tiers.get(str(next_level), "Level %s" % next_level))


func _upgrade_cost(tower: Dictionary) -> int:
	var level: int = int(tower.get("level", 1))
	var costs: Dictionary = baseline.get("upgrades", {}).get("tower_upgrade_costs", {})
	if level >= int(baseline.get("config", {}).get("base_max_tower_level", 5)):
		costs = baseline.get("upgrades", {}).get("mastery_upgrade_costs", {})
	return int(costs.get(str(level), costs.get(level, 0)))


func _sell_refund(tower: Dictionary) -> int:
	var rate: float = float(config.get("sell_refund_rate", 0.75))
	if bool(tower.get("is_paragon", false)):
		rate = float(config.get("paragon_sell_refund_rate", 0.5))
	return int(float(tower.get("money_spent", 0)) * rate)


func _update_spawning(delta: float) -> void:
	if spawned_this_wave >= SLICE_SPAWN_LIMIT:
		return
	spawn_timer += delta
	var interval: float = float(wave_row.get("spawn_interval", 0.608))
	if spawn_timer < interval:
		return
	spawn_timer = 0.0
	spawned_this_wave += 1
	enemies.append(create_enemy(_wave_enemy_kind()))


func _create_normal_enemy() -> Dictionary:
	return create_enemy(ENEMY_KIND)


func create_enemy(kind: String = ENEMY_KIND, wave_number: int = -1, position: Vector2 = Vector2.INF, target_index: int = 1) -> Dictionary:
	if wave_number < 0:
		wave_number = wave
	var enemy_kind := _normalized_enemy_kind(kind)
	var hp: float = 65.0 + wave_number * 18.0 + max(0, wave_number - 10) * 8.0 + max(0, wave_number - 20) * 18.0
	var speed: float = 62.0 + wave_number * 2.0
	var reward: int = 4 + int(floor(float(wave_number) / 8.0))
	var modifier: Dictionary = _enemy_kind_modifier(enemy_kind)
	hp *= float(modifier.get("hp_multiplier", 1.0))
	speed *= float(modifier.get("speed_multiplier", 1.0))
	reward += int(modifier.get("reward_bonus", 0))
	var shield_hits: int = int(modifier.get("shield_hits", 0))
	var spawn_position: Vector2 = path_points[0] if position == Vector2.INF else position
	return {
		"kind": enemy_kind,
		"position": spawn_position,
		"target_index": target_index,
		"hp": hp,
		"max_hp": hp,
		"speed": speed,
		"reward": reward,
		"reached_end": false,
		"progress": 0.0,
		"marked_timer": 0.0,
		"vulnerable_timer": 0.0,
		"flying": bool(modifier.get("flying", false)),
		"shield_hits": shield_hits,
		"max_shield_hits": shield_hits,
		"tags": modifier.get("tags", []).duplicate(true),
		"commander": bool(modifier.get("commander", false)),
	}


func _wave_enemy_kind() -> String:
	return _normalized_enemy_kind(str(wave_row.get("enemy_kind", ENEMY_KIND)))


func _normalized_enemy_kind(kind: String) -> String:
	if BASELINE_ENEMY_KINDS.has(kind):
		return kind
	return ENEMY_KIND


func _enemy_kind_modifier(kind: String) -> Dictionary:
	var modifiers: Dictionary = baseline.get("enemies", {}).get("kind_modifiers", {})
	var modifier: Variant = modifiers.get(_normalized_enemy_kind(kind), {})
	return modifier if modifier is Dictionary else {}


func _update_enemies(delta: float) -> void:
	var remaining: Array = []
	for enemy in enemies:
		_update_enemy(enemy, delta)
		if enemy["reached_end"]:
			lives -= 1
			leaks += 1
		elif float(enemy["hp"]) <= 0.0:
			money += int(enemy["reward"])
			kills += 1
			_credit_tower_kill(enemy)
		else:
			remaining.append(enemy)
	enemies = remaining


func _update_enemy(enemy: Dictionary, delta: float) -> void:
	var target_index: int = int(enemy["target_index"])
	if target_index >= path_points.size():
		enemy["reached_end"] = true
		return
	var position: Vector2 = enemy["position"]
	var target: Vector2 = path_points[target_index]
	var offset: Vector2 = target - position
	var distance: float = offset.length()
	if distance < 2.0:
		enemy["target_index"] = target_index + 1
		return
	var movement: float = float(enemy["speed"]) * delta
	enemy["position"] = position + offset.normalized() * min(movement, distance)
	enemy["progress"] = _enemy_progress(enemy)


func _update_towers(delta: float) -> void:
	for tower in towers:
		tower["cooldown"] = max(0.0, float(tower["cooldown"]) - delta)
		if float(tower["cooldown"]) > 0.0:
			continue
		var target: Dictionary = _find_target(tower)
		if target.is_empty():
			continue
		projectiles.append({
			"position": tower["position"],
			"target": target,
			"tower": tower,
			"damage": tower["damage"],
			"speed": _projectile_speed_for_tower(tower),
			"tower_type": tower.get("type", ""),
			"tower_level": tower.get("level", 1),
			"trail_timer": 0.0,
			"dead": false,
		})
		tower["cooldown"] = float(tower["fire_rate"])


func _find_target(tower: Dictionary) -> Dictionary:
	var valid: Array = _valid_targets(tower)
	if valid.is_empty():
		return {}
	var priority: Array = _priority_targets(valid)
	var target_mode: String = str(tower.get("target_mode", "first"))
	if target_mode == "first":
		return _max_by_progress(priority if not priority.is_empty() else valid)
	if target_mode == "last":
		return _min_by_progress(priority if not priority.is_empty() else valid)
	if target_mode == "strongest":
		return _max_by_hp(priority if not priority.is_empty() else valid)
	if target_mode == "weakest":
		return _min_by_hp(priority if not priority.is_empty() else valid)
	if target_mode == "flying":
		var flying: Array = []
		for enemy in valid:
			if bool(enemy.get("flying", false)):
				flying.append(enemy)
		if not flying.is_empty():
			var priority_flying: Array = _priority_targets(flying)
			return _min_by_distance(priority_flying if not priority_flying.is_empty() else flying, tower["position"])
	return _min_by_distance(valid, tower["position"])


func _valid_targets(tower: Dictionary) -> Array:
	var valid: Array = []
	var tower_position: Vector2 = tower["position"]
	var tower_range: float = float(tower["range"])
	for enemy in enemies:
		if tower_position.distance_to(enemy["position"]) > tower_range:
			continue
		if not _can_attack(tower, enemy):
			continue
		valid.append(enemy)
	return valid


func _can_attack(tower: Dictionary, enemy: Dictionary) -> bool:
	if not bool(enemy.get("flying", false)):
		return true
	var tower_type: String = str(tower.get("type", ""))
	var level: int = int(tower.get("level", 1))
	return tower_type == "tesla" and level >= 4 or tower_type == "sniper" and level >= 3


func _priority_targets(candidates: Array) -> Array:
	var result: Array = []
	for enemy in candidates:
		if float(enemy.get("marked_timer", 0.0)) > 0.0 or float(enemy.get("vulnerable_timer", 0.0)) > 0.0:
			result.append(enemy)
	return result


func _priority_rank(enemy: Dictionary) -> Array:
	return [
		0 if float(enemy.get("marked_timer", 0.0)) > 0.0 else 1,
		0 if float(enemy.get("vulnerable_timer", 0.0)) > 0.0 else 1,
		float(enemy.get("hp", 0.0)),
	]


func _is_better_priority(candidate: Dictionary, current: Dictionary) -> bool:
	if current.is_empty():
		return true
	var candidate_rank: Array = _priority_rank(candidate)
	var current_rank: Array = _priority_rank(current)
	for index in range(candidate_rank.size()):
		if candidate_rank[index] == current_rank[index]:
			continue
		return candidate_rank[index] < current_rank[index]
	return false


func _max_by_progress(candidates: Array) -> Dictionary:
	var best: Dictionary = {}
	for enemy in candidates:
		if best.is_empty() or float(enemy.get("progress", 0.0)) > float(best.get("progress", 0.0)):
			best = enemy
	return best


func _min_by_progress(candidates: Array) -> Dictionary:
	var best: Dictionary = {}
	for enemy in candidates:
		if best.is_empty() or float(enemy.get("progress", 0.0)) < float(best.get("progress", 0.0)):
			best = enemy
	return best


func _max_by_hp(candidates: Array) -> Dictionary:
	var best: Dictionary = {}
	for enemy in candidates:
		if best.is_empty() or float(enemy.get("hp", 0.0)) > float(best.get("hp", 0.0)):
			best = enemy
	return best


func _min_by_hp(candidates: Array) -> Dictionary:
	var best: Dictionary = {}
	for enemy in candidates:
		if best.is_empty() or float(enemy.get("hp", 0.0)) < float(best.get("hp", 0.0)):
			best = enemy
	return best


func _min_by_distance(candidates: Array, tower_position: Vector2) -> Dictionary:
	var best: Dictionary = {}
	for enemy in candidates:
		if best.is_empty() or tower_position.distance_to(enemy["position"]) < tower_position.distance_to(best["position"]):
			best = enemy
	return best


func find_target_for_test(tower: Dictionary) -> Dictionary:
	return _find_target(tower)


func make_test_tower(target_mode: String = "first", tower_type: String = ARCHER_ID, level: int = 2) -> Dictionary:
	return {
		"type": tower_type,
		"position": Vector2(100, 100),
		"level": level,
		"range": 250.0,
		"damage": 10.0,
		"fire_rate": 0.50,
		"cooldown": 0.0,
		"target_mode": target_mode,
		"kills": 0,
	}


func make_test_enemy(id: String, position: Vector2, progress: float, hp: float = 100.0, marked: bool = false, vulnerable: bool = false, flying: bool = false) -> Dictionary:
	return {
		"id": id,
		"kind": "test",
		"position": position,
		"target_index": 1,
		"hp": hp,
		"max_hp": hp,
		"speed": 0.0,
		"reward": 0,
		"reached_end": false,
		"progress": progress,
		"marked_timer": 1.0 if marked else 0.0,
		"vulnerable_timer": 1.0 if vulnerable else 0.0,
		"flying": flying,
		"shield_hits": 0,
		"max_shield_hits": 0,
		"tags": [],
		"commander": false,
	}


func make_baseline_enemy_for_test(kind: String, wave_number: int = 1) -> Dictionary:
	return create_enemy(kind, wave_number, Vector2(180, 100), 1)


func _update_projectiles(delta: float) -> void:
	var remaining: Array = []
	for projectile in projectiles:
		_update_projectile(projectile, delta)
		if not bool(projectile.get("dead", false)):
			remaining.append(projectile)
	projectiles = remaining


func _update_projectile(projectile: Dictionary, delta: float) -> void:
	var target: Dictionary = projectile["target"]
	if not enemies.has(target):
		projectile["dead"] = true
		return
	var position: Vector2 = projectile["position"]
	var target_position: Vector2 = target["position"]
	var offset: Vector2 = target_position - position
	var distance: float = offset.length()
	if distance < PROJECTILE_HIT_DISTANCE:
		_hit_projectile_target(projectile)
		projectile["dead"] = true
		return
	if distance == 0.0:
		return
	var speed: float = float(projectile.get("speed", _projectile_speed_for_tower(projectile.get("tower", {}))))
	projectile["position"] = position + offset.normalized() * min(speed * delta, distance)
	projectile["trail_timer"] = max(0.0, float(projectile.get("trail_timer", 0.0)) - delta)


func _hit_projectile_target(projectile: Dictionary) -> float:
	var target: Dictionary = projectile["target"]
	if not enemies.has(target):
		projectile["dead"] = true
		return 0.0
	var damage: float = float(projectile.get("damage", 0.0))
	var shield_hits: int = int(target.get("shield_hits", 0))
	if shield_hits > 0:
		target["shield_hits"] = shield_hits - 1
		return 0.0
	target["hp"] = float(target.get("hp", 0.0)) - damage
	var tower: Dictionary = projectile.get("tower", {})
	tower["total_damage"] = float(tower.get("total_damage", 0.0)) + damage
	tower["mastery_xp"] = float(tower.get("mastery_xp", 0.0)) + damage * 0.02
	return damage


func _projectile_speed_for_tower(tower: Dictionary) -> float:
	var tower_type: String = str(tower.get("type", ""))
	if tower_type == "mortar":
		return 300.0
	if tower_type in ["sniper", "machine_gun", "tesla"]:
		return 760.0
	return 420.0


func make_test_projectile(tower: Dictionary, target: Dictionary, position: Vector2 = Vector2.INF) -> Dictionary:
	var start_position: Vector2 = tower["position"] if position == Vector2.INF else position
	return {
		"position": start_position,
		"target": target,
		"tower": tower,
		"damage": tower.get("damage", 0.0),
		"speed": _projectile_speed_for_tower(tower),
		"tower_type": tower.get("type", ""),
		"tower_level": tower.get("level", 1),
		"trail_timer": 0.0,
		"dead": false,
	}


func update_projectile_for_test(projectile: Dictionary, delta: float) -> Dictionary:
	_update_projectile(projectile, delta)
	return projectile


func projectile_speed_for_test(tower: Dictionary) -> float:
	return _projectile_speed_for_tower(tower)


func _check_wave_completion() -> void:
	if not wave_active:
		return
	if spawned_this_wave < SLICE_SPAWN_LIMIT or not enemies.is_empty():
		return
	wave_active = false
	wave_complete = true
	wave_reward_money = _wave_completion_money()
	wave_reward_research = _research_reward()
	money += wave_reward_money
	research_points += wave_reward_research
	_play_sound("sounds/ui/wave_complete.wav", 680.0)
	_emit_status()


func _wave_completion_money() -> int:
	var base_money: int = int(config.get("start_wave_bonus", 10)) + wave
	var multiplier: float = float(map_record.get("reward_multiplier", 1.0))
	return max(1, int(round(base_money * multiplier)))


func _research_reward() -> int:
	return 1 + int(floor(float(wave) / 5.0))


func snapshot() -> Dictionary:
	return {
		"money": money,
		"lives": lives,
		"research_points": research_points,
		"wave": wave,
		"wave_active": wave_active,
		"wave_complete": wave_complete,
		"spawned_this_wave": spawned_this_wave,
		"slice_spawn_limit": SLICE_SPAWN_LIMIT,
		"baseline_regular_enemy_count": int(wave_row.get("regular_enemy_count", 0)),
		"kills": kills,
		"leaks": leaks,
		"tower_count": towers.size(),
		"enemy_count": enemies.size(),
		"projectile_count": projectiles.size(),
		"wave_reward_money": wave_reward_money,
		"wave_reward_research": wave_reward_research,
		"map_name": map_record.get("name", ""),
		"tower_family": ARCHER_ID,
		"enemy_family": _wave_enemy_kind(),
		"selected_build_type": selected_build_type,
		"shop_button_count": get_shop_button_rects().size(),
	}


func serialize_run_state() -> Dictionary:
	return {
		"schema_version": 1,
		"map_name": str(map_record.get("name", "")),
		"money": money,
		"lives": lives,
		"research_points": research_points,
		"wave": wave,
		"wave_active": wave_active,
		"wave_complete": wave_complete,
		"spawned_this_wave": spawned_this_wave,
		"spawn_timer": spawn_timer,
		"leaks": leaks,
		"kills": kills,
		"wave_reward_money": wave_reward_money,
		"wave_reward_research": wave_reward_research,
		"selected_build_type": selected_build_type,
		"selected_tower_index": selected_tower_index,
		"towers": _serialize_towers(),
		"enemies": _serialize_enemies(),
		"projectiles": _serialize_projectiles(),
	}


func restore_run_state(state: Dictionary) -> bool:
	if int(state.get("schema_version", 0)) != 1:
		return false
	reset_slice()
	money = int(state.get("money", money))
	lives = int(state.get("lives", lives))
	research_points = int(state.get("research_points", research_points))
	wave = int(state.get("wave", wave))
	wave_active = bool(state.get("wave_active", wave_active))
	wave_complete = bool(state.get("wave_complete", wave_complete))
	spawned_this_wave = int(state.get("spawned_this_wave", spawned_this_wave))
	spawn_timer = float(state.get("spawn_timer", spawn_timer))
	leaks = int(state.get("leaks", leaks))
	kills = int(state.get("kills", kills))
	wave_reward_money = int(state.get("wave_reward_money", wave_reward_money))
	wave_reward_research = int(state.get("wave_reward_research", wave_reward_research))
	selected_build_type = str(state.get("selected_build_type", selected_build_type))
	towers = _restore_towers(state.get("towers", []))
	enemies = _restore_enemies(state.get("enemies", []))
	projectiles = _restore_projectiles(state.get("projectiles", []))
	var requested_selection: int = int(state.get("selected_tower_index", NO_SELECTED_TOWER))
	selected_tower_index = requested_selection if requested_selection >= 0 and requested_selection < towers.size() else NO_SELECTED_TOWER
	_emit_status()
	queue_redraw()
	return true


func _serialize_towers() -> Array:
	var records: Array = []
	for tower in towers:
		records.append({
			"type": str(tower.get("type", ARCHER_ID)),
			"position": _vector_to_array(tower.get("position", Vector2.ZERO)),
			"level": int(tower.get("level", 1)),
			"range": float(tower.get("range", 0.0)),
			"damage": float(tower.get("damage", 0.0)),
			"fire_rate": float(tower.get("fire_rate", 0.0)),
			"cooldown": float(tower.get("cooldown", 0.0)),
			"target_mode": str(tower.get("target_mode", "first")),
			"kills": int(tower.get("kills", 0)),
			"money_spent": int(tower.get("money_spent", 0)),
			"mutations": tower.get("mutations", []).duplicate(true),
			"selected_branch": str(tower.get("selected_branch", "")),
			"is_paragon": bool(tower.get("is_paragon", false)),
			"total_damage": float(tower.get("total_damage", 0.0)),
			"mastery_xp": float(tower.get("mastery_xp", 0.0)),
		})
	return records


func _restore_towers(records: Array) -> Array:
	var restored: Array = []
	for raw in records:
		if raw is Dictionary:
			restored.append(_tower_from_state(raw))
	return restored


func _tower_from_state(record: Dictionary) -> Dictionary:
	return {
		"type": str(record.get("type", ARCHER_ID)),
		"position": _array_to_vector(record.get("position", [0.0, 0.0])),
		"level": int(record.get("level", 1)),
		"range": float(record.get("range", 0.0)),
		"damage": float(record.get("damage", 0.0)),
		"fire_rate": float(record.get("fire_rate", 0.0)),
		"cooldown": float(record.get("cooldown", 0.0)),
		"target_mode": str(record.get("target_mode", "first")),
		"kills": int(record.get("kills", 0)),
		"money_spent": int(record.get("money_spent", 0)),
		"mutations": record.get("mutations", []).duplicate(true),
		"selected_branch": str(record.get("selected_branch", "")),
		"is_paragon": bool(record.get("is_paragon", false)),
		"total_damage": float(record.get("total_damage", 0.0)),
		"mastery_xp": float(record.get("mastery_xp", 0.0)),
	}


func _serialize_enemies() -> Array:
	var records: Array = []
	for enemy in enemies:
		records.append({
			"kind": str(enemy.get("kind", ENEMY_KIND)),
			"position": _vector_to_array(enemy.get("position", Vector2.ZERO)),
			"target_index": int(enemy.get("target_index", 1)),
			"hp": float(enemy.get("hp", 0.0)),
			"max_hp": float(enemy.get("max_hp", 0.0)),
			"speed": float(enemy.get("speed", 0.0)),
			"reward": int(enemy.get("reward", 0)),
			"reached_end": bool(enemy.get("reached_end", false)),
			"progress": float(enemy.get("progress", 0.0)),
			"marked_timer": float(enemy.get("marked_timer", 0.0)),
			"vulnerable_timer": float(enemy.get("vulnerable_timer", 0.0)),
			"flying": bool(enemy.get("flying", false)),
			"shield_hits": int(enemy.get("shield_hits", 0)),
			"max_shield_hits": int(enemy.get("max_shield_hits", 0)),
			"tags": enemy.get("tags", []).duplicate(true),
			"commander": bool(enemy.get("commander", false)),
		})
	return records


func _restore_enemies(records: Array) -> Array:
	var restored: Array = []
	for raw in records:
		if raw is Dictionary:
			restored.append(_enemy_from_state(raw))
	return restored


func _enemy_from_state(record: Dictionary) -> Dictionary:
	return {
		"kind": str(record.get("kind", ENEMY_KIND)),
		"position": _array_to_vector(record.get("position", [0.0, 0.0])),
		"target_index": int(record.get("target_index", 1)),
		"hp": float(record.get("hp", 0.0)),
		"max_hp": float(record.get("max_hp", 0.0)),
		"speed": float(record.get("speed", 0.0)),
		"reward": int(record.get("reward", 0)),
		"reached_end": bool(record.get("reached_end", false)),
		"progress": float(record.get("progress", 0.0)),
		"marked_timer": float(record.get("marked_timer", 0.0)),
		"vulnerable_timer": float(record.get("vulnerable_timer", 0.0)),
		"flying": bool(record.get("flying", false)),
		"shield_hits": int(record.get("shield_hits", 0)),
		"max_shield_hits": int(record.get("max_shield_hits", 0)),
		"tags": record.get("tags", []).duplicate(true),
		"commander": bool(record.get("commander", false)),
	}


func _serialize_projectiles() -> Array:
	var records: Array = []
	for projectile in projectiles:
		records.append({
			"position": _vector_to_array(projectile.get("position", Vector2.ZERO)),
			"target_index": enemies.find(projectile.get("target", {})),
			"tower_index": towers.find(projectile.get("tower", {})),
			"damage": float(projectile.get("damage", 0.0)),
			"speed": float(projectile.get("speed", 0.0)),
			"tower_type": str(projectile.get("tower_type", "")),
			"tower_level": int(projectile.get("tower_level", 1)),
			"trail_timer": float(projectile.get("trail_timer", 0.0)),
			"dead": bool(projectile.get("dead", false)),
		})
	return records


func _restore_projectiles(records: Array) -> Array:
	var restored: Array = []
	for raw in records:
		if not raw is Dictionary:
			continue
		var record: Dictionary = raw
		var target_index: int = int(record.get("target_index", -1))
		var tower_index: int = int(record.get("tower_index", -1))
		if target_index < 0 or target_index >= enemies.size():
			continue
		if tower_index < 0 or tower_index >= towers.size():
			continue
		restored.append({
			"position": _array_to_vector(record.get("position", [0.0, 0.0])),
			"target": enemies[target_index],
			"tower": towers[tower_index],
			"damage": float(record.get("damage", 0.0)),
			"speed": float(record.get("speed", _projectile_speed_for_tower(towers[tower_index]))),
			"tower_type": str(record.get("tower_type", towers[tower_index].get("type", ""))),
			"tower_level": int(record.get("tower_level", towers[tower_index].get("level", 1))),
			"trail_timer": float(record.get("trail_timer", 0.0)),
			"dead": bool(record.get("dead", false)),
		})
	return restored


func _vector_to_array(value: Variant) -> Array:
	if value is Vector2:
		return [value.x, value.y]
	return [0.0, 0.0]


func _array_to_vector(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _draw() -> void:
	_draw_map()
	_draw_build_site()
	_draw_entities()
	_draw_sidebar()


func _draw_map() -> void:
	var map_rect := Rect2(Vector2.ZERO, Vector2(float(config.get("map_width", 900)), float(config.get("height", 600))))
	var grass := _texture("sprites/terrain/grass.png")
	if grass != null:
		draw_texture_rect(grass, map_rect, true)
	else:
		draw_rect(map_rect, Color(0.09, 0.13, 0.10))
	for index in range(path_points.size() - 1):
		draw_line(path_points[index], path_points[index + 1], Color(0.34, 0.28, 0.21), float(config.get("path_width", 54)) + 8.0)
		draw_line(path_points[index], path_points[index + 1], Color(0.58, 0.48, 0.35), float(config.get("path_width", 54)))
	if not path_points.is_empty():
		if not _draw_texture_centered("sprites/terrain/spawn_gate.png", path_points[0], Vector2(44, 44)):
			draw_circle(path_points[0], 22.0, Color(0.25, 0.85, 0.50))
		if not _draw_texture_centered("sprites/terrain/base_gate.png", path_points[path_points.size() - 1], Vector2(44, 44)):
			draw_circle(path_points[path_points.size() - 1], 22.0, Color(0.95, 0.28, 0.23))


func _draw_build_site() -> void:
	if towers.is_empty() and not selected_build_type.is_empty():
		var color := Color(0.35, 0.75, 0.35, 0.5) if can_place_tower(RECOMMENDED_BUILD_SITE) else Color(0.9, 0.2, 0.2, 0.5)
		draw_circle(RECOMMENDED_BUILD_SITE, 18.0, color)
		draw_arc(RECOMMENDED_BUILD_SITE, float(config.get("base_tower_range", 145)) + 18.0, 0.0, TAU, 48, Color(0.45, 0.85, 0.45, 0.35), 1.0)


func _draw_entities() -> void:
	for index in range(towers.size()):
		var tower: Dictionary = towers[index]
		var position: Vector2 = tower["position"]
		draw_arc(position, float(tower["range"]), 0.0, TAU, 48, Color(0.45, 0.85, 0.45, 0.25), 1.0)
		if index == selected_tower_index:
			draw_circle(position, 23.0, Color(0.98, 0.92, 0.45, 0.28))
		var tower_tex := _animated_texture("towers", ARCHER_ID, ["idle_1", "idle_2"], 240)
		if tower_tex != null:
			_draw_texture(tower_tex, position, Vector2(42, 42))
		else:
			draw_circle(position, 18.0, _color_from_array(archer_data.get("color", [95, 185, 95])))
			draw_string(ThemeDB.fallback_font, position + Vector2(-8, 5), "A", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color.WHITE)
	for enemy in enemies:
		var position: Vector2 = enemy["position"]
		var enemy_kind := str(enemy.get("kind", ENEMY_KIND))
		var enemy_tex := _animated_texture("enemies", enemy_kind, ["walk_1", "walk_2"], 220)
		if enemy_tex != null:
			_draw_texture(enemy_tex, position, Vector2(34, 34))
		else:
			draw_circle(position, 13.0, Color(0.82, 0.20, 0.18))
		if int(enemy.get("shield_hits", 0)) > 0:
			draw_arc(position, 17.0, 0.0, TAU, 28, Color(0.62, 0.75, 1.0, 0.85), 2.0)
		var hp_ratio: float = max(0.0, float(enemy["hp"]) / float(enemy["max_hp"]))
		draw_rect(Rect2(position + Vector2(-16, -24), Vector2(32, 4)), Color(0.12, 0.12, 0.12))
		draw_rect(Rect2(position + Vector2(-16, -24), Vector2(32.0 * hp_ratio, 4)), Color(0.2, 0.85, 0.25))
	for projectile in projectiles:
		if not _draw_texture_centered("sprites/projectiles/archer.png", projectile["position"], Vector2(14, 14)):
			draw_circle(projectile["position"], 4.0, Color(0.95, 0.78, 0.35))


func _draw_sidebar() -> void:
	var x: float = float(config.get("map_width", 900))
	draw_rect(Rect2(Vector2(x, 0), Vector2(float(config.get("ui_width", 280)), float(config.get("height", 600)))), Color(0.10, 0.11, 0.13))
	_draw_shop_panel()
	if selected_tower_index != NO_SELECTED_TOWER:
		_draw_upgrade_panel()
		return
	var lines := [
		"Vertical Slice",
		"Map: %s" % map_record.get("name", "Classic Road"),
		"Tower: Archer",
		"Enemy: Normal",
		"Money: %s" % money,
		"Lives: %s" % lives,
		"Kills: %s / %s" % [kills, SLICE_SPAWN_LIMIT],
		"Wave: %s" % ("complete" if wave_complete else "active" if wave_active else "ready"),
		"Reward: +$%s +%s Tech" % [wave_reward_money, wave_reward_research],
	]
	for index in range(lines.size()):
		draw_string(ThemeDB.fallback_font, Vector2(x + 16, 310 + index * 24), lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(0.88, 0.90, 0.84))


func _draw_shop_panel() -> void:
	var x: float = float(config.get("map_width", GameConfig.MAP_WIDTH))
	var panel := Rect2(Vector2(x + 8, 96), Vector2(float(config.get("ui_width", GameConfig.UI_WIDTH)) - 16.0, 184.0))
	draw_rect(panel, Color(0.08, 0.10, 0.09))
	draw_rect(Rect2(panel.position, Vector2(panel.size.x, 4)), Color(0.38, 0.67, 0.74))
	draw_rect(Rect2(panel.position, panel.size), Color(0.27, 0.30, 0.26), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(x + 30, 119), "Build Towers", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(0.92, 0.92, 0.86))
	draw_string(ThemeDB.fallback_font, Vector2(panel.end.x - 56, 119), "Shop", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(0.72, 0.80, 0.74))
	for button in get_shop_button_rects():
		_draw_shop_button(button)
	var footer := Rect2(Vector2(panel.position.x + 10, panel.end.y - 24), Vector2(panel.size.x - 20, 16))
	draw_rect(footer, Color(0.10, 0.12, 0.11))
	draw_rect(footer, Color(0.24, 0.27, 0.24), false, 1.0)
	var footer_label := "Tap a tower to place" if selected_build_type.is_empty() else "Selected: %s" % _tower_label(selected_build_type)
	var footer_color := Color(0.74, 0.76, 0.72) if selected_build_type.is_empty() else _color_from_array(archer_data.get("color", [95, 185, 95]))
	draw_string(ThemeDB.fallback_font, footer.position + Vector2(8, 12), footer_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, footer_color)


func _draw_shop_button(button: Dictionary) -> void:
	var rect: Rect2 = button["rect"]
	var tower_type: String = str(button["tower_type"])
	var color := _color_from_array(baseline.get("towers", {}).get("tower_types", {}).get(tower_type, {}).get("color", [95, 185, 95]))
	var affordable: bool = bool(button["affordable"])
	var selected: bool = bool(button["selected"])
	var fill := Color(0.16, 0.24, 0.19) if selected else Color(0.11, 0.13, 0.12)
	if not affordable:
		fill = Color(0.19, 0.14, 0.14)
	var outline := color if affordable else Color(0.47, 0.27, 0.27)
	draw_rect(rect, fill)
	draw_rect(rect, outline, false, 2.0)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4)), outline)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(8, 18), str(button["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(0.96, 0.96, 0.92))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(rect.size.x - 38, 18), "$%s" % button["cost"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.88, 0.88, 0.80))


func _draw_upgrade_panel() -> void:
	var panel := get_upgrade_panel_rect()
	var snapshot := upgrade_panel_snapshot()
	if not bool(snapshot.get("visible", false)):
		return
	var accent := _color_from_array(archer_data.get("color", [95, 185, 95]))
	draw_rect(panel, Color(0.07, 0.09, 0.08))
	draw_rect(Rect2(panel.position, Vector2(panel.size.x, 4)), accent)
	draw_rect(panel, Color(0.30, 0.34, 0.28), false, 2.0)

	var header := Rect2(panel.position + Vector2(10, 8), Vector2(panel.size.x - 20, 44))
	draw_rect(header, Color(0.10, 0.12, 0.11))
	draw_rect(header, Color(0.42, 0.48, 0.38), false, 1.0)
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(14, 26), "T", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.82, 0.86, 0.78))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(34, 26), "U", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.82, 0.86, 0.78))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(56, 26), "Del", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.82, 0.86, 0.78))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(94, 26), "target | upgrade | sell", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.66, 0.69, 0.62))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(14, 48), str(snapshot["tower_name"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(0.96, 0.96, 0.92))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(14, 76), str(snapshot["stats"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.82, 0.82, 0.74))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(14, 96), str(snapshot["details"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.90, 0.86, 0.60))

	if bool(snapshot.get("needs_branch_choice", false)):
		var branch_notice := Rect2(panel.position + Vector2(14, 108), Vector2(panel.size.x - 28, 50))
		draw_rect(branch_notice, Color(0.18, 0.15, 0.10))
		draw_rect(branch_notice, Color(0.76, 0.68, 0.38), false, 2.0)
		draw_string(ThemeDB.fallback_font, branch_notice.position + Vector2(10, 20), "Branch", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.94, 0.86, 0.55))
		draw_string(ThemeDB.fallback_font, branch_notice.position + Vector2(10, 38), "Pick branch", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.78, 0.74, 0.62))
	else:
		for option_rect in get_upgrade_button_rects():
			_draw_upgrade_button(option_rect)

	_draw_target_button()
	_draw_sell_button()


func _draw_upgrade_button(rect: Rect2) -> void:
	var snapshot := upgrade_panel_snapshot()
	var options: Array = snapshot.get("upgrade_options", [])
	if options.is_empty():
		return
	var option: Dictionary = options[0]
	var enabled: bool = bool(option.get("enabled", false))
	var fill := Color(0.16, 0.20, 0.15) if enabled else Color(0.19, 0.14, 0.14)
	var outline := _color_from_array(archer_data.get("color", [95, 185, 95])) if enabled else Color(0.47, 0.27, 0.27)
	draw_rect(rect, fill)
	draw_rect(rect, outline, false, 2.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 20), str(option["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.94, 0.94, 0.88))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(rect.size.x - 58, 20), "$%s" % option["cost"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(0.88, 0.88, 0.80))


func get_upgrade_button_rects() -> Array:
	var panel := get_upgrade_panel_rect()
	var snapshot := upgrade_panel_snapshot()
	var options: Array = snapshot.get("upgrade_options", [])
	if bool(snapshot.get("needs_branch_choice", false)) or options.is_empty():
		return []
	return [Rect2(panel.position + Vector2(14, 108), Vector2(panel.size.x - 28, 48))]


func _draw_target_button() -> void:
	var rect := get_target_button_rect()
	var snapshot := upgrade_panel_snapshot()
	draw_rect(rect, Color(0.13, 0.17, 0.20))
	draw_rect(rect, Color(0.43, 0.59, 0.75), false, 2.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(12, 20), str(snapshot["target_label"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.88, 0.92, 0.96))


func _draw_sell_button() -> void:
	var rect := get_sell_button_rect()
	var snapshot := upgrade_panel_snapshot()
	draw_rect(rect, Color(0.20, 0.15, 0.13))
	draw_rect(rect, Color(0.84, 0.49, 0.33), false, 2.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(12, 20), str(snapshot["sell_label"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(1.0, 0.90, 0.82))


func _emit_status() -> void:
	status_changed.emit({
		"title": GameConfig.GAME_TITLE,
		"version": GameConfig.GODOT_VERSION_PIN,
		"phase": "vertical slice",
		"gameplay": "%s / Archer / Normal / %s" % [map_record.get("name", "Classic Road"), "complete" if wave_complete else "ready"],
	})


func _credit_tower_kill(enemy: Dictionary) -> void:
	var best: Dictionary = {}
	for tower in towers:
		if best.is_empty() or tower["position"].distance_to(enemy["position"]) < best["position"].distance_to(enemy["position"]):
			best = tower
	if not best.is_empty():
		best["kills"] = int(best["kills"]) + 1


func _enemy_progress(enemy: Dictionary) -> float:
	var total := 0.0
	var target_index: int = int(enemy["target_index"])
	for index in range(1, min(target_index, path_points.size())):
		total += path_points[index - 1].distance_to(path_points[index])
	if target_index > 0 and target_index < path_points.size():
		total += path_points[target_index - 1].distance_to(enemy["position"])
	return total


func _points_from_path(raw_path: Array) -> Array:
	var result: Array = []
	for point in raw_path:
		result.append(Vector2(float(point[0]), float(point[1])))
	return result


func _distance_point_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment: Vector2 = end - start
	if segment.length_squared() == 0.0:
		return point.distance_to(start)
	var t: float = clamp((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * t)


func _new_run_defaults() -> Dictionary:
	var progress := _progress()
	if progress != null:
		return progress.new_run_defaults()
	return {
		"money": int(config.get("starting_money", GameConfig.STARTING_MONEY)),
		"lives": int(config.get("starting_lives", GameConfig.STARTING_LIVES)),
		"research_points": 0,
		"reward_card_choice_bonus": 0,
		"tower_damage_multiplier": 1.0,
	}


func _progress() -> Node:
	if progress_override != null:
		return progress_override
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/GameProgress")


func _color_from_array(values: Array) -> Color:
	return Color(float(values[0]) / 255.0, float(values[1]) / 255.0, float(values[2]) / 255.0)


func _assets() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/GameAssets")


func _audio() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/GameAudio")


func _texture(relative_path: String) -> Texture2D:
	var assets := _assets()
	if assets == null:
		return null
	return assets.texture(relative_path)


func _animated_texture(category: String, key: String, frames: Array, frame_ms: int) -> Texture2D:
	var assets := _assets()
	if assets == null:
		return null
	return assets.animation_frame(category, key, frames, frame_ms)


func _draw_texture_centered(relative_path: String, center: Vector2, size: Vector2) -> bool:
	var tex := _texture(relative_path)
	if tex == null:
		return false
	_draw_texture(tex, center, size)
	return true


func _draw_texture(tex: Texture2D, center: Vector2, size: Vector2) -> void:
	draw_texture_rect(tex, Rect2(center - size * 0.5, size), false)


func _play_sound(relative_path: String, fallback_frequency: float) -> void:
	var audio := _audio()
	if audio != null:
		audio.play_sound(relative_path, fallback_frequency)
