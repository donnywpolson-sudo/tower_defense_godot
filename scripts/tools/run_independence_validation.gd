extends SceneTree

const SELF_PATH := "res://scripts/tools/run_independence_validation.gd"
const TEXT_EXTENSIONS := [
	"cfg",
	"gd",
	"godot",
	"gdshader",
	"import",
	"json",
	"md",
	"ps1",
	"tres",
	"tscn",
	"txt",
	"uid",
]
const SKIP_DIRS := [".git", ".godot", ".import", ".agents", ".codex"]


func _initialize() -> void:
	var result := {
		"ok": true,
		"checks": [],
		"errors": [],
	}
	_check_canonical_data_paths(result)
	_check_removed_migration_tools(result)
	_check_no_blocked_tokens(result)

	if result["ok"]:
		print("INDEPENDENCE_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("INDEPENDENCE_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)


func _check_canonical_data_paths(result: Dictionary) -> void:
	var canonical_data_path := "res://data/game_data.json"
	var retired_data_path := "res://data/" + _py_word() + "_" + _base_word() + "_data.json"
	_record_check(result, "canonical_data_exists", FileAccess.file_exists(canonical_data_path), canonical_data_path)
	_record_check(result, "retired_data_mirror_removed", not FileAccess.file_exists(retired_data_path), "removed")

	var loader_text := _read_text("res://scripts/autoload/game_data.gd")
	_record_check(result, "loader_uses_res_canonical_data", loader_text.contains(canonical_data_path), "GameData DATA_PATH")
	_record_check(result, "loader_omits_retired_data_name", not loader_text.contains(retired_data_path.get_file()), "GameData DATA_PATH")


func _check_removed_migration_tools(result: Dictionary) -> void:
	var py := _py_word()
	var base := _base_word()
	var retired_paths := [
		"res://scripts/launch_" + py + "_" + base + ".ps1",
		"res://scripts/tools/export_" + py + "_" + base + ".py",
		"res://scripts/tools/validate_" + py + "_" + base + "_export.py",
	]
	var remaining: Array = []
	for path in retired_paths:
		if FileAccess.file_exists(path):
			remaining.append(path)
	_record_check(result, "retired_external_tools_removed", remaining.is_empty(), remaining)


func _check_no_blocked_tokens(result: Dictionary) -> void:
	var findings: Array = []
	var tokens := _blocked_tokens()
	var files := _collect_files("res://")
	for file_path in files:
		if file_path == SELF_PATH or not _is_text_path(file_path):
			continue
		var text := _read_text(file_path)
		if text.is_empty():
			continue
		for token in tokens:
			if _contains_blocked_value(text, str(token["label"]), str(token["value"])):
				findings.append({
					"path": file_path,
					"token": str(token["label"]),
				})
	_record_check(result, "no_retired_project_references", findings.is_empty(), findings)


func _blocked_tokens() -> Array:
	var py := _py_word()
	var py_upper := "PY" + "THON"
	var base := _base_word()
	var old_project := "tower" + "_defense"
	return [
		{"label": "old_windows_path", "value": "C:\\Users\\donny\\Desktop\\" + old_project},
		{"label": "old_slash_path", "value": "C:/Users/donny/Desktop/" + old_project},
		{"label": "old_root_constant", "value": py_upper + "_" + base.to_upper() + "_ROOT"},
		{"label": "old_data_name", "value": py + "_" + base},
		{"label": "old_module_name", "value": "td" + "_game"},
		{"label": "old_launcher_name", "value": "launch_" + py + "_" + base},
		{"label": "old_exporter_name", "value": "export_" + py + "_" + base},
		{"label": "old_checker_name", "value": "validate_" + py + "_" + base + "_export"},
	]


func _contains_blocked_value(text: String, label: String, value: String) -> bool:
	var offset := 0
	while true:
		var index := text.find(value, offset)
		if index == -1:
			return false
		var after_index := index + value.length()
		if label.ends_with("_path") and text.substr(after_index, "_godot".length()) == "_godot":
			offset = after_index
			continue
		return true
	return false


func _collect_files(dir_path: String) -> Array:
	var files: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return files
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var path := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not SKIP_DIRS.has(entry):
				files.append_array(_collect_files(path))
		else:
			files.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return files


func _is_text_path(path: String) -> bool:
	return TEXT_EXTENSIONS.has(path.get_extension().to_lower())


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _py_word() -> String:
	return "py" + "thon"


func _base_word() -> String:
	return "base" + "line"


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	result["checks"].append({
		"label": label,
		"passed": passed,
		"detail": detail,
	})
	if not passed:
		result["ok"] = false
		result["errors"].append("%s failed: %s" % [label, str(detail)])
