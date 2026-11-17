# Initial DSL Library analysis

Source: operator upload `Pasted text(20261117-172633).txt`. SHA-256: `5cc31656cbcc50186343357deac1801e6d56831f2374adea028e5bda399a8469`.

Parsed 3,573 tab-separated source definitions across 97 website labels; 3,560 marked selected. These are source definitions, not necessarily unique algorithms or successful executions. Counts below use exact instruction strings and the existing semicolon split contract, not Ruby-aware parsing. Multiline fields and all six columns were parsed; no rows were dropped.

## Seeded entries

| Token | Exact occurrences | Distinct websites | Contract |
|---|---:|---:|---|
| `META_TITLE` | 16 | 11 | Append Open Graph title matches; does not clear prior results. |
| `META_IMAGE` | 24 | 24 | Append Open Graph image URLs. |
| `META_DESCRIPTION` | 4 | 3 | Append Open Graph descriptions. |
| `HTML_TITLE` | 99 | 54 | Append document title matches. |
| `JSON_LD_SCRIPTS` | 24 | 5 | Append script text only; no assumption about JSON object, array or @graph shape. |
| `CURRENT_URL` | 171 | 81 | Replace results with the current URL string. |
| `ARRAY_UNIQ` | 30 | 22 | Remove duplicate values, preserving order and nested value types. |
| `ARRAY_SQUISH` | 10 | 6 | Normalize whitespace on string elements. Requires an array of strings. |
| `ARRAY_SAVE` | 1 | 1 | Preserve current state as one nested element before more accumulating extraction. |
| `ARRAY_DROP_FIRST` | 3 | 2 | Remove the first outer element; distinct from ARRAY_FIRST. |
| `ARRAY_FIRST` | 0 | 0 | Operator-supplied instruction: drop the saved first element only when size > 1, then squish remaining strings. Does NOT mean return .first. |

`ARRAY_FIRST` is the operator's requested name and exact code, not a synonym for `.first`. It does not occur verbatim in this export. Do not replace `.drop(1)`, `.first`, or nested-array variants with it without inspecting types and behavior. `ARRAY_SQUISH` counts only its exact spelling; whitespace/block-variable variants make this a broader family, but automatic textual normalization is unsafe for arbitrary Ruby.

## Good later candidates

Ovation-family title extraction (`xpath=//h1[@class='ligne_titre color_a']`) appears 30 times across 15 websites. Ovation description extraction (`xpath_sanitize=//div[@id='TextePresentation_complet']`) appears 15 times across 15 websites. These deserve platform-prefixed entries after representative HTML tests, rather than generic names implying compatibility with every site.

Repeated multi-step blocks are also significant:

| Candidate family | Exact repeated blocks | Websites | Recommendation |
|---|---:|---:|---|
| Ovation description selection + newline removal + join | 15 | 15 | Strong next platform-specific macro after HTML fixtures |
| Ovation image URL extraction + default-image fallback | 15 | 15 | Separate useful URL extraction from the questionable hardcoded fallback |
| Ovation ticket button extraction + nested-array handling | 15 | 15 | Preserve array shape; test empty, one and multiple ticket/date values |
| Ovation date XPath + French date cleanup | 14 | 14 | Needs timezone and multi-date fixtures before sharing |
| ImprimableEnsemble links + uniq | 14 | 14 | Good platform-scoped discovery macro after representative link fixtures |
| Ovation category cleanup, two variants | 7 and 6 | 7 and 6 | Compare the Stationnement-removal difference; do not collapse blindly |

These counts concern exact adjacent two/three-step sequences under the existing parser. They do not establish runtime correctness or platform identity independently of source context.

Repeated category and date pipelines also exist, but differ in XPath branches, nested state, timezone treatment and fallbacks. They need platform fixtures before sharing. JSON-LD extraction is seeded only as script selection; JSON parsing is not standardized because objects, arrays, @graph nodes, language fields and missing performers differ.

## Excluded from the initial library

- 2,130 `manual=` placeholders across 80 websites: frequency does not make an empty placeholder a useful abstraction.
- Site-specific performer/organizer fallbacks and ticket-price logic: reconciliation, cancellation, missing values and last-good preservation are materially different.
- Manual constants and timezones: not interchangeable with extraction; timezone append semantics remain intact.
- Blank XPath templates, hardcoded image fallbacks and event-status guesses: do not standardize placeholders or questionable defaults.

No existing source algorithms are rewritten. The initial migration creates the entries only. Adoption should start with a few selected sources, compare explicit versus expanded results on identical HTML/state, then expand after review.
