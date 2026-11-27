# Danse Danse shadow parity — strict pre-URI acceptance test

This is a **staging-only test plan**, not an already executed staging comparison. The trial must run against copies of the *same* PostgreSQL staging snapshot. It must not create a second Website in the existing database: Statement callbacks may update archive dates for all pages sharing an rdf_uri, including across sites.

## Immutable input and baseline

1. Take a named staging database backup/snapshot. Restore it to two isolated databases, **baseline** and **trial**, using the same code/dependencies. Pause jobs/schedulers on both.
2. Capture the legacy site's full bilingual ResourceLists and their selected source settings. Fetch/cache both calendars **once** with equivalent fetch options; preserve all language-specific pagination HTML and evidence. A missing or failed page makes trial inconclusive, not complete.
3. On baseline DB, execute the *existing* selected Danse Danse ResourceList algorithms and refresh all relevant event statements (if a full refresh is required), without changing any algorithms or selection flags. Keep the pre-run DB backup so the baseline can be repeated.
4. Execute `bin/rails runner script/danse_danse_shadow_parity.rb capture /tmp/danse-danse-baseline.json` with DATABASE_URL pointing to **baseline**. This is read-only and includes every non-ResourceList page, its rdf_uri/language/archive_date, all selected event/non-ResourceList statement cache/status/manual flags, non-ResourceList source configuration, and the site's Artsdata export.
5. Run `DANSE_EN_HTML=/tmp/en1.html[,/tmp/en2.html] DANSE_FR_HTML=/tmp/fr1.html[,/tmp/fr2.html] bin/rails runner script/danse_danse_keyed_trial.rb /tmp/danse-danse-keyed-manifest.json` with DATABASE_URL pointing at the *trial*. This is a read-only **discovery** comparison: card-relative XPath, URL slug as current Danse Danse key, full cross-language matching, existing rdf_uri conflicts, and Source #1340 URL differences. Preserve the manifest and its digest.

## The actual comparison gate, not yet wired

6. In the trial DB **only**, replace the existing Source #1340 extraction through the new `get_sorted_calendars` DSL, keeping its selected flags and the rest of the site, sources, statements, and existing RDF URIs unchanged. The new DSL instruction and shared refresh context are NOT implemented in this PR yet. Do **not** treat the read-only manifest as a full shadow run.
7. Execute the same ResourceList/URI reconciliation and final event statement refresh sequence on the trial DB using identical stored fetch responses (or clearly mark any non-reproducible network dependency as inconclusive).
8. Run `bin/rails runner script/danse_danse_shadow_parity.rb compare /tmp/danse-danse-baseline.json /tmp/danse-danse-report.json` with DATABASE_URL pointing at trial. The comparator fails on any changes to website identity, non-ResourceList source config, webpage URL/rdf_uri/language/class/archive_date, selected statement cache/status/manual and selection flags, or normalized semantic Artsdata graph. It reports added/removed triples with examples.
9. **Pass requires zero non-ResourceList differences and zero added/removed RDF statements**, plus verified complete fetch/pagination evidence and preserved URI assignments. Discovery order alone is not semantically significant. Unmatched keys, different source counts, changed source inputs, or incomplete pagination block the parity claim.
10. Run unrelated export invariance / migration safeguard tests and keep the trial DB disposable. Do not migrate/import into the live staging site or merge based only on this script.

## Existing contracts involved

- `AddWebpagesJob` assumes aligned Webpage URL List and URI List arrays and creates immutable rdf_uri values for new URLs.
- `Distillator::TransitionEventInventory` retains list and definition digests and freshness/skew evidence.
- `Distillator::TransitionDiscoveryRefresh` refreshes ResourceLists, reconciles URLs, refreshes incomplete pages and verifies the resulting inventory.
- `Distillator::GraphDiff` compares RDF graphs from final JSON-LD exports.

Run unit tests (requires Rails development checkout / test database):

`bin/rails test test/services/resource_lists/keyed_calendar_alignment_test.rb test/services/resource_lists/keyed_calendar_extractor_test.rb test/services/distillator/website_shadow_parity_test.rb`

**Current limitation:** no access to the staging database or contemporaneous Danse Danse calendar HTML in this execution environment. The actual stage 6–9 parity result is **not measured**.
