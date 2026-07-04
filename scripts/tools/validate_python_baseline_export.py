import importlib
import json
import sys
from pathlib import Path

from export_python_baseline import PYTHON_BASELINE_ROOT, OUTPUT_PATH, ast_assignment, json_safe, wave_row


def check(errors, label, actual, expected):
    if actual != expected:
        errors.append(f"{label}: expected {expected!r}, got {actual!r}")


def main():
    sys.path.insert(0, str(PYTHON_BASELINE_ROOT))
    config = importlib.import_module("td_game.config")
    data = importlib.import_module("td_game.data")
    waves = importlib.import_module("td_game.waves")

    payload = json.loads(OUTPUT_PATH.read_text(encoding="utf-8"))
    errors = []

    check(errors, "config.width", payload["config"]["width"], config.WIDTH)
    check(errors, "config.height", payload["config"]["height"], config.HEIGHT)
    check(errors, "config.max_wave", payload["config"]["max_wave"], config.MAX_WAVE)
    check(errors, "towers.shop_order", payload["towers"]["shop_order"], json_safe(data.SHOP_TOWER_ORDER))
    check(errors, "towers.root_tower_ids", payload["towers"]["root_tower_ids"], json_safe(data.ROOT_TOWER_IDS))
    check(errors, "towers.shop_costs", payload["towers"]["shop_costs"], json_safe(data.SHOP_COSTS))
    check(errors, "towers.branch_definitions", payload["towers"]["branch_definitions"], json_safe(data.BRANCH_DEFINITIONS))
    check(errors, "upgrades.mutation_traits", payload["upgrades"]["mutation_traits"], json_safe(data.MUTATION_TRAITS))
    check(errors, "maps.catalog", payload["maps"]["catalog"], json_safe(data.MAPS))
    check(errors, "waves.modifiers", payload["waves"]["modifiers"], json_safe(waves.WAVE_MODIFIERS))
    check(
        errors,
        "waves.schedule",
        payload["waves"]["schedule"],
        json_safe([wave_row(waves, number) for number in range(1, config.MAX_WAVE + 1)]),
    )
    check(errors, "progression.card_pool", payload["progression"]["card_pool"], json_safe(ast_assignment("CARD_POOL")))

    if errors:
        print("PYTHON_BASELINE_EXPORT_FAILED")
        for error in errors:
            print(f"  {error}")
        raise SystemExit(1)

    print("PYTHON_BASELINE_EXPORT_OK")
    print(f"  compared={OUTPUT_PATH}")
    print(f"  towers={len(payload['towers']['tower_types'])}")
    print(f"  branches={sum(len(branches) for branches in payload['towers']['branch_definitions'].values())}")
    print(f"  maps={len(payload['maps']['catalog'])}")
    print(f"  waves={len(payload['waves']['schedule'])}")


if __name__ == "__main__":
    main()
