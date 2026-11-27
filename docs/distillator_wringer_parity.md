# Distillator to Wringer Parity Matrix

This matrix maps Wringer-facing behavior to Distillator coverage and highlights the few intentional legacy quirks we still preserve during migration.

## URL Safety

| Behavior | Distillator coverage | Notes |
| --- | --- | --- |
| `localhost` rejected | `test/services/distillator/fetch_guard_test.rb` | Matches Wringer block behavior. |
| `127.0.0.1` rejected | `test/services/distillator/fetch_guard_test.rb`, `test/services/distillator/fetch_service_test.rb` | Blocked before native fetch. |
| `10.0.0.1` rejected | `test/services/distillator/fetch_guard_test.rb` | Matches Wringer private IPv4 block. |
| `169.254.169.254` rejected | `test/services/distillator/fetch_guard_test.rb` | Matches Wringer link-local block. |
| private IPv6 rejected | `test/services/distillator/fetch_guard_test.rb` | Covers loopback, unique-local, and link-local IPv6. |
| `file://` rejected | `test/services/distillator/fetch_guard_test.rb` | Matches Wringer non-HTTP block. |
| public HTTP/HTTPS allowed | `test/services/distillator/fetch_guard_test.rb`, `test/services/distillator/url_safety_policy_test.rb` | Explicit public allow path. |
| DNS resolves to private IP | `test/services/distillator/fetch_guard_test.rb`, `test/services/distillator/url_safety_policy_test.rb` | Distillator fails closed. |
| DNS returns `[]` | `test/services/distillator/fetch_guard_test.rb`, `test/services/distillator/url_safety_policy_test.rb` | Intentional hardening over old Wringer allow-through. |
| DNS raises timeout/error | `test/services/distillator/fetch_guard_test.rb`, `test/services/distillator/url_safety_policy_test.rb` | Intentional hardening over ambiguous legacy behavior. |
| unsafe redirect target rejected | `test/services/distillator/fetch_guard_test.rb` | Redirect chain is rechecked. |
| unsafe final URL rejected | `test/services/distillator/fetch_guard_test.rb`, `test/services/distillator/fetch_service_test.rb` | Final URL is rechecked after fetch. |
| blocked reason visible in diagnostics | `test/services/distillator/cache_refresh_preview_test.rb`, `test/controllers/distillator/cache_controller_test.rb`, `test/services/distillator/fetch_service_test.rb` | Preview exposes `guard_reason` / `guard_error`; blocked fetch metadata keeps `guard_reason`. |

## URL Key Generation

| Behavior | Distillator coverage | Notes |
| --- | --- | --- |
| core Wringer examples | `test/services/distillator/wringer_url_key_test.rb` | Canonical parity cases. |
| trailing slash normalization | `test/services/distillator/wringer_url_key_test.rb` | Preserved. |
| fragment excluded by default | `test/services/distillator/wringer_url_key_test.rb` | Preserved. |
| `include_fragment=true` | `test/services/distillator/wringer_url_key_test.rb` | Preserved. |
| `include_fragment="false"` / `"true"` | `test/services/distillator/wringer_url_key_test.rb` | Preserved. |
| malformed URL | `test/services/distillator/wringer_url_key_test.rb` | Raises for controller handling. |
| blank URL | `test/services/distillator/wringer_url_key_test.rb` | Raises deterministically. |
| already-escaped URL | `test/services/distillator/wringer_url_key_test.rb` | Preserves legacy `"Error: not a URI"` path. |
| uppercase scheme quirk | `test/services/distillator/wringer_url_key_test.rb` | Intentional legacy compatibility quirk, not a normalization improvement. |

## Wringer-Compatible JSON Contract

| Behavior | Distillator coverage | Notes |
| --- | --- | --- |
| top-level JSON keys `html/signals/hints/final_url/redirect_chain/http_code` | `test/controllers/wringer_compat_controller_test.rb`, `test/controllers/distillator/cache_controller_test.rb` | Tests fail if keys are removed. |
| redirect metadata survives replay | `test/controllers/wringer_compat_controller_test.rb`, `test/controllers/distillator/cache_controller_test.rb`, `test/services/distillator/fetch_response_contract_test.rb` | Covers `redirect_type`, `redirected`, and `final_url`. |
| failure metadata survives replay | `test/controllers/wringer_compat_controller_test.rb`, `test/services/distillator/fetch_response_contract_test.rb` | Timeout / blocked / failure signals stay visible. |
| fetch response canonical service contract | `test/services/distillator/fetch_response_contract_test.rb` | Covers legacy, internal, shadow, replay, and blocked responses. |

## POST / `json_post`

| Behavior | Distillator coverage | Notes |
| --- | --- | --- |
| POST command dispatch | `test/services/distillator/cache_fetch_command_test.rb` | `fetch_kind: "post"` maps to `json_post`. |
| POST success metadata persisted | `test/services/distillator/fetch_cache_store_test.rb` | Captures body, status code, content type, and request method. |
| POST cached replay contract | `test/controllers/wringer_compat_controller_test.rb` | Contract preserved for replayed JSON payloads. |
| empty POST response hint | `test/controllers/wringer_compat_controller_test.rb`, `test/services/distillator/fetch_cache_store_test.rb` | `empty_body` preserved. |
| failed POST response metadata | `test/services/distillator/fetch_cache_store_test.rb` | Deterministic failure metadata retained. |

## Cache Refresh Semantics

| Behavior | Distillator coverage | Notes |
| --- | --- | --- |
| cache miss refreshes | `test/services/distillator/cache_refresh_preview_test.rb`, `test/services/distillator/fetch_cache_store_test.rb` | Shared decision path. |
| `force_scrape=true` | `test/services/distillator/cache_refresh_preview_test.rb`, `test/services/distillator/fetch_cache_store_test.rb` | Preview and fetch agree. |
| `force_scrape_every_hrs=24` | `test/services/distillator/cache_refresh_preview_test.rb`, `test/services/distillator/fetch_cache_store_test.rb` | Shared stale decision. |
| `force_scrape_every_hrs=0` | `test/services/distillator/cache_refresh_preview_test.rb`, `test/services/distillator/fetch_cache_store_test.rb`, `test/controllers/distillator/cache_controller_test.rb` | Explicit refresh in preview and fetch. |
| very large `force_scrape_every_hrs` | `test/services/distillator/cache_refresh_preview_test.rb`, `test/controllers/distillator/cache_controller_test.rb` | Stays fresh. |
| missing scrape timestamp | `test/services/distillator/cache_refresh_preview_test.rb`, `test/services/distillator/fetch_cache_store_test.rb` | Explicit `missing_scrape_date`. |
| stale vs fresh diagnostics | `test/controllers/distillator/cache_controller_test.rb` | Preview and show page expose reason. |

## Absolute `src` / `href` Rewriting

| Behavior | Distillator coverage | Notes |
| --- | --- | --- |
| `/image.png` | `test/services/distillator/html_rewriter_test.rb` | Matches Wringer behavior. |
| absolute external URL unchanged | `test/services/distillator/html_rewriter_test.rb` | Matches Wringer behavior. |
| `../image.png` | `test/services/distillator/html_rewriter_test.rb` | Matches Wringer behavior. |
| non-greedy additional attributes | `test/services/distillator/html_rewriter_test.rb` | Matches Wringer behavior. |
| invalid path preserved safely | `test/services/distillator/html_rewriter_test.rb` | Fail-safe behavior. |
| `href` and `src` support | `test/services/distillator/html_rewriter_test.rb` | Rewriter tested independently. |

## Raw Cached HTML

| Behavior | Distillator coverage | Notes |
| --- | --- | --- |
| raw cached body retrievable | `test/controllers/distillator/cache_controller_test.rb`, `test/controllers/wringer_compat_controller_test.rb` | Compatibility preserved. |
| script-bearing raw HTML does not lose bytes | `test/controllers/distillator/cache_controller_test.rb` | Body still returned intact. |
| raw endpoint hardened with CSP sandbox | `test/controllers/distillator/cache_controller_test.rb` | Reduces app-origin script execution risk. |
| admin preview stays escaped and warns operators | `test/controllers/distillator/cache_controller_test.rb` | `raw_view` is operator-facing, not direct execution. |

## Fetch-Service Boundary Audit

| Behavior | Distillator coverage | Notes |
| --- | --- | --- |
| no private-method `send` for normal collaboration | source audit in `app/services/distillator/*.rb` | Replaced `FetchService.send(...)` cross-service calls with direct public helper calls. |

