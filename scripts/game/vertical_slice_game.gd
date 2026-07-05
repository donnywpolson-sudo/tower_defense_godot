extends Node2D

signal status_changed(status: Dictionary)

const ARCHER_ID := "archer"
const ENEMY_KIND := "normal"
const CANONICAL_ENEMY_KINDS := ["normal", "fast", "tank", "swarm", "shield", "flying", "armored", "commander"]
const BASIC_SLICE_TOWER_IDS := ["archer", "machine_gun", "cannon", "sniper", "tesla"]
const SLICE_SPAWN_LIMIT := 3
const PROJECTILE_HIT_DISTANCE := 8.0
const RECOMMENDED_BUILD_SITE := Vector2(300, 243)
const SHOP_BUTTON_SIZE := Vector2(78, 25)
const SHOP_BUTTON_GAP := 4.0
const BOTTOM_LAYOUT_MIN_HEIGHT := 780.0
const BOTTOM_DOCK_HEIGHT := 188.0
const BOTTOM_DOCK_PADDING := 10.0
const BOTTOM_DOCK_GAP := 10.0
const NO_SELECTED_TOWER := -1
const GAME_SPEEDS := [0.0, 1.0, 2.0, 4.0]
const GAME_SPEED_LABELS := ["Pause", "1x", "2x", "4x"]
const MAX_SIMULATION_STEP := 0.05
const INVARIANT_CHECK_INTERVAL := 0.25
const DEBUG_COMMAND_NAMES := ["give_money", "set_wave", "spawn_enemy", "kill_all_enemies", "skip_wave"]
const FOCUS_DISPLAY_NAME_OVERRIDES := {
	"ammo_fabricator": "Ammo",
	"battery_grid": "Battery",
	"chain_lightning": "Chain",
	"magnet_tech": "Magnet",
	"mercenary_guild": "Mercenary",
	"plague_mist": "Plague",
	"research_lab": "Research",
	"signal_tower": "Signal",
	"time_control": "Stasis",
	"time_lag": "Echo",
	"venom_cask": "Venom",
	"war_banner": "Banner",
}

var game_data: Dictionary = {}
var config: Dictionary = {}
var map_record: Dictionary = {}
var path_points: Array = []
var wave_row: Dictionary = {}

var money: int = 0
var lives: int = 0
var research_points: int = 0
var wave: int = 1
var wave_active: bool = false
var wave_complete: bool = false
var game_over: bool = false
var spawned_this_wave: int = 0
var spawn_timer: float = 0.0
var leaks: int = 0
var kills: int = 0
var wave_reward_money: int = 0
var wave_reward_research: int = 0
var selected_build_type: String = ""
var selected_tower_index: int = NO_SELECTED_TOWER
var game_speed: float = 1.0
var debug_overlay_enabled: bool = false
var latest_feedback: Dictionary = {}

var towers: Array = []
var enemies: Array = []
var projectiles: Array = []
var progress_override: Node = null
var layout_viewport_override: Vector2 = Vector2.ZERO
var invariant_check_timer: float = 0.0


func _ready() -> void:
	reset_slice()
	set_process(true)


func reset_slice() -> void:
	game_data = GameData.load_game_data()
	config = game_data.get("config", {})
	map_record = game_data.get("maps", {}).get("catalog", [])[0]
	path_points = _points_from_path(map_record.get("paths", [[[]]])[0])
	var run_defaults := _new_run_defaults()
	money = int(run_defaults.get("money", config.get("starting_money", GameConfig.STARTING_MONEY)))
	lives = int(run_defaults.get("lives", config.get("starting_lives", GameConfig.STARTING_LIVES)))
	research_points = int(run_defaults.get("research_points", 0))
	wave = 1
	_refresh_wave_row()
	wave_active = false
	wave_complete = false
	game_over = false
	spawned_this_wave = 0
	spawn_timer = 0.0
	leaks = 0
	kills = 0
	wave_reward_money = 0
	wave_reward_research = 0
	selected_build_type = ""
	selected_tower_index = NO_SELECTED_TOWER
	game_speed = _progress_game_speed()
	latest_feedback = {}
	invariant_check_timer = 0.0
	towers = []
	enemies = []
	projectiles = []
	_emit_status()
	_check_runtime_invariants("reset_slice")
	queue_redraw()


func place_archer(site: Vector2 = RECOMMENDED_BUILD_SITE) -> bool:
	return place_selected_tower(site, ARCHER_ID)


func place_selected_tower(site: Vector2, tower_type: String = "") -> bool:
	var keep_build_selection: bool = tower_type.is_empty()
	if tower_type.is_empty():
		tower_type = selected_build_type
	var preview := placement_preview_snapshot(site, tower_type)
	if not bool(preview.get("can_place", false)):
		_set_feedback("placement", str(preview.get("disabled_reason", "Cannot place there")))
		return false
	var snapped_site: Vector2 = preview["snapped_site"]
	var cost: int = _shop_cost(tower_type)
	money -= cost
	var run_defaults := _new_run_defaults()
	var damage_multiplier: float = float(run_defaults.get("tower_damage_multiplier", 1.0))
	var starting_level := 1
	var tower := {
		"type": tower_type,
		"position": snapped_site,
		"level": starting_level,
		"range": _basic_slice_tower_range(tower_type, starting_level),
		"damage": _basic_slice_tower_damage(tower_type, starting_level) * damage_multiplier,
		"fire_rate": _basic_slice_tower_fire_rate(tower_type, starting_level),
		"cooldown": 0.0,
		"target_mode": "first",
		"kills": 0,
		"money_spent": cost,
		"mutations": [],
		"selected_branch": "",
		"is_paragon": false,
	}
	towers.append(tower)
	if keep_build_selection:
		selected_build_type = tower_type
		selected_tower_index = NO_SELECTED_TOWER
	else:
		selected_tower_index = towers.size() - 1
	if not keep_build_selection and selected_build_type == tower_type:
		selected_build_type = ""
	_clear_feedback()
	_play_sound("sounds/ui/build.wav", 360.0)
	_emit_status()
	_check_runtime_invariants("place_selected_tower")
	queue_redraw()
	return true


func can_place_tower(site: Vector2) -> bool:
	return bool(placement_preview_snapshot(site).get("can_place", false))


func _can_place_tower_site(site: Vector2) -> bool:
	return _placement_site_disabled_reason(site).is_empty()


func placement_preview_snapshot(site: Vector2, tower_type: String = "") -> Dictionary:
	var resolved_type := tower_type if not tower_type.is_empty() else selected_build_type
	var snapped_site := Vector2.INF if site == Vector2.INF else _snap_to_build_grid(site)
	var cost := _shop_cost(resolved_type) if not resolved_type.is_empty() else 0
	var reason := _placement_disabled_reason(snapped_site, resolved_type)
	return {
		"tower_type": resolved_type,
		"site": site,
		"snapped_site": snapped_site,
		"cost": cost,
		"affordable": cost > 0 and money >= cost,
		"can_place": reason.is_empty(),
		"disabled_reason": reason,
	}


func _placement_disabled_reason(site: Vector2, tower_type: String) -> String:
	if game_over:
		return "Game over"
	if tower_type.is_empty():
		return "Choose a tower first"
	if not _is_enabled_slice_shop_tower(tower_type):
		return "Not in this slice"
	var cost := _shop_cost(tower_type)
	if money < cost:
		return "Need $%s" % cost
	return _placement_site_disabled_reason(site)


func _placement_site_disabled_reason(site: Vector2) -> String:
	if site == Vector2.INF or is_inf(site.x) or is_inf(site.y):
		return "Outside build area"
	var half_tile: float = float(config.get("build_tile_size", 54)) * 0.5
	if site.x < half_tile or site.x > float(config.get("map_width", GameConfig.MAP_WIDTH)) - half_tile:
		return "Outside build area"
	if site.y < float(config.get("build_grid_top", 81)) + half_tile or site.y > float(config.get("height", GameConfig.LOGICAL_HEIGHT)) - half_tile:
		return "Outside build area"
	for tower in towers:
		if site.distance_to(tower["position"]) < float(config.get("build_tile_size", 54)):
			return "Tile occupied"
	var blocked_distance: float = float(config.get("path_width", 54)) / 2.0 + float(config.get("build_tile_size", 54)) / 2.0
	for index in range(path_points.size() - 1):
		if _distance_point_to_segment(site, path_points[index], path_points[index + 1]) < blocked_distance:
			return "Blocked by path"
	return ""


func _build_grid_step() -> float:
	return max(1.0, float(config.get("build_grid_step", 27)))


func _snap_to_build_grid(site: Vector2) -> Vector2:
	var step := _build_grid_step()
	return Vector2(round(site.x / step) * step, round(site.y / step) * step)


func start_wave() -> bool:
	var disabled_reason := _wave_start_disabled_reason()
	if not disabled_reason.is_empty():
		_set_feedback("wave", disabled_reason)
		return false
	if wave_complete and not advance_to_next_wave():
		_set_feedback("wave", _wave_start_disabled_reason())
		return false
	_refresh_wave_row()
	wave_active = true
	spawn_timer = 0.0
	spawned_this_wave = 0
	_clear_feedback()
	_play_sound("sounds/ui/wave.wav", 480.0)
	_emit_status()
	_check_runtime_invariants("start_wave")
	return true


func advance_to_next_wave() -> bool:
	if game_over or wave_active or not wave_complete:
		return false
	var schedule: Array = _wave_schedule()
	if wave >= schedule.size():
		return false
	wave += 1
	_refresh_wave_row()
	wave_complete = false
	spawned_this_wave = 0
	spawn_timer = 0.0
	leaks = 0
	kills = 0
	wave_reward_money = 0
	wave_reward_research = 0
	enemies = []
	projectiles = []
	_emit_status()
	_check_runtime_invariants("advance_to_next_wave")
	return true


func set_tower_target_mode(index: int, target_mode: String) -> bool:
	if index < 0 or index >= towers.size():
		return false
	var target_modes: Array = game_data.get("towers", {}).get("target_modes", [])
	if not target_modes.has(target_mode):
		return false
	towers[index]["target_mode"] = target_mode
	_emit_status()
	_check_runtime_invariants("set_tower_target_mode")
	return true


func process_step(delta: float) -> void:
	if game_over:
		_tick_runtime_invariants(delta, "process_step_game_over")
		queue_redraw()
		return
	if wave_active:
		_update_spawning(delta)
	_update_enemies(delta)
	if game_over:
		_tick_runtime_invariants(delta, "process_step_game_over")
		queue_redraw()
		return
	_update_towers(delta)
	_update_projectiles(delta)
	_check_wave_completion()
	_tick_runtime_invariants(delta, "process_step")
	queue_redraw()


func _process(delta: float) -> void:
	_process_scaled_delta(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start_wave"):
		start_wave()
	if event.is_action_pressed("pause_game"):
		set_game_speed(0.0 if game_speed > 0.0 else 1.0)
	if event.is_action_pressed("speed_1"):
		set_game_speed(1.0)
	if event.is_action_pressed("speed_2"):
		set_game_speed(2.0)
	if event.is_action_pressed("speed_3"):
		set_game_speed(4.0)
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F3:
			toggle_debug_overlay()
			return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			if cancel_build_selection():
				return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if handle_game_over_click(mouse_event.position):
				return
			if handle_speed_control_click(mouse_event.position):
				return
			if handle_wave_control_click(mouse_event.position):
				return
			if handle_shop_click(mouse_event.position):
				return
			if handle_upgrade_panel_click(mouse_event.position):
				return
			handle_map_click(mouse_event.position)


func _process_scaled_delta(delta: float) -> void:
	if game_speed <= 0.0:
		queue_redraw()
		return
	var remaining: float = min(delta * game_speed, MAX_SIMULATION_STEP * max(1.0, game_speed) * 2.0)
	while remaining > 0.0:
		var step: float = min(MAX_SIMULATION_STEP, remaining)
		process_step(step)
		remaining -= step


func cancel_build_selection() -> bool:
	if selected_build_type.is_empty():
		return false
	selected_build_type = ""
	_clear_feedback()
	_emit_status()
	queue_redraw()
	return true


func handle_wave_control_click(pos: Vector2) -> bool:
	if not get_start_wave_button_rect().has_point(pos):
		return false
	start_wave()
	return true


func handle_speed_control_click(pos: Vector2) -> bool:
	for button in get_speed_button_rects():
		var rect: Rect2 = button["rect"]
		if rect.has_point(pos):
			set_game_speed(float(button["speed"]))
			return true
	return false


func handle_game_over_click(pos: Vector2) -> bool:
	if not game_over:
		return false
	if get_game_over_restart_rect().has_point(pos):
		reset_slice()
	return true


func handle_shop_click(pos: Vector2) -> bool:
	if game_over:
		return false
	for button in get_shop_button_rects():
		var rect: Rect2 = button["rect"]
		if rect.has_point(pos):
			if bool(button.get("enabled", false)):
				selected_build_type = str(button["tower_type"])
				selected_tower_index = NO_SELECTED_TOWER
				_clear_feedback()
				_emit_status()
				queue_redraw()
			return true
	return false


func handle_map_click(pos: Vector2) -> bool:
	if game_over:
		return false
	var map_pos := screen_to_map_position(pos)
	if map_pos == Vector2.INF:
		if not selected_build_type.is_empty():
			_set_feedback("placement", "Outside build area")
		return false
	if not selected_build_type.is_empty():
		return place_selected_tower(map_pos)
	var tower_index: int = _tower_index_at(map_pos)
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
	for branch_button in get_branch_button_rects():
		var branch_rect: Rect2 = branch_button["rect"]
		if branch_rect.has_point(pos):
			choose_selected_tower_branch(str(branch_button["branch_id"]))
			return true
	for option_rect in get_upgrade_button_rects():
		if option_rect.has_point(pos):
			upgrade_selected_tower()
			return true
	return true


func select_shop_tower(tower_type: String) -> bool:
	if game_over:
		return false
	if not _is_enabled_slice_shop_tower(tower_type):
		return false
	selected_build_type = tower_type
	selected_tower_index = NO_SELECTED_TOWER
	_clear_feedback()
	_emit_status()
	queue_redraw()
	return true


func set_layout_viewport_override_for_tests(size: Vector2) -> void:
	layout_viewport_override = size
	queue_redraw()


func clear_layout_viewport_override_for_tests() -> void:
	layout_viewport_override = Vector2.ZERO
	queue_redraw()


func layout_snapshot() -> Dictionary:
	return _layout_metrics()


func map_to_screen_position(site: Vector2) -> Vector2:
	var metrics := _layout_metrics()
	var map_rect: Rect2 = metrics["map_rect"]
	var map_scale: float = float(metrics["map_scale"])
	return map_rect.position + site * map_scale


func screen_to_map_position(pos: Vector2) -> Vector2:
	var metrics := _layout_metrics()
	var map_rect: Rect2 = metrics["map_rect"]
	if not map_rect.has_point(pos):
		return Vector2.INF
	return (pos - map_rect.position) / max(0.001, float(metrics["map_scale"]))


func _layout_viewport_size() -> Vector2:
	if layout_viewport_override.x > 0.0 and layout_viewport_override.y > 0.0:
		return layout_viewport_override
	var viewport_size := get_viewport_rect().size if is_inside_tree() else Vector2.ZERO
	return Vector2(
		max(viewport_size.x, float(config.get("width", GameConfig.LOGICAL_WIDTH))),
		max(viewport_size.y, float(config.get("height", GameConfig.LOGICAL_HEIGHT)))
	)


func _uses_bottom_dock_layout() -> bool:
	return _layout_viewport_size().y >= BOTTOM_LAYOUT_MIN_HEIGHT


func _game_data_map_size() -> Vector2:
	return Vector2(
		float(config.get("map_width", GameConfig.MAP_WIDTH)),
		float(config.get("height", GameConfig.LOGICAL_HEIGHT))
	)


func _layout_metrics() -> Dictionary:
	var viewport_size := _layout_viewport_size()
	var game_data_map_size := _game_data_map_size()
	var mode := "sidebar"
	var map_scale := 1.0
	var map_rect := Rect2(Vector2.ZERO, game_data_map_size)
	var dock_rect := Rect2()
	var sidebar_rect := Rect2(
		Vector2(game_data_map_size.x, 0.0),
		Vector2(float(config.get("ui_width", GameConfig.UI_WIDTH)), game_data_map_size.y)
	)
	var build_panel_rect := Rect2(
		sidebar_rect.position + Vector2(8.0, 96.0),
		Vector2(sidebar_rect.size.x - 16.0, 204.0)
	)
	var wave_panel_rect := Rect2(
		sidebar_rect.position + Vector2(8.0, 210.0),
		Vector2(sidebar_rect.size.x - 16.0, 76.0)
	)
	var detail_panel_rect := Rect2(
		sidebar_rect.position + Vector2(14.0, 304.0),
		Vector2(sidebar_rect.size.x - 28.0, 190.0)
	)
	var upgrade_panel_rect := Rect2(
		sidebar_rect.position + Vector2(8.0, 286.0),
		Vector2(sidebar_rect.size.x - 16.0, 304.0)
	)

	if viewport_size.y >= BOTTOM_LAYOUT_MIN_HEIGHT:
		mode = "bottom_dock"
		dock_rect = Rect2(Vector2(0.0, viewport_size.y - BOTTOM_DOCK_HEIGHT), Vector2(viewport_size.x, BOTTOM_DOCK_HEIGHT))
		var map_area := Rect2(Vector2.ZERO, Vector2(viewport_size.x, max(1.0, dock_rect.position.y)))
		map_scale = min(map_area.size.x / game_data_map_size.x, map_area.size.y / game_data_map_size.y)
		map_scale = max(0.001, map_scale)
		var scaled_map_size := game_data_map_size * map_scale
		map_rect = Rect2(
			map_area.position + (map_area.size - scaled_map_size) * 0.5,
			scaled_map_size
		)
		var panel_height: float = dock_rect.size.y - BOTTOM_DOCK_PADDING * 2.0
		var build_width: float = min(430.0, max(390.0, viewport_size.x * 0.36))
		var wave_width: float = min(220.0, max(180.0, viewport_size.x * 0.16))
		build_panel_rect = Rect2(
			dock_rect.position + Vector2(BOTTOM_DOCK_PADDING, BOTTOM_DOCK_PADDING),
			Vector2(build_width, panel_height)
		)
		wave_panel_rect = Rect2(
			Vector2(build_panel_rect.end.x + BOTTOM_DOCK_GAP, dock_rect.position.y + BOTTOM_DOCK_PADDING),
			Vector2(wave_width, panel_height)
		)
		detail_panel_rect = Rect2(
			Vector2(wave_panel_rect.end.x + BOTTOM_DOCK_GAP, dock_rect.position.y + BOTTOM_DOCK_PADDING),
			Vector2(max(320.0, viewport_size.x - wave_panel_rect.end.x - BOTTOM_DOCK_GAP - BOTTOM_DOCK_PADDING), panel_height)
		)
		upgrade_panel_rect = detail_panel_rect
		sidebar_rect = Rect2()

	return {
		"mode": mode,
		"viewport_size": viewport_size,
		"map_rect": map_rect,
		"map_origin": map_rect.position,
		"map_scale": map_scale,
		"dock_rect": dock_rect,
		"sidebar_rect": sidebar_rect,
		"build_panel_rect": build_panel_rect,
		"shop_panel_rect": build_panel_rect,
		"wave_panel_rect": wave_panel_rect,
		"detail_panel_rect": detail_panel_rect,
		"run_status_panel_rect": detail_panel_rect,
		"upgrade_panel_rect": upgrade_panel_rect,
	}


func get_shop_button_rects() -> Array:
	var rects: Array = []
	var metrics := _layout_metrics()
	var panel: Rect2 = metrics["shop_panel_rect"]
	var columns := 3
	var gap := SHOP_BUTTON_GAP
	var button_size := SHOP_BUTTON_SIZE
	var start_x: float = float(config.get("map_width", GameConfig.MAP_WIDTH)) + 14.0
	var start_y: float = 126.0
	if str(metrics["mode"]) == "bottom_dock":
		columns = 4
		gap = 6.0
		button_size = Vector2((panel.size.x - 28.0 - gap * float(columns - 1)) / float(columns), 28.0)
		start_x = panel.position.x + 14.0
		start_y = panel.position.y + 42.0
	for index in range(_current_slice_shop_towers().size()):
		var tower_type: String = _current_slice_shop_towers()[index]
		var col: int = index % columns
		var row: int = int(index / columns)
		var rect := Rect2(
			Vector2(start_x + col * (button_size.x + gap), start_y + row * (button_size.y + gap)),
			button_size
		)
		var enabled: bool = _is_enabled_slice_shop_tower(tower_type)
		rects.append({
			"rect": rect,
			"tower_type": tower_type,
			"label": _tower_label(tower_type),
			"short_label": _tower_shop_label(tower_type),
			"cost": _shop_cost(tower_type),
			"selected": selected_build_type == tower_type,
			"affordable": money >= _shop_cost(tower_type),
			"enabled": enabled,
			"disabled_reason": "" if enabled else "Not in this slice",
		})
	return rects


func shop_snapshot() -> Dictionary:
	var buttons: Array = []
	for button in get_shop_button_rects():
		buttons.append({
			"tower_type": button["tower_type"],
			"label": button["label"],
			"short_label": button["short_label"],
			"cost": button["cost"],
			"selected": button["selected"],
			"affordable": button["affordable"],
			"enabled": button["enabled"],
			"disabled_reason": button["disabled_reason"],
		})
	return {
		"selected_build_type": selected_build_type,
		"button_count": buttons.size(),
		"buttons": buttons,
		"start_wave_control": wave_control_snapshot(),
		"speed_control": speed_control_snapshot(),
		"canonical_shop_order": game_data.get("towers", {}).get("shop_order", []),
	}


func get_start_wave_button_rect() -> Rect2:
	var metrics := _layout_metrics()
	if str(metrics["mode"]) == "bottom_dock":
		var panel: Rect2 = metrics["wave_panel_rect"]
		return Rect2(panel.position + Vector2(14.0, 42.0), Vector2(panel.size.x - 28.0, 32.0))
	var x: float = float(config.get("map_width", GameConfig.MAP_WIDTH))
	return Rect2(
		Vector2(x + 18.0, 218.0),
		Vector2(float(config.get("ui_width", GameConfig.UI_WIDTH)) - 36.0, 28.0)
	)


func get_game_over_restart_rect() -> Rect2:
	var viewport_size := _layout_viewport_size()
	var width: float = viewport_size.x
	var height: float = viewport_size.y
	return Rect2(Vector2(width * 0.5 - 88.0, height * 0.5 + 42.0), Vector2(176.0, 34.0))


func get_speed_button_rects() -> Array:
	var rects: Array = []
	var metrics := _layout_metrics()
	var x: float = float(config.get("map_width", GameConfig.MAP_WIDTH)) + 18.0
	var y := 252.0
	var gap := 6.0
	var width := 56.0
	var height := 24.0
	if str(metrics["mode"]) == "bottom_dock":
		var panel: Rect2 = metrics["wave_panel_rect"]
		x = panel.position.x + 14.0
		y = get_start_wave_button_rect().end.y + 12.0
		width = (panel.size.x - 28.0 - gap * float(GAME_SPEEDS.size() - 1)) / float(GAME_SPEEDS.size())
		height = 26.0
	for index in range(GAME_SPEEDS.size()):
		rects.append({
			"rect": Rect2(Vector2(x + index * (width + gap), y), Vector2(width, height)),
			"speed": float(GAME_SPEEDS[index]),
			"label": str(GAME_SPEED_LABELS[index]),
			"selected": is_equal_approx(game_speed, float(GAME_SPEEDS[index])),
		})
	return rects


func wave_control_snapshot() -> Dictionary:
	var next_wave: int = wave + 1 if wave_complete else wave
	var disabled_reason := _wave_start_disabled_reason()
	return {
		"label": _wave_control_label(),
		"enabled": disabled_reason.is_empty(),
		"disabled_reason": disabled_reason,
		"rect": get_start_wave_button_rect(),
		"wave": wave,
		"next_wave": next_wave,
		"wave_active": wave_active,
		"wave_complete": wave_complete,
		"game_over": game_over,
		"has_tower": not towers.is_empty(),
	}


func speed_control_snapshot() -> Dictionary:
	var buttons: Array = []
	for button in get_speed_button_rects():
		buttons.append({
			"speed": button["speed"],
			"label": button["label"],
			"selected": button["selected"],
		})
	return {
		"speed": game_speed,
		"label": _game_speed_label(),
		"buttons": buttons,
	}


func get_upgrade_panel_rect() -> Rect2:
	return _layout_metrics()["upgrade_panel_rect"]


func get_target_button_rect() -> Rect2:
	var panel := get_upgrade_panel_rect()
	if _uses_bottom_dock_layout():
		var width := (panel.size.x - 34.0) * 0.5
		return Rect2(Vector2(panel.position.x + 14.0, panel.end.y - 34.0), Vector2(width, 24.0))
	return Rect2(Vector2(panel.position.x + 14.0, panel.end.y - 60.0), Vector2(panel.size.x - 28.0, 24.0))


func get_sell_button_rect() -> Rect2:
	var panel := get_upgrade_panel_rect()
	if _uses_bottom_dock_layout():
		var width := (panel.size.x - 34.0) * 0.5
		return Rect2(Vector2(panel.position.x + 20.0 + width, panel.end.y - 34.0), Vector2(width, 24.0))
	return Rect2(Vector2(panel.position.x + 14.0, panel.end.y - 30.0), Vector2(panel.size.x - 28.0, 24.0))


func upgrade_panel_snapshot() -> Dictionary:
	var tower := _selected_tower()
	if tower.is_empty():
		return {
			"visible": false,
			"selected_tower_index": selected_tower_index,
		}
	var needs_branch: bool = _tower_needs_branch_choice(tower)
	var options: Array = [] if needs_branch else _upgrade_options_for_tower(tower)
	var selected_branch: String = str(tower.get("selected_branch", ""))
	return {
		"visible": true,
		"selected_tower_index": selected_tower_index,
		"tower_type": tower.get("type", ""),
		"tower_name": _tower_display_name(tower),
		"stats": _tower_stat_text(tower),
		"stat_detail": tower_stat_snapshot(tower),
		"details": _tower_detail_text(tower),
		"target_label": "Target %s" % str(tower.get("target_mode", "first")).capitalize(),
		"target_mode": tower.get("target_mode", "first"),
		"sell_label": "Sell +$%s" % _sell_refund(tower),
		"sell_refund": _sell_refund(tower),
		"selected_branch": selected_branch,
		"selected_branch_name": _selected_branch_name(tower),
		"needs_branch_choice": needs_branch,
		"branch_options": _branch_options_for_tower(tower),
		"upgrade_options": options,
	}


func cycle_selected_target_mode() -> bool:
	var tower := _selected_tower()
	if tower.is_empty():
		return false
	var target_modes: Array = game_data.get("towers", {}).get("target_modes", [])
	if target_modes.is_empty():
		return false
	var current_mode: String = str(tower.get("target_mode", "first"))
	var index: int = target_modes.find(current_mode)
	if index == -1:
		index = 0
	tower["target_mode"] = target_modes[(index + 1) % target_modes.size()]
	_emit_status()
	_check_runtime_invariants("cycle_selected_target_mode")
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
	_check_runtime_invariants("sell_selected_tower")
	queue_redraw()
	return true


func set_game_speed(speed: float) -> bool:
	if not GAME_SPEEDS.has(speed):
		return false
	game_speed = speed
	var progress := _progress()
	if progress != null:
		progress.settings["game_speed"] = game_speed
	_emit_status()
	_check_runtime_invariants("set_game_speed")
	queue_redraw()
	return true


func choose_selected_tower_branch(branch_id: String) -> bool:
	var tower := _selected_tower()
	if tower.is_empty() or not _tower_needs_branch_choice(tower):
		return false
	for option in _branch_options_for_tower(tower):
		if str(option.get("id", "")) == branch_id:
			tower["selected_branch"] = branch_id
			_clear_feedback()
			_play_sound("sounds/ui/build.wav", 390.0)
			_emit_status()
			_check_runtime_invariants("choose_selected_tower_branch")
			queue_redraw()
			return true
	return false


func upgrade_selected_tower() -> bool:
	var tower := _selected_tower()
	if tower.is_empty() or _tower_needs_branch_choice(tower):
		_set_feedback("upgrade", "Choose a focus first" if not tower.is_empty() else "Select a tower first")
		return false
	var options := _upgrade_options_for_tower(tower)
	if options.is_empty():
		_set_feedback("upgrade", "No upgrade available")
		return false
	var option: Dictionary = options[0]
	if not bool(option.get("enabled", false)):
		_set_feedback("upgrade", str(option.get("disabled_reason", "Upgrade unavailable")))
		return false
	var cost: int = int(option.get("cost", 0))
	var next_level: int = int(tower.get("level", 1)) + 1
	var tower_type: String = str(tower.get("type", ARCHER_ID))
	var run_defaults := _new_run_defaults()
	var damage_multiplier: float = float(run_defaults.get("tower_damage_multiplier", 1.0))
	money -= cost
	tower["level"] = next_level
	tower["money_spent"] = int(tower.get("money_spent", 0)) + cost
	tower["range"] = _basic_slice_tower_range(tower_type, next_level)
	tower["damage"] = _basic_slice_tower_damage(tower_type, next_level) * damage_multiplier
	tower["fire_rate"] = _basic_slice_tower_fire_rate(tower_type, next_level)
	_clear_feedback()
	_play_sound("sounds/ui/build.wav", 420.0)
	_emit_status()
	_check_runtime_invariants("upgrade_selected_tower")
	queue_redraw()
	return true


func _current_slice_shop_towers() -> Array:
	var root_ids: Array = game_data.get("towers", {}).get("root_tower_ids", [])
	var shop_order: Array = game_data.get("towers", {}).get("shop_order", [])
	var ordered: Array = []
	for tower_id in root_ids:
		if str(tower_id) == ARCHER_ID:
			ordered.append(ARCHER_ID)
	for tower_id in shop_order:
		var tower_type := str(tower_id)
		if root_ids.has(tower_type) and not ordered.has(tower_type):
			ordered.append(tower_type)
	for tower_id in root_ids:
		var tower_type := str(tower_id)
		if not ordered.has(tower_type):
			ordered.append(tower_type)
	return ordered


func _is_enabled_slice_shop_tower(tower_type: String) -> bool:
	return BASIC_SLICE_TOWER_IDS.has(tower_type) and _current_slice_shop_towers().has(tower_type)


func _tower_data(tower_type: String) -> Dictionary:
	var data: Variant = game_data.get("towers", {}).get("tower_types", {}).get(tower_type, {})
	return data if data is Dictionary else {}


func _shop_cost(tower_type: String) -> int:
	return int(game_data.get("towers", {}).get("shop_costs", {}).get(tower_type, 50))


func _tower_label(tower_type: String) -> String:
	return str(_tower_data(tower_type).get("label", tower_type.capitalize()))


func _tower_shop_label(tower_type: String) -> String:
	var shop_labels := {
		"archer": "Archer",
		"machine_gun": "Gunner",
		"cannon": "Cannon",
		"frost": "Frost",
		"poison": "Venom",
		"support": "Support",
		"sniper": "Sniper",
		"tesla": "Tesla",
		"barracks": "Garrison",
	}
	return str(shop_labels.get(tower_type, _tower_label(tower_type)))


func _tower_short_label(tower_type: String) -> String:
	var fallback := tower_type.substr(0, 1).to_upper()
	return str(_tower_data(tower_type).get("short", fallback))


func _tower_sidebar_label() -> String:
	if not towers.is_empty():
		return _tower_label(str(towers[0].get("type", ARCHER_ID)))
	return "None"


func _tower_color(tower_type: String) -> Color:
	return _color_from_array(_tower_data(tower_type).get("color", [95, 185, 95]))


func _tower_range_color(tower_type: String) -> Color:
	var values: Array = _tower_data(tower_type).get("range_color", _tower_data(tower_type).get("color", [95, 185, 95]))
	var color := _color_from_array(values)
	color.a = 0.25
	return color


func _basic_slice_tower_range(tower_type: String, level: int = 1) -> float:
	var base_range: float = float(config.get("base_tower_range", 145)) + 18.0
	if tower_type == "sniper":
		base_range += 90.0
	if tower_type == "machine_gun":
		base_range -= 10.0
	if tower_type == "tesla":
		base_range += 8.0
	if level <= 1:
		return max(80.0, base_range - 12.0)
	return base_range


func _basic_slice_tower_damage(tower_type: String, level: int = 1) -> float:
	var damage := 39.0
	if tower_type == "sniper":
		damage = 58.0
	elif tower_type == "machine_gun":
		damage = 22.0
	elif tower_type == "cannon":
		damage = 46.0
	elif tower_type == "tesla":
		damage = 34.0
	if level <= 1:
		return max(1.0, round(damage * 0.93))
	return damage


func _basic_slice_tower_fire_rate(tower_type: String, level: int = 1) -> float:
	var fire_rate := 0.50
	if tower_type == "sniper":
		fire_rate = 0.85
	elif tower_type == "machine_gun":
		fire_rate = 0.28
	elif tower_type == "cannon":
		fire_rate = 0.72
	elif tower_type == "tesla":
		fire_rate = 0.45
	if level <= 1:
		return fire_rate
	return fire_rate


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
	return "L%s" % int(tower.get("level", 1))


func tower_stat_snapshot(tower: Dictionary) -> Dictionary:
	var shooting_speed: float = _tower_shooting_speed(tower)
	return {
		"level": int(tower.get("level", 1)),
		"damage": int(tower.get("damage", 0)),
		"range": int(tower.get("range", 0)),
		"shooting_speed": shooting_speed,
		"shooting_speed_label": _shooting_speed_label(shooting_speed),
		"damage_rating": _stat_rating(float(tower.get("damage", 0.0)), "damage"),
		"range_rating": _stat_rating(float(tower.get("range", 0.0)), "range"),
		"shooting_speed_rating": _stat_rating(shooting_speed, "shooting_speed"),
	}


func _tower_shooting_speed(tower: Dictionary) -> float:
	var fire_rate: float = float(tower.get("fire_rate", 0.0))
	if fire_rate <= 0.0:
		return 0.0
	return 1.0 / fire_rate


func _shooting_speed_label(shooting_speed: float) -> String:
	return "%.1f/s" % shooting_speed


func _stat_rating(value: float, stat_name: String) -> Dictionary:
	var values: Array = []
	for tower_type in _current_slice_shop_towers():
		if not _is_enabled_slice_shop_tower(str(tower_type)):
			continue
		values.append(_basic_stat_for_tower(str(tower_type), stat_name, 1))
		values.append(_basic_stat_for_tower(str(tower_type), stat_name, 2))
	if values.is_empty():
		return {"ratio": 0.5, "label": "Med"}
	var minimum: float = float(values[0])
	var maximum: float = float(values[0])
	for stat_value in values:
		minimum = min(minimum, float(stat_value))
		maximum = max(maximum, float(stat_value))
	var ratio := 0.5
	if not is_equal_approx(maximum, minimum):
		ratio = clamp((value - minimum) / (maximum - minimum), 0.0, 1.0)
	var label := "Low"
	if ratio >= 0.66:
		label = "High"
	elif ratio >= 0.33:
		label = "Med"
	return {"ratio": ratio, "label": label}


func _basic_stat_for_tower(tower_type: String, stat_name: String, level: int) -> float:
	if stat_name == "damage":
		return _basic_slice_tower_damage(tower_type, level)
	if stat_name == "range":
		return _basic_slice_tower_range(tower_type, level)
	if stat_name == "shooting_speed":
		var fire_rate := _basic_slice_tower_fire_rate(tower_type, level)
		return 0.0 if fire_rate <= 0.0 else 1.0 / fire_rate
	return 0.0


func _tower_detail_text(tower: Dictionary) -> String:
	var tower_type: String = str(tower.get("type", ARCHER_ID))
	var data: Dictionary = game_data.get("towers", {}).get("tower_types", {}).get(tower_type, {})
	var family: String = str(data.get("family", data.get("label", "Basic"))).replace(" Family", "")
	var selected_branch_name := _selected_branch_name(tower)
	var branch_text := "Focus at L3"
	if _tower_needs_branch_choice(tower):
		branch_text = "Choose L3 Focus"
	elif not selected_branch_name.is_empty():
		branch_text = "Focus: %s" % selected_branch_name
	var mutations: Array = tower.get("mutations", [])
	return "%s | %s | Traits %s/2" % [
		family,
		branch_text,
		mutations.size(),
	]


func _selected_branch_name(tower: Dictionary) -> String:
	var tower_type: String = str(tower.get("type", ARCHER_ID))
	var branch_id: String = str(tower.get("selected_branch", ""))
	if branch_id.is_empty():
		return ""
	var branch: Dictionary = _branch_definition(tower_type, branch_id)
	return _focus_display_name(tower_type, branch_id, branch)


func _focus_display_name(_tower_type: String, branch_id: String, branch: Dictionary) -> String:
	if FOCUS_DISPLAY_NAME_OVERRIDES.has(branch_id):
		return str(FOCUS_DISPLAY_NAME_OVERRIDES[branch_id])
	var fallback := branch_id.capitalize()
	var raw_name := str(branch.get("name", fallback)).strip_edges()
	if raw_name.is_empty():
		return fallback
	var words := raw_name.replace("-", " ").split(" ", false)
	if words.is_empty():
		return fallback
	return str(words[0]).capitalize()


func _focus_category_label(branch: Dictionary) -> String:
	var focus := str(branch.get("focus", "")).strip_edges()
	return focus.capitalize() if not focus.is_empty() else "General"


func _branch_level_copy(branch: Dictionary, field_name: String, level: int) -> String:
	var records: Variant = branch.get(field_name, {})
	if records is Dictionary:
		return str(records.get(str(level), records.get(level, "")))
	return ""


func _focus_perk_summary(branch: Dictionary) -> String:
	var perk := _branch_level_copy(branch, "upgrade_effects", 3)
	if perk.is_empty():
		perk = _branch_level_copy(branch, "descriptions", 3)
	if perk.is_empty():
		perk = str(branch.get("effect_preview", branch.get("role", "")))
	return perk


func _tower_needs_branch_choice(tower: Dictionary) -> bool:
	var root_ids: Array = game_data.get("towers", {}).get("root_tower_ids", [])
	var branch_unlock_level: int = int(game_data.get("towers", {}).get("branch_unlock_level", 3))
	return root_ids.has(tower.get("type", "")) and int(tower.get("level", 1)) == branch_unlock_level - 1 and str(tower.get("selected_branch", "")).is_empty()


func _branch_definitions_for_tower(tower_type: String) -> Dictionary:
	var all_branch_defs: Variant = game_data.get("towers", {}).get("branch_definitions", {})
	if not (all_branch_defs is Dictionary):
		return {}
	var branch_defs: Variant = all_branch_defs.get(tower_type, {})
	return branch_defs if branch_defs is Dictionary else {}


func _branch_definition(tower_type: String, branch_id: String) -> Dictionary:
	var branch_defs: Dictionary = _branch_definitions_for_tower(tower_type)
	var branch: Variant = branch_defs.get(branch_id, {})
	return branch if branch is Dictionary else {}


func _branch_options_for_tower(tower: Dictionary) -> Array:
	var tower_type: String = str(tower.get("type", ARCHER_ID))
	var branch_defs: Dictionary = _branch_definitions_for_tower(tower_type)
	if branch_defs.is_empty():
		return []
	var ordered_ids: Array = []
	var tower_data: Dictionary = _tower_data(tower_type)
	var branch_order: Variant = tower_data.get("branch_options", [])
	if branch_order is Array:
		for raw_branch_id in branch_order:
			var branch_id: String = str(raw_branch_id)
			if branch_defs.has(branch_id) and not ordered_ids.has(branch_id):
				ordered_ids.append(branch_id)
	for raw_branch_id in branch_defs.keys():
		var branch_id: String = str(raw_branch_id)
		if not ordered_ids.has(branch_id):
			ordered_ids.append(branch_id)
	var options: Array = []
	for branch_id in ordered_ids:
		var branch: Dictionary = _branch_definition(tower_type, branch_id)
		if branch.is_empty():
			continue
		var color_values: Variant = branch.get("color", tower_data.get("color", [95, 185, 95]))
		if not (color_values is Array) or color_values.size() < 3:
			color_values = [95, 185, 95]
		var focus_name := _focus_display_name(tower_type, branch_id, branch)
		options.append({
			"id": branch_id,
			"name": focus_name,
			"focus_name": focus_name,
			"canonical_name": str(branch.get("name", branch_id.capitalize())),
			"focus_category": _focus_category_label(branch),
			"perk_summary": _focus_perk_summary(branch),
			"short": str(branch.get("short", branch_id.substr(0, 2).to_upper())),
			"role": str(branch.get("role", "")),
			"effect_preview": str(branch.get("effect_preview", "")),
			"color": color_values,
		})
	return options


func _upgrade_options_for_tower(tower: Dictionary) -> Array:
	var cost: int = _upgrade_cost(tower)
	if cost == 0:
		return []
	var disabled_reason := "" if money >= cost else "Need $%s" % cost
	return [{
		"tower_type": tower.get("type", ""),
		"title": _upgrade_title(tower),
		"cost": cost,
		"description": _upgrade_description(tower),
		"enabled": disabled_reason.is_empty(),
		"disabled_reason": disabled_reason,
	}]


func _upgrade_title(tower: Dictionary) -> String:
	var next_level: int = int(tower.get("level", 1)) + 1
	var branch_unlock_level: int = int(game_data.get("towers", {}).get("branch_unlock_level", 3))
	if next_level >= branch_unlock_level and not str(tower.get("selected_branch", "")).is_empty():
		return "Upgrade to L%s" % next_level
	var tower_type: String = str(tower.get("type", ARCHER_ID))
	var tiers: Dictionary = _tower_data(tower_type).get("tiers", {})
	return str(tiers.get(str(next_level), "Level %s" % next_level))


func _upgrade_description(tower: Dictionary) -> String:
	var next_level: int = int(tower.get("level", 1)) + 1
	var branch_tier := _branch_tier_title(tower, next_level)
	if not branch_tier.is_empty():
		return branch_tier
	return ""


func _branch_tier_title(tower: Dictionary, level: int) -> String:
	var branch_id: String = str(tower.get("selected_branch", ""))
	if branch_id.is_empty():
		return ""
	var tower_type: String = str(tower.get("type", ARCHER_ID))
	var branch: Dictionary = _branch_definition(tower_type, branch_id)
	var branch_unlock_level: int = int(game_data.get("towers", {}).get("branch_unlock_level", 3))
	if level == branch_unlock_level:
		return _focus_display_name(tower_type, branch_id, branch)
	var tiers: Variant = branch.get("tiers", {})
	if tiers is Dictionary:
		return str(tiers.get(str(level), ""))
	return ""


func _upgrade_cost(tower: Dictionary) -> int:
	var level: int = int(tower.get("level", 1))
	var costs: Dictionary = game_data.get("upgrades", {}).get("tower_upgrade_costs", {})
	if level >= int(game_data.get("config", {}).get("base_max_tower_level", 5)):
		costs = game_data.get("upgrades", {}).get("mastery_upgrade_costs", {})
	return int(costs.get(str(level), costs.get(level, 0)))


func _sell_refund(tower: Dictionary) -> int:
	var rate: float = float(config.get("sell_refund_rate", 0.75))
	if bool(tower.get("is_paragon", false)):
		rate = float(config.get("paragon_sell_refund_rate", 0.5))
	return int(float(tower.get("money_spent", 0)) * rate)


func _update_spawning(delta: float) -> void:
	if spawned_this_wave >= _regular_enemy_count():
		return
	spawn_timer += delta
	var interval: float = _spawn_interval()
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
	var enemy := {
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
		"damage_taken_multiplier": 1.0,
		"regen_scale": 0.0,
		"death_spawns": 0,
		"death_burst_damage_fraction": 0.0,
		"death_burst_radius": 0.0,
	}
	_apply_wave_modifier(enemy)
	return enemy


func _apply_wave_modifier(enemy: Dictionary) -> void:
	var modifier_data: Variant = wave_row.get("modifier_data", {})
	if not (modifier_data is Dictionary):
		return
	var effects: Variant = modifier_data.get("effects", {})
	if not (effects is Dictionary):
		return
	if effects.has("speed_multiplier"):
		enemy["speed"] = float(enemy.get("speed", 0.0)) * float(effects["speed_multiplier"])
	if effects.has("damage_multiplier"):
		enemy["damage_taken_multiplier"] = float(effects["damage_multiplier"])
	if effects.has("shield_hits"):
		var shield_hits: int = int(enemy.get("shield_hits", 0)) + int(effects["shield_hits"])
		enemy["shield_hits"] = shield_hits
		enemy["max_shield_hits"] = shield_hits
	if effects.has("regen_scale"):
		enemy["regen_scale"] = float(effects["regen_scale"])
	if effects.has("death_spawns"):
		enemy["death_spawns"] = int(effects["death_spawns"])
	if effects.has("death_burst_damage_fraction"):
		enemy["death_burst_damage_fraction"] = float(effects["death_burst_damage_fraction"])
	if effects.has("death_burst_radius"):
		enemy["death_burst_radius"] = float(effects["death_burst_radius"])


func _wave_enemy_kind() -> String:
	return _normalized_enemy_kind(str(wave_row.get("enemy_kind", ENEMY_KIND)))


func _regular_enemy_count() -> int:
	return max(0, int(wave_row.get("regular_enemy_count", SLICE_SPAWN_LIMIT)))


func _spawn_interval() -> float:
	return float(wave_row.get("spawn_interval", 0.608))


func _wave_forecast_label() -> String:
	return str(wave_row.get("label", _wave_enemy_kind().capitalize()))


func _wave_modifier_label() -> String:
	var modifier_data: Variant = wave_row.get("modifier_data", {})
	if modifier_data is Dictionary:
		return str(modifier_data.get("label", ""))
	return ""


func _wave_modifier_id() -> String:
	var modifier: Variant = wave_row.get("modifier", "")
	return "" if modifier == null else str(modifier)


func _wave_recommendation() -> String:
	var modifier_data: Variant = wave_row.get("modifier_data", {})
	if modifier_data is Dictionary:
		return str(modifier_data.get("recommendation", "Build coverage and upgrade key towers."))
	return "Build coverage and upgrade key towers."


func _wave_recommendation_short() -> String:
	var recommendation := _wave_recommendation()
	var colon_index := recommendation.find(":")
	if colon_index >= 0 and colon_index + 1 < recommendation.length():
		return recommendation.substr(colon_index + 1).strip_edges()
	return "Build coverage."


func wave_forecast_snapshot() -> Dictionary:
	return {
		"wave": wave,
		"enemy_kind": _wave_enemy_kind(),
		"label": _wave_forecast_label(),
		"modifier": _wave_modifier_id(),
		"modifier_label": _wave_modifier_label(),
		"recommendation": _wave_recommendation(),
		"regular_enemy_count": _regular_enemy_count(),
		"spawn_interval": _spawn_interval(),
	}


func _wave_schedule() -> Array:
	return game_data.get("waves", {}).get("schedule", [])


func _can_start_wave_from_ui() -> bool:
	return _wave_start_disabled_reason().is_empty()


func _wave_start_disabled_reason() -> String:
	if game_over:
		return "Game over"
	if wave_active:
		return "Wave already active"
	if towers.is_empty():
		return "Build a tower first"
	var schedule: Array = _wave_schedule()
	if wave_complete and wave >= schedule.size():
		return "All waves cleared"
	return ""


func _wave_control_label() -> String:
	if game_over:
		return "Game Over"
	if towers.is_empty():
		return "Build a Tower"
	if wave_active:
		return "Wave Active"
	var schedule: Array = _wave_schedule()
	if wave_complete:
		if wave >= schedule.size():
			return "Final Wave Complete"
		return "Start Wave %s" % (wave + 1)
	return "Start Wave %s" % wave


func _clamped_wave_number(wave_number: int) -> int:
	var schedule: Array = _wave_schedule()
	if schedule.is_empty():
		return max(1, wave_number)
	return int(clamp(wave_number, 1, schedule.size()))


func _refresh_wave_row() -> void:
	var schedule: Array = _wave_schedule()
	if schedule.is_empty():
		wave_row = {}
		return
	var index: int = clamp(wave - 1, 0, schedule.size() - 1)
	var row: Variant = schedule[index]
	if row is Dictionary:
		wave_row = row
	else:
		wave_row = schedule[0] if schedule[0] is Dictionary else {}


func _normalized_enemy_kind(kind: String) -> String:
	if CANONICAL_ENEMY_KINDS.has(kind):
		return kind
	return ENEMY_KIND


func _enemy_kind_modifier(kind: String) -> Dictionary:
	var modifiers: Dictionary = game_data.get("enemies", {}).get("kind_modifiers", {})
	var modifier: Variant = modifiers.get(_normalized_enemy_kind(kind), {})
	return modifier if modifier is Dictionary else {}


func _update_enemies(delta: float) -> void:
	var remaining: Array = []
	var death_spawns: Array = []
	for enemy in enemies:
		_update_enemy(enemy, delta)
		if enemy["reached_end"]:
			_apply_leak_life_loss()
			leaks += 1
			if game_over:
				enemies = []
				return
		elif float(enemy["hp"]) <= 0.0:
			money += int(enemy["reward"])
			kills += 1
			_credit_tower_kill(enemy)
			_resolve_enemy_death_effects(enemy, death_spawns)
		else:
			remaining.append(enemy)
	remaining.append_array(death_spawns)
	enemies = remaining


func _apply_leak_life_loss() -> void:
	if game_over:
		return
	lives = max(0, lives - 1)
	if lives == 0:
		_trigger_game_over()


func _trigger_game_over() -> void:
	if game_over:
		return
	game_over = true
	wave_active = false
	wave_complete = false
	selected_build_type = ""
	selected_tower_index = NO_SELECTED_TOWER
	enemies = []
	projectiles = []
	wave_reward_money = 0
	wave_reward_research = 0
	_play_sound("sounds/ui/wave_boss.wav", 180.0)
	_emit_status()


func _resolve_enemy_death_effects(enemy: Dictionary, spawned: Array) -> void:
	var burst_radius: float = float(enemy.get("death_burst_radius", 0.0))
	var burst_fraction: float = float(enemy.get("death_burst_damage_fraction", 0.0))
	if burst_radius > 0.0 and burst_fraction > 0.0:
		_apply_death_burst(enemy, burst_radius, burst_fraction)
	var spawn_count: int = max(0, int(enemy.get("death_spawns", 0)))
	for _index in range(spawn_count):
		spawned.append(_make_death_spawn_enemy(enemy))


func _apply_death_burst(source: Dictionary, radius: float, damage_fraction: float) -> void:
	var source_position: Vector2 = source.get("position", Vector2.ZERO)
	var burst_damage: float = max(1.0, float(source.get("max_hp", 0.0)) * damage_fraction)
	for enemy in enemies:
		if enemy == source or bool(enemy.get("reached_end", false)) or float(enemy.get("hp", 0.0)) <= 0.0:
			continue
		if source_position.distance_to(enemy.get("position", Vector2.ZERO)) > radius:
			continue
		enemy["hp"] = float(enemy.get("hp", 0.0)) - burst_damage


func _make_death_spawn_enemy(parent: Dictionary) -> Dictionary:
	var child: Dictionary = parent.duplicate(true)
	var child_hp: float = max(8.0, float(parent.get("max_hp", 1.0)) * 0.35)
	child["hp"] = child_hp
	child["max_hp"] = child_hp
	child["reward"] = 0
	child["reached_end"] = false
	child["shield_hits"] = 0
	child["max_shield_hits"] = 0
	child["regen_scale"] = 0.0
	child["death_spawns"] = 0
	child["death_burst_damage_fraction"] = 0.0
	child["death_burst_radius"] = 0.0
	child["damage_taken_multiplier"] = 1.0
	child["speed"] = float(parent.get("speed", 0.0)) * 1.08
	child["progress"] = _enemy_progress(child)
	return child


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
	var regen_scale: float = float(enemy.get("regen_scale", 0.0))
	if regen_scale > 0.0 and float(enemy.get("hp", 0.0)) > 0.0:
		var max_hp: float = float(enemy.get("max_hp", 0.0))
		enemy["hp"] = min(max_hp, float(enemy.get("hp", 0.0)) + max_hp * regen_scale * delta)


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


func make_game_data_enemy_for_test(kind: String, wave_number: int = 1) -> Dictionary:
	return create_enemy(kind, wave_number, Vector2(180, 100), 1)


func set_wave_for_test(wave_number: int) -> Dictionary:
	wave = _clamped_wave_number(wave_number)
	_refresh_wave_row()
	wave_active = false
	wave_complete = false
	spawned_this_wave = 0
	spawn_timer = 0.0
	enemies = []
	projectiles = []
	return wave_row


func spawn_regular_wave_for_test(wave_number: int) -> Dictionary:
	set_wave_for_test(wave_number)
	var spawn_count: int = _regular_enemy_count()
	var enemy_kind: String = _wave_enemy_kind()
	for _index in range(spawn_count):
		enemies.append(create_enemy(enemy_kind, wave))
	spawned_this_wave = spawn_count
	var kind_counts: Dictionary = {}
	var boss_count := 0
	var commander_count := 0
	for enemy in enemies:
		var kind := str(enemy.get("kind", ""))
		kind_counts[kind] = int(kind_counts.get(kind, 0)) + 1
		if bool(enemy.get("boss", false)):
			boss_count += 1
		if bool(enemy.get("commander", false)):
			commander_count += 1
	return {
		"wave": wave,
		"enemy_kind": enemy_kind,
		"spawned_count": enemies.size(),
		"spawn_limit": spawn_count,
		"spawn_interval": _spawn_interval(),
		"modifier": _wave_modifier_id(),
		"modifier_label": _wave_modifier_label(),
		"kind_counts": kind_counts,
		"spawned_boss_count": boss_count,
		"spawned_commander_count": commander_count,
		"game_data_boss_count": int(wave_row.get("boss_count", 0)),
		"game_data_commander_count": int(wave_row.get("commander_count", 0)),
	}


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
	damage *= float(target.get("damage_taken_multiplier", 1.0))
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
	if game_over or not wave_active:
		return
	if spawned_this_wave < _regular_enemy_count() or not enemies.is_empty():
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
		"game_over": game_over,
		"spawned_this_wave": spawned_this_wave,
		"spawn_limit": _regular_enemy_count(),
		"spawn_interval": _spawn_interval(),
		"slice_spawn_limit": SLICE_SPAWN_LIMIT,
		"game_data_regular_enemy_count": int(wave_row.get("regular_enemy_count", 0)),
		"kills": kills,
		"leaks": leaks,
		"tower_count": towers.size(),
		"enemy_count": enemies.size(),
		"projectile_count": projectiles.size(),
		"wave_reward_money": wave_reward_money,
		"wave_reward_research": wave_reward_research,
		"map_name": map_record.get("name", ""),
		"tower_family": ARCHER_ID if towers.is_empty() else str(towers[0].get("type", ARCHER_ID)),
		"enemy_family": _wave_enemy_kind(),
		"wave_forecast": wave_forecast_snapshot(),
		"selected_build_type": selected_build_type,
		"shop_button_count": get_shop_button_rects().size(),
		"game_speed": game_speed,
		"game_speed_label": _game_speed_label(),
		"latest_feedback": latest_feedback.duplicate(true),
	}


func status_snapshot() -> Dictionary:
	return {
		"title": GameConfig.GAME_TITLE,
		"version": GameConfig.GODOT_VERSION_PIN,
		"phase": "vertical slice",
		"gameplay": "%s / %s / %s" % [map_record.get("name", "Classic Road"), _wave_forecast_label(), "game over" if game_over else "complete" if wave_complete else "ready"],
		"latest_feedback": latest_feedback.duplicate(true),
		"debug_overlay": debug_overlay_snapshot(),
	}


func set_debug_overlay_enabled(enabled: bool) -> void:
	if debug_overlay_enabled == enabled:
		return
	debug_overlay_enabled = enabled
	_emit_status()
	queue_redraw()


func toggle_debug_overlay() -> bool:
	set_debug_overlay_enabled(not debug_overlay_enabled)
	return debug_overlay_enabled


func debug_command_names() -> Array:
	return DEBUG_COMMAND_NAMES.duplicate()


func run_debug_command(command: String, args: Dictionary = {}) -> Dictionary:
	var normalized_command := command.strip_edges().to_lower()
	if not DEBUG_COMMAND_NAMES.has(normalized_command):
		return _debug_command_result(false, normalized_command, "unknown debug command", {})
	if not debug_overlay_enabled:
		return _debug_command_result(false, normalized_command, "debug commands disabled", {})
	var detail: Dictionary = {}
	if normalized_command == "give_money":
		var amount: int = int(args.get("amount", 0))
		if amount <= 0:
			return _debug_command_result(false, normalized_command, "amount must be positive", {"amount": amount})
		money += amount
		detail = {"amount": amount, "money": money}
	elif normalized_command == "set_wave":
		var requested_wave: int = int(args.get("wave", wave))
		var target_wave: int = _clamped_wave_number(requested_wave)
		_debug_set_wave(target_wave)
		detail = {"requested_wave": requested_wave, "wave": wave}
	elif normalized_command == "spawn_enemy":
		detail = _debug_spawn_enemy(args)
	elif normalized_command == "kill_all_enemies":
		detail = _debug_kill_all_enemies()
	elif normalized_command == "skip_wave":
		detail = _debug_skip_wave()
	_emit_status()
	_check_runtime_invariants("debug_command_%s" % normalized_command)
	queue_redraw()
	return _debug_command_result(true, normalized_command, "", detail)


func _debug_set_wave(target_wave: int) -> void:
	wave = _clamped_wave_number(target_wave)
	_refresh_wave_row()
	game_over = false
	wave_active = false
	wave_complete = false
	spawned_this_wave = 0
	spawn_timer = 0.0
	leaks = 0
	kills = 0
	wave_reward_money = 0
	wave_reward_research = 0
	enemies = []
	projectiles = []


func _debug_spawn_enemy(args: Dictionary) -> Dictionary:
	var requested_kind := str(args.get("kind", _wave_enemy_kind()))
	var enemy_kind := _normalized_enemy_kind(requested_kind)
	var requested_count: int = int(args.get("count", 1))
	var count: int = int(clamp(requested_count, 1, 50))
	var target_index: int = int(clamp(int(args.get("target_index", 1)), 0, max(1, path_points.size() - 1)))
	var position := Vector2.INF
	var raw_position: Variant = args.get("position", Vector2.INF)
	if raw_position is Vector2:
		position = raw_position
	elif raw_position is Array:
		position = _array_to_vector(raw_position)
	for _index in range(count):
		enemies.append(create_enemy(enemy_kind, wave, position, target_index))
	return {
		"requested_kind": requested_kind,
		"kind": enemy_kind,
		"requested_count": requested_count,
		"count": count,
		"enemy_count": enemies.size(),
	}


func _debug_kill_all_enemies() -> Dictionary:
	var removed_enemies := enemies.size()
	var removed_projectiles := projectiles.size()
	enemies = []
	projectiles = []
	if wave_active and spawned_this_wave >= _regular_enemy_count():
		_check_wave_completion()
	return {
		"removed_enemies": removed_enemies,
		"removed_projectiles": removed_projectiles,
		"wave_complete": wave_complete,
	}


func _debug_skip_wave() -> Dictionary:
	var already_complete := wave_complete
	var removed_enemies := enemies.size()
	var removed_projectiles := projectiles.size()
	enemies = []
	projectiles = []
	spawned_this_wave = _regular_enemy_count()
	if not already_complete:
		wave_active = false
		wave_complete = true
		wave_reward_money = _wave_completion_money()
		wave_reward_research = _research_reward()
		money += wave_reward_money
		research_points += wave_reward_research
	return {
		"already_complete": already_complete,
		"removed_enemies": removed_enemies,
		"removed_projectiles": removed_projectiles,
		"wave": wave,
		"wave_complete": wave_complete,
		"wave_reward_money": wave_reward_money,
		"wave_reward_research": wave_reward_research,
	}


func _debug_command_result(ok: bool, command: String, error: String, detail: Dictionary) -> Dictionary:
	return {
		"ok": ok,
		"command": command,
		"error": error,
		"detail": detail,
		"snapshot": snapshot(),
	}


func debug_overlay_snapshot() -> Dictionary:
	if not debug_overlay_enabled:
		return {"enabled": false}
	return {
		"enabled": true,
		"economy": {
			"money": money,
			"lives": lives,
			"research_points": research_points,
			"wave_reward_money": wave_reward_money,
			"wave_reward_research": wave_reward_research,
		},
		"wave": {
			"wave": wave,
			"wave_active": wave_active,
			"wave_complete": wave_complete,
			"spawned_this_wave": spawned_this_wave,
			"spawn_limit": _regular_enemy_count(),
			"spawn_interval": _spawn_interval(),
			"enemy_family": _wave_enemy_kind(),
			"wave_modifier": _wave_modifier_id(),
			"wave_modifier_label": _wave_modifier_label(),
			"game_speed": game_speed,
		},
		"commands": debug_command_names(),
		"towers": _debug_tower_records(),
		"enemies": _debug_enemy_records(),
		"projectiles": _debug_projectile_records(),
	}


func _debug_tower_records() -> Array:
	var records: Array = []
	for index in range(towers.size()):
		var tower: Dictionary = towers[index]
		var target: Dictionary = _find_target(tower)
		records.append({
			"index": index,
			"type": str(tower.get("type", ARCHER_ID)),
			"position": _vector_to_array(tower.get("position", Vector2.ZERO)),
			"level": int(tower.get("level", 1)),
			"range": float(tower.get("range", 0.0)),
			"damage": float(tower.get("damage", 0.0)),
			"fire_rate": float(tower.get("fire_rate", 0.0)),
			"cooldown": float(tower.get("cooldown", 0.0)),
			"target_mode": str(tower.get("target_mode", "first")),
			"kills": int(tower.get("kills", 0)),
			"selected": index == selected_tower_index,
			"target_index": _debug_enemy_index(target),
			"target_kind": str(target.get("kind", "")) if not target.is_empty() else "",
			"target_progress": float(target.get("progress", 0.0)) if not target.is_empty() else 0.0,
		})
	return records


func _debug_enemy_records() -> Array:
	var records: Array = []
	for index in range(enemies.size()):
		var enemy: Dictionary = enemies[index]
		records.append({
			"index": index,
			"kind": str(enemy.get("kind", ENEMY_KIND)),
			"position": _vector_to_array(enemy.get("position", Vector2.ZERO)),
			"hp": float(enemy.get("hp", 0.0)),
			"max_hp": float(enemy.get("max_hp", 0.0)),
			"progress": float(enemy.get("progress", 0.0)),
			"target_index": int(enemy.get("target_index", 0)),
			"shield_hits": int(enemy.get("shield_hits", 0)),
			"reached_end": bool(enemy.get("reached_end", false)),
		})
	return records


func _debug_projectile_records() -> Array:
	var records: Array = []
	for index in range(projectiles.size()):
		var projectile: Dictionary = projectiles[index]
		records.append({
			"index": index,
			"position": _vector_to_array(projectile.get("position", Vector2.ZERO)),
			"target_index": _debug_enemy_index(projectile.get("target", {})),
			"tower_index": _debug_tower_index(projectile.get("tower", {})),
			"tower_type": str(projectile.get("tower_type", "")),
			"damage": float(projectile.get("damage", 0.0)),
			"speed": float(projectile.get("speed", 0.0)),
			"dead": bool(projectile.get("dead", false)),
		})
	return records


func _debug_enemy_index(target: Variant) -> int:
	if not target is Dictionary:
		return -1
	for index in range(enemies.size()):
		if enemies[index] == target:
			return index
	return -1


func _debug_tower_index(target: Variant) -> int:
	if not target is Dictionary:
		return -1
	for index in range(towers.size()):
		if towers[index] == target:
			return index
	return -1


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
		"game_over": game_over,
		"spawned_this_wave": spawned_this_wave,
		"spawn_timer": spawn_timer,
		"leaks": leaks,
		"kills": kills,
		"wave_reward_money": wave_reward_money,
		"wave_reward_research": wave_reward_research,
		"selected_build_type": selected_build_type,
		"selected_tower_index": selected_tower_index,
		"game_speed": game_speed,
		"towers": _serialize_towers(),
		"enemies": _serialize_enemies(),
		"projectiles": _serialize_projectiles(),
	}


func restore_run_state(state: Dictionary) -> bool:
	if int(state.get("schema_version", 0)) != 1:
		return false
	reset_slice()
	money = int(state.get("money", money))
	lives = max(0, int(state.get("lives", lives)))
	research_points = int(state.get("research_points", research_points))
	wave = _clamped_wave_number(int(state.get("wave", wave)))
	_refresh_wave_row()
	wave_active = bool(state.get("wave_active", wave_active))
	wave_complete = bool(state.get("wave_complete", wave_complete))
	game_over = bool(state.get("game_over", false)) or lives == 0
	if game_over:
		wave_active = false
		wave_complete = false
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
	if game_over:
		selected_build_type = ""
		selected_tower_index = NO_SELECTED_TOWER
		enemies = []
		projectiles = []
	invariant_check_timer = 0.0
	set_game_speed(float(state.get("game_speed", game_speed)))
	_emit_status()
	_check_runtime_invariants("restore_run_state")
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
			"damage_taken_multiplier": float(enemy.get("damage_taken_multiplier", 1.0)),
			"regen_scale": float(enemy.get("regen_scale", 0.0)),
			"death_spawns": int(enemy.get("death_spawns", 0)),
			"death_burst_damage_fraction": float(enemy.get("death_burst_damage_fraction", 0.0)),
			"death_burst_radius": float(enemy.get("death_burst_radius", 0.0)),
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
		"damage_taken_multiplier": float(record.get("damage_taken_multiplier", 1.0)),
		"regen_scale": float(record.get("regen_scale", 0.0)),
		"death_spawns": int(record.get("death_spawns", 0)),
		"death_burst_damage_fraction": float(record.get("death_burst_damage_fraction", 0.0)),
		"death_burst_radius": float(record.get("death_burst_radius", 0.0)),
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
	var metrics := _layout_metrics()
	var viewport_size: Vector2 = metrics["viewport_size"]
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.02, 0.025, 0.024))
	_draw_map_layer(metrics)
	_draw_sidebar()
	if game_over:
		_draw_game_over_overlay()


func _draw_map_layer(metrics: Dictionary) -> void:
	var map_rect: Rect2 = metrics["map_rect"]
	var map_scale: float = float(metrics["map_scale"])
	draw_set_transform(map_rect.position, 0.0, Vector2(map_scale, map_scale))
	_draw_map()
	_draw_build_site()
	_draw_entities()
	_draw_debug_overlay()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_map() -> void:
	var map_rect := Rect2(Vector2.ZERO, Vector2(float(config.get("map_width", 900)), float(config.get("height", 600))))
	var grass := _texture("sprites/terrain/grass.png")
	if grass != null:
		draw_texture_rect(grass, map_rect, true)
	else:
		draw_rect(map_rect, Color(0.09, 0.13, 0.10))
	_draw_path()
	_draw_build_grid(map_rect)
	if not path_points.is_empty():
		if not _draw_texture_centered("sprites/terrain/spawn_gate.png", path_points[0], Vector2(44, 44)):
			draw_circle(path_points[0], 22.0, Color(0.25, 0.85, 0.50))
		if not _draw_texture_centered("sprites/terrain/base_gate.png", path_points[path_points.size() - 1], Vector2(44, 44)):
			draw_circle(path_points[path_points.size() - 1], 22.0, Color(0.95, 0.28, 0.23))


func _draw_game_over_overlay() -> void:
	var viewport_size := _layout_viewport_size()
	var width: float = viewport_size.x
	var height: float = viewport_size.y
	draw_rect(Rect2(Vector2.ZERO, Vector2(width, height)), Color(0.02, 0.025, 0.022, 0.68))
	var panel := Rect2(Vector2(width * 0.5 - 170.0, height * 0.5 - 86.0), Vector2(340.0, 190.0))
	draw_rect(panel, Color(0.08, 0.09, 0.08, 0.96))
	draw_rect(Rect2(panel.position, Vector2(panel.size.x, 5.0)), Color(0.86, 0.34, 0.28))
	draw_rect(panel, Color(0.42, 0.28, 0.24), false, 2.0)
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(24, 40), "Game Over", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28, Color(1.0, 0.92, 0.86))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(24, 72), "Lives depleted on Wave %s" % wave, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.86, 0.82, 0.74))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(24, 96), "Kills %s  |  Leaks %s" % [kills, leaks], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(0.72, 0.76, 0.68))
	var restart_rect := get_game_over_restart_rect()
	draw_rect(restart_rect, Color(0.18, 0.26, 0.18))
	draw_rect(restart_rect, Color(0.56, 0.82, 0.50), false, 2.0)
	draw_string(ThemeDB.fallback_font, restart_rect.position + Vector2(30, 23), "Restart Run", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.94, 0.98, 0.90))


func _draw_path() -> void:
	var path_width := float(config.get("path_width", 54))
	_draw_path_pass(path_width + 8.0, Color(0.34, 0.28, 0.21))
	_draw_path_pass(path_width, Color(0.58, 0.48, 0.35))


func _draw_path_pass(width: float, color: Color) -> void:
	if path_points.size() < 2:
		return
	for index in range(path_points.size() - 1):
		draw_line(path_points[index], path_points[index + 1], color, width)
	for point in path_points:
		draw_rect(Rect2(point - Vector2(width, width) * 0.5, Vector2(width, width)), color)


func _draw_build_grid(map_rect: Rect2) -> void:
	var step := _build_grid_step()
	var minor := Color(0.88, 0.96, 0.86, 0.08)
	var major := Color(0.94, 1.0, 0.90, 0.14)
	var x := map_rect.position.x
	var column := 0
	while x <= map_rect.end.x + 0.5:
		var color := major if column % 2 == 0 else minor
		draw_line(Vector2(x, map_rect.position.y), Vector2(x, map_rect.end.y), color, 1.0)
		x += step
		column += 1
	var y := map_rect.position.y
	var row := 0
	while y <= map_rect.end.y + 0.5:
		var color := major if row % 2 == 0 else minor
		draw_line(Vector2(map_rect.position.x, y), Vector2(map_rect.end.x, y), color, 1.0)
		y += step
		row += 1


func _draw_build_site() -> void:
	if selected_build_type.is_empty():
		return
	var map_pos := screen_to_map_position(get_local_mouse_position())
	if map_pos == Vector2.INF:
		return
	var site: Vector2 = _snap_to_build_grid(map_pos)
	var valid: bool = can_place_tower(site)
	var tile_size: float = float(config.get("build_tile_size", 54))
	var tile_rect := Rect2(site - Vector2(tile_size, tile_size) * 0.5, Vector2(tile_size, tile_size))
	var tower_color := _tower_color(selected_build_type)
	var outline := Color(tower_color.r, tower_color.g, tower_color.b, 0.86) if valid else Color(0.95, 0.22, 0.18, 0.86)
	var range_color := _tower_range_color(selected_build_type)
	range_color.a = 0.30 if valid else 0.16
	draw_rect(tile_rect, Color(0.10, 0.15, 0.12, 0.22) if valid else Color(0.18, 0.08, 0.07, 0.24))
	draw_rect(tile_rect, outline, false, 2.0)
	draw_arc(site, _basic_slice_tower_range(selected_build_type, 1), 0.0, TAU, 64, range_color, 1.0)
	var preview_modulate := Color(1.0, 1.0, 1.0, 0.78) if valid else Color(1.0, 0.42, 0.36, 0.62)
	var tower_tex := _animated_texture("towers", selected_build_type, ["idle_1", "idle_2"], 240)
	if tower_tex != null:
		_draw_texture(tower_tex, site, Vector2(42, 42), preview_modulate)
	else:
		draw_circle(site, 18.0, Color(tower_color.r, tower_color.g, tower_color.b, 0.56) if valid else Color(0.9, 0.18, 0.16, 0.42))
		draw_string(ThemeDB.fallback_font, site + Vector2(-8, 5), _tower_short_label(selected_build_type), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(1.0, 1.0, 1.0, 0.82))


func _draw_entities() -> void:
	for index in range(towers.size()):
		var tower: Dictionary = towers[index]
		var tower_type: String = str(tower.get("type", ARCHER_ID))
		var position: Vector2 = tower["position"]
		if index == selected_tower_index:
			draw_arc(position, float(tower["range"]), 0.0, TAU, 48, _tower_range_color(tower_type), 1.0)
			draw_circle(position, 23.0, Color(0.98, 0.92, 0.45, 0.28))
		var tower_tex := _animated_texture("towers", tower_type, ["idle_1", "idle_2"], 240)
		if tower_tex != null:
			_draw_texture(tower_tex, position, Vector2(42, 42))
		else:
			draw_circle(position, 18.0, _tower_color(tower_type))
			draw_string(ThemeDB.fallback_font, position + Vector2(-8, 5), _tower_short_label(tower_type), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color.WHITE)
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
		var tower_type := str(projectile.get("tower_type", ARCHER_ID))
		if not _draw_texture_centered("sprites/projectiles/%s.png" % tower_type, projectile["position"], Vector2(14, 14)):
			draw_circle(projectile["position"], 4.0, Color(0.95, 0.78, 0.35))


func _draw_debug_overlay() -> void:
	if not debug_overlay_enabled:
		return
	var range_color := Color(0.28, 0.74, 1.0, 0.28)
	var target_color := Color(1.0, 0.88, 0.24, 0.58)
	var projectile_color := Color(1.0, 0.46, 0.28, 0.64)
	for index in range(towers.size()):
		var tower: Dictionary = towers[index]
		var position: Vector2 = tower.get("position", Vector2.ZERO)
		var tower_type := str(tower.get("type", ARCHER_ID))
		draw_arc(position, float(tower.get("range", 0.0)), 0.0, TAU, 64, range_color, 1.0)
		var target: Dictionary = _find_target(tower)
		if not target.is_empty():
			draw_line(position, target.get("position", position), target_color, 1.5)
		var label_text := "%s L%s %s" % [_tower_short_label(tower_type), int(tower.get("level", 1)), str(tower.get("target_mode", "first"))]
		draw_string(ThemeDB.fallback_font, position + Vector2(-26, -29), label_text, HORIZONTAL_ALIGNMENT_LEFT, 82.0, 9, Color(0.78, 0.92, 1.0, 0.86))
	for index in range(enemies.size()):
		var enemy: Dictionary = enemies[index]
		var position: Vector2 = enemy.get("position", Vector2.ZERO)
		draw_arc(position, 20.0, 0.0, TAU, 28, Color(1.0, 0.42, 0.34, 0.36), 1.0)
		var enemy_label := "#%s %s %.0f%%" % [index, str(enemy.get("kind", ENEMY_KIND)), float(enemy.get("progress", 0.0)) * 100.0]
		draw_string(ThemeDB.fallback_font, position + Vector2(-28, 33), enemy_label, HORIZONTAL_ALIGNMENT_LEFT, 96.0, 8, Color(1.0, 0.78, 0.68, 0.82))
	for projectile in projectiles:
		var position: Vector2 = projectile.get("position", Vector2.ZERO)
		var target: Dictionary = projectile.get("target", {})
		if not target.is_empty():
			draw_line(position, target.get("position", position), projectile_color, 1.0)
		draw_arc(position, 8.0, 0.0, TAU, 18, projectile_color, 1.0)
	var panel := Rect2(Vector2(12, 12), Vector2(258, 66))
	draw_rect(panel, Color(0.02, 0.04, 0.045, 0.72))
	draw_rect(panel, Color(0.34, 0.68, 0.76, 0.72), false, 1.0)
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(8, 17), "Debug overlay", HORIZONTAL_ALIGNMENT_LEFT, 120.0, 11, Color(0.76, 0.94, 0.98, 0.95))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(8, 34), "Wave %s %s/%s  Speed %s" % [wave, spawned_this_wave, _regular_enemy_count(), _game_speed_label()], HORIZONTAL_ALIGNMENT_LEFT, 238.0, 10, Color(0.88, 0.92, 0.84, 0.90))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(8, 51), "$%s  Lives %s  Tech %s  T/E/P %s/%s/%s" % [money, lives, research_points, towers.size(), enemies.size(), projectiles.size()], HORIZONTAL_ALIGNMENT_LEFT, 238.0, 10, Color(0.94, 0.88, 0.64, 0.90))


func _draw_sidebar() -> void:
	var metrics := _layout_metrics()
	if str(metrics["mode"]) == "bottom_dock":
		_draw_bottom_dock(metrics)
		return
	var x: float = float(config.get("map_width", 900))
	draw_rect(Rect2(Vector2(x, 0), Vector2(float(config.get("ui_width", 280)), float(config.get("height", 600)))), Color(0.10, 0.11, 0.13))
	_draw_shop_panel()
	if selected_tower_index != NO_SELECTED_TOWER:
		_draw_upgrade_panel()
		return
	var panel := Rect2(Vector2(x + 14.0, 304.0), Vector2(float(config.get("ui_width", GameConfig.UI_WIDTH)) - 28.0, 190.0))
	_draw_run_status_panel(panel)


func _draw_bottom_dock(metrics: Dictionary) -> void:
	var dock_rect: Rect2 = metrics["dock_rect"]
	draw_rect(dock_rect, Color(0.10, 0.11, 0.13, 0.98))
	draw_rect(Rect2(dock_rect.position, Vector2(dock_rect.size.x, 3.0)), Color(0.24, 0.36, 0.34))
	draw_rect(dock_rect, Color(0.18, 0.22, 0.22), false, 2.0)
	_draw_shop_panel()
	_draw_wave_panel()
	if selected_tower_index != NO_SELECTED_TOWER:
		_draw_upgrade_panel()
		return
	var panel: Rect2 = metrics["run_status_panel_rect"]
	_draw_run_status_panel(panel)


func _draw_run_status_panel(panel: Rect2) -> void:
	draw_rect(panel, Color(0.07, 0.085, 0.085))
	draw_rect(Rect2(panel.position, Vector2(panel.size.x, 4)), Color(0.47, 0.70, 0.56))
	draw_rect(panel, Color(0.26, 0.31, 0.27), false, 2.0)
	var wave_label := "Game Over" if game_over else "Complete" if wave_complete else "Active" if wave_active else "Ready"
	var wave_color := Color(0.86, 0.34, 0.28) if game_over else Color(0.48, 0.78, 0.56) if not wave_active else Color(0.88, 0.72, 0.34)
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(12, 25), "Run Status", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(0.94, 0.96, 0.88))
	var badge := Rect2(panel.position + Vector2(panel.size.x - 96, 9), Vector2(82, 24))
	draw_rect(badge, Color(wave_color.r, wave_color.g, wave_color.b, 0.18))
	draw_rect(badge, wave_color, false, 1.0)
	draw_string(ThemeDB.fallback_font, badge.position + Vector2(8, 17), wave_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.94, 0.96, 0.88))
	_draw_sidebar_detail(panel.position + Vector2(12, 52), "Map", str(map_record.get("name", "Classic Road")))
	_draw_sidebar_detail(panel.position + Vector2(12, 74), "Threat", _wave_forecast_label())
	_draw_sidebar_detail(panel.position + Vector2(12, 96), "Counter", _wave_recommendation_short())
	var compact := panel.size.y <= 180.0
	var stat_y := 112.0 if compact else 124.0
	var reward_y := 146.0 if compact else 160.0
	var stat_panel: Rect2 = Rect2(panel.position + Vector2(12, stat_y), Vector2(panel.size.x - 24, 34))
	draw_rect(stat_panel, Color(0.10, 0.12, 0.105))
	draw_rect(stat_panel, Color(0.26, 0.31, 0.27), false, 1.0)
	draw_string(ThemeDB.fallback_font, stat_panel.position + Vector2(8, 14), "Money", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color(0.61, 0.66, 0.58))
	draw_string(ThemeDB.fallback_font, stat_panel.position + Vector2(8, 29), "$%s" % money, HORIZONTAL_ALIGNMENT_LEFT, 58.0, 14, Color(0.94, 0.90, 0.66))
	draw_string(ThemeDB.fallback_font, stat_panel.position + Vector2(92, 14), "Lives", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color(0.61, 0.66, 0.58))
	draw_string(ThemeDB.fallback_font, stat_panel.position + Vector2(92, 29), str(lives), HORIZONTAL_ALIGNMENT_LEFT, 42.0, 14, Color(0.88, 0.95, 0.84))
	draw_string(ThemeDB.fallback_font, stat_panel.position + Vector2(150, 14), "Wave", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color(0.61, 0.66, 0.58))
	draw_string(ThemeDB.fallback_font, stat_panel.position + Vector2(150, 29), str(wave), HORIZONTAL_ALIGNMENT_LEFT, 62.0, 14, Color(0.94, 0.95, 0.88))
	var reward_rect: Rect2 = Rect2(panel.position + Vector2(12, reward_y), Vector2(panel.size.x - 24, 20 if compact else 22))
	draw_rect(reward_rect, Color(0.10, 0.12, 0.105))
	draw_rect(reward_rect, Color(0.26, 0.31, 0.27), false, 1.0)
	draw_string(ThemeDB.fallback_font, reward_rect.position + Vector2(8, 15), "Reward", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.60, 0.65, 0.58))
	draw_string(ThemeDB.fallback_font, reward_rect.position + Vector2(reward_rect.size.x - 104, 15), "+$%s  +%s Tech" % [wave_reward_money, wave_reward_research], HORIZONTAL_ALIGNMENT_RIGHT, 96.0, 11, Color(0.90, 0.88, 0.72))


func _draw_sidebar_detail(pos: Vector2, label_text: String, value_text: String) -> void:
	draw_string(ThemeDB.fallback_font, pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.58, 0.63, 0.56))
	draw_string(ThemeDB.fallback_font, pos + Vector2(58, 0), value_text, HORIZONTAL_ALIGNMENT_LEFT, 168.0, 13, Color(0.88, 0.91, 0.84))


func _draw_shop_panel() -> void:
	var metrics := _layout_metrics()
	var panel: Rect2 = metrics["shop_panel_rect"]
	var bottom_layout := str(metrics["mode"]) == "bottom_dock"
	draw_rect(panel, Color(0.08, 0.10, 0.09))
	draw_rect(Rect2(panel.position, Vector2(panel.size.x, 4)), Color(0.38, 0.67, 0.74))
	draw_rect(Rect2(panel.position, panel.size), Color(0.27, 0.30, 0.26), false, 2.0)
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(20, 24), "Build", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(0.92, 0.92, 0.86))
	for button in get_shop_button_rects():
		_draw_shop_button(button)
	if not bottom_layout:
		_draw_wave_panel()
	var footer := Rect2(Vector2(panel.position.x + 10, panel.end.y - 24), Vector2(panel.size.x - 20, 18))
	draw_rect(footer, Color(0.10, 0.12, 0.11))
	draw_rect(footer, Color(0.24, 0.27, 0.24), false, 1.0)
	var feedback_message := str(latest_feedback.get("message", ""))
	var feedback_kind := str(latest_feedback.get("kind", ""))
	var footer_label := feedback_message if feedback_kind == "placement" and not feedback_message.is_empty() else "Tap a tower to place" if selected_build_type.is_empty() else "Selected: %s" % _tower_label(selected_build_type)
	var footer_color := Color(0.95, 0.60, 0.52) if feedback_kind == "placement" and not feedback_message.is_empty() else Color(0.74, 0.76, 0.72) if selected_build_type.is_empty() else _tower_color(selected_build_type)
	draw_string(ThemeDB.fallback_font, footer.position + Vector2(8, 12), footer_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, footer_color)


func _draw_shop_button(button: Dictionary) -> void:
	var rect: Rect2 = button["rect"]
	var tower_type: String = str(button["tower_type"])
	var color := _tower_color(tower_type)
	var affordable: bool = bool(button["affordable"])
	var selected: bool = bool(button["selected"])
	var enabled: bool = bool(button["enabled"])
	var fill := Color(0.16, 0.24, 0.19) if selected else Color(0.11, 0.13, 0.12)
	if not enabled:
		fill = Color(0.085, 0.095, 0.09)
	elif not affordable:
		fill = Color(0.19, 0.14, 0.14)
	var outline := color if enabled and affordable else Color(0.34, 0.37, 0.34)
	var label_color := Color(0.96, 0.96, 0.92) if enabled else Color(0.43, 0.46, 0.42)
	var cost_color := Color(0.88, 0.88, 0.80) if enabled else Color(0.39, 0.42, 0.38)
	draw_rect(rect, fill)
	draw_rect(rect, outline, false, 2.0)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4)), outline)
	if not enabled:
		draw_line(rect.position + Vector2(6, rect.size.y - 6), rect.position + Vector2(rect.size.x - 6, 6), Color(0.42, 0.46, 0.42, 0.45), 1.0)
		draw_line(rect.position + Vector2(20, rect.size.y - 4), rect.position + Vector2(rect.size.x - 4, 12), Color(0.32, 0.35, 0.32, 0.35), 1.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(6, 13), str(button["short_label"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, label_color)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(6, 23), "$%s" % button["cost"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, cost_color)


func _draw_wave_panel() -> void:
	if _uses_bottom_dock_layout():
		var panel: Rect2 = _layout_metrics()["wave_panel_rect"]
		draw_rect(panel, Color(0.07, 0.10, 0.075))
		draw_rect(Rect2(panel.position, Vector2(panel.size.x, 4.0)), Color(0.46, 0.78, 0.50))
		draw_rect(panel, Color(0.26, 0.34, 0.26), false, 2.0)
		draw_string(ThemeDB.fallback_font, panel.position + Vector2(16, 24), "Wave", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(0.92, 0.96, 0.86))
		draw_string(ThemeDB.fallback_font, panel.position + Vector2(16, panel.end.y - 20), "Reward +$%s  +%s Tech" % [wave_reward_money, wave_reward_research], HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 32.0, 11, Color(0.82, 0.82, 0.66))
	_draw_wave_control_button()


func _draw_wave_control_button() -> void:
	var rect := get_start_wave_button_rect()
	var enabled: bool = _can_start_wave_from_ui()
	var fill := Color(0.14, 0.24, 0.18) if enabled else Color(0.13, 0.14, 0.13)
	var outline := Color(0.46, 0.78, 0.50) if enabled else Color(0.33, 0.36, 0.32)
	var text_color := Color(0.94, 0.98, 0.90) if enabled else Color(0.58, 0.61, 0.56)
	draw_rect(rect, fill)
	draw_rect(rect, outline, false, 2.0)
	var disabled_reason := _wave_start_disabled_reason()
	var label_y := 16.0 if not enabled and not disabled_reason.is_empty() else 20.0
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(12, label_y), _wave_control_label(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, text_color)
	if not enabled and not disabled_reason.is_empty():
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(12, rect.size.y - 5.0), disabled_reason, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 9, Color(0.86, 0.68, 0.58))
	for button in get_speed_button_rects():
		_draw_speed_button(button)


func _draw_speed_button(button: Dictionary) -> void:
	var rect: Rect2 = button["rect"]
	var selected: bool = bool(button["selected"])
	var fill := Color(0.18, 0.27, 0.20) if selected else Color(0.10, 0.12, 0.11)
	var outline := Color(0.55, 0.82, 0.56) if selected else Color(0.31, 0.36, 0.31)
	var text_color := Color(0.96, 0.98, 0.92) if selected else Color(0.68, 0.72, 0.66)
	draw_rect(rect, fill)
	draw_rect(rect, outline, false, 1.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(8, 17), str(button["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, text_color)


func _draw_upgrade_panel() -> void:
	var panel := get_upgrade_panel_rect()
	var snapshot := upgrade_panel_snapshot()
	if not bool(snapshot.get("visible", false)):
		return
	var accent := _tower_color(str(snapshot.get("tower_type", ARCHER_ID)))
	if _uses_bottom_dock_layout():
		_draw_upgrade_panel_bottom(panel, snapshot, accent)
		return
	draw_rect(panel, Color(0.07, 0.09, 0.08))
	draw_rect(Rect2(panel.position, Vector2(panel.size.x, 4)), accent)
	draw_rect(panel, Color(0.30, 0.34, 0.28), false, 2.0)

	var header := Rect2(panel.position + Vector2(10, 8), Vector2(panel.size.x - 20, 44))
	draw_rect(header, Color(0.10, 0.12, 0.11))
	draw_rect(header, Color(0.42, 0.48, 0.38), false, 1.0)
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(14, 26), "Selected Tower", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.82, 0.86, 0.78))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(14, 48), str(snapshot["tower_name"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(0.96, 0.96, 0.92))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(14, 72), str(snapshot["stats"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.82, 0.82, 0.74))
	_draw_tower_stat_rows(panel.position + Vector2(96, 56), snapshot.get("stat_detail", {}))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(14, 108), str(snapshot["details"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.90, 0.86, 0.60))

	if bool(snapshot.get("needs_branch_choice", false)):
		for branch_button in get_branch_button_rects():
			_draw_branch_button(branch_button)
	else:
		for option_rect in get_upgrade_button_rects():
			_draw_upgrade_button(option_rect)

	_draw_target_button()
	_draw_sell_button()


func _draw_upgrade_panel_bottom(panel: Rect2, snapshot: Dictionary, accent: Color) -> void:
	draw_rect(panel, Color(0.07, 0.09, 0.08))
	draw_rect(Rect2(panel.position, Vector2(panel.size.x, 4)), accent)
	draw_rect(panel, Color(0.30, 0.34, 0.28), false, 2.0)

	draw_string(ThemeDB.fallback_font, panel.position + Vector2(14, 22), "Selected Tower", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.82, 0.86, 0.78))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(14, 46), str(snapshot["tower_name"]), HORIZONTAL_ALIGNMENT_LEFT, 190.0, 17, Color(0.96, 0.96, 0.92))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(14, 68), str(snapshot["stats"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.82, 0.82, 0.74))

	var stats: Dictionary = snapshot.get("stat_detail", {})
	if not stats.is_empty():
		var stat_text := "Damage %s   Range %s   Fire %s" % [
			int(stats.get("damage", 0)),
			int(stats.get("range", 0)),
			str(stats.get("shooting_speed_label", "0.0/s")),
		]
		draw_string(ThemeDB.fallback_font, panel.position + Vector2(212, 27), stat_text, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 232.0, 11, Color(0.76, 0.82, 0.72))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(212, 48), _truncate_text(str(snapshot["details"]), 82), HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 232.0, 12, Color(0.90, 0.86, 0.60))

	if bool(snapshot.get("needs_branch_choice", false)):
		for branch_button in get_branch_button_rects():
			_draw_branch_button(branch_button)
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
	var outline := _tower_color(str(snapshot.get("tower_type", ARCHER_ID))) if enabled else Color(0.47, 0.27, 0.27)
	var description: String = str(option.get("description", ""))
	var disabled_reason := str(option.get("disabled_reason", ""))
	draw_rect(rect, fill)
	draw_rect(rect, outline, false, 2.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 20), str(option["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.94, 0.94, 0.88))
	if not enabled and not disabled_reason.is_empty():
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 38), disabled_reason, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 76.0, 11, Color(0.92, 0.62, 0.56))
	elif not description.is_empty():
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 38), description, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 76.0, 11, Color(0.76, 0.82, 0.70))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(rect.size.x - 58, 20), "$%s" % option["cost"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(0.88, 0.88, 0.80))


func _draw_branch_button(button: Dictionary) -> void:
	var rect: Rect2 = button["rect"]
	var color_values: Array = button.get("color", [95, 185, 95])
	var accent := _color_from_array(color_values)
	var fill := Color(accent.r * 0.22, accent.g * 0.22, accent.b * 0.22, 1.0)
	var focus_name := str(button.get("focus_name", button.get("name", "")))
	var focus_category := str(button.get("focus_category", "General"))
	var perk_summary := str(button.get("perk_summary", ""))
	var preview := str(button.get("effect_preview", ""))
	var perk_line := "%s focus" % focus_category
	if not perk_summary.is_empty():
		perk_line = "%s | %s" % [perk_line, perk_summary]
	draw_rect(rect, fill)
	draw_rect(rect, accent, false, 2.0)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3.0)), Color(accent.r, accent.g, accent.b, 0.38))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 13), focus_name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0, 12, Color(0.96, 0.96, 0.90))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 25), _truncate_text(perk_line, 38), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0, 9, Color(0.78, 0.83, 0.70))
	if rect.size.y >= 34.0 and not preview.is_empty():
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 35), _truncate_text(preview, 48), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0, 8, Color(0.62, 0.68, 0.58))


func _truncate_text(text: String, max_chars: int) -> String:
	if text.length() <= max_chars:
		return text
	if max_chars <= 3:
		return text.substr(0, max_chars)
	return "%s..." % text.substr(0, max_chars - 3)


func _draw_tower_stat_rows(pos: Vector2, stats: Dictionary) -> void:
	if stats.is_empty():
		return
	_draw_stat_bar_row(pos, "Damage", str(int(stats.get("damage", 0))), stats.get("damage_rating", {}))
	_draw_stat_bar_row(pos + Vector2(0, 20), "Range", str(int(stats.get("range", 0))), stats.get("range_rating", {}))
	_draw_stat_bar_row(pos + Vector2(0, 40), "Fire", str(stats.get("shooting_speed_label", "0.0/s")), stats.get("shooting_speed_rating", {}))


func _draw_stat_bar_row(pos: Vector2, label_text: String, value_text: String, rating: Dictionary) -> void:
	var ratio: float = float(rating.get("ratio", 0.5))
	var rating_label: String = str(rating.get("label", "Med"))
	draw_string(ThemeDB.fallback_font, pos, "%s %s" % [label_text, value_text], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color(0.77, 0.80, 0.72))
	var bar := Rect2(pos + Vector2(78, -9), Vector2(58, 7))
	draw_rect(bar, Color(0.13, 0.15, 0.13))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), _stat_rating_color(ratio))
	draw_rect(bar, Color(0.31, 0.36, 0.31), false, 1.0)
	draw_string(ThemeDB.fallback_font, pos + Vector2(142, 0), rating_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color(0.72, 0.76, 0.68))


func _stat_rating_color(ratio: float) -> Color:
	if ratio >= 0.66:
		return Color(0.56, 0.82, 0.50)
	if ratio >= 0.33:
		return Color(0.84, 0.72, 0.36)
	return Color(0.62, 0.68, 0.60)


func get_branch_button_rects() -> Array:
	var panel := get_upgrade_panel_rect()
	var snapshot := upgrade_panel_snapshot()
	if not bool(snapshot.get("needs_branch_choice", false)):
		return []
	var options: Array = snapshot.get("branch_options", [])
	if options.is_empty():
		return []
	var rects: Array = []
	if _uses_bottom_dock_layout():
		var gap := 6.0
		var button_height := 44.0
		var button_width := (panel.size.x - 28.0 - gap * float(options.size() - 1)) / float(options.size())
		var start_y := panel.position.y + 82.0
		for index in range(options.size()):
			var option: Dictionary = options[index]
			rects.append({
				"rect": Rect2(Vector2(panel.position.x + 14.0 + float(index) * (button_width + gap), start_y), Vector2(button_width, button_height)),
				"branch_id": str(option.get("id", "")),
				"name": str(option.get("name", "")),
				"focus_name": str(option.get("focus_name", option.get("name", ""))),
				"canonical_name": str(option.get("canonical_name", "")),
				"focus_category": str(option.get("focus_category", "")),
				"perk_summary": str(option.get("perk_summary", "")),
				"short": str(option.get("short", "")),
				"role": str(option.get("role", "")),
				"effect_preview": str(option.get("effect_preview", "")),
				"color": option.get("color", [95, 185, 95]),
			})
		return rects
	var start_y: float = panel.position.y + 120.0
	var gap := 4.0
	var available_height: float = get_target_button_rect().position.y - start_y - 6.0
	var button_height: float = min(38.0, max(32.0, (available_height - gap * float(options.size() - 1)) / float(options.size())))
	for index in range(options.size()):
		var option: Dictionary = options[index]
		rects.append({
			"rect": Rect2(Vector2(panel.position.x + 14.0, start_y + float(index) * (button_height + gap)), Vector2(panel.size.x - 28.0, button_height)),
			"branch_id": str(option.get("id", "")),
			"name": str(option.get("name", "")),
			"focus_name": str(option.get("focus_name", option.get("name", ""))),
			"canonical_name": str(option.get("canonical_name", "")),
			"focus_category": str(option.get("focus_category", "")),
			"perk_summary": str(option.get("perk_summary", "")),
			"short": str(option.get("short", "")),
			"role": str(option.get("role", "")),
			"effect_preview": str(option.get("effect_preview", "")),
			"color": option.get("color", [95, 185, 95]),
		})
	return rects


func get_upgrade_button_rects() -> Array:
	var panel := get_upgrade_panel_rect()
	var snapshot := upgrade_panel_snapshot()
	var options: Array = snapshot.get("upgrade_options", [])
	if bool(snapshot.get("needs_branch_choice", false)) or options.is_empty():
		return []
	if _uses_bottom_dock_layout():
		return [Rect2(panel.position + Vector2(14, 82), Vector2(panel.size.x - 28, 42))]
	return [Rect2(panel.position + Vector2(14, 130), Vector2(panel.size.x - 28, 48))]


func _draw_target_button() -> void:
	var rect := get_target_button_rect()
	var snapshot := upgrade_panel_snapshot()
	draw_rect(rect, Color(0.13, 0.17, 0.20))
	draw_rect(rect, Color(0.43, 0.59, 0.75), false, 2.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(12, 17), str(snapshot["target_label"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(0.88, 0.92, 0.96))


func _draw_sell_button() -> void:
	var rect := get_sell_button_rect()
	var snapshot := upgrade_panel_snapshot()
	draw_rect(rect, Color(0.20, 0.15, 0.13))
	draw_rect(rect, Color(0.84, 0.49, 0.33), false, 2.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(12, 17), str(snapshot["sell_label"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(1.0, 0.90, 0.82))


func runtime_invariant_failures() -> Array:
	var failures: Array = []
	_check_global_invariants(failures)
	_check_tower_invariants(failures)
	_check_enemy_invariants(failures)
	_check_projectile_invariants(failures)
	return failures


func _tick_runtime_invariants(delta: float, context: String) -> void:
	invariant_check_timer += max(0.0, delta)
	if invariant_check_timer < INVARIANT_CHECK_INTERVAL:
		return
	invariant_check_timer = 0.0
	_check_runtime_invariants(context)


func _check_runtime_invariants(context: String) -> void:
	var failures := runtime_invariant_failures()
	if failures.is_empty():
		return
	push_error("RUNTIME_INVARIANT_FAILED %s: %s" % [context, _join_strings(failures, " | ")])


func _check_global_invariants(failures: Array) -> void:
	_require_nonnegative_int(failures, "money", money)
	_require_nonnegative_int(failures, "lives", lives)
	_require_nonnegative_int(failures, "research_points", research_points)
	_require_nonnegative_int(failures, "wave", wave)
	_require_nonnegative_int(failures, "spawned_this_wave", spawned_this_wave)
	_require_nonnegative_int(failures, "leaks", leaks)
	_require_nonnegative_int(failures, "kills", kills)
	_require_nonnegative_int(failures, "wave_reward_money", wave_reward_money)
	_require_nonnegative_int(failures, "wave_reward_research", wave_reward_research)
	_require_nonnegative_float(failures, "spawn_timer", spawn_timer)
	if not GAME_SPEEDS.has(game_speed):
		failures.append("game_speed unsupported: %s" % game_speed)
	var schedule := _wave_schedule()
	if not schedule.is_empty() and (wave < 1 or wave > schedule.size()):
		failures.append("wave outside schedule: %s of %s" % [wave, schedule.size()])
	if spawned_this_wave > _regular_enemy_count():
		failures.append("spawned_this_wave exceeds regular enemy count: %s > %s" % [spawned_this_wave, _regular_enemy_count()])
	if game_over and wave_active:
		failures.append("game_over with active wave")
	if wave_complete and wave_active:
		failures.append("wave_complete with active wave")
	if wave_complete and not enemies.is_empty():
		failures.append("wave_complete with enemies remaining: %s" % enemies.size())
	if selected_tower_index != NO_SELECTED_TOWER and (selected_tower_index < 0 or selected_tower_index >= towers.size()):
		failures.append("selected_tower_index out of range: %s of %s" % [selected_tower_index, towers.size()])
	if not selected_build_type.is_empty() and not _current_slice_shop_towers().has(selected_build_type):
		failures.append("selected_build_type not in shop data: %s" % selected_build_type)
	if path_points.size() < 2:
		failures.append("path_points too short: %s" % path_points.size())


func _check_tower_invariants(failures: Array) -> void:
	var target_modes: Array = game_data.get("towers", {}).get("target_modes", [])
	for index in range(towers.size()):
		var raw_tower: Variant = towers[index]
		if not (raw_tower is Dictionary):
			failures.append("tower %s is not a Dictionary" % index)
			continue
		var tower: Dictionary = raw_tower
		var tower_type := str(tower.get("type", ""))
		if tower_type.is_empty() or _tower_data(tower_type).is_empty():
			failures.append("tower %s unknown type: %s" % [index, tower_type])
		if not (tower.get("position", Vector2.ZERO) is Vector2):
			failures.append("tower %s position is not Vector2" % index)
		_require_positive_int(failures, "tower %s level" % index, int(tower.get("level", 0)))
		_require_nonnegative_float(failures, "tower %s range" % index, float(tower.get("range", 0.0)))
		_require_nonnegative_float(failures, "tower %s damage" % index, float(tower.get("damage", 0.0)))
		_require_nonnegative_float(failures, "tower %s fire_rate" % index, float(tower.get("fire_rate", 0.0)))
		_require_nonnegative_float(failures, "tower %s cooldown" % index, float(tower.get("cooldown", 0.0)))
		_require_nonnegative_int(failures, "tower %s kills" % index, int(tower.get("kills", 0)))
		_require_nonnegative_int(failures, "tower %s money_spent" % index, int(tower.get("money_spent", 0)))
		_require_nonnegative_float(failures, "tower %s total_damage" % index, float(tower.get("total_damage", 0.0)))
		_require_nonnegative_float(failures, "tower %s mastery_xp" % index, float(tower.get("mastery_xp", 0.0)))
		var target_mode := str(tower.get("target_mode", ""))
		if not target_modes.has(target_mode):
			failures.append("tower %s invalid target_mode: %s" % [index, target_mode])
		var selected_branch := str(tower.get("selected_branch", ""))
		if not selected_branch.is_empty() and not _branch_definitions_for_tower(tower_type).has(selected_branch):
			failures.append("tower %s invalid selected_branch: %s" % [index, selected_branch])


func _check_enemy_invariants(failures: Array) -> void:
	for index in range(enemies.size()):
		var raw_enemy: Variant = enemies[index]
		if not (raw_enemy is Dictionary):
			failures.append("enemy %s is not a Dictionary" % index)
			continue
		var enemy: Dictionary = raw_enemy
		var enemy_kind := str(enemy.get("kind", ""))
		if not CANONICAL_ENEMY_KINDS.has(enemy_kind):
			failures.append("enemy %s unknown kind: %s" % [index, enemy_kind])
		if not (enemy.get("position", Vector2.ZERO) is Vector2):
			failures.append("enemy %s position is not Vector2" % index)
		var target_index := int(enemy.get("target_index", 0))
		if target_index < 0 or target_index > path_points.size():
			failures.append("enemy %s target_index out of range: %s of %s" % [index, target_index, path_points.size()])
		_require_finite_float(failures, "enemy %s hp" % index, float(enemy.get("hp", 0.0)))
		var max_hp := float(enemy.get("max_hp", 0.0))
		_require_positive_float(failures, "enemy %s max_hp" % index, max_hp)
		if float(enemy.get("hp", 0.0)) > max_hp + 0.001:
			failures.append("enemy %s hp exceeds max_hp: %s > %s" % [index, enemy.get("hp", 0.0), max_hp])
		_require_nonnegative_float(failures, "enemy %s speed" % index, float(enemy.get("speed", 0.0)))
		_require_nonnegative_int(failures, "enemy %s reward" % index, int(enemy.get("reward", 0)))
		_require_nonnegative_float(failures, "enemy %s progress" % index, float(enemy.get("progress", 0.0)))
		_require_nonnegative_float(failures, "enemy %s marked_timer" % index, float(enemy.get("marked_timer", 0.0)))
		_require_nonnegative_float(failures, "enemy %s vulnerable_timer" % index, float(enemy.get("vulnerable_timer", 0.0)))
		_require_nonnegative_int(failures, "enemy %s shield_hits" % index, int(enemy.get("shield_hits", 0)))
		_require_nonnegative_int(failures, "enemy %s max_shield_hits" % index, int(enemy.get("max_shield_hits", 0)))
		if int(enemy.get("shield_hits", 0)) > int(enemy.get("max_shield_hits", 0)):
			failures.append("enemy %s shield_hits exceeds max_shield_hits" % index)
		_require_nonnegative_float(failures, "enemy %s damage_taken_multiplier" % index, float(enemy.get("damage_taken_multiplier", 1.0)))
		_require_nonnegative_float(failures, "enemy %s regen_scale" % index, float(enemy.get("regen_scale", 0.0)))
		_require_nonnegative_int(failures, "enemy %s death_spawns" % index, int(enemy.get("death_spawns", 0)))
		_require_nonnegative_float(failures, "enemy %s death_burst_damage_fraction" % index, float(enemy.get("death_burst_damage_fraction", 0.0)))
		_require_nonnegative_float(failures, "enemy %s death_burst_radius" % index, float(enemy.get("death_burst_radius", 0.0)))


func _check_projectile_invariants(failures: Array) -> void:
	for index in range(projectiles.size()):
		var raw_projectile: Variant = projectiles[index]
		if not (raw_projectile is Dictionary):
			failures.append("projectile %s is not a Dictionary" % index)
			continue
		var projectile: Dictionary = raw_projectile
		if not (projectile.get("position", Vector2.ZERO) is Vector2):
			failures.append("projectile %s position is not Vector2" % index)
		_require_nonnegative_float(failures, "projectile %s damage" % index, float(projectile.get("damage", 0.0)))
		_require_nonnegative_float(failures, "projectile %s speed" % index, float(projectile.get("speed", 0.0)))
		_require_nonnegative_float(failures, "projectile %s trail_timer" % index, float(projectile.get("trail_timer", 0.0)))
		if bool(projectile.get("dead", false)):
			continue
		var target: Variant = projectile.get("target", {})
		var tower: Variant = projectile.get("tower", {})
		if not (target is Dictionary) or not enemies.has(target):
			failures.append("projectile %s has missing live target" % index)
		if not (tower is Dictionary) or not towers.has(tower):
			failures.append("projectile %s has missing source tower" % index)


func _require_positive_int(failures: Array, label: String, value: int) -> void:
	if value <= 0:
		failures.append("%s must be positive: %s" % [label, value])


func _require_nonnegative_int(failures: Array, label: String, value: int) -> void:
	if value < 0:
		failures.append("%s must be nonnegative: %s" % [label, value])


func _require_positive_float(failures: Array, label: String, value: float) -> void:
	if is_nan(value) or is_inf(value) or value <= 0.0:
		failures.append("%s must be positive finite: %s" % [label, value])


func _require_finite_float(failures: Array, label: String, value: float) -> void:
	if is_nan(value) or is_inf(value):
		failures.append("%s must be finite: %s" % [label, value])


func _require_nonnegative_float(failures: Array, label: String, value: float) -> void:
	if is_nan(value) or is_inf(value) or value < 0.0:
		failures.append("%s must be nonnegative finite: %s" % [label, value])


func _join_strings(values: Array, separator: String) -> String:
	var text := ""
	for value in values:
		if not text.is_empty():
			text += separator
		text += str(value)
	return text


func _emit_status() -> void:
	status_changed.emit(status_snapshot())


func _set_feedback(kind: String, message: String) -> void:
	latest_feedback = {
		"kind": kind,
		"message": message,
	}
	_emit_status()
	queue_redraw()


func _clear_feedback() -> void:
	latest_feedback = {}


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


func _progress_game_speed() -> float:
	var progress := _progress()
	if progress == null:
		return 1.0
	var speed := float(progress.settings.get("game_speed", 1.0))
	return speed if GAME_SPEEDS.has(speed) else 1.0


func _game_speed_label() -> String:
	if game_speed <= 0.0:
		return "Paused"
	if is_equal_approx(game_speed, 1.0):
		return "1x"
	if is_equal_approx(game_speed, 2.0):
		return "2x"
	if is_equal_approx(game_speed, 4.0):
		return "4x"
	return "%.1fx" % game_speed


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


func _draw_texture(tex: Texture2D, center: Vector2, size: Vector2, modulate: Color = Color.WHITE) -> void:
	draw_texture_rect(tex, Rect2(center - size * 0.5, size), false, modulate)


func _play_sound(relative_path: String, fallback_frequency: float) -> void:
	var audio := _audio()
	if audio != null:
		audio.play_sound(relative_path, fallback_frequency)
