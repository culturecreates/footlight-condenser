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
