# Distillator Phase 1 Full-Migration Staging Plan

This plan validates the completed Wringer-in-Condenser migration as one staging
deployment package. It should be run after the
[Distillator Phase 1 Wringer Readiness](distillator_phase1_wringer_readiness.md)
audit is green and before production rollout.

## Deployment Scope

- Wringer-compatible `/websites/wring` is now served by Condenser.
- `/websites.json?term` lookup is served from the Distillator fetch cache.
- The `distillator_fetch_caches` table is migrated.
- `Distillator::FetchService` contract is unchanged.
- Default fetch mode remains legacy unless explicitly changed.

## Pre-Deploy Checks

- Readiness audit is green:
  - `bundle exec rails test test/docs/distillator_phase1_wringer_readiness_test.rb`
- Wringer compatibility tests are green:
  - `bundle exec rails test test/controllers/wringer_compat_controller_test.rb`
- Fetch cache store tests are green:
  - `bundle exec rails test test/services/distillator/fetch_cache_store_test.rb`
- Fetch guard tests are green:
  - `bundle exec rails test test/services/distillator/fetch_guard_test.rb`
- Export invariance tests are green:
  - `bundle exec rails test test/services/distillator/export_invariance_test.rb`
- Zeitwerk check is green:
  - `bundle exec rails zeitwerk:check`
- Migration applies cleanly in staging before traffic is shifted.

## Migration Checks

- Confirm `distillator_fetch_caches` table exists.
- Confirm the unique index on `uri_key` exists.
- Confirm JSONB fields are available for:
  - `headers`
  - `signals`
  - `hints`
  - `redirect_chain`
  - `json_ld`
- Confirm rollback plan for the migration is known before deploy.
- Confirm whether table rollback would destroy staging cache data.

## Staging Smoke Tests

Use a known safe public staging URL for `<known-url>` and its escaped form for
`<escaped-uri>`.

- `GET /websites/wring?uri=<known-url>&format=raw`
  - Expect HTTP success and raw cached/fetched HTML.
- `GET /websites/wring?uri=<known-url>&format=json`
  - Expect JSON with `html`, `signals`, `hints`, `final_url`,
    `redirect_chain`, and `http_code`.
- `GET /websites.json?term=<escaped-uri>`
  - Expect a matching cache record when one exists.
- `GET /websites/wring?uri=<known-url>&format=json&force_scrape=true`
  - Expect refresh attempt and updated `scrape_date`.
- `GET /websites/wring?uri=<known-url>&format=json&force_scrape_every_hrs=1`
  - Expect stale cache refresh and non-stale cache reuse.
- `GET /websites/wring?uri=<known-url>&format=raw&absolute_src=true`
  - Expect relative `src` and `href` values rewritten to absolute URLs.
- `GET /websites/wring?uri=<safe-json-post-target>&format=json&json_post=true`
  - Run only if staging has a safe POST target.
  - Expect JSON content signals and no unsafe external side effects.
- `GET /websites/wring?uri=<known-url>&format=json&use_phantomjs=true`
  - With `PHANTOMJS_API_KEY` absent, expect direct URL fallback behavior.
- `GET /websites/wring?uri=<known-404-url>&format=json&force_scrape=true`
  - Expect 404 metadata and preservation of last successful HTML when present.
- `GET /websites/wring?uri=http://127.0.0.1&format=json`
  - Expect unsafe URL blocked behavior with no network bypass.

## Export Validation

- Run representative website export in staging.
- Compare Artsdata export against prior known-good output when available.
- Review expected differences, if any, before accepting staging.
- Confirm no unexplained changes in:
  - `final_url`
  - `redirect_chain`
  - stored or surfaced 404 behavior

## Operational Observations

Capture these observations during and after staging smoke tests:

- Number of Distillator fetch cache records created.
- Number of blocked fetches.
- Number of 404s.
- Number of failed network scrapes.
- Examples of recorded `signals`.
- Examples of recorded `hints`.

## Acceptance Criteria

- Compatibility endpoints respond correctly.
- Cache refresh semantics are verified.
- Stored 404 lookup is verified.
- Representative export is accepted.
- No unsafe fetch bypass is observed.
- No unexpected error spike is observed.
- Rollback path is understood.

## Rollback

- Route traffic back to old Wringer if it is still available, or revert the
  Condenser deployment.
- Unset any non-default fetch mode.
- Preserve `distillator_fetch_caches` data unless migration rollback is
  required.
- Document whether cache table rollback is destructive before executing it.
