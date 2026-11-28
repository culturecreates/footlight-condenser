# Tourisme Shawinigan — next-link pagination evidence (read-only)

## Scope

The public calendar is `https://www.tourismeshawinigan.com/evenements/`.
Historically configured ResourceList URLs were numbered through `?page=4`,
but their upper bound was **not** established as the site's last page.

On 2026-11-27 a public-page investigation observed the calendar's explicit
`PRÉCÉDENTS ÉVÉNEMENTS` and `PROCHAINS ÉVÉNEMENTS` controls.
The publicly indexed `?page=4` document has a **Next** link that resolves
to `https://www.tourismeshawinigan.com/evenements/?page=5`.
Pages 6–9 have also appeared in independently indexed public results.
This demonstrates that **page 4 is not a proven terminal page**.

Evidence sources (public URLs; cached snapshots were captured at different times):

- `https://www.tourismeshawinigan.com/evenements/?page=4`
- `https://www.tourismeshawinigan.com/evenements/?page=5`
- `https://www.tourismeshawinigan.com/evenements/?page=9`

**Important:** Public browsing uses cached versions from different dates, so
the observed page contents are **not** a coherent same-time 1–9 capture.
A reachable `?page=N` URL, HTTP 200, or an indexed page alone is not
ResourceList completeness evidence.

## Candidate strategy

This is an **explicit, labeled next-link chain**, unlike Le Point de Vente's
sliding-numbered-window evidence.

- Start from the configured first-page URL with the appropriate host/path and
  unchanged query filters. Do not assume the bare archive and `?page=1`
  produce byte-equivalent responses without comparison.
- Fetch each distinct URL once, within an explicit cap. Follow a matching
  observed `PROCHAINS ÉVÉNEMENTS` link to the next numbered page when valid.
  `NumberedPageQuery` must verify same origin, path, filter multiset and
  incremented `page` key. Do not promote an unrelated numeric anchor into a
  semantic Next link.
- A missing Next control is a **terminal candidate only** until validated
  against the actual saved HTML and the site's own navigation behavior.
  A disabled or fragment-only Next link must not be treated as a valid URL.
- Repeated page HTML/link inventories, a challenge, failed fetch, or the
  maximum-page cap all produce an **inconclusive** refresh.
- A 90% short-link page remains advisory; do not stop a valid next-link chain
  because of the heuristic.
- The **existing Source DSL** extracts all event URLs and fields. Pagination
  is not responsible for extracting event links or configuring a new XPath.
- Preserve last-good Source/Statement inventories and Artsdata/RDF identities
  until complete-chain and existing-DSL parity have been verified.

## Local read-only probe

The current generic numbered probe measures whether a matching link to
`page+1` exists; it does **not** yet attest that that link is the labeled
`PROCHAINS ÉVÉNEMENTS` control. This distinction must be checked from
the saved HTML before implementing terminal logic.

```bash
bundle exec ruby script/resource_list_numbered_probe.rb \
  'https://www.tourismeshawinigan.com/evenements/?page=1' \
  15 /tmp/resource-list-trials/shawinigan-numbered

jq '{
  stop_reason, verified_completeness,
  pages_fetched,
  captures: [.captures[] | {
    page, status, pager_window_numbers,
    next_page_number_link_observed,
    short_page_stop, repeated_links, repeated_content,
    challenge_hint
  }]
}' /tmp/resource-list-trials/shawinigan-numbered/probe.json
```

The live trial is deliberately bounded. The first 15 pages may not cover
the last page; `max_pages_reached` means **unverified**, not complete.
Inspect actual saved HTML around the labeled Next control at the boundary
with optional Analyze Page tooling **only when needed**. No changes to
production Resources, imports, archiving, scheduling or exports are made
by this probe.

## Outstanding

1. One coherent local capture showing the actual navigation chain,
   last Next-control state and effective response URLs.
2. Existing DSL extraction on captured pages and parity with prior data.
3. Atomic, last-good-preserving production activation as part of a separate
   verified implementation. PR #15 remains read-only.

## Operator-confirmed selected calendar boundaries (2026-11-27)

Two distinct filters were reported:

| Selection | Observed final page | Notes |
|---|---:|---|
| Unfiltered calendar | 11 | Applies only with no category selected |
| Culture category | 9 | `categories[0]=culture` |

The culture selection was observed at:

`https://www.tourismeshawinigan.com/evenements/?search_query&categories%5B0%5D=culture&page=9`

These endpoints were supplied from the operator's browsing observations.
An independent live fetch was unavailable, so they remain **capture-specific
observations**, not permanent page caps or independently verified termination
rules. The page counts may change with new or expired events.

**Critical URL contract:** The `search_query` parameter is supplied as a
bare key without `=`. The `categories%5B0%5D=culture` parameter must remain
present; it is not equivalent to the unfiltered calendar. A generic query
re-encoder could change `search_query` into `search_query=`, which is
semantically often but **not universally** equivalent. To avoid silent
behavior changes, `NumberedPageQuery#url_for` now updates **only the raw
page-value segment**, retaining the rest of the original query unchanged
(including percent-encoding, repeated parameters, and bare keys). URL
validation still compares the decoded filter **multiset**.

Targeted read-only trials, with independent outputs and no event XPath:

```bash
bundle exec ruby test/services/resource_lists/numbered_page_query_test.rb

bundle exec ruby script/resource_list_numbered_probe.rb \
  'https://www.tourismeshawinigan.com/evenements/?page=1' \
  12 /tmp/resource-list-trials/shawinigan-all

bundle exec ruby script/resource_list_numbered_probe.rb \
  'https://www.tourismeshawinigan.com/evenements/?search_query&categories%5B0%5D=culture&page=1' \
  10 /tmp/resource-list-trials/shawinigan-culture
```

Do not merge these Source inventories, hardcode pages 9 or 11 as permanent
limits, or treat HTTP 200 beyond either page as proof of additional events.
Only a coherent response chain, actual site navigation semantics, and
existing-DSL replay can support a last-good-preserving migration.



## Two bounded capture results (operator captures, 2026-11-27)

The operator completed two independent read-only captures. These are
**different Source/filter inventories**; do not merge their event counts,
terminal pages, page URLs, or last-good refresh results.

### Unfiltered calendar — pages 1–15

The run saved to `/tmp/resource-list-trials/shawinigan-numbered` followed
the unfiltered calendar probe discussed above. Verify the exact input URL
in `captures[0].url` before treating it as a fully specified Source contract.

| Page range | Valid numbered page anchors | Forward anchor to page+1 | Total HTML links |
|---|---|---|---:|
| 1 | [2] | yes | 82 |
| 2–10 | [page-1, page+1] | yes | 85 |
| **11** | [10] | **no** | **82** |
| **12** | [11] | no | 47 |
| 13–15 | [page-1] | no | 47 |

HTTP 200 was observed for all fifteen pages, including 12–15.
The pages 12–15 all had 197955 bytes, but the probe flagged neither
repeated content nor repeated link inventories. **Same byte count does
not prove same body**. The 90%-threshold short-page hint first fires
at page 12 (47/82 = 57.3%), not on page 11.

**Assessment:** Page 11 is a strong terminal **candidate**; page 12 is
apparently out-of-range. The observation does not establish semantic
Next-link identity or verify existing DSL extraction.

### Culture category — pages 1–10

The second capture used `/tmp/resource-list-trials/shawinigan-culture`
with the category-specific query:

`https://www.tourismeshawinigan.com/evenements/?search_query&categories%5B0%5D=culture&page=1`

| Page range | Valid numbered page anchors | Forward anchor to page+1 | Total HTML links |
|---|---|---|---:|
| 1 | [2] | yes | 82 |
| 2–8 | [page-1, page+1] | yes | 85 |
| **9** | [8] | **no** | **70** |
| **10** | [9] | no | 47 |

All ten responses returned HTTP 200, with no challenge, repeated-content,
repeated-link-inventory, or AJAX-shell flag. The 90%-threshold hint
fires on page 9 (70/85 = **82.4%**) and again on page 10
(47/70 = **67.1%**). This shows that **a genuine final-page
candidate may itself be short**. Short-page detection must remain
advisory and never be used to claim complete discovery.

**Assessment:** Page 9 is a strong terminal **candidate** for this
particular culture selection; page 10 appears out-of-range. It must
not inherit the unfiltered page-11 boundary.

### Architectural implication

Both probes reported `stop_reason=max_pages_reached` and
`complete=UNVERIFIED`. Their `candidate_event_urls=0` is expected,
because `EVENT_LINK_XPATH` was not configured and **the probe is not
the event extractor**. The existing Source DSL remains responsible
for event extraction, while the pagination collector verifies only
navigation and terminal evidence.

The next implementation-level proof is to distinguish the actual
`PROCHAINS ÉVÉNEMENTS` control from arbitrary numeric links on
captured pages, and then replay the **existing Source DSL** against
the saved pages. Preserve last-good state on inconclusive or failed
refreshes. Do not encode 9 and 11 as permanent page limits.


## Offline semantic Next audit (new diagnostic, no HTTP or DSL changes)

The numbered probe's `next_page_number_link_observed` is not evidence
that a **labeled Next** control was found. To inspect actual saved HTML
rather than introduce another extraction XPath or send new requests,
run:

```bash
git pull --ff-only origin feat/resource-list-capture-proof
bundle exec ruby test/services/resource_lists/labeled_next_evidence_test.rb

bundle exec ruby script/resource_list_semantic_next_audit.rb /tmp/resource-list-trials/shawinigan-numbered
bundle exec ruby script/resource_list_semantic_next_audit.rb /tmp/resource-list-trials/shawinigan-culture

jq -r '.captures[] | "page=\(.page) status=\(.status) label_target=\(.labeled_next_url // "-") conflicts=\(.invalid_labeled_targets | length)"' \
  /tmp/resource-list-trials/shawinigan-culture/semantic-next-audit.json
```

The audit uses anchor text/accessible labels, `title` or
`rel="next"` to recognize semantic navigation, and requires
the target to be same-origin, same-path, next-page and **same filters**
via `NumberedPageQuery`. It verifies the SHA-256 of every saved
`pageN.html` against the probe before analysis, detects contradictory
or changed-filter labels, and saves `semantic-next-audit.json`.

Expected **only if** the actual Next control's text or accessible
attributes is on its `<a>` element:
- Unfiltered pages 1–10: `labeled_forward_observed`; page 11:
  `no_forward_observed`.
- Culture pages 1–8: `labeled_forward_observed`; page 9:
  `no_forward_observed`.

If the label is not exposed in the anchor, the audit will report
`numbered_forward_only`; inspect the saved pager DOM manually before
promoting semantic Next evidence. A missing, invalid, or conflicting
label **never** certifies completeness. Out-of-range pages can also
have no forward links; the final page must be established by an
independent full-chain and existing-DSL parity check.

The diagnostic extracts **no events**, does not change the DSL, and
does not import, publish, archive or mutate ResourceLists or Artsdata.


## Semantic Next audit: confirmed results (operator run, 2026-11-27)

The operator ran `labeled_next_evidence_test.rb`: **14 runs,
26 assertions, 0 failures, 0 errors, 0 skips**. Both offline audits
completed successfully against the saved captures with no reported
labeled-target conflict.

| Selection | Pages with `labeled_forward_observed` | First `no_forward_observed` | Additional `no_forward_observed` |
|---|---|---|---|
| Unfiltered (`?page=N`) | **1–10**, each targets precisely `page+1` | **11** | 12–15 |
| Culture (`search_query&categories%5B0%5D=culture&page=N`) | **1–8**, each targets precisely `page+1` and preserves filters | **9** | 10 |

The offline audit compared saved file SHA-256 hashes against the original
read-only probe captures before interpreting navigation. The observed
Next links matched the expected same-origin, same-path, same-filter
`NumberedPageQuery` contract. The report status remains
`complete=UNVERIFIED` by design; the audit does not run the extraction DSL.

**Interpretation:** This confirms the intended **semantic Next-link
navigation strategy**, including filtered query preservation, and
strongly supports terminal-page **candidates** 11 and 9 for the two
independent selections. It also confirms that **no forward control
exists on out-of-range responses**, so `no_forward_observed` in isolation
is **not a terminal proof**. A future bounded collector must start from
the selected first page, maintain an unbroken verified navigation chain,
and then evaluate candidate terminal and failure evidence rather than
guess a fixed maximum or stop on the 90% HTML-link heuristic.

**Remaining migration gate:** Replay the **existing configured DSL** on
the saved pages, compare the resulting inventory and export identities
with last-good/Artsdata baselines, and verify that incomplete refreshes
cannot remove existing statements. Do not add an event XPath to the
pagination collector. No production fetch/import/archival behavior
changed in this PR.
