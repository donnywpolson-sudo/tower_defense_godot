extends Node

const DATA_PATH := "res://data/game_data.json"

var game_data: Dictionary = {}


func _ready() -> void:
	load_game_data()


func load_game_data() -> Dictionary:
	if not game_data.is_empty():
		return game_data
	var file: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Missing game data: %s" % DATA_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Game data is not a dictionary: %s" % DATA_PATH)
		return {}
	game_data = parsed
	return game_data


func validate_game_data() -> Dictionary:
	var data: Dictionary = load_game_data()
	var result: Dictionary = {
		"ok": true,
		"checks": [],
		"errors": [],
		"warnings": [],
	}
	_record_check(result, "schema_version", data.get("schema_version") == 1, data.get("schema_version"))
	var config: Dictionary = _record_dictionary_field(result, data, "top_level_config", "config")
	_record_check(result, "config_width", config.get("width") == GameConfig.LOGICAL_WIDTH, config.get("width"))
	_record_check(result, "config_height", config.get("height") == GameConfig.LOGICAL_HEIGHT, config.get("height"))

	var towers: Dictionary = _record_dictionary_field(result, data, "top_level_towers", "towers")
	var shop_order: Array = _array_value(towers.get("shop_order", []))
	var root_tower_ids: Array = _array_value(towers.get("root_tower_ids", []))
	var target_modes: Array = _array_value(towers.get("target_modes", []))
	_record_check(result, "shop_order_count", shop_order.size() == 8, shop_order.size())
	_record_check(result, "root_tower_count", root_tower_ids.size() == 9, root_tower_ids.size())
	_record_check(result, "target_mode_count", target_modes.size() == 6, target_modes.size())
	var upgrades: Dictionary = _record_dictionary_field(result, data, "top_level_upgrades", "upgrades")
	var tower_upgrade_costs: Dictionary = _dictionary_value(upgrades.get("tower_upgrade_costs", {}))
	_record_check(result, "first_upgrade_cost", tower_upgrade_costs.get("1") == 60, tower_upgrade_costs.get("1"))

	var branch_definitions: Dictionary = _dictionary_value(towers.get("branch_definitions", {}))
	for tower_id in root_tower_ids:
		var branches: Dictionary = _dictionary_value(branch_definitions.get(tower_id, {}))
		_record_check(result, "branches_%s" % tower_id, branches.size() == 3, branches.size())

	var maps_data: Dictionary = _record_dictionary_field(result, data, "top_level_maps", "maps")
	var maps: Array = _array_value(maps_data.get("catalog", []))
	_record_check(result, "map_catalog_count", maps.size() >= 4, maps.size())

	var waves: Dictionary = _record_dictionary_field(result, data, "top_level_waves", "waves")
	var schedule: Array = _array_value(waves.get("schedule", []))
	var modifiers: Dictionary = _dictionary_value(waves.get("modifiers", {}))
	_record_check(result, "wave_schedule_count", schedule.size() == GameConfig.MAX_WAVE, schedule.size())
	_record_check(result, "wave_modifier_count", modifiers.size() == 5, modifiers.size())
	var wave_one: Dictionary = _dictionary_value(schedule[0]) if not schedule.is_empty() else {}
	_record_check(result, "wave_1_softened_count", int(wave_one.get("regular_enemy_count", 0)) == 11, wave_one)
	_record_check(result, "wave_1_softened_interval", is_equal_approx(float(wave_one.get("spawn_interval", 0.0)), 0.66), wave_one)

	var progression: Dictionary = _record_dictionary_field(result, data, "top_level_progression", "progression")
	_record_check(result, "reward_card_count", progression.get("card_pool", {}).size() == 9, progression.get("card_pool", {}).size())

	var enemies: Dictionary = _record_dictionary_field(result, data, "top_level_enemies", "enemies")
	_record_check(result, "enemy_kind_count", enemies.get("kind_modifiers", {}).size() == 8, enemies.get("kind_modifiers", {}).size())
	_record_check(result, "boss_override_count", enemies.get("boss_rules", {}).get("wave_overrides", {}).size() == 6, enemies.get("boss_rules", {}).get("wave_overrides", {}).size())

	_validate_config_content(result, config)
	_validate_tower_content(result, towers)
	_validate_upgrade_content(result, upgrades)
	_validate_enemy_content(result, enemies)
	_validate_wave_content(result, waves, enemies)
	_validate_map_content(result, maps_data)
	_validate_progression_content(result, progression)
	return result


func validate_balance_sanity() -> Dictionary:
	var data: Dictionary = load_game_data()
	var result: Dictionary = {
		"ok": true,
		"checks": [],
		"errors": [],
		"warnings": [],
	}
	_record_check(result, "balance_data_loaded", not data.is_empty(), data.keys())
	var config: Dictionary = _dictionary_value(data.get("config", {}))
	var towers: Dictionary = _dictionary_value(data.get("towers", {}))
	var upgrades: Dictionary = _dictionary_value(data.get("upgrades", {}))
	var enemies: Dictionary = _dictionary_value(data.get("enemies", {}))
	var waves: Dictionary = _dictionary_value(data.get("waves", {}))
	var maps_data: Dictionary = _dictionary_value(data.get("maps", {}))

	_validate_balance_economy_sanity(result, config, towers)
	_validate_balance_upgrade_sanity(result, config, upgrades)
	_validate_balance_enemy_sanity(result, enemies)
	_validate_balance_wave_sanity(result, config, waves)
	_validate_balance_map_sanity(result, maps_data)
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


func _record_warning(result: Dictionary, label: String, detail: Variant) -> void:
	result["warnings"].append("%s warning: %s" % [label, str(detail)])


func _validate_balance_economy_sanity(result: Dictionary, config: Dictionary, towers: Dictionary) -> void:
	var starting_money := _numeric_value(config.get("starting_money"), 0.0)
	var starting_lives := _numeric_value(config.get("starting_lives"), 0.0)
	var start_wave_bonus := _numeric_value(config.get("start_wave_bonus"), 0.0)
	var root_tower_ids: Array = _array_value(towers.get("root_tower_ids", []))
	var shop_costs: Dictionary = _dictionary_value(towers.get("shop_costs", {}))
	var cheapest_root_cost := 999999.0
	var priciest_root_cost := 0.0
	var affordable_root_count := 0
	for tower_id in root_tower_ids:
		var id := str(tower_id)
		if not _is_number(shop_costs.get(id)):
			continue
		var cost := float(shop_costs.get(id))
		cheapest_root_cost = min(cheapest_root_cost, cost)
		priciest_root_cost = max(priciest_root_cost, cost)
		if cost <= starting_money:
			affordable_root_count += 1

	_record_balance_number(result, "balance_starting_money_reasonable", starting_money, 25.0, 10000.0)
	_record_balance_number(result, "balance_starting_lives_reasonable", starting_lives, 1.0, 250.0)
	_record_balance_number(result, "balance_start_wave_bonus_reasonable", start_wave_bonus, 0.0, max(1.0, starting_money))
	_record_check(result, "balance_opening_has_affordable_root_tower", cheapest_root_cost <= starting_money, {
		"starting_money": starting_money,
		"cheapest_root_cost": cheapest_root_cost,
	})
	_record_check(result, "balance_opening_has_multiple_affordable_roots", affordable_root_count >= min(2, root_tower_ids.size()), {
		"starting_money": starting_money,
		"affordable_root_count": affordable_root_count,
		"root_tower_count": root_tower_ids.size(),
	})
	_record_check(result, "balance_root_shop_cost_spread_reasonable", cheapest_root_cost > 0.0 and priciest_root_cost / cheapest_root_cost <= 10.0, {
		"cheapest_root_cost": cheapest_root_cost,
		"priciest_root_cost": priciest_root_cost,
	})
	_record_check(result, "balance_priciest_root_not_extreme", priciest_root_cost <= max(1.0, starting_money * 10.0), {
		"starting_money": starting_money,
		"priciest_root_cost": priciest_root_cost,
	})


func _validate_balance_upgrade_sanity(result: Dictionary, config: Dictionary, upgrades: Dictionary) -> void:
	var starting_money := _numeric_value(config.get("starting_money"), GameConfig.STARTING_MONEY)
	var tower_upgrade_costs: Dictionary = _dictionary_value(upgrades.get("tower_upgrade_costs", {}))
	var mastery_upgrade_costs: Dictionary = _dictionary_value(upgrades.get("mastery_upgrade_costs", {}))
	var research_upgrade_costs: Dictionary = _dictionary_value(upgrades.get("research_upgrade_costs", {}))
	_validate_balance_cost_ladder(result, "balance_tower_upgrade_costs", tower_upgrade_costs, 1.0, starting_money * 10.0)
	_validate_balance_cost_ladder(result, "balance_mastery_upgrade_costs", mastery_upgrade_costs, 1.0, starting_money * 100.0)
	_validate_balance_cost_ladder(result, "balance_research_upgrade_costs", research_upgrade_costs, 1.0, 1000.0)
	if tower_upgrade_costs.has("1"):
		_record_check(result, "balance_first_tower_upgrade_affordable_after_opening", _numeric_value(tower_upgrade_costs.get("1"), 999999.0) <= starting_money, {
			"starting_money": starting_money,
			"first_upgrade_cost": tower_upgrade_costs.get("1"),
		})
	if not tower_upgrade_costs.is_empty() and not mastery_upgrade_costs.is_empty():
		_record_check(result, "balance_mastery_costs_exceed_basic_upgrades", _min_numeric_value(mastery_upgrade_costs) > _max_numeric_value(tower_upgrade_costs), {
			"tower_upgrade_costs": tower_upgrade_costs,
			"mastery_upgrade_costs": mastery_upgrade_costs,
		})


func _validate_balance_enemy_sanity(result: Dictionary, enemies: Dictionary) -> void:
	var kind_modifiers: Dictionary = _dictionary_value(enemies.get("kind_modifiers", {}))
	_record_check(result, "balance_enemy_normal_modifier_exists", kind_modifiers.has("normal"), kind_modifiers.keys())
	if kind_modifiers.has("normal"):
		var normal: Dictionary = _dictionary_value(kind_modifiers.get("normal", {}))
		_record_check(result, "balance_normal_enemy_is_baseline", is_equal_approx(_numeric_value(normal.get("hp_multiplier"), 0.0), 1.0) and is_equal_approx(_numeric_value(normal.get("speed_multiplier"), 0.0), 1.0), normal)
	for kind in kind_modifiers.keys():
		var id := str(kind)
		var modifier: Dictionary = _dictionary_value(kind_modifiers.get(kind, {}))
		_record_balance_number(result, "balance_enemy_hp_multiplier_%s" % id, modifier.get("hp_multiplier", 1.0), 0.25, 5.0)
		_record_balance_number(result, "balance_enemy_speed_multiplier_%s" % id, modifier.get("speed_multiplier", 1.0), 0.25, 3.0)
		_record_balance_number(result, "balance_enemy_reward_bonus_%s" % id, modifier.get("reward_bonus", 0), 0.0, 100.0)
		if modifier.has("shield_hits"):
			_record_balance_number(result, "balance_enemy_shield_hits_%s" % id, modifier.get("shield_hits"), 0.0, 25.0)
	var boss_overrides: Dictionary = _dictionary_value(_dictionary_value(enemies.get("boss_rules", {})).get("wave_overrides", {}))
	for wave_key in boss_overrides.keys():
		var label := "balance_boss_override_%s" % str(wave_key)
		var override: Dictionary = _dictionary_value(boss_overrides.get(wave_key, {}))
		if override.has("hp_multiplier"):
			_record_balance_number(result, "%s_hp_multiplier" % label, override.get("hp_multiplier"), 0.25, 5.0)
		if override.has("speed_multiplier"):
			_record_balance_number(result, "%s_speed_multiplier" % label, override.get("speed_multiplier"), 0.25, 3.0)
		if override.has("reward_bonus"):
			_record_balance_number(result, "%s_reward_bonus" % label, override.get("reward_bonus"), 0.0, 250.0)
		if override.has("shield_hits"):
			_record_balance_number(result, "%s_shield_hits" % label, override.get("shield_hits"), 0.0, 30.0)
		if override.has("death_spawns"):
			_record_balance_number(result, "%s_death_spawns" % label, override.get("death_spawns"), 0.0, 50.0)


func _validate_balance_wave_sanity(result: Dictionary, config: Dictionary, waves: Dictionary) -> void:
	var schedule: Array = _array_value(waves.get("schedule", []))
	var modifiers: Dictionary = _dictionary_value(waves.get("modifiers", {}))
	var min_spawn_interval := _numeric_value(config.get("min_spawn_interval"), 0.01)
	var previous_total := -1
	var previous_spawn_interval := 999999.0
	for index in range(schedule.size()):
		var wave_row: Dictionary = _dictionary_value(schedule[index])
		var wave_number := int(wave_row.get("wave", index + 1))
		var regular_count := int(wave_row.get("regular_enemy_count", 0))
		var boss_count := int(wave_row.get("boss_count", 0))
		var commander_count := int(wave_row.get("commander_count", 0))
		var total_count := regular_count + boss_count + commander_count
		var spawn_interval := _numeric_value(wave_row.get("spawn_interval"), 0.0)
		var label := "balance_wave_%s" % wave_number
		_record_balance_number(result, "%s_total_enemy_count_reasonable" % label, total_count, 1.0, 250.0)
		_record_balance_number(result, "%s_spawn_interval_within_budget" % label, spawn_interval, min_spawn_interval, 5.0)
		_record_check(result, "%s_boss_count_not_extreme" % label, boss_count <= max(1, int(regular_count / 10) + 1), wave_row)
		if previous_total >= 0:
			_record_check(result, "%s_enemy_count_no_extreme_jump" % label, total_count <= previous_total * 2 + 10, {
				"previous_total": previous_total,
				"total_count": total_count,
			})
			_record_check(result, "%s_spawn_interval_no_large_regression" % label, spawn_interval <= previous_spawn_interval + 0.15, {
				"previous_spawn_interval": previous_spawn_interval,
				"spawn_interval": spawn_interval,
			})
		previous_total = total_count
		previous_spawn_interval = spawn_interval
		if wave_number == GameConfig.MAX_WAVE:
			_record_check(result, "balance_final_wave_has_boss_pressure", boss_count > 0, wave_row)

	for modifier_id in modifiers.keys():
		var modifier_data: Dictionary = _dictionary_value(modifiers.get(modifier_id, {}))
		var effects: Dictionary = _dictionary_value(modifier_data.get("effects", {}))
		for effect_key in effects.keys():
			var label := "balance_wave_modifier_%s_%s" % [str(modifier_id), str(effect_key)]
			if str(effect_key) == "speed_multiplier":
				_record_balance_number(result, label, effects.get(effect_key), 0.25, 3.0)
			elif str(effect_key) == "damage_multiplier":
				_record_balance_number(result, label, effects.get(effect_key), 0.25, 3.0)
			elif str(effect_key) == "regen_scale":
				_record_balance_number(result, label, effects.get(effect_key), 0.0, 0.20)
			elif str(effect_key) == "death_spawns":
				_record_balance_number(result, label, effects.get(effect_key), 0.0, 10.0)
			elif str(effect_key) == "death_burst_damage_fraction":
				_record_balance_number(result, label, effects.get(effect_key), 0.0, 1.0)
			elif str(effect_key) == "death_burst_radius":
				_record_balance_number(result, label, effects.get(effect_key), 0.0, 300.0)
			elif str(effect_key) == "shield_hits":
				_record_balance_number(result, label, effects.get(effect_key), 0.0, 25.0)
			else:
				_record_warning(result, "%s_unclassified_effect" % label, effects.get(effect_key))


func _validate_balance_map_sanity(result: Dictionary, maps: Dictionary) -> void:
	var catalog: Array = _array_value(maps.get("catalog", []))
	for index in range(catalog.size()):
		var map_record: Dictionary = _dictionary_value(catalog[index])
		var label := "balance_map_%s" % (index + 1)
		_record_balance_number(result, "%s_reward_multiplier_reasonable" % label, map_record.get("reward_multiplier"), 0.5, 1.75)
		_record_balance_number(result, "%s_route_length_reasonable" % label, map_record.get("route_length"), 500.0, 5000.0)
		_record_balance_number(result, "%s_buildable_sites_reasonable" % label, map_record.get("buildable_sites"), 10.0, 500.0)


func _validate_config_content(result: Dictionary, config: Dictionary) -> void:
	_record_number_check(result, "config_starting_money_positive", config.get("starting_money"), 1.0, true)
	_record_number_check(result, "config_starting_lives_positive", config.get("starting_lives"), 1.0, true)
	_record_number_check(result, "config_max_wave_positive", config.get("max_wave"), 1.0, true)
	_record_number_check(result, "config_base_tower_range_positive", config.get("base_tower_range"), 1.0, true)
	_record_number_check(result, "config_tower_cost_positive", config.get("tower_cost"), 1.0, true)
	_record_number_check(result, "config_start_wave_bonus_nonnegative", config.get("start_wave_bonus"), 0.0, false)
	_record_number_check(result, "config_min_spawn_interval_positive", config.get("min_spawn_interval"), 0.01, true)
	_record_ratio_check(result, "config_sell_refund_rate_ratio", config.get("sell_refund_rate"))
	_record_ratio_check(result, "config_paragon_sell_refund_rate_ratio", config.get("paragon_sell_refund_rate"))


func _validate_tower_content(result: Dictionary, towers: Dictionary) -> void:
	var tower_types: Dictionary = _record_dictionary_field(result, towers, "towers_tower_types", "tower_types")
	var root_tower_ids: Array = _record_array_field(result, towers, "towers_root_tower_ids", "root_tower_ids")
	var shop_order: Array = _record_array_field(result, towers, "towers_shop_order", "shop_order")
	var shop_costs: Dictionary = _record_dictionary_field(result, towers, "towers_shop_costs", "shop_costs")
	var target_modes: Array = _record_array_field(result, towers, "towers_target_modes", "target_modes")
	var branch_definitions: Dictionary = _record_dictionary_field(result, towers, "towers_branch_definitions", "branch_definitions")

	_record_check(result, "tower_types_present", not tower_types.is_empty(), tower_types.keys())
	_validate_string_id_array(result, "root_tower_ids", root_tower_ids)
	_validate_string_id_array(result, "shop_order", shop_order)
	_validate_string_id_array(result, "target_modes", target_modes)

	for tower_id in root_tower_ids:
		var id := str(tower_id)
		_record_check(result, "root_tower_exists_%s" % id, tower_types.has(id), id)
		_record_check(result, "root_tower_has_shop_cost_%s" % id, shop_costs.has(id), id)
		if shop_costs.has(id):
			_record_number_check(result, "shop_cost_positive_%s" % id, shop_costs.get(id), 1.0, true)

	for tower_id in shop_order:
		var id := str(tower_id)
		_record_check(result, "shop_order_tower_exists_%s" % id, tower_types.has(id), id)
		_record_check(result, "shop_order_cost_exists_%s" % id, shop_costs.has(id), id)
		if shop_costs.has(id):
			_record_number_check(result, "shop_order_cost_positive_%s" % id, shop_costs.get(id), 1.0, true)

	for tower_id in shop_costs.keys():
		var id := str(tower_id)
		_record_check(result, "shop_cost_tower_exists_%s" % id, tower_types.has(id), id)
		_record_number_check(result, "shop_cost_value_positive_%s" % id, shop_costs.get(tower_id), 1.0, true)

	for tower_id in tower_types.keys():
		var id := str(tower_id)
		var tower: Dictionary = _dictionary_value(tower_types.get(tower_id, {}))
		_record_check(result, "tower_definition_dictionary_%s" % id, tower_types.get(tower_id, {}) is Dictionary, tower_types.get(tower_id, {}))
		_record_check(result, "tower_label_present_%s" % id, _nonempty_string(tower.get("label", "")), tower.get("label", ""))
		_record_check(result, "tower_role_present_%s" % id, _nonempty_string(tower.get("role", "")), tower.get("role", ""))
		_record_check(result, "tower_short_present_%s" % id, _nonempty_string(tower.get("short", "")), tower.get("short", ""))
		_record_check(result, "tower_color_valid_%s" % id, _is_color_triplet(tower.get("color", [])), tower.get("color", []))
		_record_check(result, "tower_range_color_valid_%s" % id, _is_color_triplet(tower.get("range_color", [])), tower.get("range_color", []))
		var branch_options: Array = _array_value(tower.get("branch_options", []))
		if root_tower_ids.has(id):
			_record_check(result, "tower_branch_options_array_%s" % id, tower.get("branch_options", []) is Array, tower.get("branch_options", []))
			_record_check(result, "tower_branch_options_present_%s" % id, branch_options.size() >= 1, branch_options)
			var branch_group: Dictionary = _dictionary_value(branch_definitions.get(id, {}))
			_record_check(result, "tower_branch_group_dictionary_%s" % id, branch_definitions.get(id, {}) is Dictionary, branch_definitions.get(id, {}))
			for branch_id in branch_options:
				var branch_key := str(branch_id)
				_record_check(result, "tower_branch_definition_exists_%s_%s" % [id, branch_key], branch_group.has(branch_key), branch_key)
				if branch_group.has(branch_key):
					var branch: Dictionary = _dictionary_value(branch_group.get(branch_key, {}))
					_record_check(result, "tower_branch_dictionary_%s_%s" % [id, branch_key], branch_group.get(branch_key, {}) is Dictionary, branch_group.get(branch_key, {}))
					_record_check(result, "tower_branch_name_present_%s_%s" % [id, branch_key], _nonempty_string(branch.get("name", "")), branch.get("name", ""))
					_record_check(result, "tower_branch_focus_present_%s_%s" % [id, branch_key], _nonempty_string(branch.get("focus", "")), branch.get("focus", ""))
					_record_check(result, "tower_branch_tags_array_%s_%s" % [id, branch_key], branch.get("tags", []) is Array, branch.get("tags", []))


func _validate_upgrade_content(result: Dictionary, upgrades: Dictionary) -> void:
	_validate_cost_ladder(result, "tower_upgrade_costs", _record_dictionary_field(result, upgrades, "upgrades_tower_upgrade_costs", "tower_upgrade_costs"))
	_validate_cost_ladder(result, "mastery_upgrade_costs", _record_dictionary_field(result, upgrades, "upgrades_mastery_upgrade_costs", "mastery_upgrade_costs"))
	_validate_cost_ladder(result, "research_upgrade_costs", _record_dictionary_field(result, upgrades, "upgrades_research_upgrade_costs", "research_upgrade_costs"))
	var mutation_traits: Dictionary = _record_dictionary_field(result, upgrades, "upgrades_mutation_traits", "mutation_traits")
	for trait_id in mutation_traits.keys():
		var id := str(trait_id)
		var trait_data: Dictionary = _dictionary_value(mutation_traits.get(trait_id, {}))
		_record_check(result, "mutation_trait_dictionary_%s" % id, mutation_traits.get(trait_id, {}) is Dictionary, mutation_traits.get(trait_id, {}))
		_record_check(result, "mutation_trait_label_present_%s" % id, _nonempty_string(trait_data.get("label", "")), trait_data.get("label", ""))
		_record_check(result, "mutation_trait_short_present_%s" % id, _nonempty_string(trait_data.get("short", "")), trait_data.get("short", ""))
		_record_check(result, "mutation_trait_color_valid_%s" % id, _is_color_triplet(trait_data.get("color", [])), trait_data.get("color", []))


func _validate_enemy_content(result: Dictionary, enemies: Dictionary) -> void:
	var kind_modifiers: Dictionary = _record_dictionary_field(result, enemies, "enemies_kind_modifiers", "kind_modifiers")
	_record_check(result, "enemy_kind_modifiers_present", not kind_modifiers.is_empty(), kind_modifiers.keys())
	for kind in kind_modifiers.keys():
		var id := str(kind)
		var modifier: Dictionary = _dictionary_value(kind_modifiers.get(kind, {}))
		_record_check(result, "enemy_kind_dictionary_%s" % id, kind_modifiers.get(kind, {}) is Dictionary, kind_modifiers.get(kind, {}))
		_record_number_check(result, "enemy_hp_multiplier_positive_%s" % id, modifier.get("hp_multiplier", 1.0), 0.01, true)
		_record_number_check(result, "enemy_speed_multiplier_positive_%s" % id, modifier.get("speed_multiplier", 1.0), 0.01, true)
		_record_number_check(result, "enemy_reward_bonus_nonnegative_%s" % id, modifier.get("reward_bonus", 0), 0.0, false)
		if modifier.has("shield_hits"):
			_record_number_check(result, "enemy_shield_hits_nonnegative_%s" % id, modifier.get("shield_hits"), 0.0, false)
		if modifier.has("tags"):
			_record_check(result, "enemy_tags_array_%s" % id, modifier.get("tags", []) is Array, modifier.get("tags", []))

	var boss_rules: Dictionary = _record_dictionary_field(result, enemies, "enemies_boss_rules", "boss_rules")
	var boss_overrides: Dictionary = _record_dictionary_field(result, boss_rules, "boss_rules_wave_overrides", "wave_overrides")
	for wave_key in boss_overrides.keys():
		var override: Dictionary = _dictionary_value(boss_overrides.get(wave_key, {}))
		_record_check(result, "boss_override_dictionary_%s" % str(wave_key), boss_overrides.get(wave_key, {}) is Dictionary, boss_overrides.get(wave_key, {}))
		_record_check(result, "boss_override_kind_present_%s" % str(wave_key), _nonempty_string(override.get("kind", "")), override.get("kind", ""))
		if override.has("hp_multiplier"):
			_record_number_check(result, "boss_hp_multiplier_positive_%s" % str(wave_key), override.get("hp_multiplier"), 0.01, true)
		if override.has("speed_multiplier"):
			_record_number_check(result, "boss_speed_multiplier_positive_%s" % str(wave_key), override.get("speed_multiplier"), 0.01, true)
		if override.has("reward_bonus"):
			_record_number_check(result, "boss_reward_bonus_nonnegative_%s" % str(wave_key), override.get("reward_bonus"), 0.0, false)
		if override.has("shield_hits"):
			_record_number_check(result, "boss_shield_hits_nonnegative_%s" % str(wave_key), override.get("shield_hits"), 0.0, false)
		if override.has("death_spawns"):
			_record_number_check(result, "boss_death_spawns_nonnegative_%s" % str(wave_key), override.get("death_spawns"), 0.0, false)


func _validate_wave_content(result: Dictionary, waves: Dictionary, enemies: Dictionary) -> void:
	var schedule: Array = _record_array_field(result, waves, "waves_schedule", "schedule")
	var modifiers: Dictionary = _record_dictionary_field(result, waves, "waves_modifiers", "modifiers")
	var kind_modifiers: Dictionary = _dictionary_value(enemies.get("kind_modifiers", {}))
	_record_check(result, "wave_schedule_present", not schedule.is_empty(), schedule.size())
	for index in range(schedule.size()):
		var wave_row: Dictionary = _dictionary_value(schedule[index])
		_record_check(result, "wave_%s_row_dictionary" % (index + 1), schedule[index] is Dictionary, schedule[index])
		var wave_number := int(wave_row.get("wave", 0))
		var label := "wave_%s" % wave_number
		_record_check(result, "%s_label_present" % label, _nonempty_string(wave_row.get("label", "")), wave_row.get("label", ""))
		_record_check(result, "%s_number_matches_position" % label, wave_number == index + 1, wave_row.get("wave", 0))
		var enemy_kind := str(wave_row.get("enemy_kind", ""))
		_record_check(result, "%s_enemy_kind_present" % label, _nonempty_string(enemy_kind), enemy_kind)
		_record_check(result, "%s_enemy_kind_exists" % label, kind_modifiers.has(enemy_kind), enemy_kind)
		_record_number_check(result, "%s_regular_count_nonnegative" % label, wave_row.get("regular_enemy_count", 0), 0.0, false)
		_record_number_check(result, "%s_boss_count_nonnegative" % label, wave_row.get("boss_count", 0), 0.0, false)
		_record_number_check(result, "%s_commander_count_nonnegative" % label, wave_row.get("commander_count", 0), 0.0, false)
		_record_number_check(result, "%s_spawn_interval_positive" % label, wave_row.get("spawn_interval"), 0.01, true)
		var total_enemies := int(wave_row.get("regular_enemy_count", 0)) + int(wave_row.get("boss_count", 0)) + int(wave_row.get("commander_count", 0))
		_record_check(result, "%s_has_enemy_content" % label, total_enemies > 0, wave_row)
		var modifier: Variant = wave_row.get("modifier", null)
		if modifier != null:
			_record_check(result, "%s_modifier_exists" % label, modifiers.has(str(modifier)), modifier)
			_record_check(result, "%s_modifier_data_dictionary" % label, wave_row.get("modifier_data", {}) is Dictionary, wave_row.get("modifier_data", {}))

	for modifier_id in modifiers.keys():
		var modifier_data: Dictionary = _dictionary_value(modifiers.get(modifier_id, {}))
		_record_check(result, "wave_modifier_dictionary_%s" % str(modifier_id), modifiers.get(modifier_id, {}) is Dictionary, modifiers.get(modifier_id, {}))
		_record_check(result, "wave_modifier_label_present_%s" % str(modifier_id), _nonempty_string(modifier_data.get("label", "")), modifier_data.get("label", ""))
		var effects: Dictionary = _dictionary_value(modifier_data.get("effects", {}))
		_record_check(result, "wave_modifier_effects_present_%s" % str(modifier_id), modifier_data.get("effects", {}) is Dictionary and not effects.is_empty(), modifier_data)
		for effect_key in effects.keys():
			_record_number_check(result, "wave_modifier_effect_number_%s_%s" % [str(modifier_id), str(effect_key)], effects.get(effect_key), 0.0, false)


func _validate_map_content(result: Dictionary, maps: Dictionary) -> void:
	var catalog: Array = _record_array_field(result, maps, "maps_catalog", "catalog")
	for index in range(catalog.size()):
		var map_record: Dictionary = _dictionary_value(catalog[index])
		var label := "map_%s" % (index + 1)
		_record_check(result, "%s_record_dictionary" % label, catalog[index] is Dictionary, catalog[index])
		_record_check(result, "%s_name_present" % label, _nonempty_string(map_record.get("name", "")), map_record.get("name", ""))
		_record_number_check(result, "%s_reward_multiplier_positive" % label, map_record.get("reward_multiplier"), 0.01, true)
		_record_number_check(result, "%s_route_length_positive" % label, map_record.get("route_length"), 1.0, true)
		var paths: Array = _array_value(map_record.get("paths", []))
		_record_check(result, "%s_has_paths" % label, map_record.get("paths", []) is Array and not paths.is_empty(), map_record.get("paths", []))
		for path_index in range(paths.size()):
			_validate_map_path(result, "%s_path_%s" % [label, path_index + 1], paths[path_index])


func _validate_progression_content(result: Dictionary, progression: Dictionary) -> void:
	var card_pool: Dictionary = _record_dictionary_field(result, progression, "progression_card_pool", "card_pool")
	var categories: Dictionary = _record_dictionary_field(result, progression, "progression_reward_card_categories", "reward_card_categories")
	var category_labels: Dictionary = _record_dictionary_field(result, progression, "progression_reward_card_category_labels", "reward_card_category_labels")
	for card_id in card_pool.keys():
		var id := str(card_id)
		var card: Dictionary = _dictionary_value(card_pool.get(card_id, {}))
		_record_check(result, "reward_card_dictionary_%s" % id, card_pool.get(card_id, {}) is Dictionary, card_pool.get(card_id, {}))
		_record_check(result, "reward_card_label_present_%s" % id, _nonempty_string(card.get("label", "")), card.get("label", ""))
		_record_check(result, "reward_card_description_present_%s" % id, _nonempty_string(card.get("description", "")), card.get("description", ""))
		_record_check(result, "reward_card_color_valid_%s" % id, _is_color_triplet(card.get("color", [])), card.get("color", []))
		_record_check(result, "reward_card_category_exists_%s" % id, categories.has(id), id)
		if categories.has(id):
			var category := str(categories.get(id, ""))
			_record_check(result, "reward_card_category_label_exists_%s" % id, category_labels.has(category), category)


func _validate_string_id_array(result: Dictionary, label: String, values: Array) -> void:
	_record_check(result, "%s_present" % label, not values.is_empty(), values)
	var seen := {}
	for value in values:
		var id := str(value)
		_record_check(result, "%s_nonempty_%s" % [label, id], _nonempty_string(id), value)
		_record_check(result, "%s_unique_%s" % [label, id], not seen.has(id), values)
		seen[id] = true


func _validate_cost_ladder(result: Dictionary, label: String, costs: Dictionary) -> void:
	_record_check(result, "%s_present" % label, not costs.is_empty(), costs)
	var levels: Array = []
	for key in costs.keys():
		_record_check(result, "%s_level_key_numeric_%s" % [label, str(key)], str(key).is_valid_int(), key)
		var level := int(str(key))
		levels.append(level)
		_record_check(result, "%s_level_positive_%s" % [label, str(key)], level > 0, key)
		_record_number_check(result, "%s_cost_positive_%s" % [label, str(key)], costs.get(key), 1.0, true)
	levels.sort()
	var previous_cost := -1.0
	for level in levels:
		var cost := float(costs.get(str(level), costs.get(level, 0.0)))
		if previous_cost >= 0.0 and cost < previous_cost:
			_record_warning(result, "%s_cost_decreases_at_%s" % [label, level], costs)
		previous_cost = cost


func _validate_balance_cost_ladder(result: Dictionary, label: String, costs: Dictionary, minimum: float, maximum: float) -> void:
	_record_check(result, "%s_present" % label, not costs.is_empty(), costs)
	var levels: Array = []
	for key in costs.keys():
		if str(key).is_valid_int():
			levels.append(int(str(key)))
	levels.sort()
	var previous_cost := -1.0
	for level in levels:
		var key := str(level)
		var cost := _numeric_value(costs.get(key, costs.get(level)), -1.0)
		_record_balance_number(result, "%s_level_%s_reasonable" % [label, level], cost, minimum, maximum)
		if previous_cost >= 0.0:
			_record_check(result, "%s_level_%s_not_decreasing" % [label, level], cost >= previous_cost, {
				"previous_cost": previous_cost,
				"cost": cost,
				"costs": costs,
			})
		previous_cost = cost


func _record_balance_number(result: Dictionary, label: String, value: Variant, minimum: float, maximum: float) -> void:
	var passed := _is_number(value)
	if passed:
		var number := float(value)
		passed = not is_nan(number) and not is_inf(number) and number >= minimum and number <= maximum
	_record_check(result, label, passed, {
		"value": value,
		"minimum": minimum,
		"maximum": maximum,
	})


func _numeric_value(value: Variant, fallback: float = 0.0) -> float:
	if _is_number(value):
		var number := float(value)
		if not is_nan(number) and not is_inf(number):
			return number
	return fallback


func _min_numeric_value(values: Dictionary) -> float:
	var result := 999999999.0
	for key in values.keys():
		if _is_number(values.get(key)):
			result = min(result, float(values.get(key)))
	return result


func _max_numeric_value(values: Dictionary) -> float:
	var result := -999999999.0
	for key in values.keys():
		if _is_number(values.get(key)):
			result = max(result, float(values.get(key)))
	return result


func _record_number_check(result: Dictionary, label: String, value: Variant, minimum: float, strict: bool) -> void:
	var passed := _is_number(value)
	var number := 0.0
	if passed:
		number = float(value)
		passed = not is_nan(number) and not is_inf(number)
		if strict:
			passed = passed and number >= minimum
		else:
			passed = passed and number >= minimum
	_record_check(result, label, passed, value)


func _record_dictionary_field(result: Dictionary, parent: Dictionary, label: String, key: String) -> Dictionary:
	var value: Variant = parent.get(key, null)
	_record_check(result, "%s_dictionary" % label, value is Dictionary, value)
	return _dictionary_value(value)


func _record_array_field(result: Dictionary, parent: Dictionary, label: String, key: String) -> Array:
	var value: Variant = parent.get(key, null)
	_record_check(result, "%s_array" % label, value is Array, value)
	return _array_value(value)


func _dictionary_value(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _array_value(value: Variant) -> Array:
	return value if value is Array else []


func _validate_map_path(result: Dictionary, label: String, path: Variant) -> void:
	_record_check(result, "%s_array" % label, path is Array, path)
	var points: Array = _array_value(path)
	_record_check(result, "%s_has_two_points" % label, points.size() >= 2, points)
	for point_index in range(points.size()):
		var point: Variant = points[point_index]
		var point_label := "%s_point_%s" % [label, point_index + 1]
		_record_check(result, "%s_pair" % point_label, point is Array and _array_value(point).size() == 2, point)
		var coords: Array = _array_value(point)
		if coords.size() == 2:
			_record_number_check(result, "%s_x_number" % point_label, coords[0], 0.0, false)
			_record_number_check(result, "%s_y_number" % point_label, coords[1], 0.0, false)


func _record_ratio_check(result: Dictionary, label: String, value: Variant) -> void:
	var passed := _is_number(value)
	if passed:
		var number := float(value)
		passed = not is_nan(number) and not is_inf(number) and number >= 0.0 and number <= 1.0
	_record_check(result, label, passed, value)


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _nonempty_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not str(value).strip_edges().is_empty()


func _is_color_triplet(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var values: Array = value
	if values.size() != 3:
		return false
	for channel in values:
		if not _is_number(channel):
			return false
		var number := float(channel)
		if is_nan(number) or is_inf(number) or number < 0.0 or number > 255.0:
			return false
	return true
