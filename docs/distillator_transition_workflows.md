# Validate and activate selected event sites

On Websites, filter by name/seedurl (for example `culture*`), then select sites in
the Transition column. `*` is a wildcard; without it the search remains a contains
search. Select all applies to every eligible row in the filtered result, including
the collapsed Unscheduled category. It does not select Preferred checkboxes or
sites outside the filtered page. Templates, tests and entity-only sites are
excluded on the server as well as in the UI. Event pages or selected Event
sources establish event-site eligibility; a workflow with no event pages stops
for attention rather than certifying an unrelated listing.

**Validate and activate selected** uses **Light** for the default sample and
Standard field comparison, or **Thorough** for all eligible pages and Strict
field comparison. Thorough is the default and moves previously Active sites to
Shadow before the precheck. Light validation of an already Active site goes
straight to Active verification and can return the site to Shadow on failure.
**Audit selected Active sites (Thorough)** checks the Active path using all
eligible pages and Strict field comparison. It reports failures for review
while leaving the serving mode under operator control. Only Active event sites
can enter an audit. Audits also include historical event pages.

One selected
site opens its own workflow report. More than one opens a group report with
aggregate progress, result filters, individual report links and Stop remaining
sites. Sites in a group run sequentially. A site's failure does not prevent the
remaining sites from being checked. Stop remaining cancels queued sites; it lets
the current site finish verification or recovery. **Cancel current transition**
requests a cooperative stop for the running site. A stopped validation can
return the site to Shadow during recovery. An in-flight operation can finish before cancellation takes
effect. The rest of the group can proceed unless Stop remaining sites was also
used. Already completed sites retain their result.
Use **Recent transitions** on Websites to resume or revisit reports. This history
is paginated, and entries for a single site link directly to its site report.

The full validation workflow performs these steps for Legacy and Shadow sites,
and for Active sites when Thorough is selected.

1. Enter Shadow (Wringer remains serving backend).
2. Run the chosen profile against fresh HTML from both backends and selected sources.
   Existing reviewed URL exclusions apply and remain visible in each run.
3. Activate only when all required checks and normal promotion gates pass.
   Review-needed or incomplete results stop for attention, without overrides.
4. Run a separate check with the same profile through the ordinary Active serving path,
   without a forced execution-mode override. Verify the resolved serving backend
   is Condenser and that every successful fetch actually uses its native path.
5. Keep Active on success; otherwise return to Shadow and record recovery.

### Prepare event inventory

Use **Refresh lists and add webpages** from the website's batch jobs and let
discovery and any newly queued event refreshes finish before validating. The
transition itself reads the stored lists. The normal discovery and publishing
schedule is independent of transition validation.

An activation check can omit a past event when its selected start and end
values place its last occurrence before the check day, and every applicable
ResourceList confirms its absence by both webpage URL and RDF URI. The selected
URL and URI lists must be nonempty, aligned and refreshed in the last 48 hours,
within ten minutes of each other. A modified, missing, stale or ambiguous list
keeps the existing scope, as does a list with URLs still awaiting import.
Matching a current list or having uncertain dates
also keeps a page eligible. The report records the discovery evidence and each
omitted URL. A changed or expired proof requires a new check before activation.
An empty post-filter scope cannot pass. The export comparison still uses the
stored data in the environment.

Shared extraction failures are reported as inconclusive statements. When both
backends record fresh source HTTP 404 or 410 responses for the same URL, the
report counts one source-availability finding. Activation still requires
successful coverage of the in-scope pages. A reviewed exclusion remains an
explicit, reversible decision.

Transition fetches take one slot per source hostname across workers. The `www`
alias shares that slot. Wringer retries transient timeouts, connection
interruptions, and HTTP 429, 500, 502, 503 and 504 up to twice. Each retry forces a
scrape. Backoff starts at 0.5 seconds and then 1 second, and honors a longer
`Retry-After` up to 5 seconds within the check's time budget. A longer wait
leaves the fetch incomplete. The report records recovered and incomplete retries
with request timings and HTTP statuses. Cached fallback bodies remain invalid.

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

## Shared extraction failures and grouped source review

Both fresh HTML inputs are evaluated by the same local Condenser DSL runner.
The comparison does not independently execute the production Wringer DSL engine.
Identical, nonempty error type/message/source/step artifacts are recorded as
`SHARED_EXTRACTION_ERROR`, not a successful value match. One-sided or different
errors remain `PARSE_ERROR`; differing valid values retain their value verdict.
Shared selected-source errors leave activation pending in Standard and Strict
checks; they are not counted as confirmed critical or optional differences.
Matching errors support equivalent behavior on those inputs without proving
successful extraction. Missing snapshots and unsupported nested fetches remain unverified.

Reports group matching failures by source/language, show each error variant and
its count, and link one representative page per variant. All affected URL evidence
remains expandable. Older completed PARSE_ERROR records with matching errors get
the same presentation without rewriting their evidence or making them promotable.
Inspect the actual algorithm and compare with a stored production statement before
deciding whether a shared runner failure is an existing DSL defect or a compatibility
regression. A repeated `.drop` error alone is insufficient to choose a DSL rewrite.

Multiple bilateral fresh 404/410 candidates have one review form with unchecked
URL selections and one required justification. The server validates the entire
selection against the latest completed run under the website lock and records all
reviews atomically, each with its own URL/evidence and independent restoration.
Redirects, one-sided failures, stale caches and arbitrary URLs do not qualify.
These reviews change comparison scope only; they never delete events or convert
shared extraction failures into passing evidence. A new check is required afterward.

Deploy migrations through `20261114000300_add_transition_batch_reconciliation.rb`
and run:

```sh
heroku run rails db:migrate --app footlight-condenser-test
```

The worker dyno must be running for workflow steps and delayed recovery guards.
Tests cover phase progression, failure, exceptions, recovery, manual intervention,
idempotency, selection rules, progress polling and real active-path dispatch.
