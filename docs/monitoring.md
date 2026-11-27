# Opt-in DSL monitoring

Monitoring is operational error reporting. Explicitly enrolled [preprocessing policies](preprocessing_refresh.md) also report refresh failures, stale results and stale inputs through this same issue store. These policy issues have independent resolution conditions; a normal DSL success cannot clear stale-input evidence. It does not change DSL extraction semantics, source selection, refresh schedules, publication, or rollout modes.

## Flag a particular error

Return the existing structured abort result, adding `notify: 'daily'`:

```ruby
ruby=
begin
  # Compute the normal value here.
  raise 'Audience mapping is stale' if mapping_is_stale
  audience_values
rescue StandardError => error
  ['abort_update', { error: error.message, notify: 'daily' }]
end
```

The example variables stand for the source's own calculations. Catch only the errors that need attention; an unflagged abort or exception retains its existing diagnostics and is not added to Monitoring. The flag is metadata in the existing abort payload, not a new DSL instruction. It never sends email directly.

Ordinary DSL issues are recorded only by actual statement refreshes. Running an extraction trace, cache comparison, transition comparison or Databus replay does not create or resolve operational monitoring issues. Existing good statement caches retain the normal abort protection.

An issue groups repeated flagged failures by webpage and source. The Monitoring page shows its message, site, property, source/statement links, occurrence count, first/last observation and resolution status. A successful saved refresh resolves it. A later flagged failure reopens the issue and starts a new occurrence count. Skipped manual statements, unflagged failures and blank-preserved refreshes do not claim recovery. Records retain identifying snapshots if a source or page is later deleted; deletion alone does not claim recovery.

## View issues

Condenser: `/monitoring` (existing operator authentication).

Console: Account → Monitoring (administrators only), on branch `dashboard-monitoring`. Console reads Condenser's authenticated `/monitoring.json`; Condenser remains the sole issue store. Both pages have site/status filters and 100 issues per page. A feed outage displays an unavailable message rather than an empty-success state. Console can be deployed after Condenser; before that, it displays unavailable.

## Scheduled event discovery

Websites with monitoring and a refresh schedule enabled track ResourceList
jobs through saved, verified extraction and import. **Last scheduled run** in
Websites shows when the scheduler queued the run. Inventory freshness shows
the verified list timestamp. Monitoring reports unsuccessful or overdue list
refreshes, incomplete imports, and listed events in the current archive window
that still lack publishable statements. Allow six hours for queued work and
newly imported event statements. A successful import is recorded only when the
verified list's event URLs exist on its target website.

On the first verified snapshot, monitoring establishes a list baseline. A
continuously listed archived event generates no issue. If an archived URL
disappears and later reappears across verified snapshots, monitoring logs the
observation and queues up to five read-only page checks per list refresh. The
probe uses the selected Dates source when its DSL can run against a single
fresh HTML snapshot. Ruby, nested fetches, static dates, and dates without an
explicit year provide no automatic confirmation. A possible missed event
appears in Websites and the digest when the fresh extraction finds a future
date inconsistent with the archive date. The issue resolves after a saved
Dates refresh and a corrected archive date. These observations do not update
event statements, archive dates, publication, or rollout modes.

The existing digest task also checks for overdue schedules and recovered
issues when the email mailbox is blank. The scheduler continues to queue
normal discovery and export jobs on its existing cadence.

## Optional daily email

In Condenser Options, save one **Monitoring mailbox**. This is a persistent server-wide setting, not a browser cookie. Leave it blank for page-only monitoring. The mailbox is never included in the issue API.

**Weekly monitoring pulse** is enabled by default and can be disabled independently in Options. It sends even when Monitoring has zero open issues. It uses exactly the same open issues (including preprocessing freshness problems) as the Monitoring page/API, includes counts per site, and excludes resolved or unflagged errors. It does not infer overall site health or prove that scheduled refreshes ran. The pulse goes to the same monitoring mailbox.

The existing daily task sends the pulse on its first execution in each Monday–Sunday week (America/Toronto). The pulse replaces the error digest on that day; the shared daily limit prevents a second monitoring email. On other days, an error digest is sent only if open flagged issues exist. No additional scheduler task is needed. A failed pulse delivery does not advance either the daily or weekly sent markers. If the task is not running, no pulse can be sent; this is not an independent external watchdog.

The digest includes all open monitoring issues, including scheduled discovery findings. Repeated observations of one statement form one entry. Unresolved issues remain in later daily digests as reminders. Resolved issues are omitted; no email is sent when none remain. The limit is one successful digest per America/Toronto calendar day for the whole installation, not one email per site. Changing the mailbox does not reset that limit.

Configure delivery on each deployment:

- `MONITORING_EMAIL_FROM`: verified sender address (required for email).
- `MONITORING_CONSOLE_URL`: absolute link to Console's Monitoring page (recommended).
- `MONITORING_SMTP_ADDRESS`, `MONITORING_SMTP_PORT` (default 587), `MONITORING_SMTP_USERNAME`, `MONITORING_SMTP_PASSWORD`.
- Optional `MONITORING_SMTP_DOMAIN`, `MONITORING_SMTP_AUTHENTICATION` (default plain).

SMTP settings are enabled only when `MONITORING_SMTP_ADDRESS` is present; an existing separately configured ActionMailer provider can also be used. Credentials remain in deployment configuration, never in Options or source DSL. STARTTLS and bounded connection/read timeouts are enabled for the monitoring SMTP configuration.

After deploying and running `rails db:migrate`, add a **separate daily Heroku Scheduler task** at the desired time:

```sh
bundle exec rake footlight:monitoring_digest
```

This task does not call or modify the existing website scheduler. `MonitoringDigestJob` is available if an existing background scheduler is preferred. Concurrent digest invocations are serialized with a database lock. Failed email delivery raises and does not mark the day sent, allowing a retry. As with ordinary SMTP delivery, an ambiguous transport failure after acceptance or a process crash between acceptance and database commit can produce a duplicate on retry; exactly-once delivery would require a provider with idempotency support.

No provider credentials, actual mailbox, deployed scheduler entry, or source algorithms are provisioned by this code change. No test emails are sent to external recipients.
