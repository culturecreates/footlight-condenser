# Environment-relative DSL URLs

Use the same source algorithm in staging and production:

```ruby
api="$$SELF_URL$$/statements.json?source=8039&seedurl=culturemauricie_lepointdevente-com-RList"
;ruby=JSON.parse($array.first['cache'])
```

`$$SELF_URL$$` defaults to this app's origin, with no trailing slash. URL instructions also accept `$$SELF-URL$$` as an alias for existing sources. Resolution priority:

1. Optional `CONDENSER_PUBLIC_URL` override.
2. Heroku's `HEROKU_APP_DEFAULT_DOMAIN_NAME` runtime metadata, when available.
3. The known staging or production origin below, based on the app environment.
4. Development defaults to `http://localhost:3000`.

Defaults for the existing apps:

- Staging: `https://footlight-condenser-test-c24c162bb7c8.herokuapp.com`
- Production: the production Condenser origin, e.g. `https://footlight-condenser.herokuapp.com`
- Development: e.g. `http://localhost:3000`

The origin may have one trailing slash. Paths, credentials, query strings and fragments in the setting are rejected. The staging environment selects staging, never production. The scraped website and request Host headers are never used. Background workers use the same app identity as web requests. An override is needed only for a different/custom origin or an unidentified environment.

Expansion happens on resolved URL strings after Ruby evaluation, before URL normalization and validation. It works for `api`, `url`, `renderjs_url`, `post_url` and `json_url` through the shared URL resolver, including array URL candidates. It does not rewrite arbitrary Ruby code, add authentication, trigger upstream statement refreshes or change explicit existing URLs. `ruby=HTTParty.get(...)` is arbitrary Ruby and does not pass through this resolver. No other placeholder names are introduced.

An unidentified app or invalid override yields the existing structured DSL abort; it never silently chooses another environment. Existing algorithms are not changed automatically. Review the mapping APIs and consumers (including Gatineau source #4608) before replacing literal origins. A Databus replay still needs a captured API input for the resolved URL and must never fall back to live data.

Dedicated Resource List websites appear in a separate collapsible category on the website index. Classification uses a dedicated `-RList`/`_RList` or ResourceList suffix, or an explicit Resource List name; template/test categories retain precedence. Ordinary event sites are not moved merely because they contain discovery ResourceList webpages. This presentation change does not change refresh schedules. Preferred sites remain available in the Preferred view. Resource List sites are excluded from the existing event-only bulk transition selection.

The DSL Library page lists `$$SELF_URL$$` as a read-only built-in, with the effective origin from this same resolver. `$$CURRENT_URL$$` is a separate optional library shorthand for `ruby=$url`; it returns the current scraped page URL, not this app origin.
