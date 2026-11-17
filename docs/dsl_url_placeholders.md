# Environment-relative DSL URLs

Use the same source algorithm in staging and production:

```ruby
api="$$SELF_URL$$/statements.json?source=8039&seedurl=culturemauricie_lepointdevente-com-RList"
;ruby=JSON.parse($array.first['cache'])
```

Set `CONDENSER_PUBLIC_URL` independently on each deployment to its own externally reachable origin:

- Staging: `https://footlight-condenser-test-c24c162bb7c8.herokuapp.com`
- Production: the production Condenser origin, e.g. `https://footlight-condenser.herokuapp.com`
- Development: e.g. `http://localhost:3000`

The origin may have one trailing slash. Paths, credentials, query strings and fragments in the setting are rejected. There is no fallback to production, the scraped website, or request Host headers. Background workers use the same environment setting as web requests. Set it on every process executing DSL.

Expansion happens on resolved URL strings after Ruby evaluation, before URL normalization and validation. It works for `api`, `url`, `renderjs_url`, `post_url` and `json_url` through the shared URL resolver, including array URL candidates. It does not rewrite arbitrary Ruby code, add authentication, trigger upstream statement refreshes or change explicit existing URLs. `ruby=HTTParty.get(...)` is arbitrary Ruby and does not pass through this resolver. No other placeholder names are introduced.

Missing/invalid configuration yields the existing structured DSL abort; it never silently chooses another environment. Existing algorithms are not changed automatically. Review the mapping APIs and consumers (including Gatineau source #4608) before replacing literal origins. A Databus replay still needs a captured API input for the resolved URL and must never fall back to live data.

Dedicated Resource List websites appear in a separate collapsible category on the website index. Classification uses a dedicated `-RList`/`_RList` or ResourceList suffix, or an explicit Resource List name; template/test categories retain precedence. Ordinary event sites are not moved merely because they contain discovery ResourceList webpages. This presentation change does not change refresh schedules. Preferred sites remain available in the Preferred view. Resource List sites are excluded from the existing event-only bulk transition selection.
