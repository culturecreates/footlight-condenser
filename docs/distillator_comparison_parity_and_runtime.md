# Transition comparison: data, reliability and diagnostics

Transition checks validate selected extracted values, required-field coverage and
export serialization. Cache diagnostics support this decision; they are not a
requirement to reproduce Wringer's monitoring limitations.

**Transition context** is a native details/summary infobox, closed on each page by
default. Its summary gives mode and active backend; expansion shows website
identity, the latest recorded check state and up to three transition-specific
links. It does not calculate readiness, fetch cache diagnostics or render action
forms. The website page owns operations; the pinned report owns evidence and
decisions. A completed background job is labeled Completed, never Passed without
examining its comparison report.

| Observation | Treatment |
| --- | --- |
| Wringer lacks HTTP, content or transport telemetry; Condenser records a healthy value | Additional Condenser diagnostics; no review requirement |
| Different hashes or HTML byte counts, with the same selected extracted values | Keep the raw difference as diagnostics; no automatic parity failure from hashes |
| Different real document titles | Keep the existing title safety blocker |
| Different known final destinations | Review in operator cache policy; block in strict cache policy |
| A redirect is newly observed without a legacy destination baseline | Additional diagnostics; actual unsafe content/fetch failures still block |
| Explicit failed transport/content, HTTP failure, empty HTML or blocking issue | Independent fetch safety failure, including when Wringer reports the same failure |
| Selected values differ | Core differences block Standard; all selected differences block Strict |
| Missing snapshots, source coverage, required values or interrupted comparison | Incomplete/failed evidence cannot authorize activation |

Strict field comparison and the cache diagnostic policy are separate settings.
Neither requires identical diagnostic metadata. A passing cache comparison alone
never establishes statement or export parity. Existing evidence and accepted
rollout history are not rewritten; run a new check to use the corrected policy.

The report presents one decision and next step, with the completed run's **Data
field comparison: Standard/Strict** beside its ID. The separate **Cache diagnostics
policy** is labeled **Review known destination changes** or **Block known
destination changes**, including on the cache-comparison page. The existing API
values `operator` and `strict` are retained for links and stored evidence.

Benign diagnostic notes do not reduce evidence confidence. Missing, stale,
incomplete or review-needed evidence still lowers confidence as before; optional
statement differences retain Medium confidence. Confidence describes the evidence,
not a separate activation decision. Blocking checks and warnings always take
priority over a promotion recommendation, even when diagnostic notes are present.

Redundant per-row diagnostic captions, duplicate cache links and a repeated export
URL are suppressed in presentation. The underlying diagnostics and historical
readiness snapshots are preserved. These presentation/confidence changes require
only a page reload after deployment, not a new comparison run or migration.

Parity does not establish that the source website's data is correct. Identical
incorrect timezone offsets on both sides still require a separate data-quality
check.

# Why tiny websites were slow

The uploaded staging logs for Petit Théâtre show:

| Run | Scope | Total | Sum of native fetch durations |
| --- | --- | ---: | ---: |
| 9 | 5 pages, Strict | 113.44s | 0.605s |
| 10 | 9 pages, Standard | 197.95s | 0.976s |

All nine native fetches completed within about four seconds. Date-format log
clusters then progressed roughly once every 16–27 seconds, consistent with most
time being spent in sequential source comparisons. The old logs do not time
individual fields or reconciliation calls, so they cannot prove which lookups
dominated that particular run.

The comparator runs every selected DSL source against both snapshots and formats
both outputs. URI formatting can query Artsdata after a local lookup. The old
path repeats identical requests on both sides and across pages. Organization
expansion also repeats the same Person query. The latter is now served from the
run cache rather than changing ordinary reconciliation semantics.

A controlled probe used the real comparator, formatter and local lookups, with
instant simulated HTTP responses. Each synthetic page had Title, Location,
Organizer and Performer; venue and organizer were shared and performer differed
per page. Both snapshots agreed, and selected-source execution counts were
unchanged.

| Pages | DSL executions | Previous HTTP requests | Requests with run-scoped reuse |
| ---: | ---: | ---: | ---: |
| 1 | 8 | 10 | 4 |
| 9 | 72 | 90 | 12 |
| 100 | 800 | 1,000 | 103 |

These are measured request counts for the synthetic configuration, not staging
speed promises. Local work with instant HTTP was around 1.5 seconds for 100 pages
in both cases. Real elapsed savings depend on external latency and site sources.
At the old observed rate of roughly 22 seconds/page, 100 pages would take around
37 minutes and 300 around 110 minutes: a linear projection, not a benchmark.

# Boundaries and measurement

`ComparisonRefreshProxy` is created once per transition run and shared by its page
comparators. Its cache holds parsed raw reconciliation responses keyed by the
exact request URL, including query, type, endpoint and structured region
constraints. Valid empty results are reused. Responses are copied; per-page
filtering and self-link exclusion still run separately. A new run gets a new
cache, so results never leak into another run, operator or normal refresh.

Only comparison lookups use the ten-second HTTP timeout. Non-success statuses,
invalid response shapes, error payloads and exceptions are never cached as
successful empty matches. They remain extraction errors and cannot certify
parity. Ordinary statement refresh behavior is unchanged.

The run's existing deadline is checked between pages, source sides and before
formatting. Interrupted pages are inconclusive; already detected critical
differences are retained. The final run-publication gate still checks its lease
and configuration digest. These checkpoints do not forcibly interrupt arbitrary
Ruby DSL code inside a single step.

Each source artifact now records separate extraction and formatting times for
both sides. Export phase evidence holds a `performance` snapshot containing
phase durations, reconciliation request/reuse/error counts, HTTP duration and the
ten slowest sources. A single `distillator.transition.performance` log entry
summarizes the run. The pinned report shows this under collapsed **Where time was
spent**. Formatting and reconciliation timings overlap; they must not be added
together as independent totals. No migration is needed.

After deployment, rerun Petit Théâtre with All + Strict, inspect the runtime
breakdown and then assess a larger site. Check request counts and extraction time
before adding concurrency; increasing worker load without removing duplicate
requests would amplify calls to Artsdata and consume more database connections.
