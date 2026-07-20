# Audit Remediation Backlog

This is a durable planning aid for the Godot audit workflow. It is not a
release-health certificate and it does not replace current audit artifacts.

## Current Workflow State

| Item | Current state | Evidence |
| --- | --- | --- |
| Audit entrypoint | `.\_ai_audit_workflow\RUN_AUDIT.ps1` dispatches Light, Smoke, Medium, Deep, and Overnight audit tiers plus queue generation; Light is a Medium compatibility alias | `_ai_audit_workflow/RUN_AUDIT.ps1` |
| Latest workflow state | Pass with gaps; current authoritative state is dirty-worktree evidence only | `_ai_audit_workflow/_internal/current/status.json` (`runId=2026_07_18_215856`, `status=pass with gaps`) |
| Failure cause | No workflow failure reported; the current status is `pass with gaps` | `_ai_audit_workflow/_internal/current/status.json` (`failure=`) |
| Apply queue | Complete review-backed queue with 15 items; 0 evidence-backed and 15 review-backed | `_ai_audit_workflow/_internal/current/improvement_queue.json` (`packetComplete=true`, `count=15`, `evidenceBackedCount=0`, `reviewBackedCount=15`) |
| Current diagnostic packet | Complete packet `2026_07_18_2043` is the current queue source; no evidence-backed items were recorded | `_ai_audit_workflow/_internal/current/improvement_queue.json` (`sourcePacketId=2026_07_18_2043`, `packetComplete=true`) |
| Diagnostic strength | Pass with gaps; evidence is from a dirty worktree, and the queue is review-backed rather than evidence-backed | `_ai_audit_workflow/_internal/current/status.json` and `_ai_audit_workflow/_internal/current/improvement_queue.json` |

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
2. Frost and Poison are correctly treated as enabled slice towers by the
   simulation harness. Poison's shared toxin-stack DoT is covered by projectile,
   persistence, shop, and simulation probes. Support and Barracks remain the
   only unsupported shop families.
3. Metadata and full scenario-probe validations lock the enabled/unsupported
   tower contract, including Poison's three canonical branch probes.
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

### P2 - Port Poison as the next tower family (implemented)

**Why:** Poison was canonical but unavailable in the slice. It adds damage over
time and a natural tank/boss counterplay role, increasing meaningful build
choices without duplicating Frost's control role.

**Scope:** Enable Poison in the slice only after it has a distinct damage-over-
time state, projectile application, runtime-invariant coverage, shop/upgrade
panel wiring, and focused tests. Do not enable Support or Barracks in the same
change.

**Acceptance:** Met: Poison can be selected, placed, upgraded, saved/restored,
and its capped stacks, periodic damage, regeneration suppression, and expiry are
covered by targeted projectile, persistence, and simulation tests. The branch
mechanics are also covered: Plague Mist spreads to the two nearest enemies in
its radius, Venom Cask scales poison ticks against bosses, and Wildfire applies
short burn blooms to the primary and nearby targets.

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

- Support and Barracks tower families.
- Reward-card choices, mutation, mastery, and paragon runtime behavior.
- Cost/damage/economy tuning from smoke/custom packets.
- Export, non-Windows platform, localization, and accessibility claims.

## Evidence Gate For The Next Queue

Run one uninterrupted Light audit after this reviewed change set is committed
and on a host that permits a single Godot process to run past the current
environment's 46-72 second interruption. Only that clean, uninterrupted packet
may support balance conclusions; do not auto-apply a finding from the dirty or
chunked-fallback queue.
