# P1 transition integrity

The transition batch now compares selected DSL source values against separate Wringer and Condenser HTML snapshots. It shares `MigrationComparator` with the diagnostic comparison page and never refreshes stored statements. Event Title, Dates and Location differences block activation; optional differences require review. Missing required sources, missing snapshots, mixed rendered/plain source profiles and unsupported nested-resource fetches remain inconclusive. Rendered sources request a rendered candidate snapshot; one snapshot pair cannot certify multiple fetch profiles. Array order is preserved, including date/location alignment. The export phase checks **serializer compatibility over the existing database**, not independent end-to-end exports.

## Run lifecycle

A transition run records queued/running/completed/failed state and its configuration fingerprint. The fingerprint includes website language/graph/seed, source and property values (including datatype definitions), class names, and candidate webpage metadata. It hashes values directly so whole-second timestamps cannot hide rapid edits. Each phase appends evidence associated with that run. Readiness reads only the latest completed run; a newer queued, running or failed attempt blocks normal activation. Old completed evidence remains visible while its replacement is unfinished. A source/sample change invalidates readiness.

Requests lock the website row and reuse its active run. A database partial unique index also prevents two active runs. Workers claim queued runs once; duplicate delivery is a no-op. A failed enqueue leaves an explicit failed attempt that can be retried. Attempts expire after an hour; requesting again replaces an expired attempt, and an expired worker cannot publish. A hard-killed worker can leave a running run until it expires; this cannot authorize activation.

The preflight reads Sidekiq/Redis heartbeat data and verifies a recent, non-quiet worker consumes the transition job queue. A configured adapter alone no longer establishes worker health. Enqueue success still does not guarantee execution: the report shows queued until a worker claims the run. No dynos are enabled automatically.

Mode changes and rollout audit events use one transaction and the same website row lock. Readiness is rechecked inside that lock. An audit failure rolls back the mode change. Explicit runtime-controlled overrides remain available and retain their reason/audit trail.

## Reports

“All rollout modes” has an explicit `all` value. The default is still Shadow. Comparison/cache context links retain their complete labels. Summary cards and blocker totals cover **all sites matching the filters across pages**; table rows and page counts describe the current page. Blocker counts use structured phase statuses instead of searching English messages.

## Staging deployment

1. Deploy this branch to `footlight-condenser-test` with `bundle exec rails db:migrate` applied before new web/worker processes start. Use a release phase, or pause the web/worker processes during a manual deploy and run `heroku run rails db:migrate --app footlight-condenser-test` before resuming them. Maintenance mode alone does not pause workers. The migration adds transition runs and an optional evidence foreign key; it does not rewrite old evidence.
2. Verify the Sidekiq worker is running with Redis configured and consumes `default` (or the configured transition job queue). Run `bundle exec rake distillator:transition:preflight` to check heartbeat/queue readiness.
3. Run a new transition batch check for each site being considered for normal activation. Historical unbound evidence is retained for audit but cannot authorize activation.
4. Check one completed report, deliberately change a source and verify activation is blocked until a fresh completed check. Exercise a duplicate request and a failed check before expanding the rollout.

No production mode or database is changed by this commit. The Console repository needs no change for these Condenser transition fixes.

## Verification

The regression tests cover real PostgreSQL run publication, deduplication, worker failure, configuration invalidation, concurrent mode changes and audit rollback. Paired extraction tests use local HTML/DSL fixtures; HTTP is disabled. Unsupported nested-resource parity is deliberately not certified. The report/navigation tests cover explicit All, intact diagnostic links, structured failures and stable summary scopes across pagination.

Verified locally with Ruby 3.4.8, Rails 8.0.2 and PostgreSQL 17: 588 targeted model, service, controller, job and task tests, 4,039 assertions, no failures/errors/skips. The routine Distillator fast task also passes; its existing extraction-drift sentinel remains explicitly skipped.
