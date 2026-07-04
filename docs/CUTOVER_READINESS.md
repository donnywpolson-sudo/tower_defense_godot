# Cutover Readiness

## Decision

Do not final-cutover yet.

The Godot build can be the primary launch path for continued migration work, but it is not a full replacement for the Python game. Python remains available and should stay intact until full gameplay/UI/release parity is verified.

## Primary And Fallback Launchers

- Godot primary migrated path: `scripts/launch_godot.ps1`
- Python baseline fallback: `scripts/launch_python_baseline.ps1`

## Verified Parity Results

Latest recorded passing checks for the Step 12 checkpoint:

- `PLACEHOLDER_SMOKE_OK`
- `DATA_VALIDATION_OK`
- `VERTICAL_SLICE_SMOKE_OK`
- `TARGETING_VALIDATION_OK`
- `PROJECTILE_VALIDATION_OK`
- `SHOP_VALIDATION_OK`
- `UPGRADE_PANEL_VALIDATION_OK`
- `ASSET_AUDIO_VALIDATION_OK`
- `PERSISTENCE_VALIDATION_OK`

GitHub checkpoint target:

- Repository: `https://github.com/donnywpolson-sudo/tower_defense_godot.git`
- Branch: `main`
- Commit message: `Add Godot migration checkpoint`

Python cleanup status:

- Not approved for Step 12.
- No Python baseline files should be removed, renamed, retired, moved, or edited in this checkpoint.

Known non-fatal local warning:

- Godot headless emits `Failed to read the root certificate store` on this Windows machine.

## Remaining Parity Gaps

- Godot gameplay is still a bounded vertical slice, not the full 30-wave Python runtime.
- Only Classic Road, Archer, and normal enemy packets are playable.
- Full shop tower roster is not playable yet.
- Branch choice, branch upgrades, mutations, mastery, paragon paths, and high-tier research gates remain incomplete.
- Status effects, shields, splitting, splash, boss rules, commander rules, support interactions, barracks units, and full enemy variants remain incomplete.
- Map selector, wave forecast, reward cards, boss warning, end screens, settings menu, and profile/save-slot UI remain incomplete.
- Python renderer-specific behavior is not ported; Godot uses native 2D rendering.
- Many imported visual/audio assets are not yet connected to gameplay events.
- Production `user://` persistence needs a real desktop/editor run check outside this sandbox because sandbox validation used a unique ignored `.godot` temp file.

## Cleanup List For Python-Only Glue And Dead Paths

Do not execute this cleanup until explicit approval is given in a later run.

- Keep `C:\Users\donny\Desktop\tower_defense` intact as the fallback baseline until final cutover is approved.
- After full parity, identify Python-only launcher entry points that no longer serve user-facing play, starting with `tower_defense.py`.
- After full parity, review `td_game/app.py` for monolithic runtime/UI/combat logic that has Godot equivalents.
- After full parity, review Python renderer selection and fallback paths in `td_game/rendering.py`.
- After full parity, review Python asset/audio loaders in `td_game/assets.py` and `td_game/audio.py` for any remaining tooling/provenance roles before removing runtime-only glue.
- Keep Python data/export tooling that still feeds `data/python_baseline_data.json` until Godot owns canonical data or a replacement pipeline exists.
- Keep asset manifests, license files, provenance notes, and any Python scripts needed to regenerate or audit imported assets.
- Remove stale migration-only validation scripts only after equivalent Godot editor/export CI checks exist.

## Release Risks

- Full parity has not been verified, so replacing the Python build now would regress major gameplay systems.
- Current validations are smoke/regression harnesses, not full playthrough coverage.
- No exported Godot desktop build has been produced or tested yet.
- Save/load has no player-facing UI and no real-user profile migration path.
- This checkpoint is safe to publish as migration progress, not as a final release.
