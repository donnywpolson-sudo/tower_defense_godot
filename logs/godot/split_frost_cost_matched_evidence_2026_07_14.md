# Cost-Matched Frost Evidence Report

Evidence-only report. Frost values remain unchanged and tuning authorization is fail-closed.

## Gate

- Raw survival gate: `true`
- Cost-neutral gate: `true`
- Tuning authorized: `true`
- Normalized advantage: 6/6 repeats

## Coverage

- Cases: 32/32
- Setup valid: 32/32
- Branch-ready: 16/16
- Cost-matched controls: 8/8 valid
- Cost target: 815 control spend versus 810 branch spend; tolerance: 5 credits; archer branch: `deadeye`
- Paired cost comparisons: 16/16; metadata mismatches: 0; topology mismatches: 0
- Determinism: 16/16 checks, 0 failures
- Runtime invariant failures: 0

## Raw Signals

- Raw qualifying branches: `shatter`
- Cost-neutral qualifying branches: `shatter`

## Rejection


All declared cost-neutral gates passed. This report remains evidence-only; any tuning action requires separate approval.
