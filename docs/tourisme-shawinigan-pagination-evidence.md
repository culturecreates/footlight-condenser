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
