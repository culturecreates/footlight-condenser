# Distillator Phase 1 Wringer Readiness

This audit tracks each required Wringer-compatible behavior against the current
Distillator implementation. A behavior is only marked `tested` when the named
test exercises the Distillator-owned path, not just legacy Wringer behavior.

Status values:
- `legacy-only`: preserved only through the legacy fetch path.
- `native`: implemented in Distillator, but not yet proven by a Distillator-path test.
- `shadow-only`: observed only in shadow comparison mode.
- `tested`: implemented in Distillator and exercised by the named test.
- `open`: not ready for cutover; must also appear in Open items.

| Required behavior | Status | Owning code path | Test file proving behavior | Migration risk | Cutover requirement |
|---|---|---|---|---|---|
| GET /websites/wring route | tested | `config/routes.rb`, `app/controllers/websites_controller.rb` | `test/controllers/wringer_compat_controller_test.rb` | Low: route drift would break callers immediately. | Keep the route and controller action wired to `Distillator::FetchCacheStore.fetch`. |
| raw response format | tested | `app/controllers/websites_controller.rb`, `app/services/distillator/fetch_cache_store.rb` | `test/controllers/wringer_compat_controller_test.rb` | Medium: wrong body rendering would change caller-visible HTML. | Preserve raw body passthrough from cached Distillator HTML. |
| json response format | tested | `app/controllers/websites_controller.rb`, `app/services/distillator/fetch_cache_store.rb` | `test/controllers/wringer_compat_controller_test.rb` | High: response-key drift would break Wringer consumers. | Keep JSON keys and value shapes aligned with the compatibility contract. |
| html redirect/default response | tested | `app/controllers/websites_controller.rb` | `test/controllers/wringer_compat_controller_test.rb`, `test/controllers/websites_controller_test.rb` | Low: fallback UX regression is visible but localized. | Preserve redirect-to-websites behavior for non-raw and non-json requests. |
| invalid params no_content behavior | tested | `app/controllers/websites_controller.rb`, `app/services/distillator/wringer_url_key.rb` | `test/controllers/wringer_compat_controller_test.rb`, `test/services/distillator/wringer_url_key_test.rb` | Medium: raising instead of returning `204` would break compatibility callers. | Keep invalid or missing URI handling on the Distillator controller path. |
| /websites.json?term lookup | tested | `app/controllers/websites_controller.rb`, `app/services/distillator/fetch_cache_store.rb` | `test/controllers/wringer_compat_controller_test.rb` | High: stored-cache lookup is a direct migration dependency. | Continue serving lookup results from `Distillator::FetchCacheStore.lookup_by_term`. |
| URI key generation | tested | `app/services/distillator/wringer_url_key.rb` | `test/services/distillator/wringer_url_key_test.rb` | High: key drift would orphan cache records and lookups. | Preserve Wringer-compatible normalization and escaping rules. |
| no-scheme URL handling | tested | `app/services/distillator/wringer_url_key.rb` | `test/services/distillator/wringer_url_key_test.rb` | Medium: normalization mismatch would miss cache hits. | Keep implicit `http://` normalization before key generation. |
| query preservation | tested | `app/services/distillator/wringer_url_key.rb` | `test/services/distillator/wringer_url_key_test.rb` | High: dropping query strings would alias distinct pages. | Preserve query strings in both normalized URL and `uri_key`. |
| fragment exclusion by default | tested | `app/services/distillator/wringer_url_key.rb` | `test/services/distillator/wringer_url_key_test.rb` | Medium: fragment handling changes cache identity. | Keep default behavior excluding fragments unless explicitly requested. |
| fragment inclusion with include_fragment | tested | `app/services/distillator/wringer_url_key.rb` | `test/services/distillator/wringer_url_key_test.rb` | Medium: include-fragment callers need stable cache identity. | Preserve `include_fragment` support on the Distillator key path. |
| CGI.escape uri_key storage | tested | `app/services/distillator/wringer_url_key.rb`, `app/services/distillator/fetch_cache_store.rb` | `test/services/distillator/wringer_url_key_test.rb`, `test/services/distillator/fetch_cache_store_test.rb` | High: escaping drift breaks storage and lookup parity. | Keep `CGI.escape` as the persisted key format. |
| cache hit | tested | `app/services/distillator/fetch_cache_store.rb` | `test/services/distillator/fetch_cache_store_test.rb` | Medium: unnecessary refetches change behavior and load. | Preserve Distillator cache-hit short-circuiting. |
| force_scrape | tested | `app/services/distillator/fetch_cache_store.rb` | `test/services/distillator/fetch_cache_store_test.rb` | Medium: ignored refresh flags would delay updates. | Keep explicit force-refresh semantics on the Distillator fetch cache path. |
| force_scrape_every_hrs | tested | `app/services/distillator/fetch_cache_store.rb` | `test/services/distillator/fetch_cache_store_test.rb` | Medium: stale-threshold drift changes refresh cadence. | Preserve stale-cache refresh timing logic. |
| successful 2xx cache update | tested | `app/services/distillator/fetch_cache_store.rb` | `test/services/distillator/fetch_cache_store_test.rb` | High: bad writes would corrupt cached source HTML and metadata. | Keep 2xx writes updating HTML, body, name, refresh timestamps, and HTTP code. |
| failed 404 metadata update without overwriting last successful HTML | tested | `app/services/distillator/fetch_cache_store.rb` | `test/services/distillator/fetch_cache_store_test.rb` | High: overwriting good HTML on 404 would damage exports. | Preserve the current 404 write policy before cutover. |
| scrape_date | tested | `app/services/distillator/fetch_cache_store.rb` | `test/services/distillator/fetch_cache_store_test.rb` | Medium: missing scrape timestamps hides refresh behavior. | Keep `scrape_date` updates on refresh attempts. |
| successful_refresh | tested | `app/services/distillator/fetch_cache_store.rb` | `test/services/distillator/fetch_cache_store_test.rb` | Medium: bad success timestamps obscure last-known-good content. | Keep `successful_refresh` updates restricted to successful refreshes. |
| http_response_code | tested | `app/services/distillator/fetch_cache_store.rb`, `app/controllers/websites_controller.rb` | `test/controllers/wringer_compat_controller_test.rb`, `test/services/distillator/fetch_cache_store_test.rb` | High: response-code drift changes stored-404 behavior and compatibility JSON. | Preserve storage and surfacing of HTTP response codes. |
| headers | tested | `app/services/distillator/fetch_cache_store.rb`, `app/services/distillator/fetch_service.rb` | `test/services/distillator/fetch_service_test.rb`, `test/services/distillator/fetch_replay_test.rb` | Medium: header normalization errors can misclassify content. | Keep normalized header extraction on Distillator fetch outputs. |
| signals | tested | `app/services/distillator/fetch_cache_store.rb`, `app/services/distillator/fetch_service.rb` | `test/controllers/wringer_compat_controller_test.rb`, `test/services/distillator/fetch_cache_store_test.rb`, `test/services/distillator/fetch_service_test.rb` | High: signal drift changes downstream error handling. | Preserve Wringer-compatible signal keys from Distillator fetch paths. |
| hints | tested | `app/services/distillator/fetch_cache_store.rb`, `app/services/distillator/fetch_service.rb` | `test/controllers/wringer_compat_controller_test.rb`, `test/services/distillator/fetch_cache_store_test.rb`, `test/services/distillator/fetch_service_test.rb` | Medium: lost hints reduce debugging and retry accuracy. | Keep Distillator hint population and JSON surfacing unchanged. |
| final_url | tested | `app/services/distillator/fetch_cache_store.rb`, `app/services/distillator/fetch_service.rb` | `test/controllers/wringer_compat_controller_test.rb`, `test/services/distillator/fetch_cache_store_test.rb`, `test/services/distillator/fetch_service_test.rb`, `test/services/distillator/export_invariance_test.rb` | High: wrong final URLs can change export semantics and redirect auditing. | Preserve stored and returned final URLs through cutover. |
| redirect_chain | tested | `app/services/distillator/fetch_cache_store.rb`, `app/services/distillator/fetch_service.rb` | `test/controllers/wringer_compat_controller_test.rb`, `test/services/distillator/fetch_cache_store_test.rb`, `test/services/distillator/fetch_service_test.rb`, `test/services/distillator/export_invariance_test.rb` | High: redirect-chain drift can hide unsafe redirects and change parity checks. | Preserve ordered redirect-chain capture and surfacing. |
| absolute_src rewriting for src and href | tested | `app/services/distillator/html_rewriter.rb`, `app/services/distillator/fetch_cache_store.rb`, `app/services/distillator/native_fetch.rb` | `test/services/distillator/html_rewriter_test.rb`, `test/services/distillator/fetch_cache_store_test.rb` | Medium: broken rewriting changes cached HTML consumers see. | Keep parser-based relative `src` and `href` rewriting tied to `absolute_src` on the NativeFetch-backed cache path. |
| json_post behavior | tested | `app/services/distillator/native_fetch.rb`, `app/services/distillator/fetch_cache_store.rb`, `app/services/distillator/fetch_service.rb` | `test/services/distillator/native_fetch_test.rb`, `test/services/distillator/fetch_cache_store_test.rb`, `test/services/distillator/fetch_service_test.rb` | Medium: POST-mode divergence could break specialized callers. | Keep native Distillator POST refreshes preserving JSON metadata and last-known-good HTML on failed refreshes. |
| use_phantomjs behavior | tested | `app/services/distillator/rendered_fetch.rb`, `app/services/distillator/renderers/legacy_phantomjs_renderer.rb`, `app/services/distillator/native_fetch.rb`, `app/services/distillator/fetch_cache_store.rb` | `test/services/distillator/rendered_fetch_test.rb`, `test/services/distillator/renderers/legacy_phantomjs_renderer_test.rb`, `test/services/distillator/fetch_cache_store_test.rb` | Medium: rendered-request drift would break compatibility rendering. | Preserve the explicit rendered-fetch strategy and renderer metadata while modern renderer migration stays deferred. |
| PhantomJS missing-key fallback | tested | `app/services/distillator/renderers/legacy_phantomjs_renderer.rb` | `test/services/distillator/renderers/legacy_phantomjs_renderer_test.rb` | Medium: missing fallback would turn config gaps into outages. | Keep direct-fetch fallback when `PHANTOMJS_API_KEY` is absent. |
| iframe special case | tested | `app/controllers/websites_controller.rb`, `app/services/distillator/renderers/legacy_phantomjs_renderer.rb`, `app/services/distillator/native_fetch.rb` | `test/services/distillator/renderers/legacy_phantomjs_renderer_test.rb`, `test/controllers/wringer_compat_controller_test.rb` | Medium: iframe extraction drift would change stored HTML. | Preserve iframe detection, PhantomJS JSON mode, and child-frame extraction on the rendered compatibility path. |
| materialized cache health summary | tested | `app/services/distillator/cache_health_materializer.rb`, `app/services/distillator/cache_summary.rb`, `app/services/distillator/cache_index_query.rb`, `lib/tasks/distillator_cache.rake` | `test/services/distillator/cache_health_materializer_test.rb`, `test/services/distillator/cache_summary_test.rb`, `test/services/distillator/cache_index_query_test.rb`, `test/tasks/distillator_cache_task_test.rb` | Medium: summary/index regressions would make large cache tables expensive to inspect. | Keep materialized health fields current on write and backfillable without network calls. |
| ERB delimiter escaping | tested | `app/services/distillator/fetch_cache_store.rb`, `app/services/distillator/native_fetch.rb` | `test/services/distillator/fetch_cache_store_test.rb` | Medium: unescaped ERB in cached HTML is a safety risk. | Keep ERB delimiter escaping before NativeFetch-backed cache writes. |
| initial URL guard | tested | `app/services/distillator/fetch_cache_store.rb`, `app/services/distillator/fetch_guard.rb`, `app/services/distillator/fetch_service.rb` | `test/services/distillator/fetch_cache_store_test.rb`, `test/services/distillator/fetch_guard_test.rb`, `test/services/distillator/fetch_service_test.rb` | High: guard regressions would reintroduce unsafe fetches. | Preserve URL guard checks on both cache-store and internal-fetch entry points. |
| redirect URL guard | tested | `app/services/distillator/fetch_cache_store.rb`, `app/services/distillator/fetch_guard.rb`, `app/services/distillator/fetch_service.rb` | `test/services/distillator/fetch_cache_store_test.rb`, `test/services/distillator/fetch_guard_test.rb`, `test/services/distillator/fetch_service_test.rb` | High: unsafe redirects must stay blocked after cutover. | Preserve redirect-chain and final-URL guard enforcement. |
| SSL/Mechanize/Socket error metadata | tested | `app/services/distillator/fetch_cache_store.rb` | `test/services/distillator/fetch_cache_store_test.rb` | Medium: wrong failure metadata changes retries and diagnosis. | Keep failed-network signal and hint mapping stable. |
| export invariance | tested | `app/services/distillator/fetch_service.rb`, `app/services/export_artsdata_service.rb` | `test/services/distillator/export_invariance_test.rb` | High: export drift is the core migration risk. | Keep normalized Artsdata output equivalent across replay, legacy, and internal runs. |
| legacy/internal fetch parity | tested | `app/services/distillator/fetch_service.rb` | `test/services/distillator/fetch_service_test.rb`, `test/services/distillator/export_invariance_test.rb` | High: parity gaps would make full cutover unsafe. | Preserve current internal-path contract and parity assertions before enabling it broadly. |
| default legacy mode | legacy-only | `app/services/distillator/fetch_service.rb`, `app/services/distillator/fetch_mode.rb` | `test/services/distillator/fetch_service_test.rb` | Low for current rollout, but it means production still depends on legacy behavior by default. | Change only when an explicit fetch-mode cutover decision is made and parity evidence stays green. |
| replay fixture compatibility | tested | `app/services/distillator/fetch_replay.rb`, `app/services/distillator/fetch_service.rb` | `test/services/distillator/fetch_replay_test.rb`, `test/services/distillator/export_invariance_test.rb` | Low for production, medium for migration verification quality. | Keep replay response shape stable so migration audits remain trustworthy. |

## Open items

None.

## Wringer Parity Target

Use this focused regression target before calling the migration Wringer-parity-complete:

```bash
DISABLE_SPRING=1 bundle exec rails test \
  test/helpers/statements_helper_test.rb \
  test/helpers/statements_helper_format_datatype_test.rb \
  test/controllers/statements_controller_test.rb \
  test/presenters/trace_presenter_test.rb \
  test/services/statements/refresh_webpage_statements_service_test.rb \
  test/services/distillator/wringer_system_error_matcher_test.rb \
  test/integration/distillator_refresh_then_export_test.rb \
  test/integration/distillator_refresh_rdf_uri_cache_test.rb
```

This target covers the active Wringer-parity surface that most recently drifted:
- SPARQL extraction compatibility and structured abort propagation.
- linked-data `xsd:anyURI` formatting without sentinel leakage.
- single-statement Distillator cache writes through the real DSL fetch seam.
- trace visibility, redirect/session trace persistence, and request-local helper cookies.
- bulk refresh and immediate export-after-refresh behavior.

Keep the existing skipped extraction-drift sentinel in `test/services/dsl_contract_test.rb` skipped until the underlying drift is fixed.

## Current Sign-off

- Compatibility complete:
  - `json_post` native parity is covered.
  - `use_phantomjs` compatibility behavior is preserved through explicit rendered-fetch services.
  - iframe and missing-key fallback behavior are directly tested.
- Native parity complete:
  - GET, POST, and rendered compatibility fetches all write through `Distillator::FetchCacheStore`.
- Operational scalability complete:
  - cache summary and byte-sorting now rely on materialized cache-health fields and a rerunnable backfill task.
- Deferred later-phase work:
  - modern non-Phantom rendered fetch replacement
  - Sidekiq-backed cache refresh orchestration
  - cache mutation UI from the inspector
