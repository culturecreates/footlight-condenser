# Signé Laval — numbered JSON events API (read-only evidence)

## Scope

The current calendar endpoint is:

`https://signelaval.com/api/events?count=12&lavalOnly=true&page=1&type=events`

The former `/fr/evenements/liste.json?page=N` URLs are historical. They must **not** be resurrected for current event discovery, nor should the existing historical Place/Person records be changed.

## Observed API contract — 2026-11-27

A user-supplied JSON response contains the top-level `items` array (12 distinct event IDs) and:

```json
{"pagination":{"page":10,"last_page":16,"per_page":12,"count":12,"total":185,"is_last":false}}
```

The response's metadata identifies it as **page 10**, despite an earlier URL description containing `page=16`. Always verify the effective requested URL against `pagination.page`.

The second user-supplied response is **page 6**, earlier in the page sequence than page 10. It also has **12 items**, `count=12`, `per_page=12`, `total=185`, `last_page=16`, and `is_last=false`. The 12 event IDs from page 6 and 12 event IDs from page 10 are **disjoint (zero overlap)**. This is direct evidence of ordinary, non-cumulative numbered pagination. No sparse page was observed.

**Do not assume cumulative pagination.** The observed `items.length=12`, `pagination.count=12`, and `last_page=16` are consistent with an ordinary numbered API, but a coherent 1–16 capture is still required before treating its inventory as complete.

## Validation and safety

`ResourceLists::SigneLavalPageEvidence` is a read-only page-level contract. It checks:

- `items` is an array, each item has a nonempty unique `id`, and `pagination.count == items.length`.
- Response `pagination.page` equals the requested page; `pagination.per_page` equals the requested `count` query parameter.
- Valid, consistent-looking `total`, `last_page`, and `is_last`, including `last_page == ceil(total/per_page)`.
- `pagination.is_last` agrees with whether the page equals the advertised `last_page`.
- Zero-total calendars are inconclusive, not archiving authority.

Unexpected short intermediate pages remain **warnings**, not stop conditions; no such page has yet been observed. A full 1–16 collection must verify distinct event IDs across pages, consistent metadata, and a complete 185-item inventory. Do not assume completion from one or two page samples.

The generic read-only JSON probe applies this page-level contract only for `signelaval.com/api/events`; other JSON endpoints remain schema-neutral. All existing filters are preserved by `NumberedPageQuery`.

## Local verification

```bash
bundle exec ruby test/services/resource_lists/signe_laval_page_evidence_test.rb

bundle exec ruby script/resource_list_json_probe.rb \
  'https://signelaval.com/api/events?count=12&lavalOnly=true&page=1&type=events' \
  1,6,10,16 /tmp/resource-list-trials/signelaval-current-json

jq '.captures[] | {requested_page: .page, status, errors,
  api_pagination: (.api_pagination | if . then
    {page, count, per_page, total, last_page, is_last, warnings}
    else null end)}' \
  /tmp/resource-list-trials/signelaval-current-json/probe.json
```

The probe saves response snapshots but does not perform a complete calendar capture, mutate Sources/Webpages/Statements, archive events, or alter Artsdata exports. Even valid metadata constitutes **page-level evidence only**. Preserve the last-good inventory until a complete chain and downstream contracts are verified.
