# Le Point de Vente / Culture Mauricie — numbered filters and page labels

## Why this is a separate investigation

Historic configured ResourceList page-2 URLs include three **different** selected inventories:

- `culturemauricie_lepointdevente-com`, `locality=2234`, `radius=31`, multiple category keys represented in one encoded JSON `categories` query value.
- `culturemauricie_lepointdevente-com-RList`, `locality=2234`, `radius=30`, `categories={"1":0}`.
- `culturemauricie_lepointdevente-com-RList`, `locality=2234`, `radius=30`, `categories={"11":0}`.

These are distinct Source/filter contracts. Do not collapse or deduplicate the filters across chains. Preserve `q=`, `type=physical`, `locality`, `radius`, category JSON, language and other selected parameters. Change only the designated numbered `page` parameter. If the website also has a separate `p` query key, choose `PAGE_PARAMETER=page` explicitly and keep `p` unchanged.

## Observed external clue, not verified for these filters

A separately indexed public Le Point de Vente listing displayed a French pagination summary of the form `Page 11 de 75`. **This was not observed in the three configured Culture Mauricie selections**, whose filtered URLs could not be fetched by this review environment. Hence it is not evidence for their exact final-page counts or content.

`ResourceLists::NumberedPageLabel` now detects *candidate* `Page X de Y` text in an HTML body, checking requested page number and rejecting absent/ambiguous/conflicting labels. It is purely read-only **advisory** evidence; a text match may occur outside the pager. A trustworthy HTML selector and stable result-set evidence must establish authenticity before this can become an authoritative termination rule. The existing 90% HTML link heuristic remains advisory, and a one-page short link count is not evidence of missing events.

## Targeted local read-only trial

Try just pages 1–3 for one selected filter chain:

```bash
bundle exec ruby test/services/resource_lists/numbered_page_query_test.rb
bundle exec ruby test/services/resource_lists/numbered_page_label_test.rb

bundle exec ruby script/resource_list_numbered_probe.rb \
 'https://lepointdevente.com/?q=&type=physical&locality=2234&radius=30&categories=%7B%221%22%3A0%7D&lang=fr&page=1' \
 3 /tmp/resource-list-trials/lepointdevente-categ1-r30

jq '{stop_reason, verified_completeness, captures: [
 .captures[] | {page, status, page_label, next_link_observed, short_page_stop,
 numbered_link_urls, event_link_count}]} ' \
 /tmp/resource-list-trials/lepointdevente-categ1-r30/probe.json
```

Save snapshots and inspect the exact markup around the pagination summary before assuming it is part of the actual filtered pager. The generic probe's `event_link_count=0` is expected unless `EVENT_LINK_XPATH` is explicitly set. A full capture must compare event IDs/URLs and selected-filter correctness, including any differences between the `radius=30` and `radius=31` chains.

**No writes:** This trial cannot alter selected Sources, refresh Statements, retire ResourceList Webpages, archive events, or change Artsdata exports. The PR still lacks a production collector and an atomic last-good-preserving membership update.

## Verified filtered sliding-page window (local read-only trial)

The operator's filtered `radius=30`, `categories={"1":0}` capture returned HTTP 200 on pages 1–3, with
unchanged selected filters and a visible numbered-page window:

| Current page | Raw same-filter page targets | Accessible next-number link |
|---|---|---|
| 1 | 1#skip-content-anchor, 1#, 2 | 2 |
| 2 | 2#skip-content-anchor, 3, 4 | 3 |
| 3 | 3#skip-content-anchor, 2, 4 | 4 |

The fragment-bearing URLs are not pagination. Thus genuine numeric windows are
`[2]`, `[3,4]`, `[2,4]`. The changing page-label observations
(`1/2`, `2/4`, `3/4`) **must not be used as final-page totals**:
this source uses a sliding window and the label's DOM provenance is not yet established.

`ResourceLists::NumberedPagerWindow` now excludes fragment links, validates
the origin/path and exact selected filters using `NumberedPageQuery`, and records
`pager_window_numbers` plus `next_page_number_link_observed`. The legacy
`next_link_observed` field remains as a compatibility alias, **meaning only that
a numbered anchor to current+1 exists, not that a semantic Next control exists**.
The old `NumberedPagerEvidence` validator rejects sliding windows and must
not be applied to this site as an end-of-list proof.

The probe remains read-only and bounded; absent next-number links, apparent
page-label totals, 90% short-page hints, and its page cap are all **inconclusive**
without verified terminal evidence. Do not mutate Source/ResourceList records
or assume completeness from pages 1–3.

After updating the branch, rerun the short local capture and inspect:

```bash
bundle exec ruby test/services/resource_lists/numbered_pager_window_test.rb

bundle exec ruby script/resource_list_numbered_probe.rb \
  'https://lepointdevente.com/?q=&type=physical&locality=2234&radius=30&categories=%7B%221%22%3A0%7D&lang=fr&page=1' \
  5 /tmp/resource-list-trials/lepointdevente-windowed

jq '.captures[] | {page, pager_window_numbers,
  next_page_number_link_observed, page_label,
  short_page_stop}' /tmp/resource-list-trials/lepointdevente-windowed/probe.json
```

