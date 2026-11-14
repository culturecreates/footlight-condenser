# Validate and activate selected event sites

On Websites, filter by name/seedurl (for example `culture*`), then select sites in
the Transition column. `*` is a wildcard; without it the search remains a contains
search. Select all applies to every eligible row in the filtered result, including
the collapsed Unscheduled category. It does not select Preferred checkboxes or
sites outside the filtered page. Templates, tests and entity-only sites are
excluded on the server as well as in the UI. Event pages or selected Event
sources establish event-site eligibility; a workflow with no event pages stops
for attention rather than certifying an unrelated listing.

**Validate and activate selected** authorizes the complete workflow. One selected
site opens its own workflow report. More than one opens a group report with
aggregate progress, result filters, individual report links and Stop remaining
sites. Sites in a group run sequentially. A site's failure does not prevent the
remaining sites from being checked. Stop remaining cancels queued sites; it lets
the current site finish verification or recovery. Already completed sites retain
their result. An already Active site skips pre-activation and verifies its Active
path; failed verification returns it to Shadow under the same recovery policy.
Use **Recent transitions** on Websites to resume or revisit reports. This history
is paginated, and entries for a single site link directly to its site report.

Each Legacy/Shadow site performs:

1. Enter Shadow (Wringer remains serving backend).
2. Run All + Strict against fresh HTML from both backends and selected sources.
   Existing reviewed URL exclusions apply and remain visible in each run.
3. Activate only when all required checks and normal promotion gates pass.
   Review-needed or incomplete results stop for attention, without overrides.
4. Run a separate All + Strict check through the ordinary Active serving path,
   without a forced execution-mode override. Verify the resolved serving backend
   is Condenser and that every successful fetch actually uses its native path.
5. Keep Active on success; otherwise return to Shadow and record recovery.

Both workflow checks require a native Condenser fetch; comparing two Wringer
fallbacks cannot qualify. Existing diagnostic/standalone check behavior is retained.
Checks update fetch caches but never stored statements or event exports. A mode
rollback restores backend selection; it is not a database restore.

The site report retains starting mode, pre-check, activation, active verification,
recovery, recorded final state and reason. Each comparison links to its exact
run. Current mode is displayed separately from the recorded outcome. Deleting a
website retains its group entry as stopped/deleted, rather than removing it from
the accounting. Failed recovery is explicitly red and records the actual mode.

## Progress and timing

Reports poll read-only status every five seconds, stop at completion, and back off
on network errors. Reloading never resubmits a workflow. Run progress records the
current phase and processed-page counts for retrieval and statements. Processed
pages are not asserted to have passed; completed comparison reports retain the
separate attempt/success/paired/compared counts.

Estimated work uses the median seconds per selected page from up to six recent
completed checks for each site, scaled to its current eligible publishable pages
and one or two checks as appropriate. The report shows an approximate range,
excludes queue waiting, identifies sites lacking timing history, and says when
work exceeds previous timings. It does not fabricate an ETA from job percentages.
Timing history and initial estimates are loaded in bulk for group admission.

## Ownership and recovery

Group request keys make repeated submissions idempotent. A partial unique index
allows only one queued/running workflow per website. Conflicting checks and
exclusion changes are rejected while the workflow owns a site. Ordinary manual
mode controls remain available; a mode/event change cancels automation without
overriding the operator. Configuration changes invalidate publication/activation.

Each phase is durably recorded and claimed once. Duplicate or late jobs cannot
activate a completed, cancelled or recovered site. A delayed watchdog is queued
before check work. The pre-check watchdog also survives the activation-to-postcheck
handoff. It follows the current deadline, fails an abandoned run, and attempts
Shadow recovery after expiration. Queue failures during handoff also trigger
recovery. Recovery failures are surfaced rather than being reported as success.

A separate group reconciler is scheduled every minute by Sidekiq's recurring
worker heartbeat, including after worker restarts. It resumes groups stranded
between sites or before their first enqueue, retries unclaimed Active-check
handoffs, and queues recovery for expired running work even when the original
per-site watchdog was never enqueued. A stopped group still receives recovery
for its current site, but its cancelled sites never restart. Database locks keep
group steps sequential and throttle duplicate sweeps across worker processes.
Queue failures leave committed queued work available for a later sweep. Sweeps
and recovery jobs still depend on an available worker and queue; queue waiting
adds to the one-minute sweep interval. Claimed checks are not run twice: an
abandoned claimed phase is recovered after its existing one-hour lease/grace.

Admission expires standalone queued/running checks whose one-hour lease elapsed,
recording the failure before creating the workflow. Healthy standalone checks
still block admission. Runs owned by another workflow must finish or recover
through that workflow; admission never bypasses their ownership.

Successful site reports display one final verdict and concise linked verification
results. Findings expand only when there is a warning, failure or other finding.

## Content rejection and inspection context

Cloudflare/CAPTCHA keywords in cookie descriptions, script URLs or embedded forms
do not by themselves establish a challenge page. These rules also require a
recognizable primary page title/heading (or a short plain-text challenge response).
An explicit `cf-mitigated: challenge` response header independently blocks content,
even with a large body or a familiar title. Genuine challenge pages and HTTP
failures still reject content. Selected-source
statement and export gates are unchanged; accepted HTML alone cannot activate a site.

New comparisons record transport/content success separately, the fresh HTTP code,
and bounded primary matcher evidence (source, pattern and snippet). A reported
HTTP-200 challenge is described as rejected content rather than a network failure.
Previously completed runs retain their recorded results and require a new check
to validate a detector correction. Do not exclude valid event URLs to bypass an
incorrect detector. Adaptive fingerprints and profile backfills are not part of
this correction and are not prerequisites for accepting ordinary event HTML.

Cache inspection resolves site context from an unambiguous exact webpage URL.
Unknown/shared URLs and the global cache list do not inherit a previous site's
navigation cookie. Redirect counts use destination changes; a chain containing
only the requested URL is Direct. Existing materialized redirect flags are updated
on the next cache save/refresh, while inspection computes the corrected summary.

Deploy migrations through `20261114000300_add_transition_batch_reconciliation.rb`
and run:

```sh
heroku run rails db:migrate --app footlight-condenser-test
```

The worker dyno must be running for workflow steps and delayed recovery guards.
Tests cover phase progression, failure, exceptions, recovery, manual intervention,
idempotency, selection rules, progress polling and real active-path dispatch.
