# DSL Library

Open **DSL Library** beside Options. The migration seeds eleven reusable entries, with a revision-1 history record. See [export analysis](dsl_library_analysis.md) for exact frequencies and exclusions.

```text
$$META_TITLE$$
;$$ARRAY_SQUISH$$
;$$ARRAY_UNIQ$$
```

A token must occupy a complete pipeline step. Its body can contain one instruction or a semicolon-separated pipeline, including other library tokens. Expansion occurs before execution and uses a single database snapshot per run. It does not start a separate runner, reset $array, flatten values, squish XPath results or alter legacy accumulation. `$$SELF_URL$$` is reserved for URLs and cannot be a library entry. Tokens inside Ruby strings or XPath expressions are not instruction macros.

`ARRAY_FIRST` deliberately preserves the operator's exact code: `ruby=$array.size > 1 ? $array.drop(1).map{|e| e.squish} : $array`. It is not `.first`, and it is not interchangeable with unconditional `ARRAY_DROP_FIRST`. Check the input shape in a trace before adopting either.

Editing an entry changes future executions of all direct and nested users. Body edits do not rewrite source algorithms or refresh stored statements automatically. Renames update complete token references as described below. The editor shows literal source references and revision history. Token names are editable. Renaming atomically updates complete token steps in source algorithms and other library bodies, preserving whitespace and leaving literal strings and URL placeholders untouched. Previous names remain reserved aliases, so in-flight or copied algorithms keep working. Name and body changes create revisions; historical revision bodies are never rewritten. Reusing another entry’s old name is rejected. No delete action is provided. Concurrent edits use optimistic locking and return a conflict instead of overwriting another operator's changes.

Unknown names, circular references and excessive expansion return a structured LibraryExpansionError before executing the pipeline. Depth is limited to 16, expanded instruction count to 1000 and expanded text to 1 MB. The original semicolon parser remains authoritative: arbitrary Ruby code containing semicolons has the same limitations as before.

Raw trace events retain expanded instruction code with library name/revision provenance. Databus replay records the used library bodies, revisions and hashes in source-level `library_evidence`, so its raw source hash is not mistaken for a complete record of expansion. Compact browser-session trace formatting may omit provenance; library revision history and replay evidence are the audit records. A snapshot covers one runner execution, not an entire multi-page transition batch. Library edits should not be made during a comparison intended to freeze all sources.

Library bodies execute with the same operator trust and permissions as source DSL. Expansion is not a sandbox. The editor uses the existing Condenser operator authentication. Site-specific reconciliation, pricing, date/time and platform fallbacks should be introduced only with representative input fixtures. Existing sources are left unchanged for controlled adoption.

Deploy and run `rails db:migrate`. No external service or scheduler is required. Starter entries are created independently in each environment; subsequent library edits are environment-local database data and must be deliberately synchronized if staging and production must use the same revision.
