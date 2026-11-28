# Place des Arts: production ResourceList sitemap shards (2026-11-27)

Correction to the earlier single-shard-vs-all-Console comparison.
Evidence: two user-supplied production UI exports, **not a fresh sitemap fetch**.

| Webpage | ResourceList URL | RDF URI |
|---|---|---|
| 43997 | https://www.placedesarts.com/sitemaps-1-section-event-1-sitemap-p1.xml | footlight:placedesarts-com_calendrier0 |
| 213113 | https://www.placedesarts.com/sitemaps-1-section-event-1-sitemap-p2.xml | footlight:placedesarts-com_calendrier1 |

The supplied Statement export is **only for calendrier1** (second sitemap):
selected URL Source 4600 (Statement 3708536) and URI Source 4601
(Statement 3708535), each refreshed 2026-11-27 22:46:02 EST.
The URL Source contains 466 distinct URL values. The separate
Console inventory reports 973 Upcoming Events.

| Exact URL comparison against second sitemap only | Count |
|---|---:|
| Console and calendrier1 | **454** |
| Only in calendrier1 | **12** |
| Only in Console relative to calendrier1 | **519** |

**The 519 cannot be called missing discovery.** The first sitemap
(calendrier0) has not been included in the comparison. The p1 cache
count, overlap between p1 and p2, and union size remain unverified.
The 12 second-shard URLs missing from Console are reconciliation
candidates, not necessarily import failures or upcoming events.

## Reliability implications

1. The configured production discovery route is the two XML sitemap
   ResourceLists, not the site's filtered Algolia programming UI.
2. Compare URL/URI identities from the union of both sitemap Statements
   with Console, preserving historical Events and last-good cache.
3. Inspect the **actual sitemap index**, if any, for event shard references.
   A new p3 must be observed, not inferred from filename patterns.
4. Verify that a failed shard fetch does not clear existing Statements
   or trigger destructive reconciliation.
5. Keep the existing Source DSL and Artsdata/Databus identities unchanged.

The previous proposed P0 classification based on 973-vs-466 was
**unsupported**. Current sitemap discovery coverage remains unverified
until both shards and any index-listed successors are examined.

This is documentation only. No source code, fetch, import, archive,
cache, or production behavior changed.
