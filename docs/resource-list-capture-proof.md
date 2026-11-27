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
