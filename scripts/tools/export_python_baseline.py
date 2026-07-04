import ast
import importlib
import json
import sys
from pathlib import Path


PYTHON_BASELINE_ROOT = Path(r"C:\Users\donny\Desktop\tower_defense")
OUTPUT_PATH = Path(__file__).resolve().parents[2] / "data" / "python_baseline_data.json"
APP_PATH = PYTHON_BASELINE_ROOT / "td_game" / "app.py"


def ast_assignment(name):
    tree = ast.parse(APP_PATH.read_text(encoding="utf-8"))
    values = {}
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        for target in node.targets:
            if isinstance(target, ast.Name):
                try:
                    values[target.id] = ast.literal_eval(node.value)
                except (ValueError, SyntaxError):
                    pass
    return values[name]


def json_safe(value):
    if isinstance(value, dict):
        return {str(key): json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_safe(item) for item in value]
    return value


def wave_row(waves, wave_number):
    modifier_key = waves.get_wave_modifier(wave_number)
    return {
        "wave": wave_number,
        "enemy_kind": waves.get_wave_enemy_kind(wave_number),
        "modifier": modifier_key,
        "modifier_data": json_safe(waves.get_wave_modifier_data(wave_number)),
        "label": waves.get_wave_label(wave_number),
        "boss_count": waves.get_boss_count_for_wave(wave_number),
        "commander_count": waves.get_commander_count_for_wave(wave_number),
        "regular_enemy_count": waves.get_regular_enemy_count(wave_number),
        "spawn_interval": waves.get_spawn_interval(wave_number),
    }


def main():
    sys.path.insert(0, str(PYTHON_BASELINE_ROOT))
    config = importlib.import_module("td_game.config")
    data = importlib.import_module("td_game.data")
    waves = importlib.import_module("td_game.waves")

    card_pool = ast_assignment("CARD_POOL")
    reward_card_categories = ast_assignment("REWARD_CARD_CATEGORIES")
    reward_card_category_order = ast_assignment("REWARD_CARD_CATEGORY_ORDER")
    reward_card_category_labels = ast_assignment("REWARD_CARD_CATEGORY_LABELS")
    reward_card_category_colors = ast_assignment("REWARD_CARD_CATEGORY_COLORS")

    payload = {
        "schema_version": 1,
        "source": {
            "python_baseline_root": str(PYTHON_BASELINE_ROOT),
            "modules": {
                "config": "td_game.config",
                "data": "td_game.data",
                "waves": "td_game.waves",
                "app_static_literals": "td_game.app",
            },
        },
        "config": {
            "map_width": config.MAP_WIDTH,
            "ui_width": config.UI_WIDTH,
            "width": config.WIDTH,
            "height": config.HEIGHT,
            "build_tile_size": config.BUILD_TILE_SIZE,
            "build_grid_step": config.BUILD_GRID_STEP,
            "build_grid_top": config.BUILD_GRID_TOP,
            "path_width": config.PATH_WIDTH,
            "base_tower_range": config.BASE_TOWER_RANGE,
            "max_wave": config.MAX_WAVE,
            "starting_money": config.STARTING_MONEY,
            "starting_lives": config.STARTING_LIVES,
            "base_enemies_per_wave": config.BASE_ENEMIES_PER_WAVE,
            "enemies_per_wave_growth": config.ENEMIES_PER_WAVE_GROWTH,
            "min_spawn_interval": config.MIN_SPAWN_INTERVAL,
            "start_wave_bonus": config.START_WAVE_BONUS,
            "protocol_reward_interval": config.PROTOCOL_REWARD_INTERVAL,
            "base_max_tower_level": config.BASE_MAX_TOWER_LEVEL,
            "max_tower_level": config.MAX_TOWER_LEVEL,
            "paragon_level": config.PARAGON_LEVEL,
            "tower_cost": config.TOWER_COST,
            "sell_refund_rate": config.SELL_REFUND_RATE,
            "paragon_sell_refund_rate": config.PARAGON_SELL_REFUND_RATE,
        },
        "towers": {
            "shop_costs": data.SHOP_COSTS,
            "shop_order": data.SHOP_TOWER_ORDER,
            "root_tower_ids": data.ROOT_TOWER_IDS,
            "branch_unlock_level": data.BRANCH_UNLOCK_LEVEL,
            "legacy_aliases": data.LEGACY_TOWER_ALIASES,
            "tower_types": data.TOWER_TYPES,
            "branch_definitions": data.BRANCH_DEFINITIONS,
            "target_modes": data.TARGET_MODES,
            "required_tower_keys": data.REQUIRED_TOWER_KEYS,
            "required_branch_keys": data.REQUIRED_BRANCH_KEYS,
        },
        "upgrades": {
            "tower_upgrade_costs": data.TOWER_UPGRADE_COSTS,
            "mastery_upgrade_costs": data.MASTERY_UPGRADE_COSTS,
            "research_upgrade_costs": data.RESEARCH_UPGRADE_COSTS,
            "mutation_traits": data.MUTATION_TRAITS,
        },
        "progression": {
            "card_pool": card_pool,
            "reward_card_categories": reward_card_categories,
            "reward_card_category_order": reward_card_category_order,
            "reward_card_category_labels": reward_card_category_labels,
            "reward_card_category_colors": reward_card_category_colors,
            "max_reward_card_choices": len(card_pool),
            "max_intel_bonus_level": max(0, len(card_pool) - 3),
        },
        "maps": {
            "catalog": data.MAPS,
        },
        "waves": {
            "modifiers": waves.WAVE_MODIFIERS,
            "schedule": [wave_row(waves, number) for number in range(1, config.MAX_WAVE + 1)],
        },
        "enemies": {
            "base_formula": {
                "hp": "65 + wave * 18 + max(0, wave - 10) * 8 + max(0, wave - 20) * 18",
                "speed": "62 + wave * 2",
                "reward": "4 + wave // 8",
            },
            "kind_modifiers": {
                "normal": {"hp_multiplier": 1.0, "speed_multiplier": 1.0, "reward_bonus": 0},
                "fast": {"hp_multiplier": 0.65, "speed_multiplier": 1.65, "reward_bonus": 1, "tags": ["fast"]},
                "tank": {"hp_multiplier": 2.2, "speed_multiplier": 0.62, "reward_bonus": 4},
                "swarm": {"hp_multiplier": 0.45, "speed_multiplier": 1.15, "reward_bonus": 0, "tags": ["swarm"]},
                "shield": {"hp_multiplier": 1.2, "speed_multiplier": 0.9, "reward_bonus": 3, "shield_hits": 2, "tags": ["armored"]},
                "flying": {"hp_multiplier": 0.9, "speed_multiplier": 1.35, "reward_bonus": 4, "flying": True, "tags": ["flying"]},
                "armored": {"hp_multiplier": 1.35, "speed_multiplier": 0.85, "reward_bonus": 4, "shield_hits": 3, "tags": ["armored"]},
                "commander": {"hp_multiplier": 2.6, "speed_multiplier": 0.86, "reward_bonus": 18, "shield_hits": 1, "commander": True, "tags": ["commander"]},
            },
            "boss_rules": {
                "base_formula": {
                    "boss_tier": "wave // 5",
                    "hp": "950 + wave * 190 + boss_tier * 420",
                    "speed": "max(35, 58 - boss_tier * 3)",
                    "reward": "75 + boss_tier * 25",
                },
                "protocols": {"10": "ransomware", str(config.MAX_WAVE): "ransomware"},
                "wave_overrides": {
                    "5": {"kind": "ogre boss", "boss": True},
                    "10": {"kind": "ransomware boss", "hp_multiplier": 1.25, "speed_multiplier": 0.9, "reward_bonus": 20, "shield_hits": 6, "boss": True, "boss_protocol": "ransomware"},
                    "15": {"kind": "iron boss", "hp_multiplier": 1.1, "reward_bonus": 25, "shield_hits": 8, "boss": True},
                    "20": {"kind": "summoner boss", "speed_multiplier": 0.95, "reward_bonus": 35, "death_spawns": 12, "boss": True},
                    "25": {"kind": "sky boss", "hp_multiplier": 1.2, "speed_multiplier": 1.15, "reward_bonus": 45, "flying": True, "boss": True},
                    "default": {"kind": "final boss", "hp_multiplier": 1.55, "reward_bonus": 75, "shield_hits": 8, "death_spawns": 18, "boss": True},
                },
            },
        },
    }

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(json_safe(payload), indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
