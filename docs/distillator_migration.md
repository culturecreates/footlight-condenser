# Distillator Migration Modes

## Environment switches

- `DISTILLATOR_FETCH_MODE=legacy`
- `DISTILLATOR_FETCH_MODE=internal`
- `DISTILLATOR_FETCH_MODE=shadow`
- `REPLAY_FETCH=fixture`
- `DISTILLATOR_CACHE_REFRESH_UI=true`

## Mode behavior

`legacy`

Condenser uses the Distillator seam but keeps the existing Wringer-compatible fetch behavior. This is the safe default. Unset, blank, or invalid `DISTILLATOR_FETCH_MODE` values fall back here.

`internal`

Condenser uses native Distillator fetch only when the request is eligible. Unsupported cases stay explicit:

- `json_post` remains legacy-only
- `render_js` / PhantomJS sources stay on legacy fallback
- blocked URLs and unsupported schemes abort before network fetch

This mode is the production cutover target once parity is proven.

`shadow`

Condenser still returns the legacy result, but Distillator runs the native path in parallel when eligible and records comparison diagnostics. Ineligible native requests log a skipped comparison reason instead of pretending native ran.

`replay`

Set `REPLAY_FETCH=fixture` to serve fetch responses from fixture replay data. This is intended for repeatable tests and migration investigation, not live cache truth.

## Cache refresh UI

`DISTILLATOR_CACHE_REFRESH_UI=true` enables the refresh button on Distillator cache pages. Leave it unset in normal operation to keep the cache UI read-only.

The backend refresh endpoint can still exist while the UI remains hidden by default.

## Rollback

Set `DISTILLATOR_FETCH_MODE=legacy`.

That restores the Wringer-compatible fetch path without any code rollback or schema change.

## Operational notes

- Start validation in `shadow` mode before considering `internal`.
- Treat export invariance as the real cutover gate, not fetch parity alone.
- Watch structured Distillator logs for `cache.hit`, `cache.miss`, `cache.refresh`, `fetch.native`, `fetch.legacy`, `fetch.shadow_compare`, and `fetch.abort`.
