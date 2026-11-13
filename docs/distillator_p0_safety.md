# Transition P0 safety fixes

The serving cache now validates the successful body's backend, request method, rendering and URL-rewriting profile before reuse. A mode/profile mismatch forces a fetch through the requested path. If that fetch fails, content from the previous engine is not returned as a last-good fallback. Failures within the same profile still preserve the previous successful body and its provenance.

Successful writes record `signals.body_profile`; failed writes do not relabel a preserved body as belonging to the failing attempt's backend. Shadow responses are identified as legacy/Wringer content. Existing URI keys remain compatible.

Historical entries without body provenance are refreshed on their next access. Expect additional fetches on the first access after deployment and when switching modes. The current single cache slot can still be replaced by diagnostic fetches; subsequent serving requests validate its profile and refetch when necessary. Fully separate immutable diagnostic snapshots belong to the follow-up evidence/run work.

Across sampled URLs, blocking comparisons take precedence over review differences and unavailable lookup metadata. Missing/unknown comparisons cannot be downgraded by a review result on another URL. A later failed cache attempt supersedes earlier passing fetch evidence for promotion readiness and lowers confidence.

Run with the normal Rails/PostgreSQL test environment:

```sh
bin/rails test test/services/distillator/p0_transition_safety_test.rb test/services/distillator/fetch_cache_store_test.rb test/services/distillator/transition_status_test.rb test/services/distillator/transition_check_runner_test.rb
```

The focused safety tests are also included in `test:distillator_fast`. No database migration or rollout-mode change is needed. The separate P1 evidence-run, audit-atomicity and semantic-parity findings remain follow-up work.
