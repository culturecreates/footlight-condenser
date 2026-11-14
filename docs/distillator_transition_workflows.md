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

Deploy migration `20261114000200_create_transition_batches.rb` and run:

```sh
heroku run rails db:migrate --app footlight-condenser-test
```

The worker dyno must be running for workflow steps and delayed recovery guards.
Tests cover phase progression, failure, exceptions, recovery, manual intervention,
idempotency, selection rules, progress polling and real active-path dispatch.
