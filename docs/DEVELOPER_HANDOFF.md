# Condenser: developer handoff and change map

> **Start here when taking over Condenser, reviewing the Wringer-to-Condenser migration, or preparing a release.** This is a navigation guide, not a substitute for the linked technical specifications or a claim that every feature is deployed.

**Snapshot:** 2026-11-17. **Development reference:** [harden-dsl-reliability at ad6eec8](https://github.com/culturecreates/footlight-condenser/commit/ad6eec81e8601355dd3808719c9844898022c4aa). **Git baseline:** [main at fde44ce](https://github.com/culturecreates/footlight-condenser/commit/fde44ced8d8b83216d45cbf03cbbf2f2252427b0). At this snapshot the development branch is 136 commits ahead of and 3 commits behind main; **these branches have diverged**. See the [GitHub comparison](https://github.com/culturecreates/footlight-condenser/compare/main...harden-dsl-reliability) and [branch history](https://github.com/culturecreates/footlight-condenser/commits/harden-dsl-reliability/).

**Important release limitation:** main is a Git baseline, **not a verified production deployment SHA**. Before declaring a change to be “since production,” get the currently deployed Heroku release commit for production and staging and compare each to the candidate commit. This guide marks features as *implemented on the development branch* unless a deployment and configuration are independently verified.

## Read this in 10 minutes

Condenser gathers webpages, executes **DSL sources** to derive statements, supports review/manual corrections, and exports event and related-entity RDF to Artsdata. The historical fetch/cache backend is **Wringer**. The project is moving compatible fetch/cache behavior into Condenser under the internal **Distillator** namespace, with per-website production rollout controls. This migration must **preserve functionality and RDF data first**; a performance optimization does not justify output differences without an explicit review.

~~~
External pages / ResourceLists
    -> Wringer cache (Legacy) OR Condenser fetch cache (Active)
    -> DSL source execution and datatype formatting
    -> stored statements + operator review/manual overrides
    -> Event/EventSeries/Place/Person/Organization/Offer RDF
    -> Artsdata / Databus

Separate dependency: ResourceList statements -> derived mapping statements
                                     -> event DSL properties
~~~

**Terminology:** Legacy = Wringer production path; Shadow = Wringer serves while Condenser is compared; Active = Condenser serves with Wringer retained for inspection/rollback. “Distillator” and “internal” are implementation/compatibility names, not new operator rollout states. [Rollout glossary](rollout_modes.md) · [current site transition playbook](distillator_migration.md).

**Do not confuse these checks:**
- **Transition check:** compares candidate fetch/statement/export behavior to decide whether a website may move from Legacy through Shadow to Active. A fresh completed run with bound evidence is needed. [Scope](distillator_transition_check_scope.md) · [report/rollback states](distillator_transition_report_states.md).
- **Databus replay:** read-only investigation against dated production exports and pinned existing Wringer cache inputs, using the candidate DSL runner and current formatting/export code. This is **not** production promotion evidence by itself; “incomplete” means missing input or extraction/export coverage, not necessarily a regression. [Replay guide](databus_replay.md).
- **Preprocessing refresh:** separate, opt-in periodic refresh of a specific derived statement. It does **not** change the website's daily scheduler, auto-enroll statements, or strictly order all dependencies. [Policy and recovery guide](preprocessing_refresh.md).
- **Monitoring:** reports specifically flagged DSL aborts and problems from enrolled preprocessing policies; it is not a global site-health guarantee. [Monitoring guide](monitoring.md).

## Major changes and where to learn them

| Workstream | What changed on the development branch | Primary docs / code | Activation or risk |
| --- | --- | --- | --- |
| **Fetch/cache migration** | Condenser-side compatible fetch cache, safer URL handling, redirect/response metadata and Wringer compatibility boundaries; site-aware modes and inspection tools | [Parity matrix](distillator_wringer_parity.md), [compatibility contract](distillator/cache_compatibility_contract.md), [Wringer matrix](distillator/wringer_compatibility_matrix.md) | Legacy fallback must remain operational; verify real fetch behavior and selected response versions |
| **Rollout controls** | Legacy/Shadow/Active website modes, guarded activation, recorded evidence and rollback history, scoped/grouped transition checks, batch progress and recovery | [Playbook](distillator_migration.md), [modes](rollout_modes.md), [transition workflows](distillator_transition_workflows.md), [integrity](distillator_p1_transition_integrity.md), [report states](distillator_transition_report_states.md) | Never treat old or incomplete evidence as current approval; required database migrations |
| **DSL semantics / diagnosis** | Explicit production append/accumulation contract, legacy-vs-new evaluator differential tests, stronger abort/trace and URL handling; source-specific tests for Gatineau End Date and other cases | [DSL accumulation contract](dsl_production_accumulation_contract.md), [URL placeholders](dsl_url_placeholders.md), [runner](../app/services/dsl/core/algorithm_runner.rb) | Do not “fix” a historical DSL semantic silently; validate output against independent historical execution |
| **DSL instruction library** | Editable reusable instruction tokens with revision history; starter entries and source-editor support; expansion before execution | [Library manual](dsl_library.md), [candidate analysis](dsl_library_analysis.md) | Editing a shared token affects future executions of all consumers; no automatic statement refresh |
| **Preprocessing / ResourceLists** | Explicit per-statement periodic policies, due-run scheduling, durable attempts, stale-input/result checks, operator opt-in; supports Bundle caches too | [Preprocessing playbook](preprocessing_refresh.md), [dispatcher](../app/services/preprocessing/dispatcher.rb), [job](../app/jobs/refresh_preprocessing_statement_job.rb) | **Code exists, policies are disabled until enrolled and scheduler is configured.** Does not enforce global completion ordering |
| **Operational monitoring** | Opt-in per-source DSL failure recording; monitored preprocessing failures/freshness; authenticated issue lists, optional daily digest and weekly pulse; Console integration in its own branch | [Monitoring manual](monitoring.md), [recorder](../app/services/monitoring/recorder.rb), [Console dashboard-monitoring branch](https://github.com/culturecreates/footlight-console/tree/dashboard-monitoring) | Requires database migration and optionally mailbox/SMTP plus separate daily scheduler; an unflagged DSL failure is not automatically recorded |
| **Databus/RDF fidelity** | Read-only export replay, local resource enrichment and parent venues, stricter EventSeries error reporting, date/location alignment scrutiny; performance changes must not change graph | [Replay guide](databus_replay.md), [EventSeries/export code](../app/services/jsonld_generator.rb) | Compare actual RDF and classify historical/input drift, manual corrections and missing staging pages separately from regressions |
| **Website/administration UX** | Grouped website overview, Preferred view, selected-event-site transitions, clearer comparison/error reports and linked inspection workflows | [Website index](website_index.md), [transition UI](distillator_transition_workflows.md), [report states](distillator_transition_report_states.md) | Preferred is an operator convenience, not a release or rollout mode; some features require migrations |
| **Runtime/build** | Upgraded Ruby/Node and buildpack assumptions, clearer local/staging build and test instructions | [Runtime versions](runtime_versions.md), [README](../README.md) | Check *deployed* runtime, buildpack order, locked dependencies and asset compilation independently |
| **API contracts** | Hardened event JSON/list/report contracts and filter/query behavior | [Events JSON contract](events-json-contract.md), [comparison runtime notes](distillator_comparison_parity_and_runtime.md) | Consumers may rely on legacy response shape; check Console and downstream clients |

These are thematic highlights, **not** a per-commit changelog. For changes outside this map, use the [commit comparison](https://github.com/culturecreates/footlight-condenser/compare/main...harden-dsl-reliability) and the linked source tests.

## Two real preprocessing chains (Gatineau and Culture Mauricie)

The incident that revealed the missing derived-refresh stage is instructive. The upstream ResourceLists were already refreshed on ordinary daily website schedules, but intermediate **synthetic webpages** were not covered by the existing scheduler's ResourceList/eligible Event selection.

| | Gatineau | Culture Mauricie |
| --- | --- | --- |
| Input | Eight current JSON ResourceList statements (property 69) | Category-specific Le Point de Vente ResourceLists |
| Derived statement(s) | **646580** / source 4589 / property 101: consolidate URLs and Audience parameters; then **663745** / source 4606 / property 122: event ID → audience codes | **2020881** / property 121: URL → category codes |
| Consumer | Event source **4608** → Audience property 119 | Event source **7885** → Event type property 14 |
| Failure mode | Derived statements frozen in 2024 despite current upstream pages; current events returned blank Audience | ResourceList mapping freshness/coverage can lag event pages; inspect actual source changes before attributing missing type |
| Manual diagnostic | After refreshing 646580 and then 663745 on production (2026-11-17), mapping covered 71 IDs; sample events 46121 and 46699 extracted **Tous** and **Ados/Familles/Tous** | Production mapping snapshot was used in replay; historical vs current values can differ |
| Permanent mechanism | Enroll explicitly verified derived statements and declared inputs under [preprocessing policies](preprocessing_refresh.md) | Same mechanism after checking the target/source and its actual inputs |

**IDs above were observed in production and are not portable configuration.** The new policy system inventories identities per environment; it intentionally does not auto-enroll by ID, class, URL or “-RList” suffix. A 12-hour interval and a 48-hour freshness threshold are configurable defaults; lag across independently refreshed stages is acceptable where business requirements permit it, **not guaranteed to be bounded at 48 hours**. A separate hourly task drives policies; failures are retried/monitored. Use [preprocessing_refresh.md](preprocessing_refresh.md) as the source of truth.

There is also a separate **Gatineau End Date rule**: this project's End Date denotes a **calendar date for an explicit continuous multi-day range**, not the ending hour of one-day or repeated performances. Start Date can carry time. The current repository contains differential tests and a replacement DSL fixture; **a fixture does not itself update the live source #4264 or stored statement caches**. See [DSL accumulation contract](dsl_production_accumulation_contract.md).

## Release/deployment status ledger (fill in before a release)

Do **not** infer deployment from a merged commit, a green test suite, a README sentence, or a recently updated website timestamp. A new maintainer should complete this table with Heroku release identifiers, commit SHAs, configuration and validation evidence.

| Environment | Deployed Git SHA / Heroku release | DB migrations applied | New scheduler tasks running | Source/policy configuration | Verified by / date |
| --- | --- | --- | --- | --- | --- |
| Production Condenser | **Not verified in this guide** | Not verified | Not verified | Not verified | — |
| Staging Condenser | **Not verified in this guide** | Not verified | Not verified | Not verified | — |
| Console production/staging | **Not verified in this guide** | As applicable | As applicable | Monitoring view deployment unverified | — |

Before rollout, reconcile the branch's **three commits missing from its ancestry of main** rather than assume a fast-forward merge; use the [live comparison](https://github.com/culturecreates/footlight-condenser/compare/main...harden-dsl-reliability).

**Deployment-sensitive additions to check:**
- Apply outstanding migrations **after** identifying the actual deployed migration level; recent additions cover transition runs/batches/exclusions, preferred websites, monitoring, preprocessing policies and DSL library. Inspect [db/migrate](../db/migrate) and [staging integrity](distillator_p1_transition_integrity.md).
- Confirm runtime and buildpacks using [runtime versions](runtime_versions.md).
- Keep the existing website schedule. The optional periodic derived-statement task is **bundle exec rake footlight:refresh_preprocessing** (hourly) and the optional monitoring email task is **bundle exec rake footlight:monitoring_digest** (daily); neither is enabled by a Git commit. See [preprocessing](preprocessing_refresh.md) and [monitoring](monitoring.md).
- Confirm policy enrollment and environment-relative endpoints, rather than assuming a staging source points to staging. See [DSL URL placeholders](dsl_url_placeholders.md).
- Run fresh transition evidence before any website activation and retain Legacy rollback. See [transition playbook](distillator_migration.md).

## Developer verification and safe first tasks

1. **Orient:** read [the README](../README.md), [this guide](DEVELOPER_HANDOFF.md), [rollout glossary](rollout_modes.md), [migration playbook](distillator_migration.md), and [runtime versions](runtime_versions.md). Inspect staging/production release SHAs and scheduler tasks; do not modify production while orienting.
2. **Understand the behavior contracts:** read [DSL accumulation](dsl_production_accumulation_contract.md), [Wringer parity](distillator_wringer_parity.md), [RDF replay](databus_replay.md), and [Events JSON](events-json-contract.md). Preserving output is more important than speeding up a broken transformation.
3. **Run fast tests locally:** DISABLE_SPRING=1 bin/rails test:distillator_fast. Before merging release-sensitive changes: DISABLE_SPRING=1 bin/rails test. Recorded scraping and graph tests are **not** all in the fast subset. See [README Tests](../README.md#tests).
4. **Inspect one site end-to-end:** pick a Legacy or Shadow site. Read the selected DSL, inspect raw cache and statement values, run a scoped fresh transition check, then use [Databus replay](databus_replay.md) where historical RDF evidence is needed. Do not promote on incomplete replay evidence.
5. **Inspect preprocessing separately:** in Options, inspect policies and upstream inputs for Gatineau and Culture Mauricie, check source URLs and actual statement freshness, then validate small refreshes. Do not automatically refresh every page or override manually reviewed statements.
6. **Check operational failure handling:** use [Monitoring](monitoring.md), [transition report states](distillator_transition_report_states.md), and [transition workflow recovery](distillator_transition_workflows.md). Distinguish enqueued work, executed work, saved results, and successful exports.

## Current caution list

- **Release identity:** production deployment SHA and staging deployment SHA are not verified here. This is the first outstanding handoff fact to fill in.
- **Incomplete evidence is not parity:** export comparisons can differ due to missing staging webpages, dated Databus exports, source content changes, or reconciliation; classify causes rather than suppress differences. [Replay](databus_replay.md).
- **DSL changes vs migration:** the Gatineau End Date source correction and other source-level repairs must be assessed separately from interpreter compatibility; tests alone do not change live DSL. [Accumulation tests](dsl_production_accumulation_contract.md).
- **Manual data:** reviewed/manual corrections must survive refresh and rollout. Never treat fresh extraction as an automatic replacement for approved statements. [Migration](distillator_migration.md).
- **Preprocessing:** even successful upstream updates do not refresh derived mappings unless their policies run; freshness monitoring is useful only for enrolled dependencies. [Preprocessing](preprocessing_refresh.md).
- **Monitoring:** the weekly pulse summarizes the *open monitored issue list*, not all website health. [Monitoring](monitoring.md).
- **Operational rollout:** phase-oriented documents from early 2026 are archived history, **not** today's step-by-step operator workflow. Start with [current playbook](distillator_migration.md).

## Keeping this guide current

After a meaningful feature tranche, update the corresponding row above, link its detailed document, and record whether it is **implemented / staged / deployed / enabled / validated**. Update the release ledger with real SHA evidence at deployment time. Keep detailed mechanics in their existing documents; use this file as the one-page navigation index plus critical release cautions. For every contested comparison, capture its source commit, date, selected sites, input provenance and whether the result is partial.

**See also:** [Condenser docs directory](.) · [GitHub changes](https://github.com/culturecreates/footlight-condenser/compare/main...harden-dsl-reliability) · [Console repository](https://github.com/culturecreates/footlight-console).
