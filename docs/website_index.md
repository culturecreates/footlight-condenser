# Website overview

The overview uses eight columns and the full available browser width. Rows keep
names, counts, mode, 24-hour statement activity and last refresh on one line;
smaller viewports can scroll the table horizontally. Sources are directly
accessible. Details opens a separate inline row for identity, schedule, graph,
page breakdown, cache, export and settings links. No per-website transition
readiness calculation or remote fetch is performed to build the overview.

## Lists

`Distillator::WebsiteIndexGroups` assigns each website exactly once, in priority
order. These are display categories, independent of Legacy/Shadow/Active modes:

1. **Templates:** the six production template seedurls, names marked Template,
   and the explicitly requested `footlight-manual-fr` manual-entry site.
2. **Test sites:** names or seedurl tokens marked Test, Testing or Testwebsite.
   Real names such as Contest Theatre are not matched by substring alone.
3. **Places / Artists / People:** dedicated feed suffixes/names and the known
   production entity feeds. This includes `signelaval-com` (retained for its
   people/place/organization data), `signelaval-com-place`,
   `spec-qc-ca-people` and `nowplayingtoronto-com-places`. Place des arts remains
   an event venue rather than being classified by the word Place in its name.
4. **Scheduled sites:** other websites with a positive `schedule_every_days`.
5. **Unscheduled:** other websites with a missing, zero or negative interval.

Scheduled sites are the default visible list. Other lists are native, closed
details panels. Filtering reveals nonempty matching categories automatically;
sorting links preserve a category anchor so it reopens after navigation.
Explicitly opening a category and its per-site Details works with keyboard input.
Without JavaScript, category panels still work and per-site Details links open
the website page instead.

Categories are derived from the current records on every request. Changing an
ordinary site's interval to zero or clearing it moves it to Unscheduled; giving
it a positive interval moves it back. Templates, tests and entity feeds remain in
their own categories regardless of interval. No rows are deleted or copied and
no schedules, rollout modes or production/staging configuration are changed.
No migration is needed for grouping. The production inventory supplied on November 13, 2026
informs the explicit role exceptions, not a whitelist of allowed scheduled sites.

## Preferred list

Each row has a Preferred checkbox. Its boolean is stored on the website, shared
with other operators of this Condenser instance. The Preferred view is an
independent working list: it includes any marked site, including unscheduled,
entity, template and test sites, without changing the site's display category.
Search, filters and sorting still apply. Empty lists explain how to add sites.

Use Preferred as default stores only an allowlisted view name in a signed,
HttpOnly browser cookie. There is no individual-user model in Condenser's shared
HTTP Basic sign-in. The default can be unchecked; the All sites link explicitly
overrides it for navigation. JSON API requests do not inherit the browser default.

Checkbox changes submit their own CSRF-protected PATCH forms; without JavaScript
the forms expose Save buttons. The row update writes only the preferred column,
avoiding rollout, scheduling and monitorable callbacks. Filtered return paths stay
local. Default-view updates accept only All or Preferred, never redirect URLs.

This addition requires migration `20261113000200_add_preferred_to_websites.rb`.
Existing sites start unchecked. The list grouping above itself needs no migration.
After deploying to staging, run:

```sh
heroku run rails db:migrate --app footlight-condenser-test
```

## Filters and counters

There is one search/mode/cohort form. Search matches name or seedurl. Language,
graph and seedurl filters, plus less common sorting keys, are available
under More filters and sorting; active advanced filters stay open. Mode chips
keep the other filters and sort direction. Cohort and mode filters compose
before the result is grouped. Empty searches retain reset and sorting controls.

All resource types count toward Pages and Publishable. Publishable is not a
count of upcoming events. The detailed breakdown retains its scoped links.
Summary statement totals are explicitly global; mode counts remain global too.
The scheduling and staging rollout policies are unchanged.
