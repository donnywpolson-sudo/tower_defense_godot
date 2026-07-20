extends SceneTree

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const REQUIRED_AUTOLOADS := [
	"GameConfig",
	"GameData",
	"GameAssets",
	"GameAudio",
	"GameProgress",
	"ParityHarness",
]
const REQUIRED_INPUT_ACTIONS := [
	"start_wave",
	"pause_game",
	"restart_run",
	"toggle_audio",
	"target_mode",
	"upgrade_tower",
	"sell_tower",
	"speed_1",
	"speed_2",
	"speed_3",
]


func _initialize() -> void:
	var result := {
		"ok": true,
		"checks": [],
		"errors": [],
	}
	_check_application_settings(result)
	_check_autoloads(result)
	_check_input_map(result)
	_check_main_scene(result)
	_check_export_presets_scope(result)

	if result["ok"]:
		print("EXPORT_PLATFORM_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("EXPORT_PLATFORM_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)


func _check_application_settings(result: Dictionary) -> void:
	_record_check(result, "app_name_configured", str(ProjectSettings.get_setting("application/config/name", "")) == "Tower Defense", ProjectSettings.get_setting("application/config/name", ""))
	_record_check(result, "app_version_configured", str(ProjectSettings.get_setting("application/config/version", "")).length() > 0, ProjectSettings.get_setting("application/config/version", ""))
	_record_check(result, "main_scene_setting_uses_res_path", str(ProjectSettings.get_setting("application/run/main_scene", "")) == MAIN_SCENE_PATH, ProjectSettings.get_setting("application/run/main_scene", ""))
	_record_check(result, "viewport_width_configured", int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) == 1180, ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	_record_check(result, "viewport_height_configured", int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)) == 600, ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	_record_check(result, "renderer_mobile_configured", str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")) == "mobile", ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))


func _check_autoloads(result: Dictionary) -> void:
	var missing: Array = []
	for autoload_name in REQUIRED_AUTOLOADS:
		var path := str(ProjectSettings.get_setting("autoload/%s" % autoload_name, ""))
		if path.is_empty() or not path.begins_with("*res://scripts/autoload/"):
			missing.append({"name": autoload_name, "path": path})
	_record_check(result, "required_autoloads_configured", missing.is_empty(), missing)


func _check_input_map(result: Dictionary) -> void:
	var missing: Array = []
	for action in REQUIRED_INPUT_ACTIONS:
		if not InputMap.has_action(action) or InputMap.action_get_events(action).is_empty():
			missing.append(action)
	_record_check(result, "required_input_actions_configured", missing.is_empty(), missing)


func _check_main_scene(result: Dictionary) -> void:
	var packed_scene := load(MAIN_SCENE_PATH)
	_record_check(result, "main_scene_loads_for_export", packed_scene is PackedScene, MAIN_SCENE_PATH)
	if not packed_scene is PackedScene:
		return
	var instance: Node = packed_scene.instantiate()
	_record_check(result, "main_scene_instantiates_for_export", instance != null, MAIN_SCENE_PATH)
	if instance != null:
		_record_check(result, "main_scene_has_game_root_for_export", instance.get_node_or_null("VerticalSliceGame") != null, "VerticalSliceGame")
		instance.free()


func _check_export_presets_scope(result: Dictionary) -> void:
	if not FileAccess.file_exists("res://export_presets.cfg"):
		_record_check(result, "export_presets_absent_release_export_not_claimed", true, "No export preset is configured; this lane proves project export readiness only.")
		return
	var text := FileAccess.get_file_as_string("res://export_presets.cfg")
	_record_check(result, "export_presets_parseable_text", text.contains("[preset.") and text.contains("platform="), "export_presets.cfg")


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	ValidationHarness.record_check(result, label, passed, detail)
