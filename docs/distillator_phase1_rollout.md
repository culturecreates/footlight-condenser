# Distillator Phase 1 Fetch Rollout

## Current Default

`DISTILLATOR_FETCH_MODE` unset, empty, invalid, or set to `legacy` uses the existing legacy Wringer-compatible fetch path.

Do not enable internal mode by default.

## Staging Shadow Rollout

1. Set `DISTILLATOR_FETCH_MODE=shadow` in staging.
2. Run representative refresh/export traffic.
3. Verify the returned fetch result is still the legacy result.
4. Verify shadow comparison logs are emitted.

Shadow mode runs the internal Distillator fetch path only for comparison. It must not change caller-visible output.

## Logs To Inspect

Watch structured logs for:

- `distillator.fetch_shadow.compare`
- `distillator.fetch_shadow.error`
- `distillator.fetch_mode.internal_ineligible`
- `DistillatorFetchBlocked`

## Expected Mismatch Classes

Shadow comparison mismatches are expected to use these field names:

- `body_hash`
- `headers`
- `final_url`
- `redirect_chain`
- `wringer_error_type`
- `wringer_received_404`
- `wringer_system_error`
- `wringer_unreachable`

Review mismatch counts and examples before cutover. Body content is compared by hash; full bodies should not be logged.

## Known Ineligible Cases

Internal fetch is not used for:

- `render_js=true`
- `json_post=true`
- missing `use_wringer` or `safe_wringer_call`
- unsupported clients

These should continue through the legacy path and may emit `distillator.fetch_mode.internal_ineligible`.

## Rollback

Unset `DISTILLATOR_FETCH_MODE` or set it to `legacy`.

This restores the legacy path without code changes.

## Internal-Mode Cutover Gate

Only consider internal mode after:

- zero unexpected `distillator.fetch_shadow.error` entries over the agreed sample
- reviewed shadow mismatch rate and accepted known differences
- export invariance tests passing
- fetch guard tests passing

## Post-Cutover

1. Set `DISTILLATOR_FETCH_MODE=internal` in staging first.
2. Monitor blocked fetches, especially `DistillatorFetchBlocked`.
3. Monitor fallback and ineligible logs.
4. Promote to production only after staging has a clean observation window.
5. Do not delete the legacy path yet.
