# Tower Defense Godot

Godot 4 migration workspace for the Python/Pygame tower defense baseline.

## Current Run Paths

Primary migrated path:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\launch_godot.ps1
```

Python baseline fallback:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\launch_python_baseline.ps1
```

## Cutover Status

Godot is prepared as the primary path for the migrated build, but full release cutover is not approved yet. The Python project at `C:\Users\donny\Desktop\tower_defense` remains the source-of-truth baseline until the remaining parity gaps in `docs/GODOT_MIGRATION_NOTES.md` and `docs/CUTOVER_READINESS.md` are closed.

Pinned Godot executable:

```text
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe
```

Pinned Godot version:

```text
4.7.stable.official.5b4e0cb0f
```

## Latest Verified Godot Checks

- `PLACEHOLDER_SMOKE_OK`
- `DATA_VALIDATION_OK`
- `VERTICAL_SLICE_SMOKE_OK`
- `TARGETING_VALIDATION_OK`
- `PROJECTILE_VALIDATION_OK`
- `SHOP_VALIDATION_OK`
- `UPGRADE_PANEL_VALIDATION_OK`
- `ASSET_AUDIO_VALIDATION_OK`
- `PERSISTENCE_VALIDATION_OK`

The current Godot implementation is still a vertical slice: Classic Road, Archer, normal enemies, shop, upgrade panel, assets/audio fallback, and persistence/progression scaffolding.
