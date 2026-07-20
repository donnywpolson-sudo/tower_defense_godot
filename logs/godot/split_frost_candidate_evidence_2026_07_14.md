# Candidate Frost Evidence Report

Evidence-only analysis of the matched paired replay artifact. The gate emits authorization state but never changes Frost values.

## Gate

- Source: `res://logs/godot/split_frost_broader_paired_replay_2026_07_14.json`
- Candidate entries: 20/20
- Matched no-Frost controls: `true`
- Repeat-complete conditions: 10/10
- Tuning authorized: `false`

## Deterministic Frost Tuning Gate

- Gate passed: `false`
- Raw survival gate: `true`
- Cost-neutral gate: `false`
- Structural checks: `true`
- Setup valid: 768/768
- Branch-ready: 512/512
- Deterministic repeats: 384 checks, 0 failures
- Runtime invariant failures: 0
- Raw qualifying branches: `shatter`
- Cost-neutral qualifying branches: ``
- Normalized advantage repeats: 0/6
- Raw qualifying maps: `Split Road, Spiral Road`
- Cost-neutral qualifying maps: ``

| Branch | Raw gate | Cost-neutral gate | Raw maps | Cost-neutral maps | Raw rejection reasons | Normalized rejection reasons |
|---|---|---|---|---|---|---|
| glacier | false | false |  |  | A candidate condition has missing or contradictory survival direction across repeats.; Fewer than two maps support the same enemy-family pressure.; Fewer than two distinct build/layout conditions support the same enemy-family pressure. | Spend-normalized damage advantage failed in one or more required repeats or conditions. |
| shatter | true | false | Split Road, Spiral Road |  | Fewer than two maps support the same enemy-family pressure. | Spend-normalized damage advantage failed in one or more required repeats or conditions. |

## Candidate Summary

| Dimension | Counts |
|---|---|
| Branch | glacier=10, shatter=10 |
| Reason | completion_advantage=14, leak_advantage=6, life_advantage=6, survival_advantage=14 |
| Map | Classic Road=12, Spiral Road=4, Split Road=4 |
| Enemy kind | normal=6, swarm=12, tank=2 |
| Condition classification | mixed=6, repeated=4 |

## Matched Signal Groups

| Branch | Map | Wave | Enemy | Layout | Build | Reason | Repeats | Classification |
|---|---|---:|---|---|---|---|---:|---|
| glacier | Classic Road | 4 | tank | default | mixed | leak_advantage, life_advantage | 1, 2 | repeated |
| glacier | Classic Road | 9 | swarm | active | mixed | completion_advantage, survival_advantage | 1, 2 | mixed |
| glacier | Classic Road | 9 | swarm | default | mixed | completion_advantage, survival_advantage | 1, 2 | mixed |
| glacier | Classic Road | 9 | swarm | default | rotated_lane_priority | leak_advantage, life_advantage | 1, 2 | repeated |
| glacier | Split Road | 9 | swarm | default | rotated_lane_priority | leak_advantage, life_advantage | 1, 2 | repeated |
| shatter | Classic Road | 9 | swarm | active | mixed | completion_advantage, survival_advantage | 1, 2 | mixed |
| shatter | Classic Road | 9 | swarm | default | mixed | completion_advantage, survival_advantage | 1, 2 | mixed |
| shatter | Spiral Road | 8 | normal | active | mixed | completion_advantage, survival_advantage | 1, 2 | mixed |
| shatter | Spiral Road | 8 | normal | default | mixed | completion_advantage, survival_advantage | 1, 2 | mixed |
| shatter | Split Road | 8 | normal | default | mixed | completion_advantage, survival_advantage | 1, 2 | repeated |

## Per-Entry Metric Comparisons

Each row is matched to the same map, wave, enemy kind, layout, build variant, seed, and repeat in its no-Frost control.

| Branch | Map | Wave | Enemy | Build | Repeat | Completion | Lives | Leaks | Damage | Spend | Damage/spend | Frost/runtime observations |
|---|---|---:|---|---|---:|---|---|---|---|---|---|---|
| glacier | Classic Road | 4 | tank | mixed | 1 | true / true | 8.0 / 9.0 | 17.0 / 16.0 | 4088.0 / 4100.9 | 810.0 / 455.0 | 5.04691358024691 / 9.01296703296703 | frost_total_damage=1160.0/0.0; slow_observations=142.0/0.0; freeze_observations=28.0/0.0; shatter_observations=0.0/0.0 |
| glacier | Classic Road | 4 | tank | mixed | 2 | true / true | 8.0 / 9.0 | 17.0 / 16.0 | 4088.0 / 4100.9 | 810.0 / 455.0 | 5.04691358024691 / 9.01296703296703 | frost_total_damage=1160.0/0.0; slow_observations=142.0/0.0; freeze_observations=28.0/0.0; shatter_observations=0.0/0.0 |
| glacier | Classic Road | 9 | swarm | mixed | 1 | true / false | 8.0 / 0.0 | 17.0 / 25.0 | 5356.0 / 4823.9 | 810.0 / 455.0 | 6.61234567901235 / 10.601978021978 | frost_total_damage=1360.0/0.0; slow_observations=128.0/0.0; freeze_observations=29.0/0.0; shatter_observations=0.0/0.0 |
| shatter | Classic Road | 9 | swarm | mixed | 1 | true / false | 8.0 / 0.0 | 17.0 / 25.0 | 5242.2556 / 4823.9 | 810.0 / 455.0 | 6.47192049382716 / 10.601978021978 | frost_total_damage=1470.1756/0.0; slow_observations=123.0/0.0; freeze_observations=0.0/0.0; shatter_observations=96.0/0.0 |
| glacier | Classic Road | 9 | swarm | mixed | 2 | true / false | 8.0 / 0.0 | 17.0 / 25.0 | 5356.0 / 4823.9 | 810.0 / 455.0 | 6.61234567901235 / 10.601978021978 | frost_total_damage=1360.0/0.0; slow_observations=128.0/0.0; freeze_observations=29.0/0.0; shatter_observations=0.0/0.0 |
| shatter | Classic Road | 9 | swarm | mixed | 2 | true / false | 8.0 / 0.0 | 17.0 / 25.0 | 5242.2556 / 4823.9 | 810.0 / 455.0 | 6.47192049382716 / 10.601978021978 | frost_total_damage=1470.1756/0.0; slow_observations=123.0/0.0; freeze_observations=0.0/0.0; shatter_observations=96.0/0.0 |
| glacier | Classic Road | 9 | swarm | rotated_lane_priority | 1 | true / true | 24.0 / 25.0 | 1.0 / 0.0 | 6167.0 / 5917.9 | 810.0 / 455.0 | 7.61358024691358 / 13.0063736263736 | frost_total_damage=1240.0/0.0; slow_observations=24.0/0.0; freeze_observations=12.0/0.0; shatter_observations=0.0/0.0 |
| glacier | Classic Road | 9 | swarm | rotated_lane_priority | 2 | true / true | 24.0 / 25.0 | 1.0 / 0.0 | 6167.0 / 5917.9 | 810.0 / 455.0 | 7.61358024691358 / 13.0063736263736 | frost_total_damage=1240.0/0.0; slow_observations=24.0/0.0; freeze_observations=12.0/0.0; shatter_observations=0.0/0.0 |
| glacier | Classic Road | 9 | swarm | mixed | 1 | true / false | 11.0 / 0.0 | 14.0 / 25.0 | 5598.0 / 5284.3 | 810.0 / 455.0 | 6.91111111111111 / 11.6138461538461 | frost_total_damage=1160.0/0.0; slow_observations=7.0/0.0; freeze_observations=7.0/0.0; shatter_observations=0.0/0.0 |
| shatter | Classic Road | 9 | swarm | mixed | 1 | true / false | 11.0 / 0.0 | 14.0 / 25.0 | 5985.1485 / 5284.3 | 810.0 / 455.0 | 7.38907222222222 / 11.6138461538461 | frost_total_damage=1547.1485/0.0; slow_observations=7.0/0.0; freeze_observations=0.0/0.0; shatter_observations=7.0/0.0 |
| glacier | Classic Road | 9 | swarm | mixed | 2 | true / false | 11.0 / 0.0 | 14.0 / 25.0 | 5598.0 / 5284.3 | 810.0 / 455.0 | 6.91111111111111 / 11.6138461538461 | frost_total_damage=1160.0/0.0; slow_observations=7.0/0.0; freeze_observations=7.0/0.0; shatter_observations=0.0/0.0 |
| shatter | Classic Road | 9 | swarm | mixed | 2 | true / false | 11.0 / 0.0 | 14.0 / 25.0 | 5985.1485 / 5284.3 | 810.0 / 455.0 | 7.38907222222222 / 11.6138461538461 | frost_total_damage=1547.1485/0.0; slow_observations=7.0/0.0; freeze_observations=0.0/0.0; shatter_observations=7.0/0.0 |
| shatter | Split Road | 8 | normal | mixed | 1 | true / false | 7.0 / 0.0 | 18.0 / 25.0 | 5043.648 / 4511.616 | 810.0 / 455.0 | 6.22672592592593 / 9.91563956043956 | frost_total_damage=936.0/0.0; slow_observations=34.0/0.0; freeze_observations=0.0/0.0; shatter_observations=33.0/0.0 |
| shatter | Split Road | 8 | normal | mixed | 2 | true / false | 7.0 / 0.0 | 18.0 / 25.0 | 5043.648 / 4511.616 | 810.0 / 455.0 | 6.22672592592593 / 9.91563956043956 | frost_total_damage=936.0/0.0; slow_observations=34.0/0.0; freeze_observations=0.0/0.0; shatter_observations=33.0/0.0 |
| glacier | Split Road | 9 | swarm | rotated_lane_priority | 1 | true / true | 9.0 / 12.0 | 16.0 / 13.0 | 5897.0 / 5903.4 | 810.0 / 455.0 | 7.28024691358025 / 12.9745054945055 | frost_total_damage=1160.0/0.0; slow_observations=52.0/0.0; freeze_observations=21.0/0.0; shatter_observations=0.0/0.0 |
| glacier | Split Road | 9 | swarm | rotated_lane_priority | 2 | true / true | 9.0 / 12.0 | 16.0 / 13.0 | 5897.0 / 5903.4 | 810.0 / 455.0 | 7.28024691358025 / 12.9745054945055 | frost_total_damage=1160.0/0.0; slow_observations=52.0/0.0; freeze_observations=21.0/0.0; shatter_observations=0.0/0.0 |
| shatter | Spiral Road | 8 | normal | mixed | 1 | true / false | 1.0 / 0.0 | 24.0 / 25.0 | 5648.6368 / 4879.488 | 810.0 / 455.0 | 6.97362567901235 / 10.7241494505495 | frost_total_damage=1541.5968/0.0; slow_observations=134.0/0.0; freeze_observations=0.0/0.0; shatter_observations=108.0/0.0 |
| shatter | Spiral Road | 8 | normal | mixed | 2 | true / false | 1.0 / 0.0 | 24.0 / 25.0 | 5648.6368 / 4879.488 | 810.0 / 455.0 | 6.97362567901235 / 10.7241494505495 | frost_total_damage=1541.5968/0.0; slow_observations=134.0/0.0; freeze_observations=0.0/0.0; shatter_observations=108.0/0.0 |
| shatter | Spiral Road | 8 | normal | mixed | 1 | true / false | 1.0 / 0.0 | 24.0 / 25.0 | 5648.6368 / 4879.488 | 810.0 / 455.0 | 6.97362567901235 / 10.7241494505495 | frost_total_damage=1541.5968/0.0; slow_observations=134.0/0.0; freeze_observations=0.0/0.0; shatter_observations=108.0/0.0 |
| shatter | Spiral Road | 8 | normal | mixed | 2 | true / false | 1.0 / 0.0 | 24.0 / 25.0 | 5648.6368 / 4879.488 | 810.0 / 455.0 | 6.97362567901235 / 10.7241494505495 | frost_total_damage=1541.5968/0.0; slow_observations=134.0/0.0; freeze_observations=0.0/0.0; shatter_observations=108.0/0.0 |

## Decision

Spend-normalized damage is a required gate metric: every condition counted toward a raw qualifying branch must pass in both repeats.
Raw survival evidence exists for: shatter, but cost-neutral authorization failed. Frost values must remain unchanged.
