# Distillator Phase 1 Shadow Observation

Use this checklist for the first staging run with Distillator shadow fetch enabled.

## Environment

- Set `DISTILLATOR_FETCH_MODE=shadow`.
- Ensure `REPLAY_FETCH` is unset.
- Confirm production default remains unchanged: unset mode still means legacy.

## Minimum Traffic Sample

Run representative refresh/export traffic through staging.

Include these cases when available:

- simple HTML event page
- JSON-LD event page
- redirect and final URL case
- 404 or stored failure case
- known ineligible cases such as `render_js=true` and `json_post=true`

## Logs To Collect

Collect Rails logs containing:

- `distillator.fetch_shadow.compare`
- `distillator.fetch_shadow.error`
- `distillator.fetch_mode.internal_ineligible`
- `DistillatorFetchBlocked`

## Summary Metrics

Summarize:

- total comparisons
- matched count
- mismatch count
- mismatch fields frequency
- shadow errors count
- internal ineligible count
- blocked fetch count

Use:

```sh
ruby script/distillator_shadow_log_summary.rb log/staging.log
```

## Cutover Gate

Do not move to internal mode until:

- no unexpected shadow errors
- no unexplained mismatch class
- blocked fetches reviewed
- export invariance test green
- guard test green

## Rollback

Unset `DISTILLATOR_FETCH_MODE` or set it to `legacy`.

That returns staging to the legacy fetch path without code changes.
