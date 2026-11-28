# Saved ResourceList DSL replay (read-only QA)

**Purpose:** Replay an existing **selected** ResourceList "Webpage URL List" or
"URI List" Source algorithm against the already-captured, SHA-verified HTML
from PR #15. This does **not** introduce a pagination-specific XPath or
change the configured DSL. The replay is not an import, a database refresh,
an Artsdata parity certification, or evidence for archiving.

## Requirements

- Local **development or test** Rails environment, using a disposable
  PostgreSQL database containing the **actual** Shawinigan Source
  configuration. Do not run this against staging or production.
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
