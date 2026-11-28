# Signé Laval JSON ResourceList — read-only inspection

Scope: `signelaval-com`, historical Condenser ResourceList Webpages:
`https://signelaval.com/fr/evenements/liste.json?page=1` through `?page=14`.
These are historical configurations, **not evidence of a currently valid 14-page calendar**.

The public calendar returned a browser-verification response when opened through external web tooling on 2026-11-27. Direct access to the `.json` URL was unavailable from the review environment. An archived Condenser cassette references an older individual-event URL format; that does not establish whether the current JSON endpoint is active.

`ResourceLists::JsonPageObservation` reports HTTP/content-type/parse validity,
JSON envelope shape and arrays without assuming event identities or terminal status.
`script/resource_list_json_probe.rb` issues only a few explicitly enumerated GETs,
preserves the configured query filters and stores raw bodies plus a compact
`probe.json` diagnostic. It stops on any untrusted response. It does not
change Sources, Webpages or Statements.

Try pages 1, 2, 14 and an out-of-range boundary candidate 15:

```bash
bundle exec ruby script/resource_list_json_probe.rb \
  'https://signelaval.com/fr/evenements/liste.json?page=1' \
  1,2,14,15 /tmp/resource-list-trials/signelaval-json
jq '{stop_reason, verified_completeness, captures: [.captures[] | {page,http_status,content_type,status,errors,top_keys,array_candidates}]}' \
  /tmp/resource-list-trials/signelaval-json/probe.json
```

A 200 response with an empty array **cannot** establish the last page; a 200 HTML
challenge or unexpected effective URL is a hard diagnostic failure. The
payload's real event-list and pagination metadata fields must be identified
before designing a JSON-aware collection/termination contract. No last-good
retirement, archiving or export updates are allowed from these receipts.

Standalone tests:

```bash
bundle exec ruby test/services/resource_lists/json_page_observation_test.rb
```
