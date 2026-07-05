extends Node

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const MAIN_SCRIPT_PATH := "res://scripts/main.gd"


func run_placeholder_scene_smoke() -> Dictionary:
	var result := {
		"ok": true,
		"checks": [],
		"errors": [],
	}
	_check_project_settings(result)
	_check_scene_loads(result)
	return result


func _check_project_settings(result: Dictionary) -> void:
	var viewport_width := int(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var viewport_height := int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	_record_check(result, "viewport_width", viewport_width == GameConfig.LOGICAL_WIDTH, viewport_width)
	_record_check(result, "viewport_height", viewport_height == GameConfig.LOGICAL_HEIGHT, viewport_height)
	_record_check(result, "stretch_mode_canvas_items", str(ProjectSettings.get_setting("display/window/stretch/mode")) == "canvas_items", ProjectSettings.get_setting("display/window/stretch/mode"))
	_record_check(result, "stretch_aspect_expand", str(ProjectSettings.get_setting("display/window/stretch/aspect")) == "expand", ProjectSettings.get_setting("display/window/stretch/aspect"))
	var features: Variant = ProjectSettings.get_setting("application/config/features")
	_record_check(result, "godot_minor_pin", str(features).contains(GameConfig.GODOT_MINOR_PIN), features)


func _check_scene_loads(result: Dictionary) -> void:
	var packed_scene := load(MAIN_SCENE_PATH)
	_record_check(result, "main_scene_loads", packed_scene is PackedScene, MAIN_SCENE_PATH)
	if not packed_scene is PackedScene:
		return

	var instance: Node = packed_scene.instantiate()
	_record_check(result, "main_scene_instantiates", instance != null, MAIN_SCENE_PATH)
	if instance == null:
		return

	_record_check(result, "main_scene_root_name", instance.name == "Main", instance.name)
	_record_check(result, "main_scene_has_script", instance.get_script() != null, MAIN_SCRIPT_PATH)
	_record_check(result, "main_scene_has_debug_hud", instance.has_node("DebugHUD"), "DebugHUD")
	_record_check(result, "main_scene_has_vertical_slice", instance.has_node("VerticalSliceGame"), "VerticalSliceGame")
	instance.queue_free()


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	result["checks"].append({
		"label": label,
		"passed": passed,
		"detail": detail,
	})
	if not passed:
		result["ok"] = false
		result["errors"].append("%s failed: %s" % [label, str(detail)])
