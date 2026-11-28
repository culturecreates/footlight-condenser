# Co-Motion numbered ResourceList — total-count consistency (read-only)

Scope: `co-motion-ca`, currently has manually configured `https://co-motion.ca/spectacles/?page=2` through `?page=10`. The base `https://co-motion.ca/spectacles/` and `?page=1` equivalence has **not** been proven by identical raw snapshots. Do not replace currently selected ResourceList Webpages or their RDF identifiers based on this test.

Observed by public calendar review on 2026-11-27 (not a single coherent capture chain):
- A calendar response for `?page=2` advertised **211 résultats**, a pager ending at **9**, and 24 visible event *occurrences* on that page.
- A response for `?page=9` captured at a **different time** advertised **209 résultats**, with 17 event occurrences (`8 * 24 + 17 = 209`).
- An older `?page=10` snapshot advertised **220 résultats** and a final 4 occurrences (`9 * 24 + 4 = 220`).
- Do **not** combine pages from these observations: totals changed, and the website is live.

`ResourceLists::NumberedTotalEvidence` checks a collector-supplied, same-time batch:
- Page numbers exactly `1..advertised_last`, in order, under a configured page limit.
- An identical `advertised_total` and `advertised_last` on every captured page.
- `advertised_last == ceil(advertised_total / page_size)`.
- Full pages each have `page_size` event *occurrences*, final page has exactly the remainder, and the sum equals the advertised total.
- Timestamps stay within an explicit capture-skew bound; zero-result calendars stay **inconclusive** absent independent empty evidence.

Separate URL and filter safeguards belong to `ResourceLists::NumberedPageQuery`, and real capture evidence (HTTP result, final URL, content type, body fingerprint, authentic selectors) must be gathered by the collector before relying on the arithmetic validator. A website can display a false total or repeat the same 24 cards and still pass these *arithmetic* checks; semantic event identity reconciliation is necessary for stronger proof. None of this permits archiving or automatic removal of Webpages.

Example (synthetic receipt sequence, **not** a live nine-page trial):

```ruby
require_relative "app/services/resource_lists/numbered_total_evidence"
receipts = (1..9).map do |page|
  { page: page, records: page == 9 ? 19 : 24, advertised_total: 211,
    advertised_last: 9, fetched_at: "2026-11-27T18:00:00Z" }
end
result = ResourceLists::NumberedTotalEvidence.call(captures: receipts, page_size: 24)
raise result.errors.join(", ") unless result.terminal_candidate?
```

Unit tests (mocked counts, no site requests, no Rails database):

```bash
ruby test/services/resource_lists/numbered_total_evidence_test.rb
```

**Integration is still pending**: find and validate the site's actual item, result-total and pager-last selectors from a saved raw response; capture all pages in one bounded trial; compare event occurrences and unique event URLs; then evaluate a controlled migration with last-good retention. This work is an additional independent validator, not a production pagination collector.
