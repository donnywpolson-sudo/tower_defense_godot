# Shatter Death-Burst Ablation Evidence

Evidence-only report. Canonical Frost values remain unchanged and no data edit is authorized.

## Recommendation

- Status: `candidate_recommended`
- Recommended ratio: `0.18`
- Data edit authorized: `false`

## Arms

- `0.16`: cases 32, setup 32/32, branch-ready 16/16, controls 8/8, determinism failures 0, runtime failures 0
  - Raw survival gate: `true`; normalized gate: `true`; normalized excess: `0.795229`; candidate qualifies: `true`
- `0.18`: cases 32, setup 32/32, branch-ready 16/16, controls 8/8, determinism failures 0, runtime failures 0
  - Raw survival gate: `true`; normalized gate: `true`; normalized excess: `0.828862`; candidate qualifies: `true`
- `0.20`: cases 32, setup 32/32, branch-ready 16/16, controls 8/8, determinism failures 0, runtime failures 0
  - Raw survival gate: `true`; normalized gate: `true`; normalized excess: `0.862495`; candidate qualifies: `false`

- Ratio 0.18 is the smallest candidate reduction that preserves the declared Shatter survival gate and lowers normalized excess.
