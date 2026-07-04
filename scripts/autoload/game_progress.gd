extends Node

const SAVE_SCHEMA_VERSION := 1
const DEFAULT_SAVE_PATH := "user://tower_defense_godot_save.json"
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
	if int(data.get("schema_version", 0)) != SAVE_SCHEMA_VERSION:
		return false
	var progression: Dictionary = data.get("progression", {})
	stars = int(progression.get("stars", 0))
	starting_money_bonus_level = int(progression.get("starting_money_bonus_level", 0))
	tower_damage_bonus_level = int(progression.get("tower_damage_bonus_level", 0))
	starting_research_bonus_level = int(progression.get("starting_research_bonus_level", 0))
	starting_reward_choice_bonus_level = int(progression.get("starting_reward_choice_bonus_level", 0))
	starting_lives_bonus_level = int(progression.get("starting_lives_bonus_level", 0))
	settings = data.get("settings", settings).duplicate(true)
	last_run_state = data.get("run_state", {}).duplicate(true)
	return true


func save_to_path(path: String = DEFAULT_SAVE_PATH, run_state: Dictionary = last_run_state, overwrite: bool = false) -> bool:
	if FileAccess.file_exists(path) and not overwrite:
		last_save_error = ERR_ALREADY_EXISTS
		return false
	if path.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://"))
	var data := JSON.stringify(payload(run_state), "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_save_error = FileAccess.get_open_error()
		return false
	file.store_string(data)
	last_save_error = OK
	return true


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
