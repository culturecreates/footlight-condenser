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
report = Distillator::DatabusReplay.call(sites: ["co-motion-ca"], per_site: 1)
puts JSON.pretty_generate(Distillator::DatabusReplay.summary(report))
```

Once the pilot is understood, run up to 20 pages for each of the seven sites:

```ruby
report = Distillator::DatabusReplay.call(per_site: 20)
puts JSON.pretty_generate(Distillator::DatabusReplay.summary(report))
```

The defaults use November 7, 2026 for co-motion, Culture3R, Place des Arts,
Culture Mauricie/lepointdevente, Gatineau and Maison de la culture. Tourisme des
Chenaux uses November 8. Sampling is deterministic and evenly spread through
sorted event source URLs. A site with fewer than 20 URLs uses all available URLs.

The script accepts Legacy and Shadow sites. It does not change
rollout settings. It requires matching existing staging webpage records, resolves
the usual event/nested-property source scope, and executes only selected sources.

Inputs are pinned to `https://footlight-wringer.herokuapp.com`, independently of
Condenser's rollout and compatibility endpoint settings. Shadow sites do not
trigger a native Condenser fetch or a shadow pair. The report records
`input_backend: remote_wringer_cache` and the credential-free Wringer URL.
An explicit `wringer_url:` can select another Wringer deployment if needed.

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

## Reading the result

- `equivalent_event_data`: sampled RDF matches after ignoring only
  `schema:lastReviewed`, which changes with refresh time. Exact timestamp
  differences remain in the report and graph files.
- `differences_need_review`: complete extraction produced different RDF. This is
  not automatically a code regression: inspect historical input changes, source
  changes, manual corrections and reconciliation before assigning a cause.
- `incomplete`: missing webpage/cache, execution/formatting/export failure, or
  another input problem. A partial graph is never reported as proof of parity.

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
