# Production DSL accumulation contract

The authority for existing source algorithms is the non-traced production
`StatementsHelper#process_algorithm` on the repository's main branch. Its old
tracing implementation is not an alternative specification. Traced and ordinary
execution now use the same accumulating runner. Existing source #7023 is kept
unchanged in a regression fixture; no source migration or database update is needed.

| Instruction | Result behavior |
| --- | --- |
| XPath, CSS, matching if_xpath | Append each node's exact text, including whitespace and empty strings |
| xpath_sanitize | Append each sanitized HTML result |
| json | Parse current input and append one evaluated value, retaining nested arrays and nil |
| time_zone | Append its marker |
| sparql | Append the answer(s), then flatten the result array |
| ruby | Replace results with its expression value, including nil or an explicitly empty array |
| url, renderjs_url, json_url, post_url | Navigate while preserving collected results |
| unless_xpath | Preserve results or halt with previously collected results |
| api | Replace with the parsed response, as before |

`ruby=[$array]` creates a new outer array containing the previous results. The next
extraction appends to that outer array; `.drop(1)` then discards the saved group.
Extraction does not implicitly flatten, strip, squish, or remove blank slots.

Trace events copy their values at recording time, so a later append cannot alter
an earlier step's displayed output. Empty-XPath probes inspect the new match set,
not whether the accumulator already contains data. Probes remain diagnostic only.

## Validation and rollout

Regression cases cover exact whitespace/empty slots, nested groups and drop,
CSS, conditional extraction, sanitized values, JSON arrays/scalars/nil, repeated
JSON parsing, time zones, SPARQL flattening, Ruby replacement, navigation, tracing,
and the supplied Joliette algorithm without any rewrite. The Joliette sold-out
fixture must produce the four existing SoldOut values; the available fixture
preserves the original source's tariff-to-URL business rule. That separate business
rule is not silently corrected during interpreter restoration.

The differential suite loads a frozen copy of the historical non-traced method
from commit `fde44ced8d8b83216d45cbf03cbbf2f2252427b0` in a test-only evaluator.
Its I/O dependencies receive the same fixture HTML as the corrected runner.
Both traced and ordinary execution are checked against this independent oracle,
including recursive types, ordering, nesting, explicit Ruby replacements and
error class/failing instruction. Error payload wording is deliberately not required
to match the old renderer. The frozen evaluator is never used by application code.

The supplied FASS #219 algorithm protects four CSS selections followed by date
pairing. The supplied Vieux Noranda #1716 algorithm protects JSON-LD script
indexing and timezone accumulation through the real datetime formatter. A winter
date must remain non-empty and become `2026-11-20T20:00:00-05:00` in the fixture.
Additional patterns cover parallel performer links, nested/drop logic, pagination,
multiple JSON instructions and exact blank/whitespace preservation.

Culture Mauricie Price #7870 is also preserved unchanged in a fixture. The old
and new evaluators receive identical HTML and rates JSON across navigation back
to the original page. Array rates, a single rate object, nil prices and multiple
tariffs are covered, with tracing enabled and disabled. These are controlled
inputs, not recovered historical rates responses. Agreement does not by itself
explain the live `37.74` versus `42.99` discrepancy; cached input timestamps,
source versions and historical refresh evidence still need separate review.

The export's reported 38 compatibility-sensitive sources indicate investigation
scope, not 38 established failures. These fixtures do not execute all 1,308
definitions or establish live production parity for every source. Revalidate
Vieux Noranda's selected outputs against production before further promotions,
especially Dates #1716, then rerun Joliette with #7023 unchanged.

New transition evidence records `dsl_contract_version: production_append_v1`.
The contract version participates in comparison fingerprints. Results produced
under the replacement interpreter remain historical and cannot certify activation
under this corrected interpreter. In-flight checks with an older fingerprint
cannot publish a ready result. Existing rollout modes and statements are untouched.

After deploying, validate source #7023 on a small targeted Joliette sample before
another full run. Reviewed shared 404s remain a separate lifecycle decision.
Do not replace source #7023 merely to accommodate the interpreter regression.

Reference:
https://github.com/culturecreates/footlight-condenser/blob/fde44ced8d8b83216d45cbf03cbbf2f2252427b0/app/helpers/statements_helper.rb

## Gatineau End Date source 4264

The approved source rule is calendar-based: only a continuous multiday interval
(`Du ... au ...`) yields an explicit End Date, with no time component. Same-day
events and separate performances yield no explicit End Date, even when they have
closing times or AddEvent end markup. Repeated intervals sharing one ending date
are deduplicated. Reversed intervals, invalid dates and multiple distinct ending
dates produce an abort rather than a guessed value.

The operator-supplied replacement is preserved verbatim in
`test/fixtures/dsl/gatineau_multiday_end_date.dsl`. The independent differential
suite exercises this exact script through the historical evaluator and both
traced and ordinary current execution. It covers date-only intervals, times
ignored within an interval, year boundaries, leap dates, duplicate ending dates,
same-day intervals, separate performances and each validation failure. Its result
for event 46121's interval is `["2027-04-25"]`.

The original source remains a separate historical fixture. Both evaluators
returned `[["dimanche 25 avril 2027"]]` when its optional AddEvent `if_xpath`
halted before an unwrapping step. This establishes the original defect without
changing general DSL control flow or nested-array semantics. The selected source
has now been replaced by the operator's multiday-only policy. Time-of-day is
never emitted by this source.

The source replacement does not clear existing statement caches. Normal refresh
preserves an existing value when extraction is blank, so stale End Dates for
same-day events or separate performances need a separately reviewed cleanup.
The read-only replay regenerates values without substituting those caches and
does not perform that cleanup. Record the new algorithm hash when replaying.

This source rule is separate from the EventSeries serializer's generated overall
range metadata, which can derive an end boundary from the last occurrence's start
date even when there is no explicit End Date source value. These tests do not
change that serializer behavior or the site's rollout mode.
