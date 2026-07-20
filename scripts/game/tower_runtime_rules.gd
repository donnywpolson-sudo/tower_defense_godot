class_name TowerRuntimeRules
extends RefCounted

const DEFAULT_MODIFIERS := {
	"damage_multiplier": 1.0,
	"attack_speed_multiplier": 1.0,
	"range_bonus": 0.0,
	"pierce_bonus": 0,
}


static func default_modifiers() -> Dictionary:
	return DEFAULT_MODIFIERS.duplicate(true)


static func normalized_modifiers(value: Variant) -> Dictionary:
	var result := default_modifiers()
	if not value is Dictionary:
		return result
	result["damage_multiplier"] = max(0.01, float(value.get("damage_multiplier", 1.0)))
	result["attack_speed_multiplier"] = max(0.01, float(value.get("attack_speed_multiplier", 1.0)))
	result["range_bonus"] = float(value.get("range_bonus", 0.0))
	result["pierce_bonus"] = max(0, int(value.get("pierce_bonus", 0)))
	return result


static func apply_reward_effects(current: Dictionary, effects: Dictionary) -> Dictionary:
	var result := normalized_modifiers(current)
	result["damage_multiplier"] *= max(0.01, float(effects.get("damage_multiplier", 1.0)))
	# Game fire_rate is a cooldown interval. A value above one means faster attacks.
	result["attack_speed_multiplier"] *= max(0.01, float(effects.get("fire_rate_multiplier", 1.0)))
	result["range_bonus"] += float(effects.get("range_bonus", 0.0))
	result["pierce_bonus"] += max(0, int(effects.get("pierce_bonus", 0)))
	return result


static func base_range(config: Dictionary, tower_type: String, level: int = 1) -> float:
	var value: float = float(config.get("base_tower_range", 145)) + 18.0
	if tower_type == "sniper":
		value += 90.0
	elif tower_type == "frost":
		value += 22.0
	elif tower_type == "poison":
		value += 4.0
	elif tower_type == "machine_gun":
		value -= 10.0
	elif tower_type == "tesla":
		value += 8.0
	if level <= 1:
		return max(80.0, value - 12.0)
	return value + float(max(0, level - 2)) * 6.0


static func base_damage(tower_type: String, level: int = 1) -> float:
	var value := 39.0
	if tower_type == "sniper":
		value = 58.0
	elif tower_type == "machine_gun":
		value = 22.0
	elif tower_type == "cannon":
		value = 46.0
	elif tower_type == "frost":
		value = 40.0
	elif tower_type == "poison":
		value = 20.0
	elif tower_type == "tesla":
		value = 34.0
	if level <= 1:
		return max(1.0, round(value * 0.93))
	return value * pow(1.12, float(max(0, level - 2)))


static func base_fire_interval(tower_type: String, level: int = 1) -> float:
	var value := 0.50
	if tower_type == "sniper":
		value = 0.85
	elif tower_type == "machine_gun":
		value = 0.28
	elif tower_type == "cannon":
		value = 0.72
	elif tower_type == "frost":
		value = 0.68
	elif tower_type == "poison":
		value = 0.62
	elif tower_type == "tesla":
		value = 0.45
	return max(0.05, value * pow(0.94, float(max(0, level - 2))))


static func resolved_stats(config: Dictionary, tower_type: String, level: int, progression_damage_multiplier: float, modifiers: Dictionary) -> Dictionary:
	var normalized := normalized_modifiers(modifiers)
	return {
		"range": base_range(config, tower_type, level) + float(normalized["range_bonus"]),
		"damage": base_damage(tower_type, level) * max(0.01, progression_damage_multiplier) * float(normalized["damage_multiplier"]),
		"fire_rate": base_fire_interval(tower_type, level) / float(normalized["attack_speed_multiplier"]),
	}


static func enabled_branch_ids(game_data: Dictionary, tower_type: String) -> Array:
	var configured: Variant = game_data.get("towers", {}).get("runtime_enabled_branches", {}).get(tower_type, [])
	return configured.duplicate() if configured is Array else []


static func is_branch_enabled(game_data: Dictionary, tower_type: String, branch_id: String) -> bool:
	return enabled_branch_ids(game_data, tower_type).has(branch_id)
