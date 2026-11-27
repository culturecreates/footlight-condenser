# Events JSON contract

`GET /websites/:seedurl/events.json` returns every matching event in one response:

```json
{"seedurl":"example-com","total_events":0,"events":[]}
```

`total_events` equals the length of `events`, after date/search filters and grouping by event URI. For 198 matching events the response contains 198 event objects and reports `total_events: 198`. Existing event fields and publishability rules are unchanged. `startDate`, `endDate`, `term`, `sort`, and `direction` still apply.

HTML pagination parameters (`page` and `per_page`) do not truncate JSON. Console needs the complete collection before calculating status counts, filtering, and applying its own pagination. Do not fix API truncation by raising the page-size limit or changing the count alone.

The HTML events page remains paginated, with the existing default of 25 and maximum of 100 rows per page. Its total counts all filtered results, including those on other pages.

Regression checks:

```sh
bin/rails test test/queries/events/index_query_test.rb test/controllers/events_controller_test.rb
```

Tests use more than 100 events to exercise both HTML limits. JSON must return the complete collection even with `page=2&per_page=100`; HTML must retain pagination. These are read-only operations and must not fetch or execute scraping.
