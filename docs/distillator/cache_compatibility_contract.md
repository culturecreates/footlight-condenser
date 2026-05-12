# Distillator Cache Compatibility Contract

This document defines the legacy Wringer cache semantics that Distillator must preserve during migration work.

Compatibility references:
- [Wringer Compatibility Matrix](/home/educa/rails-upgrade/githubed/footlight-condenser/docs/distillator/wringer_compatibility_matrix.md)
- [Phase 1 Wringer Readiness](/home/educa/rails-upgrade/githubed/footlight-condenser/docs/distillator_phase1_wringer_readiness.md)
- Legacy controller contract: [wringer/app/controllers/websites_controller.rb](/home/educa/rails-upgrade/githubed/footlight-condenser/wringer/app/controllers/websites_controller.rb)
- Current cache store: [app/services/distillator/fetch_cache_store.rb](/home/educa/rails-upgrade/githubed/footlight-condenser/app/services/distillator/fetch_cache_store.rb)
- Current compatibility controller: [app/controllers/websites_controller.rb](/home/educa/rails-upgrade/githubed/footlight-condenser/app/controllers/websites_controller.rb)

## Compatibility Rules

- `scrape_date` = last attempted scrape.
- `successful_refresh` = last successful 2xx content refresh.
- Non-2xx responses must preserve existing `html`.
- Raw, JSON, and HTML formats are compatibility outputs, not new APIs.
- Distillator-specific refactors must not invent new cache semantics that differ from Wringer unless a later migration document explicitly approves that change.
- Cache inspection sorting defaults to `updated_at desc` and remains read-only.
- JSON inspection endpoints continue to return array payloads plus pagination headers.
- Health/status UI is diagnostic only; it must not mutate cache state.
- Internal/native statement refresh without `force_scrape` or `force_scrape_every_hrs` remains transient and must not write Distillator fetch cache rows.
- Crawl URI refresh with `force_scrape_every_hrs` routes eligible native HTTP GET fetches through `Distillator::FetchCacheStore`.

## Contract Matrix

| Field or parameter | Legacy Wringer behavior | Current Distillator implementation | Current tests | Missing tests | UI visibility |
|---|---|---|---|---|---|
| `uri` / `uri_key` | Wringer stores and looks up cache rows by escaped URI key. Missing or invalid `uri` returns no content rather than raising. | `Distillator::WringerUrlKey` builds the normalized URL and escaped `uri_key`; `Distillator::FetchCacheStore` persists by `uri_key`; `WebsitesController#wring` returns `no_content` for invalid input. | `test/services/distillator/wringer_url_key_test.rb`, `test/controllers/wringer_compat_controller_test.rb`, `test/services/distillator/fetch_cache_store_test.rb`, `test/services/distillator/cache_refresh_preview_test.rb` | No missing test identified for current cache-key compatibility behavior. | User-visible in `/websites/wring`, `/websites.json?term=...`, and the read-only JSON/raw/wring_json/preview cache endpoints. |
| `html` | Cached HTML is the compatibility source of truth used by Wringer raw output and JSON output. On successful 2xx refresh, it is replaced. On non-2xx refresh, last known good HTML is preserved. | `Distillator::FetchCacheStore#write_result` writes `html` only in the 2xx branch and preserves prior HTML on non-2xx results. | `test/services/distillator/fetch_cache_store_test.rb`, `test/controllers/wringer_compat_controller_test.rb`, `test/controllers/distillator/cache_controller_test.rb` | No missing test identified for 2xx/404/500 preservation semantics in the current compatibility path. | Directly visible in `format=raw`, `format=json`, and the read-only raw/wring_json cache endpoints. |
| `json_ld` | Stored cache metadata field used by Condenser lookup surfaces; not part of the `/websites/wring` compatibility payload. | Persisted on `Distillator::FetchCache`; surfaced by `/websites.json?term=...`. | `test/controllers/wringer_compat_controller_test.rb` | No new cache-contract test was added here; refresh-preservation coverage for `json_ld` remains unproven. | Visible in `/websites.json?term=...`; not yet exposed by the new read-only cache endpoints. |
| `name` | Cache row name is updated from refreshed content metadata when available. Failed refreshes may still update metadata without replacing HTML. | `Distillator::FetchCacheStore#write_result` assigns `name` from normalized fetch results before the 2xx-only HTML overwrite branch. | `test/services/distillator/fetch_cache_store_test.rb` | No missing test identified for current 2xx and non-2xx name-update behavior. | Visible in lookup results and the serialized read-only cache JSON endpoints. |
| `scrape_date` | Last attempted scrape time, whether the fetch succeeded or failed. | `Distillator::FetchCacheStore#write_result` sets `scrape_date` on every refresh attempt. | `test/services/distillator/fetch_cache_store_test.rb`, `test/services/distillator/cache_refresh_preview_test.rb`, `test/controllers/distillator/cache_controller_test.rb`, `docs/distillator_phase1_wringer_readiness.md` | No missing test identified for current cache-store and preview semantics. | Important for UI messaging, refresh previews, and the read-only JSON cache endpoints. |
| `successful_refresh` | Last successful 2xx content refresh time. It only changes when fresh content is successfully written. | `Distillator::FetchCacheStore#write_result` updates `successful_refresh` only in the 2xx branch. | `test/services/distillator/fetch_cache_store_test.rb`, `test/services/distillator/cache_refresh_preview_test.rb`, `test/controllers/distillator/cache_controller_test.rb`, `docs/distillator_phase1_wringer_readiness.md` | No missing test identified for current 2xx-update and 404/500 preservation behavior. | Important for UI confidence indicators and the read-only JSON cache endpoints. |
| `http_response_code` | Stores the latest HTTP result code. It is updated on both successful and non-2xx refreshes so callers can see the last attempt outcome while preserved HTML remains available. | `Distillator::FetchCacheStore#write_result` assigns `http_response_code` before the 2xx-only content branch; `WebsitesController#wring` returns it as `http_code` in JSON. | `test/services/distillator/fetch_cache_store_test.rb`, `test/controllers/wringer_compat_controller_test.rb`, `test/controllers/distillator/cache_controller_test.rb` | No missing test identified for current success, non-2xx, and failure-shaped JSON compatibility output. | Visible in `format=json` and the read-only `wring_json`/serialized cache endpoints. |
| `signals` | Wringer-compatible fetch signals capture network/content state and are preserved in cache and JSON output. | `Distillator::FetchCacheStore#normalize_fetch_cache_signals` writes normalized `signals`; controller JSON returns them unchanged. | `test/services/distillator/fetch_cache_store_test.rb`, `test/controllers/wringer_compat_controller_test.rb`, `test/services/distillator/fetch_service_test.rb`, `test/controllers/distillator/cache_controller_test.rb` | No missing test identified for current cache-store and JSON compatibility output. | Visible in `format=json` and the read-only `wring_json`/serialized cache endpoints. |
| `hints` | Wringer-compatible hints preserve fetch diagnoses such as redirect/content observations and empty-body warnings. | `Distillator::FetchCacheStore#normalize_fetch_cache_hints` writes normalized `hints`; controller JSON returns them unchanged. | `test/services/distillator/fetch_cache_store_test.rb`, `test/controllers/wringer_compat_controller_test.rb`, `test/services/distillator/fetch_service_test.rb`, `test/controllers/distillator/cache_controller_test.rb` | No missing test identified for current cache-store and JSON compatibility output. | Visible in `format=json` and the read-only `wring_json`/serialized cache endpoints. |
| `final_url` | Final resolved URL after redirects is stored with the cache row and returned to JSON callers. | `Distillator::FetchCacheStore#write_result` persists `final_url`; `WebsitesController#wring` returns it in JSON. | `test/services/distillator/fetch_cache_store_test.rb`, `test/controllers/wringer_compat_controller_test.rb`, `test/services/distillator/native_fetch_test.rb`, `test/controllers/distillator/cache_controller_test.rb` | No missing test identified for current cache-store and JSON compatibility output. | Visible in `format=json` and the read-only `wring_json`/serialized cache endpoints. |
| `redirect_chain` | Ordered list of visited URLs; defaults to `[]` rather than `nil`; stored with cache and returned in JSON. | `Distillator::FetchCacheStore#write_result` normalizes `redirect_chain` to an array; controller JSON returns it unchanged. | `test/services/distillator/fetch_cache_store_test.rb`, `test/controllers/wringer_compat_controller_test.rb`, `test/services/distillator/native_fetch_test.rb`, `test/controllers/distillator/cache_controller_test.rb` | No missing test identified for current normalization and JSON compatibility output. | Visible in `format=json` and the read-only `wring_json`/serialized cache endpoints. |
| `format=raw` | Compatibility output that renders cached `html` only, with frame protections removed. It is not a new API contract. | `WebsitesController#wring` renders `cache.html` and clears `X-Frame-Options`; `Distillator::CacheController#raw` provides read-only cache inspection output with the same frame-header removal. | `test/controllers/wringer_compat_controller_test.rb`, `test/controllers/distillator/cache_controller_test.rb` | No missing test identified for current raw compatibility output. | Directly user-visible in browser/manual verification flows, the read-only raw cache endpoint, and the implemented `raw_view` HTML inspection page. |
| `format=html` | Compatibility output that redirects to the websites UI with the legacy success notice. It is not a new API contract. | `WebsitesController#wring` redirects to `websites_path` with `Website was successfully wrung.` | `test/controllers/wringer_compat_controller_test.rb` | No missing test identified for current redirect behavior after cache hit and forced refresh. | Directly user-visible in existing UI flows; no new cache mutation UI has been added. |
| `format=json` | Compatibility output that returns exactly `html`, `signals`, `hints`, `final_url`, `redirect_chain`, and `http_code`. It is not a new API contract. | `WebsitesController#wring` serializes the cached row/result into the legacy JSON shape; `Distillator::CacheController#wring_json` provides the same shape from cache only. | `test/controllers/wringer_compat_controller_test.rb`, `test/controllers/distillator/cache_controller_test.rb` | No missing test identified for current JSON compatibility shape, including empty redirect chains and failure-shaped payloads. | Directly user-visible in current consumers, the read-only `wring_json` cache endpoint, and the implemented `wring_json_view` HTML inspection page. |
| `force_scrape` | Forces a fresh attempt even when cache exists and scrape_date is recent. | `Distillator::FetchCacheStore#should_refresh?` returns true when `force_scrape` is truthy. | `test/services/distillator/fetch_cache_store_test.rb`, `test/controllers/wringer_compat_controller_test.rb`, `test/services/distillator/cache_refresh_preview_test.rb`, `test/controllers/distillator/cache_controller_test.rb` | No missing test identified for current cache-store, controller plumbing, and preview semantics. | Important for manual refresh controls and preview endpoints, but should remain a compatibility flag. |
| `force_scrape_every_hrs` | Forces refresh only when cached `scrape_date` is older than the threshold; `0` means always refresh; blank means do not force based on age. | `Distillator::FetchCacheStore#should_refresh?` compares `scrape_date` against `now - hours`. | `test/services/distillator/fetch_cache_store_test.rb`, `test/controllers/wringer_compat_controller_test.rb`, `test/services/distillator/cache_refresh_preview_test.rb`, `test/controllers/distillator/cache_controller_test.rb` | No missing test identified for current threshold, controller plumbing, and preview semantics. | Important for preview/explanation endpoints, but semantics must stay Wringer-compatible. |
| `include_fragment` | Fragment is ignored by default and only included in the cache key when explicitly requested. | `Distillator::WringerUrlKey` strips fragments unless `include_fragment` is truthy; `FetchCacheStore` uses the generated key. | `test/services/distillator/wringer_url_key_test.rb`, `test/controllers/wringer_compat_controller_test.rb`, `test/services/distillator/cache_refresh_preview_test.rb` | No missing test identified for current controller/store fragment-key compatibility behavior. | Important for cache inspection clarity and duplicate-row explanation in the JSON preview/read-only endpoints. |
| `absolute_src` | On successful 2xx refresh only, Wringer rewrites relative `src` and `href` to absolute URLs for compatibility display. Failed refreshes must not rewrite preserved old HTML. | `Distillator::FetchCacheStore#write_fetch_result` calls `Distillator::HtmlAbsolutizer.call` only in the 2xx branch when `absolute_src` is truthy. | `test/services/distillator/html_absolutizer_test.rb`, `test/services/distillator/fetch_cache_store_test.rb`, `test/controllers/wringer_compat_controller_test.rb` | No missing test identified for current controller plumbing and cache-store success-only rewrite behavior. | User-visible in raw/html verification surfaces and in cached HTML exposed by raw endpoints. |
| `json_post` | Compatibility mode fetches through POST, preserves JSON/content hints, and must still preserve last known good HTML on failed refreshes. | `Distillator::NativeFetch` now performs native POST fetches with JSON-aware metadata; `Distillator::FetchService` marks eligible POST requests as `native_http_post`; `Distillator::FetchCacheStore` persists the result through the same cache contract as GET fetches. | `test/services/distillator/native_fetch_test.rb`, `test/services/distillator/fetch_service_test.rb`, `test/services/distillator/fetch_cache_store_test.rb`, `test/controllers/wringer_compat_controller_test.rb`, `test/services/dsl_algorithm_runner_test.rb` | No missing test identified for current native POST fetch/cache semantics. | UI and operators can now treat this as a first-class Distillator cache path. |
| `use_phantomjs` | Compatibility mode routes fetch through PhantomJS Cloud for rendered content. Distillator now preserves this through an explicit rendered-fetch abstraction, while still using the legacy PhantomJS service rather than a modern renderer. | `Distillator::RenderedFetch` selects `legacy_phantomjs` or `disabled`; `Distillator::Renderers::LegacyPhantomjsRenderer` owns PhantomJS URL generation, missing-key fallback, and renderer metadata; `Distillator::NativeFetch` dispatches rendered requests there. | `test/services/distillator/rendered_fetch_test.rb`, `test/services/distillator/renderers/legacy_phantomjs_renderer_test.rb`, `test/services/distillator/fetch_cache_store_test.rb`, `test/services/distillator/fetch_service_test.rb`, `test/controllers/wringer_compat_controller_test.rb` | Modern renderer replacement remains deferred, but current compatibility behavior is directly covered. | UI should treat this as an explicit compatibility renderer strategy, not as a modern-renderer migration. |
| `iframe` suffix behavior | When the encoded `uri_key` ends with `iframe`, Wringer forces rendered JSON mode and extracts the first child frame’s HTML, but only when the fetch result is successful enough to use returned content. | `WebsitesController#wring` forces `use_phantomjs` for `iframe` suffixes; `Distillator::NativeFetch` flags iframe requests; `Distillator::Renderers::LegacyPhantomjsRenderer` extracts the first child frame HTML from PhantomJS JSON. | `test/services/distillator/renderers/legacy_phantomjs_renderer_test.rb`, `test/services/distillator/fetch_cache_store_test.rb`, `test/controllers/wringer_compat_controller_test.rb` | No missing test identified for current rendered-cache and controller behavior. | Mostly hidden from UI, but important for debug/read-only verification tools because it changes stored HTML semantics. |

## Notes For Follow-up Work

- This contract is intentionally narrower than a future Distillator-native cache model. It documents what must remain true while Wringer compatibility is still the migration target.
- Any UI work that exposes cache state should use these semantics first:
  - `scrape_date` means last attempt.
  - `successful_refresh` means last successful 2xx write.
  - preserved `html` can coexist with a failed latest `http_response_code`.
- The completed cache inspection work now includes both endpoint and read-only HTML inspection pages:
  - `GET /distillator/cache`
  - `GET /distillator/cache/:id`
  - `GET /distillator/cache/:id/raw_view`
  - `GET /distillator/cache/:id/wring_json_view`
  - `GET /distillator/cache/preview`
  - `GET /distillator/cache/compare?uri=...`
  - `GET /distillator/cache.json`
  - `GET /distillator/cache/:id.json`
  - `GET /distillator/cache/:id/raw`
  - `GET /distillator/cache/:id/wring_json`
  - `GET /distillator/cache/preview.json`
- `Distillator::CacheIndexQuery` now owns cache-index filtering, sorting, and pagination behavior:
  - SQL-backed filters: `term`, `http_response_code`, `has_html`, `network_status`, `health`, `status_group`, `content_type`, `hint`, `redirected`, `last_attempt`, `last_success`
  - SQL-backed sorts: `id`, `updated_at`, `scrape_date`, `successful_refresh`, `http_response_code`, `name`, `normalized_url`, `uri_key`, `html_bytes`, `body_bytes`
- Cache index HTML URLs canonicalize blank and invalid params to stable shareable URLs. JSON endpoints normalize internally but keep the existing array response shape and pagination headers.
- The read-only cache index now follows the Condenser Websites table pattern:
  - a single GET form wrapped around the table
  - sortable column headers in the first `thead` row
  - filters directly under corresponding columns in the second `thead` row
  - like Websites, current `sort` and `direction` are preserved through hidden fields when applying filters
  - `per_page` is only preserved in the form when it differs from the default page size
  - compact quick-filter summary links instead of a dominant card block
  - no refresh mutation controls on the index
  - pagination headers: `X-Page`, `X-Per-Page`, `X-Total-Count`, `X-Total-Pages`
- `Distillator::CacheSummary` is relation-aware and now SQL-backed for standard cards through materialized cache fields.
- Materialized cache-health fields now live directly on `distillator_fetch_caches`:
  - `health_status`
  - `health_severity`
  - `health_reasons`
  - `html_bytes`
  - `body_bytes`
  - `redirected`
  - `network_status`
  - `content_type`
  - `hint_keys`
- `bin/rails distillator:cache:backfill_health` backfills those materialized fields for older cache rows without making network calls.
- Cache health states currently exposed by the serializer and UI are:
  - `healthy`
  - `preserved_after_failure`
  - `never_fetched`
  - `network_failed`
  - `blocked`
  - `empty_body`
  - `redirect_changed`
  - `stale`
  - `unknown`
- Mode-aware operator links now resolve read-only cache destinations for:
  - legacy mode
  - internal mode
  - shadow mode via `/distillator/cache/compare`
  - replay mode with a warning that replay may not represent persisted live cache
- Statement trace-step views now expose both `Open active cache` and `Open Wringer cache` links without triggering fetches, and shadow mode routes the active link to `/distillator/cache/compare`.
- `Distillator::CacheCompare` now labels cache data sources explicitly:
  - `legacy_source`: `remote_wringer`, `injected_lookup`, or `unavailable`
  - `legacy_lookup_error`: populated when legacy lookup fails
  - `distillator_source`: `local_fetch_cache`
- The read-only cache inspector now has CSS-only operator polish for:
  - compact quick-filter strip
  - Websites-style table header/filter layout
  - badge severity colors
  - monospace cache identities and JSON blocks
  - compare same/different highlighting
- Read-only cache UI pages are implemented, but refresh mutation UI remains deferred.
- Audit-event work remains deferred.
- `json_post` now has native Distillator fetch/cache parity for POST-mode refreshes.
- `use_phantomjs` now has an explicit Distillator renderer strategy, but a modern renderer replacement is still deferred.
- Follow-up tasks should update this document only when behavior or proof changes, not to speculate about future native-only semantics.
