# Audit Remediation Backlog

This is a durable planning aid for the Godot audit workflow. It is not a
release-health certificate and it does not replace current audit artifacts.

## Current Workflow State

| Item | Current state | Evidence |
| --- | --- | --- |
| Audit entrypoint | `.\_ai_audit_workflow\RUN_AUDIT.ps1` dispatches Light/Deep audit and queue generation | `_ai_audit_workflow/RUN_AUDIT.ps1` |
| Latest workflow state | Pass with gaps; completed through chunked fallback after two interrupted full attempts | `_ai_audit_workflow/_internal/current/status.json` (`runId=2026_07_11_080218`) |
| Failure cause | The host terminated full Godot attempts with `exit=-1`; both 120-run chunks completed and aggregated | `logs/godot/ai_simulation/2026_07_11_080218/` |
| Apply queue | Empty and correctly blocked by the dirty-baseline gate | `_ai_audit_workflow/_internal/current/improvement_queue.json` |
| Current diagnostic packet | Complete Light aggregate: 240 runs, with 122 scheduled and 122 spawned bosses in the special-wave metrics | `.godot/ai_simulation/ai_simulation_data_2026_07_11_0809_2.json` |
| Diagnostic strength | Full Light evidence, but current-worktree and chunked-fallback caveats remain | `.godot/ai_simulation/ai_simulation_report_2026_07_11_0809_2.md` |

## Correlated Artifact Map

| Purpose | Authoritative path |
| --- | --- |
| Workflow entrypoint | `_ai_audit_workflow/RUN_AUDIT.ps1` |
| Workflow configuration | `_ai_audit_workflow/_internal/config.json` |
| Audit orchestration | `_ai_audit_workflow/_internal/run_cycle.ps1`, `_ai_audit_workflow/_internal/run_deep_audit.ps1` |
| Current state and queue | `_ai_audit_workflow/_internal/current/` |
| Process-attempt diagnostics | `logs/godot/ai_simulation/<run-id>/` |
| Simulation packets | `.godot/ai_simulation/` |
| Canonical gameplay data | `data/game_data.json` |
| Runtime slice | `scripts/game/vertical_slice_game.gd` |
| Focused audit validators | `scripts/tools/run_ai_*_validation.gd` |

## Completed Audit Correctness Fixes

1. Resilience validation now snapshots and restores `_internal/current`, so its
   deliberate failure case cannot leave the live audit queue invalidated.
2. Frost is correctly treated as an enabled slice tower by the simulation
   harness. The current diagnostic packet recorded 92 Frost placements, 64 by
   normal bots, and 34 upgrades. Poison, Support, and Garrison remain the only
   unsupported shop families.
3. Metadata and full scenario-probe validations lock the enabled/unsupported
   tower contract, including Frost's 18 full branch probes.
4. Scheduled boss and commander pressure is now spawned before regular wave
   units. Boss rules apply canonical per-wave modifiers, counters and enemy
   flags persist through save/load, and scenario metrics report spawned counts.

## Prioritized Remediation And Expansion Work

### Completed P1 - Spawn scheduled boss and commander pressure

**Outcome:** The runtime now creates every configured boss and commander before
the regular queue. Bosses use canonical `boss_rules.wave_overrides` (or the
default rule), while commanders retain their canonical enemy modifiers.

**Verified:** `run_wave_schedule_validation.gd`,
`run_ai_scenario_probe_validation.gd`, `run_enemy_kind_validation.gd`, and
`run_persistence_validation.gd` passed on 2026-07-11. The scenario harness now
uses runtime snapshot counters instead of a hard-coded zero count.

**Residual risk:** Late-wave difficulty changed; the latest Light packet has no
boss/commander spawn gap, but balance conclusions still require an uninterrupted
clean-baseline run.

### P2 - Port Poison as the next tower family

**Why:** Poison is canonical but unavailable in the slice. It adds damage over
time and a natural tank/boss counterplay role, increasing meaningful build
choices without duplicating Frost's control role.

**Scope:** Enable Poison in the slice only after it has a distinct damage-over-
time state, projectile application, runtime-invariant coverage, shop/upgrade
panel wiring, and focused tests. Do not enable Support or Garrison in the same
change.

**Acceptance:** Poison can be selected, placed, upgraded, saved/restored, and
its DoT stacks/expiry are covered by targeted projectile and persistence tests.
The audit harness then moves Poison from unsupported to enabled in a separate
follow-up change.

### P3 - Reproduce tank-wave pressure before balance tuning

**Why:** The current 120-run diagnostic recorded 57.2% leaks on tank wave 4,
but it is explicitly non-actionable smoke/custom evidence. The earlier 240-run
diagnostic showed the same direction, not enough proof for cost or damage
changes.

**Scope:** Run a predeclared multi-seed controlled comparison at wave 4 using
fixed valid placements and policies, with and without Frost/anti-tank choices.
Capture tower mix, target mode, spend, damage, leaks, and completion.

**Acceptance:** The report distinguishes an actual canonical-data imbalance
from bot-policy weakness. Only then consider one bounded balance adjustment and
its focused regression test.

### P4 - Investigate resource cleanup only on reproduction

**Why:** A previous playable-surface run reported shutdown ObjectDB/resource
warnings despite passing. Current evidence does not prove a gameplay leak.

**Scope:** Re-run the playable-surface validator and inspect teardown ownership
only if the warning repeats in current output or normal gameplay.

## Deferred Until Explicitly Scoped

- Support and Garrison tower families.
- Reward-card choices, mutation, mastery, and paragon runtime behavior.
- Cost/damage/economy tuning from smoke/custom packets.
- Export, non-Windows platform, localization, and accessibility claims.

## Evidence Gate For The Next Queue

Run one uninterrupted Light audit after this reviewed change set is committed
and on a host that permits a single Godot process to run past the current
environment's 46-72 second interruption. Only that clean, uninterrupted packet
may support balance conclusions; do not auto-apply a finding from the dirty or
chunked-fallback queue.
