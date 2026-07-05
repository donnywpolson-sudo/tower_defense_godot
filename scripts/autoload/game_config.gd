extends Node

const GODOT_VERSION_PIN := "4.7.stable.official.5b4e0cb0f"
const GODOT_MINOR_PIN := "4.7"
const GODOT_PROJECT_ROOT := "C:/Users/donny/Desktop/tower_defense_godot"
const GAME_TITLE := "Tower Defense"
const LOGICAL_WIDTH := 1180
const LOGICAL_HEIGHT := 600
const MAP_WIDTH := 900
const UI_WIDTH := 280
const STARTING_MONEY := 175
const STARTING_LIVES := 25
const MAX_WAVE := 30


func project_summary() -> Dictionary:
	return {
		"godot_version_pin": GODOT_VERSION_PIN,
		"godot_minor_pin": GODOT_MINOR_PIN,
		"godot_project_root": GODOT_PROJECT_ROOT,
		"logical_size": Vector2i(LOGICAL_WIDTH, LOGICAL_HEIGHT),
		"map_width": MAP_WIDTH,
		"ui_width": UI_WIDTH,
		"starting_money": STARTING_MONEY,
		"starting_lives": STARTING_LIVES,
		"max_wave": MAX_WAVE,
	}
