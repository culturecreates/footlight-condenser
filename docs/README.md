# Documentation map for targeted agent work

Use this index to select **only the documents relevant to the task**. Files under `docs/` contain both live contracts and historical planning/audit records. Their presence does not require reading them before every change.

Start with the affected source code and tests. Read the contract relevant to a change, and consult a historical audit only to resolve a specific compatibility question. If a document and executable behavior disagree, investigate the discrepancy rather than silently treating either as proof of intended behavior.

| When changing… | Read first (as relevant) | Additional references when needed |
| --- | --- | --- |
| Wringer-compatible fetches, cache, HTTP/renderer behavior | [Cache compatibility contract](distillator/cache_compatibility_contract.md), [Distillator/Wringer parity](distillator_wringer_parity.md) | [Wringer compatibility matrix](distillator/wringer_compatibility_matrix.md), [Phase 1 readiness](distillator_phase1_wringer_readiness.md) |
| Migration modes, qualification, validation and recovery | [Transition workflows](distillator_transition_workflows.md), [Transition check scope](distillator_transition_check_scope.md) | [Transition report states](distillator_transition_report_states.md), [P0 safety](distillator_p0_safety.md), [P1 integrity](distillator_p1_transition_integrity.md), [Rollout modes](rollout_modes.md) |
| Website Action/Information dashboards and ResourceList evidence | [Website overview](website_index.md), [Transition workflows](distillator_transition_workflows.md) | [Monitoring](monitoring.md), [Preprocessing/refresh](preprocessing_refresh.md) |
| DSL interpretation, refresh, source extraction and library | [DSL production accumulation contract](dsl_production_accumulation_contract.md), [DSL library](dsl_library.md) | [Preprocessing/refresh](preprocessing_refresh.md), [DSL URL placeholders](dsl_url_placeholders.md), [DSL library analysis](dsl_library_analysis.md) |
| Artsdata/Databus/JSON-LD export and replay | [Databus replay](databus_replay.md), [Events JSON contract](events-json-contract.md) | [Comparison parity/runtime](distillator_comparison_parity_and_runtime.md), relevant `test/integration/` and `test/services/distillator/*export*` tests |
| Operator procedures and staging rollout | [Migration operator guide](distillator_migration.md), [Full migration staging plan](distillator_phase1_full_migration_staging_plan.md) | [Staging acceptance report](distillator_phase1_staging_acceptance_report.md), [Phase 1 rollout](distillator_phase1_rollout.md) |

## Historical status and investigations

These are useful when their specific history is relevant, not as default context for new code edits:

- [Phase 1 shadow observations](distillator_phase1_shadow_observation.md) and [Phase I status](distillator_phase_i_status.md)
- [Phase 1 Wringer readiness](distillator_phase1_wringer_readiness.md) and [Wringer compatibility matrix](distillator/wringer_compatibility_matrix.md) for legacy audit evidence
- [Comparison parity and runtime investigation](distillator_comparison_parity_and_runtime.md)
- [Encoding and activation display](distillator_encoding_and_activation_display.md)
- [Migration contract template](migration/contract_template.md) when writing a new contract
- [Runtime versions](runtime_versions.md) when changing dependencies or environments

## Avoid default loading of large assets

The following are not introductory reading material:

- `latest.dump` (database dump)
- `data/migration_baseline/` (export comparison snapshots)
- `test/fixtures/files/artsdata-dump.nt`
- `test/vcr_cassettes/`
- Full test/controller files when a narrow test or code search is sufficient

Load these only when running or debugging a matching replay, data-parity or fixture-based test. Do **not** delete or weaken them merely to reduce agent context usage.

## How to keep context economical

1. Find the target symbols, their callers, and tests via narrow search.
2. Read this index and open at most the directly pertinent contracts; expand only when a mismatch requires it.
3. Inspect diffs and limited failing test output on subsequent iterations, rather than reposting the same files.
4. Preserve existing contract checks and report which tests actually ran.

Use [../README.md](../README.md) for repository setup and test commands.
