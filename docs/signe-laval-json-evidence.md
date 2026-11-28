# Signé Laval current events API — cumulative-response investigation (read-only)

**Scope correction (2026-11-27):** the historical `/fr/evenements/liste.json?page=N` URLs are no longer used for current event ResourceList discovery. The site's historical Footlight entries are retained for Place and Person purposes; **do not** recreate a dynamic event pagination chain from those old URLs.

The current event endpoint supplied by the operator is:

`https://signelaval.com/api/events?count=12&lavalOnly=true&page=16&type=events`

The operator suspects the response is **cumulative** as `page` increases. This has **not yet been verified**. A cumulative response may make automatic page-by-page ResourceList discovery unnecessary, provided its configured depth covers the inventory and this is validated. A single `page=16` response is *not* automatically proof of an untruncated inventory.

The public calendar returned a browser-verification response and the API could not be retrieved through the review environment. Use read-only local sampling of the actual endpoint before implementing any collector.

`ResourceLists::JsonPageObservation` reports HTTP/content-type/parse validity, JSON envelope shape and arrays, without assuming event identities or terminal status. `script/resource_list_json_probe.rb` performs at most six explicitly numbered GETs, preserves **all other query parameters** and stores response bodies plus compact metadata; it makes no changes to Sources, Webpages or Statements.

Run:

```bash
bundle exec ruby test/services/resource_lists/json_page_observation_test.rb

bundle exec ruby script/resource_list_json_probe.rb \
  'https://signelaval.com/api/events?count=12&lavalOnly=true&page=1&type=events' \
  1,2,16 /tmp/resource-list-trials/signelaval-current-json

jq '{stop_reason, verified_completeness, captures: [.captures[] |
  {page,http_status,content_type,status,errors,top_keys,array_candidates}]}' \
  /tmp/resource-list-trials/signelaval-current-json/probe.json
```

After identifying the event array and stable identity key (ID or event URL), compare
the actual **sets and ordered prefixes** from page 1 to page 2 to page 16:

- Cumulative candidate: each larger response includes every event ID/URL from smaller responses, and the inventories grow with the requested page.
- Distinct pages: items are primarily disjoint or advance rather than include all earlier items.
- Static/capped/ignored `page`: responses are equal or reach a ceiling; inspect API metadata before treating this as terminal.
- Changes during the run: inconsistent identities or ordering make the result **inconclusive**. Stable prefix and count alone are not authoritative completeness evidence.

**Do not** assume `page=16` is the final page, infer completeness from an empty JSON array, replace the existing historical Place/Person source URLs, or archive existing events. If truly cumulative, prefer the working single-endpoint existing extraction rather than implementing unnecessary dynamic ResourceList pagination.

