# Distillator Phase I Status

Phase I is a per-website production rollout, not a feature preview.

Current rollout model:

- `legacy`: Wringer remains the active fetch/cache result.
- `shadow`: Wringer remains the active result and Distillator runs comparison work.
- `active`: Distillator is the active fetch/cache path and Wringer remains available for legacy inspection.

Execution model:

- Website rollout state is stored on `websites.distillator_mode`.
- Distillator fetch execution modes remain `legacy`, `shadow`, `internal`, and `replay`.
- Website rollout `active` maps to Distillator fetch execution mode `internal`.
- `active` is accepted only as an input alias for `internal`; it is not a separate runtime fetch path.
- `FetchService` performs one fetch execution.
- `FetchCacheStore` owns Wringer-compatible cache lookup and refresh semantics.
- Wringer remains the legacy comparator and inspection path.

What this correction pass verifies:

- Statement refresh respects per-website rollout state for `legacy`, `shadow`, and `active`.
- Structured Distillator fetch/cache logs preserve `statement_id`, `source_id`, `webpage_id`, and `website_id`.
- Active cache links and warnings match rollout state on statement, webpage, and website pages.
- Wringer URL-key parity is covered for the Phase I contract cases.
- `json_post` is a first-class Distillator native fetch path:
  - `post_url` routes into native POST fetch for active websites.
  - request method is stored as `POST`.
  - JSON content detection and `json_detected` hints are preserved in cache metadata.
  - non-2xx responses preserve the last successful cached body while updating failure metadata.
- Cache freshness reasons are normalized to:
  - `missing_cache`
  - `force_scrape`
  - `missing_scrape_date`
  - `stale_by_force_scrape_every_hrs`
  - `fresh_cache`
- HTML absolutization remains covered for `src` and `href` rewrite behavior.
- PhantomJS iframe compatibility is covered on the Distillator cache path:
  - iframe URLs force rendered fetches even without explicit `use_phantomjs`.
  - child-frame extraction is cached as HTML rather than the PhantomJS JSON envelope.
  - malformed or missing child-frame output preserves the last successful rendered cache body and records diagnostic hints.
- Website edit and show pages expose the rollout state with production-facing labels.

Focused validation run:

```bash
bin/rails test \
  test/models/website_test.rb \
  test/services/distillator/fetch_mode_test.rb \
  test/services/distillator/fetch_service_test.rb \
  test/services/distillator/fetch_cache_store_test.rb \
  test/services/distillator/native_fetch_test.rb \
  test/services/distillator/phantomjs_fetcher_test.rb \
  test/services/distillator/cache_link_resolver_test.rb \
  test/helpers/statements_helper_refresh_test.rb \
  test/controllers/statements_controller_test.rb \
  test/controllers/websites_controller_test.rb \
  test/controllers/webpages_controller_test.rb \
  test/services/distillator/wringer_url_key_test.rb \
  test/services/distillator/html_absolutizer_test.rb \
  test/services/distillator/cache_refresh_preview_test.rb \
  test/integration/distillator_json_post_fallback_test.rb \
  test/integration/wringer_contract_distillator_test.rb \
  test/integration/distillator_rollout_statement_refresh_test.rb
```

Still pending after this pass:

- durable shadow comparison persistence
- website rollout health summaries and waiting-room diagnostics
- broader dashboard/comparison persistence work
