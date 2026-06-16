# How To Transition A Site

This is the operator playbook for moving a site through the Condenser production transition.

Production states:

- `legacy`: Wringer remains the production fetch path.
- `shadow`: Wringer remains the production fetch path while Condenser is compared in the background.
- `active`: Condenser becomes the production fetch path while Wringer remains available for inspection and rollback.

Use the web Transition Report as the primary dashboard. The shadow-log summary script is a fallback for offline log analysis, not a required transition step.

## Preflight

Before changing any site mode:

- confirm the app boots and jobs run normally
- confirm the cache index and compare page load read-only
- confirm Wringer inspection links still resolve
- keep the global default safe while site-level rollout proceeds
- run `bin/rails distillator:transition:preflight`

## Shadow

Move a site from `legacy` to `shadow` first.

While a site is in `shadow`:

- Wringer remains the active production backend
- the Transition Report is the daily dashboard
- comparison links and cache links stay available without triggering fetches
- the site should collect enough evidence for promotion

## Inspect

Promote by evidence, not by ceremony. A site is ready for `active` when the operator evidence is clean or explicitly explained:

- the Transition Report detail page loads read-only
- important webpages have active cache links
- the compare page shows no blocking regressions
- export invariance or graph diff is clean or accepted
- queue behavior is stable under refresh
- rollback still points to Wringer inspection

Run the same readiness flow from either the report or the CLI:

- `bin/rails distillator:transition:preflight`
- `bin/rails distillator:transition:check[website_id]`

## Promote

Normal production rollout order is:

1. `legacy`
2. `shadow`
3. `active`

Do not use replay or internal aliases as operator-facing rollout steps.

## Rollback

Rollback is a mode change, not a redeploy.

- change the site from `active` back to `legacy`
- confirm the active backend flips back to Wringer
- keep the Condenser cache link available for inspection
- review the recorded rollout event and readiness snapshot

## Common Blockers

Common reasons a site should stay out of `active`:

- fetch check failed or is stale
- statements evidence is missing or failed
- export diff is missing, stale, or failed
- redirect or cache health requires review
- representative URLs are not yet covered

## Commands

- `bin/rails distillator:transition:preflight`
- `bin/rails distillator:transition:check[website_id]`
- `DISTILLATOR_CACHE_REFRESH_UI=true` only when refresh controls must be exposed intentionally

## Historical Notes

Older phase-oriented notes remain in `docs/` as archived project history. They are not the current operator workflow.

Legacy Apify scripts are external automation and are not part of the Condenser production transition. They will be reassessed separately.
