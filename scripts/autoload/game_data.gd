extends Node

const DATA_PATH := "res://data/python_baseline_data.json"

var baseline: Dictionary = {}


func _ready() -> void:
	load_baseline()


func load_baseline() -> Dictionary:
	if not baseline.is_empty():
		return baseline
	var file: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Missing baseline data: %s" % DATA_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Baseline data is not a dictionary: %s" % DATA_PATH)
		return {}
	baseline = parsed
	return baseline


func validate_baseline() -> Dictionary:
	var data: Dictionary = load_baseline()
	var result: Dictionary = {
		"ok": true,
		"checks": [],
		"errors": [],
	}
	_record_check(result, "schema_version", data.get("schema_version") == 1, data.get("schema_version"))
	_record_check(result, "config_width", data.get("config", {}).get("width") == GameConfig.LOGICAL_WIDTH, data.get("config", {}).get("width"))
	_record_check(result, "config_height", data.get("config", {}).get("height") == GameConfig.LOGICAL_HEIGHT, data.get("config", {}).get("height"))

	var towers: Dictionary = data.get("towers", {})
	_record_check(result, "shop_order_count", towers.get("shop_order", []).size() == 8, towers.get("shop_order", []).size())
	_record_check(result, "root_tower_count", towers.get("root_tower_ids", []).size() == 9, towers.get("root_tower_ids", []).size())
	_record_check(result, "target_mode_count", towers.get("target_modes", []).size() == 6, towers.get("target_modes", []).size())

	var branch_definitions: Dictionary = towers.get("branch_definitions", {})
	for tower_id in towers.get("root_tower_ids", []):
		var branches: Dictionary = branch_definitions.get(tower_id, {})
		_record_check(result, "branches_%s" % tower_id, branches.size() == 3, branches.size())

	var maps: Array = data.get("maps", {}).get("catalog", [])
	_record_check(result, "map_catalog_count", maps.size() >= 4, maps.size())

	var waves: Dictionary = data.get("waves", {})
	_record_check(result, "wave_schedule_count", waves.get("schedule", []).size() == GameConfig.MAX_WAVE, waves.get("schedule", []).size())
	_record_check(result, "wave_modifier_count", waves.get("modifiers", {}).size() == 5, waves.get("modifiers", {}).size())

	var progression: Dictionary = data.get("progression", {})
	_record_check(result, "reward_card_count", progression.get("card_pool", {}).size() == 9, progression.get("card_pool", {}).size())

	var enemies: Dictionary = data.get("enemies", {})
	_record_check(result, "enemy_kind_count", enemies.get("kind_modifiers", {}).size() == 8, enemies.get("kind_modifiers", {}).size())
	_record_check(result, "boss_override_count", enemies.get("boss_rules", {}).get("wave_overrides", {}).size() == 6, enemies.get("boss_rules", {}).get("wave_overrides", {}).size())
	return result


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	result["checks"].append({
		"label": label,
		"passed": passed,
		"detail": detail,
	})
	if not passed:
		result["ok"] = false
		result["errors"].append("%s failed: %s" % [label, str(detail)])
