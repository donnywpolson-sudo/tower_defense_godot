class_name RunStateCodec
extends RefCounted

const TOWER_RUNTIME_RULES = preload("res://scripts/game/tower_runtime_rules.gd")
const MAX_SAFE_NUMBER := 1000000000.0
const MAX_COLLECTION_SIZE := 10000


static func encode(state: Dictionary) -> Dictionary:
	var encoded := state.duplicate(true)
	encoded["schema_version"] = 1
	return encoded


static func decode(raw: Variant, context: Dictionary) -> Dictionary:
	if not raw is Dictionary:
		return _failure("run state must be a dictionary")
	var state: Dictionary = raw
	if not _is_integer(state.get("schema_version", null)) or int(state.get("schema_version", 0)) != 1:
		return _failure("unsupported run-state schema")
	for key in ["map_index", "money", "lives", "research_points", "wave", "spawned_this_wave", "spawned_extra_this_wave", "spawned_boss_this_wave", "spawned_commander_this_wave", "spawn_lane_cursor", "leaks", "kills", "wave_reward_money", "wave_reward_research", "reward_card_pierce_bonus", "next_tower_id"]:
		if state.has(key) and (not _is_integer(state[key]) or int(state[key]) < 0 or float(state[key]) > MAX_SAFE_NUMBER):
			return _failure("%s must be a bounded non-negative integer" % key)
	for key in ["spawn_timer", "game_speed"]:
		if state.has(key) and (not _is_finite_number(state[key]) or abs(float(state[key])) > MAX_SAFE_NUMBER):
			return _failure("%s must be finite and bounded" % key)
	for key in ["wave_active", "wave_complete", "game_over"]:
		if state.has(key) and not state[key] is bool:
			return _failure("%s must be boolean" % key)
	for key in ["pending_reward_cards", "reward_card_history", "towers", "enemies", "projectiles"]:
		if state.has(key) and not state[key] is Array:
			return _failure("%s must be an array" % key)
		if state.has(key) and state[key].size() > MAX_COLLECTION_SIZE:
			return _failure("%s exceeds the collection limit" % key)
	if state.has("run_modifiers") and not state["run_modifiers"] is Dictionary:
		return _failure("run_modifiers must be a dictionary")
	if state.has("run_modifiers"):
		var modifier_result := _validate_modifiers(state["run_modifiers"])
		if not bool(modifier_result.get("ok", false)):
			return modifier_result
	var valid_tower_types: Array = context.get("valid_tower_types", [])
	var valid_target_modes: Array = context.get("valid_target_modes", [])
	var valid_branches: Dictionary = context.get("valid_branches", {})
	var valid_enemy_kinds: Array = context.get("valid_enemy_kinds", [])
	var reward_cards: Dictionary = context.get("reward_cards", {})
	var valid_game_speeds: Array = context.get("valid_game_speeds", [0.0, 1.0, 2.0, 4.0])
	var lane_count: int = max(1, int(context.get("lane_count", 1)))
	var max_map_index: int = max(0, int(context.get("max_map_index", 0)))
	if int(state.get("map_index", 0)) > max_map_index:
		return _failure("map_index is out of range")
	if state.has("game_speed") and not valid_game_speeds.has(float(state["game_speed"])):
		return _failure("game_speed is not allowed")
	var build_type := str(state.get("selected_build_type", ""))
	if not build_type.is_empty() and not valid_tower_types.has(build_type):
		return _failure("selected_build_type is unknown")
	for key in ["pending_reward_cards", "reward_card_history"]:
		var reward_result := _validate_reward_records(state.get(key, []), reward_cards)
		if not bool(reward_result.get("ok", false)):
			return _failure("%s: %s" % [key, reward_result.get("error", "invalid")])
	var towers: Array = state.get("towers", [])
	var tower_ids := {}
	for index in range(towers.size()):
		var result := _validate_tower(towers[index], valid_tower_types, valid_target_modes, valid_branches)
		if not bool(result.get("ok", false)):
			return _failure("tower %s: %s" % [index, result.get("error", "invalid")])
		if towers[index].has("tower_id"):
			var tower_id: int = int(towers[index]["tower_id"])
			if tower_ids.has(tower_id):
				return _failure("tower_id values must be unique")
			tower_ids[tower_id] = true
	var enemies: Array = state.get("enemies", [])
	for index in range(enemies.size()):
		var result := _validate_enemy(enemies[index], lane_count, valid_enemy_kinds)
		if not bool(result.get("ok", false)):
			return _failure("enemy %s: %s" % [index, result.get("error", "invalid")])
	var projectiles: Array = state.get("projectiles", [])
	for index in range(projectiles.size()):
		var result := _validate_projectile(projectiles[index], enemies.size(), towers.size())
		if not bool(result.get("ok", false)):
			return _failure("projectile %s: %s" % [index, result.get("error", "invalid")])
	var selected_index: int = int(state.get("selected_tower_index", -1))
	if selected_index < -1 or selected_index >= towers.size():
		return _failure("selected_tower_index is out of range")
	var normalized := state.duplicate(true)
	var modifier_source: Variant = state.get("run_modifiers", {
		"pierce_bonus": int(state.get("reward_card_pierce_bonus", 0)),
	})
	normalized["run_modifiers"] = TOWER_RUNTIME_RULES.normalized_modifiers(modifier_source)
	return {"ok": true, "value": normalized, "error": ""}


static func _validate_tower(raw: Variant, valid_types: Array, valid_modes: Array, valid_branches: Dictionary) -> Dictionary:
	if not raw is Dictionary:
		return _failure("must be a dictionary")
	var record: Dictionary = raw
	var tower_type := str(record.get("type", ""))
	if tower_type.is_empty() or not valid_types.has(tower_type):
		return _failure("unknown tower type")
	if not _valid_vector(record.get("position", null)):
		return _failure("position must contain two finite numbers")
	if not _is_integer(record.get("level", null)) or int(record.get("level", 0)) < 1:
		return _failure("level must be positive")
	for key in ["range", "damage", "fire_rate", "cooldown", "total_damage", "mastery_xp"]:
		if record.has(key) and (not _is_finite_number(record[key]) or float(record[key]) < 0.0 or float(record[key]) > MAX_SAFE_NUMBER):
			return _failure("%s must be finite, bounded, and non-negative" % key)
	var mode := str(record.get("target_mode", "first"))
	if not valid_modes.has(mode):
		return _failure("unknown target mode")
	var branch := str(record.get("selected_branch", ""))
	if not branch.is_empty() and not valid_branches.get(tower_type, []).has(branch):
		return _failure("unknown branch")
	if record.has("tower_id") and (not _is_integer(record["tower_id"]) or int(record["tower_id"]) <= 0):
		return _failure("tower_id must be positive")
	return {"ok": true}


static func _validate_enemy(raw: Variant, lane_count: int, valid_enemy_kinds: Array) -> Dictionary:
	if not raw is Dictionary:
		return _failure("must be a dictionary")
	var record: Dictionary = raw
	if not valid_enemy_kinds.is_empty() and not valid_enemy_kinds.has(str(record.get("kind", ""))):
		return _failure("unknown enemy kind")
	if not _valid_vector(record.get("position", null)):
		return _failure("position must contain two finite numbers")
	if not _is_integer(record.get("lane_index", null)) or int(record["lane_index"]) < 0 or int(record["lane_index"]) >= lane_count:
		return _failure("lane_index is out of range")
	for key in ["hp", "max_hp", "speed", "progress"]:
		if record.has(key) and (not _is_finite_number(record[key]) or float(record[key]) < 0.0 or float(record[key]) > MAX_SAFE_NUMBER):
			return _failure("%s must be finite, bounded, and non-negative" % key)
	for key in ["breach_source_tower_id", "poison_source_tower_id", "wildfire_burn_source_tower_id", "shatter_source_tower_id", "last_damage_source_tower_id"]:
		if record.has(key) and (not _is_integer(record[key]) or int(record[key]) < -1 or float(record[key]) > MAX_SAFE_NUMBER):
			return _failure("%s is invalid" % key)
	return {"ok": true}


static func _validate_projectile(raw: Variant, enemy_count: int, tower_count: int) -> Dictionary:
	if not raw is Dictionary:
		return _failure("must be a dictionary")
	var record: Dictionary = raw
	if not _valid_vector(record.get("position", null)):
		return _failure("position must contain two finite numbers")
	var target_index := int(record.get("target_index", -1))
	if target_index < 0 or target_index >= enemy_count:
		return _failure("target_index is out of range")
	var tower_index := int(record.get("tower_index", -1))
	if not record.has("source_tower_id") and (tower_index < 0 or tower_index >= tower_count):
		return _failure("tower source is out of range")
	if record.has("source_tower_id") and (not _is_integer(record["source_tower_id"]) or int(record["source_tower_id"]) <= 0 or float(record["source_tower_id"]) > MAX_SAFE_NUMBER):
		return _failure("source_tower_id is invalid")
	for key in ["damage", "speed", "trail_timer"]:
		if record.has(key) and (not _is_finite_number(record[key]) or float(record[key]) < 0.0 or float(record[key]) > MAX_SAFE_NUMBER):
			return _failure("%s must be finite, bounded, and non-negative" % key)
	return {"ok": true}


static func _validate_modifiers(modifiers: Dictionary) -> Dictionary:
	for key in ["damage_multiplier", "attack_speed_multiplier"]:
		var value: Variant = modifiers.get(key, 1.0)
		if not _is_finite_number(value) or float(value) <= 0.0 or float(value) > 1000.0:
			return _failure("run modifier %s must be positive and bounded" % key)
	var range_bonus: Variant = modifiers.get("range_bonus", 0.0)
	if not _is_finite_number(range_bonus) or float(range_bonus) < 0.0 or float(range_bonus) > MAX_SAFE_NUMBER:
		return _failure("run modifier range_bonus must be bounded and non-negative")
	var pierce_bonus: Variant = modifiers.get("pierce_bonus", 0)
	if not _is_integer(pierce_bonus) or int(pierce_bonus) < 0 or float(pierce_bonus) > MAX_SAFE_NUMBER:
		return _failure("run modifier pierce_bonus must be a bounded non-negative integer")
	return {"ok": true}


static func _validate_reward_records(records: Array, reward_cards: Dictionary) -> Dictionary:
	for record in records:
		if not record is Dictionary:
			return _failure("reward record must be a dictionary")
		var card_id := str(record.get("id", ""))
		if card_id.is_empty() or not reward_cards.has(card_id):
			return _failure("unknown reward card")
		var canonical: Dictionary = reward_cards[card_id]
		if record.has("effects") and not _effects_match(record.get("effects", {}), canonical.get("effects", {})):
			return _failure("reward effects do not match canonical data")
	return {"ok": true}


static func _effects_match(actual: Variant, canonical: Variant) -> bool:
	if not actual is Dictionary or not canonical is Dictionary:
		return false
	if actual.size() != canonical.size():
		return false
	for key in canonical:
		if not actual.has(key):
			return false
		var actual_value: Variant = actual[key]
		var canonical_value: Variant = canonical[key]
		if _is_finite_number(actual_value) and _is_finite_number(canonical_value):
			if not is_equal_approx(float(actual_value), float(canonical_value)):
				return false
		elif actual_value != canonical_value:
			return false
	return true


static func _is_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and is_equal_approx(float(value), float(int(value)))


static func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _valid_vector(value: Variant) -> bool:
	return value is Array and value.size() >= 2 and _is_finite_number(value[0]) and _is_finite_number(value[1]) and abs(float(value[0])) <= MAX_SAFE_NUMBER and abs(float(value[1])) <= MAX_SAFE_NUMBER


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": {}, "error": message}
