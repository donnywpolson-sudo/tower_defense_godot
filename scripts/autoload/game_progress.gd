extends Node

const SAVE_SCHEMA_VERSION := 1
const DEFAULT_SAVE_PATH := "user://tower_defense_godot_save.json"
const TEMP_SAVE_SUFFIX := ".tmp"
const SKILL_ORDER := ["money", "damage", "research", "intel", "shield"]
const MAX_INTEL_BONUS_LEVEL := 6

var stars: int = 0
var starting_money_bonus_level: int = 0
var tower_damage_bonus_level: int = 0
var starting_research_bonus_level: int = 0
var starting_reward_choice_bonus_level: int = 0
var starting_lives_bonus_level: int = 0
var settings: Dictionary = {
	"sfx_enabled": true,
	"music_enabled": true,
	"game_speed": 1.0,
}
var last_run_state: Dictionary = {}
var last_save_error: Error = OK


func reset_progression() -> void:
	stars = 0
	starting_money_bonus_level = 0
	tower_damage_bonus_level = 0
	starting_research_bonus_level = 0
	starting_reward_choice_bonus_level = 0
	starting_lives_bonus_level = 0
	settings = {
		"sfx_enabled": true,
		"music_enabled": true,
		"game_speed": 1.0,
	}
	last_run_state = {}


func payload(run_state: Dictionary = last_run_state) -> Dictionary:
	return {
		"schema_version": SAVE_SCHEMA_VERSION,
		"godot_version": _godot_version_pin(),
		"progression": progression_state(),
		"settings": settings.duplicate(true),
		"run_state": run_state.duplicate(true),
	}


func progression_state() -> Dictionary:
	return {
		"stars": stars,
		"starting_money_bonus_level": starting_money_bonus_level,
		"tower_damage_bonus_level": tower_damage_bonus_level,
		"starting_research_bonus_level": starting_research_bonus_level,
		"starting_reward_choice_bonus_level": starting_reward_choice_bonus_level,
		"starting_lives_bonus_level": starting_lives_bonus_level,
	}


func apply_payload(data: Dictionary) -> bool:
	if not _is_integral_number(data.get("schema_version", null)) or int(data.get("schema_version", 0)) != SAVE_SCHEMA_VERSION:
		return false
	var raw_progression: Variant = data.get("progression", {})
	var raw_settings: Variant = data.get("settings", {})
	var raw_run_state: Variant = data.get("run_state", {})
	if not raw_progression is Dictionary or not raw_settings is Dictionary or not raw_run_state is Dictionary:
		return false
	var progression: Dictionary = raw_progression
	var progression_keys := [
		"stars",
		"starting_money_bonus_level",
		"tower_damage_bonus_level",
		"starting_research_bonus_level",
		"starting_reward_choice_bonus_level",
		"starting_lives_bonus_level",
	]
	for key in progression_keys:
		if not _is_integral_number(progression.get(key, 0)) or int(progression.get(key, 0)) < 0:
			return false
	var intel_level := int(progression.get("starting_reward_choice_bonus_level", 0))
	if intel_level > MAX_INTEL_BONUS_LEVEL:
		return false
	var parsed_settings: Dictionary = raw_settings.duplicate(true)
	for key in ["sfx_enabled", "music_enabled"]:
		if not parsed_settings.get(key, true) is bool:
			return false
	var parsed_speed: Variant = parsed_settings.get("game_speed", 1.0)
	if not (parsed_speed is int or parsed_speed is float) or not is_finite(float(parsed_speed)) or not [0.0, 1.0, 2.0, 4.0].has(float(parsed_speed)):
		return false
	# Commit only after the complete payload has passed validation.
	stars = int(progression.get("stars", 0))
	starting_money_bonus_level = int(progression.get("starting_money_bonus_level", 0))
	tower_damage_bonus_level = int(progression.get("tower_damage_bonus_level", 0))
	starting_research_bonus_level = int(progression.get("starting_research_bonus_level", 0))
	starting_reward_choice_bonus_level = intel_level
	starting_lives_bonus_level = int(progression.get("starting_lives_bonus_level", 0))
	settings = parsed_settings
	last_run_state = raw_run_state.duplicate(true)
	return true


func _is_integral_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and is_equal_approx(float(value), float(int(value)))


func save_to_path(path: String = DEFAULT_SAVE_PATH, run_state: Dictionary = last_run_state, overwrite: bool = false) -> bool:
	if FileAccess.file_exists(path) and not overwrite:
		last_save_error = ERR_ALREADY_EXISTS
		return false
	if path.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var data := JSON.stringify(payload(run_state), "\t")
	var temp_path := temporary_save_path(path)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		last_save_error = FileAccess.get_open_error()
		return false
	file.store_string(data)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		last_save_error = write_error
		_cleanup_temporary_save(temp_path)
		return false
	var written_data := FileAccess.get_file_as_string(temp_path)
	var parsed: Variant = JSON.parse_string(written_data)
	if not parsed is Dictionary:
		last_save_error = ERR_FILE_CORRUPT
		_cleanup_temporary_save(temp_path)
		return false
	var target_dir := DirAccess.open(path.get_base_dir())
	if target_dir == null:
		last_save_error = DirAccess.get_open_error()
		_cleanup_temporary_save(temp_path)
		return false
	var rename_error := target_dir.rename(temp_path.get_file(), path.get_file())
	if rename_error != OK:
		last_save_error = rename_error
		_cleanup_temporary_save(temp_path)
		return false
	last_save_error = OK
	return true


func temporary_save_path(path: String) -> String:
	return path + TEMP_SAVE_SUFFIX


func _cleanup_temporary_save(path: String) -> void:
	if FileAccess.file_exists(path):
		var parent := DirAccess.open(path.get_base_dir())
		if parent != null:
			parent.remove(path.get_file())


func load_from_path(path: String = DEFAULT_SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return false
	return apply_payload(parsed)


func skill_upgrade_level(skill_key: String) -> int:
	if skill_key == "money":
		return starting_money_bonus_level
	if skill_key == "damage":
		return tower_damage_bonus_level
	if skill_key == "research":
		return starting_research_bonus_level
	if skill_key == "intel":
		return starting_reward_choice_bonus_level
	if skill_key == "shield":
		return starting_lives_bonus_level
	return 0


func skill_upgrade_cost(skill_key: String) -> Variant:
	if skill_key == "intel" and skill_upgrade_level(skill_key) >= MAX_INTEL_BONUS_LEVEL:
		return null
	return skill_upgrade_level(skill_key) + 1


func skill_upgrade_details(skill_key: String) -> Array:
	var level := skill_upgrade_level(skill_key)
	if skill_key == "money":
		return ["Start Cash", "Lv %s | +$25" % level]
	if skill_key == "damage":
		return ["Tower Damage", "Lv %s | +5%% dmg" % level]
	if skill_key == "research":
		var research_bonus: int = min(2, int(level / 4))
		if research_bonus > 0:
			return ["Research", "Lv %s | +2 Tech +%s wave tech" % [level, research_bonus]]
		return ["Research", "Lv %s | +2 Tech" % level]
	if skill_key == "intel":
		if level >= MAX_INTEL_BONUS_LEVEL:
			return ["Wave Intel", "Lv %s | MAX" % level]
		return ["Wave Intel", "Lv %s | +1 card" % level]
	if skill_key == "shield":
		return ["Core Shield", "Lv %s | +2 HP" % level]
	return [skill_key.capitalize(), "Lv %s" % level]


func buy_skill_upgrade(skill_key: String) -> bool:
	var cost: Variant = skill_upgrade_cost(skill_key)
	if cost == null or stars < int(cost):
		return false
	if skill_key == "money":
		starting_money_bonus_level += 1
	elif skill_key == "damage":
		tower_damage_bonus_level += 1
	elif skill_key == "research":
		starting_research_bonus_level += 1
	elif skill_key == "intel":
		starting_reward_choice_bonus_level += 1
	elif skill_key == "shield":
		starting_lives_bonus_level += 1
	else:
		return false
	stars -= int(cost)
	return true


func new_run_defaults() -> Dictionary:
	return {
		"money": int(GameConfig.STARTING_MONEY) + starting_money_bonus_level * 25,
		"lives": int(GameConfig.STARTING_LIVES) + starting_lives_bonus_level * 2,
		"research_points": starting_research_bonus_level * 2,
		"reward_card_choice_bonus": starting_reward_choice_bonus_level,
		"tower_damage_multiplier": 1.0 + tower_damage_bonus_level * 0.05,
	}


func _godot_version_pin() -> String:
	if is_inside_tree():
		var config_node := get_node_or_null("/root/GameConfig")
		if config_node != null:
			return str(config_node.GODOT_VERSION_PIN)
	return "4.7"
