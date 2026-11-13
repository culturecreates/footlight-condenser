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

No database migration is required.
