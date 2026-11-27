# Transition report state and rollback

The detail report distinguishes three facts:

| Fact | Source | Meaning |
| --- | --- | --- |
| Current operation | Website rollout mode and latest activation event | Which backend serves this website now |
| Current check | Latest transition run | Queued, running, completed, or failed attempt |
| Completed comparison | Evidence from one published completed run | The sampled findings from that run, evaluated as of completion |

Running a new check never changes the rollout mode. Until all phases finish, the
previous completed comparison remains visible with its run ID and timestamp.
Partial evidence is not presented as a completed result. Failed attempts have
their own error message and do not overwrite the previous completed result.
The attempt is observed once per report; every phase, count, timestamp, and URL
row is bound to the selected completed run. If another process finishes a run
mid-render, it appears on the next request rather than replacing part of the report.

`TransitionStatus.for_completed_run` is a read-only snapshot projection. It
requires a completed run belonging to the website, reads only that run's evidence,
uses its completion time, and excludes newer cache observations and live run gates.
Normal `TransitionStatus.call`, activation services, and promotion controls retain
their live checks for freshness, configuration changes, and incomplete runs.

An accepted comparison is marked as reviewed only when its run ID and configuration
digest match the relevant activation snapshot, all phases passed, and its warnings
were covered by that review. That historical label is separate from permission to
activate now. Later runs cannot inherit the earlier review. New fetch failures are
shown as current operational observations even if the old comparison was accepted.

| Rollout change | Backend afterward | Report behavior |
| --- | --- | --- |
| Active → Legacy | Wringer | Shows Legacy operation; move to Shadow before considering activation |
| Active → Shadow | Wringer | Shows current readiness; a prior activation is not current approval |
| Shadow → Active after review | Condenser | Records the new reason and activation snapshot |
| Check finishes while Legacy is selected | Wringer | Publishes comparison evidence without changing mode |

Fresh, unchanged comparison evidence remains usable under the existing policy.
Review-needed differences still require an explicit reviewed activation and reason.
Direct Legacy → Active remains blocked except for the existing explicit override
path. Saving the same mode does not create another activation event.
Configuration changes still invalidate current readiness. Restoring a setting
does not bypass the fingerprint check: only an exact matching configuration can
use the existing evidence, and normal activation freshness rules still apply.

Only Shadow sites with ready evidence count as promotable. Active and Legacy sites
are excluded from that count even when their completed comparisons pass.

The website and report share rollout history rendering. Original warning/blocker
snapshots and reasons remain available in collapsed audit details. A healthy local
cache is labeled as a Condenser cache, never a failed cache. Active-cache links name
the resolved backend. The read-only paired check shows source comparisons rather
than a misleading zero statement-refresh count.

The report layout itself requires no migration. Reviewed URL exclusions add the
table described below.

## Report layout and evidence links

The header identifies current operation; it is separate from a single decision
banner and the latest attempt's lifecycle. A pending/failed attempt never borrows
the previous run's passing verdict as permission to activate. Historical reports
offer neither activation guidance nor retry controls. Active sites remain Active
when a later comparison fails; those failures remain visible as evidence.

Every report displays all three checks, in order: fresh fetch parity, selected
statement equivalence, and export serializer compatibility. Green means passed,
amber means review/incomplete/stale, red means a recorded failure, blue identifies
an in-progress run, and grey means not evaluated or not recorded. Each colour is
paired with a text label; the checks do not disappear when another check fails.
The serializer check uses stored data and is explicitly separate from fresh
extraction coverage. Its passing result must not imply full end-to-end parity.

Retrieval failures name the affected URL, backend, HTTP result and recorded error.
Attempts, successes, available pairs and compared pages are separate counts.
Incomplete coverage is distinct from a confirmed difference. Known selected-field
or export failures remain blocking even if other pages could not be compared.
Only non-MATCH recorded statement artifacts appear in the findings section, grouped
by page and identifying the property, source and language. Both recorded values
and any extraction errors are visible. Unsupported comparison fetch steps remain
inconclusive, rather than being relabelled as confirmed data regressions.
Standard and Strict both compare selected sources only. The report never expands
the source scope using current selections or re-executes the DSL on GET.

Recorded-fetch links include the completed run ID and evidence key; opening one
expands that exact stored record without JavaScript. Recorded-value permalinks
point to the same run and artifact. Later checks/cache refreshes cannot replace
that evidence. Current source editing and cache inspection are separately labelled.
Older checks that lack compared values say so rather than inventing values.

Timing, all-URL diagnostics, scope and audit details are closed by default.
The layout expands with the browser width; long values wrap and paired values
stack on smaller screens. Existing activation and rollback services remain the
authority for state changes; the presentation layer cannot activate a website.

## Reviewed URL exclusions

When the latest completed fresh check records **source HTTP 404 or 410 on both
backends**, its report offers **Exclude this URL from transition checks**. The
operator confirms that the URL was removed rather than moved and records a reason.
This does not mean the event was cancelled and does not delete/archive its data.

The review records the website, exact URL, reason, time, supporting run and the
recorded per-URL evidence. A Wringer API endpoint error, timeout, one-sided 404,
server error, missing freshness metadata or cached response is insufficient.
Historical runs and in-flight checks do not accept scope changes. All controls
use authenticated, CSRF-protected POST/PATCH requests; GET remains read-only.

An active exclusion applies to that website's exact URL until it is explicitly
restored. There is no automatic retirement after a failed request. **Restore URL
to transition checks** requires a reason and retains the earlier review and
revocation history. The original review cannot be edited in place. A new review
after restoration creates a separate record.
The current report's Audit section includes the latest ten reviews and their
restoration reasons. Pinned historical reports retain only their recorded scope.

Changing scope invalidates the current configuration fingerprint. Use **Run a new
check**; the existing completed run, its phase evidence and verdict are unchanged.
Exclusions are applied before choosing Default/Count/All samples, including the
generic fallback, and each new phase records an immutable copy of the applied
reviews. Reports keep original candidates, eligible/selected/compared pages and
reviewed exclusions distinct: for example, **9 original candidates · 8 compared ·
1 excluded after review**. A passing report explicitly says it has reviewed
exclusions; no fresh parity is claimed for excluded URLs. Restoring a URL cannot
rewrite a historical report or authorize activation without a new comparison.

If all publishable event candidates are excluded, the runner does not fall back
to an unrelated listing page. It records an incomplete check and requires an
eligible URL to be restored. Normal refresh, archive dates, stored statements,
last-good cache preservation and Artsdata export behavior are unchanged.

Deploy migration `20261114000100_create_distillator_transition_exclusions.rb`:

```sh
heroku run rails db:migrate --app footlight-condenser-test
```
