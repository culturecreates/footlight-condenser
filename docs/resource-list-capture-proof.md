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

For sites with a stable per-page number of event links, the user-selected
stopping rule is: **include the current page and stop when its extracted event
link count is strictly less than 90% of the previous page's count.**

`ResourceLists::ShortPageStop.stop?(previous_count:, current_count:)`
uses exact integer comparison (`current_count * 10 < previous_count * 9`)
to avoid floating-point ambiguity. The first page cannot trigger this rule;
previous count zero cannot trigger it. Counts must represent successfully
extracted event URLs, not all page anchors. The page that triggers the rule
is **included**.

Hector-Charland captured example: 42, 42, 42, 42, 23 ⇒ stop after page 5,
191 distinct URLs; boundary probes pages 6 and 7 each have zero events.

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
