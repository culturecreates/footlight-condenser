# Explicit preprocessing refresh policies

This opt-in mechanism refreshes individual derived statements. It does not change existing website schedules, Event or ResourceList jobs, exports, rollout modes or stored source algorithms. There is no refresh DSL instruction and no POST-to-self orchestration.

## Stage-first deployment and inventory

Deploy branch `harden-dsl-reliability` and run the database migration:

```sh
heroku run rails db:migrate --app footlight-condenser-test
heroku run rake footlight:preprocessing_inventory --app footlight-condenser-test
```

Inventory is read-only: it does not call remote APIs, refresh statements, create policies or enable anything. It inspects these operator-supplied **statement IDs**:

| Expected website | Statement | Purpose |
|---|---:|---|
| gatineau-cloud-RList | 646580 | Consolidated URLs and audience parameters |
| gatineau-cloud-RList | 663745 | Event-to-audience mapping |
| culturemauricie_lepointdevente-com-RList | 2020881 | URL-to-category mapping |

IDs can differ between environments. The inventory prints actual ownership, webpage/class/source/property IDs, manual state and refresh/change timestamps. It also lists same-website ResourceList property-69 input candidates; these are suggestions to inspect, not automatically declared dependencies. Missing or mismatched IDs require investigation rather than a broader class/URL fallback.

## Create and validate a policy

Open **Options → Preprocessing refresh policies**. Pilot links prefill a statement ID and expected website seedurl. Creating a policy always creates a disabled draft. No source algorithm executes on save.

1. Confirm the statement, source, webpage and website identity in this environment. Policies are not limited to ResourceList websites.
2. Inspect its existing DSL, especially literal `api=` URLs and Ruby database queries. Gatineau Event Audience source #4608 previously referenced production explicitly. A staging refresh cannot change what a production-pointing consumer reads. This implementation does not rewrite URLs or prove that arbitrary Ruby reads declared inputs.
3. Enter the actual required upstream statement IDs. They must exist in the same website; the target cannot depend on itself. For an external-input cache such as Co-motion Bundle, explicitly leave the list empty and verify its external inputs instead. No upstream-statement freshness claim is made in that case.
4. Confirm that the DSL reads those inputs in the intended environment. This is an operator confirmation, not an automatic analysis of arbitrary DSL code.
5. Set the interval (default 12 hours), stale threshold (default 48 hours) and monitoring preference, then enable.
6. Use **Queue refresh now** and inspect the recorded attempt, stored refresh timestamp and input observations.

For Gatineau consolidation, inspect the eight upstream property-69 statements (reported as 646572–646579). The audience mapping's declared input is the validated consolidation statement. For Culture Mauricie, inspect the mapping and its eight actual list statements before enrollment. No pilot policy is seeded or enabled automatically.

For a ResourceList used only as a preprocessing input, add a selected **RDF Class** source for **ResourceList** with `manual=None`. Refresh the lists and confirm each has a selected RDF Class statement with cached value `None`. The normal list refresh saves its inputs, then discovery skips that list without requiring a URI List. A class such as `manual=Event` enables discovery. A blank or missing RDF Class still raises a configuration error. For an older queued discovery job whose URL is shared, queue a new run from the intended website to identify its list record.

Only enroll read/derive DSL: database transactions cannot undo external side effects from arbitrary Ruby, and retries can repeat such side effects.

Manual reviewed statements are protected. A skipped manual statement is not reported as a successful recomputation.

## Automatic execution

Add one **separate hourly Heroku Scheduler task**:

```sh
bundle exec rake footlight:refresh_preprocessing
```

The task queues only enabled, due policies and checks their freshness. With no enabled policies it queues no refresh jobs. Timing uses elapsed hours, independent of daylight-saving changes. This task is separate from `footlight:refresh_websites`; ordinary operations retain their existing schedule.

Each target has its own job. One failure does not stop another policy. A successful save schedules its next run after the configured interval. A failed execution becomes due after one hour. An unchanged value counts as successfully refreshed; a blank-preserved result, failed save or abort does not.

The exact statement is locked and refreshed through the existing helper. URL-only lookup, webpage discovery and webpage-removal behavior are not invoked. An additive `saved` result field distinguishes successful persistence from an apparently empty error list. Existing helper behavior and DSL accumulation semantics are unchanged.

## Duplicate and interruption handling

A database claim records the queued run before enqueueing. Queue claims expire after two hours; worker claims expire after 15 minutes, with a five-minute execution deadline. The hourly dispatcher recovers expired claims, including a crash between committing a queue claim and submitting the job. Missing ticks are caught by the next due sweep.

Duplicate jobs cannot execute an already running/completed/superseded run. Statement writes and completion are committed together. A worker whose policy was disabled or changed during execution rolls back its result rather than completing stale configuration. Policy identity snapshots prevent a target moved to another website from being refreshed.

The dispatcher must continue running for lease recovery. Backlogs can delay jobs; neither this mechanism nor the existing daily schedules promise a strict end-to-end 48-hour bound. There is no dependency-order gate or export gate.

## Operational monitoring

Enabled policies can opt into three independent issue kinds:

- **Preprocessing failure:** queue/configuration/extraction/save failures, regardless of whether the DSL added `notify: daily`.
- **Stale refresh:** no valid target `cache_refreshed` within the threshold. `cache_changed` is never used for freshness.
- **Stale inputs:** a required input is missing, moved, never refreshed or too old. An implausibly future timestamp is also invalid.

These share the existing Condenser Monitoring store, Console feed, daily digest and weekly pulse. Ordinary DSL errors remain opt-in under their original flag. A DSL success resolves its DSL issue; it cannot erase a separate stale-input condition. Duplicate representations of an existing flagged DSL failure are suppressed.

Successful attempts retain declared input timestamp observations. If an output was computed while those observed inputs were stale, refreshing the inputs alone does not repair the output or clear its warning: successfully rerun the policy. Observations describe declared inputs, not a guaranteed atomic snapshot of every API or database read performed by arbitrary Ruby. They do not establish that data is identical to the latest upstream version.

Freshness checks run during the hourly sweep and independently before the email digest/pulse. Thus the email task can detect stale preprocessing even when its refresh dispatcher stopped, provided the email task itself still runs. Monitoring pages are read-only. Policy pages show when freshness was last checked. Disabling a policy or its policy monitoring resolves that policy's operational issues; separately flagged DSL errors retain their own lifecycle.

## Pilot acceptance

Use staging first. Validate each intended target, run it once, inspect the saved result and provenance, then repeat to prove an unchanged result still advances refresh time. Verify abort/blank/manual protection, stale-input warning and recovery, duplicate delivery, expired-claim recovery, changed ownership and independent-policy progress. Confirm unrelated schedules and exports were not altered. Activation and publication are outside this workflow.

## Co-motion Bundle cache

The same opt-in policy mechanism supports ordinary Event websites. A Bundle statement can be explicitly enrolled even when its source is unselected for publication. A root Bundle policy has no stored input IDs; its verified DSL fetches ticket data and stores the compact JSON. Monitoring covers execution and output freshness, not the unobserved freshness of external APIs.

Price and Price Description remain readers of the stored Bundle. Their existing Event refreshes may consume it normally. If a different cadence is needed, enroll those specific reader statements separately and declare the Bundle statement for the **same webpage** as their required input. There is no automatic enrollment of all Co-motion events and no change to source #5266, #1138, #5265, existing Event schedules, manual corrections or blank-preservation rules. Validate actual statement IDs per event. No global ordering or a new cache format is introduced.
