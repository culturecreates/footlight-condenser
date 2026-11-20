# Replay production exports through staging DSL

This is an end-to-end regression investigation, not an activation gate. The old
result is a dated production Databus export. The new result is generated from
selected staging sources and cached Wringer HTML/JSON. It does not compare two
fetch backends through the same DSL engine.

## Pilot in staging Rails console

Deploy the `harden-dsl-reliability` branch to staging first. No migration is needed.
Then:

```sh
heroku run rails console --app footlight-condenser-test
```

```ruby
load Rails.root.join("script/databus_replay.rb")
report = Distillator::DatabusReplay.call(manifest: "/path/to/manifest.json", sites: ["co-motion-ca"], per_site: 1)
puts JSON.pretty_generate(Distillator::DatabusReplay.summary(report))
```

Once the pilot is understood, run up to 20 pages for each site in the manifest:

```ruby
report = Distillator::DatabusReplay.call(manifest: "/path/to/manifest.json", per_site: 20)
puts JSON.pretty_generate(Distillator::DatabusReplay.summary(report))
```

Sampling is deterministic and evenly spread through sorted event source URLs.
A site with fewer than 20 URLs uses all available URLs. Use `historical: true`
instead of `manifest:` to rerun the original November 7–8 pilot explicitly.

The script accepts Legacy and Shadow sites. It requires matching staging webpage
records, resolves ordinary event and nested-property sources, and executes only
selected sources. The manifest pins the Wringer URL independently of the rollout
and compatibility endpoint settings. A Shadow replay uses that Wringer cache.
The report records the manifest and export SHA-256 and the Wringer URL.

## Capture the baseline

Download each dated, published Databus JSON-LD export once. Keep its exact bytes
alongside the manifest and compute SHA-256. The optional `production_sources`
file contains a JSON array of selected source versions with IDs, algorithm hashes
and relevant settings, captured with authorized production access. Omitted
production source evidence is reported as missing for that site.

Example manifest with placeholder checksums:

```json
{
  "captured_at": "2026-11-20T12:00:00Z",
  "wringer_url": "https://footlight-wringer-staging-a876afe2e40f.herokuapp.com",
  "exports": {
    "co-motion-ca": {
      "date": "2026-11-19",
      "url": "https://data.culturecreates.com/databus/culture-creates/footlight/co-motion-ca/2026-11-19/co-motion-ca.json",
      "file": "co-motion-ca.json",
      "sha256": "<export checksum>",
      "production_sources": {
        "file": "co-motion-ca-source-versions.json",
        "sha256": "<source snapshot checksum>",
        "captured_at": "2026-11-20T11:55:00Z"
      }
    }
  },
  "api_inputs": {}
}
```

Capture times describe when evidence was collected. Treat an export, source
snapshot, API snapshot and restored cache as contemporaneous only when their
provenance establishes that. The replay copies the manifest and verified export
bytes into the report and records the cache times and hashes observed during
execution.

## What is and is not regenerated

Every selected DSL is executed using the new runner, then passed through current
datatype formatting and reconciliation. The script constructs unsaved statements
from these new results and runs the existing Artsdata graph builder, Contact/Offer/
Event-series transformations, Footlight enrichment and annotation removal.

Existing statement caches are never substituted for failed or empty extraction.
Source algorithms, settings and raw/formatted results are recorded for diagnosis.
Existing manual corrections are flagged; their cached values are not substituted
for the DSL result. Successful values have an explicit `updated` preview status
so the graph tests serialization of new results. This is not a replay of human
approval, statement-save callbacks or the publication eligibility workflow.

PostgreSQL runs in a read-only transaction, which is rolled back. Accidental SQL
writes fail. Each site has a savepoint so a failed site cannot strand the others.
The script neither saves statements nor queues publication, promotes sites, or
uploads to Artsdata. Outputs are local files only.

## Cache behavior

The reader first looks up an exact existing successful Wringer record. Missing or
failed entries are reported, never requested as new source URLs. Body hydration
uses `/websites/wring.json` without force/expiry/rendering/POST flags; cache ID,
URI, refresh time, update time and HTTP code are checked again afterwards.

Wringer currently lacks an atomic read-only body endpoint. A concurrent deletion
between inspection and hydration could make `/wring` retrieve the page; any
resulting version change is rejected as incomplete evidence. This is a limitation
of the existing API, not an absolute server-side no-fetch guarantee.

Secondary URL, rendering, JSON and POST navigation instructions read the same
URL-keyed cache; no rendering or live POST is initiated. Raw DSL `HTTParty.get`
calls also read cache. Request bodies and unsupported direct network calls are
reported as missing inputs. This can expose uncached ticketing endpoints in
complex pricing DSLs; those cases are incomplete, not extraction regressions.

Secondary HTTP cache lookups preserve the request URI using HTTParty's URI
builder. Existing query spelling, duplicate parameters and escapes remain
intact; additional query options are appended as HTTParty would send them.
The subsequent remote-cache lookup follows Wringer's historical key algorithm:
decode the target once with `CGI.unescape`, then build and escape the stored key.
This is separate from native Distillator cache keys. Sending the original target
for body hydration prevents a second decode of reserved characters. Input
evidence records the requested URL, canonical URL and exact stored cache key.

Formatting/reconciliation and RDF entity enrichment run outside the raw-DSL
network guard and can make their normal read-only lookups. Reconciliation HTTP
responses are reused within the run. They are current observations, not historical
production inputs. Their drift must be reviewed separately.

Reconciliation also treats spaced ` - ` separators as possible organization /
venue aliases. Internal hyphens in names such as `Trois-Rivières` and
`Denise-Pelletier` do not introduce an alias: matching only `Rivières` or
`Pelletier` would incorrectly turn unrelated suggestions into published links.
The recorded Partytime candidate names/identities are a regression fixture;
with its one extracted venue, formatting retains only Le Memphis Cabaret and
the six-date EventSeries can be generated. Existing multi-venue extraction via
full names or spaced hierarchy separators remains supported.

## Explicit API dependencies

Some `api=` sources read another Condenser site's resource-list statements,
rather than fetching a source webpage through Wringer. For example, Culture
Mauricie source 7885 reads category mappings from its `-RList` site. Those
responses need not exist in Wringer. An uncaptured dependency remains incomplete;
the replay never silently fetches it live or substitutes staging statement data.

Capture the production API response explicitly and save its raw JSON beside
the manifest. Use the exact URL the staging DSL will request as the
`api_inputs` key. To supply a production observation to a staging
`$$SELF_URL$$` request, give the exact staging URL and describe the substitution
in `provenance`.

```json
{
  "https://footlight-condenser.herokuapp.com/statements.json?prop=121&seedurl=culturemauricie_lepointdevente-com-RList": {
    "file": "mauricie-category.json",
    "sha256": "<API body checksum>",
    "captured_at": "2026-11-20T11:55:00Z",
    "provenance": "Production Condenser category mapping, captured after the export"
  }
}
```

The explicitly supplied JSON is copied and reused for GETs to that exact request
URL throughout the run. Different parameters still require their own snapshot or
an existing Wringer cache entry. HTML navigation continues to use Wringer. No
stored source algorithm changes, and no synthetic category mapping is created.

Used API snapshots appear separately in `api_inputs` in the report and console
summary, with capture time, provenance, byte count and SHA-256. Their exact bodies
are saved alongside Wringer inputs in `cache-inputs.json` as base64. A snapshot
captured today is not evidence that the API returned identical data on the dated
export's day; review resource-list changes independently. Supplied snapshots must
contain valid JSON, an ISO-8601 capture time and non-empty provenance.

Missing keys inside a successfully captured mapping remain the DSL's ordinary
results. Source 7885 returns `Key '...' not found in any category` for such keys;
this is a category-coverage issue, distinct from a missing replay input or an
execution failure. The replay preserves that behavior for comparison.

## Reading the result

- `equivalent_event_data`: sampled RDF matches after ignoring only
  `schema:lastReviewed`, which changes with refresh time. Exact timestamp
  differences remain in the report and graph files.
- `differences_need_review`: complete extraction produced different RDF. This is
  not automatically a code regression: inspect historical input changes, source
  changes, manual corrections and reconciliation before assigning a cause.
- `incomplete`: missing webpage/cache, execution/formatting/export failure, or
  another input problem. A partial graph is never reported as proof of parity.

If EventSeries conversion cannot align multiple location values with start
dates, it raises `JsonldGenerator::EventSeriesConversionError` with the event URI
and start-date, end-date and location counts. Normal export stops before upload.
The replay records this as an `export`-layer error against each affected webpage
and retains other pages' RDF for diagnosis. The site's result remains incomplete;
the resulting partial graph is a diagnostic preview. A failed transformation
does not silently count as an equivalent empty event.

Graphs are compared using RDF blank-node canonicalization, preserving all actual
event literals, types, language tags, ordering represented as RDF positions and
URIs. The expected graph includes the sampled Event/EventSeries roots and their
outgoing referenced nodes, including performances, prices, webpages and locations.

The report directory contains the exact production JSON, expected and actual
N-Quads, differences, source definitions, extraction results, and base64-encoded
Wringer bodies with timestamps and SHA-256 hashes. Files on a Heroku one-off dyno
are ephemeral: print the summary while the console remains open, and retain any
detailed evidence you need before ending that session.

The known historical source is the production export, not a freshly executed
production DSL baseline. A clean result demonstrates equivalent output for the
sample. A difference needs diagnosis, and the frozen historical-evaluator tests
remain the independent way to isolate DSL semantics.
