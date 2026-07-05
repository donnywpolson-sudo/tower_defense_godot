extends SceneTree

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const SCREENSHOT_DIR := "res://logs/godot/visual_review"
const VIEWPORTS := [
	{"label": "pinned_1180x600", "size": Vector2i(1180, 600)},
	{"label": "bottom_dock_1180x820", "size": Vector2i(1180, 820)},
]

var _errors: Array = []
var _checks: Array = []
var _main: Node = null
var _game: Node = null


func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	_prepare_output_dir()
	await _instantiate_main_scene()
	if _game != null:
		_exercise_representative_inputs()
		await process_frame
		await _validate_viewports_and_screenshots()
	_cleanup()
	if _errors.is_empty():
		print("PLAYABLE_SURFACE_VALIDATION_OK")
		for check in _checks:
			print("  %s" % str(check))
		quit(0)
	else:
		push_error("PLAYABLE_SURFACE_VALIDATION_FAILED")
		for error in _errors:
			push_error(str(error))
		quit(1)


func _prepare_output_dir() -> void:
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCREENSHOT_DIR))
	_record_check("screenshot_dir_created", error == OK or error == ERR_ALREADY_EXISTS, SCREENSHOT_DIR)


func _instantiate_main_scene() -> void:
	var packed_scene := load(MAIN_SCENE_PATH)
	_record_check("main_scene_loads", packed_scene is PackedScene, MAIN_SCENE_PATH)
	if not packed_scene is PackedScene:
		return
	_main = packed_scene.instantiate()
	_record_check("main_scene_instantiates", _main != null, MAIN_SCENE_PATH)
	if _main == null:
		return
	root.add_child(_main)
	await process_frame
	_game = _main.get_node_or_null("VerticalSliceGame")
	_record_check("main_scene_has_vertical_slice", _game != null, "VerticalSliceGame")
	_record_check("main_scene_has_debug_hud", _main.get_node_or_null("DebugHUD") != null, "DebugHUD")
	_record_check("vertical_slice_has_status_signal", _game != null and _game.has_signal("status_changed"), "status_changed")
	_record_check("vertical_slice_has_layout_snapshot", _game != null and _game.has_method("layout_snapshot"), "layout_snapshot")


func _exercise_representative_inputs() -> void:
	_send_key_action("speed_2")
	_record_check("keyboard_speed_2_sets_speed", is_equal_approx(float(_game.snapshot().get("game_speed", 0.0)), 2.0), _game.snapshot())
	_send_key_action("pause_game")
	_record_check("keyboard_pause_sets_zero_speed", is_equal_approx(float(_game.snapshot().get("game_speed", -1.0)), 0.0), _game.snapshot())
	_send_key_action("speed_1")
	_record_check("keyboard_speed_1_sets_speed", is_equal_approx(float(_game.snapshot().get("game_speed", 0.0)), 1.0), _game.snapshot())

	var shop_buttons: Array = _game.get_shop_button_rects()
	_record_check("shop_buttons_available", not shop_buttons.is_empty(), shop_buttons)
	if shop_buttons.is_empty():
		return
	var archer_button := _first_button_for_tower(shop_buttons, "archer")
	_record_check("archer_shop_button_available", not archer_button.is_empty(), shop_buttons)
	if archer_button.is_empty():
		return
	_send_mouse(MOUSE_BUTTON_LEFT, _rect_center(archer_button["rect"]))
	_record_check("mouse_shop_selects_archer", str(_game.snapshot().get("selected_build_type", "")) == "archer", _game.snapshot())

	_send_mouse(MOUSE_BUTTON_RIGHT, Vector2(24, 24))
	_record_check("right_click_cancels_build", str(_game.snapshot().get("selected_build_type", "")) == "", _game.snapshot())

	_send_mouse(MOUSE_BUTTON_LEFT, _rect_center(archer_button["rect"]))
	var site := _first_valid_build_site()
	_record_check("valid_build_site_available", site != Vector2.INF, site)
	if site != Vector2.INF:
		_send_mouse(MOUSE_BUTTON_LEFT, _game.map_to_screen_position(site))
		_record_check("mouse_map_places_tower", int(_game.snapshot().get("tower_count", 0)) >= 1, _game.snapshot())
		_send_mouse(MOUSE_BUTTON_RIGHT, Vector2(24, 24))
		_send_mouse(MOUSE_BUTTON_LEFT, _game.map_to_screen_position(site))
		_record_check("mouse_map_selects_tower", int(_game.upgrade_panel_snapshot().get("selected_tower_index", -1)) != -1, _game.upgrade_panel_snapshot())
		var target_rect: Rect2 = _game.get_target_button_rect()
		_send_mouse(MOUSE_BUTTON_LEFT, _rect_center(target_rect))
		_record_check("target_button_click_exercised", str(_game.upgrade_panel_snapshot().get("target_mode", "")).length() > 0, _game.upgrade_panel_snapshot())

	var speed_buttons: Array = _game.get_speed_button_rects()
	_record_check("speed_buttons_available", speed_buttons.size() >= 3, speed_buttons)
	if speed_buttons.size() >= 2:
		_send_mouse(MOUSE_BUTTON_LEFT, _rect_center(speed_buttons[1]["rect"]))
		_record_check("mouse_speed_button_sets_speed", is_equal_approx(float(_game.snapshot().get("game_speed", 0.0)), float(speed_buttons[1]["speed"])), _game.snapshot())

	_send_mouse(MOUSE_BUTTON_LEFT, _rect_center(_game.get_start_wave_button_rect()))
	_record_check("wave_start_click_path_exercised", bool(_game.wave_control_snapshot().get("wave_active", false)) or not str(_game.wave_control_snapshot().get("disabled_reason", "")).is_empty(), _game.wave_control_snapshot())


func _validate_viewports_and_screenshots() -> void:
	for viewport in VIEWPORTS:
		var size: Vector2i = viewport["size"]
		var label := str(viewport["label"])
		root.size = size
		_game.set_layout_viewport_override_for_tests(Vector2(size))
		await process_frame
		await process_frame
		var layout: Dictionary = _game.layout_snapshot()
		_validate_layout(label, size, layout)
		_game.queue_redraw()
		await process_frame
		_save_screenshot(label)
	_game.clear_layout_viewport_override_for_tests()


func _validate_layout(label: String, size: Vector2i, layout: Dictionary) -> void:
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(size))
	var map_rect: Rect2 = layout["map_rect"]
	var build_panel: Rect2 = layout["build_panel_rect"]
	var wave_panel: Rect2 = layout["wave_panel_rect"]
	var detail_panel: Rect2 = layout["detail_panel_rect"]
	_record_check("%s_map_inside_viewport" % label, _rect_inside(map_rect, viewport_rect), layout)
	_record_check("%s_panels_positive" % label, _rect_positive(build_panel) and _rect_positive(wave_panel) and _rect_positive(detail_panel), layout)
	if str(layout["mode"]) == "bottom_dock":
		var dock: Rect2 = layout["dock_rect"]
		_record_check("%s_dock_inside_viewport" % label, _rect_inside(dock, viewport_rect), layout)
		_record_check("%s_bottom_panels_inside_dock" % label, _rect_inside(build_panel, dock) and _rect_inside(wave_panel, dock) and _rect_inside(detail_panel, dock), layout)
		_record_check("%s_bottom_panels_do_not_overlap" % label, not build_panel.intersects(wave_panel) and not wave_panel.intersects(detail_panel) and not build_panel.intersects(detail_panel), layout)
	else:
		var sidebar: Rect2 = layout["sidebar_rect"]
		_record_check("%s_sidebar_inside_viewport" % label, _rect_inside(sidebar, viewport_rect), layout)
		_record_check("%s_sidebar_panels_inside_sidebar" % label, _rect_inside(build_panel, sidebar) and _rect_inside(wave_panel, sidebar) and _rect_inside(detail_panel, sidebar), layout)


func _save_screenshot(label: String) -> void:
	var texture := root.get_texture()
	if texture == null:
		_record_check("%s_screenshot_texture_available" % label, false, "Viewport texture unavailable; run this validator with a rendering display driver, not dummy headless rendering.")
		return
	var image := texture.get_image()
	if image == null:
		_record_check("%s_screenshot_image_available" % label, false, "Viewport image unavailable; run this validator with a rendering display driver, not dummy headless rendering.")
		return
	var path := "%s/playable_surface_%s.png" % [SCREENSHOT_DIR, label]
	var error := image.save_png(ProjectSettings.globalize_path(path))
	_record_check("%s_screenshot_saved" % label, error == OK, path)


func _send_key_action(action: String) -> void:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		_record_check("%s_action_has_event" % action, false, action)
		return
	var event: InputEvent = events[0].duplicate()
	event.pressed = true
	_game._unhandled_input(event)


func _send_mouse(button: int, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = position
	event.pressed = true
	_game._unhandled_input(event)


func _first_button_for_tower(buttons: Array, tower_type: String) -> Dictionary:
	for button in buttons:
		if str(button.get("tower_type", "")) == tower_type and bool(button.get("enabled", false)):
			return button
	return {}


func _first_valid_build_site() -> Vector2:
	for y in range(108, 568, 27):
		for x in range(54, 838, 27):
			var site := Vector2(x, y)
			if _game.can_place_tower(site):
				return site
	return Vector2.INF


func _rect_center(rect: Rect2) -> Vector2:
	return rect.position + rect.size * 0.5


func _rect_inside(inner: Rect2, outer: Rect2) -> bool:
	return outer.has_point(inner.position) and outer.has_point(inner.end - Vector2(0.5, 0.5))


func _rect_positive(rect: Rect2) -> bool:
	return rect.size.x > 0.0 and rect.size.y > 0.0


func _record_check(label: String, passed: bool, detail: Variant) -> void:
	_checks.append({"label": label, "passed": passed})
	if not passed:
		_errors.append("%s failed: %s" % [label, str(detail)])


func _cleanup() -> void:
	if _main != null:
		root.remove_child(_main)
		_main.free()
		_main = null
		_game = null
