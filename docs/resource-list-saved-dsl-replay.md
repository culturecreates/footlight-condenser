# Saved ResourceList DSL replay (read-only QA)

**Purpose:** Replay an existing **selected** ResourceList "Webpage URL List" or
"URI List" Source algorithm against the already-captured, SHA-verified HTML
from PR #15. This does **not** introduce a pagination-specific XPath or
change the configured DSL. The replay is not an import, a database refresh,
an Artsdata parity certification, or evidence for archiving.

## Requirements

- Local **development or test** Rails environment, using a disposable
  PostgreSQL database; it can be **empty** when using an exported Source
  JSON file. Do not run against staging or production.
- A previously saved `probe.json`, matching `pageN.html` files and
  `semantic-next-audit.json` in the same directory.
- The ID of the existing selected Source whose Property label is
  "Webpage URL List" or "URI List". Do **not** substitute a handcrafted
  XPath for the configured algorithm. The IDs are database-specific.
- The Source algorithm must be trusted; DSL `ruby=` may evaluate arbitrary
  Ruby and **this script is not an OS/file-system sandbox**.

For example, inspect selected ResourceList list Source IDs on the local
development database (read-only):

```bash
RAILS_ENV=development bundle exec rails runner \
  'Source.includes(:property, :website).where(selected: true).each { |s|
    puts "#{s.id} website=#{s.website.seedurl} label=#{s.property.label}" if
      ["Webpage URL List", "URI List"].include?(s.property.label) &&
      s.website.seedurl.include?("shawinigan")
  }'
```

Run the local tests, then replay **each appropriate existing Source**
against the saved unfiltered and culture-filtered sequences:

```bash
bundle exec ruby test/services/resource_lists/saved_dsl_replay_test.rb

RAILS_ENV=development bundle exec ruby \
  script/resource_list_existing_dsl_replay.rb \
  /tmp/resource-list-trials/shawinigan-culture SOURCE_ID

RAILS_ENV=development bundle exec ruby \
  script/resource_list_existing_dsl_replay.rb \
  /tmp/resource-list-trials/shawinigan-numbered SOURCE_ID
```

Replace `SOURCE_ID` with a selected Source ID. If URL and URI list
Sources differ, run each independently with its own ID. Do **not**
claim the eventual URL/URI pairing is consistent before both are checked.
If a Source is not present in the disposable DB, **do not guess** its DSL.

The runner invokes `Dsl::Core::AlgorithmRunner#run` with
`snapshot_html:` for each saved page, using the configured Source
`algorithm_value`. It blocks HTTP with WebMock, replaces the DSL's
secondary fetch method with an explicit `FetchUnsupported` abort,
and executes within a PostgreSQL read-only transaction that is rolled
back. This reduces unintended external effects but **does not sandbox
arbitrary Ruby filesystem/process operations**. It records raw DSL arrays
without changing their format or re-implementing event extraction.

The pure audit first verifies page order, filter identity, snapshot
SHA-256, semantic Next-link transitions and first terminal candidate.
It replays only the candidate valid pages, ignoring out-of-range probe
pages after the first terminal. Blank output, aborts, broken navigation
and modified snapshots fail **inconclusive**. A successful replay reports
`status=dsl_replayed_parity_unverified`, never `complete=true`.

Output:
`dsl-snapshot-replay-source-SOURCE_ID.json` in the saved probe directory,
with per-page raw values, counts, digests, duplicate-value diagnostics
and terminal candidate. Note that duplicate raw values may be an
expected DSL feature, not necessarily an error.

## Still required for migration

- Confirm the Source was selected on the relevant ResourceList Webpage.
- Compare the raw per-page outputs and formatted URL/URI list pairings
  against last-good Statement caches, source configuration and
  Artsdata/Databus identity invariants.
- Investigate any secondary-fetch DSL logic separately using supported
  recorded fetch fixtures; **never silently replace** the missing fetch
  with fresh network data or a synthetic XPath extraction.
- Keep PR #15 draft and production ResourceList/import/archive code
  unchanged until these checks and full integration tests pass.

## Replay using real exported Sources 9098 and 9102 (Shawinigan)

The staging snapshot has the selected original `URI List` Source 9098 and
`Webpage URL List` Source 9102, shared across the four configured unfiltered
ResourceLists. The local development database has zero Sources and is used
only for its read-only transaction guard. This command does **not** create
Source records, import data or change the DSL.

Export each Source from the **local snapshot database** using read-only SQL:

```bash
mkdir -p /tmp/resource-list-trials/shawinigan-sources
for id in 9098 9102; do
  PGOPTIONS='-c default_transaction_read_only=on' \
  psql -X -At -v ON_ERROR_STOP=1 \
    -d footlight_condenser_staging_snapshot \
    -c "SELECT json_build_object(
      'source_id', s.id, 'website_id', s.website_id,
      'website_seedurl', w.seedurl,
      'property_label', p.label, 'selected', s.selected,
      'render_js', s.render_js, 'algorithm_value', s.algorithm_value
    )::text
    FROM sources s
    JOIN properties p ON p.id = s.property_id
    JOIN websites w ON w.id = s.website_id
    WHERE s.id = ${id} AND s.selected = true
      AND w.seedurl = 'tourismeshawinigan-com'
      AND p.label IN ('URI List', 'Webpage URL List')" \
    > "/tmp/resource-list-trials/shawinigan-sources/source-${id}.json" || exit 1
  test -s "/tmp/resource-list-trials/shawinigan-sources/source-${id}.json" || exit 1
done
```

Run the fixture validator and both selected-source replays (development only):

```bash
bundle exec ruby test/services/resource_lists/replay_source_config_test.rb
for selection in shawinigan-numbered shawinigan-culture; do
  for id in 9098 9102; do
    RAILS_ENV=development bundle exec ruby \
      script/resource_list_existing_dsl_replay.rb \
      "/tmp/resource-list-trials/${selection}" \
      "/tmp/resource-list-trials/shawinigan-sources/source-${id}.json" || exit 1
  done
done
```

Export files are private local QA inputs and must not be committed.
Report status remains `dsl_replayed_parity_unverified`; verify URL/URI
pairing and compare with last-good statements separately.
Existing source configuration is trusted input; `ruby=` expressions are
not process- or filesystem-sandboxed. Do not point the runner to staging.

## Actual Shawinigan DSL replay observations (2026-11-27)

The operator replayed both **original** selected Source algorithms (9098 for
URI List, 9102 for Webpage URL List) on the SHA-verified local captures.
Every invocation reported `dsl_replayed_parity_unverified`:

| Selected calendar | Source outputs | Occurrences | Repeated occurrences | Unique values | Terminal candidate |
|---|---|---:|---:|---:|---:|
| Unfiltered | 9098 and 9102 | 86 each | 35 each | 51 each | 11 |
| Culture | 9098 and 9102 | 72 each | 27 each | 45 each | 9 |

These are **per-chain** unique raw values, not a proven count of missing Event
Webpages. The snapshot has 31 Event webpages but was captured at a different
time and only has configured ResourceLists for unfiltered pages 1–4.
URL/URI positional pairing, Source cache baselines, and Artsdata parity remain
separate evidence gates. Equal counts and duplicate totals alone do not certify
pairing correctness.

To check **every URL/URI pair in its original DSL array position**, without
re-extracting HTML, fetches, database connections or any new XPath:

```bash
bundle exec ruby test/services/resource_lists/saved_dsl_pair_parity_test.rb
for selection in shawinigan-numbered shawinigan-culture; do
  bundle exec ruby script/resource_list_saved_dsl_pair_audit.rb \
    "/tmp/resource-list-trials/${selection}" || exit 1
done
```

The pairing audit checks the existing Shawinigan URI naming contract,
matching page/Source identity, value digests, duplicates and pair ordering.
A `url_uri_pairing_verified_last_good_unverified` result certifies only
**local pairing of recorded DSL outputs**. It does not establish pagination
completeness, last-good Statement-cache parity, or Artsdata/Databus invariants.

## Production Webpages inventory compared with the unfiltered replay

A separately supplied production Webpages listing for `tourismeshawinigan-com`
contains **48 Event webpages**, **4 ResourceLists** (pages 1–4), and
historical Place/EventType records. The earlier local **staging snapshot**
contained **31 Event webpages**; these are different snapshots, not an
authoritative before/after delta.

An operator ran a **read-only exact URL-set comparison** of the production
listing with the unfiltered saved-HTML Source replays
(`9102` URL List, `9098` URI List). Results:

| Set | Unique URLs |
|---|---:|
| Replayed unfiltered calendar (86 occurrences, 35 duplicates) | **51** |
| Production Event webpages | **48** |
| Exact URL matches | **25** |
| Replay-only discovery candidates | **26** |
| Production-only historical/unlisted records | **23** |

**Crucial location evidence:** Of 26 replay-only candidates, **25 appear
on calendar pages 5–11**, outside production's four configured ResourceList
pages. The **one candidate on page 4** is
`https://www.tourismeshawinigan.com/evenements/emilie-perreault-theatre/`.
It requires separate investigation of refresh/import timing and existing
Source Statement state; adding pagination does not explain it.

The 23 production-only Event webpages have supplied `archive_date` values
**no later than 2026-11-26**, preceding the current capture. Their absence
from a current calendar is consistent with normal historical retention,
**not** evidence for deletion or forced archiving. A production `Publishable`
flag alone is not evidence that the event is currently active.

For the **25 exact URL overlaps**, the supplied comparator reported **zero
RDF identifier mismatches**. This confirms compatibility on existing
identities, but not the untouched 26 replay-only candidate identities, nor
full positional URL/URI pairing. Run
`script/resource_list_saved_dsl_pair_audit.rb` on both saved chains
before calling pairing verified.

**Interpretation:** The fixed production page-1–4 inventory is strongly
associated with substantial current-event discovery undercoverage;
the evidence does **not** imply that 26 events should be immediately
imported or that 23 historical pages should be removed. Source pages,
calendar contents, snapshot dates and event archive dates are distinct
dimensions. Compare against *contemporaneous* last-good statements,
then verify URL/URI pairing and Artsdata/Databus identity invariants
before any production collector/refresh changes.

The production listing and the replay are user-supplied local evidence;
PR #15 remains **read-only and draft**. This section records observations
only and does not create a Source, add page URLs, schedule refreshes, import
Events, change archive dates, or modify Artsdata exports.
