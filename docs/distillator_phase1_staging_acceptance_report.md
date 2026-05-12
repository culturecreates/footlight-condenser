# Distillator Phase 1 Staging Acceptance Report

Use this report to record the result of the full-migration staging validation.

## Run Metadata

- Date/time window:
- Commit SHA:
- Migration version:
- Environment:

## Test URLs Used

- Known HTML URL:
- Known JSON URL:
- Safe JSON POST target:
- Known 404 URL:
- Unsafe URL test:
- Escaped URI used for `/websites.json?term`:

## Endpoint Smoke-Test Results

| Check | URL or command | Result | Notes |
|---|---|---|---|
| raw `/websites/wring` | `GET /websites/wring?uri=<known-url>&format=raw` |  |  |
| json `/websites/wring` | `GET /websites/wring?uri=<known-url>&format=json` |  |  |
| `/websites.json?term` lookup | `GET /websites.json?term=<escaped-uri>` |  |  |
| force_scrape behavior | `GET /websites/wring?uri=<known-url>&format=json&force_scrape=true` |  |  |
| force_scrape_every_hrs behavior | `GET /websites/wring?uri=<known-url>&format=json&force_scrape_every_hrs=1` |  |  |
| absolute_src behavior | `GET /websites/wring?uri=<known-url>&format=raw&absolute_src=true` |  |  |
| json_post behavior | `GET /websites/wring?uri=<safe-json-post-target>&format=json&json_post=true` |  |  |
| PhantomJS missing-key fallback | `GET /websites/wring?uri=<known-url>&format=json&use_phantomjs=true` |  |  |
| 404/stored failure behavior | `GET /websites/wring?uri=<known-404-url>&format=json&force_scrape=true` |  |  |
| unsafe URL blocked behavior | `GET /websites/wring?uri=http://127.0.0.1&format=json` |  |  |

## Export Validation Result

- Representative website:
- Export command:
- Prior known-good output used:
- Comparison result:
- Expected differences reviewed:
- Unexplained `final_url` changes:
- Unexplained `redirect_chain` changes:
- Unexplained 404 changes:

## Cache Record Count

- Before:
- After:
- Net new records:

## Blocked Fetch Review

- Count:
- Sample URLs:
- Expected or unexpected:
- Notes:

## Failed Scrape Review

- Count:
- Sample URLs:
- Error types:
- Signals/hints examples:
- Notes:

## Decision

- Decision: accept / reject / accept with follow-ups
- Decider:
- Decision timestamp:
- Rationale:

## Follow-Up Tasks

- [ ] 
