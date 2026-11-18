# DSL Library

Open **DSL Library** beside Options. The migration seeds eleven reusable entries, with a revision-1 history record. See [export analysis](dsl_library_analysis.md) for exact frequencies and exclusions.

Read-only source DSL and library previews use pale instruction backgrounds: rose for extraction, alternating green/blue for Ruby, amber for URL/API navigation, and lavender for complete library tokens. Colors identify instructions, not success or failure. Ruby alternation restarts for each algorithm. Text stays dark, with slightly bolder instruction prefixes and no per-step borders.

Highlighting preserves the original characters, whitespace and semicolons and does not expand tokens or execute instructions. Editing fields remain plain text.

```text
$$META_TITLE$$
;$$A_SQUISH$$
;$$A_UNIQ$$
```

A token must occupy a complete pipeline step. Its body can contain one instruction or a semicolon-separated pipeline, including other library tokens. Expansion occurs before execution and uses a single database snapshot per run. It does not start a separate runner, reset $array, flatten values, squish XPath results or alter legacy accumulation. `$$SELF_URL$$` is reserved for URLs and cannot be a library entry. Tokens inside Ruby strings or XPath expressions are not instruction macros.

`A_DROP_FIRST` (formerly `ARRAY_FIRST`) is the conditional saved-first-element helper, not `.first`. `A_DROP_FIRST_ALWAYS` (formerly `ARRAY_DROP_FIRST`) unconditionally executes `.drop(1)`. Check the input shape in a trace before adopting either. The rename migration preserves environment-local bodies, including operator-added type guards.

Editing an entry changes future executions of all direct and nested users. Body edits do not rewrite source algorithms or refresh stored statements automatically. Renames update complete token references as described below. The editor shows literal source references and revision history. Token names are editable. Renaming atomically updates complete token steps in source algorithms and other library bodies, preserving whitespace and leaving literal strings and URL placeholders untouched. Previous names remain reserved aliases, so in-flight or copied algorithms keep working. Name and body changes create revisions; historical revision bodies are never rewritten. Reusing another entry’s old name is rejected. No delete action is provided. Concurrent edits use optimistic locking and return a conflict instead of overwriting another operator's changes.

Unknown names, circular references and excessive expansion return a structured LibraryExpansionError before executing the pipeline. Depth is limited to 16, expanded instruction count to 1000 and expanded text to 1 MB. The original semicolon parser remains authoritative: arbitrary Ruby code containing semicolons has the same limitations as before.

Raw trace events retain expanded instruction code with library name/revision provenance. Databus replay records the used library bodies, revisions and hashes in source-level `library_evidence`, so its raw source hash is not mistaken for a complete record of expansion. Compact browser-session trace formatting may omit provenance; library revision history and replay evidence are the audit records. A snapshot covers one runner execution, not an entire multi-page transition batch. Library edits should not be made during a comparison intended to freeze all sources.

Library bodies execute with the same operator trust and permissions as source DSL. Expansion is not a sandbox. The editor uses the existing Condenser operator authentication. Site-specific reconciliation, pricing, date/time and platform fallbacks should be introduced only with representative input fixtures. Existing sources are left unchanged for controlled adoption.

Deploy and run `rails db:migrate`. No external service or scheduler is required. Starter entries are created independently in each environment; subsequent library edits are environment-local database data and must be deliberately synchronized if staging and production must use the same revision.

## Built-ins and shorter array names

The library page shows the reserved `$$SELF_URL$$` URL placeholder separately, with its resolved app origin (no trailing slash) and a usage example. It uses the same resolver as DSL execution, including environment defaults and optional overrides. It is not an editable library entry and cannot be used as a standalone pipeline step. `CURRENT_URL` is only shorthand for `ruby=$url`, which returns the current source page URL. The unchanged starter shorthand appears in a closed optional section; existing references continue to work.

Run `rails db:migrate` after deployment to shorten array instruction names:

| Previous name | Current name |
| --- | --- |
| `ARRAY_SAVE` | `A_SAVE` |
| `ARRAY_SQUISH` | `A_SQUISH` |
| `ARRAY_UNIQ` | `A_UNIQ` |
| `ARRAY_FIRST` | `A_DROP_FIRST` |
| `ARRAY_DROP_FIRST` | `A_DROP_FIRST_ALWAYS` |

Other canonical `ARRAY_` names become `A_` names. Already renamed instructions are preserved. All renames and complete source/nested-library reference updates occur in one transaction; a canonical-name or alias collision aborts the migration without overwriting anything. Old names remain aliases and historical revisions remain intact. Repeating the operation is a no-op. No statement refresh, cache update, schedule change or HTTP request is triggered.

The data migration cannot automatically be reversed, because doing so could undo later operator edits. Earlier code can continue using the retained aliases; use the normal library editor if a canonical name needs to change again.
