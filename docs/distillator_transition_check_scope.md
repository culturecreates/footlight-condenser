# Choosing transition check scope

Open a website and use **Transition batch check**. These controls belong to the
individual check, rather than the general Options page.

| Control | Choices |
| --- | --- |
| Event sample | Default sample, a fixed number (1–1000), or all publishable event pages |
| Field comparison | Standard or Strict |

The default sample is unchanged: 20%, minimum five, maximum 25, or all pages when
fewer than five exist. For Petit Théâtre's nine publishable events, choose **All**
to check nine instead of five. Explicit counts and All bypass the default cap of 25.
If no publishable event pages exist, the existing fallback to other website pages
still applies. Future/undated/past event selection order remains deterministic.

Both field policies compare all selected sources. Standard makes Title, Dates and
Location differences blocking; other differences produce warnings. Strict makes
differences in any selected field blocking. It does not require every optional
field to exist: matching absent optional values still agree. Missing required core
values, unavailable snapshots, unsupported nested fetches and incomplete coverage
cannot become passing checks.

Options are saved immutably on the transition run and copied into phase evidence.
The worker reads them from the run, independently of browser preferences. A second
identical request reuses the active run; a different scope is rejected with a clear
message instead of silently running a smaller check. Completed results show their
own scope, separately from a newly requested check. Reviewed activations include
the run's options in their audit snapshot. Rollout mode is unchanged by a check.

Large checks stop before the existing one-hour run lease expires. Selected,
fetched and compared counts remain separate; incomplete work cannot claim full
coverage or authorize activation. No stored statements are updated by the checks.

The task accepts the same policies:

```sh
SAMPLE_MODE=all STRICTNESS=strict bin/rails 'distillator:transition:check[134]'
SAMPLE_MODE=count SAMPLE_SIZE=50 bin/rails 'distillator:transition:check[134]'
```

Run `bin/rails db:migrate` when deploying this change. The migration adds the
`check_options` JSONB column to transition runs, with `{}` preserving historical
default behavior. Existing phase evidence and rollout decisions are not rewritten.

# Messages

The Messages index is paginated at 100 rows by default, newest first with ID as a
stable tie-breaker. The Site filter matches the Databus callback artifact exactly
to the website seedurl. Pagination preserves the selected site and filter changes
start at page one. Historical artifact keys remain selectable after website deletion.
The JSON index uses the same filtering and pagination without changing its array
response structure. Callback ingestion is unchanged; no message migration is needed.
