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

**Separation of concerns:** Pagination is responsible only for discovering
which pages should be fetched, preserving URL/filter identity, and recording
capture/terminal evidence. Event URLs, records, and event fields are extracted
by the **existing configured DSL**, not a new pagination-specific XPath
extractor. Optional `EVENT_LINK_XPATH` fields in QA probes are for
deliberate offline page analysis only; they are not a production requirement.
End-to-end extraction parity must replay the actual DSL and compare its
outputs against last-good data and Artsdata contracts.

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
The default is **25 pages** (configurable 1–50). A current page with strictly
fewer than 90% of the previous page's `//a[@href]` links records the advisory
`short_page_stop` flag, but **does not end the default probe**. Otherwise a
valid next-page link can be lost, as observed on Co-Motion page 10. To use the
older experimental stopping behavior explicitly, set
`RESOURCE_LIST_PROBE_STOP_ON_SHORT_PAGE=1`; even then, an observed matching
next-page URL suppresses the heuristic stop. This opt-in stop is inconclusive,
never a completeness claim. For
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

The JSON records `stop_reason` = `heuristic_short_page` (opt-in only),
`max_pages_reached`, or `challenge_page_detected`, along with
`pages_fetched`, `max_pages`, and `verified_completeness: false`.
Hitting the cap is **not** a successful completion signal. The cap limits
requests and prevents unbounded loops; it does not make an incomplete
ResourceList authoritative. A site with many unrelated navigation links may never cross the 90% threshold,
so the cap is especially important. `numbered_link_urls` in the per-page probe
receipts records the raw pager links for resolving missing/contradictory next
signals.


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


## Chasse-galerie: link inventory stall check

The HTML hashes differ across pages 1–4, but 40 anchors and 25 unique raw
href destinations were observed on each. This suggests comparing the
**destinations**, rather than byte-for-byte HTML; equality of counts alone
does not establish equality of sets.

`ResourceLists::LinkInventory.fingerprint` uses a sorted unique list of
raw href values (not anchor text or other dynamic HTML). The experimental
live probe now reports `link_inventory_sha256` and
`repeated_links` and terminates with
`repeated_link_inventory` when consecutive page
inventories are identical. This is **inconclusive**, not a complete calendar:
the site might require JS fetching, or have event data without anchor links.

Test against the **already saved HTML** before another network probe:

```bash
bundle exec ruby -rnokogiri -rdigest -rjson -e '
  previous = nil
  (1..4).each do |page|
    file = "/tmp/resource-list-trials/chasse-galerie-repeat/page#{page}.html"
    doc = Nokogiri::HTML(File.binread(file))
    hrefs = doc.xpath("//a[@href]").map { |a| a["href"].strip }.uniq.sort
    sha = Digest::SHA256.hexdigest(JSON.generate(hrefs))
    puts "page=#{page} distinct_links=#{hrefs.size} href_sha=#{sha[0,12]} same_as_previous=#{previous == sha}"
    previous = sha
  end
'
```

If inventories differ, compare the actual href values or site-specific
event cards rather than assuming they repeat. Keep all Source category
and date filters invariant when the numeric page parameter changes.


## Native rendered ResourceLists: filtered URL contract and bounded QA

The active Condenser implementation routes `render_js=true` from a Source
through `Distillator::FetchService` (native eligibility) to
`Distillator::RenderedFetch` and
`Distillator::PhantomjsFetcher`. The Wringer compatibility endpoint
`/websites/wring?use_phantomjs=true` also uses the Distillator cache store
and native rendered fetch; it is not evidence of a separate JavaScript renderer.
Default `DISTILLATOR_RENDERER` is `legacy_phantomjs`;
disabled rendering aborts, and missing `PHANTOMJS_API_KEY` must not
fall back to unrendered HTML.

A renderer request parameter must encode the entire JSON payload, rather than
interpolating the target URL (with `&` and `?`) directly into its
query string. Previous requests risked splitting repeated category selectors
into top-level PhantomJSCloud query keys. The renderer JSON now round-trips
filtered calendar URLs and retains iframe and wait settings. Regression tests
cover `number_items`, repeated `typeevenement[]`,
`pageNumber` and URL-encoded values, including an active
`FetchService.fetch_result(mode: :internal, render_js: true)` path.

For a **small, explicitly authorized paid-renderer live trial**, use:

```bash
cd ~/rails-upgrade/githubed/footlight-condenser-pagination
bundle exec rails test test/services/distillator/phantomjs_fetcher_test.rb \
  test/services/distillator/rendered_fetch_test.rb
# Makes at most 3 PhantomJSCloud calls (each may incur charges).
bin/rails runner script/resource_list_rendered_probe.rb \
  'https://www.chasse-galerie.ca/fr/calendrier?page=1&number_items=48' \
  3 /tmp/resource-list-trials/chasse-rendered
```

The rendered probe calls `FetchService.fetch_result` directly without
calling `FetchCacheStore`, saving or refreshing Statements, or
importing Webpages. It stores per-page rendered HTML and diagnostic metadata,
and stops on an AJAX shell still empty after rendering, a challenge response,
two consecutive identical link destination sets, a less-than-90%-link page,
or a request cap. All stop reasons remain `complete=UNVERIFIED`;
no event deletion, archiving, or automated production cutover follows.

**Unverified:** the actual configured category choices may be dynamically
applied by the site's JavaScript rather than query parameters; checking URLs
and HTML counts is not enough to assert selected-category correctness. Compare
rendered card identities, configured Source XPath, and category selection
before considering completeness. Do not force an unrendered fallback if the
renderer is unavailable.


## Local PostgreSQL 17 test database bootstrap

The checked-in `db/schema.rb` declares `enable_extension "pg_stat_statements"`,
which a normal PostgreSQL role cannot install. For an **isolated local test DB**,
install the extension using PostgreSQL superuser **once per database** before
loading the schema; never point Rails test schema loading at a staging database.

```bash
createdb -p 5433 footlight_condenser_pagination_test
sudo -u postgres psql -p 5433 -d footlight_condenser_pagination_test \
  -c 'CREATE EXTENSION IF NOT EXISTS pg_stat_statements;'
env FOOTLIGHT_CONDENSER_DB_TEST=footlight_condenser_pagination_test \
  PGPORT=5433 RAILS_ENV=test bin/rails db:schema:load
env FOOTLIGHT_CONDENSER_DB_TEST=footlight_condenser_pagination_test \
  PGPORT=5433 bundle exec rails test \
  test/services/distillator/phantomjs_fetcher_test.rb \
  test/services/distillator/rendered_fetch_test.rb
```

Use the shell-compatible `FOOTLIGHT_CONDENSER_DB_TEST` override. The prior
hyphenated name is still accepted as a backward-compatible fallback, but was
observed as missing inside Rails in this worktree. Always check the resolved
Rails test database before schema loading; never target staging.
This installation is only a test environment prerequisite and does not
change migration or Artsdata export contracts.


## Renderer tests and inherited fixtures (PostgreSQL 17)

The first Rails run on the isolated `footlight_condenser_pagination_test`
database reached Minitest but failed before assertions: global fixtures in
`test/test_helper.rb` attempted to insert `properties.rdfs_class_id=980190962`
before its referenced `rdfs_classes` row was available. PostgreSQL reports
`PG::ForeignKeyViolation` during `ActiveRecord::FixtureSet.insert`.
Mocha's `undefined method 'pop' for nil` teardown errors are subsequent
noise after the setup exception, not separate renderer failures.

The renderer unit tests do not use application records. Both
`PhantomjsFetcherTest` and `RenderedFetchTest` now opt out of globally
inherited fixtures via `self.fixture_table_names = []`. This is deliberately
scoped to these tests: do not disable foreign keys, elevate the application
database role, or weaken global fixtures to make these checks pass. Global
fixture referential-integrity behavior on PostgreSQL 17 remains a separate
test-infrastructure issue for DB-backed test suites.

Verify locally:

```bash
git pull --ff-only
FOOTLIGHT_CONDENSER_DB_TEST=footlight_condenser_pagination_test PGPORT=5433 \
  bundle exec rails test test/services/distillator/phantomjs_fetcher_test.rb \
  test/services/distillator/rendered_fetch_test.rb
```

Unit test execution results are **not yet verified** on the local WSL PostgreSQL
instance after this focused fix.


## Explicit rendered empty-tail candidate (read-only, opt-in)

For a site with a validated, exact empty-page message, the saved rendered
card audit can evaluate a **terminal candidate** without new paid requests.
The Chasse-galerie capture has 48 + 44 dated cards, reports 92 items on each
page, and renders a single empty-results paragraph on page 3.

\`ResourceLists::RenderedTerminalEvidence\` checks consecutive numbered-page
receipts, unchanged query filters (including repeated values), saved HTML
SHA-256 digests, native renderer/challenge flags, a bounded capture time span,
one nonempty event card per DOM child, stable numeric reported totals, card
**occurrences** (not distinct hrefs), and the exact configured empty paragraph.
A failed check is \`inconclusive\`; a pass is only \`terminal_candidate\`.

Run on the existing saved HTML without network or database calls:

\`\`\`bash
bundle exec ruby test/services/resource_lists/rendered_terminal_evidence_test.rb
RESOURCE_LIST_TERMINAL_TEXT="Il n'y a aucun événement" \
  bundle exec ruby script/resource_list_rendered_audit.rb \
  /tmp/resource-list-trials/chasse-rendered/probe.json
\`\`\`

The new \`terminal_evidence\` section in \`rendered-card-audit.json\` includes
errors, card count, reported total, receipt digest, and
\`verified_completeness: false\`. No terminal inference runs unless the exact
site-specific text is explicitly supplied. Observed request URLs do **not**
prove that the server actually applied the category filters.

**Do not feed this result into \`PaginationCaptureProof\` as
\`verified_no_next_link\`.** That class requires an observed next-link chain,
which AJAX pagination does not supply. A later explicit adapter needs separate
pagination-transition provenance and selected Source/identity validation.
Maintain the last-good ResourceList on any uncertainty; never archive from
this diagnostic or the short-page heuristic.


## Chasse-galerie category-filtered AJAX POST: offline candidate (2026-11-27)

The user verified the site's unauthenticated \`multipart/form-data\` POST to
\`/fetch-front-end-events\` with \`reference_id\`, \`filters[categ]\`,
\`current_page\`, \`number_items_per_page\`, and \`action=null\`. The returned
JSON contains \`count\`, \`current_page\`, \`max\`, \`url\`, and \`html\`.
The calendar's plain GET correctly selects a category but initially returns
an empty AJAX shell; a GET to the AJAX endpoint returns HTML rather than JSON.

Observed live results:
- **Jeunesse**, page size 1: 1 / 1 / 0 cards on pages 1 / 2 / 3.
  Page 1 was \`les-voisines\`, page 2 \`l-expedition-de-la-rythmobile\`;
  page 3 supplied the exact empty message \`Il n'y a aucun événement\`.
- **Prestige**, page size 10: 10 / 10 / 8 / 0 cards on pages 1–4,
  all 28 nonempty cards labeled Prestige. A separate supplied JSON
  response with page size 48 contained 28 distinct event URLs.
  The available outputs corroborate *counts*, but the 10+10+8 URLs
  were not independently saved and compared against the 48-item response.
- \`max\` was consistently 2 for Jeunesse and 27 for Prestige. Its meaning
  is **unknown**; do not use it as an authoritative total or last page.

\`ResourceLists::AjaxPaginationEvidence\` independently checks **saved**
request/response receipts: method, endpoint and invariant multipart fields;
status/JSON content type; actual JSON page, card count, category label,
site-scoped event links, server URL template and immutable selected filters;
adjacent repeated nonempty HTML, explicit empty terminal message, bounded page
count, optional separate expected card total, and capture-time skew. It only
returns \`terminal_candidate\` or \`inconclusive\`; it does **not** declare
complete ResourceList discovery or authorize deletions, archivals or exports.
An event URL can occur on multiple dated cards without being counted as lost.

Fixture provenance matters: \`test/fixtures/resource_lists/chasse_galerie_ajax_observations.json\`
records the observed page summaries and the 28 URLs from the original single
Prestige response. The regression test constructs **minimal synthetic
page-specific JSON/HTML** from these observations; these are **not saved raw
HTTP responses for each page**. The positive tests verify the validator's
invariants, not independent network provenance or actual source completeness.
To move beyond this, save the raw response body and status/header metadata for
each live page separately (without cookies or credentials) and replay those.

Run the standalone tests using the app's Nokogiri dependency:

\`\`\`bash
bundle exec ruby test/services/resource_lists/ajax_pagination_evidence_test.rb
\`\`\`

This is read-only and offline. No POST fetcher, DB writes, scheduling,
ResourceList source changes, RDF minting or Artsdata export logic were added.
Do **not** pass AJAX evidence as \`verified_no_next_link\` to the anchor-chain
\`PaginationCaptureProof\`; an AJAX transition requires its own proof path.


## Co-Motion contradictory pager / short-page diagnostic (2026-11-27)

The user ran the bounded Co-Motion probe on `?page=1` and obtained HTTP 200 on
pages 1–10. Page 9 reported 106 total HTML links and **no matching next-page
link**, yet page 10 was fetchable; page 10 had 89 links (84% of page 9) and
**did expose a matching page-11 link**. The old probe stopped at page 10 on
`heuristic_short_page`. This is **not** evidence that page 10 is terminal.

The numbered probe now records short pages as advisory only by default,
retains `short_page_stop` as the historical diagnostic field name, and records
`numbered_link_urls` in each saved receipt so exact hrefs can be inspected.
The explicit opt-in `RESOURCE_LIST_PROBE_STOP_ON_SHORT_PAGE=1` is for legacy
trials only and cannot override `next_link_observed=true`. Stops for challenge,
AJAX shell and repeated body/link inventory remain inconclusive. A page cap
still terminates read-only diagnostics without proving completeness.

To rerun at most 13 read-only requests (no database writes):

```bash
bundle exec ruby script/resource_list_numbered_probe.rb \
  'https://co-motion.ca/spectacles/?page=1' 13 \
  /tmp/resource-list-trials/co-motion-continued
jq '.captures[] | select(.page == 9 or .page == 10 or .page == 11) |
    {page, next_link_observed, numbered_link_urls, short_page_stop}' \
  /tmp/resource-list-trials/co-motion-continued/probe.json
```

The missing page-10 link on page 9 needs HTML pager inspection; `next_link_observed=false`
alone is not an authoritative terminal signal. No ResourceList page creation,
retirement, event archiving, or publishing is authorized by this trial.
