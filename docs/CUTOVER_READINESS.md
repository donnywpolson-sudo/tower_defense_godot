# Godot Independence Status

## Decision

Godot is now the canonical project path for runtime code, data loading, validation, docs, and launch workflow. The external pre-migration project is not required by the current Godot project, but it should not be deleted until the final no-reference validation is run with that folder unavailable and the user explicitly approves the destructive action.

## Owned Project Surfaces

- Launch workflow: `scripts/launch_godot.ps1`
- Canonical data: `data/game_data.json`
- Data loader: `scripts/autoload/game_data.gd`
- Gameplay surface: `scripts/game/vertical_slice_game.gd`
- Assets and licenses: `assets/asset_manifest.json`, `assets/licenses/kenney_assets.md`, `assets/licenses/sfx_sources.md`, and `assets/licenses/sfx_replacement_map.json`
- Validation scripts: `scripts/tools/`

## Validation Gates

- `PLACEHOLDER_SMOKE_OK`
- `DATA_VALIDATION_OK`
- `VERTICAL_SLICE_SMOKE_OK`
- `TARGETING_VALIDATION_OK`
- `PROJECTILE_VALIDATION_OK`
- `SHOP_VALIDATION_OK`
- `UPGRADE_PANEL_VALIDATION_OK`
- `ASSET_AUDIO_VALIDATION_OK`
- `PERSISTENCE_VALIDATION_OK`
- `ENEMY_KIND_VALIDATION_OK`
- `WAVE_SCHEDULE_VALIDATION_OK`
- `SPEED_WAVE_STRESS_VALIDATION_OK`
- `INDEPENDENCE_VALIDATION_OK`

Known non-fatal local warning:

- Godot headless may emit `Failed to read the root certificate store` on this Windows machine.

## Remaining Gameplay Parity Gaps

- Several tower families are visible in data/UI scaffolding but are not fully playable with all branch mechanics.
- Branch upgrades, mutations, mastery/paragon behavior, support interactions, barracks units, and high-tier research gates need complete runtime coverage.
- Bosses, commanders, shields, split/death-spawn behavior, status effects, reward modifiers, and protocol-specific wave behaviors need complete runtime coverage.
- Map selector, random map generation, map preview, reward-card UI, research/meta-upgrade UI, wave forecast, boss warning/status, end screen, settings menu, and shortcut coverage remain incomplete.
- Layout overlap checks, deterministic full-playthrough smoke, exported-build testing, and real desktop save-path testing still need to be added.

## Release Risks

- Current validation proves independence and the currently ported systems; it is not yet a full release-certification suite.
- The current game should be treated as a Godot-owned implementation in progress, not a complete shipped replacement.
- External project deletion remains a separate approval step.
