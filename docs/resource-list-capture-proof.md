# ResourceList live pagination — capture-proof contract (first tranche)

**Status:** Read-only validator, not integrated with fetching, scheduling, ResourceList imports, bilingual alignment or publishing.

The existing `ResourceLists::Pagination.review!` judges already stored ResourceList pages and handles valid empty pagination tails. That is **not** proof that the live set of fetched pages is complete.

`ResourceLists::PaginationCaptureProof` accepts an explicitly ordered sequence of successfully fetched page receipts and checks:
- The first receipt matches the configured starting URL.
- Every next URL is the **observed link from the previous fetched page**, and every expected next page has a captured receipt.
- No cycles, cross-origin transfers, fetch/extraction failures, duplicate pages, early termination, unbounded page counts or excessively skewed fetch timestamps.
- The last page carries explicit `terminal_evidence: "verified_no_next_link"` from the collector, not an inference from an empty result array.
- All-empty captures produce `no_event_discovery` rather than being accepted as authoritative discovery.
- Results carry a digest of the input receipts for audit and replay.

Example input:

```ruby
proof = ResourceLists::PaginationCaptureProof.call(
  start_url: "https://example.org/events",
  captures: [
    { url: "https://example.org/events", status: "fetched", records: [{ key: "a", url: "https://example.org/a" }],
      next_url: "https://example.org/events?page=2", fetched_at: "2026-11-27T14:00:00Z" },
    { url: "https://example.org/events?page=2", status: "fetched", records: [],
      next_url: nil, terminal_evidence: "verified_no_next_link", fetched_at: "2026-11-27T14:00:10Z" }
  ]
)
raise "Discovery incomplete" unless proof.complete?
```

**Important trust boundary:** A caller could incorrectly claim that it observed no next link. This validator checks the **consistency of evidence supplied by the collector**, not the truthfulness/completeness of the HTML parser or hidden AJAX/network pagination. Do not treat `proof.complete?` alone as production migration evidence.

**Next integration:** Implement an explicitly configured, bounded, fetch-once collector that derives link/terminal evidence from actual snapshots; include SSR/JS and query pagination examples. For bilingual calendars, require both independent pagination chains to pass, then align keys and verify existing RDF identities. Complete selected-list refreshes atomically; preserve last-good evidence on any partial failure. Never auto-remove events because a page is empty or missing.

No changes to Jobs, selected Statements, Webpages, RDF URI minting or Artsdata exports are part of this PR.

Standalone test, no Rails database:
```bash
ruby test/services/resource_lists/pagination_capture_proof_test.rb
```

Locally verified: **11 tests, 23 assertions, 0 failures/errors** (Ruby 3.3.8). Full Rails integration and real-world live fetches have not been run.

## Local multi-page website trial (saved HTML, no database mutation)

1. Open a site's paginated calendar and save **each page's actual HTML** to a separate file, keeping the original page URLs. For JavaScript calendars, save the rendered HTML and record whether pagination was a button/API request rather than an anchor.
2. Copy `script/resource_list_capture_trial.example.json` into the same directory as the saved HTML. Edit `start_url`, `record_xpath`, `next_xpath`, `terminal_xpath`, and the ordered `pages` list. Each `fetched_at` is the actual capture time, not a made-up timestamp.
3. From the Condenser repo, run:

   ```bash
   bundle exec ruby script/resource_list_capture_trial.rb /tmp/site/manifest.json
   ```

   This script reads HTML snapshots only; it does **not** fetch websites, run Condenser Sources or change data. Output contains a per-page count, content fingerprint, observed next URL and overall chain status. Exit code `0` is a complete nonempty chain and `2` is inconclusive/incomplete.
4. Repeat with at least two pagination forms and one deliberate missing middle page. Preserve output and snapshots for review.

**Terminal signal requirement:** The example `terminal_xpath` looks for a disabled Next button. Adapt it to a real, independently identifiable DOM signal on your site's last page. Absence of a Next anchor is *not* sufficient: if there is no independent HTML terminal signal, the result is expected to be `incomplete`. This is a limitation to document, not a reason to invent terminal evidence. For AJAX-only or infinite-scroll sites, the collector needs a later API/JS capture adapter rather than pretending the HTML contains link-based pagination.

**Known limitations:** This initial script does not validate extracted event identities, duplicate cards, actual network responses or source-provided HTTP provenance. It does not substitute for live page coverage, bilingual alignment, or export parity. The record XPath should be chosen to identify one card per event, not a page container. The `next_xpath` must return at most one `@href` attribute. HTML snapshots must correspond to the saved URLs in the manifest.

## Configurable 90% short-page heuristic (experimental)

For sites with a stable number of HTML anchors on full calendar pages, the user-selected
stopping rule is: **include the current page and stop when its total number of
`//a[@href]` links is strictly less than 90% of the previous page's count.**

`ResourceLists::ShortPageStop.stop?(previous_count:, current_count:)`
uses exact integer comparison (`current_count * 10 < previous_count * 9`)
to avoid floating-point ambiguity. The first page cannot trigger this rule;
previous count zero cannot trigger it. Counts are **all HTML anchors having an href**, not event-only URLs. Both pages must be successfully fetched and parsed. The page that triggers the rule is **included**.

Hector-Charland captured example, all anchors: **127, 127, 127, 127, 108** ⇒ stop after page 5 (108/127 = 85%). The event-specific extraction independently found **191 distinct event URLs**. Boundary pages 6 and 7 have 85 anchors and zero event URLs. All-anchor counting is used **only to detect the short page**, not to populate discovered event URLs.

**Trust boundary:** this heuristic is *not* a completeness proof: filters,
dynamic loads, intermittent site failures, and naturally uneven page sizes
can make a page unexpectedly short. In particular, a partially populated
page followed by additional pages would cause premature termination.
Therefore a threshold stop is recorded as `heuristic_short_page` and must
not be converted into `verified_no_next_link` or cause automatic
deletion/archiving of previously discovered events. Keep max-page caps,
explicit fetch validation, snapshot provenance and last-good preservation.
The stricter `PaginationCaptureProof` contract remains unchanged.

Run the standalone tests:

```bash
bundle exec ruby test/services/resource_lists/short_page_stop_test.rb
```


## Live numbered-page probe: bounded by default

`script/resource_list_numbered_probe.rb` now accepts `URL [MAX_PAGES] OUTPUT_DIR`.
The default is **25 pages** (configurable 1–50), and it stops early when the
current fetched page has strictly fewer than 90% of the previous page's
`//a[@href]` links. The triggering page remains included and saved. For
Hector-Charland's saved response counts (127, 127, 127, 127, 108), that
means five requests, not six or seven. The probe does not require an event
XPath for the short-page decision.

```bash
bundle exec ruby script/resource_list_numbered_probe.rb \
  'https://hector-charland.com/programmation-spectacles?page=1' \
  /tmp/resource-list-trials/hector-auto
# Explicit smaller cap for smoke tests:
bundle exec ruby script/resource_list_numbered_probe.rb \
  'https://hector-charland.com/programmation-spectacles?page=1' 5 \
  /tmp/resource-list-trials/hector-capped
```

The JSON records `stop_reason` = `heuristic_short_page`,
`max_pages_reached`, or `challenge_page_detected`, along with
`pages_fetched`, `max_pages`, and `verified_completeness: false`.
Hitting the cap is **not** a successful completion signal. The cap limits
requests and prevents unbounded loops; it does not make an incomplete
ResourceList authoritative. A site with many unrelated navigation links
may never cross the 90% threshold, so the cap is especially important.


## Filters are immutable across numbered pages; repeated HTML is inconclusive

For ResourceLists with selected categories, date intervals, language, venue,
page size or other query parameters, **only** the designated numeric pagination
parameter can change. `ResourceLists::NumberedPageQuery` preserves the complete
multiset of query parameters, including repeated `typeevenement[]` keys and
empty parameters. It supports `page`, `pag`, `p`, `pageNumber`, `p_numb`
and zero-based pagination. Set `PAGE_PARAMETER` if multiple supported keys occur.
The live probe rejects an effective response URL whose host, path, pagination
value, or selected filters differ from the configured request (for example,
a redirect that silently resets category selection). This guard does not prove
server-side application of filters when the response URL remains unchanged.

The Chasse-galerie user trial returned ten HTTP 200 responses with **40 links
and no pagination links on each page**; 9 responses were exactly 51,296 bytes
and the tenth 51,298 bytes. That makes repeated/unapplied pagination plausible,
but bytes alone do not establish identical page contents. The probe now stops
on two consecutive byte-identical HTML responses with
`stop_reason: "repeated_content"`, not a completion claim. Dynamic HTML may
prevent exact repetition even if event inventories repeat; a semantic event-set
fingerprint requires an explicit event selector and will be added separately.

Run:

```bash
bundle exec ruby test/services/resource_lists/numbered_page_query_test.rb
bundle exec ruby script/resource_list_numbered_probe.rb \
 'https://www.chasse-galerie.ca/fr/calendrier?page=1&number_items=48' 10 \
 /tmp/resource-list-trials/chasse-galerie-filtered
# Another supported page parameter:
PAGE_PARAMETER=pag bundle exec ruby script/resource_list_numbered_probe.rb \
 'https://example.org/calendar?pag=1&category=concert' 5 /tmp/test-pag
```

Never use the short-page heuristic, repeated content, or max-page cap as
permission to delete or archive existing events. On ambiguity, retain last-good
ResourceList discovery and surface an incomplete refresh.
