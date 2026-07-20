extends SceneTree

const HARNESS = preload("res://scripts/tools/validation_harness.gd")


func _initialize() -> void:
	var config: Node = _root_node_or_new("GameConfig", load("res://scripts/autoload/game_config.gd"))
	var data_loader: Node = _root_node_or_new("GameData", load("res://scripts/autoload/game_data.gd"))
	var progress: Node = _root_node_or_new("GameProgress", load("res://scripts/autoload/game_progress.gd"))
	var audio: Node = _root_node_or_new("GameAudio", load("res://scripts/autoload/game_audio.gd"))
	var game: Node = load("res://scripts/game/vertical_slice_game.gd").new()
	root.add_child(game)
	game.name = "VerticalSliceGame"
	game.progress_override = progress
	game.reset_slice()
	var result := HARNESS.new_result()
	_check_reward_rules(game, progress, result)
	_check_branch_gate(game, result)
	_check_persistence(game, result)
	_check_attribution(game, result)
	_check_inputs_and_progress(game, audio, result)
	HARNESS.finish(self, result, "REMEDIATION_VALIDATION_OK", "REMEDIATION_VALIDATION_FAILED")


func _check_reward_rules(game: Node, progress: Node, result: Dictionary) -> void:
	progress.reset_progression()
	game.reset_slice()
	game.money = 2000
	HARNESS.record_check(result, "reward_place_existing_tower", _place_any(game, "archer"), game.snapshot())
	var tower: Dictionary = game.towers[0]
	var original_interval := float(tower["fire_rate"])
	game.pending_reward_cards = [{"id": "overclock_patch", "label": "Overclock", "effects": {"fire_rate_multiplier": 1.1}}]
	HARNESS.record_check(result, "overclock_selected", game.choose_reward_card("overclock_patch"), game.reward_card_choice_snapshot())
	HARNESS.record_check(result, "overclock_reduces_cooldown", float(tower["fire_rate"]) < original_interval, tower)
	var overclock_interval := float(tower["fire_rate"])
	game.selected_tower_index = 0
	HARNESS.record_check(result, "reward_preserved_by_upgrade", game.upgrade_selected_tower() and is_equal_approx(float(tower["fire_rate"]), overclock_interval), tower)
	HARNESS.record_check(result, "reward_place_future_tower", _place_any(game, "machine_gun"), game.snapshot())
	var future: Dictionary = game.towers.back()
	var expected_future: float = float(game._basic_slice_tower_fire_rate("machine_gun", 1)) / 1.1
	HARNESS.record_check(result, "future_tower_inherits_overclock", is_equal_approx(float(future["fire_rate"]), expected_future), future)
	for intel_level in [0, 1, 6]:
		progress.starting_reward_choice_bonus_level = intel_level
		game.reset_slice()
		game.wave = 3
		game.pending_reward_cards = []
		game._offer_reward_cards()
		var expected: int = min(9, 3 + int(intel_level))
		HARNESS.record_check(result, "wave_intel_choices_%s" % intel_level, game.pending_reward_cards.size() == expected, game.pending_reward_cards.size())
	progress.reset_progression()


func _check_branch_gate(game: Node, result: Dictionary) -> void:
	game.reset_slice()
	var enabled: Array = []
	for tower_type in game.BASIC_SLICE_TOWER_IDS:
		var test_tower: Dictionary = game.make_test_tower("first", tower_type, 2)
		for option in game._branch_options_for_tower(test_tower):
			enabled.append("%s/%s" % [tower_type, option["id"]])
	var expected := ["cannon/artillery", "cannon/demolition", "frost/glacier", "frost/shatter", "poison/plague_mist", "poison/venom_cask", "poison/wildfire"]
	enabled.sort()
	expected.sort()
	HARNESS.record_check(result, "exactly_seven_runtime_branches", enabled == expected, enabled)
	var rejected_hidden: Array = []
	var branch_definitions: Dictionary = game.game_data.get("towers", {}).get("branch_definitions", {})
	for tower_type in branch_definitions:
		if not game.BASIC_SLICE_TOWER_IDS.has(str(tower_type)):
			continue
		for branch_id in branch_definitions[tower_type]:
			if expected.has("%s/%s" % [tower_type, branch_id]):
				continue
			game.towers = [game.make_test_tower("first", str(tower_type), 2)]
			game.selected_tower_index = 0
			game.money = 1000
			var before_hidden_money: int = game.money
			var rejected: bool = not game.choose_selected_tower_branch(str(branch_id)) and game.money == before_hidden_money and int(game.towers[0].get("level", 0)) == 2 and str(game.towers[0].get("selected_branch", "")).is_empty()
			if rejected:
				rejected_hidden.append("%s/%s" % [tower_type, branch_id])
	HARNESS.record_check(result, "all_fourteen_unfinished_branches_rejected", rejected_hidden.size() == 14, rejected_hidden)
	game.money = 1000
	game.towers = []
	HARNESS.record_check(result, "place_unimplemented_family", _place_any(game, "archer"), game.snapshot())
	game.towers[0]["level"] = 2
	game.selected_tower_index = 0
	var before_money: int = game.money
	HARNESS.record_check(result, "unsupported_branch_rejected", not game.choose_selected_tower_branch("deadeye"), game.latest_feedback)
	HARNESS.record_check(result, "unsupported_upgrade_does_not_charge", not game.upgrade_selected_tower() and game.money == before_money and int(game.towers[0]["level"]) == 2, game.upgrade_panel_snapshot())


func _check_persistence(game: Node, result: Dictionary) -> void:
	game.reset_slice()
	game.money = 1000
	_place_any(game, "poison")
	game.pending_reward_cards = [{"id": "pierce_patch", "label": "Pierce", "effects": {"pierce_bonus": 1}}]
	game.choose_reward_card("pierce_patch")
	game.pending_reward_cards = [{"id": "range_patch", "label": "Range", "effects": {"range_bonus": 12.0}}]
	var saved: Dictionary = game.serialize_run_state()
	HARNESS.record_check(result, "reward_state_serialized", saved.has("pending_reward_cards") and saved.has("reward_card_history") and saved.has("run_modifiers") and saved.has("next_tower_id"), saved.keys())
	var restored: Node = load("res://scripts/game/vertical_slice_game.gd").new()
	root.add_child(restored)
	restored.name = "RestoredVerticalSliceGame"
	restored.reset_slice()
	HARNESS.record_check(result, "reward_state_restored", restored.restore_run_state(saved), restored.snapshot())
	HARNESS.record_check(result, "reward_roundtrip_exact", restored.pending_reward_cards == game.pending_reward_cards and restored.reward_card_history == game.reward_card_history and restored.run_modifiers == game.run_modifiers and restored.reward_card_pierce_bonus == game.reward_card_pierce_bonus, restored.serialize_run_state())
	var before_money: int = restored.money
	var malformed := saved.duplicate(true)
	malformed["money"] = -1
	HARNESS.record_check(result, "malformed_restore_is_atomic", not restored.restore_run_state(malformed) and restored.money == before_money, restored.latest_feedback)
	var malformed_cases: Array = []
	var wrong_type := saved.duplicate(true)
	wrong_type["money"] = "100"
	malformed_cases.append({"label": "wrong_type", "state": wrong_type})
	var non_finite := saved.duplicate(true)
	non_finite["spawn_timer"] = INF
	malformed_cases.append({"label": "non_finite", "state": non_finite})
	var extreme := saved.duplicate(true)
	extreme["towers"][0]["damage"] = 1.0e20
	malformed_cases.append({"label": "extreme_value", "state": extreme})
	var unknown_tower := saved.duplicate(true)
	unknown_tower["towers"][0]["type"] = "unknown"
	malformed_cases.append({"label": "unknown_tower", "state": unknown_tower})
	var unknown_branch := saved.duplicate(true)
	unknown_branch["towers"][0]["selected_branch"] = "unknown"
	malformed_cases.append({"label": "unknown_branch", "state": unknown_branch})
	var unknown_mode := saved.duplicate(true)
	unknown_mode["towers"][0]["target_mode"] = "unknown"
	malformed_cases.append({"label": "unknown_mode", "state": unknown_mode})
	var invalid_selection := saved.duplicate(true)
	invalid_selection["selected_tower_index"] = 99
	malformed_cases.append({"label": "invalid_selection", "state": invalid_selection})
	var invalid_speed := saved.duplicate(true)
	invalid_speed["game_speed"] = 3.0
	malformed_cases.append({"label": "invalid_speed", "state": invalid_speed})
	var negative_modifier := saved.duplicate(true)
	negative_modifier["run_modifiers"]["range_bonus"] = -1.0
	malformed_cases.append({"label": "negative_modifier", "state": negative_modifier})
	var malformed_enemy: Dictionary = game.create_enemy("normal", 1)
	game.enemies = [malformed_enemy]
	var invalid_lane: Dictionary = game.serialize_run_state()
	invalid_lane["enemies"][0]["lane_index"] = 99
	malformed_cases.append({"label": "invalid_lane", "state": invalid_lane})
	var unknown_enemy: Dictionary = invalid_lane.duplicate(true)
	unknown_enemy["enemies"][0]["lane_index"] = 0
	unknown_enemy["enemies"][0]["kind"] = "unknown"
	malformed_cases.append({"label": "unknown_enemy", "state": unknown_enemy})
	for test_case in malformed_cases:
		var atomic_before: Dictionary = restored.serialize_run_state()
		var rejected: bool = not restored.restore_run_state(test_case["state"])
		HARNESS.record_check(result, "malformed_%s_rejected_atomically" % test_case["label"], rejected and restored.serialize_run_state() == atomic_before, restored.latest_feedback)
	var progress: Node = root.get_node("GameProgress")
	progress.reset_progression()
	var before_progress: Dictionary = progress.progression_state()
	var bad_payload: Dictionary = progress.payload()
	bad_payload["progression"]["starting_reward_choice_bonus_level"] = 99
	HARNESS.record_check(result, "malformed_progression_is_atomic", not progress.apply_payload(bad_payload) and progress.progression_state() == before_progress, progress.progression_state())
	var legacy_enemy: Dictionary = game.create_enemy("normal", 1)
	legacy_enemy["poison_stacks"] = 1
	legacy_enemy["poison_timer"] = 1.0
	legacy_enemy["poison_damage"] = 2.0
	game.enemies = [legacy_enemy]
	var legacy: Dictionary = game.serialize_run_state()
	for field in ["pending_reward_cards", "reward_card_history", "reward_card_pierce_bonus", "run_modifiers", "next_tower_id"]:
		legacy.erase(field)
	legacy["towers"][0].erase("tower_id")
	legacy["towers"][0]["damage"] = 777.0
	legacy["enemies"][0].erase("poison_source_tower_id")
	legacy["enemies"][0]["poison_source_tower_index"] = 0
	var legacy_restored: Node = load("res://scripts/game/vertical_slice_game.gd").new()
	root.add_child(legacy_restored)
	legacy_restored.name = "LegacyRestoredVerticalSliceGame"
	legacy_restored.reset_slice()
	var legacy_ok: bool = legacy_restored.restore_run_state(legacy)
	HARNESS.record_check(result, "legacy_save_defaults_and_preserves_stats", legacy_ok and is_equal_approx(float(legacy_restored.towers[0].get("damage", 0.0)), 777.0) and int(legacy_restored.towers[0].get("tower_id", -1)) > 0 and legacy_restored.run_modifiers == {"damage_multiplier": 1.0, "attack_speed_multiplier": 1.0, "range_bonus": 0.0, "pierce_bonus": 0}, legacy_restored.serialize_run_state())
	HARNESS.record_check(result, "legacy_status_index_translates_to_id", legacy_ok and int(legacy_restored.enemies[0].get("poison_source_tower_id", -1)) == int(legacy_restored.towers[0].get("tower_id", -2)), legacy_restored.enemies)
	legacy_restored.queue_free()
	restored.queue_free()


func _check_attribution(game: Node, result: Dictionary) -> void:
	game.reset_slice()
	var near: Dictionary = game.make_test_tower("first", "archer", 2)
	near["tower_id"] = 10
	near["position"] = Vector2.ZERO
	var source: Dictionary = game.make_test_tower("first", "poison", 3)
	source["tower_id"] = 20
	source["position"] = Vector2(500, 500)
	source["selected_branch"] = "venom_cask"
	game.towers = [near, source]
	game.next_tower_id = 21
	var enemy: Dictionary = game.make_test_enemy("credit", Vector2(1, 1), 0.0, 100.0)
	enemy["last_damage_source_tower_id"] = 20
	game._credit_tower_kill(enemy)
	HARNESS.record_check(result, "kill_credited_to_actual_source", int(source["kills"]) == 1 and int(near["kills"]) == 0, game.towers)
	game._apply_poison(enemy, 20.0, source, 3)
	var source_id := int(enemy["poison_source_tower_id"])
	game.towers.remove_at(0)
	game._tick_poison(enemy, 0.6)
	HARNESS.record_check(result, "index_shift_keeps_source_identity", source_id == 20 and float(source.get("total_damage", 0.0)) > 0.0, enemy)
	var damage_before_sell := float(source.get("total_damage", 0.0))
	game.towers = [near]
	game._tick_poison(enemy, 0.6)
	HARNESS.record_check(result, "sold_source_not_reassigned", int(near.get("kills", 0)) == 0 and is_equal_approx(float(source.get("total_damage", 0.0)), damage_before_sell), enemy)


func _check_inputs_and_progress(game: Node, _audio: Node, result: Dictionary) -> void:
	game.reset_slice()
	game.money = 1000
	_place_any(game, "cannon")
	game.selected_tower_index = 0
	_send_action(game, "target_mode")
	HARNESS.record_check(result, "target_input_cycles", str(game.towers[0]["target_mode"]) == "last", game.towers[0])
	_send_action(game, "upgrade_tower")
	HARNESS.record_check(result, "upgrade_input_purchases_level", int(game.towers[0]["level"]) == 2, game.towers[0])
	var progress: Node = root.get_node("GameProgress")
	var audio_before := bool(progress.settings.get("sfx_enabled", true))
	_send_action(game, "toggle_audio")
	HARNESS.record_check(result, "audio_input_toggles", bool(progress.settings.get("sfx_enabled", true)) != audio_before, {"before": audio_before, "after": progress.settings.get("sfx_enabled", true), "feedback": game.latest_feedback})
	_send_action(game, "sell_tower")
	HARNESS.record_check(result, "sell_input_removes_tower", game.towers.is_empty(), game.snapshot())
	game.money = 1
	_send_action(game, "restart_run")
	HARNESS.record_check(result, "restart_input_resets_run", game.money > 1 and game.wave == 1, game.snapshot())
	var progress_enemy: Dictionary = game.create_enemy("normal", 1)
	progress_enemy["position"] = game.path_points.back()
	progress_enemy["target_index"] = game.path_points.size()
	HARNESS.record_check(result, "debug_progress_is_normalized", is_equal_approx(game._enemy_progress_ratio(progress_enemy), 1.0), game._enemy_progress_ratio(progress_enemy))
	var flying_enemy: Dictionary = game.create_enemy("flying", 1)
	HARNESS.record_check(result, "reachable_level_two_anti_air", game._can_attack({"type": "tesla", "level": 2}, flying_enemy) and game._can_attack({"type": "sniper", "level": 2}, flying_enemy), flying_enemy)


func _send_action(game: Node, action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	event.strength = 1.0
	game._unhandled_input(event)


func _place_any(game: Node, tower_type: String) -> bool:
	for y in range(40, 570, 27):
		for x in range(40, 870, 27):
			if game.place_selected_tower(Vector2(x, y), tower_type):
				return true
	return false


func _root_node_or_new(node_name: String, script: Script) -> Node:
	return HARNESS.root_node_or_new(self, node_name, script)
