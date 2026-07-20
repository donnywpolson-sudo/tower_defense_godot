class_name GameplayViewModel
extends RefCounted


static func enemy_debug_label(index: int, enemy: Dictionary, default_kind: String, progress_ratio: float) -> String:
	return "#%s %s %.0f%%" % [index, str(enemy.get("kind", default_kind)), clamp(progress_ratio, 0.0, 1.0) * 100.0]


static func debug_overlay(enabled: bool, economy: Dictionary, wave: Dictionary, commands: Array, towers: Array, enemies: Array, projectiles: Array) -> Dictionary:
	if not enabled:
		return {"enabled": false}
	return {
		"enabled": true,
		"economy": economy.duplicate(true),
		"wave": wave.duplicate(true),
		"commands": commands.duplicate(),
		"towers": towers.duplicate(true),
		"enemies": enemies.duplicate(true),
		"projectiles": projectiles.duplicate(true),
	}


static func tower_debug_record(index: int, tower: Dictionary, selected: bool, target_index: int, target: Dictionary, default_type: String) -> Dictionary:
	return {
		"index": index,
		"type": str(tower.get("type", default_type)),
		"position": _vector_to_array(tower.get("position", Vector2.ZERO)),
		"level": int(tower.get("level", 1)),
		"range": float(tower.get("range", 0.0)),
		"damage": float(tower.get("damage", 0.0)),
		"fire_rate": float(tower.get("fire_rate", 0.0)),
		"cooldown": float(tower.get("cooldown", 0.0)),
		"target_mode": str(tower.get("target_mode", "first")),
		"kills": int(tower.get("kills", 0)),
		"selected": selected,
		"target_index": target_index,
		"target_kind": str(target.get("kind", "")) if not target.is_empty() else "",
		"target_progress": float(target.get("progress", 0.0)) if not target.is_empty() else 0.0,
	}


static func enemy_debug_record(index: int, enemy: Dictionary, default_kind: String) -> Dictionary:
	return {
		"index": index,
		"kind": str(enemy.get("kind", default_kind)),
		"lane_index": int(enemy.get("lane_index", 0)),
		"position": _vector_to_array(enemy.get("position", Vector2.ZERO)),
		"hp": float(enemy.get("hp", 0.0)),
		"max_hp": float(enemy.get("max_hp", 0.0)),
		"progress": float(enemy.get("progress", 0.0)),
		"target_index": int(enemy.get("target_index", 0)),
		"shield_hits": int(enemy.get("shield_hits", 0)),
		"reached_end": bool(enemy.get("reached_end", false)),
		"freeze_timer": float(enemy.get("freeze_timer", 0.0)),
		"shatter_timer": float(enemy.get("shatter_timer", 0.0)),
		"shatter_vulnerability_multiplier": float(enemy.get("shatter_vulnerability_multiplier", 1.0)),
	}


static func projectile_debug_record(index: int, projectile: Dictionary, target_index: int, tower_index: int) -> Dictionary:
	return {
		"index": index,
		"position": _vector_to_array(projectile.get("position", Vector2.ZERO)),
		"target_index": target_index,
		"tower_index": tower_index,
		"tower_type": str(projectile.get("tower_type", "")),
		"damage": float(projectile.get("damage", 0.0)),
		"speed": float(projectile.get("speed", 0.0)),
		"dead": bool(projectile.get("dead", false)),
	}


static func _vector_to_array(value: Variant) -> Array:
	var vector: Vector2 = value if value is Vector2 else Vector2.ZERO
	return [vector.x, vector.y]
