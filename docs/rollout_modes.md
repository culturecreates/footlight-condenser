# Rollout Modes Glossary

This document is the single terminology reference for the Wringer to Condenser rollout.

## Terms

| Internal term | Operator term | Meaning |
| --- | --- | --- |
| Wringer | Wringer | Legacy production fetch and cache system. |
| Distillator | Condenser implementation | Internal migration namespace used in code while Condenser becomes the operator-facing system. |
| Condenser | Condenser | Operator-facing new fetch and cache system. |
| legacy | Legacy Wringer active | Wringer serves production results. |
| shadow | Shadow comparison | Wringer serves production results; Condenser compares in the background. |
| internal | Condenser active | Private compatibility alias for older runtime callers. |
| active | Condenser active | Canonical public rollout and execution name. |
| replay | Replay diagnostic | Replay-only diagnostic execution path. |

## Resolution rules

1. Website rollout state wins when a website or website id is present.
2. Explicit diagnostic mode is allowed for operator and test workflows.
3. Missing website context fails safe to legacy production behavior.
4. `active` is the canonical public mode; `internal` remains a private compatibility alias where older code paths still need it.

## Operator copy

Use these phrases in operator-facing UI:

- `Legacy Wringer active`
- `Shadow comparison`
- `Condenser active`
- `Wringer remains the production fetch path.`
- `Wringer serves production results; Condenser compares in the background.`
- `Condenser serves fetch/cache results; legacy Wringer remains available for inspection.`
- `Open active cache`
- `Open Condenser cache`
- `Inspect legacy Wringer`
- `Compare Condenser vs Wringer`

Avoid mixing operator copy with internal implementation terms such as `internal`, `Distillator active`, or `new cache`.

## Scope note

Legacy Apify scripts are external automation and are not part of the Condenser production transition. They will be reassessed separately.
