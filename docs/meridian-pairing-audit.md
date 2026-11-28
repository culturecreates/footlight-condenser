# Meridian bilingual pairing — bounded read-only audit

**Branch:** `feat/keyed-resource-list-alignment` (draft PR #14). This audit
does **not** update Webpages, Statements, RDF identities, refresh jobs,
Wringer/Condenser caches, scheduling, or Artsdata exports.

## What the audit can and cannot prove

The existing Meridian ResourceList mapping has EN
`/en/events?page=N` and FR `/fr/evenements?page=N`, numbered from zero.
The original proof of concept sampled pages 0 and 1 in each language.
Those four URLs alone are **not** a complete inventory: an indexed historical
FR page-1 snapshot showed numbered pagination through page 6 (index 5).

`script/meridian_live_pagination_audit.rb` now validates HTML content before
using the site's **selected** Webpage URL List Source XPath. An HTTP-200
anti-bot interstitial is a blocked fetch, not an empty calendar. It uses the
generic `Distillator::PageEvidence` and a lightweight calendar identity/DOM
check; URLs are still extracted by the currently selected Source XPath,
**not** by executing its Ruby/URL DSL steps.

The report matches already-known EN/FR Webpage URLs using the **selected website's existing RDF identities** (original or QA copy). This is a trustworthy way to compare
pairs on different calendar pages. New/unmapped URLs are reported, not minted
or guessed into bilingual pairs. A complete new-event pairing algorithm,
stable site-specific key and reconciliation/archival policy remain separate work.

## Commands (local staging working database only)

Reuse the configured `bin/condenser` wrapper, local socket, and port 5433.
No test DB recreation or reset is required. The audit refuses production
and accepts only an explicitly recognized local staging working or QA DB.

```bash
# Snapshot the original's stored RL pairing/inventory without external fetches
bin/condenser --db footlight_condenser_staging_work --rails-env development \
  runner script/meridian_resource_list_baseline_audit.rb --json /tmp/meridian-baseline.json

# Inspect selected Source IDs and currently configured RL pages
bin/condenser --db footlight_condenser_staging_work --rails-env development \
  runner script/meridian_resource_list_preflight.rb --json /tmp/meridian-preflight.json

# QA pairing: use the copied site's selected Sources, not the original
# site's render_js setting. Does not change either site's Sources.
bin/condenser --db footlight_condenser_staging_work --rails-env development \
  runner script/meridian_live_pagination_audit.rb --qa-copy --full \
  --json /tmp/meridian-qa-full.json

# Optional comparison against the original configured Sources (separate
# report; it may require a renderer because the original has render_js=true):
bin/condenser --db footlight_condenser_staging_work --rails-env development \
  runner script/meridian_live_pagination_audit.rb --full \
  --json /tmp/meridian-original-full.json
```

Do not overwrite existing report files; choose different filenames for
subsequent runs.

The `--qa-copy` option requires **exactly one** unscheduled Meridian
copy associated with the original `meridiancentrepointe-com`; its Sources
and Webpage/RDF ownership are used throughout the audit. The original
remains unchanged. The audit reads each selected URL Source's `render_js`
flag: false uses HTTP-only fetching, true uses the existing guarded native
rendering pipeline without writing to the cache. A rendered-fetch failure
is reported, not silently retried through static HTTP or Wringer.

If either page returns an Imperva or unknown challenge, or if the first
page does not expose an explicit last-page link, the full mode fails closed.
It never assumes a terminal page from the absence of results, links, or a
next button. Actual page counts are discovered independently for EN and FR;
different page counts and cross-page matches are expected possibilities.

### For intermittent anti-bot blocking

An operator can collect the *same time window* HTML from all four sampled
URLs and use an optional four-page replay (not full pagination proof):

```bash
bin/condenser --db footlight_condenser_staging_work --rails-env development \
  runner script/meridian_live_pagination_audit.rb \
  --html en:0:/tmp/meridian-en0.html --html en:1:/tmp/meridian-en1.html \
  --html fr:0:/tmp/meridian-fr0.html --html fr:1:/tmp/meridian-fr1.html \
  --json /tmp/meridian-replay.json
```

This is **operator-supplied input**, not proof that the live network fetch
worked. The current snapshot cannot be proved contemporaneous from its
filename alone. The audit records only sample-page pairing and keeps
`inventory_authoritative: false`.

## Acceptance before any write/import

- All live pages discovered from explicit terminal-page evidence for both
  languages; no challenge, missing page, invalid redirect, or invalid XPath
  extraction in any part of the capture.
- Report cross-page existing RDF pairs; investigate unmapped event URLs,
  unmatched existing identities and repeated URLs.
- Compare with the original ResourceList baseline and chosen QA-copy
  namespace; existing paired RDF IDs must remain stable.
- A safe new-event key and deterministic URI minting policy, including cases
  with different EN/FR slugs, must pass separate migration parity tests.
- No scheduling, archival, publishing or authoritative discovery without
  complete validation and explicit user authorization.

## Focused unit tests (verified locally only after the user runs them)

```bash
bin/condenser --db footlight_condenser_keyed_qa_test --rails-env test test \
  test/services/resource_lists/meridian_page_validation_test.rb \
  test/services/resource_lists/meridian_pager_test.rb \
  test/services/resource_lists/meridian_rendered_page_test.rb
```

**Verification status:** changes committed to draft PR. Local Ruby and
PostgreSQL test execution has not yet been reported for these new files.
The earlier passing 62-test/874-assertion suite predates this audit change.

**2026-11-28 correction:** the first audit run stopped on original RL #10684 because its selected Source has `render_js=true`. The operator had set `render_js=false` **only on the QA copy**. Use `--qa-copy` for pairing validation. The first attempt did not fetch pages or establish parity. The corrected path and renderer tests await local execution.

## Single-page resume after HTTP-200 Imperva challenge (2026-11-28)

The first QA-copy full audit (database `footlight_condenser_dansedanse_qa`,
website #585) inspected all EN pages 0–2, FR pages 0–1 and rejected FR
page 2 as an Imperva challenge. **This was correct safety behavior.** Its
partial diagnostic counted 25 unique EN URLs, 24 unique FR URLs, 22
existing bilingual RDF identities, 3 cross-page identities, 4 unmapped
URLs and 1 unmatched existing identity. Those latter anomalies are only
provisional until FR page 2 is validated.

To avoid refetching the five successful pages, the audit supports a bounded
resume from the saved JSON report, without reusing rejected content:

```bash
bin/condenser --db footlight_condenser_dansedanse_qa --rails-env development \
  runner script/meridian_live_pagination_audit.rb --qa-copy --full \
  --resume /tmp/meridian-qa-full.json \
  --json /tmp/meridian-qa-full-resumed.json
```

The resume requires a report no more than **30 minutes old**, the exact
database and QA-copy Website identity, matching EN/FR selected Source IDs,
XPath DSL digests and rendering flags, unchanged page URLs, and fresh
verified HTML receipts. Blocked pages cannot be reused. It retries the
missing page(s), recomputes all pairing metrics and records the original
JSON's SHA-256 as provenance. If any check fails, start a new full audit
rather than weakening the evidence.

A resumed run uses captured URLs from two moments, so it **does not prove
atomic inventory** even when both language pagers have valid terminal
receipts. It remains read-only and diagnostic; a successful resume does
not authorize unattended imports, deletion, archival or new RDF minting.

Focused regression:
```bash
bin/condenser --db footlight_condenser_keyed_qa_test --rails-env test test \
  test/services/resource_lists/meridian_audit_resume_test.rb \
  test/services/resource_lists/meridian_page_validation_test.rb \
  test/services/resource_lists/meridian_pager_test.rb \
  test/services/resource_lists/meridian_rendered_page_test.rb
```

**Status:** Committed to draft PR #14; this additional resume code and tests
have not been run on the user's WSL machine. No local database was changed.

## FR page 2 remains blocked on resume — diagnostic HTML option

A second resumed run still rejected `/fr/evenements?page=2` with an
HTTP-200 challenge. No new live inventory evidence was produced. The
read-only audit can now inspect **only an explicitly blocked page** using
operator-supplied HTML, with `--blocked-html` and `--resume` together.

Open `https://meridiancentrepointe.com/fr/evenements?page=2` in a normal
browser. If it displays the genuine calendar rather than the security
interstitial, save the resulting document HTML (containing the event links
and pagination markup) as `/tmp/meridian-fr2.html`. Do **not** save or
supply an Imperva page, credentials, cookies, or security tokens. Then,
if the prior report is still within 30 minutes:

```bash
bin/condenser --db footlight_condenser_dansedanse_qa --rails-env development \
  runner script/meridian_live_pagination_audit.rb --qa-copy --full \
  --resume /tmp/meridian-qa-full-resumed.json \
  --blocked-html fr:2:/tmp/meridian-fr2.html \
  --json /tmp/meridian-qa-browser-diagnostic.json
```

The audit checks that FR page 2 was genuinely blocked in the prior report
and verifies the supplied HTML with the same page-evidence, pager and
selected Source XPath validators used for network content. It preserves
page hashes, Source identity and origin metadata. All other pages must
already be valid, matching, fresh receipts.

**Never interpret this as live fetch success or verified current inventory.**
`input_mode=mixed_live_and_operator_html`, `terminal_coverage` and
`terminal_verified` are distinct; existing-pair verification remains
false when operator HTML contributes to the report. This workflow is
suitable for investigating cross-page pairs and unmapped URLs, not as
authorization for imports, archival, publishing, or production changes.

If the previous report is older than 30 minutes, run a new read-only
`--qa-copy --full` audit with a fresh JSON name first and use that
report as the resume input. No database reset is needed.

## Browser navigation yields inconsistent numbered pages (2026-11-28)

The operator captured four French HTML pages under
`/mnt/r/Downloads`:

| File | Requested URL query | Observed browser result |
|---|---|---|
| `meridian-fr1.html` | `?page=0` | full calendar |
| `meridian-fr2.html` | `?page=1` | empty calendar |
| `meridian-fr2b.html` | `?page=1` | full calendar |
| `meridian-fr3.html` | `?page=2` | one event, Scaramouch |

A separate earlier `?page=0` browser navigation also yielded an empty
calendar but was not saved. The browser labels pages 1, 2, 3 while query
numbers are 0, 1, 2 respectively.

These observations indicate possible **same-URL content instability**;
they do not by themselves identify whether the cause is server/cache state,
session-sensitive behavior, JavaScript navigation or an error response.

A new offline and DB-read-only comparison uses the QA copy's **selected
Webpage URL List Source XPath**, never the original's chosen Source or
a guessed CSS selector. It compares exact URL sets, duplicates, page
identity, content challenge markers, pager and canonical hints. The
expected file mapping is explicit and must not be inferred from filenames:

```bash
bin/condenser --db footlight_condenser_dansedanse_qa --rails-env development \
  runner script/meridian_browser_snapshots_audit.rb \
  --page fr1:0:/mnt/r/Downloads/meridian-fr1.html \
  --page fr2-empty:1:/mnt/r/Downloads/meridian-fr2.html \
  --page fr2b-full:1:/mnt/r/Downloads/meridian-fr2b.html \
  --page fr3-scaramouch:2:/mnt/r/Downloads/meridian-fr3.html \
  --json /tmp/meridian-browser-comparison.json
```

This is not the prior `--blocked-html` live-audit resume; it does not
need a fresh audit report, does not access the network and cannot declare
live inventory complete. A saved empty page is a legitimate data point
but not proof there are no events. It checks the loaded page's DOM and
selected Source XPath; if no event links are extracted from a full
browser-visible calendar, verify the saved HTML contains rendered
markup rather than a JS shell.

Review the `same_url_comparisons` and `unstable_page_numbers` first,
then compare link sets and pager labels. This must pass before treating
any single timestamped page-numbered response as authoritative
discovery/archival evidence.

Focused test:
```bash
bin/condenser --db footlight_condenser_keyed_qa_test --rails-env test test \
  test/services/resource_lists/meridian_saved_pages_comparison_test.rb
```

**Status:** tool and test committed on draft PR #14; local test and
browser-saved HTML have not yet been executed/inspected by this tool.

## Revision after comparing four actual browser-saved HTML documents

The operator's offline report showed **identical raw HTML SHA-256 digests
for two cross-page pairs**:
- `fr1` (assigned `?page=0`) and `fr2b-full` (assigned `?page=1`):
  `85baa77312fc…`, with active label **Page actuelle 1**.
- `fr2-empty` (assigned `?page=1`) and `fr3-scaramouch`
  (assigned `?page=2`): `1d19da062a40…`, with active label
  **Page actuelle 3**.

The files' *contents* did not match their assigned URL in the two
page-1 captures. They **do not demonstrate that the server returned
inconsistent bodies for the same URL**: browser history, navigation,
stale document state or saving the wrong tab could explain them.
The standalone non-browser audit separately established an HTTP-200
Imperva interstitial for FR page 2. These are distinct observations.

The comparison now reports `mismatched_active_page_labels`,
`identical_documents_across_assigned_pages` and
`inconsistent_assigned_page_numbers` rather than the misleading
`unstable_page_numbers` conclusion. Keep the regular keyed ResourceList
architecture; do not add Meridian-specific pagination handling without
repeatable **URL-bound** response evidence. A fresh HTTP capture that
records the request URL, response URL, HTML digest and extracted links
is needed to make such a claim.

**Code committed but local regression tests still need to be run.**

## QA-copy namespace and identity audit (2026-11-28)

QA copy `meridiancentrepointetest-com` yielded 60 selected URL/RDF
list positions across four ResourceLists, including 15 identifiers in the
original website namespace, all on French RL #233318; 3 URLs with mixed
original/QA namespace IDs (`hotel-california`, `cinderella-classical-arts`,
`abbamania`); and 4 not-yet-imported URL entries representing
`Solitary Man` and `Scaramouche` in English and French.

**Do not assume the 47 cached-versus-Webpage mismatch rows represent
47 wrong event pairs.** QA cloning hashes original Webpage RDF URIs;
the refreshed DSL caches contain slug-based `footlight:` CURIEs. They
are distinct URI identities even if they refer to the same named event.
A CURIE can be expanded to an HTTP URI without changing identity; a
slug-based QA URI cannot be changed into a hashed QA URI by ordinary
prefix normalization.

The read-only `MeridianCacheIdentityDiagnostics` separates exact
matches, CURIE expansions, original-vs-QA namespace contamination,
distinct QA-namespace identities, and missing Webpages. It groups
conflicts by canonical expanded RDF URI so syntax alone doesn't
inflate conflict counts. Run the QA baseline again with a new JSON name:

```bash
bin/condenser --db footlight_condenser_dansedanse_qa --rails-env development \
  runner script/meridian_resource_list_baseline_audit.rb --qa-copy \
  --json /tmp/meridian-qa-baseline-identities.json
```

And the focused regression:

```bash
bin/condenser --db footlight_condenser_keyed_qa_test --rails-env test test \
  test/services/resource_lists/meridian_cache_identity_diagnostics_test.rb
```

**Extra importer issue requiring a separate verified design:** Current
`AddWebpagesJob` QA namespace guard requires a literal absolute
`http://kg.footlight.io/resource/<copy-seedurl>_` prefix. A valid
`footlight:<copy-seedurl>_…` CURIE will fail this guard as written,
even when the seedurl is correct. This is safe fail-closed behavior,
but it means repairing the 15 original-namespace entries alone is
insufficient. Before enabling QA import, agree on canonical expansion
and stable existing QA RDF identity reuse; then add integration tests.
No production import, graph changes or Webpage corrections have been
made by these diagnostics.

## Explicit translation evidence for two missing events

The cached lists include these candidate pairs, but no shared key has been
validated:

- Solitary Man: EN `/en/solitary-man-neil-diamond-postponed` and FR
  `/fr/solitary-man-neil-diamond-REPORTE`
- Scaramouche: EN `/en/scaramouche-queen-tribute-postponed` and FR
  `/fr/scaramouche-hommage-queen-REPORTE`

RL #233317 generates QA-prefixed EN slug URIs; RL #233318 generates
original-prefixed FR slug URIs. Prefix rewriting alone would retain
different EN/FR RDF keys. Never pair or mint by translated title, page
position or language-specific slug.

A read-only event-page audit now checks for reciprocal head
`link[rel=alternate][hreflang]` pointing to the exact counterpart URL,
valid page identity, canonical links and optional Drupal `node/<id>`
shortlinks. *Reciprocal head alternates* are evidence of the translation
relationship, but the results do not authorize import or establish
live calendar completeness.

Run with ordinary independent HTTP GETs (may fail if the site blocks them):

```bash
bin/condenser --db footlight_condenser_dansedanse_qa --rails-env development \
  runner script/meridian_event_translation_audit.rb --live \
  --json /tmp/meridian-translations-live.json
```

Alternatively save the four actual event documents in the browser and pass
one `--html PAIR:LANG:PATH` for each. This is operator-supplied evidence,
not proof the server delivered the HTML under the stated URL.

Focused tests:

```bash
bin/condenser --db footlight_condenser_keyed_qa_test --rails-env test test \
  test/services/resource_lists/meridian_event_translation_evidence_test.rb
```

**Status:** Implemented on draft PR #14; the new tests and live event
fetch have not been run in the operator's WSL environment. No
database writes, imports or RDF minting were performed by this audit.

## Drupal node identity evidence from cached calendar HTML

The operator supplied the original site's cached `/en/events` HTML (scrape
2026-11-28 13:04:48 -0500). In the **main** event-listing cards,
`article.theatre-listing-teaser a[rel=bookmark]` owns
`h2#node-<id>-title`. Twelve event URLs have twelve explicit Drupal
node IDs. A separate *Featured events* section repeats three events with
`h2#featured-node-<id>-title` and explains the 15 XPath hits versus 12
unique calendar URLs. This is structural duplication, not necessarily
pagination overlap.

The corresponding Drupal node identifier across EN/FR **may provide a
stable language-independent event key** if the French card and both event
documents confirm the same ID. The individual event pages also expose
Drupal settings JSON `path.currentPath = node/<id>` on this site
(the cached calendar itself has `node/8`, which identifies the calendar
page, not an event).

The read-only translation audit now extracts `drupal_node_id` from event
page settings. When both documents have the same node ID and reciprocal
`hreflang`, it reports `verified_shared_key=drupal-node:<id>`. When
explicit node IDs conflict, the verification is blocked; if neither node
ID is present, reciprocal translation evidence remains separately
verified but `verified_shared_key` remains null.

Re-run the focused test and event audit using new output filename:

```bash
bin/condenser --db footlight_condenser_keyed_qa_test --rails-env test test \
  test/services/resource_lists/meridian_event_translation_evidence_test.rb

bin/condenser --db footlight_condenser_dansedanse_qa --rails-env development \
  runner script/meridian_event_translation_audit.rb --live \
  --json /tmp/meridian-translations-node-evidence.json
```

**Not yet verified locally:** updated test and live node evidence. No
discovery import or RDF minting is performed; existing QA RDF identities
remain untouched.
